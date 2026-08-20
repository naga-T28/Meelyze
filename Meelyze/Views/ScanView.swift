import SwiftUI
import UIKit

/// S06 メニュー撮影画面。カメラプレビューをsafe areaまで広げ、撮影ガイドとシャッターボタンを重ねる
/// （`docs/ui-design.md`「Navigation」方針によりS06は`fullScreenCover`を使わない）。撮影→OCR実行の
/// 結果が0件・失敗の場合はE01（`OCRFailureView`）へ切り替える。
///
/// カメラ・OCRへのアクセスは`CameraService` `OCRService`経由（`ScanViewModel`が保持）にとどめ、
/// AVFoundation・Visionを直接importしない。
struct ScanView: View {
    @State private var viewModel: ScanViewModel
    let displayLanguage: DisplayLanguage

    init(displayLanguage: DisplayLanguage, cameraService: CameraService, ocrService: OCRService) {
        self.displayLanguage = displayLanguage
        self._viewModel = State(initialValue: ScanViewModel(cameraService: cameraService, ocrService: ocrService))
    }

    var body: some View {
        Group {
            switch viewModel.scanState {
            case .failed:
                OCRFailureView(displayLanguage: displayLanguage) {
                    viewModel.retake()
                }
            case .idle, .capturing, .recognizing, .recognized:
                cameraContent
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .alert(
            ScanViewText.permissionDeniedTitle.value(for: displayLanguage),
            isPresented: $viewModel.isShowingPermissionDeniedAlert
        ) {
            Button(ScanViewText.openSettings.value(for: displayLanguage)) {
                openSettings()
            }
            Button(ScanViewText.cancel.value(for: displayLanguage), role: .cancel) {}
        } message: {
            Text(ScanViewText.permissionDeniedMessage.value(for: displayLanguage))
        }
    }

    private var cameraContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            viewModel.cameraPreviewView
                .ignoresSafeArea()

            CameraGuideOverlayView(message: ScanViewText.guideMessage.value(for: displayLanguage))

            #if DEBUG
            if case .recognized(let result) = viewModel.scanState {
                VStack {
                    Spacer()
                    DebugOCRResultOverlay(result: result)
                        .padding(.bottom, 120)
                }
            }
            #endif

            VStack {
                Spacer()
                ShutterButtonView {
                    Task { await viewModel.capturePhoto() }
                }
                .disabled(viewModel.isBusy)
                .padding(.bottom, 32)
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// `ScanView`の画面chrome文言。MVP対象4言語で固定の意味を維持する。
private enum ScanViewText {
    static let guideMessage = LocalizedText(
        english: "Fit the menu within the frame",
        traditionalChinese: "請將菜單對齊框內",
        simplifiedChinese: "请将菜单对齐框内",
        korean: "메뉴를 프레임 안에 맞춰주세요"
    )

    static let permissionDeniedTitle = LocalizedText(
        english: "Camera access is not allowed",
        traditionalChinese: "無法使用相機",
        simplifiedChinese: "无法使用相机",
        korean: "카메라를 사용할 수 없습니다"
    )

    static let permissionDeniedMessage = LocalizedText(
        english: "To scan a menu, allow camera access for Meelyze in Settings.",
        traditionalChinese: "請至「設定」允許Meelyze使用相機以拍攝菜單。",
        simplifiedChinese: "请至“设置”允许Meelyze使用相机以拍摄菜单。",
        korean: "메뉴를 촬영하려면 설정에서 Meelyze의 카메라 접근을 허용해주세요."
    )

    static let openSettings = LocalizedText(
        english: "Open Settings",
        traditionalChinese: "前往設定",
        simplifiedChinese: "前往设置",
        korean: "설정으로 이동"
    )

    static let cancel = LocalizedText(
        english: "Cancel",
        traditionalChinese: "取消",
        simplifiedChinese: "取消",
        korean: "취소"
    )
}

#if DEBUG
/// デバッグ専用の簡易表示。OCR成功時（`.recognized`）に認識できた文字列とConfidenceを一覧表示し、
/// シャッター操作が実際にOCRまで到達しているかを手動テストで確認できるようにする。
///
/// S07（解析中）・S08（判定結果オーバーレイ）は別Issue（#19・#20）の担当範囲であり、本Viewはそれらの
/// 代替ではない。`#if DEBUG`でRelease/実配布ビルドからは常に除外される一時的な開発補助であり、
/// `docs/ui-design.md`のS06/E01デザインの一部ではない。
private struct DebugOCRResultOverlay: View {
    let result: OCRResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG: \(result.observations.count) text(s) recognized")
                .font(.caption.bold())
                .foregroundStyle(.yellow)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(result.observations.enumerated()), id: \.offset) { _, observation in
                        Text("\(observation.text)  (\(String(format: "%.2f", observation.confidence)))")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(10)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("DebugOCRResultOverlay")
    }
}
#endif

#Preview {
    ScanView(displayLanguage: .english, cameraService: PreviewCameraService(), ocrService: PreviewOCRService())
}

/// Preview専用の`CameraService`スタブ。実際のカメラ・権限フローには接続しない。
private final class PreviewCameraService: CameraService {
    func authorizationStatus() -> CameraAuthorizationStatus { .authorized }
    func requestAuthorization() async -> CameraAuthorizationStatus { .authorized }
    func startSession() async throws {}
    func stopSession() {}
    func capturePhoto() async throws -> Data { Data() }
    func makePreviewView() -> AnyView { AnyView(Color.black) }
}

/// Preview専用の`OCRService`スタブ。
private struct PreviewOCRService: OCRService {
    func recognizeText(in imageData: Data) async throws -> OCRResult {
        OCRResult(observations: [])
    }
}
