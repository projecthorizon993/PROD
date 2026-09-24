import Foundation
import CoreImage
import UIKit
import Metal

final class ColorGradingEngine {
    struct GradingParams {
        var exposure: Float = 0
        var contrast: Float = 1.0
        var saturation: Float = 1.0
        var temperature: Float = 0
        var tint: Float = 0
        var shadows: Float = 0
        var highlights: Float = 0
        var lift = SIMD3<Float>(0,0,0)
        var gamma = SIMD3<Float>(1,1,1)
        var gain = SIMD3<Float>(1,1,1)
        var lutIntensity: Float = 1.0
        var vibrance: Float = 0
        var hue: Float = 0
    }
    var params = GradingParams()
    var isEnabled = true
    private var cubeData: Data?
    private var cubeDimension: Int = 0
    private var cubeFilter: CIFilter?
    private var lutName: String?
    private let colorControls = CIFilter(name: "CIColorControls")!
    private let exposureFilter = CIFilter(name: "CIExposureAdjust")!
    private let tempTintFilter = CIFilter(name: "CITemperatureAndTint")!
    private let highlightShadow = CIFilter(name: "CIHighlightShadowAdjust")!
    private let vibranceFilter = CIFilter(name: "CIVibrance")!
    private let hueFilter = CIFilter(name: "CIHueAdjust")!
    private var lggKernel: CIColorKernel?
    private var mixKernel: CIColorKernel?
    private let context = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [.cacheIntermediates: false])
    init() {
        let lggSrc = """
        kernel vec4 lggKernel(__sample c, float liftR, float liftG, float liftB, float gammaR, float gammaG, float gammaB, float gainR, float gainG, float gainB) {
            vec3 x = c.rgb;
            x = x + vec3(liftR, liftG, liftB) * (1.0 - x);
            x = x * vec3(gainR, gainG, gainB);
            x = pow(max(x, vec3(0.0)), vec3(1.0/gammaR, 1.0/gammaG, 1.0/gammaB));
            return vec4(clamp(x,0.0,1.0), c.a);
        }
        """
        let mixSrc = "kernel vec4 mixKernel(__sample a, __sample b, float t) { return vec4(mix(a.rgb, b.rgb, t), a.a); }"
        lggKernel = CIColorKernel(source: lggSrc)
        mixKernel = CIColorKernel(source: mixSrc)
    }
    func loadLUT(named name: String, ext: String = "cube") -> Bool {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return false }
        return loadLUT(url: url)
    }
    @discardableResult
    func loadLUT(url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        guard let parsed = CubeLUTParser.parse(cubeString: text) else { return false }
        self.cubeData = parsed.data
        self.cubeDimension = parsed.size
        self.lutName = url.lastPathComponent
        self.cubeFilter = nil
        print("[ColorGrading] Loaded LUT \(url.lastPathComponent) size=\(parsed.size)")
        return true
    }
    func clearLUT() { cubeData=nil; cubeDimension=0; cubeFilter=nil; lutName=nil }
    var currentLUTName: String? { lutName }
    func availableLUTs() -> [String] {
        var out: [String]=[]
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            out += files.filter{ $0.pathExtension.lowercased()=="cube" }.map{ $0.lastPathComponent }
        }
        if let bundles = Bundle.main.urls(forResourcesWithExtension: "cube", subdirectory: nil) {
            out += bundles.map{ $0.lastPathComponent }
        }
        return Array(Set(out)).sorted()
    }
    func setLUTIntensity(_ v: Float) { params.lutIntensity = max(0,min(1,v)) }
    func setLift(_ r: Float,_ g: Float,_ b: Float) { params.lift = SIMD3(r,g,b) }
    func setGamma(_ r: Float,_ g: Float,_ b: Float) { params.gamma = SIMD3(r,g,b) }
    func setGain(_ r: Float,_ g: Float,_ b: Float) { params.gain = SIMD3(r,g,b) }
    func setVibrance(_ v: Float) { params.vibrance = max(-1,min(1,v)) }
    func setHue(_ v: Float) { params.hue = max(-0.5,min(0.5,v)) }
    func process(ciImage: CIImage) -> CIImage {
        var img = ciImage
        if params.exposure != 0 {
            exposureFilter.setValue(img, forKey: kCIInputImageKey)
            exposureFilter.setValue(params.exposure, forKey: kCIInputEVKey)
            if let out = exposureFilter.outputImage { img = out }
        }
        if params.temperature != 0 || params.tint != 0 {
            tempTintFilter.setValue(img, forKey: kCIInputImageKey)
            tempTintFilter.setValue(CIVector(x: CGFloat(params.temperature * 1200), y: 0), forKey: "inputNeutral")
            tempTintFilter.setValue(CIVector(x: 0, y: CGFloat(params.tint * 80)), forKey: "inputTargetNeutral")
            if let out = tempTintFilter.outputImage { img = out }
        }
        if params.lift != .zero || params.gamma != SIMD3<Float>(1,1,1) || params.gain != SIMD3<Float>(1,1,1),
           let k = lggKernel {
            let args: [Any] = [img, params.lift.x, params.lift.y, params.lift.z, params.gamma.x, params.gamma.y, params.gamma.z, params.gain.x, params.gain.y, params.gain.z]
            if let out = k.apply(extent: img.extent, arguments: args) { img = out }
        }
        if params.contrast != 1 || params.saturation != 1 {
            colorControls.setValue(img, forKey: kCIInputImageKey)
            colorControls.setValue(params.saturation, forKey: kCIInputSaturationKey)
            colorControls.setValue(params.contrast, forKey: kCIInputContrastKey)
            colorControls.setValue(0, forKey: kCIInputBrightnessKey)
            if let out = colorControls.outputImage { img = out }
        }
        if params.shadows != 0 || params.highlights != 0 {
            highlightShadow.setValue(img, forKey: kCIInputImageKey)
            highlightShadow.setValue(params.shadows, forKey: "inputShadowAmount")
            highlightShadow.setValue(params.highlights, forKey: "inputHighlightAmount")
            if let out = highlightShadow.outputImage { img = out }
        }
        if params.vibrance != 0 {
            vibranceFilter.setValue(img, forKey: kCIInputImageKey)
            vibranceFilter.setValue(params.vibrance * 0.7, forKey: "inputAmount")
            if let out = vibranceFilter.outputImage { img = out }
        }
        if params.hue != 0 {
            hueFilter.setValue(img, forKey: kCIInputImageKey)
            hueFilter.setValue(params.hue * 3.14159, forKey: kCIInputAngleKey)
            if let out = hueFilter.outputImage { img = out }
        }
        if let data = cubeData, cubeDimension > 0, params.lutIntensity > 0 {
            let cube = getCubeFilter()
            cube?.setValue(img, forKey: kCIInputImageKey)
            if let lutOut = cube?.outputImage {
                if params.lutIntensity >= 0.999 { img = lutOut }
                else if let mix = mixKernel, let mixed = mix.apply(extent: img.extent, arguments: [img, lutOut, params.lutIntensity]) { img = mixed }
                else { img = lutOut }
            }
        }
        return img
    }
    private func getCubeFilter() -> CIFilter? {
        if let f = cubeFilter { return f }
        guard let data = cubeData else { return nil }
        let f = CIFilter(name: "CIColorCube")!
        f.setValue(cubeDimension, forKey: "inputCubeDimension")
        f.setValue(data, forKey: "inputCubeData")
        cubeFilter = f
        return f
    }
    func exportPreset() -> Data? { try? JSONEncoder().encode(PresetExport(params: params)) }
    func importPreset(data: Data) -> Bool {
        guard let obj = try? JSONDecoder().decode(PresetExport.self, from: data) else { return false }
        let c = obj.params
        params.exposure=c.exposure; params.contrast=c.contrast; params.saturation=c.saturation
        params.temperature=c.temperature; params.tint=c.tint; params.shadows=c.shadows; params.highlights=c.highlights
        params.lutIntensity=c.lutIntensity; params.vibrance=c.vibrance; params.hue=c.hue
        params.lift=SIMD3(c.lift[0],c.lift[1],c.lift[2]); params.gamma=SIMD3(c.gamma[0],c.gamma[1],c.gamma[2]); params.gain=SIMD3(c.gain[0],c.gain[1],c.gain[2])
        return true
    }
    func exportPresetJSON() -> String? { exportPreset().flatMap{ String(data:$0, encoding:.utf8) } }
    @discardableResult
    func importPresetJSON(_ json: String) -> Bool { guard let d = json.data(using:.utf8) else { return false }; return importPreset(data: d) }
    func bakeLUT(size: Int = 33) -> Data? {
        var cubeText = "TITLE \"Baked from ProCamera \(Date())\"\nLUT_3D_SIZE \(size)\nDOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n"
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let col = CIColor(red: CGFloat(r)/CGFloat(size-1), green: CGFloat(g)/CGFloat(size-1), blue: CGFloat(b)/CGFloat(size-1))
            let ci = CIImage(color: col).cropped(to: CGRect(x:0,y:0,width:1,height:1))
            let out = process(ciImage: ci)
            var bmp:[UInt8]=[0,0,0,0]
            context.render(out, toBitmap: &bmp, rowBytes: 4, bounds: CGRect(x:0,y:0,width:1,height:1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            cubeText += String(format: "%.6f %.6f %.6f\n", Float(bmp[0])/255, Float(bmp[1])/255, Float(bmp[2])/255)
        }}}
        return cubeText.data(using:.utf8)
    }
    func saveBakedLUTToDocuments(name: String, size: Int=33) -> URL? {
        guard let data = bakeLUT(size: size), let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent(name.hasSuffix(".cube") ? name : name+".cube")
        try? data.write(to: url)
        return url
    }
    struct PresetExport: Codable { let params: GradingParamsCodable; init(params: GradingParams) { self.params = GradingParamsCodable(params) } }
    struct GradingParamsCodable: Codable {
        var exposure, contrast, saturation, temperature, tint, shadows, highlights, lutIntensity, vibrance, hue: Float
        var lift, gamma, gain: [Float]
        init(_ p: GradingParams) {
            exposure=p.exposure; contrast=p.contrast; saturation=p.saturation; temperature=p.temperature; tint=p.tint
            shadows=p.shadows; highlights=p.highlights; lutIntensity=p.lutIntensity; vibrance=p.vibrance; hue=p.hue
            lift=[p.lift.x,p.lift.y,p.lift.z]; gamma=[p.gamma.x,p.gamma.y,p.gamma.z]; gain=[p.gain.x,p.gain.y,p.gain.z]
        }
    }
}
enum CubeLUTParser {
    static func parse(cubeString: String) -> (data: Data, size: Int)? {
        var size = 0
        var r: [Float]=[], g: [Float]=[], b: [Float]=[]
        var domainMin: Float = 0, domainMax: Float = 1
        for line in cubeString.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if t.hasPrefix("LUT_3D_SIZE") { size = Int(t.components(separatedBy: .whitespaces).last ?? "") ?? 0; continue }
            if t.hasPrefix("DOMAIN_MIN") { domainMin = Float(t.components(separatedBy: .whitespaces).dropFirst().first ?? "0") ?? 0; continue }
            if t.hasPrefix("DOMAIN_MAX") { domainMax = Float(t.components(separatedBy: .whitespaces).dropFirst().first ?? "1") ?? 1; continue }
            if t.hasPrefix("TITLE") { continue }
            let comps = t.components(separatedBy: .whitespaces).compactMap{ Float($0) }
            if comps.count == 3 { r.append(comps[0]); g.append(comps[1]); b.append(comps[2]) }
        }
        guard size>0, r.count==size*size*size else { return nil }
        let scale: Float = (domainMax - domainMin) != 1 && (domainMax - domainMin) != 0 ? 1/(domainMax - domainMin) : 1
        var data = Data(capacity: size*size*size*4*4)
        for i in 0..<(size*size*size) {
            var rf = (r[i]-domainMin)*scale, gf = (g[i]-domainMin)*scale, bf = (b[i]-domainMin)*scale
            rf = max(0,min(1,rf)); gf = max(0,min(1,gf)); bf = max(0,min(1,bf))
            var vals: [Float] = [rf,gf,bf,1]
            vals.withUnsafeBytes{ data.append(contentsOf: $0) }
        }
        guard data.count == size*size*size*16 else { return nil }
        return (data, size)
    }
}
