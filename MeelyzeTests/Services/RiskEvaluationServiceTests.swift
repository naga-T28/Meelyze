import Testing
import Foundation
@testable import Meelyze

/// `RiskEvaluationService`が前処理→Menu Understanding→Alias解決→Fact構築→Rule Engineを実際に
/// 結線していること（`MenuTextPreprocessor` `MenuAliasResolver`がテストからのみでなく実経路から
/// 呼ばれること）と、部分失敗時に境界の分かる成功項目を保持しつつ架空の項目を生成しないことを検証する。
struct RiskEvaluationServiceTests {
    @Test func evaluateWiresPreprocessingUnderstandingAliasResolutionFactBuildingAndRuleEngineTogether() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let segment = MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー 980円", confidence: 0.9, boundingBox: .zero)
        let request = MenuUnderstandingRequest(segments: [segment])

        let understandingService = FakeMenuUnderstandingService(
            result: MenuUnderstandingResult(
                request: request,
                items: [makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー 980円", baseDishCandidates: ["ラフテー"])],
                availability: .available,
                failures: []
            )
        )
        let repository = makeRepositoryWithRafuteLinkedToPork()
        let profile = try profile(withAllergens: [.pork])
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)

        let result = await service.evaluate(request, profile: profile)

        // MenuTextPreprocessorが実経路で呼ばれ、価格を除いたanalysisTextがMenuUnderstandingServiceへ渡っている。
        #expect(understandingService.capturedRequest?.segments.first?.analysisText == "ラフテー")
        #expect(understandingService.capturedRequest?.segments.first?.rawText == "ラフテー 980円")

