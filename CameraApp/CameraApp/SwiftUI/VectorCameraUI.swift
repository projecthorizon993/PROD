import SwiftUI
import AVFoundation

// MARK: - VectorCam UI (Production)
// UI from VectorCameraUI.swift — now wired to ProCameraManager (AVFoundation + ANE).
// No mock: CameraPreviewMock replaced by CameraPreview(manager:).

struct VectorCameraView: View {
    @StateObject private var manager = ProCameraManager()
    @State private var mode: CameraMode = .photo
    @State private var isNight = false
    @State private var isBracket = false
    @State private var activeSheet: CameraSheet?
    @State private var showFeatures = false
    @State private var focusPoint: CGPoint?
    @State private var showFocus = false

    var body: some View {
        ZStack {
            // Real preview — falls back to mock only in #Preview (manager not running)
            CameraPreview(manager: manager)
                .onAppear {
                    manager.colorGradingEngine = ColorGradingEngine()
                    manager.filterPipeline = FilterPipeline()
                    if let enh = LowLightEnhancer() { manager.lowLightEnhancer = enh }
                    if let zs = ZoomSharpnessEngine(device: MTLCreateSystemDefaultDevice()) { manager.zoomSharpnessEngine = zs }
                    if let br = BracketEngine(device: MTLCreateSystemDefaultDevice()) { manager.bracketEngine = br }
                    manager.checkPermissionAndSetup()
                    // Sync UI state with manager
                    isNight = manager.lowLightBoostEnabled
                    isBracket = manager.bracketEnabled
                }
                .onChange(of: isNight) { _, v in manager.lowLightBoostEnabled = v }
                .onChange(of: isBracket) { _, v in
                    manager.bracketEnabled = v
                    if v && manager.bracketEngine == nil, let br = BracketEngine(device: MTLCreateSystemDefaultDevice()) { manager.bracketEngine = br }
                }
                .onTapGesture { loc in
                    let p = CGPoint(x: loc.x / UIScreen.main.bounds.width, y: loc.y / UIScreen.main.bounds.height)
                    manager.setAutoFocus(at: p)
                    focusPoint = loc; showFocus = true
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.9) { withAnimation { showFocus = false } }
                }
                .gesture(MagnificationGesture().onChanged { v in manager.rampZoom(to: manager.zoomFactor * v) })

            // Focus feedback (vector)
            if let point = focusPoint, showFocus {
                FocusIndicator()
                    .position(point)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                zoomBadge
                Spacer()
                bottomInterface
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(item: $activeSheet) { sheet in
            CameraControlSheet(sheet: sheet, zoom: Binding(get: { Double(manager.zoomFactor) }, set: { manager.setZoom(CGFloat($0)) }), manager: manager)
                .presentationDetents(sheet.detents)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showFeatures) {
            FeatureChooserView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            CameraPill(icon: "square.grid.2x2", title: "Features") { showFeatures = true }
            Spacer(minLength: 4)
            CameraPill(icon: "camera.rotate", title: nil) { manager.switchCamera() }
            CameraPill(icon: isNight ? "moon.fill" : "moon", title: "Night", isActive: isNight) { isNight.toggle() }
            if isNight {
                CameraPill(icon: "slider.horizontal.3", title: nil) { activeSheet = .lowLight }
            }
            CameraPill(icon: "square.stack.3d.up", title: nil, isActive: isBracket) { isBracket.toggle() }
            CameraPill(icon: "gearshape", title: nil) { activeSheet = .zoom }
        }
        .padding(.horizontal, 14)
    }

    private var zoomBadge: some View {
        Text(String(format: "%.1f× %@", manager.zoomFactor, manager.activeLens))
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(.black.opacity(0.48), in: Capsule())
    }

    private var bottomInterface: some View {
        VStack(spacing: 14) {
            featureStrip
            HStack(alignment: .center) {
                GalleryThumbnail(manager: manager)
                Spacer()
                ModeSelector(mode: $mode)
                    .onChange(of: mode) { _, _ in /* photo/video switch is UI-only; capture uses manager.capturePhoto vs startRecording */ }
                Spacer()
                ShutterButton(isRecording: Binding(get: { manager.isRecording }, set: { _ in }), mode: mode, manager: manager)
            }
            .padding(.horizontal, 20)
        }
    }

    private var featureStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CameraFeatureButton(title: "Grading", icon: "circle.lefthalf.filled") { activeSheet = .grading }
                CameraFeatureButton(title: "Manual", icon: "dial.low") { activeSheet = .manual }
                CameraFeatureButton(title: "Filters", icon: "camera.filters") { activeSheet = .filters }
                CameraFeatureButton(title: "Sharpness", icon: "viewfinder") { activeSheet = .sharpness }
                CameraFeatureButton(title: "Zoom", icon: "plus.magnifyingglass") { activeSheet = .zoom }
                CameraFeatureButton(title: "Bracket", icon: "square.stack.3d.up") { activeSheet = .bracket }
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - Top Components

struct CameraPill: View {
    let icon: String
    let title: String?
    var isActive: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                if let title { Text(title).font(.system(size: 12, weight: .semibold)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, title == nil ? 11 : 12)
            .padding(.vertical, 9)
            .background(isActive ? Color.white.opacity(0.24) : Color.black.opacity(0.42), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Capture Controls

enum CameraMode: String { case photo = "Photo"; case video = "Video" }

struct ModeSelector: View {
    @Binding var mode: CameraMode
    var body: some View {
        HStack(spacing: 4) {
            ForEach([CameraMode.photo, .video], id: \.self) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { mode = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode == item ? .black : .white)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .background { if mode == item { Capsule().fill(.white) } }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(.black.opacity(0.48), in: Capsule())
    }
}

struct ShutterButton: View {
    @Binding var isRecording: Bool
    let mode: CameraMode
    var manager: ProCameraManager? = nil

    var body: some View {
        Button {
            guard let m = manager else {
                if mode == .video { isRecording.toggle() }
                return
            }
            if mode == .photo {
                // Photo capture via manager (includes bracket/low-light/sharpen pipeline)
                let del = SwiftUIShutterDelegate()
                m.capturePhoto(delegate: del)
            } else {
                if m.isRecording { m.stopVideoRecording() } else { m.startVideoRecording() }
            }
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 78, height: 78)
                if mode == .video && (isRecording || (manager?.isRecording ?? false)) {
                    RoundedRectangle(cornerRadius: 7).fill(.red).frame(width: 28, height: 28)
                } else {
                    Circle().fill(.black.opacity(0.9)).frame(width: 58, height: 58)
                        .overlay { if mode == .video { Circle().fill(.red).frame(width: 26, height: 26) } }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private class SwiftUIShutterDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // No-op: ProCameraManager's PhotoDelegate handles saving; this delegate is for VectorCam shutter without RN bridge
        // For SwiftUI standalone, we rely on ProCameraManager's internal handling via manager.capturePhoto with dummy delegate that saves to Photos
    }
}

struct GalleryThumbnail: View {
    var manager: ProCameraManager? = nil
    var body: some View {
        Button {
            if let url = manager?.recordedVideoURL ?? manager?.lastCapturedImage.map({ _ in URL(string: "photos://") } as? URL) { /* open */ }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.12))
                if let img = manager?.lastCapturedImage {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 52, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "photo").font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 52, height: 52)
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.25), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

struct CameraFeatureButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium))
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(minWidth: 65)
            .padding(.vertical, 9).padding(.horizontal, 7)
            .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.09), lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets

enum CameraSheet: String, Identifiable {
    case zoom, manual, grading, filters, lowLight, bracket, sharpness
    var id: String { rawValue }
    var detents: Set<PresentationDetent> {
        switch self {
        case .grading: return [.fraction(0.88)]
        case .filters: return [.fraction(0.72)]
        default: return [.fraction(0.62)]
        }
    }
    var title: String {
        switch self {
        case .zoom: return "Zoom"
        case .manual: return "Manual"
        case .grading: return "Color Grading"
        case .filters: return "Filters"
        case .lowLight: return "Low Light"
        case .bracket: return "Bracket"
        case .sharpness: return "Sharpness"
        }
    }
}

struct CameraControlSheet: View {
    let sheet: CameraSheet
    @Binding var zoom: Double
    var manager: ProCameraManager? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch sheet {
                case .zoom: ZoomPanel(zoom: $zoom, manager: manager)
                case .manual: ManualPanel(manager: manager)
                case .grading: GradingPanel(manager: manager)
                case .filters: FilterPanel(manager: manager)
                case .lowLight: LowLightPanel(manager: manager)
                case .bracket: BracketPanel(manager: manager)
                case .sharpness: SharpnessPanel(manager: manager, zoom: zoom)
                }
            }
            .navigationTitle(sheet.title).navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Panels wired to ProCameraManager (reuse existing logic)

struct ZoomPanel: View {
    @Binding var zoom: Double
    var manager: ProCameraManager? = nil
    @State private var superResolution = true
    @State private var seamless = true
    private let presets: [Double] = [0.5, 1, 2, 3, 5]
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text(String(format: "%.1f× %@", zoom, manager?.activeLens ?? "wide"))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Slider(value: $zoom, in: 0.5...8, step: 0.1)
                    .onChange(of: zoom) { _, v in manager?.setZoom(CGFloat(v)) }
                HStack(spacing: 9) {
                    ForEach(presets, id: \.self) { value in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { zoom = value; manager?.setZoom(CGFloat(value)) }
                        } label: {
                            Text(String(format: "%.1f×", value))
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(abs(zoom - value) < 0.05 ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Toggle("Super Resolution", isOn: $superResolution).onChange(of: superResolution) { _, v in manager?.setSuperResolution(enabled: v) }
                Toggle("Seamless Lens Switching", isOn: $seamless).onChange(of: seamless) { _, v in manager?.setSeamlessEnabled(v) }
                StatusCard(title: (zoom <= 2 ? "OPTICAL" : "DIGITAL + ANE SR"), detail: zoom <= 2 ? "Using available optical lens" : "Super-resolution processing enabled")
            }
            .padding(22)
        }
        .onAppear { superResolution = manager?.zoomSharpnessEngine?.superResEnabled ?? true; seamless = manager?.seamlessEnabled ?? true }
    }
}

struct ManualPanel: View {
    var manager: ProCameraManager? = nil
    @State private var iso = 200.0
    @State private var shutter = 0.25
    @State private var focus = 0.5
    @State private var temperature = 0.5
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                CameraSlider(title: "ISO", value: $iso, range: 32...3200, valueText: "\(Int(iso))").onChange(of: iso) { _, v in manager?.setManualExposure(iso: Float(v), shutter: nil) }
                CameraSlider(title: "Shutter", value: $shutter, range: 0.5...33, valueText: String(format: "%.1f ms", shutter)).onChange(of: shutter) { _, v in
                    let cm = CMTimeMakeWithSeconds(v/1000, preferredTimescale: 1_000_000); manager?.setManualExposure(iso: Float(iso), shutter: cm)
                }
                CameraSlider(title: "Focus", value: $focus, range: 0...1, valueText: String(format: "%.2f", focus)).onChange(of: focus) { _, v in manager?.setManualFocus(lensPosition: Float(v)) }
                CameraSlider(title: "WB", value: $temperature, range: 0...1, valueText: String(format: "%.2f", temperature))
            }
            .padding(22)
        }
    }
}

