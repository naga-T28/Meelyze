import Foundation

/// OCR結果からRule Engineまでを結んだ、撮影1回分の解析を担うService。
/// `MenuAnalysisViewModel`（TASK-039）が画面状態管理から呼び出す唯一の入口とする。
protocol MenuAnalysisService {
    /// `OCRResult`とユーザーが選択済みのアレルゲン・食事制限（`UserProfile`）から、
    /// 料理ごとの三値判定・Evidence・Bounding Boxを含む解析結果を返す。
    func analyze(_ ocrResult: OCRResult, profile: UserProfile) async -> MenuAnalysisResult
}

/// `MenuAnalysisService`の既定実装。`MenuUnderstandingRequestBuilder`（TASK-037）で組み立てた
/// requestを`RiskEvaluationService`（Issue #17。前処理→Menu Understanding→Alias解決→DB Fact構築→
/// Rule Engineまで結線済み）へ渡し、その結果を元のOCR Bounding Boxと結び付ける。
///
/// `RiskEvaluationService`自体（Issue #17）は「境界不明の失敗から架空の料理・Bounding Boxを
/// 生成しない」という原則を守っており、request/sourcesスコープの失敗はitemを生成しない。本Serviceは
/// その原則を変更せず、次の2つの縮退ルールだけを追加する。
///
/// 1. item scopeの失敗（Menu Understanding側のitem検証失敗、またはAlias解決/DB照合の失敗）は、
///    実際のitem境界（`MenuUnderstandingItemReference`）が判明しているため、対象target全件を
///    `undetermined`とした結果へ復元し、Bounding Boxを失わない。
/// 2. Foundation Models利用不可（request scopeの`modelUnavailable`）によって`items`が1件も
///    得られなかった場合に限り、OCRセグメント1件を1項目とみなした最も保守的なフォールバックを行う
///    （FR-1.7、`docs/ui-design.md`E02「未解決料理だけを縮退させる」）。Menu Understandingが
///    実際に動作して単に0件だった場合（対象外の写真等）にまで適用すると無関係なOCR断片
///    （店名・電話番号等）まで「判定不可」表示になってしまうため、この場合には適用しない。
struct DefaultMenuAnalysisService: MenuAnalysisService {
    private let riskEvaluationService: RiskEvaluationService
    private let requestBuilder: MenuUnderstandingRequestBuilder

    init(
        riskEvaluationService: RiskEvaluationService,
        requestBuilder: MenuUnderstandingRequestBuilder = MenuUnderstandingRequestBuilder()
    ) {
        self.riskEvaluationService = riskEvaluationService
        self.requestBuilder = requestBuilder
    }

    func analyze(_ ocrResult: OCRResult, profile: UserProfile) async -> MenuAnalysisResult {
        let output = requestBuilder.build(from: ocrResult)
        guard !output.request.segments.isEmpty else {
            return .noRecognizableText
        }

        let riskResult = await riskEvaluationService.evaluate(output.request, profile: profile)
        let targets = profile.selectedRiskTargets

        var items = riskResult.items.map { evaluation in
            MenuAnalysisItemResult(
                evaluation: evaluation,
                boundingBoxes: Self.boundingBoxes(for: evaluation.reference, sourceMap: output.sourceMap)
            )
        }

        let itemScopedFailures = riskResult.failures.filter { Self.itemReference(for: $0.scope) != nil }
        let otherFailures = riskResult.failures.filter { Self.itemReference(for: $0.scope) == nil }

        items += itemScopedFailures.map { failure in
            Self.undeterminedItemResult(for: failure, targets: targets, sourceMap: output.sourceMap)
        }
        items.sort { $0.reference.ordinal < $1.reference.ordinal }

        if items.isEmpty {
            let unavailableReasons = Self.modelUnavailableReasons(in: otherFailures)
            if !unavailableReasons.isEmpty {
                items = Self.fallbackItemResults(
                    segments: output.request.segments,
                    reasons: unavailableReasons,
                    targets: targets,
                    sourceMap: output.sourceMap
                )
            }
        }

        return .completed(MenuAnalysisSummary(items: items, failures: otherFailures))
    }

    private static func boundingBoxes(
        for reference: MenuUnderstandingItemReference,
        sourceMap: [MenuUnderstandingSourceID: RecognizedTextObservation]
    ) -> [CGRect] {
        reference.sourceReferences.compactMap { sourceMap[$0.sourceID]?.boundingBox }
    }

