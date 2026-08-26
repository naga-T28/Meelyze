import Testing
import Foundation
import SwiftData
@testable import Meelyze

/// `RiskFactBuilder`が、UserProfileの選択とDBを突き合わせて`RiskFact`を決定論的に構築できることを
/// 確認するテスト。`Meelyze/Resources/InitialMenuKnowledgeData.json`の実データ（ラフテー等）を使い、
/// 通常食材・隠れ食材・複数一致・DB上の該当なし・未解決/曖昧候補・DB取得失敗を検証する。
struct RiskFactBuilderTests {
    @Test func buildFactsMatchesUserSelectedAllergenAgainstResolvedDishIngredient() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(allergenItems: [.pork])

        let facts = builder.buildFacts(
            for: resolvedDish(id: "rafute", canonicalName: "ラフテー"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 1)
        let fact = try #require(facts.first)
        #expect(fact.target == .allergen(.pork))
        #expect(fact.resolution == .resolved)
        #expect(fact.databaseMatches.count == 1)
        let match = try #require(fact.databaseMatches.first)
        #expect(match.ingredientID == "pork")
        #expect(match.confidence == .confirmed)
        #expect(match.isHiddenIngredient == false)
        #expect(match.hiddenIngredientCategory == nil)
        #expect(Set(match.sourceIDs) == Set(["maff_uchino_rafute", "maff_uchino_goya_chanpuru", "maff_uchino_okinawa_soba"]))
    }

    @Test func buildFactsMatchesUserSelectedDietaryRestrictionAgainstHiddenIngredient() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(dietaryRestrictionCategories: [.vegetarian])

        let facts = builder.buildFacts(
            for: resolvedDish(id: "rafute", canonicalName: "ラフテー"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 1)
        let fact = try #require(facts.first)
        #expect(fact.target == .dietaryRestriction(.vegetarian))
        #expect(fact.resolution == .resolved)
        // かつおだしは料理名に明示されない隠れ食材だが、ベジタリアン制限との一致として検出できる。
        #expect(fact.databaseMatches.count == 1)
        let match = try #require(fact.databaseMatches.first)
        #expect(match.ingredientID == "bonito_dashi")
        #expect(match.isHiddenIngredient == true)
        #expect(match.hiddenIngredientCategory == .dashi)
    }

    @Test func buildFactsIncludesHiddenIngredientsInSameFactAsRegularIngredientsDistinguishedByFlag() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(dietaryRestrictionCategories: [.halal])

        let facts = builder.buildFacts(
            for: resolvedDish(id: "rafute", canonicalName: "ラフテー"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 1)
        let fact = try #require(facts.first)
        #expect(fact.target == .dietaryRestriction(.halal))
        // 豚肉（通常食材・非隠れ）と泡盛（隠れ食材・調味料）の両方がhalal_*制限に一致する。
        #expect(fact.databaseMatches.count == 2)
        let byIngredient = Dictionary(uniqueKeysWithValues: fact.databaseMatches.map { ($0.ingredientID, $0) })
        let porkMatch = try #require(byIngredient["pork"])
        #expect(porkMatch.isHiddenIngredient == false)
        let awamoriMatch = try #require(byIngredient["awamori"])
        #expect(awamoriMatch.isHiddenIngredient == true)
        #expect(awamoriMatch.hiddenIngredientCategory == .seasoning)
        // Evidence側でも隠れ食材かどうかを区別できる。一致2件＋解決根拠（explicit/normalized）1件で3件。
        #expect(fact.evidence.count == 3)
        #expect(Set(fact.evidence.map(\.isHiddenIngredient)) == Set([true, false]))
        #expect(fact.evidence.filter { $0.kind == .dishDatabase }.count == 2)
        #expect(fact.evidence.contains { $0.kind == .explicit || $0.kind == .normalized })
    }

    @Test func buildFactsReturnsEmptyDatabaseMatchesWhenResolvedButNoRecordedLink() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(allergenItems: [.egg])

