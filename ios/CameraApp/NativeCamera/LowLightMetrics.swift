import CoreImage
import UIKit
final class LowLightMetrics {
    static let shared = LowLightMetrics()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    struct Report: Codable {
        var psnr: Float?
        var ssim: Float?
        var mse: Float?
        var mae: Float?
        var loe: Float
        var niqeProxy: Float
        var lightnessStd: Float
    }
    func psnr(output: CIImage, reference: CIImage) -> Float {
        guard let outCG = ciContext.createCGImage(output, from: output.extent),
              let refCG = ciContext.createCGImage(reference, from: reference.extent) else { return 0 }
        let mse = self.mse(img1: outCG, img2: refCG)
        if mse == 0 { return 100 }
        return 10 * log10(255*255 / mse)
    }
    private func mse(img1: CGImage, img2: CGImage) -> Float {
        let w = img1.width, h = img1.height
        let bytesPerRow = w * 4
        var buf1 = [UInt8](repeating: 0, count: h*bytesPerRow)
        var buf2 = [UInt8](repeating: 0, count: h*bytesPerRow)
        let cs = CGColorSpaceCreateDeviceRGB()
        buf1.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img1, in: CGRect(x:0,y:0,width:w,height:h))
        }
        buf2.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img2, in: CGRect(x:0,y:0,width:w,height:h))
        }
        var sum: Float = 0
        var n: Int = 0
        for y in 0..<h { for x in 0..<w { let off = y*bytesPerRow + x*4; for c in 0..<3 { let d = Float(Int(buf1[off+c]) - Int(buf2[off+c])); sum += d*d; n += 1 }; if n > 200_000 { break } }; if n > 200_000 { break } }
        return n>0 ? sum / Float(n) : 0
    }
    func ssim(output: CIImage, reference: CIImage, context: CIContext? = nil) -> Float {
        let ctx = context ?? ciContext
        let extent = output.extent.intersection(reference.extent)
        guard !extent.isEmpty else { return 0 }
        let lumaOut = output.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0]).cropped(to: extent)
        let lumaRef = reference.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0]).cropped(to: extent)
        let maeProxy: Float = abs(estimateMean(lumaOut, ctx: ctx) - estimateMean(lumaRef, ctx: ctx))
        return max(0, 1 - maeProxy*1.8)
    }
    private func estimateMean(_ ci: CIImage, ctx: CIContext) -> Float {
        let sm = ci.transformed(by: CGAffineTransform(scaleX: 0.02, y: 0.02))
        let f = CIFilter(name: "CIAreaAverage")!
        f.setValue(sm, forKey: kCIInputImageKey)
        f.setValue(CIVector(cgRect: sm.extent), forKey: kCIInputExtentKey)
        guard let out = f.outputImage else { return 0.5 }
        var bmp=[UInt8](repeating:0,count:4)
        ctx.render(out,toBitmap:&bmp,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
        return Float(bmp[0])/255.0
    }
    func loeProxy(input: CIImage, enhanced: CIImage, context: CIContext) -> Float {
        let size: CGFloat = 32
        func downsampleMax(_ ci: CIImage) -> [UInt8] {
            let scaled = ci.transformed(by: CGAffineTransform(scaleX: size/ci.extent.width, y: size/ci.extent.height)).cropped(to: CGRect(x:0,y:0,width:size,height:size))
            let luma = scaled.applyingFilter("CIMaximumComponent", parameters: [:])
            guard let cg = context.createCGImage(luma, from: luma.extent) else { return [UInt8](repeating:128,count:Int(size*size)) }
            var buf=[UInt8](repeating:0,count:Int(size*size*4))
            let cs = CGColorSpaceCreateDeviceRGB()
            buf.withUnsafeMutableBytes { ptr in
                let c = CGContext(data: ptr.baseAddress,width:Int(size),height:Int(size),bitsPerComponent:8,bytesPerRow:Int(size*4),space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.draw(cg,in:CGRect(x:0,y:0,width:size,height:size))
            }
            return stride(from:0,to:buf.count,by:4).map{buf[$0]}
        }
        let a = downsampleMax(input)
        let b = downsampleMax(enhanced)
        var err: Int = 0
        for i in 0..<a.count { for j in (i+1)..<a.count { let o1 = a[i] > a[j]; let o2 = b[i] > b[j]; if o1 != o2 { err += 1 } } }
        return Float(err) / Float(a.count * (a.count-1)/2) * 600
    }
    func niqeProxy(image: CIImage, context: CIContext) -> Float {
        let extent = image.extent
        let center = CGRect(x: extent.midX-64, y: extent.midY-64, width:128, height:128)
        guard let cg = context.createCGImage(image, from: center) else { return 5 }
        var buf=[UInt8](repeating:0,count:128*128*4)
        let cs = CGColorSpaceCreateDeviceRGB()
        buf.withUnsafeMutableBytes{ ptr in
            let c = CGContext(data: ptr.baseAddress,width:128,height:128,bitsPerComponent:8,bytesPerRow:128*4,space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(cg,in:CGRect(x:0,y:0,width:128,height:128))
        }
        var mean: Float = 0; for i in stride(from:0,to:buf.count,by:4){ mean += Float(buf[i]) }; mean/=Float(128*128)
        var varr: Float = 0; for i in stride(from:0,to:buf.count,by:4){ let d=Float(buf[i])-mean; varr+=d*d }; varr/=Float(128*128)
        let v = min(2500, max(0, varr))
        return Float(7.5 - (v/600.0))
    }
    func report(output: CIImage, reference: CIImage?, input: CIImage, context: CIContext) -> Report {
        let loe = loeProxy(input: input, enhanced: output, context: context)
        let niqe = niqeProxy(image: output, context: context)
        if let ref = reference {
            let ps = psnr(output: output, reference: ref)
            let ss = ssim(output: output, reference: ref, context: context)
            return Report(psnr: ps, ssim: ss, mse: nil, mae: nil, loe: loe, niqeProxy: niqe, lightnessStd: 0)
        }
        return Report(psnr: nil, ssim: nil, mse: nil, mae: nil, loe: loe, niqeProxy: niqe, lightnessStd: 0)
    }
}
