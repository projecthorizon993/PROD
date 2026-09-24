import Foundation
import CoreImage
import CoreML
import Vision
import Metal
final class ZoomSharpnessEngine {
    enum SharpnessPreset: String { case auto, psnr, perceptual, natural, balanced }
    var sharpness: Float = 0.5
    var preset: SharpnessPreset = .balanced
    var superResEnabled = true
    var maxOpticalZoom: CGFloat = 6.0
    private let context: CIContext
    private let device: MTLDevice?
    private var srModel: MLModel?
    private var srVisionModel: VNCoreMLModel?
    private let srQueue = DispatchQueue(label: "zoom.sr.queue", qos: .userInitiated)
    private let unsharp = CIFilter(name: "CIUnsharpMask")!
    private let sharpenLum = CIFilter(name: "CISharpenLuminance")!
    init?(device: MTLDevice?) {
        self.device = device ?? MTLCreateSystemDefaultDevice()
        guard let d = self.device else { return nil }
        context = CIContext(mtlDevice: d, options: [.cacheIntermediates: false])
        loadSRModel()
    }
    private func loadSRModel() {
        let candidates = ["RealESRGAN_Tiny","SwinIR_Light","ESRGAN","LiteSR","BSRGAN","ZoomSR"]
        if let (ml, vn) = ANEOptimizer.loadModel(named: candidates, bundle: .main, device: device) {
            srModel = ml; srVisionModel = vn
            ANEOptimizer.warmup(model: ml, shape: [1,3,512,512], queue: srQueue)
        }
    }
    func process(ciImage: CIImage, zoomFactor: CGFloat, isDigital: Bool) -> CIImage {
        var out = ciImage
        let cfg = sharpnessConfig(for: zoomFactor)
        sharpenLum.setValue(out, forKey: kCIInputImageKey)
        sharpenLum.setValue(cfg.lumSharpness, forKey: kCIInputSharpnessKey)
        sharpenLum.setValue(cfg.lumRadius, forKey: kCIInputRadiusKey)
        if let sl = sharpenLum.outputImage { out = sl }
        unsharp.setValue(out, forKey: kCIInputImageKey)
        unsharp.setValue(cfg.unsharpRadius, forKey: kCIInputRadiusKey)
        unsharp.setValue(cfg.unsharpIntensity, forKey: kCIInputIntensityKey)
        if let r = unsharp.outputImage { out = r }
        return out
    }
    func enhanceStill(image: CIImage, zoomFactor: CGFloat, completion: @escaping (CIImage)->Void) {
        let isDigital = zoomFactor > maxOpticalZoom * 0.85
        if isDigital && superResEnabled, let vModel = srVisionModel {
            srQueue.async {
                ANEOptimizer.sharedToken.withToken {
                    let req = VNCoreMLRequest(model: vModel) { req, _ in
                        guard let obs = req.results?.first as? VNPixelBufferObservation, let buf = obs.pixelBuffer else {
                            let cfg = self.sharpnessConfig(for: zoomFactor)
                            completion(self.applyStaticSharpen(image: image, cfg: cfg)); return
                        }
                        var out = CIImage(cvPixelBuffer: buf)
                        let need = zoomFactor / 2.0
                        if need > 1.05 { out = out.transformed(by: CGAffineTransform(scaleX: need, y: need)) }
                        var adj = self.sharpnessConfig(for: zoomFactor); adj.unsharpIntensity *= 0.6; adj.lumSharpness *= 0.7
                        completion(self.applyStaticSharpen(image: out, cfg: adj))
                    }
                    req.imageCropAndScaleOption = .scaleFill
                    req.usesCPUOnly = false
                    if #available(iOS 16.0, *) { req.preferBackgroundProcessing = true }
                    let handler = VNImageRequestHandler(ciImage: image, options: [:])
                    try? handler.perform([req])
                }
            }
            return
        }
        let cfg = sharpnessConfig(for: zoomFactor)
        completion(applyStaticSharpen(image: image, cfg: cfg))
    }
    private struct Cfg { var lumRadius: CGFloat; var lumSharpness: CGFloat; var unsharpRadius: CGFloat; var unsharpIntensity: CGFloat }
    private func sharpnessConfig(for zoom: CGFloat) -> Cfg {
        switch preset {
        case .psnr: return Cfg(lumRadius: 1.0, lumSharpness: 0.45 * CGFloat(sharpness), unsharpRadius: 1.0, unsharpIntensity: 0.5 * CGFloat(sharpness))
        case .perceptual: return Cfg(lumRadius: 1.4, lumSharpness: 0.65 * CGFloat(sharpness), unsharpRadius: 1.6, unsharpIntensity: 0.72 * CGFloat(sharpness))
        case .natural: return Cfg(lumRadius: 0.8, lumSharpness: 0.30 * CGFloat(sharpness), unsharpRadius: 0.9, unsharpIntensity: 0.35 * CGFloat(sharpness))
        default:
            let r = 0.9 + 0.25 * Double(max(0, zoom-1))
            let i = 0.50 + 0.08 * Double(max(0, zoom-1))
            return Cfg(lumRadius: CGFloat(r), lumSharpness: CGFloat(i*0.6)*CGFloat(sharpness), unsharpRadius: CGFloat(r), unsharpIntensity: CGFloat(i)*CGFloat(sharpness))
        }
    }
    private func applyStaticSharpen(image: CIImage, cfg: Cfg) -> CIImage {
        sharpenLum.setValue(image, forKey: kCIInputImageKey)
        sharpenLum.setValue(cfg.lumSharpness, forKey: kCIInputSharpnessKey)
        sharpenLum.setValue(cfg.lumRadius, forKey: kCIInputRadiusKey)
        var out = sharpenLum.outputImage ?? image
        unsharp.setValue(out, forKey: kCIInputImageKey)
        unsharp.setValue(cfg.unsharpRadius, forKey: kCIInputRadiusKey)
        unsharp.setValue(cfg.unsharpIntensity, forKey: kCIInputIntensityKey)
        if let r = unsharp.outputImage { out = r }
        return out
    }
}
