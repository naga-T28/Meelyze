import SwiftUI
import UIKit

/// S06 メニュー撮影画面。カメラプレビューをsafe areaまで広げ、撮影ガイドとシャッターボタンを重ねる
/// （`docs/ui-design.md`「Navigation」方針によりS06は`fullScreenCover`を使わない）。撮影→OCR実行の
/// 結果が0件・失敗の場合はE01（`OCRFailureView`）へ切り替える。
///
/// OCRが1件以上取得できた場合（`.recognized`）は、`docs/ui-design.md`が定める「同一スキャン内の
/// 状態置換」方針（S06→S07→S08を別画面としてスタックしない）に従い、本View自身が
/// `MenuAnalysisViewModel`を呼び出してS07/S08相当の表示へ切り替える（TASK-043）。実際のS07/S08の
/// 画面デザインはTASK-049・TASK-048が担当するため、`AnalysisResultPlaceholderView`はそれまでの
/// 暫定表示に留める。
///
/// カメラ・OCR・解析へのアクセスは`CameraService` `OCRService` `MenuAnalysisService`経由
/// （ViewModelが保持）にとどめ、AVFoundation・Vision・Foundation Modelsを直接importしない。
struct ScanView: View {
    @State private var viewModel: ScanViewModel
    @State private var analysisViewModel: MenuAnalysisViewModel
    @State private var dishNameTranslationService = AppleDishNameTranslationService()
    let displayLanguage: DisplayLanguage

    init(
        displayLanguage: DisplayLanguage,
        cameraService: CameraService,
        ocrService: OCRService,
        menuAnalysisService: MenuAnalysisService,
        profileRepository: ProfileRepository
    ) {
        self.displayLanguage = displayLanguage
        self._viewModel = State(initialValue: ScanViewModel(cameraService: cameraService, ocrService: ocrService))
        self._analysisViewModel = State(initialValue: MenuAnalysisViewModel(
            menuAnalysisService: menuAnalysisService,
            profileRepository: profileRepository
        ))
    }

    var body: some View {
        Group {
            switch viewModel.scanState {
            case .failed:
                OCRFailureView(displayLanguage: displayLanguage) {
                    viewModel.retake()
                }
            case .idle, .capturing, .recognizing:
                cameraContent
            case .recognized(let ocrResult, let imageData):
                AnalysisResultPlaceholderView(
                    ocrResult: ocrResult,
                    imageData: imageData,
                    displayLanguage: displayLanguage,
                    analysisViewModel: analysisViewModel,
                    translationService: dishNameTranslationService,
                    onRetake: { viewModel.retake() }
                )
                .dishNameTranslationSession(using: dishNameTranslationService)
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

/// OCRが1件以上取得できた後（`.recognized`）に表示する、S07（解析中）・S08（判定結果オーバーレイ）
/// 相当の表示へのハブ。`.idle` `.processing`ではTASK-049の`AnalysisProgressView`（S07）、
/// `.completed`ではTASK-048の`ResultOverlayView`（S08）を表示する。`.failed`
/// `.noRecognizableText`は本タスク（#20）の対象外の稀なケースのため、暫定表示のままとする。
private struct AnalysisResultPlaceholderView: View {
    let ocrResult: OCRResult
    let imageData: Data
    let displayLanguage: DisplayLanguage
    let analysisViewModel: MenuAnalysisViewModel
    let translationService: any DishNameTranslationService
    let onRetake: () -> Void

    var body: some View {
        Group {
            switch analysisViewModel.analysisState {
            case .idle, .processing:
                AnalysisProgressView(displayLanguage: displayLanguage)
            case .completed(let result):
                completedContent(for: result)
            case .failed:
                retakePrompt(message: "Couldn't analyze the menu.", identifier: "AnalysisFailedPlaceholder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
            }
        }
        .task(id: ocrResult) {
            await analysisViewModel.analyze(ocrResult: ocrResult)
        }
    }

    @ViewBuilder
    private func completedContent(for result: MenuAnalysisResult) -> some View {
        switch result {
        case .noRecognizableText:
            retakePrompt(message: "No recognizable menu text.", identifier: "AnalysisCompletedPlaceholder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
        case .completed(let summary):
            ResultOverlayView(
                imageData: imageData,
                summary: summary,
                displayLanguage: displayLanguage,
                translationService: translationService,
                onRetake: onRetake,
                onRetryAnalysis: { Task { await analysisViewModel.analyze(ocrResult: ocrResult) } }
            )
        }
    }

    /// `message`・`identifier`はTASK-048/TASK-049が本Viewを置き換えるまでの暫定値。identifierは
    /// メッセージのText自身へ付与する（`OCRFailureView`と同様、共有コンテナへは付与しない）。
    private func retakePrompt(message: String, identifier: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .foregroundStyle(.white)
                .accessibilityIdentifier(identifier)
            Button("Retake", action: onRetake)
                .accessibilityIdentifier("AnalysisPlaceholderRetakeButton")
        }
        .padding()
    }
}

#Preview {
    ScanView(
        displayLanguage: .english,
        cameraService: PreviewCameraService(),
        ocrService: PreviewOCRService(),
        menuAnalysisService: PreviewMenuAnalysisService(),
        profileRepository: PreviewProfileRepository()
    )
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

/// Preview専用の`MenuAnalysisService`スタブ。常に空の解析結果を返す。
private struct PreviewMenuAnalysisService: MenuAnalysisService {
    func analyze(_ ocrResult: OCRResult, profile: UserProfile) async -> MenuAnalysisResult {
        .completed(MenuAnalysisSummary(items: [], failures: []))
    }
}

/// Preview専用の`ProfileRepository`スタブ。常に初期設定済みの固定プロファイルを返す。
private struct PreviewProfileRepository: ProfileRepository {
    func currentProfile() throws -> UserProfile? {
        UserProfile(isInitialSetupCompleted: true)
    }

    func save(_ profile: UserProfile) throws {}
}
