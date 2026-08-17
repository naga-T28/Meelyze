import SwiftUI
import UIKit

/// S06 メニュー撮影画面。カメラプレビューをsafe areaまで広げ、撮影ガイドとシャッターボタンを重ねる
/// （`docs/ui-design.md`「Navigation」方針によりS06は`fullScreenCover`を使わない）。
///
/// カメラ・OCRへのアクセスは`CameraService`経由（`ScanViewModel`が保持）にとどめ、AVFoundationを
/// 直接importしない。OCR実行・OCR失敗時のフォールバックUI（E01）はTASK-022で追加する。
struct ScanView: View {
    @State private var viewModel: ScanViewModel
    let displayLanguage: DisplayLanguage

    init(displayLanguage: DisplayLanguage, cameraService: CameraService) {
        self.displayLanguage = displayLanguage
        self._viewModel = State(initialValue: ScanViewModel(cameraService: cameraService))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            viewModel.cameraPreviewView
                .ignoresSafeArea()

            CameraGuideOverlayView(message: ScanViewText.guideMessage.value(for: displayLanguage))

            VStack {
                Spacer()
                ShutterButtonView {
                    Task { await viewModel.capturePhoto() }
                }
                .padding(.bottom, 32)
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

#Preview {
    ScanView(displayLanguage: .english, cameraService: PreviewCameraService())
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
