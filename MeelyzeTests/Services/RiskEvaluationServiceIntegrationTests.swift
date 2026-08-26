import Testing
import Foundation
import SwiftData
@testable import Meelyze

/// `RiskEvaluationService`を実SwiftData（`InitialMenuKnowledgeData.json`をインポート済み）に対して
/// 動かす安全性回帰・統合テスト。TASK-029〜033はそれぞれ契約・Fact構築・Rule Engine・Service結線を
/// 個別に検証しているが、本テストは実際の初期データ（ラフテー・ゴーヤーチャンプルー・沖縄そば等）を
/// 使ってend-to-endで判定が決定論的に正しいことを確認する。
///
/// LLM Positive/Negativeシグナルの安全側集約自体は`RiskRuleEngineTests`（TASK-032）の判定表で
/// 網羅済み。`RiskEvaluationService`は`RiskLLMSignalExtractor`（FIX-007）経由で`ParsedMenuItem`
/// からシグナルを自動抽出しRule Engineへ渡す。本ファイルの「LLMシグナルの安全側集約」節は、
/// 実DBから構築したFactへRule Engineが受け取るシグナルを直接組み合わせるテストと、
/// `RiskLLMSignalExtractor`を経由してService自体がシグナルを抽出するend-to-endテストの両方を含む。
struct RiskEvaluationServiceIntegrationTests {
    // MARK: - 実DB統合: DB一致・不一致・隠れ食材

    @Test func evaluateDetectsPorkAllergenInRafuteThroughTheFullPipeline() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let (service, _) = try makeService(items: [
            makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(allergens: [.pork]))

        let evaluation = try #require(result.items.first)
        #expect(evaluation.results.first?.target == .allergen(.pork))
        #expect(evaluation.results.first?.determination == .likelyContains)
    }

    @Test func evaluateDetectsHiddenDashiForVegetarianRestrictionInRafuteThroughTheFullPipeline() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let (service, _) = try makeService(items: [
            makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(restrictions: [.vegetarian]))

        let evaluation = try #require(result.items.first)
        let restrictionResult = try #require(evaluation.results.first { $0.target == .dietaryRestriction(.vegetarian) })
        #expect(restrictionResult.determination == .likelyContains)
        // かつおだしは料理名に明示されない隠れ食材。主要食材と同じ判定対象へ含まれていることを確認する。
        #expect(restrictionResult.evidence.contains { $0.isHiddenIngredient == true && $0.hiddenIngredientCategory == .dashi })
    }

    @Test func evaluateIncludesBothHiddenAndRegularIngredientMatchesForHalalRestrictionInRafute() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let (service, _) = try makeService(items: [
            makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(restrictions: [.halal]))

        let halalResult = try #require(result.items.first?.results.first { $0.target == .dietaryRestriction(.halal) })
        #expect(halalResult.determination == .likelyContains)
        // 豚肉（通常食材）と泡盛（隠れ食材）の両方がhalal制限に一致し、区別を保ったまま集約されている。
        #expect(Set(halalResult.evidence.map(\.isHiddenIngredient)) == Set([true, false]))
    }

