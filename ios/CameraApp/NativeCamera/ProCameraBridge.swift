import Foundation
import React
import AVFoundation
import Photos

@objc(ProCameraModule)
class ProCameraModule: NSObject, RCTBridgeModule {
    static func moduleName() -> String! { "ProCameraModule" }
    static func requiresMainQueueSetup() -> Bool { true }

    private var manager: ProCameraManager?

    func managerInstance() -> ProCameraManager {
        if let m = manager { return m }
        let m = ProCameraManager()
        m.colorGradingEngine = ColorGradingEngine()
        m.filterPipeline = FilterPipeline()
        if let enh = LowLightEnhancer() { m.lowLightEnhancer = enh }
        if let zs = ZoomSharpnessEngine(device: MTLCreateSystemDefaultDevice()) { m.zoomSharpnessEngine = zs }
        if let br = BracketEngine(device: MTLCreateSystemDefaultDevice()) { m.bracketEngine = br }
        m.checkPermissionAndSetup()
        manager = m
        return m
    }

    @objc func capturePhoto(_ options: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        let m = managerInstance()
        let flash: AVCaptureDevice.FlashMode = (options["flash"] as? String) == "on" ? .on : (options["flash"] as? String) == "off" ? .off : .auto
        if m.bracketEnabled, m.bracketEngine != nil {
            let del = BracketPhotoDelegate(resolve: resolve, reject: reject, manager: m)
            objc_setAssociatedObject(m, "photoDelegate", del, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if m.captureBracketedPhoto(delegate: del) { return }
        }
        let delegate = PhotoDelegate(resolve: resolve, reject: reject, manager: m)
        objc_setAssociatedObject(m, "photoDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        m.capturePhoto(with: PhotoSettings(flashMode: flash), delegate: delegate)
    }
    @objc func setBracketMode(_ enabled: NSNumber, count: NSNumber, iso: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        m.bracketEnabled = enabled.boolValue
        if let eng = m.bracketEngine {
            eng.count = max(3, min(7, count.intValue))
            eng.targetISO = iso.floatValue > 0 ? iso.floatValue : 6400
        } else if let d = MTLCreateSystemDefaultDevice(), let eng = BracketEngine(device: d) {
            eng.count = max(3, min(7, count.intValue)); eng.targetISO = iso.floatValue > 0 ? iso.floatValue : 6400
            m.bracketEngine = eng
        }
        resolve(["bracket": enabled, "count": count, "iso": iso, "effectiveGainDB": m.bracketEngine?.snrGainDB ?? 0])
    }
    @objc func getBracketInfo(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        resolve(["enabled": m.bracketEnabled, "count": m.bracketEngine?.count ?? 5, "targetISO": m.bracketEngine?.targetISO ?? 6400, "effectiveISO": m.bracketEngine?.effectiveISO ?? 6400, "snrGainDB": m.bracketEngine?.snrGainDB ?? 0])
    }

    @objc func startRecording(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        let m = managerInstance()
        m.startVideoRecording()
        resolve(["started": true])
    }

    @objc func stopRecording(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        let m = managerInstance()
        m.stopVideoRecording()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let url = m.recordedVideoURL?.absoluteString {
                resolve(["url": url])
            } else { resolve(["url": NSNull()]) }
        }
    }

    @objc func switchCamera(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().switchCamera()
        resolve(["switched": true])
    }

    @objc func setZoom(_ zoom: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().setZoom(CGFloat(truncating: zoom))
        resolve(["zoom": zoom, "range": ["min": 1, "max": managerInstance().zoomRange.upperBound]])
    }
    @objc func setSharpness(_ intensity: NSNumber, preset: NSString, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().setSharpness(intensity: intensity.floatValue, preset: preset as String)
        resolve(["sharpness": intensity, "preset": preset])
    }
    @objc func setSuperResolution(_ enabled: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().setSuperResolution(enabled: enabled.boolValue)
        resolve(["superRes": enabled])
    }
    @objc func getZoomInfo(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        let back = m.adaptiveLens.lensesBack.map{ ["id": $0.id, "label": $0.label, "nominal": $0.nominalZoom] }
        resolve(["zoom": m.zoomFactor, "min": m.zoomRange.lowerBound, "max": m.zoomRange.upperBound, "opticalThreshold": m.opticalZoomThreshold, "sharpness": m.zoomSharpnessEngine?.sharpness ?? 0.5, "activeLens": m.activeLens, "seamless": m.seamlessEnabled, "switchFactors": m.virtualSwitchFactors, "lensesBack": back, "isSeamlessAvailable": m.adaptiveLens.isSeamlessAvailable(for: m.currentPosition)])
    }
    @objc func setSeamlessEnabled(_ enabled: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().setSeamlessEnabled(enabled.boolValue)
        resolve(["seamless": enabled])
    }
    @objc func getLensInfo(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        let back = m.adaptiveLens.lensesBack.map{ ["id": $0.id, "label": $0.label, "nominal": $0.nominalZoom, "type": $0.deviceType.rawValue] }
        let front = m.adaptiveLens.lensesFront.map{ ["id": $0.id, "label": $0.label, "nominal": $0.nominalZoom] }
        resolve(["activeLens": m.activeLens, "factors": m.virtualSwitchFactors, "position": m.currentPosition == .back ? "back" : "front", "seamless": m.seamlessEnabled, "isSeamlessAvailable": m.adaptiveLens.isSeamlessAvailable(for: m.currentPosition), "lensesBack": back, "lensesFront": front])
    }

    @objc func setManualExposure(_ iso: NSNumber, shutterMs: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        let isoF = iso.floatValue > 0 ? iso.floatValue : nil
        let shutter: CMTime? = shutterMs.doubleValue > 0 ? CMTimeMakeWithSeconds(shutterMs.doubleValue/1000.0, preferredTimescale: 1_000_000) : nil
        m.setManualExposure(iso: isoF, shutter: shutter)
        resolve(["ok": true])
    }

    @objc func setManualFocus(_ pos: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().setManualFocus(lensPosition: pos.floatValue)
        resolve(["ok": true])
    }

    @objc func setWhiteBalance(_ r: NSNumber, g: NSNumber, b: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        var gains = AVCaptureDevice.WhiteBalanceGains(redGain: r.floatValue, greenGain: g.floatValue, blueGain: b.floatValue)
        managerInstance().setWhiteBalance(gains: gains)
        resolve(["ok": true])
    }

    @objc func setGrading(_ params: NSDictionary, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        guard let eng = m.colorGradingEngine else { resolve(["ok": false]); return }
        if let v = params["exposure"] as? NSNumber { eng.params.exposure = v.floatValue }
        if let v = params["contrast"] as? NSNumber { eng.params.contrast = v.floatValue }
        if let v = params["saturation"] as? NSNumber { eng.params.saturation = v.floatValue }
        if let v = params["temperature"] as? NSNumber { eng.params.temperature = v.floatValue }
        if let v = params["tint"] as? NSNumber { eng.params.tint = v.floatValue }
        if let v = params["shadows"] as? NSNumber { eng.params.shadows = v.floatValue }
        if let v = params["highlights"] as? NSNumber { eng.params.highlights = v.floatValue }
        if let v = params["vibrance"] as? NSNumber { eng.params.vibrance = v.floatValue }
        if let v = params["hue"] as? NSNumber { eng.params.hue = v.floatValue }
        if let v = params["lutIntensity"] as? NSNumber { eng.params.lutIntensity = v.floatValue }
        if let v = params["enabled"] as? Bool { eng.isEnabled = v; m.colorGradingEnabled = v }
        if let lift = params["lift"] as? [NSNumber], lift.count==3 { eng.setLift(lift[0].floatValue, lift[1].floatValue, lift[2].floatValue) }
        if let gamma = params["gamma"] as? [NSNumber], gamma.count==3 { eng.setGamma(gamma[0].floatValue, gamma[1].floatValue, gamma[2].floatValue) }
        if let gain = params["gain"] as? [NSNumber], gain.count==3 { eng.setGain(gain[0].floatValue, gain[1].floatValue, gain[2].floatValue) }
        resolve(["ok": true])
    }
    @objc func setLUTIntensity(_ intensity: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().colorGradingEngine?.setLUTIntensity(intensity.floatValue)
        resolve(["intensity": intensity])
    }
    @objc func listLUTs(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(managerInstance().colorGradingEngine?.availableLUTs() ?? [])
    }
    @objc func clearLUT(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().colorGradingEngine?.clearLUT()
        resolve(["cleared": true])
    }
    @objc func exportPreset(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(["json": managerInstance().colorGradingEngine?.exportPresetJSON() ?? "{}"])
    }
    @objc func importPreset(_ json: NSString, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let ok = managerInstance().colorGradingEngine?.importPresetJSON(json as String) ?? false
        resolve(["imported": ok])
    }
    @objc func bakeLUT(_ name: NSString, size: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let url = managerInstance().colorGradingEngine?.saveBakedLUTToDocuments(name: name as String, size: size.intValue)
        resolve(["url": url?.absoluteString ?? NSNull(), "saved": url != nil])
    }
    @objc func getLUTInfo(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let eng = managerInstance().colorGradingEngine
        resolve(["name": eng?.currentLUTName ?? NSNull(), "intensity": eng?.params.lutIntensity ?? 1, "enabled": eng?.isEnabled ?? false])
    }

    @objc func setFilter(_ name: NSString, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        if let f = CameraFilter(rawValue: name as String) { m.filterPipeline?.currentFilter = f }
        resolve(["filter": name])
    }

    @objc func setLowLightBoost(_ enabled: NSNumber, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        managerInstance().lowLightBoostEnabled = enabled.boolValue
        resolve(["enabled": enabled])
    }

    @objc func setLowLightStrategy(_ strategy: NSString, target: NSString, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        if let enh = m.lowLightEnhancer {
            if let s = LowLightEnhancer.Strategy(rawValue: strategy as String) { enh.strategy = s }
            switch (target as String).lowercased() {
            case "psnr": enh.targetMetric = .psnr
            case "perceptual", "lpips": enh.targetMetric = .perceptual
            case "natural", "niqe", "loe": enh.targetMetric = .natural
            default: enh.targetMetric = .balanced
            }
            m.lowLightTarget = enh.targetMetric
        }
        resolve(["strategy": strategy, "target": target])
    }

    @objc func getLowLightMetrics(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        let enh = m.lowLightEnhancer
        resolve([
            "strategy": enh?.strategy.rawValue ?? "auto",
            "target": "\(String(describing: enh?.targetMetric))",
            "intensity": enh?.intensity ?? 0,
            "isANE": enh?.isANEPreferred ?? false
        ])
    }

    @objc func loadLUT(_ path: NSString, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let m = managerInstance()
        var url = URL(fileURLWithPath: path as String)
        var ok = m.colorGradingEngine?.loadLUT(url: url) ?? false
        if !ok, let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let alt = docs.appendingPathComponent(path as String)
            ok = m.colorGradingEngine?.loadLUT(url: alt) ?? false
            if ok { url = alt }
        }
        if !ok { ok = m.colorGradingEngine?.loadLUT(named: (path as String).replacingOccurrences(of: ".cube", with: "")) ?? false }
        resolve(["loaded": ok, "name": m.colorGradingEngine?.currentLUTName ?? NSNull()])
    }
}

