import Testing
import Foundation
import SwiftData
@testable import Meelyze

struct MenuAliasResolverTests {
    @Test func resolveDishCandidateReturnsResolvedWhenOneAliasMatches() throws {
        let repository = FakeMenuKnowledgeRepository()
        repository.dishesByName["ゴーヤーチャンプルー"] = [
            Dish(id: "goya_chanpuru", canonicalName: "ゴーヤーチャンプルー", region: "okinawa"),
        ]
        let resolver = MenuAliasResolver(repository: repository)

        let evidence = try resolver.resolveDishCandidate("ゴーヤー・チャンプルー")

        #expect(evidence.entityType == .dish)
        #expect(evidence.status == .resolved)
        #expect(evidence.normalization.normalizedText == "ゴーヤーチャンプルー")
        #expect(evidence.matches.map(\.id) == ["goya_chanpuru"])
    }

    @Test func resolveIngredientCandidateClassifiesUnresolvedAndAmbiguous() throws {
        let repository = FakeMenuKnowledgeRepository()
        repository.ingredientsByName["豆腐"] = [
            Ingredient(id: "okinawan_tofu", canonicalName: "沖縄豆腐"),
            Ingredient(id: "regular_tofu", canonicalName: "豆腐"),
        ]
        let resolver = MenuAliasResolver(repository: repository)

        let ambiguous = try resolver.resolveIngredientCandidate("豆腐")
        let unresolved = try resolver.resolveIngredientCandidate("島らっきょう")

        #expect(ambiguous.status == .ambiguous)
        #expect(ambiguous.matches.map(\.id) == ["okinawan_tofu", "regular_tofu"])
        #expect(unresolved.status == .unresolved)
        #expect(unresolved.matches.isEmpty)
    }

    @Test func resolveItemCarriesSourceEvidenceAndDoesNotMakeSafetyJudgments() throws {
        let repository = FakeMenuKnowledgeRepository()
        repository.dishesByName["ラフテー"] = [Dish(id: "rafute", canonicalName: "ラフテー", region: "okinawa")]
        repository.ingredientsByName["豚肉"] = [Ingredient(id: "pork", canonicalName: "豚肉")]
        let resolver = MenuAliasResolver(repository: repository)
        let sourceID = MenuUnderstandingSourceID("s1")
        let reference = MenuUnderstandingItemReference(
            ordinal: 0,
            sourceReferences: [MenuUnderstandingSourceReference(sourceID: sourceID, rawFragment: "ラフテー 豚肉")],
            separator: "\n"
        )
        let item = ParsedMenuItem(
            reference: reference,
            baseDishCandidates: ["ラフテー"],
            explicitIngredients: ["豚肉"],
            preparationMethods: [],
            modifiers: [],
            unknownTerms: []
        )
        let sourceEvidence = MenuTextPreprocessingEvidence(
            sourceID: sourceID,
            rawText: "ラフテー 豚肉 980円",
            analysisText: "ラフテー 豚肉",
            confidence: 0.8,
            boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
            changes: [.priceRemoved]
        )

        let evidence = try resolver.resolve(item, sourceEvidence: [sourceEvidence])

        #expect(evidence.reference.originalText == "ラフテー 豚肉")
        #expect(evidence.sourceEvidence.map(\.sourceID) == [sourceID])
        #expect(evidence.baseDishCandidateResolutions.map(\.status) == [.resolved])
        #expect(evidence.explicitIngredientResolutions.map(\.status) == [.resolved])
    }

    @Test func resolveInitialMenuKnowledgeDishCanonicalNamesAndAliasesWithSwiftDataRepository() throws {
        let resolver = try makeResolverWithInitialMenuKnowledge()

        let expectations: [(input: String, expectedID: String)] = [
            ("ラフテー", "rafute"),
            ("ラフティー", "rafute"),
            ("沖縄風豚角煮", "rafute"),
            ("ラフテ一", "rafute"),
            ("ゴーヤーチャンプルー", "goya_chanpuru"),
            ("ゴーヤー・チャンプルー", "goya_chanpuru"),
            ("ゴーヤチャンプル", "goya_chanpuru"),
            ("沖縄そば", "okinawa_soba"),
            ("おきなわそば", "okinawa_soba"),
            ("沖縄すば", "okinawa_soba"),
            // FIX-012: デモ画像に写る実在料理を追加した際の回帰アンカー。
            ("ソーキそば", "soki_soba"),
            ("軟骨ソーキそば", "soki_soba"),
            ("タコライス", "taco_rice"),
            ("海ぶどう", "umi_budou_dish"),
            ("うみぶどう", "umi_budou_dish"),
            ("ミミガー", "mimigaa"),
            ("みみがー", "mimigaa"),
            ("島らっきょう天ぷら", "shima_rakkyo_tempura"),
            ("島らっきょうの天ぷら", "shima_rakkyo_tempura"),
            ("泡盛", "awamori_drink"),
            ("あわもり", "awamori_drink"),
            ("オリオン生ビール", "orion_draft_beer"),
            ("オリオンビール", "orion_draft_beer"),
            ("生ビール", "draft_beer_generic"),
        ]

        for expectation in expectations {
            let evidence = try resolver.resolveDishCandidate(expectation.input)
            #expect(evidence.status == .resolved)
            #expect(evidence.matches.map(\.id) == [expectation.expectedID])
        }
    }