    @Test func evaluateReturnsNoRecordedMatchWhenOkinawaSobaHasNoRecordedLinkToTarget() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let (service, _) = try makeService(items: [
            makeParsedItem(sourceID: sourceID, rawFragment: "沖縄そば", baseDishCandidates: ["沖縄そば"])
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "沖縄そば", confidence: 0.9, boundingBox: .zero)
        ])

        // 沖縄そばの初期データには卵アレルゲンの記録がない。
        let result = await service.evaluate(request, profile: profile(allergens: [.egg]))

        #expect(result.items.first?.results.first?.determination == .noRecordedMatch)
    }

    @Test func evaluateDoesNotProduceNoRecordedMatchForKnownDishWithUnknownTermsThroughTheFullPipeline() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let (service, _) = try makeService(items: [
            makeParsedItem(
                sourceID: sourceID, rawFragment: "沖縄そば 謎の薬味", baseDishCandidates: ["沖縄そば"], unknownTerms: ["謎の薬味"]
            )
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "沖縄そば 謎の薬味", confidence: 0.9, boundingBox: .zero)
        ])

        // 沖縄そば単独ならnoRecordedMatch候補（卵の記録なし）だが、未解決語がある限り断定しない。
        let result = await service.evaluate(request, profile: profile(allergens: [.egg]))

        #expect(result.items.first?.results.first?.determination != .noRecordedMatch)
        #expect(result.items.first?.results.first?.determination == .undetermined)
    }

    @Test func evaluateReturnsUndeterminedForADishNameThatCannotBeResolvedInTheRealDatabase() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let (service, _) = try makeService(items: [
            makeParsedItem(sourceID: sourceID, rawFragment: "未登録の創作料理", baseDishCandidates: ["未登録の創作料理"])
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "未登録の創作料理", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(allergens: [.pork]))

        #expect(result.items.first?.results.first?.determination == .undetermined)
    }

    @Test func evaluateReturnsUndeterminedNeverNoRecordedMatchWhenACandidateResolvesAmbiguously() async throws {
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        _ = try InitialDataImportService(repository: repository)
            .importInitialDataIfNeeded(from: Data(contentsOf: initialMenuKnowledgeDataURL()))
        // 実データに、同じaliasを持つ2件目の料理を追加し、意図的に曖昧な解決を作る。
        try repository.upsertDish(Dish(id: "mystery_dish", canonicalName: "謎料理", region: "okinawa", aliases: ["ラフテー"]))

        let sourceID = MenuUnderstandingSourceID("s1")
        let understandingService = FakeMenuUnderstandingService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []),
            items: [makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])],
            availability: .available,
            failures: []
        ))
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(allergens: [.pork]))

        #expect(result.items.first?.results.first?.determination == .undetermined)
    }

    // MARK: - TASK-029回帰: Risk Engine経路での再確認

    @Test func evaluateResolvesKnownOCRLongSoundConfusionAndDetectsPorkThroughTheFullPipeline() async throws {
        // 「ラフテ一」は末尾の「一」が長音記号の既知OCR揺れ。正規化後「ラフテー」としてrafuteへ解決される。
        let sourceID = MenuUnderstandingSourceID("s1")
        let (service, _) = try makeService(items: [
            makeParsedItem(sourceID: sourceID, rawFragment: "ラフテ一", baseDishCandidates: ["ラフテ一"])
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテ一", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(allergens: [.pork]))

        let evidence = try #require(result.items.first?.results.first?.evidence.first)
        #expect(evidence.normalization?.normalizedText == "ラフテー")
        #expect(result.items.first?.results.first?.determination == .likelyContains)
    }

    @Test func evaluateDoesNotOverCorrectLegitimateKanjiOneThroughTheFullPipeline() async throws {
        // 「ビール一杯」「第一だし」「一つ」「一品料理」「メニュー一」は正当な「一」であり、長音化されてはならない。
        // 実DBには該当しないため未解決になるが、正規化結果（Evidence）自体は保持している。
        let cases: [(rawText: String, expectedNormalizedText: String)] = [
            ("ビール一杯", "ビール一杯"),
            ("第一だし", "第一ダシ"),
            ("一つ", "一ツ"),
            ("一品料理", "一品料理"),
            ("メニュー一", "メニュー一"),
        ]

        for testCase in cases {
            let sourceID = MenuUnderstandingSourceID("s1")
            let (service, _) = try makeService(items: [
                makeParsedItem(sourceID: sourceID, rawFragment: testCase.rawText, baseDishCandidates: [testCase.rawText])
            ])
            let request = MenuUnderstandingRequest(segments: [
                MenuUnderstandingSourceSegment(id: sourceID, rawText: testCase.rawText, confidence: 0.9, boundingBox: .zero)
            ])

            let result = await service.evaluate(request, profile: profile(allergens: [.pork]))

            let evidence = try #require(result.items.first?.results.first?.evidence.first, "\(testCase.rawText)")
            #expect(evidence.normalization?.normalizedText == testCase.expectedNormalizedText, "\(testCase.rawText)")
            // 実DBに該当なしのため未解決寄りの判定になるが、長音誤変換によるものではないことが目的。
            #expect(result.items.first?.results.first?.determination != .likelyContains, "\(testCase.rawText)")
        }
    }

    @Test func evaluateStripsDecorativeStarsBeforeMenuUnderstandingAndStillResolvesAgainstRealDatabase() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let understandingService = FakeMenuUnderstandingService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []),
            items: [makeParsedItem(sourceID: sourceID, rawFragment: "★ラフテー★", baseDishCandidates: ["ラフテー"])],
            availability: .available,
            failures: []
        ))
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        _ = try InitialDataImportService(repository: repository)
            .importInitialDataIfNeeded(from: Data(contentsOf: initialMenuKnowledgeDataURL()))
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "★ラフテー★", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(allergens: [.pork]))

        #expect(understandingService.capturedRequest?.segments.first?.analysisText == "ラフテー")
        #expect(result.items.first?.results.first?.determination == .likelyContains)
    }

    @Test func evaluateStripsRepresentativePriceExpressionsBeforeMenuUnderstanding() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let understandingService = FakeMenuUnderstandingService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []),
            items: [makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー 1,280円", baseDishCandidates: ["ラフテー"])],
            availability: .available,
            failures: []
        ))
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        _ = try InitialDataImportService(repository: repository)
            .importInitialDataIfNeeded(from: Data(contentsOf: initialMenuKnowledgeDataURL()))
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー 1,280円", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(allergens: [.pork]))

        #expect(understandingService.capturedRequest?.segments.first?.analysisText == "ラフテー")
        #expect(result.items.first?.results.first?.determination == .likelyContains)
    }

    // MARK: - LLMシグナルの安全側集約（実DB Fact × Rule Engine、およびService経由のend-to-end）
    //
    // 前半2件は、実DBから構築したFactへRiskRuleEngineが受け取るLLMシグナルを直接組み合わせて、
    // 「LLM Negative単独ではnoRecordedMatchを動かさない」「LLM Positiveは矛盾するDB結果を
    // undeterminedへ倒す」というRule Engine自体の安全性を確認する（TASK-032の判定表と対になる）。
    // 後半2件（FIX-007）は、`RiskLLMSignal`を手動構築せず、`RiskEvaluationService`が
    // `RiskLLMSignalExtractor`経由で`ParsedMenuItem`から自動抽出したシグナルだけで
    // 同じ安全性が成立することをend-to-endに確認する。

    @Test func negativeLLMSignalAloneDoesNotProduceOrReinforceNoRecordedMatchAgainstRealCleanDBFact() throws {
        let repository = try makeSeededRepository()
        let factBuilder = RiskFactBuilder(repository: repository)
        let profile = profile(allergens: [.egg])
        // 沖縄そばには卵の記録がなく、Fact単独ではnoRecordedMatch相当のクリーンな結果になる。
        let resolution = resolveDish("沖縄そば", id: "okinawa_soba")
        let facts = factBuilder.buildFacts(for: resolution, sourceEvidence: [], profile: profile)

        let negativeSignal = RiskLLMSignal(target: .allergen(.egg), polarity: .negative, sourceText: "卵の言及なし", sourceEvidence: [])
        let results = RiskRuleEngine().evaluate(targets: profile.selectedRiskTargets, facts: facts, llmSignals: [negativeSignal])

        #expect(results.first?.determination == .noRecordedMatch)
        #expect(!(results.first?.evidence.contains { $0.kind == .llmInference } ?? true))
    }

    @Test func positiveLLMSignalEscalatesAContradictingRealCleanDBResultToUndetermined() throws {
        let repository = try makeSeededRepository()
        let factBuilder = RiskFactBuilder(repository: repository)
        let profile = profile(allergens: [.egg])
        let resolution = resolveDish("沖縄そば", id: "okinawa_soba")
        let facts = factBuilder.buildFacts(for: resolution, sourceEvidence: [], profile: profile)

        let positiveSignal = RiskLLMSignal(target: .allergen(.egg), polarity: .positive, sourceText: "卵とじ風", sourceEvidence: [])
        let results = RiskRuleEngine().evaluate(targets: profile.selectedRiskTargets, facts: facts, llmSignals: [positiveSignal])

        #expect(results.first?.determination == .undetermined)
        #expect(results.first?.evidence.contains { $0.kind == .llmInference && $0.inferredOrigin == .llmPositiveInference } == true)
    }

    @Test func evaluateEscalatesACleanDBResultToUndeterminedWhenAModifierMentionsTheTargetThroughTheFullService() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        // 「卵とじ風」はmodifierとして抽出され、explicitIngredientsには現れない（DBのAlias解決を経由しない）
        // 想定。RiskLLMSignalExtractorがテキストレベルで検出し、Serviceが自動的にRule Engineへ渡す。
        let (service, _) = try makeService(items: [
            makeParsedItem(sourceID: sourceID, rawFragment: "沖縄そば 卵とじ風", baseDishCandidates: ["沖縄そば"], modifiers: ["卵とじ風"])
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "沖縄そば 卵とじ風", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(allergens: [.egg]))

        #expect(result.items.first?.results.first?.determination == .undetermined)
        #expect(result.items.first?.results.first?.evidence.contains { $0.kind == .llmInference } == true)
    }

    @Test func evaluateDoesNotEscalateWhenOnlyTheDishNameCoincidentallyContainsTheTargetKeywordThroughTheFullService() async throws {
        // 「沖縄そば」は小麦麺ベース（そば粉不使用）。baseDishCandidatesはシグナル抽出の対象外のため、
        // そば（buckwheat）アレルギーを選択していても、料理名だけでnoRecordedMatchがundeterminedへ
        // 誤って引き上がらないことを確認する（Plan agentが発見した誤検知の回帰防止）。
        let sourceID = MenuUnderstandingSourceID("s1")
        let (service, _) = try makeService(items: [
            makeParsedItem(sourceID: sourceID, rawFragment: "沖縄そば", baseDishCandidates: ["沖縄そば"])
        ])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID, rawText: "沖縄そば", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.evaluate(request, profile: profile(allergens: [.buckwheat]))

        #expect(result.items.first?.results.first?.determination == .noRecordedMatch)
    }

    // MARK: - Fixtures

    private func makeService(
        items: [ParsedMenuItem],
        failures: [MenuUnderstandingFailure] = []
    ) throws -> (service: DefaultRiskEvaluationService, understandingService: FakeMenuUnderstandingService) {
        let repository = try makeSeededRepository()
        let understandingService = FakeMenuUnderstandingService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []),
            items: items,
            availability: .available,
            failures: failures
        ))
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)
        return (service, understandingService)
    }

    private func makeSeededRepository() throws -> SwiftDataMenuKnowledgeRepository {
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        _ = try InitialDataImportService(repository: repository)
            .importInitialDataIfNeeded(from: Data(contentsOf: initialMenuKnowledgeDataURL()))
        return repository
    }

    private func resolveDish(_ name: String, id: String) -> MenuAliasResolutionEvidence {
        MenuAliasResolutionEvidence(
            entityType: .dish,
            inputText: name,
            normalization: MenuNameNormalizationEvidence(originalText: name, normalizedText: name, changes: []),
            status: .resolved,
            matches: [MenuAliasResolvedEntity(id: id, canonicalName: name)]
        )
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self,
            Dish.self,
            DishAlias.self,
            Ingredient.self,
            IngredientAlias.self,
            DishIngredient.self,
            Allergen.self,
            Restriction.self,
            IngredientAllergen.self,
            IngredientRestriction.self,
            EvidenceSource.self,
            DataImportVersion.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func initialMenuKnowledgeDataURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Meelyze/Resources/InitialMenuKnowledgeData.json")
    }

    private func makeParsedItem(
        sourceID: MenuUnderstandingSourceID,
        rawFragment: String,
        baseDishCandidates: [String],
        explicitIngredients: [String] = [],
        preparationMethods: [String] = [],
        modifiers: [String] = [],
        unknownTerms: [String] = []
    ) -> ParsedMenuItem {
        ParsedMenuItem(
            reference: MenuUnderstandingItemReference(
                ordinal: 0,
                sourceReferences: [MenuUnderstandingSourceReference(sourceID: sourceID, rawFragment: rawFragment)],
                separator: "\n"
            ),
            baseDishCandidates: baseDishCandidates,
            explicitIngredients: explicitIngredients,
            preparationMethods: preparationMethods,
            modifiers: modifiers,
            unknownTerms: unknownTerms
        )
    }

    private func profile(allergens: [AllergenItem] = [], restrictions: [DietaryRestrictionCategory] = []) -> UserProfile {
        UserProfile(allergenItems: allergens, dietaryRestrictionCategories: restrictions)
    }
}

/// `MenuUnderstandingService`のfake。渡された`request`を記録し、事前に設定した結果を返す。
private final class FakeMenuUnderstandingService: MenuUnderstandingService {
    private let result: MenuUnderstandingResult
    private(set) var capturedRequest: MenuUnderstandingRequest?

    init(result: MenuUnderstandingResult) {
        self.result = result
    }

    func availability() async -> MenuUnderstandingAvailability { .available }

    func analyze(_ request: MenuUnderstandingRequest) async -> MenuUnderstandingResult {
        capturedRequest = request
        return result
    }
}
