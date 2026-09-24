import Foundation
import CoreML
import Vision
import Metal
import CoreVideo
import os

enum ANEOptimizer {
    static let log = OSLog(subsystem: "com.procamer.ane", category: "ANE")
    static func loadModel(named candidates: [String], bundle: Bundle = .main, device: MTLDevice?) -> (MLModel, VNCoreMLModel)? {
        for name in candidates {
            guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else { continue }
            do {
                let cfg = MLModelConfiguration()
                cfg.computeUnits = .cpuAndNeuralEngine
                if #available(iOS 16.0, *) { cfg.allowLowPrecisionAccumulationOnGPU = true }
                if #available(iOS 17.0, *), let d = device { cfg.preferredMetalDevice = d }
                let ml = try MLModel(contentsOf: url, configuration: cfg)
                let vn = try VNCoreMLModel(for: ml)
                os_log("ANE model %{public}@ loaded (%{public}@). Inputs: %{public}@", log: log, type: .info, name, url.lastPathComponent, String(describing: ml.modelDescription.inputDescriptionsByName.keys))
                return (ml, vn)
            } catch {
                os_log("ANE load %{public}@ failed: %{public}@", log: log, type: .error, name, String(describing: error))
            }
        }
        return nil
    }
    static func warmup(model: MLModel, shape: [Int] = [1,3,512,512], queue: DispatchQueue) {
        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let w = 512, h = 512
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, [kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pb)
            guard let pix = pb else { return }
            if let vn = try? VNCoreMLModel(for: model) {
                let req = VNCoreMLRequest(model: vn)
                req.imageCropAndScaleOption = .scaleFill
                req.usesCPUOnly = false
                if #available(iOS 16.0, *) { req.preferBackgroundProcessing = true }
                let handler = VNImageRequestHandler(cvPixelBuffer: pix, options: [:])
                try? handler.perform([req])
            }
            let dt = CFAbsoluteTimeGetCurrent() - start
            os_log("ANE warmup done in %.1f ms", log: log, type: .info, dt*1000)
        }
    }
    final class PixelPool {
        let width: Int
        let height: Int
        let format: OSType
        private var pool: CVPixelBufferPool?
        init?(width: Int, height: Int, format: OSType = kCVPixelFormatType_32BGRA) {
            let alignedW = (width + 15) & ~15
            let alignedH = (height + 15) & ~15
            self.width = alignedW; self.height = alignedH; self.format = format
            let attrs: [String:Any] = [kCVPixelBufferPixelFormatTypeKey as String: format, kCVPixelBufferWidthKey as String: alignedW, kCVPixelBufferHeightKey as String: alignedH, kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:], kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
            if pool == nil { return nil }
        }
        func make() -> CVPixelBuffer? { var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool!, &pb); return pb }
        func render(ci: CIImage, context: CIContext) -> CVPixelBuffer? { guard let pb = make() else { return nil }; context.render(ci, to: pb); return pb }
    }
    final class ANEToken {
        private let sem = DispatchSemaphore(value: 1)
        func withToken<T>(_ body: () throws -> T) rethrows -> T { sem.wait(); defer { sem.signal() }; return try body() }
        func tryWithToken<T>(_ body: () throws -> T) rethrows -> T? { guard sem.wait(timeout: .now()) == .success else { return nil }; defer { sem.signal() }; return try body() }
    }
    static let sharedToken = ANEToken()
    static func shouldThrottleANE() -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        if state == .critical { os_log("ANE throttle: thermal critical, skip preview ANE", log: log, type: .fault); return true }
        if state == .serious { return true }
        return false
    }
    static func predictDirect(model: MLModel, pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first else { return nil }
        do {
            let fv = try MLFeatureValue(pixelBuffer: pixelBuffer)
            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: fv])
            let out = try model.prediction(from: provider)
            if let outPB = out.featureValue(for: out.featureNames.first!)?.imageBufferValue { return outPB }
        } catch { os_log("ANE direct predict failed: %{public}@", log: log, type: .error, String(describing: error)) }
        return nil
    }
}
private extension MLMultiArray { func asCVPixelBufferHack() -> CVPixelBuffer? { return nil } }
