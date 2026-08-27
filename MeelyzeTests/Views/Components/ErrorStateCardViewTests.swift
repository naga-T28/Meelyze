import Testing
@testable import Meelyze

/// `UndeterminedReason.from(_:)`の分類ロジック（E02/E03のどちらの理由に該当するかの判定）を検証する。
struct ErrorStateCardViewTests {
    @Test func itemUnderstandingIncompleteEvidenceMapsToMenuUnderstandingIncomplete() {
        let evidence = [RiskEvidence(kind: .unknown, inferredOrigin: .itemUnderstandingIncomplete([.modelUnavailable(.deviceNotEligible)]))]
        #expect(UndeterminedReason.from(evidence) == .menuUnderstandingIncomplete)
    }

    @Test func unresolvedTermEvidenceMapsToDatabaseUnresolved() {
        let evidence = [RiskEvidence(kind: .unknown, inferredOrigin: .unresolvedTerm)]
        #expect(UndeterminedReason.from(evidence) == .databaseUnresolved)
    }

    @Test func ambiguousCandidatesEvidenceMapsToDatabaseUnresolved() {
        let evidence = [RiskEvidence(kind: .unknown, inferredOrigin: .ambiguousCandidates([
            MenuAliasResolvedEntity(id: "dish-1", canonicalName: "沖縄そば"),
            MenuAliasResolvedEntity(id: "dish-2", canonicalName: "そば")
        ]))]
        #expect(UndeterminedReason.from(evidence) == .databaseUnresolved)
    }

    @Test func databaseFetchFailedEvidenceMapsToDatabaseUnresolved() {
        let evidence = [RiskEvidence(kind: .unknown, inferredOrigin: .databaseFetchFailed)]
        #expect(UndeterminedReason.from(evidence) == .databaseUnresolved)
    }

    /// Alias解決自体が失敗した項目レベルの縮退（`DefaultMenuAnalysisService.undeterminedItemResult`が
    /// `aliasResolutionFailed`理由の場合に作る、`inferredOrigin == nil`のEvidence）もE03として扱う。
    @Test func unknownKindWithNilInferredOriginMapsToDatabaseUnresolved() {
        let evidence = [RiskEvidence(kind: .unknown, inferredOrigin: nil)]
        #expect(UndeterminedReason.from(evidence) == .databaseUnresolved)
    }

    @Test func menuUnderstandingIncompleteTakesPriorityWhenBothReasonsArePresent() {
        let evidence = [
            RiskEvidence(kind: .unknown, inferredOrigin: .unresolvedTerm),
            RiskEvidence(kind: .unknown, inferredOrigin: .itemUnderstandingIncomplete([.modelUnavailable(.deviceNotEligible)]))
        ]
        #expect(UndeterminedReason.from(evidence) == .menuUnderstandingIncomplete)
    }

    @Test func explicitOrDishDatabaseEvidenceWithoutUnknownDoesNotMapToAnyReason() {
        let evidence = [RiskEvidence(kind: .dishDatabase)]
        #expect(UndeterminedReason.from(evidence) == nil)
    }

    @Test func emptyEvidenceDoesNotMapToAnyReason() {
        #expect(UndeterminedReason.from([]) == nil)
    }

    @Test func messagesAreProvidedForAllMVPLanguages() {
        let languages: [DisplayLanguage] = [.english, .traditionalChinese, .simplifiedChinese, .korean]
        for language in languages {
            #expect(!UndeterminedReason.menuUnderstandingIncomplete.message(for: language).isEmpty)
            #expect(!UndeterminedReason.databaseUnresolved.message(for: language).isEmpty)
        }
    }

    @Test func summaryWithRequestScopeModelUnavailableFailureHasModelUnavailableCondition() {
        let summary = MenuAnalysisSummary(items: [], failures: [
            RiskEvaluationFailure(scope: .request, reason: .menuUnderstanding(.modelUnavailable(.deviceNotEligible)), retryability: .notRetryable)
        ])
        #expect(summary.hasModelUnavailableCondition)
    }

