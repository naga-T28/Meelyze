import Testing
import Foundation
@testable import Meelyze

/// `RiskRuleEngine`が、DB Fact由来の一致/不一致とLLM Positive/Negativeシグナルから、安全側の三値を
/// 決定論的に導出できることを確認する判定表テスト。
struct RiskRuleEngineTests {
    private let target = RiskTarget.allergen(.pork)

    @Test func judgmentTableCoversMainDatabaseAndLLMSignalCombinations() {
        struct Case {
            let name: String
            let facts: [RiskFact]
            let signals: [RiskLLMSignal]
            let expected: RiskDetermination
        }

        let cases: [Case] = [
            Case(name: "DB確定一致(confirmed)のみ", facts: [resolvedFact(matches: [match(.confirmed)])], signals: [], expected: .likelyContains),
            Case(name: "DB確定一致(typical)のみ", facts: [resolvedFact(matches: [match(.typical)])], signals: [], expected: .likelyContains),
            Case(name: "DB解決済み・一致なし・不確実性なし", facts: [resolvedFact(matches: [])], signals: [], expected: .noRecordedMatch),
            Case(name: "未解決語あり", facts: [unresolvedFact()], signals: [], expected: .undetermined),
            Case(name: "曖昧候補あり", facts: [ambiguousFact()], signals: [], expected: .undetermined),
            Case(name: "DB取得失敗", facts: [databaseUnavailableFact()], signals: [], expected: .undetermined),
            Case(name: "variesByStoreのみの一致", facts: [resolvedFact(matches: [match(.variesByStore)])], signals: [], expected: .undetermined),
            Case(name: "選択targetだがFactが1件もない", facts: [], signals: [], expected: .undetermined),
            Case(name: "DB一致なし + LLM Positive（矛盾）", facts: [resolvedFact(matches: [])], signals: [positiveSignal()], expected: .undetermined),
            Case(name: "DB一致なし + LLM Negative", facts: [resolvedFact(matches: [])], signals: [negativeSignal()], expected: .noRecordedMatch),
            Case(name: "DB確定一致 + LLM Negative（下げない）", facts: [resolvedFact(matches: [match(.confirmed)])], signals: [negativeSignal()], expected: .likelyContains),
            Case(name: "DB確定一致 + LLM Positive（変化なし）", facts: [resolvedFact(matches: [match(.confirmed)])], signals: [positiveSignal()], expected: .likelyContains),
            Case(name: "Factなし + LLM Positiveのみ", facts: [], signals: [positiveSignal()], expected: .undetermined),
            Case(name: "Factなし + LLM Negativeのみ", facts: [], signals: [negativeSignal()], expected: .undetermined),
            Case(
                name: "複数解釈: 片方確定一致・片方未解決",
                facts: [resolvedFact(matches: [match(.confirmed)]), unresolvedFact()],
                signals: [],
                expected: .likelyContains
            ),
            Case(
                name: "複数解釈: 両方とも一致なし・不確実性なし",
                facts: [resolvedFact(matches: []), resolvedFact(matches: [])],
                signals: [],
                expected: .noRecordedMatch
            ),
            Case(
                name: "複数解釈: 片方一致なし・片方曖昧",
                facts: [resolvedFact(matches: []), ambiguousFact()],
                signals: [],
                expected: .undetermined
            ),
        ]

        let engine = RiskRuleEngine()
        for testCase in cases {
            let results = engine.evaluate(targets: [target], facts: testCase.facts, llmSignals: testCase.signals)
            #expect(results.count == 1, "\(testCase.name)")
            #expect(results.first?.determination == testCase.expected, "\(testCase.name)")
        }
    }

