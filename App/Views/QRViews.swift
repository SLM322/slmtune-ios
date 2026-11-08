import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum QRCode {
    /// A QR code for a share link (the "Поделиться" screen).
    static func image(for text: String, size: CGFloat = 280) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scale = size / out.extent.width
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Text of the first QR code in a picture (a screenshot of a subscription page, a photo).
    static func decode(imageData: Data) -> String? {
        guard let ci = CIImage(data: imageData),
              let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return det.features(in: ci).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

/// Camera QR scanner (needs NSCameraUsageDescription).
struct QRScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false

    var body: some View {
        NavigationStack {
            ZStack {
                if denied {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Slm.accent2)
                        Text("Нет доступа к камере").font(.headline)
                        Text("Разрешите камеру для SLMtune в Настройках iOS.").foregroundStyle(Slm.text2)
                        Button("Открыть Настройки") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }
                    }
                    .padding()
                } else {
                    CameraScanner(onCode: onCode, onDenied: { denied = true }).ignoresSafeArea()
                    RoundedRectangle(cornerRadius: 24).stroke(Slm.accent2, lineWidth: 3).frame(width: 250, height: 250)
                }
            }
            .background(Color.black)
            .navigationTitle("QR-код")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

private struct CameraScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onDenied: () -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onCode = onCode
        c.onDenied = onDenied
        return c
    }

    func updateUIViewController(_ c: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onDenied: (() -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { ok ? self.setup() : self.onDenied?() }
        }
    }

    private func setup() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { onDenied?(); return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { DispatchQueue.global().async { self.session.stopRunning() } }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }
}

/// A share link as text + QR code, for moving a server to another device.
struct ShareServerView: View {
    let link: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let img = QRCode.image(for: link) {
                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 280).padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }
                Text(link).font(.system(.caption, design: .monospaced)).foregroundStyle(Slm.text2).lineLimit(4).textSelection(.enabled)
                HStack {
                    Button { UIPasteboard.general.string = link } label: { Label("Копировать", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderedProminent)
                    ShareLink(item: link) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }
                Hint("В ссылке пароль от сервера — отправляйте её только тем, кому доверяете.")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Slm.ink)
            .navigationTitle("Поделиться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}
