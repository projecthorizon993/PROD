import AVFoundation
import UIKit
import Combine
import CoreImage
import CoreMedia
import CoreVideo

// MARK: - ProCameraManager
// Central AVFoundation stack. Handles session, photo/video, manual controls, and delegates frame processing
// to ColorGradingEngine + LowLightEnhancer (both ANE-accelerated where possible).

final class ProCameraManager: NSObject, ObservableObject {
    // Published state for SwiftUI / RN bridge
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var currentPosition: AVCaptureDevice.Position = .back
    @Published var zoomFactor: CGFloat = 1.0
    @Published var torchEnabled = false
    @Published var lastCapturedImage: UIImage?
    @Published var recordedVideoURL: URL?

    // Manual controls
    @Published var iso: Float = 0      // auto if 0
    @Published var shutterSpeed: CMTime = .invalid // auto if invalid
    @Published var focusLensPosition: Float = 0.5 // 0..1
    @Published var whiteBalanceGains = AVCaptureDevice.WhiteBalanceGains(redGain: 1, greenGain: 1, blueGain: 1)
    @Published var exposureBias: Float = 0
    @Published var isManualFocus = false
    @Published var isManualExposure = false
    @Published var isManualWB = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "pro.camera.session.queue")
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var audioDeviceInput: AVCaptureDeviceInput?

    // For live preview layer
    var previewLayer: AVCaptureVideoPreviewLayer?

    // Processing engines (injected)
    var colorGradingEngine: ColorGradingEngine?
    var lowLightEnhancer: LowLightEnhancer?
    var filterPipeline: FilterPipeline?
    var zoomSharpnessEngine: ZoomSharpnessEngine?
    var bracketEngine: BracketEngine?
    let adaptiveLens = AdaptiveLensManager() // discovers per-device, system-baked if available

    // Feature toggles
    @Published var lowLightBoostEnabled = false
    @Published var colorGradingEnabled = true
    // Metrics-driven tuning (awesome list)
    @Published var lowLightTarget: LowLightEnhancer.MetricPriority = .balanced
    var onMetricsUpdate: ((LowLightMetrics.Report) -> Void)?
    private var lastMetricsTime: CFAbsoluteTime = 0
    // Seamless system-baked lens switching (virtual device)
    @Published var seamlessEnabled = true
    @Published var activeLens: String = "wide" // ultraWide | wide | tele | front
    @Published var virtualSwitchFactors: [CGFloat] = [] // e.g. [1.0, 2.0, 6.0]
    @Published var isSwitchingLenses = false
    var onSeamlessSwitch: (() -> Void)? // UI crossfade hook

    private var cancellables = Set<AnyCancellable>()

    // MARK: - ANE thermal monitoring (WWDC22: throttle ANE on .serious/.critical)
    private func observeThermal() {
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            let s = ProcessInfo.processInfo.thermalState
            print("[ANE] thermalState=\(s.rawValue) (\(s == .critical ? "critical → ANE preview OFF" : s == .serious ? "serious → ANE throttled" : "nominal"))")
            if s == .critical {
                // Keep still capture ANE but disable preview heavy work (we already do fallback for preview)
                self.lowLightEnhancer?.isANEPreferred = false
            } else {
                self.lowLightEnhancer?.isANEPreferred = true
            }
        }
    }

    // MARK: - Session setup
    func checkPermissionAndSetup() {
        observeThermal()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.setupSession() }
            }
        default:
            print("[ProCamera] Camera permission denied")
        }
    }

    private func setupSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high // supports 4K if device allows, we upgrade later

            // Input: video device
            self.configureVideoInput(position: self.currentPosition)

            // Audio input for video
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
                self.audioDeviceInput = audioInput
            }

            // Outputs
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                if #available(iOS 15.0, *) {
                    self.photoOutput.isResponsiveCaptureEnabled = true
                }
            }
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }
            // Video data output for live processing (color grading / low-light ANE)
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "pro.camera.video.queue"))
            if self.session.canAddOutput(self.videoDataOutput) {
                self.session.addOutput(self.videoDataOutput)
                // Keep preview orientation consistent
                if let conn = self.videoDataOutput.connection(with: .video), conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
                }
            }

            self.session.commitConfiguration()
            self.startRunning()
        }
    }

    private func configureVideoInput(position: AVCaptureDevice.Position) {
        if let old = videoDeviceInput { session.removeInput(old) }

        // Adaptive: prefer system-baked virtual device if present, else best physical for this device (SE→Pro Max)
        let device: AVCaptureDevice? = {
            // Refresh discovery per switch (handles external lens attach)
            self.adaptiveLens.rediscover()
            if let vd = self.adaptiveLens.virtualDeviceFor(position: position) { return vd }
            // No virtual → pick best physical from discovery (wide preferred)
            let list = position == .back ? self.adaptiveLens.lensesBack : self.adaptiveLens.lensesFront
            if let wide = list.first(where:{ $0.id=="wide" }) {
                return AVCaptureDevice.default(wide.deviceType, for: .video, position: position)
            }
            if let first = list.first {
                return AVCaptureDevice.default(first.deviceType, for: .video, position: position)
            }
            // Ultimate fallback (simulator/SE)
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        }()

        guard let videoDevice = device,
              let input = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(input) else {
            print("[ProCamera] Failed to create video input")
            return
        }
        session.addInput(input)
        videoDeviceInput = input
        currentPosition = position
        zoomFactor = 1.0
        // Adaptive switch factors: virtual → system-baked, physical-only → synthesized from nominals
        virtualSwitchFactors = adaptiveLens.switchFactorsBack()
        if virtualSwitchFactors.isEmpty { virtualSwitchFactors = [1.0] }
        let maxZ = videoDevice.activeFormat.videoMaxZoomFactor
        let optical = virtualSwitchFactors.last ?? (maxZ >= 8 ? 6.0 : (maxZ >= 4 ? 2.5 : 1.0))
        zoomSharpnessEngine?.maxOpticalZoom = optical
        updateActiveLens(for: 1.0)
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.isSubjectAreaChangeMonitoringEnabled = true
            if #available(iOS 15.0, *) { videoDevice.automaticallyAdjustsVideoHDREnabled = seamlessEnabled }
            videoDevice.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Seamless helpers
    private func updateActiveLens(for zoom: CGFloat) {
        // Map zoom → constituent lens (system-baked)
        if currentPosition == .front { activeLens = "front"; return }
        let factors = virtualSwitchFactors
        if factors.count >= 3 { // triple
            if zoom < (factors[1] * 0.85) { activeLens = zoom < 0.9 ? "ultraWide" : "wide" }
            else { activeLens = "tele" }
        } else if factors.count == 2 { // dual
            activeLens = zoom < (factors[1] * 0.9) ? "wide" : "tele"
        } else {
            activeLens = "wide"
        }
    }
    func setSeamlessEnabled(_ enabled: Bool) {
        seamlessEnabled = enabled
        guard let d = videoDeviceInput?.device else { return }
        try? d.lockForConfiguration()
        if #available(iOS 15.0, *) { d.automaticallyAdjustsVideoHDREnabled = enabled }
        d.unlockForConfiguration()
    }

    // Manual fallback for non-virtual devices (SE, iPad, older) — switch physical device at zoom threshold
    private func ensurePhysicalLens(for zoom: CGFloat) {
        guard !adaptiveLens.isSeamlessAvailable(for: currentPosition) else { return }
        guard let target = adaptiveLens.lens(for: zoom, position: currentPosition),
              let curType = videoDeviceInput?.device.deviceType,
              target.deviceType != curType else { return }
        // Crossfade + reconfigure to target physical lens
        DispatchQueue.main.async { self.isSwitchingLenses = true; self.onSeamlessSwitch?() }
        sessionQueue.async {
            self.session.beginConfiguration()
            if let old = self.videoDeviceInput { self.session.removeInput(old) }
            if let newDev = AVCaptureDevice.default(target.deviceType, for: .video, position: self.currentPosition),
               let newIn = try? AVCaptureDeviceInput(device: newDev), self.session.canAddInput(newIn) {
                self.session.addInput(newIn)
                self.videoDeviceInput = newIn
                self.activeLens = target.id
                let maxZ = newDev.activeFormat.videoMaxZoomFactor
                self.zoomSharpnessEngine?.maxOpticalZoom = target.nominalZoom * 2.5
                try? newDev.lockForConfiguration(); newDev.isSubjectAreaChangeMonitoringEnabled = true; newDev.unlockForConfiguration()
            }
            self.session.commitConfiguration()
            DispatchQueue.main.asyncAfter(deadline: .now()+0.30) { self.isSwitchingLenses = false }
        }
    }

    func startRunning() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async { self.isSessionRunning = true }
            }
        }
    }

    func stopRunning() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.isSessionRunning = false }
            }
        }
    }

    // MARK: - Switch camera (seamless crossfade)
    func switchCamera() {
        // UI: crossfade preview (0.28s) to mask hard input swap front↔back. Zoom-driven lens switches (ultraWide/wide/tele)
        // on the same position are already seamless via virtual device — no session reconfigure needed.
        DispatchQueue.main.async {
            self.isSwitchingLenses = true
            self.onSeamlessSwitch?()
        }
        sessionQueue.async {
            Thread.sleep(forTimeInterval: 0.06) // let fade start
            let newPos: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            self.session.beginConfiguration()
            self.configureVideoInput(position: newPos)
            if let conn = self.videoDataOutput.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
                conn.isVideoMirrored = newPos == .front
            }
            if let conn = self.photoOutput.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.currentPosition = newPos
                self.activeLens = newPos == .front ? "front" : "wide"
                // end crossfade
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { self.isSwitchingLenses = false }
            }
        }
    }

    // MARK: - Zoom + Sharpness (adaptive vs seamless)
    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        // Adaptive: if manual fallback needed, switch physical lens first
        ensurePhysicalLens(for: factor)
        // Re-fetch device after potential switch (ensurePhysicalLens may have swapped)
        guard let curDev = videoDeviceInput?.device else { return }
        let clamped = max(1.0, min(factor, curDev.activeFormat.videoMaxZoomFactor))
        let useRamp = seamlessEnabled && !virtualSwitchFactors.isEmpty && adaptiveLens.isSeamlessAvailable(for: currentPosition)
        do {
            try curDev.lockForConfiguration()
            if useRamp && abs(clamped - curDev.videoZoomFactor) > 0.08 {
                curDev.ramp(toVideoZoomFactor: clamped, withRate: 5)
            } else {
                curDev.videoZoomFactor = clamped
            }
            curDev.unlockForConfiguration()
            DispatchQueue.main.async {
                self.zoomFactor = clamped
                self.updateActiveLens(for: clamped)
            }
        } catch { print("[ProCamera] zoom error \(error)") }
    }
    func setSharpness(intensity: Float, preset: String = "balanced") {
        zoomSharpnessEngine?.sharpness = max(0, min(1, intensity))
        if let p = ZoomSharpnessEngine.SharpnessPreset(rawValue: preset.lowercased()) { zoomSharpnessEngine?.preset = p }
    }
    func setSuperResolution(enabled: Bool) { zoomSharpnessEngine?.superResEnabled = enabled }
    var zoomRange: ClosedRange<CGFloat> {
        guard let d = videoDeviceInput?.device else { return 1...8 }
        return 1...d.activeFormat.videoMaxZoomFactor
    }
    var opticalZoomThreshold: CGFloat { zoomSharpnessEngine?.maxOpticalZoom ?? 2.5 }

    func rampZoom(to factor: CGFloat, rate: Float = 8) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: max(1, min(factor, device.activeFormat.videoMaxZoomFactor)), withRate: rate)
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Torch / Flash
    func setTorch(_ on: Bool) {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchEnabled = on
        } catch {}
    }

    // MARK: - Manual controls
    func setManualExposure(iso: Float?, shutter: CMTime?) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if let iso = iso {
                self.iso = iso
                isManualExposure = true
            }
            if let shutter = shutter, shutter.isValid {
                self.shutterSpeed = shutter
                isManualExposure = true
            }
            if isManualExposure {
                let minISO = device.activeFormat.minISO
                let maxISO = device.activeFormat.maxISO
                let clampedISO = max(minISO, min(self.iso > 0 ? self.iso : device.iso, maxISO))
                let duration = shutterSpeed.isValid ? shutterSpeed : device.exposureDuration
                // Clamp duration to format limits
                let minDur = device.activeFormat.minExposureDuration
                let maxDur = device.activeFormat.maxExposureDuration
                let clampedDur: CMTime
                if CMTimeCompare(duration, minDur) < 0 { clampedDur = minDur }
                else if CMTimeCompare(duration, maxDur) > 0 { clampedDur = maxDur }
                else { clampedDur = duration }
                device.setExposureModeCustom(duration: clampedDur, iso: clampedISO, completionHandler: nil)
            } else {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch { print("[ProCamera] exposure error \(error)") }
    }

    func setExposureBias(_ bias: Float) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let clamped = max(device.minExposureTargetBias, min(bias, device.maxExposureTargetBias))
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
            exposureBias = clamped
        } catch {}
    }

    func setManualFocus(lensPosition: Float) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let clamped = max(0, min(lensPosition, 1))
            device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
            device.unlockForConfiguration()
            focusLensPosition = clamped
            isManualFocus = true
        } catch {}
    }

    func setAutoFocus(at point: CGPoint) {
        guard let device = videoDeviceInput?.device, device.isFocusPointOfInterestSupported else { return }
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
            device.unlockForConfiguration()
            isManualFocus = false
        } catch {}
    }

    func setWhiteBalance(gains: AVCaptureDevice.WhiteBalanceGains) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let maxG = device.maxWhiteBalanceGain
            var g = gains
            g.redGain = max(1, min(g.redGain, maxG))
            g.greenGain = max(1, min(g.greenGain, maxG))
            g.blueGain = max(1, min(g.blueGain, maxG))
            device.setWhiteBalanceModeLocked(with: g, completionHandler: nil)
            device.unlockForConfiguration()
            whiteBalanceGains = g
            isManualWB = true
        } catch {}
    }

    func setAutoWhiteBalance() {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            device.whiteBalanceMode = .continuousAutoWhiteBalance
            device.unlockForConfiguration()
            isManualWB = false
        } catch {}
    }

    func setAutoExposure() {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
            isManualExposure = false
            iso = 0
            shutterSpeed = .invalid
        } catch {}
    }

    // MARK: - Photo capture
    var bracketEnabled = false // extreme low-light stacking
    func capturePhoto(with settings: PhotoSettings = PhotoSettings(), delegate: AVCapturePhotoCaptureDelegate) {
        let photoSettings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            photoSettings = AVCapturePhotoSettings()
        }
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.flashMode = settings.flashMode
        photoSettings.isAutoStillImageStabilizationEnabled = true
        if let preview = settings.previewPhotoFormat { photoSettings.previewPhotoFormat = preview }
        photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
    }
    // Extreme low-light bracket (high-ISO stacking) — called from Bridge when bracketEnabled
    func captureBracketedPhoto(delegate: AVCapturePhotoCaptureDelegate) -> Bool {
        guard let eng = bracketEngine, let dev = videoDeviceInput?.device else { return false }
        let baseISO: Float = (isManualExposure && iso > 0) ? iso : dev.iso
        let baseDur: CMTime = (isManualExposure && shutterSpeed.isValid) ? shutterSpeed : dev.exposureDuration
        guard let bracket = eng.bracketSettings(for: dev, baseISO: baseISO, baseDuration: baseDur) else { return false }
        photoOutput.capturePhoto(with: bracket, delegate: delegate)
        return true
    }

    // MARK: - Video recording
    func startVideoRecording() {
        guard !movieOutput.isRecording else { return }
        // Ensure 4K if available
        sessionQueue.async {
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.hd4K3840x2160) { self.session.sessionPreset = .hd4K3840x2160 }
            self.session.commitConfiguration()
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        if let conn = movieOutput.connection(with: .video) {
            conn.videoOrientation = .portrait
            if conn.isVideoMirroringSupported { conn.isVideoMirrored = currentPosition == .front }
            // Enable stabilization if supported
            if conn.isVideoStabilizationSupported { conn.preferredVideoStabilizationMode = .auto }
        }
        movieOutput.startRecording(to: tmp, recordingDelegate: self)
    }

    func stopVideoRecording() {
        if movieOutput.isRecording { movieOutput.stopRecording() }
    }

    // MARK: - Utility: convert sampleBuffer -> processed CIImage for preview callback
    var onProcessedFrame: ((CIImage) -> Void)?

    // Quick device capabilities for UI
    var isoRange: ClosedRange<Float> {
        guard let d = videoDeviceInput?.device else { return 32...3200 }
        return d.activeFormat.minISO...d.activeFormat.maxISO
    }
    var shutterRange: ClosedRange<Double> {
        guard let d = videoDeviceInput?.device else { return 1/8000...1/30 }
        let minS = CMTimeGetSeconds(d.activeFormat.minExposureDuration)
        let maxS = CMTimeGetSeconds(d.activeFormat.maxExposureDuration)
        return minS...maxS
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension ProCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var ci = CIImage(cvPixelBuffer: pb)

        // 1) Filter pipeline (Core Image)
        if let pipe = filterPipeline, pipe.currentFilter != .none {
            ci = pipe.apply(to: ci)
        }
        // 2) Live color grading ( lift / gamma / gain + LUT )
        if colorGradingEnabled, let eng = colorGradingEngine, eng.isEnabled {
            ci = eng.process(ciImage: ci)
        }
        // 3) Low-light boost via ANE (CoreML + MPS) - throttled to 15 fps internally
        // Metrics-synchronized: enhancer keeps LOE/NIQE guard internally; we also emit live LOE/NIQE every 1s for UI
        if lowLightBoostEnabled, let enh = lowLightEnhancer {
            // Sync target metric
            if enh.targetMetric != lowLightTarget { enh.targetMetric = lowLightTarget }
            if enh.shouldEnhance(pixelBuffer: pb) {
                if let enhanced = enh.enhance(ciImage: ci, pixelBuffer: pb) {
                    // Optional live metrics (1 fps) without hurting preview
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastMetricsTime > 1.0 {
                        lastMetricsTime = now
                        let rpt = LowLightMetrics.shared.report(output: enhanced, reference: nil, input: ci, context: CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!))
                        DispatchQueue.main.async { self.onMetricsUpdate?(rpt) }
                    }
                    ci = enhanced
                }
            }
        }
        // 4) Zoom-aware sharpness (improves MTF50/SSIM at 1.5-6× digital, NIQE-safe)
        if let zs = zoomSharpnessEngine {
            let isDigital = zoomFactor > zs.maxOpticalZoom * 0.9
            ci = zs.process(ciImage: ci, zoomFactor: zoomFactor, isDigital: isDigital)
        }
        onProcessedFrame?(ci)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension ProCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            if error == nil {
                self.recordedVideoURL = outputFileURL
                // Save to photo library is handled by bridge / UI
            } else {
                print("[ProCamera] recording error \(String(describing: error))")
            }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { self.isRecording = true }
    }
}

struct PhotoSettings {
    var flashMode: AVCaptureDevice.FlashMode = .auto
    var previewPhotoFormat: [String: Any]? = nil
}
