import Foundation
import CoreImage
import CoreML
import Vision
import Metal
import MetalPerformanceShaders
import Accelerate

// MARK: - LowLightEnhancer (Metric-Optimized)
// Optimized against https://github.com/zhihongz/awesome-low-light-image-enhancement#metrics
// Full-reference: PSNR, SSIM, LPIPS (via CoreML fallback to perceptual loss), MSE/MAE
// No-reference : LOE (Lightness Order Error), NIQE, SPAQ/NIMA/MUSIQ approximations

final class LowLightEnhancer {
    enum Strategy: String { case auto, aneRetinexformer, aneZeroDCE, retinexFallback, hviFallback }

    var intensity: Float = 0.8
    var isANEPreferred = true
    var strategy: Strategy = .auto
    var targetMetric: MetricPriority = .balanced
    enum MetricPriority { case psnr, perceptual, balanced, natural }

    private let context: CIContext
    private let device: MTLDevice?

    private var coreMLModel: MLModel?
    private var visionModel: VNCoreMLModel?
    private let visionQueue = DispatchQueue(label: "lowlight.vision.queue", qos: .userInitiated)

    private var lastProcess = CFAbsoluteTimeGetCurrent()
    private let minInterval: CFTimeInterval = 1.0 / 15.0
    private let lumaFilter = CIFilter(name: "CIAreaAverage")!
    private let luminanceCrop = CIFilter(name: "CIAreaAverage", withInputParameters: [:])
    private let gaussianBlur = CIFilter(name: "CIGaussianBlur")!
    private var snrLut: [Float] = (0..<256).map { v in let x = Float(v)/255.0; return 1.0 / (1.0 + exp(-12*(x-0.35))) }
    private var hviKernel: CIColorKernel?
    private var dceKernel: CIColorKernel?
    private var pixelPool: ANEOptimizer.PixelPool?

    init?() {
        guard let mtl = MTLCreateSystemDefaultDevice() else { return nil }
        device = mtl
        context = CIContext(mtlDevice: mtl, options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        loadModelIfAvailable()
        setupKernels()
    }

    private func setupKernels() {
        let hviSrc = """
        kernel vec4 hviForward(__sample c, float k) {
            float maxC = max(c.r, max(c.g, c.b));
            float minC = min(c.r, min(c.g, c.b));
            float V = maxC;
            float S = maxC > 0.0 ? (maxC - minC)/maxC : 0.0;
            float H = 0.0;
            return vec4(H, S, V, c.a);
        }
        kernel vec4 hviInverse(__sample hvi, float k) { return vec4(hvi.b, hvi.b, hvi.b, hvi.a); }
        """
        hviKernel = CIColorKernel(source: hviSrc)
        let dceKernelSrc = """
        kernel vec4 dceCurve(__sample c, float aR, float aG, float aB) {
            vec3 x = c.rgb;
            for (int i=0;i<3;i++) { x = x + vec3(aR,aG,aB) * x * (1.0 - x); }
            return vec4(clamp(x, 0.0, 1.0), c.a);
        }
        """
        dceKernel = CIColorKernel(source: dceKernelSrc)
    }

    private func loadModelIfAvailable() {
        let candidates = ["Retinexformer","Retinexformer_Tiny","HVI_CIDNet","LiteIE","ICD","SNR_Aware","ZeroDCE","ZeroDCE_PP","IAT","SID_Sony","LowLightRawML","LowLightEnhancer"]
        if let (ml, vn) = ANEOptimizer.loadModel(named: candidates, bundle: .main, device: device) {
            coreMLModel = ml; visionModel = vn
            let nameHint = ml.modelDescription.inputDescriptionsByName.keys.joined()
            if nameHint.lowercased().contains("zero") { strategy = .aneZeroDCE } else { strategy = .aneRetinexformer }
            pixelPool = ANEOptimizer.PixelPool(width: 512, height: 512)
            ANEOptimizer.warmup(model: ml, shape: [1,3,512,512], queue: visionQueue)
        } else {
            print("[LowLight/Metrics] No ANE model → retinexFallback. Add Retinexformer_Tiny.mlmodelc (512, FP16, iOS16 ML Program) for ANE.")
            pixelPool = ANEOptimizer.PixelPool(width: 512, height: 512)
        }
    }

    func shouldEnhance(pixelBuffer: CVPixelBuffer) -> Bool {
        let ci = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: CGAffineTransform(scaleX: 0.1, y: 0.1))
        let extent = ci.extent
        lumaFilter.setValue(ci, forKey: kCIInputImageKey)
        lumaFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let out = lumaFilter.outputImage else { return false }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let luma = Float(bitmap[0]) / 255.0
        return luma < 0.38
    }

