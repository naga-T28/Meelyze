import Foundation
import SwiftUI

#if targetEnvironment(simulator)

/// Simulator専用の`CameraService`実装。iOS Simulatorには実カメラSessionがなく
/// `AVFoundationCameraService`は`CameraServiceError.deviceUnavailable`をthrowするため、実機なしで
/// Simulator上から実際の`VisionOCRService`（本物のVision OCR）の挙動を手動確認できるよう、
/// `Meelyze/DebugResources/SimulatorMenuPhotos/`に置かれた画像を撮影結果の代わりに返す。
///
/// `#if targetEnvironment(simulator)`でコンパイル時に実機ビルドから除外されるため、実機では常に
/// `AVFoundationCameraService`が使われる（`Meelyze/Views/RootView.swift`参照）。OCR自体はスタブに
/// 差し替えない。固定のOCR結果で確認したい場合は`UITEST_OCR_STUB_MODE`（`UITestScanStubs.swift`）を使う。
@MainActor
final class SimulatorCameraService: CameraService {
    private var nextImageIndex = 0

    func authorizationStatus() -> CameraAuthorizationStatus { .authorized }
    func requestAuthorization() async -> CameraAuthorizationStatus { .authorized }
    func startSession() async throws {}
    func stopSession() {}

    /// フォルダ内の画像をファイル名順で1枚ずつ返す（末尾まで行くと先頭へ戻る）。画像が1枚もない
    /// 場合は、実機でカメラデバイスがない場合と同じ`CameraServiceError.deviceUnavailable`をthrowし、
    /// 既存のE01フォールバック（`ScanViewModel`）へそのまま乗せる。
    func capturePhoto() async throws -> Data {
        let urls = Self.sampleImageURLs
        guard !urls.isEmpty else {
            throw CameraServiceError.deviceUnavailable
        }
        let url = urls[nextImageIndex % urls.count]
        nextImageIndex += 1
        return try Data(contentsOf: url)
    }

    func makePreviewView() -> AnyView {
        AnyView(SimulatorCameraPreviewPlaceholder(imageCount: Self.sampleImageURLs.count))
    }

    private static var sampleImageURLs: [URL] {
        guard let directoryURL = Bundle.main.url(forResource: "SimulatorMenuPhotos", withExtension: nil) else {
            return []
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
        return contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// 実カメラプレビューの代わりに表示する、Simulatorモードであることを示すプレースホルダ。
private struct SimulatorCameraPreviewPlaceholder: View {
    let imageCount: Int

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                Text("Simulator Mode")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(
                    imageCount > 0
                        ? "Tap the shutter to load a sample image (\(imageCount) available)"
                        : "Add images to Meelyze/DebugResources/SimulatorMenuPhotos to test"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
    }
}

#endif
