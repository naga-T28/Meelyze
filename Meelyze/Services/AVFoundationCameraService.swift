@preconcurrency import AVFoundation
import SwiftUI

/// `CameraService`のAVFoundation実装。`AVCaptureSession`の構成、カメラ権限の確認・要求、
/// `AVCapturePhotoOutput`による撮影、プレビュー表示を扱う。
///
/// 撮影した画像データはメモリ上でのみ扱い、本Service自体はディスク・SwiftDataへの保存を行わない
/// （`docs/ui-design.md`「画像の非永続化」方針）。AVFoundationへの依存はこのファイル（Services層）に
/// 閉じ込め、`makePreviewView()`は`AnyView`のみを返すためViewModel/ViewはAVFoundationを直接importしない。
@MainActor
final class AVFoundationCameraService: NSObject, CameraService {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isSessionConfigured = false
    private var photoCaptureContinuation: CheckedContinuation<Data, Error>?

    func authorizationStatus() -> CameraAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video).asCameraAuthorizationStatus
    }

    func requestAuthorization() async -> CameraAuthorizationStatus {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        guard current == .notDetermined else { return current.asCameraAuthorizationStatus }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    func startSession() async throws {
        if !isSessionConfigured {
            try configureSession()
        }
        guard !session.isRunning else { return }
        let session = self.session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                continuation.resume()
            }
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    func capturePhoto() async throws -> Data {
        guard photoCaptureContinuation == nil else {
            throw CameraServiceError.captureFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            photoCaptureContinuation = continuation
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func makePreviewView() -> AnyView {
        AnyView(CameraSessionPreviewView(session: session))
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw CameraServiceError.deviceUnavailable
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            throw CameraServiceError.deviceUnavailable
        }
        session.addOutput(photoOutput)

        isSessionConfigured = true
    }
}

extension AVFoundationCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            let continuation = photoCaptureContinuation
            photoCaptureContinuation = nil
            if let error {
                continuation?.resume(throwing: error)
            } else if let data = photo.fileDataRepresentation() {
                continuation?.resume(returning: data)
            } else {
                continuation?.resume(throwing: CameraServiceError.captureFailed)
            }
        }
    }
}

/// `AVFoundationCameraService`固有のエラー。
enum CameraServiceError: Error, Equatable {
    /// カメラデバイスを利用できない場合（Simulator等、実カメラがない環境を含む）。
    case deviceUnavailable
    /// 撮影処理自体が失敗した場合（多重撮影要求を含む）。
    case captureFailed
}

/// `AVCaptureSession`のライブプレビューをSwiftUIへ橋渡しするUIViewRepresentable。AVFoundationへの
/// 依存をServices層に閉じ込めるため`private`とし、`CameraService.makePreviewView()`経由でのみ
/// 利用できるようにする。
private struct CameraSessionPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {}
}

private final class PreviewLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("PreviewLayerView.layerClass must be AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}

private extension AVAuthorizationStatus {
    var asCameraAuthorizationStatus: CameraAuthorizationStatus {
        switch self {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