    private static func itemReference(for scope: MenuUnderstandingFailureScope) -> MenuUnderstandingItemReference? {
        guard case .item(let reference) = scope else { return nil }
        return reference
    }

    /// item scopeの失敗（Menu Understanding側のitem検証失敗、またはIssue #17のAlias解決/DB照合失敗）を、
    /// 対象target全件`undetermined`の結果へ復元する。原因がMenu Understanding由来であれば
    /// `RiskInferredOrigin.itemUnderstandingIncomplete`へその理由を残し、Alias解決/DB照合由来
    /// （`RiskEvaluationFailureReason.aliasResolutionFailed`）の場合は対応する`MenuUnderstandingFailureReason`が
    /// 存在しないため`inferredOrigin`はnilのままにする。
    private static func undeterminedItemResult(
        for failure: RiskEvaluationFailure,
        targets: [RiskTarget],
        sourceMap: [MenuUnderstandingSourceID: RecognizedTextObservation]
    ) -> MenuAnalysisItemResult {
        guard let reference = itemReference(for: failure.scope) else {
            preconditionFailure("caller must filter to item-scoped failures only")
        }

        let inferredOrigin: RiskInferredOrigin?
        if case .menuUnderstanding(let reason) = failure.reason {
            inferredOrigin = .itemUnderstandingIncomplete([reason])
        } else {
            inferredOrigin = nil
        }
        let evidence = RiskEvidence(kind: .unknown, inferredOrigin: inferredOrigin)
        let results = targets.map { RiskEvaluationResult(target: $0, determination: .undetermined, evidence: [evidence]) }

        return MenuAnalysisItemResult(
            evaluation: MenuItemRiskEvaluation(reference: reference, results: results),
            boundingBoxes: boundingBoxes(for: reference, sourceMap: sourceMap)
        )
    }

    private static func modelUnavailableReasons(in failures: [RiskEvaluationFailure]) -> [MenuUnderstandingFailureReason] {
        failures.compactMap { failure in
            guard failure.scope == .request, case .menuUnderstanding(let reason) = failure.reason else { return nil }
            guard case .modelUnavailable = reason else { return nil }
            return reason
        }
    }

    /// Foundation Models利用不可によって実Itemが1件も得られなかった場合の、OCRセグメント単位の
    /// 最も保守的なフォールバック。料理としてのグルーピングは一切推測せず、OCRが検出した領域を
    /// そのまま1項目・`undetermined`として表示する。
    ///
    /// 価格・メニュー番号・装飾記号のみのセグメント（例: `500円`単独のBounding Box）は、それ自体が
    /// 料理ではないため判定対象itemにしない（FIX-013）。通常経路（Foundation Models利用可能時）では
    /// `MenuTextPreprocessor`の前処理結果を踏まえてLLMがこれらをitem化しないが、本フォールバックは
    /// 前処理を経由しないため、ここで同じ判定基準（`hasNoAnalyzableContent`）を明示的に適用する。
    private static func fallbackItemResults(
        segments: [MenuUnderstandingSourceSegment],
        reasons: [MenuUnderstandingFailureReason],
        targets: [RiskTarget],
        sourceMap: [MenuUnderstandingSourceID: RecognizedTextObservation]
    ) -> [MenuAnalysisItemResult] {
        let evidence = RiskEvidence(kind: .unknown, inferredOrigin: .itemUnderstandingIncomplete(reasons))
        let results = targets.map { RiskEvaluationResult(target: $0, determination: .undetermined, evidence: [evidence]) }
        let preprocessor = MenuTextPreprocessor()
        let analyzableSegments = segments.filter { !preprocessor.hasNoAnalyzableContent($0.rawText) }

        return analyzableSegments.enumerated().map { index, segment in
            let sourceReference = MenuUnderstandingSourceReference(sourceID: segment.id, rawFragment: segment.rawText)
            let reference = MenuUnderstandingItemReference(ordinal: index, sourceReferences: [sourceReference], separator: "\n")
            return MenuAnalysisItemResult(
                evaluation: MenuItemRiskEvaluation(reference: reference, results: results),
                boundingBoxes: boundingBoxes(for: reference, sourceMap: sourceMap)
            )
        }
    }
}