    @Test func summaryWithItemUnderstandingIncompleteEvidenceHasModelUnavailableCondition() {
        let reference = MenuUnderstandingItemReference(ordinal: 0, sourceReferences: [], separator: "")
        let evidence = RiskEvidence(kind: .unknown, inferredOrigin: .itemUnderstandingIncomplete([.modelUnavailable(.deviceNotEligible)]))
        let result = RiskEvaluationResult(target: .allergen(.pork), determination: .undetermined, evidence: [evidence])
        let item = MenuAnalysisItemResult(evaluation: MenuItemRiskEvaluation(reference: reference, results: [result]), boundingBoxes: [])
        let summary = MenuAnalysisSummary(items: [item], failures: [])

        #expect(summary.hasModelUnavailableCondition)
    }

    @Test func summaryWithOnlyDatabaseUnresolvedEvidenceDoesNotHaveModelUnavailableCondition() {
        let reference = MenuUnderstandingItemReference(ordinal: 0, sourceReferences: [], separator: "")
        let evidence = RiskEvidence(kind: .unknown, inferredOrigin: .unresolvedTerm)
        let result = RiskEvaluationResult(target: .allergen(.pork), determination: .undetermined, evidence: [evidence])
        let item = MenuAnalysisItemResult(evaluation: MenuItemRiskEvaluation(reference: reference, results: [result]), boundingBoxes: [])
        let summary = MenuAnalysisSummary(items: [item], failures: [])

        #expect(!summary.hasModelUnavailableCondition)
    }

    @Test func summaryWithNoFailuresOrIncompleteEvidenceDoesNotHaveModelUnavailableCondition() {
        let summary = MenuAnalysisSummary(items: [], failures: [])
        #expect(!summary.hasModelUnavailableCondition)
    }

    /// 回帰テスト: E02は`docs/ui-design.md`上「利用不可」だけでなく「実行時エラー」全般を含むため、
    /// `.modelUnavailable`以外のMenu Understanding失敗（生成失敗等）でも表示条件を満たす必要がある。
    /// Simulator実行時にFoundation Modelsが`.generationFailed`相当の理由で失敗し、フォールバックも
    /// 効かず`items`が空になったにもかかわらずE02バナーが表示されないUI Test上の実挙動から発見した。
    @Test func summaryWithNonModelUnavailableMenuUnderstandingFailureHasModelUnavailableCondition() {
        let summary = MenuAnalysisSummary(items: [], failures: [
            RiskEvaluationFailure(scope: .request, reason: .menuUnderstanding(.generationFailed(.guardrailViolation)), retryability: .notRetryable)
        ])
        #expect(summary.hasModelUnavailableCondition)
    }

    /// 失敗が1件以上あるにもかかわらず`items`が0件の場合（フォールバックが効かない失敗理由）も、
    /// 「解析できなかった」ことをユーザーへ示すため表示条件を満たす。
    @Test func summaryWithFailuresButNoItemsHasModelUnavailableConditionRegardlessOfReason() {
        let summary = MenuAnalysisSummary(items: [], failures: [
            RiskEvaluationFailure(scope: .item(MenuUnderstandingItemReference(ordinal: 0, sourceReferences: [], separator: "")), reason: .aliasResolutionFailed, retryability: .notRetryable)
        ])
        #expect(summary.hasModelUnavailableCondition)
    }

    @Test func retryableModelUnavailableFailureIsReportedAsRetryable() {
        let summary = MenuAnalysisSummary(items: [], failures: [
            RiskEvaluationFailure(scope: .request, reason: .menuUnderstanding(.modelUnavailable(.modelNotReady)), retryability: .retryable)
        ])
        #expect(summary.isModelUnavailableFailureRetryable)
    }

    @Test func notRetryableModelUnavailableFailureIsNotReportedAsRetryable() {
        let summary = MenuAnalysisSummary(items: [], failures: [
            RiskEvaluationFailure(scope: .request, reason: .menuUnderstanding(.modelUnavailable(.deviceNotEligible)), retryability: .notRetryable)
        ])
        #expect(!summary.isModelUnavailableFailureRetryable)
    }
}
