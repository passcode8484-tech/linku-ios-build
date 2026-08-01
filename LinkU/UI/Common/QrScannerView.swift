import AVFoundation
import PhotosUI
import SwiftUI

/// 摄像头取景 + 元数据识别，对应 android-native ui/common/QrScannerScreen.kt 里 CameraX +
/// ML Kit/zxing 那部分。iOS 上用 AVFoundation 原生的 AVCaptureMetadataOutput 识别二维码，
/// 不需要额外的第三方扫码库。
final class QrCaptureViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var didEmit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didEmit = false
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer.addSublayer(previewLayer)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmit,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        didEmit = true
        onScan?(value)
    }
}

private struct QrCaptureRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QrCaptureViewController {
        let controller = QrCaptureViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: QrCaptureViewController, context: Context) {}
}

/// 从相册选一张图识别二维码，用 Vision 而不是又拉一个第三方解码库。
enum QrImageDecoder {
    static func decode(_ image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: CIContext(),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: ciImage) ?? []
        for case let feature as CIQRCodeFeature in features {
            if let message = feature.messageString { return message }
        }
        return nil
    }
}

struct QrScannerView: View {
    let title: String
    let onResult: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var decodeError: String?

    var body: some View {
        ZStack {
            QrCaptureRepresentable { value in
                onResult(value)
                dismiss()
            }
            .ignoresSafeArea()

            VStack {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 240, height: 240)
                    .padding(.top, 80)
                Spacer()
                if let decodeError {
                    Text(decodeError)
                        .foregroundStyle(.white)
                        .font(.footnote)
                        .padding(.bottom, 8)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 40)
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let value = QrImageDecoder.decode(image) {
                    decodeError = nil
                    onResult(value)
                    dismiss()
                } else {
                    decodeError = "未能从该图片识别出二维码"
                }
            }
        }
    }
}
