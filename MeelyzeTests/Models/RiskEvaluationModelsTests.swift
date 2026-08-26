import Testing
import Foundation
@testable import Meelyze

/// TASK-030が定義するRisk契約モデル（三値・RiskTarget・Evidence・Fact・LLM Signal）の
/// 初期化・不変性・網羅性を確認するテスト。
struct RiskEvaluationModelsTests {
    @Test func riskDeterminationKeepsThreeValuesDistinct() {
        #expect(RiskDetermination.likelyContains == .likelyContains)
        #expect(RiskDetermination.likelyContains != .noRecordedMatch)
        #expect(RiskDetermination.likelyContains != .undetermined)
        #expect(RiskDetermination.noRecordedMatch != .undetermined)
    }

    @Test func riskTargetDistinguishesAllergenAndDietaryRestrictionByRawValueBackedEquality() {
        let allergenTarget = RiskTarget.allergen(.egg)
        let restrictionTarget = RiskTarget.dietaryRestriction(.halal)

        #expect(allergenTarget == .allergen(.egg))
        #expect(allergenTarget != .allergen(.milk))
        #expect(restrictionTarget == .dietaryRestriction(.halal))
        #expect(restrictionTarget != .dietaryRestriction(.vegan))
        #expect(allergenTarget != restrictionTarget)
        #expect(Set([allergenTarget, restrictionTarget]).count == 2)
    }

    @Test func riskEvidenceKindDoesNotCollideWithEvidenceSourceSwiftDataModel() {
        // Issue #16のEvidenceSource（SwiftData model、料理・食材DBの出典）と同じモジュール内で、
        // 判定用のRiskEvidenceKindが型名衝突なく共存できることを確認する。
        let modelEvidenceSource = EvidenceSource(id: "src1", name: "消費者庁", urlString: "https://example.com", checkedAt: "2026-08-26")
        let evidenceKind = RiskEvidenceKind.dishDatabase

        #expect(modelEvidenceSource.id == "src1")
        #expect(evidenceKind == .dishDatabase)
        let allKinds: [RiskEvidenceKind] = [.explicit, .normalized, .dishDatabase, .llmInference, .unknown]
        #expect(allKinds.count == 5)
    }

    @Test func riskEvidenceHoldsAllRequiredFieldsAsValueTypesWithoutSwiftDataModelInstances() {
        let sourceID = MenuUnderstandingSourceID("s1")
        let sourceEvidence = MenuTextPreprocessingEvidence(
            sourceID: sourceID,
            rawText: "ラフテー 980円",
            analysisText: "ラフテー",
            confidence: 0.9,
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            changes: [.priceRemoved]
        )
        let normalization = MenuNameNormalizationEvidence(
            originalText: "らふてー",
            normalizedText: "ラフテー",
            changes: [.hiraganaConvertedToKatakana]
        )
        let resolvedEntity = MenuAliasResolvedEntity(id: "rafute", canonicalName: "ラフテー")

        let evidence = RiskEvidence(
            kind: .dishDatabase,
            sourceEvidence: [sourceEvidence],
            normalization: normalization,
            resolvedEntityType: .dish,
            resolvedEntity: resolvedEntity,
            databaseSourceIDs: ["evidence_source_1"],
            isHiddenIngredient: true,
            hiddenIngredientCategory: .dashi,
            inferredOrigin: nil
        )

        #expect(evidence.kind == .dishDatabase)
        #expect(evidence.sourceEvidence == [sourceEvidence])
        #expect(evidence.sourceEvidence.first?.sourceID == sourceID)
        #expect(evidence.sourceEvidence.first?.rawText == "ラフテー 980円")
        #expect(evidence.sourceEvidence.first?.confidence == 0.9)
        #expect(evidence.sourceEvidence.first?.boundingBox == CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        #expect(evidence.normalization == normalization)
        #expect(evidence.resolvedEntityType == .dish)
        #expect(evidence.resolvedEntity == resolvedEntity)
        #expect(evidence.databaseSourceIDs == ["evidence_source_1"])
        #expect(evidence.isHiddenIngredient == true)
        #expect(evidence.hiddenIngredientCategory == .dashi)
        #expect(evidence.inferredOrigin == nil)
    }

    @Test func riskEvidenceDefaultsLeaveOptionalFieldsEmpty() {
        let evidence = RiskEvidence(kind: .unknown)

        #expect(evidence.sourceEvidence.isEmpty)
        #expect(evidence.normalization == nil)
        #expect(evidence.resolvedEntityType == nil)
        #expect(evidence.resolvedEntity == nil)
        #expect(evidence.databaseSourceIDs.isEmpty)
        #expect(evidence.isHiddenIngredient == false)
        #expect(evidence.hiddenIngredientCategory == nil)
        #expect(evidence.inferredOrigin == nil)
    }

    @Test func riskInferredOriginRepresentsLLMPositiveUnresolvedAndAmbiguousCandidates() {
        let ambiguous = RiskInferredOrigin.ambiguousCandidates([
            MenuAliasResolvedEntity(id: "okinawan_tofu", canonicalName: "沖縄豆腐"),
            MenuAliasResolvedEntity(id: "regular_tofu", canonicalName: "豆腐")
        ])

        #expect(RiskInferredOrigin.llmPositiveInference == .llmPositiveInference)
        #expect(RiskInferredOrigin.unresolvedTerm == .unresolvedTerm)
        #expect(RiskInferredOrigin.llmPositiveInference != .unresolvedTerm)

        if case .ambiguousCandidates(let candidates) = ambiguous {
            #expect(candidates.map(\.id) == ["okinawan_tofu", "regular_tofu"])
        } else {
            Issue.record("expected .ambiguousCandidates")
        }
    }