struct GradingPanel: View {
    var manager: ProCameraManager? = nil
    @State private var exposure = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var temperature = 0.0
    @State private var tint = 0.0
    @State private var shadows = 0.0
    @State private var highlights = 0.0
    @State private var vibrance = 0.0
    @State private var hue = 0.0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gradingSlider("Exposure", $exposure, -2...2) { manager?.colorGradingEngine?.params.exposure = Float($0) }
                gradingSlider("Contrast", $contrast, 0.5...1.8) { manager?.colorGradingEngine?.params.contrast = Float($0) }
                gradingSlider("Saturation", $saturation, 0...2) { manager?.colorGradingEngine?.params.saturation = Float($0) }
                gradingSlider("Temperature", $temperature, -1...1) { manager?.colorGradingEngine?.params.temperature = Float($0) }
                gradingSlider("Tint", $tint, -1...1) { manager?.colorGradingEngine?.params.tint = Float($0) }
                gradingSlider("Shadows", $shadows, -1...1) { manager?.colorGradingEngine?.params.shadows = Float($0) }
                gradingSlider("Highlights", $highlights, -1...1) { manager?.colorGradingEngine?.params.highlights = Float($0) }
                gradingSlider("Vibrance", $vibrance, -1...1) { manager?.colorGradingEngine?.params.vibrance = Float($0) }
                gradingSlider("Hue", $hue, -0.5...0.5) { manager?.colorGradingEngine?.params.hue = Float($0) }
            }
            .padding(22)
        }
    }
    private func gradingSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ onChange: @escaping (Double)->Void) -> some View {
        CameraSlider(title: title, value: value, range: range, valueText: String(format: "%.2f", value.wrappedValue)).onChange(of: value.wrappedValue) { _, v in onChange(v) }
    }
}

