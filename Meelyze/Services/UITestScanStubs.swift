import Foundation
import SwiftUI

/// UI Testからカメラ・OCRの実機依存（実カメラ・実Vision実行）を排除するためのスタブ実装。
///
/// `UITEST_OCR_STUB_MODE`環境変数が指定された場合にのみ`RootView`がこれらへ差し替える
/// （`Meelyze/MeelyzeApp.swift`の`UITEST_STORE_IDENTIFIER`と同じ、UI Test専用フックのパターン）。
/// Simulatorには実カメラがなくOCR0件・成功のシナリオを実カメラ・実Visionで再現できないため、
/// `MeelyzeUITests/ScanOCRFailureUITests.swift`がE01（OCR失敗）と非E01（OCR成功）の両方を
/// 決定的に検証できるようにする。

/// 撮影が常に成功する`CameraService`スタブ。実際のカメラ・権限フローには接続しない。
@MainActor
final class StubCameraService: CameraService {
    func authorizationStatus() -> CameraAuthorizationStatus { .authorized }
    func requestAuthorization() async -> CameraAuthorizationStatus { .authorized }
    func startSession() async throws {}
    func stopSession() {}
    func capturePhoto() async throws -> Data { Data([0x00]) }
    func makePreviewView() -> AnyView { AnyView(Color.black) }
}

/// 固定の結果を返す`OCRService`スタブ。
struct StubOCRService: OCRService {
    enum Mode: String {
        /// OCRが0件抽出（E01フォールバックUIが表示されることを検証する）。
        case empty
        /// OCRが1件以上取得できた（E01が表示されないことを検証する）。
        case success
    }

    let mode: Mode

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        switch mode {
        case .empty:
            return OCRResult(observations: [])
        case .success:
            return OCRResult(observations: [
                RecognizedTextObservation(
                    text: "唐揚げ定食",
                    confidence: 0.9,
                    boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)
                )
            ])
        }
    }
}
