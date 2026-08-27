import Foundation

/// UI Testから解析パイプライン全体（Foundation Models・SwiftData DB照合含む）の実機依存を排除し、
/// 三値混在・E02・E03・処理長時間化を決定論的に再現するためのスタブ実装。
///
/// `UITEST_ANALYSIS_STUB_MODE`環境変数が指定された場合にのみ`RootView`がこれへ差し替える
/// （`Meelyze/Services/UITestScanStubs.swift`の`UITEST_OCR_STUB_MODE`と同じパターン）。
/// Simulator上ではFoundation Modelsの利用可否・DB照合結果が環境依存で非決定的になるため
/// （TASK-051で判明）、S08/S09のUI Testを安定させるにはこのスタブが必要。
struct StubMenuAnalysisService: MenuAnalysisService {
    enum Mode: String {
        /// 三値（含有の可能性が高い／収録データ上は該当なし／判定不可）が同一結果内に混在する。
        case mixed
        /// E02: メニュー解析利用不可（request scopeのMenu Understanding失敗、items 0件）。
        case e02
        /// E03: DB未一致・Alias曖昧（1件の料理がunresolvedTerm由来のundetermined）。
        case e03
        /// processing状態を意図的に長引かせる（S07表示の確認用）。
        case slow
    }

    let mode: Mode

    func analyze(_ ocrResult: OCRResult, profile: UserProfile) async -> MenuAnalysisResult {
        switch mode {
        case .mixed:
            return Self.mixedResult()
        case .e02:
            return Self.e02Result()
        case .e03:
            return Self.e03Result()
        case .slow:
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return Self.mixedResult()
        }
    }

    private static func reference(ordinal: Int, text: String) -> MenuUnderstandingItemReference {
        MenuUnderstandingItemReference(
            ordinal: ordinal,
            sourceReferences: [MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("stub-\(ordinal)"), rawFragment: text)],
            separator: ""
        )
    }

    private static func mixedResult() -> MenuAnalysisResult {
        let likelyContains = MenuAnalysisItemResult(
            evaluation: MenuItemRiskEvaluation(
                reference: reference(ordinal: 0, text: "ラフテー"),
                results: [RiskEvaluationResult(
                    target: .allergen(.pork),
                    determination: .likelyContains,
                    evidence: [RiskEvidence(kind: .dishDatabase, resolvedEntity: MenuAliasResolvedEntity(id: "dish-rafute", canonicalName: "ラフテー"))]
                )]
            ),
            boundingBoxes: [CGRect(x: 0.1, y: 0.67, width: 0.35, height: 0.08)]
        )
        let noRecordedMatch = MenuAnalysisItemResult(
            evaluation: MenuItemRiskEvaluation(
                reference: reference(ordinal: 1, text: "ゴーヤーチャンプルー"),
                results: [RiskEvaluationResult(
                    target: .allergen(.pork),
                    determination: .noRecordedMatch,
                    evidence: [RiskEvidence(kind: .dishDatabase, resolvedEntity: MenuAliasResolvedEntity(id: "dish-goya", canonicalName: "ゴーヤーチャンプルー"))]
                )]
            ),
            // FIX-015: 3項目を均等（画像高さの0.25刻み）に配置すると、S08の最上段タグが常時注意文
            // （`ResultOverlayView.topNotices`）に近すぎる位置になり、`XCTest.performAccessibilityAudit()`
            // のコントラスト判定がタグと常時注意文の色を混在させて誤って"Contrast failed"と判定する
            // ことを確認した。0.30刻みへ広げ、実際のメニュー写真により近い間隔にした。
            boundingBoxes: [CGRect(x: 0.1, y: 0.37, width: 0.35, height: 0.08)]
        )
        let undetermined = MenuAnalysisItemResult(
            evaluation: MenuItemRiskEvaluation(
                reference: reference(ordinal: 2, text: "沖縄そば"),
                results: [RiskEvaluationResult(
                    target: .allergen(.pork),
                    determination: .undetermined,
                    evidence: [RiskEvidence(kind: .unknown, inferredOrigin: .unresolvedTerm)]
                )]
            ),
            boundingBoxes: [CGRect(x: 0.1, y: 0.07, width: 0.35, height: 0.08)]
        )
        return .completed(MenuAnalysisSummary(items: [likelyContains, noRecordedMatch, undetermined], failures: []))
    }

    private static func e02Result() -> MenuAnalysisResult {
        .completed(MenuAnalysisSummary(items: [], failures: [
            RiskEvaluationFailure(
                scope: .request,
                reason: .menuUnderstanding(.modelUnavailable(.deviceNotEligible)),
                retryability: .notRetryable
            )
        ]))
    }

    private static func e03Result() -> MenuAnalysisResult {
        let item = MenuAnalysisItemResult(
            evaluation: MenuItemRiskEvaluation(
                reference: reference(ordinal: 0, text: "幻の料理"),
                results: [RiskEvaluationResult(
                    target: .allergen(.pork),
                    determination: .undetermined,
                    evidence: [RiskEvidence(kind: .unknown, inferredOrigin: .unresolvedTerm)]
                )]
            ),
            boundingBoxes: [CGRect(x: 0.1, y: 0.5, width: 0.35, height: 0.08)]
        )
        return .completed(MenuAnalysisSummary(items: [item], failures: []))
    }
}
