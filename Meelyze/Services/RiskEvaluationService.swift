import Foundation

/// 前処理→Menu Understanding→Alias解決→Fact構築→Rule Engineを結んだ、再利用可能なService層。
/// `OCRResult`からrequestを組み立てる画面状態管理や`ScanViewModel`への接続はIssue #19の範囲。
protocol RiskEvaluationService {
    /// source ID付きのOCR segment相当のrequestと対象UserProfileから、メニュー全体のRisk評価を返す。
    func evaluate(_ request: MenuUnderstandingRequest, profile: UserProfile) async -> MenuRiskEvaluationResult
}

/// `RiskEvaluationService`の既定実装。`MenuTextPreprocessor` → `MenuUnderstandingService` →
/// `MenuAliasResolver` → `RiskFactBuilder` → `RiskRuleEngine`の順に結線する。
///
/// `MenuAliasResolver`と`RiskFactBuilder`は同じ`MenuKnowledgeRepository`インスタンスを共有する
/// 必要があるため、呼び出し側には個別実装ではなくRepository自体を渡してもらう設計にしている。
struct DefaultRiskEvaluationService: RiskEvaluationService {
    private let preprocessor: MenuTextPreprocessor
    private let understandingService: MenuUnderstandingService
    private let aliasResolver: MenuAliasResolver
    private let factBuilder: RiskFactBuilder
    private let ruleEngine: RiskRuleEngine
    private let signalExtractor: RiskLLMSignalExtractor

    init(
        repository: MenuKnowledgeRepository,
        understandingService: MenuUnderstandingService,
        preprocessor: MenuTextPreprocessor = MenuTextPreprocessor(),
        ruleEngine: RiskRuleEngine = RiskRuleEngine(),
        signalExtractor: RiskLLMSignalExtractor = RiskLLMSignalExtractor()
    ) {
        self.preprocessor = preprocessor
        self.understandingService = understandingService
        self.aliasResolver = MenuAliasResolver(repository: repository)
        self.factBuilder = RiskFactBuilder(repository: repository)
        self.ruleEngine = ruleEngine
        self.signalExtractor = signalExtractor
    }

    func evaluate(_ request: MenuUnderstandingRequest, profile: UserProfile) async -> MenuRiskEvaluationResult {
        let preprocessed = preprocessor.preprocess(request.segments)
        var understandingRequest = request
        understandingRequest.segments = preprocessed.segments

        let understandingResult = await understandingService.analyze(understandingRequest)

        let targets = profile.selectedRiskTargets
        var items: [MenuItemRiskEvaluation] = []
        var failures = understandingResult.failures.map { failure in
            RiskEvaluationFailure(scope: failure.scope, reason: .menuUnderstanding(failure.reason), retryability: failure.retryability)
        }

        // 境界が判明している成功済み項目だけを評価する。項目境界を復元できない失敗（上のfailuresへ
        // そのまま透過済み）から架空の料理・Bounding Boxを生成しない。
        for item in understandingResult.items {
            do {
                let itemNormalization = try aliasResolver.resolve(item, sourceEvidence: preprocessed.evidence)
                let facts = riskFacts(for: item, normalization: itemNormalization, profile: profile)
                let llmSignals = signalExtractor.extractSignals(
                    from: item, sourceEvidence: itemNormalization.sourceEvidence, targets: targets
                )
                let rawResults = ruleEngine.evaluate(targets: targets, facts: facts, llmSignals: llmSignals)

                // item scopeのMenu Understanding失敗（validation失敗・出力上限到達等）と併存する項目は、
                // 「該当なし」を断定できるだけの完全性が確認できていないため、noRecordedMatchだけを
                // undeterminedへ倒す（likelyContains・既存のundeterminedはそのまま）。
                let itemScopedFailureReasons = understandingResult.failures
                    .filter { $0.scope == .item(item.reference) }
                    .map(\.reason)
                let results = Self.downgradingNoRecordedMatch(in: rawResults, dueToItemScopedFailureReasons: itemScopedFailureReasons)

                items.append(MenuItemRiskEvaluation(reference: item.reference, results: results))
            } catch {
                // Alias解決（DB照合）自体が失敗した項目だけをtyped failureへ倒し、他項目の評価は継続する。
                failures.append(
                    RiskEvaluationFailure(scope: .item(item.reference), reason: .aliasResolutionFailed, retryability: .notRetryable)
                )
            }
        }

        return MenuRiskEvaluationResult(items: items, failures: failures)
    }

    private func riskFacts(for item: ParsedMenuItem, normalization: MenuItemNormalizationEvidence, profile: UserProfile) -> [RiskFact] {
        let candidateResolutions = normalization.baseDishCandidateResolutions + normalization.explicitIngredientResolutions
        let candidateFacts = candidateResolutions.flatMap { resolution in
            factBuilder.buildFacts(for: resolution, sourceEvidence: normalization.sourceEvidence, profile: profile)
        }
        // LLMが意味を解決できなかった語も、Alias解決できなかった候補と同じ「未解決」として扱う。
        // RiskFactBuilder/RiskRuleEngineは無改修のまま、既存のhasUnresolvedUncertaintyロジックが
        // 選択済み全targetの安全側判定（noRecordedMatchの抑止）へ反映する。
        let unknownTermFacts = item.unknownTerms.flatMap { term in
            factBuilder.buildFacts(
                for: Self.unresolvedResolution(forUnknownTerm: term), sourceEvidence: normalization.sourceEvidence, profile: profile
            )
        }
        return candidateFacts + unknownTermFacts
    }

    private static func unresolvedResolution(forUnknownTerm term: String) -> MenuAliasResolutionEvidence {
        MenuAliasResolutionEvidence(
            entityType: .ingredient, // .unresolvedステータスではRiskFactBuilderが参照しないため実質未使用
            inputText: term,
            normalization: MenuNameNormalizationEvidence(originalText: term, normalizedText: term, changes: []),
            status: .unresolved,
            matches: []
        )
    }

    private static func downgradingNoRecordedMatch(
        in results: [RiskEvaluationResult],
        dueToItemScopedFailureReasons reasons: [MenuUnderstandingFailureReason]
    ) -> [RiskEvaluationResult] {
        guard !reasons.isEmpty else { return results }
        return results.map { result in
            guard result.determination == .noRecordedMatch else { return result }
            let evidence = RiskEvidence(kind: .unknown, inferredOrigin: .itemUnderstandingIncomplete(reasons))
            return RiskEvaluationResult(target: result.target, determination: .undetermined, evidence: result.evidence + [evidence])
        }
    }
}