    @Test func riskEvaluationResultPairsTargetDeterminationAndEvidence() {
        let evidence = RiskEvidence(kind: .dishDatabase)
        let result = RiskEvaluationResult(target: .allergen(.shrimp), determination: .likelyContains, evidence: [evidence])

        #expect(result.target == .allergen(.shrimp))
        #expect(result.determination == .likelyContains)
        #expect(result.evidence == [evidence])
    }

    @Test func riskFactHoldsResolutionDatabaseMatchesAndEvidenceForATarget() {
        let match = RiskFactDatabaseMatch(
            ingredientID: "pork",
            confidence: .confirmed,
            isHiddenIngredient: false,
            hiddenIngredientCategory: nil,
            sourceIDs: ["maff_uchino_rafute"]
        )
        let fact = RiskFact(
            target: .allergen(.pork),
            resolution: .resolved,
            databaseMatches: [match],
            evidence: [RiskEvidence(kind: .dishDatabase)]
        )

        #expect(fact.target == .allergen(.pork))
        #expect(fact.resolution == .resolved)
        #expect(fact.databaseMatches == [match])
        #expect(fact.databaseMatches.first?.confidence == .confirmed)
        #expect(fact.databaseMatches.first?.sourceIDs == ["maff_uchino_rafute"])
    }

    @Test func riskFactResolutionDistinguishesFourStates() {
        #expect(RiskFactResolution.resolved != .unresolved)
        #expect(RiskFactResolution.unresolved != .ambiguous)
        #expect(RiskFactResolution.ambiguous != .databaseUnavailable)
        #expect(RiskFactResolution.databaseUnavailable != .resolved)
    }

    @Test func riskFactDatabaseMatchDistinguishesVariesByStoreFromConfirmedMatch() {
        let confirmed = RiskFactDatabaseMatch(
            ingredientID: "pork",
            confidence: .confirmed,
            isHiddenIngredient: false,
            hiddenIngredientCategory: nil,
            sourceIDs: []
        )
        let variesByStore = RiskFactDatabaseMatch(
            ingredientID: "lard",
            confidence: .variesByStore,
            isHiddenIngredient: true,
            hiddenIngredientCategory: .fatOrOil,
            sourceIDs: []
        )

        #expect(confirmed.confidence == .confirmed)
        #expect(variesByStore.confidence == .variesByStore)
        #expect(confirmed != variesByStore)
    }

    @Test func riskFactIsEquatableAcrossIdenticalConstructionsForDeterminism() {
        func makeFact() -> RiskFact {
            RiskFact(
                target: .dietaryRestriction(.halal),
                resolution: .resolved,
                databaseMatches: [
                    RiskFactDatabaseMatch(ingredientID: "pork", confidence: .confirmed, isHiddenIngredient: false, hiddenIngredientCategory: nil, sourceIDs: [])
                ],
                evidence: []
            )
        }

        #expect(makeFact() == makeFact())
    }

    @Test func riskLLMSignalCarriesPolarityTargetAndSourceEvidenceWithoutDatabaseMatching() {
        let sourceEvidence = MenuTextPreprocessingEvidence(
            sourceID: MenuUnderstandingSourceID("s1"),
            rawText: "エビ風味",
            analysisText: nil,
            confidence: 0.7,
            boundingBox: .zero,
            changes: []
        )
        let signal = RiskLLMSignal(
            target: .allergen(.shrimp),
            polarity: .positive,
            sourceText: "エビ風味",
            sourceEvidence: [sourceEvidence]
        )

        #expect(signal.target == .allergen(.shrimp))
        #expect(signal.polarity == .positive)
        #expect(signal.polarity != .negative)
        #expect(signal.sourceText == "エビ風味")
        #expect(signal.sourceEvidence == [sourceEvidence])
    }

    @Test func selectedRiskTargetsPreservesOrderAndDropsDuplicatesFromUserProfile() {
        let profile = UserProfile(
            allergenItems: [.pork, .egg, .pork],
            dietaryRestrictionCategories: [.halal]
        )

        #expect(profile.selectedRiskTargets == [.allergen(.pork), .allergen(.egg), .dietaryRestriction(.halal)])
    }

    @Test func selectedRiskTargetsIsEmptyWhenUserProfileSelectsNothing() {
        let profile = UserProfile()

        #expect(profile.selectedRiskTargets.isEmpty)
    }

    @Test func overallDeterminationPrioritizesLikelyContainsOverUndeterminedOverNoRecordedMatch() {
        #expect(makeEvaluation([.likelyContains]).overallDetermination == .likelyContains)
        #expect(makeEvaluation([.noRecordedMatch, .likelyContains, .undetermined]).overallDetermination == .likelyContains)
        #expect(makeEvaluation([.undetermined]).overallDetermination == .undetermined)
        #expect(makeEvaluation([.noRecordedMatch, .undetermined]).overallDetermination == .undetermined)
        #expect(makeEvaluation([.noRecordedMatch]).overallDetermination == .noRecordedMatch)
        #expect(makeEvaluation([.noRecordedMatch, .noRecordedMatch]).overallDetermination == .noRecordedMatch)
    }

    @Test func overallDeterminationIsNilWhenNoTargetWasEvaluated() {
        #expect(makeEvaluation([]).overallDetermination == nil)
    }

    private func makeEvaluation(_ determinations: [RiskDetermination]) -> MenuItemRiskEvaluation {
        let reference = MenuUnderstandingItemReference(
            ordinal: 0,
            sourceReferences: [MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s1"), rawFragment: "text")],
            separator: "\n"
        )
        let results = determinations.map { RiskEvaluationResult(target: .allergen(.egg), determination: $0, evidence: []) }
        return MenuItemRiskEvaluation(reference: reference, results: results)
    }
}