        let facts = builder.buildFacts(
            for: resolvedDish(id: "rafute", canonicalName: "ラフテー"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 1)
        let fact = try #require(facts.first)
        #expect(fact.resolution == .resolved)
        #expect(fact.databaseMatches.isEmpty)
        // 「解決済みだが一致なし」でも、解決根拠（explicit/normalized）とDB照合結果のEvidenceを保持する。
        #expect(fact.evidence.count == 2)
        #expect(fact.evidence.first?.kind == .explicit)
        #expect(fact.evidence.first?.resolvedEntity == MenuAliasResolvedEntity(id: "rafute", canonicalName: "ラフテー"))
        #expect(fact.evidence.last?.kind == .dishDatabase)
        #expect(fact.evidence.last?.resolvedEntity == MenuAliasResolvedEntity(id: "rafute", canonicalName: "ラフテー"))
    }

    @Test func buildFactsReturnsNoFactsWhenUserProfileSelectsNothing() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile()

        let facts = builder.buildFacts(
            for: resolvedDish(id: "rafute", canonicalName: "ラフテー"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.isEmpty)
    }

    @Test func buildFactsPreservesVariesByStoreConfidenceDistinctFromConfirmedMatch() throws {
        // InitialMenuKnowledgeData.jsonの実データにvariesByStore例がないため、この観点専用の
        // 最小fixtureをRepository経由で直接構築する（実データを改変してテスト用に捏造しない）。
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        try repository.upsertDish(Dish(id: "curry_rice", canonicalName: "カレーライス", region: "unknown"))
        try repository.upsertIngredient(Ingredient(id: "lard", canonicalName: "ラード"))
        try repository.upsertAllergen(Allergen(id: "pork", japaneseName: "豚肉"))
        try repository.upsertIngredientAllergen(ingredientId: "lard", allergenId: "pork", sourceIds: ["store_survey_1"])
        try repository.upsertDishIngredient(
            dishId: "curry_rice",
            ingredientId: "lard",
            confidence: .variesByStore,
            isHiddenIngredient: true,
            hiddenIngredientCategory: .fatOrOil,
            sourceIds: ["store_survey_1"]
        )
        let builder = RiskFactBuilder(repository: repository)
        let profile = makeProfile(allergenItems: [.pork])

        let facts = builder.buildFacts(
            for: resolvedDish(id: "curry_rice", canonicalName: "カレーライス"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 1)
        #expect(facts.first?.resolution == .resolved)
        let match = try #require(facts.first?.databaseMatches.first)
        #expect(match.confidence == .variesByStore)
        #expect(match.confidence != .confirmed)
        #expect(match.isHiddenIngredient == true)
        #expect(match.hiddenIngredientCategory == .fatOrOil)
    }

    @Test func buildFactsOnlyGeneratesFactsForSelectedTargetsNotOtherDBAllergens() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        // ラフテーは実際には醤油（小麦・大豆アレルゲン）も含むが、選択していないtargetのFactは作らない。
        let profile = makeProfile(allergenItems: [.pork])

        let facts = builder.buildFacts(
            for: resolvedDish(id: "rafute", canonicalName: "ラフテー"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.map(\.target) == [.allergen(.pork)])
    }

    @Test func buildFactsHandlesExplicitIngredientCandidateDirectlyWithoutDishIngredientHop() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(allergenItems: [.pork])

        let facts = builder.buildFacts(
            for: resolvedIngredient(id: "pork", canonicalName: "豚肉"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 1)
        let match = try #require(facts.first?.databaseMatches.first)
        #expect(match.ingredientID == "pork")
        // 原文へ明示された食材そのものなので、DishIngredientのconfidence/隠れ食材概念は経由しない。
        #expect(match.confidence == .confirmed)
        #expect(match.isHiddenIngredient == false)
    }

    @Test func buildFactsNeverProducesResolvedOrDatabaseMatchesForUnresolvedCandidate() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(allergenItems: [.pork], dietaryRestrictionCategories: [.halal])

        let facts = builder.buildFacts(
            for: unresolvedCandidate(text: "未登録メニュー"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 2)
        for fact in facts {
            #expect(fact.resolution == .unresolved)
            #expect(fact.databaseMatches.isEmpty)
        }
        #expect(facts.allSatisfy { $0.evidence.count == 1 })
        #expect(facts.allSatisfy { $0.evidence.first?.kind == .unknown })
        #expect(facts.allSatisfy { $0.evidence.first?.inferredOrigin == .unresolvedTerm })
    }

    @Test func buildFactsNeverProducesResolvedOrDatabaseMatchesForAmbiguousCandidate() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(allergenItems: [.pork])
        let ambiguousMatches = [
            MenuAliasResolvedEntity(id: "okinawan_tofu", canonicalName: "沖縄豆腐"),
            MenuAliasResolvedEntity(id: "regular_tofu", canonicalName: "豆腐")
        ]

        let facts = builder.buildFacts(
            for: ambiguousCandidate(text: "豆腐", matches: ambiguousMatches),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 1)
        let fact = try #require(facts.first)
        #expect(fact.resolution == .ambiguous)
        #expect(fact.databaseMatches.isEmpty)
        #expect(fact.evidence.first?.inferredOrigin == .ambiguousCandidates(ambiguousMatches))
    }