private class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let resolve: RCTPromiseResolveBlock
    let reject: RCTPromiseRejectBlock
    let manager: ProCameraManager
    init(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock, manager: ProCameraManager) {
        self.resolve = resolve; self.reject = reject; self.manager = manager
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { reject("capture_error", error.localizedDescription, error); return }
        guard let data = photo.fileDataRepresentation(), var image = UIImage(data: data) else { reject("capture_error", "no data", nil); return }
        if let pipe = manager.filterPipeline { image = pipe.applyToStill(image) }
        if let eng = manager.colorGradingEngine, eng.isEnabled, let ci = CIImage(image: image) {
            let graded = eng.process(ciImage: ci)
            let ctx = CIContext()
            if let cg = ctx.createCGImage(graded, from: graded.extent) { image = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation) }
        }
        let doZoomSharpen: (UIImage) -> Void = { img in
            guard let zs = self.manager.zoomSharpnessEngine, self.manager.zoomFactor > 1.05, let ci = CIImage(image: img) else { self.finalize(img); return }
            zs.enhanceStill(image: ci, zoomFactor: self.manager.zoomFactor) { outCI in
                let ctx = CIContext()
                if let cg = ctx.createCGImage(outCI, from: outCI.extent) {
                    let sharpened = UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation)
                    self.finalize(sharpened)
                } else { self.finalize(img) }
            }
        }
        if manager.lowLightBoostEnabled, let enh = manager.lowLightEnhancer, let ci = CIImage(image: image) {
            enh.enhanceStill(image: ci) { outCI in
                if let out = outCI {
                    let ctx = CIContext()
                    if let cg = ctx.createCGImage(out, from: out.extent) {
                        let enhanced = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
                        doZoomSharpen(enhanced); return
                    }
                }
                doZoomSharpen(image)
            }
        } else {
            doZoomSharpen(image)
        }
    }
    private func finalize(_ finalImage: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try? finalImage.jpegData(compressionQuality: 0.92)?.write(to: url)
                DispatchQueue.main.async { self.resolve(["uri": url.absoluteString, "saved": false]) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: finalImage)
            }) { success, err in
                DispatchQueue.main.async {
                    if success {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                        try? finalImage.jpegData(compressionQuality: 0.92)?.write(to: url)
                        self.resolve(["uri": url.absoluteString, "saved": true])
                    } else { self.reject("save_error", err?.localizedDescription ?? "unknown", err) }
                }
            }
        }
    }
}