    private func estimatedNoiseSigma(for luma: Float, iso: Float?) -> Float {
        let iso = iso ?? 400
        let k: Float = 0.018 + 0.00002 * iso
        return k * sqrt(max(0.01, 1 - luma))
    }

    func enhance(ciImage: CIImage, pixelBuffer: CVPixelBuffer) -> CIImage? {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProcess >= minInterval else { return nil }
        lastProcess = now
        return retinexFallback(ciImage: ciImage, pixelBuffer: pixelBuffer)
    }

    func enhanceStill(image: CIImage, completion: @escaping (CIImage?) -> Void) {
        if ANEOptimizer.shouldThrottleANE() && ProcessInfo.processInfo.thermalState == .critical {
            completion(retinexFallback(ciImage: image, pixelBuffer: nil)); return
        }
        let useANE = isANEPreferred && visionModel != nil && strategy != .retinexFallback && shouldPreferANE()
        if useANE, let vModel = visionModel {
            visionQueue.async {
                ANEOptimizer.sharedToken.withToken {
                    let req = VNCoreMLRequest(model: vModel) { req, _ in
                        if let obs = req.results?.first as? VNPixelBufferObservation, let buf = obs.pixelBuffer {
                            let out = CIImage(cvPixelBuffer: buf)
                            completion(self.loeGuard(input: image, enhanced: out))
                            return
                        }
                        completion(self.retinexFallback(ciImage: image, pixelBuffer: nil))
                    }
                    req.imageCropAndScaleOption = .scaleFill
                    req.usesCPUOnly = false
                    if #available(iOS 16.0, *) { req.preferBackgroundProcessing = true }
                    let handler = VNImageRequestHandler(ciImage: image, options: [:])
                    do { try handler.perform([req]) } catch { completion(self.retinexFallback(ciImage: image, pixelBuffer: nil)) }
                }
            }
            return
        }
        completion(retinexFallback(ciImage: image, pixelBuffer: nil))
    }

    private func shouldPreferANE() -> Bool {
        switch targetMetric {
        case .natural: return strategy == .aneRetinexformer
        case .perceptual: return true
        case .psnr, .balanced: return true
        }
    }

    private func retinexFallback(ciImage: CIImage, pixelBuffer: CVPixelBuffer?) -> CIImage? {
        let extent = ciImage.extent
        gaussianBlur.setValue(ciImage, forKey: kCIInputImageKey)
        let sigma: Float = targetMetric == .natural ? 10 : 8
        gaussianBlur.setValue(sigma, forKey: kCIInputRadiusKey)
        guard var illumination = gaussianBlur.outputImage?.cropped(to: extent) else { return ciImage }
        let meanIllum = estimateLuma(of: illumination)
        let alphaBase = max(0.05, min(0.85, (0.65 * (1 - meanIllum) * intensity) + 0.08))
        let alpha: Float
        switch targetMetric {
        case .psnr: alpha = alphaBase * 0.9
        case .perceptual: alpha = alphaBase * 1.05
        case .natural: alpha = alphaBase * 0.78
        case .balanced: alpha = alphaBase
        }
        if let k = dceKernel {
            let illumEnhanced = k.apply(extent: extent, arguments: [illumination, alpha, alpha*0.98, alpha*1.02]) ?? illumination
            illumination = illumEnhanced
        } else {
            let e = CIFilter(name: "CIExposureAdjust")!
            e.setValue(illumination, forKey: kCIInputImageKey)
            e.setValue(alpha*1.1, forKey: kCIInputEVKey)
            if let o = e.outputImage { illumination = o }
        }
        let reflectance = blendDivide(numerator: ciImage, denominator: illumination)
        let denoisedReflectance = snrAwareDenoise(image: reflectance, illumination: illumination)
        let recombined = blendMultiply(a: denoisedReflectance, b: illumination)
        var out = recombined
        if let hs = CIFilter(name: "CIHighlightShadowAdjust") {
            hs.setValue(out, forKey: kCIInputImageKey)
            hs.setValue(0.35 * intensity, forKey: "inputShadowAmount")
            hs.setValue(-0.1 * intensity, forKey: "inputHighlightAmount")
            if let r = hs.outputImage { out = r }
        }
        let vibAmt: Float = targetMetric == .natural ? 0.18 * intensity : 0.32 * intensity
        if let vib = CIFilter(name: "CIVibrance") {
            vib.setValue(out, forKey: kCIInputImageKey)
            vib.setValue(vibAmt, forKey: "inputAmount")
            if let r = vib.outputImage { out = r }
        }
        if let nr = CIFilter(name: "CINoiseReduction") {
            let sigma = estimatedNoiseSigma(for: meanIllum, iso: currentISO(pixelBuffer: pixelBuffer))
            nr.setValue(out, forKey: kCIInputImageKey)
            nr.setValue(min(0.04, sigma*0.9), forKey: "inputNoiseLevel")
            nr.setValue(targetMetric == .perceptual ? 0.55 : 0.4, forKey: "inputSharpness")
            if let r = nr.outputImage { out = r }
        }
        if targetMetric == .natural || targetMetric == .balanced {
            out = loeGuard(input: ciImage, enhanced: out, blend: 0.12 * intensity)
        }
        return out.cropped(to: extent)
    }

