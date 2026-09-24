import AVFoundation

final class AdaptiveLensManager {
    struct Lens: Codable {
        var id: String
        var label: String
        var deviceType: AVCaptureDevice.DeviceType
        var position: AVCaptureDevice.Position
        var nominalZoom: CGFloat
        var minZoom: CGFloat
        var maxZoom: CGFloat
        var focalMM: Float?
        var isVirtual: Bool
    }
    var lensesBack: [Lens] = []
    var lensesFront: [Lens] = []
    var virtualDevice: AVCaptureDevice?
    var currentBackLensID: String = "wide"
    init() { rediscover() }
    func rediscover() {
        lensesBack = discover(position: .back)
        lensesFront = discover(position: .front)
        virtualDevice = virtualDeviceFor(position: .back)
    }
    private func discover(position: AVCaptureDevice.Position) -> [Lens] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera,.builtInDualWideCamera,.builtInDualCamera,.builtInUltraWideCamera,.builtInWideAngleCamera,.builtInTelephotoCamera,.builtInTrueDepthCamera]
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)
        var lenses: [Lens] = []
        for d in session.devices {
            if #available(iOS 15.0, *), d.deviceType == .builtInLiDARDepthCamera { continue }
            if d.deviceType == .builtInTripleCamera || d.deviceType == .builtInDualWideCamera || d.deviceType == .builtInDualCamera { continue }
            let id: String; let label: String; let nominal: CGFloat
            switch d.deviceType {
            case .builtInUltraWideCamera: id = "ultraWide"; label = "0.5×"; nominal = 0.5
            case .builtInWideAngleCamera: id = "wide"; label = "1×"; nominal = 1.0
            case .builtInTelephotoCamera: id = "tele"; label = teleLabel(for: d); nominal = teleNominal(for: d)
            case .builtInTrueDepthCamera: id = "front"; label = "Front"; nominal = 1.0
            default: id = d.localizedName.lowercased(); label = d.localizedName; nominal = 1.0
            }
            let lens = Lens(id: id, label: label, deviceType: d.deviceType, position: position, nominalZoom: nominal, minZoom: nominal*0.9, maxZoom: nominal*3, focalMM: nil, isVirtual: false)
            if !lenses.contains(where:{ $0.id==id && $0.deviceType==d.deviceType }) { lenses.append(lens) }
        }
        if let virt = virtualDeviceFor(position: position) {
            var virtLenses: [Lens] = []
            if #available(iOS 13.0, *) {
                let constituents: [AVCaptureDevice] = virt.constituentDevices
                if !constituents.isEmpty {
                    for (idx, pd) in constituents.enumerated() {
                        let id: String
                        if pd.deviceType == .builtInUltraWideCamera { id = "ultraWide" }
                        else if pd.deviceType == .builtInTelephotoCamera { id = "tele" }
                        else { id = idx==0 && constituents.count==2 ? "wide" : "wide" }
                        let nominal: CGFloat = id=="ultraWide" ? 0.5 : id=="tele" ? 5 : 1.0
                        let label = id=="ultraWide" ? "0.5×" : id=="tele" ? "\(Int(nominal))×" : "1×"
                        virtLenses.append(Lens(id:id, label:label, deviceType: pd.deviceType, position: position, nominalZoom: nominal, minZoom: nominal*0.9, maxZoom: nominal*3, focalMM: nil, isVirtual: true))
                    }
                }
            }
            if !virtLenses.isEmpty { return virtLenses.sorted{ $0.nominalZoom < $1.nominalZoom } }
        }
        if lenses.isEmpty && position == .back {
            lenses.append(Lens(id:"wide", label:"1×", deviceType:.builtInWideAngleCamera, position:.back, nominalZoom:1, minZoom:1, maxZoom:8, focalMM: nil, isVirtual:false))
        }
        return lenses.sorted{ $0.nominalZoom < $1.nominalZoom }
    }
    func virtualDeviceFor(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let d = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) { return d }
        if let d = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) { return d }
        if let d = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) { return d }
        return nil
    }
    private func teleNominal(for d: AVCaptureDevice) -> CGFloat {
        let maxZ = d.activeFormat.videoMaxZoomFactor
        if maxZ >= 10 { return 5 }
        if maxZ >= 6 { return 3 }
        return 2
    }
    private func teleLabel(for d: AVCaptureDevice) -> String { "\(Int(teleNominal(for: d)))×" }
    func lens(for zoom: CGFloat, position: AVCaptureDevice.Position) -> Lens? {
        let list = position == .back ? lensesBack : lensesFront
        guard !list.isEmpty else { return nil }
        for l in list { if zoom >= l.minZoom && zoom <= l.maxZoom { return l } }
        return list.min(by: { abs($0.nominalZoom - zoom) < abs($1.nominalZoom - zoom) })
    }
    func switchFactorsBack() -> [CGFloat] {
        if let vd = virtualDevice {
            let arr = vd.virtualDeviceSwitchOverVideoZoomFactors
            if !arr.isEmpty { return arr.map{ CGFloat(truncating: $0) } }
        }
        return lensesBack.map{ $0.nominalZoom }.sorted()
    }
    var labelsBack: [String] { lensesBack.map{ $0.label } }
    func isSeamlessAvailable(for position: AVCaptureDevice.Position) -> Bool { return virtualDeviceFor(position: position) != nil }
}