        // MenuAliasResolver→RiskFactBuilder→RiskRuleEngineが実経路で結線され、DB一致からlikelyContainsが出る。
        #expect(result.items.count == 1)
        let evaluation = try #require(result.items.first)
        #expect(evaluation.results.count == 1)
        #expect(evaluation.results.first?.target == .allergen(.pork))
        #expect(evaluation.results.first?.determination == .likelyContains)
        #expect(evaluation.results.first?.evidence.contains { $0.kind == .dishDatabase } == true)
        #expect(result.failures.isEmpty)
    }

    @Test func evaluateKeepsSuccessfulItemsWhenOtherItemsFailAtMenuUnderstanding() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let segment = MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero)
        let request = MenuUnderstandingRequest(segments: [segment])
        let successItem = makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])
        let unrelatedFailure = MenuUnderstandingFailure(
            scope: .sources([MenuUnderstandingSourceID("s2")]),
            reason: .generationFailed(.contextWindowExceeded),
            retryability: .retryable
        )

        let understandingService = FakeMenuUnderstandingService(
            result: MenuUnderstandingResult(request: request, items: [successItem], availability: .available, failures: [unrelatedFailure])
        )
        let repository = makeRepositoryWithRafuteLinkedToPork()
        let profile = try profile(withAllergens: [.pork])
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)

        let result = await service.evaluate(request, profile: profile)

        #expect(result.items.count == 1)
        #expect(result.items.first?.results.first?.determination == .likelyContains)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.scope == .sources([MenuUnderstandingSourceID("s2")]))
        #expect(result.failures.first?.reason == .menuUnderstanding(.generationFailed(.contextWindowExceeded)))
        #expect(result.failures.first?.retryability == .retryable)
    }

    @Test func evaluateNeverFabricatesItemsWhenMenuUnderstandingTotallyFails() async throws {
        let request = MenuUnderstandingRequest(segments: [])
        let failure = MenuUnderstandingFailure(scope: .request, reason: .modelUnavailable(.appleIntelligenceNotEnabled), retryability: .notRetryable)
        let understandingService = FakeMenuUnderstandingService(
            result: MenuUnderstandingResult(request: request, items: [], availability: .unavailable(.appleIntelligenceNotEnabled), failures: [failure])
        )
        let repository = FakeMenuKnowledgeRepository()
        let profile = try profile(withAllergens: [.pork])
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)

        let result = await service.evaluate(request, profile: profile)

        #expect(result.items.isEmpty)
        #expect(result.failures == [RiskEvaluationFailure(scope: .request, reason: .menuUnderstanding(.modelUnavailable(.appleIntelligenceNotEnabled)), retryability: .notRetryable)])
    }

    @Test func evaluateConvertsAliasResolutionRepositoryFailureIntoAnItemScopedFailureWithoutLosingOtherItems() async throws {
        let sourceID1 = MenuUnderstandingSourceID("s1")
        let sourceID2 = MenuUnderstandingSourceID("s2")
        let failingItem = makeParsedItem(sourceID: sourceID1, rawFragment: "謎メニュー", ordinal: 0, baseDishCandidates: ["謎メニュー"])
        let okItem = makeParsedItem(sourceID: sourceID2, rawFragment: "ラフテー", ordinal: 1, baseDishCandidates: ["ラフテー"])
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID1, rawText: "謎メニュー", confidence: 0.9, boundingBox: .zero),
            MenuUnderstandingSourceSegment(id: sourceID2, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero),
        ])
        let understandingService = FakeMenuUnderstandingService(
            result: MenuUnderstandingResult(request: request, items: [failingItem, okItem], availability: .available, failures: [])
        )
        let repository = makeRepositoryWithRafuteLinkedToPork()
        repository.dishNameQueriesThatThrow.insert("謎メニュー")
        let profile = try profile(withAllergens: [.pork])
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)

        let result = await service.evaluate(request, profile: profile)

        #expect(result.items.count == 1)
        #expect(result.items.first?.reference.ordinal == 1)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.scope == .item(failingItem.reference))
        #expect(result.failures.first?.reason == .aliasResolutionFailed)
    }

    @Test func evaluateDoesNotProduceNoRecordedMatchWhenItemHasUnknownTerms() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let segment = MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー 謎の薬味", confidence: 0.9, boundingBox: .zero)
        let request = MenuUnderstandingRequest(segments: [segment])
        let item = makeParsedItem(
            sourceID: sourceID, rawFragment: "ラフテー 謎の薬味", baseDishCandidates: ["ラフテー"], unknownTerms: ["謎の薬味"]
        )
        let understandingService = FakeMenuUnderstandingService(
            result: MenuUnderstandingResult(request: request, items: [item], availability: .available, failures: [])
        )
        // rafuteはpork@confirmedのみを持ち、卵の記録がない（=単独ならnoRecordedMatch候補）。
        let repository = makeRepositoryWithRafuteLinkedToPork()
        let profile = try profile(withAllergens: [.egg])
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)

        let result = await service.evaluate(request, profile: profile)

        #expect(result.items.first?.results.first?.target == .allergen(.egg))
        #expect(result.items.first?.results.first?.determination == .undetermined)
        #expect(result.items.first?.results.first?.determination != .noRecordedMatch)
    }

    @Test func evaluateDowngradesNoRecordedMatchToUndeterminedWhenItemHasScopedMenuUnderstandingFailure() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let segment = MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero)
        let request = MenuUnderstandingRequest(segments: [segment])
        let item = makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])
        let reason = MenuUnderstandingFailureReason.itemValidationFailed(.explicitIngredientsNotInSource(["謎食材"]))
        let itemScopedFailure = MenuUnderstandingFailure(scope: .item(item.reference), reason: reason, retryability: .notRetryable)
        let understandingService = FakeMenuUnderstandingService(
            result: MenuUnderstandingResult(request: request, items: [item], availability: .available, failures: [itemScopedFailure])
        )
        let repository = makeRepositoryWithRafuteLinkedToPork()
        let profile = try profile(withAllergens: [.egg])
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)

        let result = await service.evaluate(request, profile: profile)

        #expect(result.items.first?.results.first?.determination == .undetermined)
        #expect(result.items.first?.results.first?.evidence.contains { $0.inferredOrigin == .itemUnderstandingIncomplete([reason]) } == true)
        // 元のMenuUnderstandingFailureもそのまま透過されている。
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.scope == .item(item.reference))
    }

    @Test func evaluateOnlyDowngradesTheItemWithTheScopedFailureNotSiblingItems() async throws {
        let sourceID1 = MenuUnderstandingSourceID("s1")
        let sourceID2 = MenuUnderstandingSourceID("s2")
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: sourceID1, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero),
            MenuUnderstandingSourceSegment(id: sourceID2, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero),
        ])
        let failingItem = makeParsedItem(sourceID: sourceID1, rawFragment: "ラフテー", ordinal: 0, baseDishCandidates: ["ラフテー"])
        let okItem = makeParsedItem(sourceID: sourceID2, rawFragment: "ラフテー", ordinal: 1, baseDishCandidates: ["ラフテー"])
        let itemScopedFailure = MenuUnderstandingFailure(
            scope: .item(failingItem.reference),
            reason: .outputLimitReached(MenuUnderstandingOutputLimit(field: .explicitIngredients, limit: 6)),
            retryability: .notRetryable
        )
        let understandingService = FakeMenuUnderstandingService(
            result: MenuUnderstandingResult(
                request: request, items: [failingItem, okItem], availability: .available, failures: [itemScopedFailure]
            )
        )
        let repository = makeRepositoryWithRafuteLinkedToPork()
        let profile = try profile(withAllergens: [.egg])
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)

        let result = await service.evaluate(request, profile: profile)

        #expect(result.items.count == 2)
        let failingResult = try #require(result.items.first { $0.reference.ordinal == 0 })
        let okResult = try #require(result.items.first { $0.reference.ordinal == 1 })
        #expect(failingResult.results.first?.determination == .undetermined)
        // 同じrequest内の無関係な他item（failureなし）は影響を受けない。
        #expect(okResult.results.first?.determination == .noRecordedMatch)
    }

    @Test func evaluateDoesNotDowngradeLikelyContainsEvenWithItemScopedFailure() async throws {
        let sourceID = MenuUnderstandingSourceID("s1")
        let segment = MenuUnderstandingSourceSegment(id: sourceID, rawText: "ラフテー", confidence: 0.9, boundingBox: .zero)
        let request = MenuUnderstandingRequest(segments: [segment])
        let item = makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])
        let itemScopedFailure = MenuUnderstandingFailure(
            scope: .item(item.reference),
            reason: .itemValidationFailed(.explicitIngredientsNotInSource(["謎食材"])),
            retryability: .notRetryable
        )
        let understandingService = FakeMenuUnderstandingService(
            result: MenuUnderstandingResult(request: request, items: [item], availability: .available, failures: [itemScopedFailure])
        )
        let repository = makeRepositoryWithRafuteLinkedToPork()
        // rafute→pork@confirmedでlikelyContainsになるはずのtarget。item scope失敗があってもlikelyContainsは動かない。
        let profile = try profile(withAllergens: [.pork])
        let service = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)

        let result = await service.evaluate(request, profile: profile)

        #expect(result.items.first?.results.first?.determination == .likelyContains)
    }

    // MARK: - Fixtures

    private func makeParsedItem(
        sourceID: MenuUnderstandingSourceID,
        rawFragment: String,
        ordinal: Int = 0,
        baseDishCandidates: [String],
        explicitIngredients: [String] = [],
        preparationMethods: [String] = [],
        modifiers: [String] = [],
        unknownTerms: [String] = []
    ) -> ParsedMenuItem {
        ParsedMenuItem(
            reference: MenuUnderstandingItemReference(
                ordinal: ordinal,
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

    private func makeRepositoryWithRafuteLinkedToPork() -> FakeMenuKnowledgeRepository {
        let porkIngredient = Ingredient(id: "pork", canonicalName: "豚肉")
        let porkAllergen = Allergen(id: "pork", japaneseName: "豚肉")
        porkIngredient.allergens = [IngredientAllergen(ingredient: porkIngredient, allergen: porkAllergen, sourceIds: ["maff_uchino_rafute"])]

        let rafuteDish = Dish(id: "rafute", canonicalName: "ラフテー", region: "okinawa")
        let link = DishIngredient(
            dish: rafuteDish,
            ingredient: porkIngredient,
            confidence: .confirmed,
            isHiddenIngredient: false,
            sourceIds: ["maff_uchino_rafute"]
        )
        rafuteDish.ingredients = [link]

        let repository = FakeMenuKnowledgeRepository()
        repository.dishesByName["ラフテー"] = [rafuteDish]
        repository.dishesByID["rafute"] = rafuteDish
        return repository
    }

    private func profile(withAllergens allergens: [AllergenItem]) throws -> UserProfile {
        UserProfile(allergenItems: allergens)
    }
}

/// `MenuUnderstandingService`のfake。渡された`request`を記録し、事前に設定した結果を返す。
/// requestを記録することで、`MenuTextPreprocessor`が実際に呼ばれてから渡されたことを検証できる。
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

/// `MenuKnowledgeRepository`のfake。名前検索・ID検索を辞書で表現し、指定した名前検索クエリを
/// 意図的に失敗させることでDB取得失敗経路を検証できる。
private final class FakeMenuKnowledgeRepository: MenuKnowledgeRepository {
    var dishesByName: [String: [Dish]] = [:]
    var ingredientsByName: [String: [Ingredient]] = [:]
    var dishesByID: [String: Dish] = [:]
    var ingredientsByID: [String: Ingredient] = [:]
    var dishNameQueriesThatThrow: Set<String> = []
    var ingredientNameQueriesThatThrow: Set<String> = []

    func dish(id: String) throws -> Dish? { dishesByID[id] }

    func dishes(matchingName name: String) throws -> [Dish] {
        if dishNameQueriesThatThrow.contains(name) { throw FakeRepositoryError.simulatedFailure }
        return dishesByName[name] ?? []
    }

    func ingredient(id: String) throws -> Ingredient? { ingredientsByID[id] }
    func allergen(id: String) throws -> Allergen? { nil }
    func restriction(id: String) throws -> Restriction? { nil }
    func evidenceSource(id: String) throws -> EvidenceSource? { nil }

    func ingredients(matchingName name: String) throws -> [Ingredient] {
        if ingredientNameQueriesThatThrow.contains(name) { throw FakeRepositoryError.simulatedFailure }
        return ingredientsByName[name] ?? []
    }

    func upsertDish(_ dish: Dish) throws {}
    func upsertIngredient(_ ingredient: Ingredient) throws {}
    func upsertAllergen(_ allergen: Allergen) throws {}
    func upsertRestriction(_ restriction: Restriction) throws {}
    func upsertEvidenceSource(_ source: EvidenceSource) throws {}

    func upsertDishIngredient(
        dishId: String,
        ingredientId: String,
        confidence: DishIngredientConfidence,
        isHiddenIngredient: Bool,
        hiddenIngredientCategory: HiddenIngredientCategory?,
        sourceIds: [String]
    ) throws {}

    func upsertIngredientAllergen(ingredientId: String, allergenId: String, sourceIds: [String]) throws {}
    func upsertIngredientRestriction(ingredientId: String, restrictionId: String, sourceIds: [String]) throws {}
    func hasImportedDataVersion(_ id: String) throws -> Bool { false }
    func markDataVersionImported(_ id: String) throws {}
}

private enum FakeRepositoryError: Error {
    case simulatedFailure
}