private class BracketPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let resolve: RCTPromiseResolveBlock
    let reject: RCTPromiseRejectBlock
    let manager: ProCameraManager
    private var images: [CIImage] = []
    private let expected: Int
    private var didReject = false
    init(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock, manager: ProCameraManager) {
        self.resolve = resolve; self.reject = reject; self.manager = manager
        self.expected = manager.bracketEngine?.count ?? 5
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error, !didReject { didReject = true; reject("bracket_error", error.localizedDescription, error); return }
        guard let data = photo.fileDataRepresentation(), let ui = UIImage(data: data), let ci = CIImage(image: ui) else {
            if images.count + 1 >= expected { fuseAndFinish() }
            return
        }
        images.append(ci)
        if images.count >= expected { fuseAndFinish() }
        if images.count == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now()+1.2) { if self.images.count < self.expected && self.images.count > 1 { self.fuseAndFinish() } }
        }
    }
    private var fused = false
    private func fuseAndFinish() {
        guard !fused else { return }; fused = true
        guard let engine = manager.bracketEngine else { fallbackSingle(); return }
        let toFuse = images
        engine.fuse(images: toFuse) { fusedCI in
            guard let ci = fusedCI else { self.fallbackSingle(); return }
            self.processFused(ci)
        }
    }
    private func fallbackSingle() {
        guard let first = images.first else { reject("bracket_error","no frames",nil); return }
        processFused(first)
    }
    private func processFused(_ ci: CIImage) {
        var outCI = ci
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(outCI, from: outCI.extent) else { finalize(UIImage(ciImage: outCI)); return }
        var img = UIImage(cgImage: cg)
        if let pipe = manager.filterPipeline { img = pipe.applyToStill(img) }
        if let eng = manager.colorGradingEngine, eng.isEnabled, let ci2 = CIImage(image: img) {
            let graded = eng.process(ciImage: ci2)
            if let cg2 = ctx.createCGImage(graded, from: graded.extent) { img = UIImage(cgImage: cg2, scale: img.scale, orientation: img.imageOrientation) }
        }
        if manager.lowLightBoostEnabled, let enh = manager.lowLightEnhancer, let ci3 = CIImage(image: img) {
            enh.enhanceStill(image: ci3) { out in
                if let o = out, let cg3 = ctx.createCGImage(o, from: o.extent) {
                    let enhanced = UIImage(cgImage: cg3, scale: img.scale, orientation: img.imageOrientation)
                    self.doZoomSharpen(enhanced)
                } else { self.doZoomSharpen(img) }
            }
        } else { doZoomSharpen(img) }
    }
    private func doZoomSharpen(_ img: UIImage) {
        guard let zs = manager.zoomSharpnessEngine, manager.zoomFactor > 1.05, let ci = CIImage(image: img) else { finalize(img); return }
        zs.enhanceStill(image: ci, zoomFactor: manager.zoomFactor) { outCI in
            let ctx = CIContext()
            if let cg = ctx.createCGImage(outCI, from: outCI.extent) {
                finalize(UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation))
            } else { finalize(img) }
        }
    }
    private func finalize(_ finalImage: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try? finalImage.jpegData(compressionQuality: 0.92)?.write(to: url)
                DispatchQueue.main.async { self.resolve(["uri": url.absoluteString, "saved": false, "bracket": self.images.count, "effectiveISO": self.manager.bracketEngine?.effectiveISO ?? 0]) }
                return
            }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: finalImage) }) { success, err in
                DispatchQueue.main.async {
                    if success {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                        try? finalImage.jpegData(compressionQuality: 0.92)?.write(to: url)
                        self.resolve(["uri": url.absoluteString, "saved": true, "bracket": self.images.count, "effectiveISO": self.manager.bracketEngine?.effectiveISO ?? 0])
                    } else { self.reject("save_error", err?.localizedDescription ?? "unknown", err) }
                }
            }
        }
    }
}
