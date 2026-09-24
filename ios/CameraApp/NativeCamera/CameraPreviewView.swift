import SwiftUI
import AVFoundation
import CoreImage

final class PreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    private var ciImageView: UIImageView?
    func attach(session: AVCaptureSession) {
        if previewLayer == nil {
            let pl = AVCaptureVideoPreviewLayer(session: session)
            pl.videoGravity = .resizeAspectFill
            pl.frame = bounds
            layer.addSublayer(pl)
            previewLayer = pl
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        ciImageView?.frame = bounds
    }
    func crossfade(duration: CFTimeInterval = 0.28) {
        let t = CATransition()
        t.type = .fade
        t.duration = duration
        t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(t, forKey: "seamlessSwitch")
        previewLayer?.add(t, forKey: "seamlessSwitch")
        ciImageView?.layer.add(t, forKey: "seamlessSwitch")
        alpha = 1
    }
    func display(ciImage: CIImage, ciContext: CIContext) {
        if ciImageView == nil {
            let iv = UIImageView(frame: bounds)
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            addSubview(iv)
            ciImageView = iv
        }
        guard let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        DispatchQueue.main.async {
            self.ciImageView?.image = UIImage(cgImage: cg)
            self.ciImageView?.isHidden = false
            self.previewLayer?.isHidden = true
        }
    }
    func showPreviewLayerOnly() {
        DispatchQueue.main.async {
            self.ciImageView?.isHidden = true
            self.previewLayer?.isHidden = false
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var manager: ProCameraManager
    var ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.attach(session: manager.session)
        manager.onSeamlessSwitch = { DispatchQueue.main.async { v.crossfade() } }
        manager.onProcessedFrame = { ci in
            let needsOverlay = manager.colorGradingEnabled || manager.filterPipeline?.currentFilter != .none || manager.lowLightBoostEnabled
            if needsOverlay { v.display(ciImage: ci, ciContext: ciContext) } else { v.showPreviewLayerOnly() }
        }
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer?.connection?.videoOrientation = .portrait
    }
}

struct FocusTapView: View {
    var point: CGPoint
    var body: some View {
        Circle().stroke(Color.yellow, lineWidth: 2)
            .frame(width: 80, height: 80)
            .position(point)
            .animation(.easeOut(duration: 0.3), value: point)
    }
}