struct FilterPanel: View {
    var manager: ProCameraManager? = nil
    private let filters = ["None","Vivid","Vivid Warm","Mono","Noir","Silver","Chrome","Fade","Instant","Process","Transfer","Tonal","Cinematic","Teal & Orange","Night Boost"]
    @State private var selected = "None"
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(filters, id: \.self) { filter in
                    Button { selected = filter; if let f = CameraFilter(rawValue: filter) { manager?.filterPipeline?.currentFilter = f } } label: {
                        VStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [.blue.opacity(0.45), .purple.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 75)
                                .overlay { if selected == filter { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2) } }
                            Text(filter).font(.caption).foregroundStyle(.primary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
        }
    }
}

struct LowLightPanel: View {
    var manager: ProCameraManager? = nil
    @State private var target = "Balanced"
    @State private var strategy = "Auto"
    let targets = ["PSNR","Perceptual","Natural","Balanced"]
    let strategies = ["Auto","ANE Retinexformer","ANE ZeroDCE","Retinex Fallback","HVI Fallback"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Target Metric").font(.headline)
                Picker("Target", selection: $target) { ForEach(targets, id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    .onChange(of: target) { _, v in manager?.lowLightEnhancer?.targetMetric = v.lowercased() == "psnr" ? .psnr : v.lowercased() == "perceptual" ? .perceptual : v.lowercased() == "natural" ? .natural : .balanced }
                Text("Strategy").font(.headline)
                ForEach(strategies, id: \.self) { item in
                    Button { strategy = item; if let s = LowLightEnhancer.Strategy(rawValue: item.replacingOccurrences(of: " ", with: "")) { manager?.lowLightEnhancer?.strategy = s } } label: {
                        HStack {
                            Image(systemName: strategy == item ? "largecircle.fill.circle" : "circle")
                            Text(item); Spacer()
                        }
                        .foregroundStyle(.primary).padding().background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                StatusCard(title: "PROCESSING", detail: "Strategy: \(strategy)\nTarget: \(target)\nANE acceleration when available")
            }
            .padding(22)
        }
    }
}

struct BracketPanel: View {
    var manager: ProCameraManager? = nil
    @State private var enabled = false
    @State private var shots = 5.0
    @State private var iso = 6400.0
    var dbGain: Double { 10 * log10(shots) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Extreme Low Light Bracketing", isOn: $enabled).onChange(of: enabled) { _, v in manager?.bracketEnabled = v; if v && manager?.bracketEngine == nil, let br = BracketEngine(device: MTLCreateSystemDefaultDevice()) { manager?.bracketEngine = br } }
                CameraSlider(title: "N (shots)", value: $shots, range: 3...7, valueText: "\(Int(shots))").onChange(of: shots) { _, v in manager?.bracketEngine?.count = Int(v) }
                HStack { Text("+\(String(format: "%.1f", dbGain)) dB"); Spacer(); Text("10 · log₁₀(N)") }.font(.caption).foregroundStyle(.secondary)
                CameraSlider(title: "ISO", value: $iso, range: 3200...12800, valueText: "\(Int(iso))").onChange(of: iso) { _, v in manager?.bracketEngine?.targetISO = Float(v) }
                StatusCard(title: "EFFECTIVE ISO", detail: "ISO / √N  •  burst <600 ms  •  Vision align  •  linear mean  •  LOE")
            }
            .padding(22)
        }
        .onAppear { enabled = manager?.bracketEnabled ?? false; shots = Double(manager?.bracketEngine?.count ?? 5); iso = Double(manager?.bracketEngine?.targetISO ?? 6400) }
    }
}