    @Test func resolveInitialMenuKnowledgeIngredientCanonicalNamesAndAliasesWithSwiftDataRepository() throws {
        let resolver = try makeResolverWithInitialMenuKnowledge()

        let expectations: [(input: String, expectedID: String)] = [
            ("豚肉", "pork"),
            ("豚バラ肉", "pork"),
            ("ポーク", "pork"),
            ("かつおだし", "bonito_dashi"),
            ("鰹だし", "bonito_dashi"),
            ("かつお出汁", "bonito_dashi"),
            ("泡盛", "awamori"),
            ("あわもり", "awamori"),
            ("醤油", "soy_sauce"),
            ("しょうゆ", "soy_sauce"),
            ("ゴーヤー", "goya"),
            ("にがうり", "goya"),
            ("沖縄豆腐", "okinawan_tofu"),
            ("島豆腐", "okinawan_tofu"),
            ("卵", "egg"),
            ("たまご", "egg"),
            ("小麦麺", "wheat_noodle"),
            ("沖縄そば麺", "wheat_noodle"),
            ("豚骨だし", "pork_bone_dashi"),
            ("豚骨出汁", "pork_bone_dashi"),
            // FIX-012: デモ画像に写る実在料理を追加した際の回帰アンカー。
            ("ソーキ", "pork"),
            ("豚耳", "pork"),
            ("牛ひき肉", "beef"),
            ("タコミート", "beef"),
            ("チーズ", "cheese"),
            ("ピーナッツ", "peanut"),
            ("ピーナッツバター", "peanut"),
            ("落花生", "peanut"),
            ("白味噌", "white_miso"),
            ("白みそ", "white_miso"),
            ("クビレズタ", "umi_budou_seaweed"),
            ("島らっきょう", "shima_rakkyo"),
            ("天ぷら衣", "tempura_batter"),
            ("ビール", "beer"),
        ]

        for expectation in expectations {
            let evidence = try resolver.resolveIngredientCandidate(expectation.input)
            #expect(evidence.status == .resolved)
            #expect(evidence.matches.map(\.id) == [expectation.expectedID])
        }
    }

    @Test func resolveInitialMenuKnowledgeKeepsUnknownCandidateUnresolved() throws {
        let resolver = try makeResolverWithInitialMenuKnowledge()

        let evidence = try resolver.resolveDishCandidate("未登録メニュー")

        #expect(evidence.status == .unresolved)
        #expect(evidence.matches.isEmpty)
    }

    private func makeResolverWithInitialMenuKnowledge() throws -> MenuAliasResolver {
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        let service = InitialDataImportService(repository: repository)
        let data = try Data(contentsOf: initialMenuKnowledgeDataURL())
        _ = try service.importInitialDataIfNeeded(from: data)
        return MenuAliasResolver(repository: repository)
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
}

private final class FakeMenuKnowledgeRepository: MenuKnowledgeRepository {
    var dishesByName: [String: [Dish]] = [:]
    var ingredientsByName: [String: [Ingredient]] = [:]

    func dish(id: String) throws -> Dish? { nil }
    func dishes(matchingName name: String) throws -> [Dish] { dishesByName[name] ?? [] }
    func ingredient(id: String) throws -> Ingredient? { nil }
    func allergen(id: String) throws -> Allergen? { nil }
    func restriction(id: String) throws -> Restriction? { nil }
    func evidenceSource(id: String) throws -> EvidenceSource? { nil }
    func ingredients(matchingName name: String) throws -> [Ingredient] { ingredientsByName[name] ?? [] }
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
