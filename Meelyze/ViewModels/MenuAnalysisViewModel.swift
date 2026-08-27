import Foundation

/// 解析全体（Menu Understanding〜Rule Engine）の状態を保持し、`MenuAnalysisService`を呼び出す。
///
/// `ScanViewModel`は撮影・OCR実行までの責務に留め、本ViewModelはOCR完了後（`OCRResult`）を受け取って
/// 以降を担当する。`ScanViewModel.ScanState`と統合するかどうかは、S07以降のView層を実装する後続Issueで
/// 判断する（本タスクではService層・状態管理のみを提供する）。
@MainActor
@Observable
final class MenuAnalysisViewModel {
    /// `AnalysisState.failed`の理由。
    enum AnalysisFailureReason: Equatable {
        /// プロファイル未保存（オンボーディング未完了）、または読み込み失敗のため解析を開始できなかった。
        case profileUnavailable
    }

    /// 解析全体の状態。`docs/ui-design.md`が定めるidle/processing/completed/failedの共有概念に対応する。
    enum AnalysisState: Equatable {
        case idle
        case processing
        case completed(MenuAnalysisResult)
        case failed(AnalysisFailureReason)
    }

    private(set) var analysisState: AnalysisState = .idle

    private let menuAnalysisService: MenuAnalysisService
    private let profileRepository: ProfileRepository

    init(menuAnalysisService: MenuAnalysisService, profileRepository: ProfileRepository) {
        self.menuAnalysisService = menuAnalysisService
        self.profileRepository = profileRepository
    }

    /// 解析処理中かどうか。`true`の間はシャッター等の再操作を無効化する用途を想定する。
    var isProcessing: Bool {
        if case .processing = analysisState { return true }
        return false
    }

    /// `ocrResult`を対象に解析を実行する。処理中の重複呼び出しは無視する（多重実行を防ぐガードは
    /// 最初の`await`より前、同期的に`.processing`へ遷移させた直後に効かせる）。
    func analyze(ocrResult: OCRResult) async {
        guard !isProcessing else { return }
        analysisState = .processing

        guard let profile = try? profileRepository.currentProfile() else {
            analysisState = .failed(.profileUnavailable)
            return
        }

        analysisState = .completed(await menuAnalysisService.analyze(ocrResult, profile: profile))
    }
}