struct SharpnessPanel: View {
    var manager: ProCameraManager? = nil
    var zoom: Double = 1
    @State private var intensity = 0.7
    @State private var preset = "Balanced"
    let presets = ["Auto","PSNR","Perceptual","Natural","Balanced"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            CameraSlider(title: "Intensity", value: $intensity, range: 0...1, valueText: String(format: "%.2f", intensity)).onChange(of: intensity) { _, v in manager?.setSharpness(intensity: Float(v), preset: preset.lowercased()) }
            Text("Preset").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(presets, id: \.self) { item in
                        Button(item) { preset = item; manager?.setSharpness(intensity: Float(intensity), preset: item.lowercased()) }
                            .buttonStyle(.borderedProminent).tint(preset == item ? .accentColor : .gray.opacity(0.25))
                    }
                }
            }
            StatusCard(title: "ADAPTIVE SHARPENING", detail: "r = 0.9 + 0.25 · (zoom − 1)\nDigital >2.2× → SR + sharpen")
            Spacer()
        }
        .padding(22)
    }
}

// MARK: - Focus Indicator (vector)

struct FocusIndicator: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color.yellow, lineWidth: 2).frame(width: 80, height: 80)
            Circle().fill(Color.yellow).frame(width: 5, height: 5)
        }
    }
}

// MARK: - Shared Components

struct CameraSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(valueText).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

struct StatusCard: View {
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption.weight(.bold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(15).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
    }
}

struct FocusIndicator_Previews: PreviewProvider {
    static var previews: some View { FocusIndicator() }
}