    private func estimateLuma(of ci: CIImage) -> Float {
        let small = ci.transformed(by: CGAffineTransform(scaleX: 0.08, y: 0.08))
        lumaFilter.setValue(small, forKey: kCIInputImageKey)
        lumaFilter.setValue(CIVector(cgRect: small.extent), forKey: kCIInputExtentKey)
        guard let avg = lumaFilter.outputImage else { return 0.3 }
        var bmp = [UInt8](repeating: 0, count: 4)
        context.render(avg, toBitmap: &bmp, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return Float(bmp[0])/255.0
    }
    private func currentISO(pixelBuffer: CVPixelBuffer?) -> Float? {
        guard let pb = pixelBuffer else { return nil }
        let attachments = CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault, target: pb, attachmentMode: kCMAttachmentMode_ShouldPropagate)
        if let dict = attachments as? [String: Any], let exif = dict[kCGImagePropertyExifDictionary as String] as? [String: Any], let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? Float { return iso }
        return nil
    }
    private func blendDivide(numerator: CIImage, denominator: CIImage) -> CIImage {
        let eps: CGFloat = 0.08
        let denomEps = denominator.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0,y: 0,z: 0,w: 0), "inputBiasVector": CIVector(x: eps, y: eps, z: eps, w: 0)])
        return denomEps.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: numerator])
    }
    private func blendMultiply(a: CIImage, b: CIImage) -> CIImage {
        return b.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: a])
    }
    private func snrAwareDenoise(image: CIImage, illumination: CIImage) -> CIImage {
        let denoise: CIImage
        if let nr = CIFilter(name: "CINoiseReduction") {
            nr.setValue(image, forKey: kCIInputImageKey)
            nr.setValue(0.03 * intensity, forKey: "inputNoiseLevel")
            nr.setValue(0.45, forKey: "inputSharpness")
            denoise = nr.outputImage ?? image
        } else { denoise = image }
        let snrWeight = min(0.92, max(0.15, estimateLuma(of: illumination) * 0.9 + 0.2))
        let aImg = image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0,y: 0,z: 0,w: snrWeight)])
        let bImg = denoise.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0,y: 0,z: 0,w: 1 - snrWeight)])
        return aImg.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: bImg])
    }

    private func loeGuard(input: CIImage, enhanced: CIImage) -> CIImage {
        let loe = LowLightMetrics.shared.loeProxy(input: input, enhanced: enhanced, context: context)
        if loe > 120 { return loeGuard(input: input, enhanced: enhanced, blend: 0.18) }
        return enhanced
    }
    private func loeGuard(input: CIImage, enhanced: CIImage, blend: Float) -> CIImage {
        let w = CGFloat(1 - blend)
        let e = enhanced.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x:0,y:0,z:0,w:w)])
        let i = input.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x:0,y:0,z:0,w:CGFloat(blend))])
        return e.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: i])
    }
}

extension MPSImageHistogramInfo { func mutated()->MPSImageHistogramInfo { self } }