    @Test func buildFactsFallsBackToDatabaseUnavailableWhenRepositoryThrows() throws {
        let context = try makeInMemoryContext()
        let realRepository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        _ = try InitialDataImportService(repository: realRepository)
            .importInitialDataIfNeeded(from: Data(contentsOf: initialMenuKnowledgeDataURL()))
        let throwingRepository = ThrowingDishMenuKnowledgeRepository(wrapping: realRepository, failingDishIDs: ["rafute"])
        let builder = RiskFactBuilder(repository: throwingRepository)
        let profile = makeProfile(allergenItems: [.pork])

        let facts = builder.buildFacts(
            for: resolvedDish(id: "rafute", canonicalName: "ラフテー"),
            sourceEvidence: [],
            profile: profile
        )

        #expect(facts.count == 1)
        #expect(facts.first?.resolution == .databaseUnavailable)
        #expect(facts.first?.databaseMatches.isEmpty == true)
        // 解決先のCanonical Entityと、DB取得失敗であること自体がEvidenceとして残る（空にならない）。
        let evidence = try #require(facts.first?.evidence)
        #expect(evidence.count == 2)
        #expect(evidence.first?.kind == .explicit)
        #expect(evidence.first?.resolvedEntity == MenuAliasResolvedEntity(id: "rafute", canonicalName: "ラフテー"))
        #expect(evidence.last?.kind == .unknown)
        #expect(evidence.last?.inferredOrigin == .databaseFetchFailed)
        #expect(evidence.last?.resolvedEntity == MenuAliasResolvedEntity(id: "rafute", canonicalName: "ラフテー"))
    }

    @Test func buildFactsChoosesExplicitOrNormalizedEvidenceBasedOnWhetherNormalizationChangedTheText() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(allergenItems: [.pork])
        let explicitResolution = MenuAliasResolutionEvidence(
            entityType: .dish,
            inputText: "ラフテー",
            normalization: MenuNameNormalizationEvidence(originalText: "ラフテー", normalizedText: "ラフテー", changes: []),
            status: .resolved,
            matches: [MenuAliasResolvedEntity(id: "rafute", canonicalName: "ラフテー")]
        )
        let normalizedResolution = MenuAliasResolutionEvidence(
            entityType: .dish,
            inputText: "らふてー",
            normalization: MenuNameNormalizationEvidence(
                originalText: "らふてー", normalizedText: "ラフテー", changes: [.hiraganaConvertedToKatakana]
            ),
            status: .resolved,
            matches: [MenuAliasResolvedEntity(id: "rafute", canonicalName: "ラフテー")]
        )

        let explicitFacts = builder.buildFacts(for: explicitResolution, sourceEvidence: [], profile: profile)
        let normalizedFacts = builder.buildFacts(for: normalizedResolution, sourceEvidence: [], profile: profile)

