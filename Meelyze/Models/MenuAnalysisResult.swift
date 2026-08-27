import Foundation

/// `MenuAnalysisService.analyze(_:profile:)`の結果。
enum MenuAnalysisResult: Equatable, Sendable {
    /// OCRが意味のあるテキストを1件も検出できなかった（`MenuUnderstandingRequestBuilder`が
    /// 空白のみのobservationを除外した結果、segmentsが0件になった場合を含む）。呼び出し側は
    /// 再撮影を促す（`docs/requirements.md` AC-1.4、`ScanViewModel`のOCR単体0件時の扱いと同様）。
    case noRecognizableText
    /// Menu Understanding以降を実行できた解析結果。
    case completed(MenuAnalysisSummary)
}

/// 解析が完了した場合の、料理ごとの判定結果一式。
struct MenuAnalysisSummary: Equatable, Sendable {
    /// Bounding Boxが解決できた料理（またはFoundation Models利用不可時のOCRセグメント単位の
    /// フォールバック項目）ごとの判定結果。
    let items: [MenuAnalysisItemResult]
    /// 項目境界が判明しなかった失敗（request/sourcesスコープ）。境界不明の失敗から架空の料理・
    /// Bounding Boxは生成しない（`task/README-issue17.md`「部分失敗」）。
    let failures: [RiskEvaluationFailure]
}

/// 1つの料理（またはFoundation Models利用不可時のOCRセグメント）についての判定結果と、
/// それに紐づくBounding Box。
///
/// 判定結果自体はIssue #17の`MenuItemRiskEvaluation`をそのまま保持し、Issue #19が新たに
/// 提供するのはBounding Boxとの対応関係のみとする（既存の三値集約ロジックを重複実装しない）。
struct MenuAnalysisItemResult: Equatable, Sendable {
    let evaluation: MenuItemRiskEvaluation
    /// この項目の根拠となったOCR領域のBounding Box（1件以上）。
    let boundingBoxes: [CGRect]

    var reference: MenuUnderstandingItemReference { evaluation.reference }
    var results: [RiskEvaluationResult] { evaluation.results }
    var overallDetermination: RiskDetermination? { evaluation.overallDetermination }
}