    @Test func likelyContainsAttachesDishDatabaseEvidenceFromTheMatchingFact() throws {
        let fact = resolvedFact(matches: [match(.confirmed, isHidden: true, category: .dashi)])
        let engine = RiskRuleEngine()

        let results = engine.evaluate(targets: [target], facts: [fact])

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.determination == .likelyContains)
        #expect(result.evidence == fact.evidence)
        // 隠れ食材由来でも通常食材と同じ判定対象として扱われ、Evidence上で区別だけ保持される。
        #expect(result.evidence.first?.isHiddenIngredient == true)
        #expect(result.evidence.first?.hiddenIngredientCategory == .dashi)
    }

    @Test func llmPositiveEvidenceIsAttachedEvenWhenDeterminationIsAlreadyLikelyContains() throws {
        let fact = resolvedFact(matches: [match(.confirmed)])
        let engine = RiskRuleEngine()

        let results = engine.evaluate(targets: [target], facts: [fact], llmSignals: [positiveSignal(text: "エビ風味")])

        let result = try #require(results.first)
        #expect(result.determination == .likelyContains)
        #expect(result.evidence.count == fact.evidence.count + 1)
        let llmEvidence = try #require(result.evidence.last)
        #expect(llmEvidence.kind == .llmInference)
        #expect(llmEvidence.inferredOrigin == .llmPositiveInference)
    }

    @Test func negativeSignalProducesNoEvidenceAndNeverChangesDetermination() throws {
        let cleanFact = resolvedFact(matches: [])
        let engine = RiskRuleEngine()

        let results = engine.evaluate(targets: [target], facts: [cleanFact], llmSignals: [negativeSignal(text: "言及なし")])

        let result = try #require(results.first)
        #expect(result.determination == .noRecordedMatch)
        #expect(result.evidence == cleanFact.evidence)
        #expect(!result.evidence.contains { $0.kind == .llmInference })
    }

    @Test func evaluateNeverOmitsASelectedTargetEvenWithoutAnyFactsOrSignals() {
        let engine = RiskRuleEngine()

        let results = engine.evaluate(targets: [target], facts: [], llmSignals: [])

        #expect(results.map(\.target) == [target])
        #expect(results.first?.determination == .undetermined)
        #expect(results.first?.evidence.isEmpty == true)
    }

    @Test func evaluateReturnsResultsForExplicitTargetsFirstThenAnyExtraTargetsFoundOnlyInSignals() {
        let porkFact = RiskFact(target: .allergen(.pork), resolution: .resolved, databaseMatches: [], evidence: [])
        let halalFact = RiskFact(target: .dietaryRestriction(.halal), resolution: .resolved, databaseMatches: [], evidence: [])
        // eggはUserProfileの選択targetには含めていないが、シグナル側にだけ現れる防御的なケース。
        let eggSignal = RiskLLMSignal(target: .allergen(.egg), polarity: .positive, sourceText: "卵風味", sourceEvidence: [])
        let engine = RiskRuleEngine()

        let results = engine.evaluate(
            targets: [.allergen(.pork), .dietaryRestriction(.halal)],
            facts: [porkFact, halalFact],
            llmSignals: [eggSignal]
        )

        #expect(results.map(\.target) == [.allergen(.pork), .dietaryRestriction(.halal), .allergen(.egg)])
    }

    @Test func ruleEngineSourceDoesNotImportSwiftDataOrReferenceMenuKnowledgeRepository() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Meelyze/Services/RiskRuleEngine.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        #expect(!source.contains("import SwiftData"))
        #expect(!source.contains("MenuKnowledgeRepository"))
    }

    // MARK: - Fixtures

    /// `RiskFactBuilder`が実際に生成する形（一致ごとに1件のEvidence、一致なしでも1件の確認Evidence）を
    /// 模したFact。matchesとevidenceの対応が崩れるとテストの意味がなくなるため、ここで揃えて構築する。
    private func resolvedFact(matches: [RiskFactDatabaseMatch]) -> RiskFact {
        let evidence: [RiskEvidence]
        if matches.isEmpty {
            evidence = [RiskEvidence(kind: .dishDatabase)]
        } else {
            evidence = matches.map { match in
                RiskEvidence(
                    kind: .dishDatabase,
                    databaseSourceIDs: match.sourceIDs,
                    isHiddenIngredient: match.isHiddenIngredient,
                    hiddenIngredientCategory: match.hiddenIngredientCategory
                )
            }
        }
        return RiskFact(target: target, resolution: .resolved, databaseMatches: matches, evidence: evidence)
    }

    private func unresolvedFact() -> RiskFact {
        RiskFact(
            target: target,
            resolution: .unresolved,
            databaseMatches: [],
            evidence: [RiskEvidence(kind: .unknown, inferredOrigin: .unresolvedTerm)]
        )
    }

    private func ambiguousFact() -> RiskFact {
        RiskFact(
            target: target,
            resolution: .ambiguous,
            databaseMatches: [],
            evidence: [RiskEvidence(kind: .unknown, inferredOrigin: .ambiguousCandidates([]))]
        )
    }

    private func databaseUnavailableFact() -> RiskFact {
        RiskFact(target: target, resolution: .databaseUnavailable, databaseMatches: [], evidence: [])
    }

    private func match(
        _ confidence: DishIngredientConfidence,
        isHidden: Bool = false,
        category: HiddenIngredientCategory? = nil
    ) -> RiskFactDatabaseMatch {
        RiskFactDatabaseMatch(
            ingredientID: "test_ingredient",
            confidence: confidence,
            isHiddenIngredient: isHidden,
            hiddenIngredientCategory: category,
            sourceIDs: []
        )
    }

    private func positiveSignal(text: String = "エビ風味") -> RiskLLMSignal {
        RiskLLMSignal(target: target, polarity: .positive, sourceText: text, sourceEvidence: [])
    }

    private func negativeSignal(text: String = "言及なし") -> RiskLLMSignal {
        RiskLLMSignal(target: target, polarity: .negative, sourceText: text, sourceEvidence: [])
    }
}