        #expect(explicitFacts.first?.evidence.first?.kind == .explicit)
        #expect(normalizedFacts.first?.evidence.first?.kind == .normalized)
    }

    @Test func buildFactsReturnsStableIngredientOrderForMultipleMatchesRegardlessOfInsertionOrder() throws {
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        try repository.upsertDish(Dish(id: "mixed_platter", canonicalName: "盛り合わせ", region: "unknown"))
        try repository.upsertIngredient(Ingredient(id: "z_pork_product", canonicalName: "豚加工品Z"))
        try repository.upsertIngredient(Ingredient(id: "a_pork_product", canonicalName: "豚加工品A"))
        try repository.upsertAllergen(Allergen(id: "pork", japaneseName: "豚肉"))
        // idの降順で登録し、格納順ではなくidの安定ソートで返っていることを検証する。
        try repository.upsertIngredientAllergen(ingredientId: "z_pork_product", allergenId: "pork", sourceIds: [])
        try repository.upsertIngredientAllergen(ingredientId: "a_pork_product", allergenId: "pork", sourceIds: [])
        try repository.upsertDishIngredient(
            dishId: "mixed_platter", ingredientId: "z_pork_product",
            confidence: .confirmed, isHiddenIngredient: false, hiddenIngredientCategory: nil, sourceIds: []
        )
        try repository.upsertDishIngredient(
            dishId: "mixed_platter", ingredientId: "a_pork_product",
            confidence: .confirmed, isHiddenIngredient: false, hiddenIngredientCategory: nil, sourceIds: []
        )
        let builder = RiskFactBuilder(repository: repository)
        let profile = makeProfile(allergenItems: [.pork])
        let resolution = resolvedDish(id: "mixed_platter", canonicalName: "盛り合わせ")

        let firstCall = builder.buildFacts(for: resolution, sourceEvidence: [], profile: profile)
        let secondCall = builder.buildFacts(for: resolution, sourceEvidence: [], profile: profile)

        #expect(firstCall.first?.databaseMatches.map(\.ingredientID) == ["a_pork_product", "z_pork_product"])
        #expect(firstCall == secondCall)
    }

    @Test func buildFactsIsDeterministicAcrossRepeatedCallsWithTheSameInput() throws {
        let builder = try makeBuilderWithInitialMenuKnowledge()
        let profile = makeProfile(allergenItems: [.pork], dietaryRestrictionCategories: [.halal, .vegetarian])
        let resolution = resolvedDish(id: "rafute", canonicalName: "ラフテー")

        let first = builder.buildFacts(for: resolution, sourceEvidence: [], profile: profile)
        let second = builder.buildFacts(for: resolution, sourceEvidence: [], profile: profile)

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    // MARK: - Fixtures

    private func makeBuilderWithInitialMenuKnowledge() throws -> RiskFactBuilder {
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        let service = InitialDataImportService(repository: repository)
        let data = try Data(contentsOf: initialMenuKnowledgeDataURL())
        _ = try service.importInitialDataIfNeeded(from: data)
        return RiskFactBuilder(repository: repository)
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

    private func makeProfile(
        allergenItems: [AllergenItem] = [],
        dietaryRestrictionCategories: [DietaryRestrictionCategory] = []
    ) -> UserProfile {
        UserProfile(allergenItems: allergenItems, dietaryRestrictionCategories: dietaryRestrictionCategories)
    }

    private func resolvedDish(id: String, canonicalName: String) -> MenuAliasResolutionEvidence {
        MenuAliasResolutionEvidence(
            entityType: .dish,
            inputText: canonicalName,
            normalization: MenuNameNormalizationEvidence(originalText: canonicalName, normalizedText: canonicalName, changes: []),
            status: .resolved,
            matches: [MenuAliasResolvedEntity(id: id, canonicalName: canonicalName)]
        )
    }

    private func resolvedIngredient(id: String, canonicalName: String) -> MenuAliasResolutionEvidence {
        MenuAliasResolutionEvidence(
            entityType: .ingredient,
            inputText: canonicalName,
            normalization: MenuNameNormalizationEvidence(originalText: canonicalName, normalizedText: canonicalName, changes: []),
            status: .resolved,
            matches: [MenuAliasResolvedEntity(id: id, canonicalName: canonicalName)]
        )
    }

    private func unresolvedCandidate(text: String) -> MenuAliasResolutionEvidence {
        MenuAliasResolutionEvidence(
            entityType: .dish,
            inputText: text,
            normalization: MenuNameNormalizationEvidence(originalText: text, normalizedText: text, changes: []),
            status: .unresolved,
            matches: []
        )
    }

    private func ambiguousCandidate(text: String, matches: [MenuAliasResolvedEntity]) -> MenuAliasResolutionEvidence {
        MenuAliasResolutionEvidence(
            entityType: .ingredient,
            inputText: text,
            normalization: MenuNameNormalizationEvidence(originalText: text, normalizedText: text, changes: []),
            status: .ambiguous,
            matches: matches
        )
    }
}

/// `dish(id:)`が指定IDについて必ず失敗する、DB取得失敗をシミュレートするためのdecorator。
private final class ThrowingDishMenuKnowledgeRepository: MenuKnowledgeRepository {
    private let wrapped: MenuKnowledgeRepository
    private let failingDishIDs: Set<String>

    init(wrapping wrapped: MenuKnowledgeRepository, failingDishIDs: Set<String>) {
        self.wrapped = wrapped
        self.failingDishIDs = failingDishIDs
    }

    func dish(id: String) throws -> Dish? {
        if failingDishIDs.contains(id) {
            throw SimulatedRepositoryFailure.fetchFailed
        }
        return try wrapped.dish(id: id)
    }

    func dishes(matchingName name: String) throws -> [Dish] { try wrapped.dishes(matchingName: name) }
    func ingredient(id: String) throws -> Ingredient? { try wrapped.ingredient(id: id) }
    func allergen(id: String) throws -> Allergen? { try wrapped.allergen(id: id) }
    func restriction(id: String) throws -> Restriction? { try wrapped.restriction(id: id) }
    func evidenceSource(id: String) throws -> EvidenceSource? { try wrapped.evidenceSource(id: id) }
    func ingredients(matchingName name: String) throws -> [Ingredient] { try wrapped.ingredients(matchingName: name) }
    func upsertDish(_ dish: Dish) throws { try wrapped.upsertDish(dish) }
    func upsertIngredient(_ ingredient: Ingredient) throws { try wrapped.upsertIngredient(ingredient) }
    func upsertAllergen(_ allergen: Allergen) throws { try wrapped.upsertAllergen(allergen) }
    func upsertRestriction(_ restriction: Restriction) throws { try wrapped.upsertRestriction(restriction) }
    func upsertEvidenceSource(_ source: EvidenceSource) throws { try wrapped.upsertEvidenceSource(source) }

    func upsertDishIngredient(
        dishId: String,
        ingredientId: String,
        confidence: DishIngredientConfidence,
        isHiddenIngredient: Bool,
        hiddenIngredientCategory: HiddenIngredientCategory?,
        sourceIds: [String]
    ) throws {
        try wrapped.upsertDishIngredient(
            dishId: dishId,
            ingredientId: ingredientId,
            confidence: confidence,
            isHiddenIngredient: isHiddenIngredient,
            hiddenIngredientCategory: hiddenIngredientCategory,
            sourceIds: sourceIds
        )
    }

    func upsertIngredientAllergen(ingredientId: String, allergenId: String, sourceIds: [String]) throws {
        try wrapped.upsertIngredientAllergen(ingredientId: ingredientId, allergenId: allergenId, sourceIds: sourceIds)
    }

    func upsertIngredientRestriction(ingredientId: String, restrictionId: String, sourceIds: [String]) throws {
        try wrapped.upsertIngredientRestriction(ingredientId: ingredientId, restrictionId: restrictionId, sourceIds: sourceIds)
    }

    func hasImportedDataVersion(_ id: String) throws -> Bool { try wrapped.hasImportedDataVersion(id) }
    func markDataVersionImported(_ id: String) throws { try wrapped.markDataVersionImported(id) }
}

private enum SimulatedRepositoryFailure: Error {
    case fetchFailed
}
