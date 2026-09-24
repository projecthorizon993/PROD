import CoreImage
import UIKit

enum CameraFilter: String, CaseIterable, Identifiable {
    case none = "None"
    case vivid = "Vivid"
    case vividWarm = "Vivid Warm"
    case mono = "Mono"
    case noir = "Noir"
    case silvertone = "Silver"
    case chrome = "Chrome"
    case fade = "Fade"
    case instant = "Instant"
    case process = "Process"
    case transfer = "Transfer"
    case tonal = "Tonal"
    case cinematic = "Cinematic"
    case tealOrange = "Teal & Orange"
    case nightVision = "Night Boost"
    var id: String { rawValue }
}

final class FilterPipeline {
    var currentFilter: CameraFilter = .none
    var intensity: Float = 1.0
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var filters: [CameraFilter: CIFilter] = [:]
    init() {
        filters[.mono] = CIFilter(name: "CIPhotoEffectMono")
        filters[.noir] = CIFilter(name: "CIPhotoEffectNoir")
        filters[.chrome] = CIFilter(name: "CIPhotoEffectChrome")
        filters[.fade] = CIFilter(name: "CIPhotoEffectFade")
        filters[.instant] = CIFilter(name: "CIPhotoEffectInstant")
        filters[.process] = CIFilter(name: "CIPhotoEffectProcess")
        filters[.transfer] = CIFilter(name: "CIPhotoEffectTransfer")
        filters[.tonal] = CIFilter(name: "CIPhotoEffectTonal")
    }
    func apply(to image: CIImage) -> CIImage {
        guard currentFilter != .none else { return image }
        switch currentFilter {
        case .none: return image
        case .vivid:
            let f = CIFilter(name: "CIColorControls")!
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.15, forKey: kCIInputSaturationKey)
            f.setValue(1.05, forKey: kCIInputContrastKey)
            return f.outputImage ?? image
        case .vividWarm:
            let warm = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 800, y: 0), "inputTargetNeutral": CIVector(x: 0, y: 0)])
            let f = CIFilter(name: "CIColorControls")!
            f.setValue(warm, forKey: kCIInputImageKey)
            f.setValue(1.2, forKey: kCIInputSaturationKey)
            return f.outputImage ?? warm
        case .cinematic:
            var out = image
            out = out.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.9, kCIInputContrastKey: 1.1])
            out = out.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 0, y: 0), "inputTargetNeutral": CIVector(x: -300, y: 10)])
            return out
        case .tealOrange:
            let m = CIFilter(name: "CIColorMatrix")!
            m.setValue(image, forKey: kCIInputImageKey)
            m.setValue(CIVector(x: 1.1, y: 0.05, z: 0, w: 0), forKey: "inputRVector")
            m.setValue(CIVector(x: 0, y: 0.95, z: 0.05, w: 0), forKey: "inputGVector")
            m.setValue(CIVector(x: 0, y: 0.1, z: 1.15, w: 0), forKey: "inputBVector")
            return m.outputImage ?? image
        case .nightVision:
            let e = CIFilter(name: "CIExposureAdjust")!
            e.setValue(image, forKey: kCIInputImageKey)
            e.setValue(0.5, forKey: kCIInputEVKey)
            return e.outputImage ?? image
        default:
            if let f = filters[currentFilter] {
                f.setValue(image, forKey: kCIInputImageKey)
                return f.outputImage ?? image
            }
            return image
        }
    }
    func applyToStill(_ uiImage: UIImage) -> UIImage {
        guard currentFilter != .none, let ci = CIImage(image: uiImage) else { return uiImage }
        let out = apply(to: ci)
        guard let cg = context.createCGImage(out, from: out.extent) else { return uiImage }
        return UIImage(cgImage: cg, scale: uiImage.scale, orientation: uiImage.imageOrientation)
    }
}
