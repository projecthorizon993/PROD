import Foundation
import AVFoundation
import CoreImage
import Vision
import Metal
import CoreVideo
import CoreMedia
import ImageIO

final class BracketEngine {
    enum AlignMode: String { case auto, tripod, handheld }
    var count: Int = 5
    var targetISO: Float = 6400
    var evStep: Float = 0
    var alignMode: AlignMode = .auto
    var useANEAlign: Bool = true
    private let ciContext: CIContext
    private let alignQueue = DispatchQueue(label: "bracket.align", qos: .userInitiated)
    init?(device: MTLDevice?) {
        guard let d = device ?? MTLCreateSystemDefaultDevice() else { return nil }
        ciContext = CIContext(mtlDevice: d, options: [.cacheIntermediates: false])
    }
    func bracketSettings(for device: AVCaptureDevice, baseISO: Float, baseDuration: CMTime) -> AVCapturePhotoBracketSettings? {
        let maxISO = device.activeFormat.maxISO
        let hwISO = min(baseISO, maxISO)
        let actualCount = max(3, min(7, count))
        var settings: [AVCaptureBracketedStillImageSettings] = []
        for _ in 0..<actualCount {
            let s = AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(exposureDuration: baseDuration, iso: hwISO) as AVCaptureBracketedStillImageSettings
            settings.append(s)
        }
        guard let bracket = try? AVCapturePhotoBracketSettings(rawPixelFormatType: OSType(0), processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc], bracketedSettings: settings) else { return nil }
        bracket.isHighResolutionPhotoEnabled = true
        return bracket
    }
    func fuse(images: [CIImage], completion: @escaping (CIImage?) -> Void) {
        guard !images.isEmpty else { completion(nil); return }
        if images.count == 1 { completion(images[0]); return }
        let needAlign: Bool = {
            switch alignMode {
            case .tripod: return false
            case .handheld: return true
            case .auto: return estimateMotion(images: images) > 0.015
            }
        }()
        if needAlign && useANEAlign {
            align(images: images, completion: { aligned in self.meanFuse(images: aligned ?? images, completion: completion) })
        } else { meanFuse(images: images, completion: completion) }
    }
    private func estimateMotion(images: [CIImage]) -> Float {
        guard images.count >= 2 else { return 0 }
        let a = luma32(images[0]), b = luma32(images[1])
        var sum: Float = 0
        for i in 0..<a.count { sum += abs(Float(a[i]) - Float(b[i])) / 255 }
        return sum / Float(a.count)
    }
    private func luma32(_ ci: CIImage) -> [UInt8] {
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 32/ci.extent.width, y: 32/ci.extent.height)).cropped(to: CGRect(x:0,y:0,width:32,height:32))
        let luma = scaled.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        guard let cg = ciContext.createCGImage(luma, from: luma.extent) else { return [UInt8](repeating: 128, count: 1024) }
        var buf=[UInt8](repeating:0, count:32*32*4)
        let cs = CGColorSpaceCreateDeviceRGB()
        buf.withUnsafeMutableBytes{ ptr in
            let c = CGContext(data: ptr.baseAddress, width:32, height:32, bitsPerComponent:8, bytesPerRow:32*4, space:cs, bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(cg, in:CGRect(x:0,y:0,width:32,height:32))
        }
        return stride(from:0,to:buf.count,by:4).map{ buf[$0] }
    }
    private func align(images: [CIImage], completion: @escaping ([CIImage]?) -> Void) {
        guard let cg0 = ciContext.createCGImage(images[0], from: images[0].extent) else { completion(images); return }
        var aligned: [CIImage] = [images[0]]
        let group = DispatchGroup()
        let lock = NSLock()
        for idx in 1..<images.count {
            group.enter()
            alignQueue.async {
                guard let cg = self.ciContext.createCGImage(images[idx], from: images[idx].extent) else { group.leave(); return }
                let req = VNTranslationalImageRegistrationRequest(targetedCGImage: cg0, orientation: .up)
                let handler = VNSequenceRequestHandler()
                try? handler.perform([req], on: cg, orientation: .up)
                if let obs = req.results?.first as? VNImageTranslationAlignmentObservation, obs.confidence > 0.3 {
                    let t = obs.alignmentTransform
                    let tx = t.tx * images[idx].extent.width
                    let ty = t.ty * images[idx].extent.height
                    let shifted = images[idx].transformed(by: CGAffineTransform(translationX: CGFloat(tx), y: CGFloat(ty)))
                    lock.lock(); aligned.append(shifted); lock.unlock()
                } else { lock.lock(); aligned.append(images[idx]); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: alignQueue) { completion(aligned.sorted { $0.extent.midX < $1.extent.midX }) }
        alignQueue.asyncAfter(deadline: .now()+0.25) { if aligned.count < images.count { completion(images) } }
    }
    private func meanFuse(images: [CIImage], completion: @escaping (CIImage?) -> Void) {
        guard let gammaKernel = linearKernel else {
            var mean = images[0].applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x:0,y:0,z:0,w:1.0/CGFloat(images.count))])
            for i in 1..<images.count {
                let w = images[i].applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x:0,y:0,z:0,w:1.0/CGFloat(images.count))])
                mean = mean.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: w])
            }
            completion(mean.cropped(to: images[0].extent))
            return
        }
        let extent = images[0].extent
        var mean = gammaKernel.apply(extent: extent, arguments: [images[0], Float(2.2)])?.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x:0,y:0,z:0,w:1.0/CGFloat(images.count))]) ?? images[0]
        for i in 1..<images.count {
            let lin = gammaKernel.apply(extent: extent, arguments: [images[i], Float(2.2)]) ?? images[i]
            let w = lin.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x:0,y:0,z:0,w:1.0/CGFloat(images.count))])
            mean = mean.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: w])
        }
        if let out = gammaKernel.apply(extent: extent, arguments: [mean, Float(1/2.2)]) { completion(out.cropped(to: extent)) } else { completion(mean.cropped(to: extent)) }
    }
    private var linearKernel: CIColorKernel? = {
        let src = "kernel vec4 toLinear(__sample c, float g){ vec3 x = pow(c.rgb, vec3(g)); return vec4(x,c.a); }"
        return CIColorKernel(source: src)
    }()
    var snrGainDB: Float { 10 * log10(Float(count)) }
    var effectiveISO: Float { targetISO / sqrt(Float(count)) }
}
