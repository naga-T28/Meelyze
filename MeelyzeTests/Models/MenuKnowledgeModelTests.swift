import Testing
import SwiftData
@testable import Meelyze

/// Dish / Ingredient が SwiftData に保存・取得できることを確認するテスト。
///
/// Issue #12 の最初の土台として、料理DBモデルがインメモリの ModelContainer 上で
/// 正しく永続化対象として扱われることを検証する。
struct MenuKnowledgeModelTests {

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

    @Test func dishCanBeSavedAndFetched() throws {
        let context = try makeInMemoryContext()
        let dish = Dish(
            id: "goya_chanpuru",
            canonicalName: "ゴーヤーチャンプルー",
            region: "okinawa",
            aliases: ["ゴーヤチャンプルー", "ゴーヤーチャンプル"],
            sourceIds: ["source_1"]
        )

        context.insert(dish)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Dish>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "goya_chanpuru")
        #expect(fetched.first?.canonicalName == "ゴーヤーチャンプルー")
        #expect(fetched.first?.region == "okinawa")
        #expect(fetched.first?.aliases.contains("ゴーヤチャンプルー") == true)
        #expect(fetched.first?.aliasRecords.map(\.value).contains("ゴーヤチャンプルー") == true)
        #expect(fetched.first?.sourceIds == ["source_1"])
    }

    @Test func ingredientCanBeSavedAndFetched() throws {
        let context = try makeInMemoryContext()
        let ingredient = Ingredient(
            id: "pork",
            canonicalName: "豚肉",
            aliases: ["ポーク", "ぶた肉", "豚"],
            sourceIds: ["source_1"]
        )

        context.insert(ingredient)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Ingredient>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "pork")
        #expect(fetched.first?.canonicalName == "豚肉")
        #expect(fetched.first?.aliases.contains("ポーク") == true)
        #expect(fetched.first?.aliasRecords.map(\.value).contains("ポーク") == true)
        #expect(fetched.first?.sourceIds == ["source_1"])
    }

    @Test func dishIngredientConnectsDishAndIngredient() throws {
        let context = try makeInMemoryContext()
        let dish = Dish(
            id: "okinawa_soba",
            canonicalName: "沖縄そば",
            region: "okinawa"
        )
        let ingredient = Ingredient(
            id: "bonito_dashi",
            canonicalName: "かつおだし",
            aliases: ["鰹だし", "かつお出汁"]
        )
        let dishIngredient = DishIngredient(
            dish: dish,
            ingredient: ingredient,
            confidence: .typical,
            isHiddenIngredient: true,
            hiddenIngredientCategory: .dashi,
            sourceIds: ["source_1"]
        )

        context.insert(dish)
        context.insert(ingredient)
        context.insert(dishIngredient)
        try context.save()

        let fetchedDishes = try context.fetch(FetchDescriptor<Dish>())
        let fetchedDish = try #require(fetchedDishes.first)
        let fetchedLink = try #require(fetchedDish.ingredients.first)

        #expect(fetchedLink.ingredient.id == "bonito_dashi")
        #expect(fetchedLink.confidence == .typical)
        #expect(fetchedLink.isHiddenIngredient == true)
        #expect(fetchedLink.hiddenIngredientCategory == .dashi)
        #expect(fetchedLink.sourceIds == ["source_1"])
    }

    @Test func ingredientConnectsToAllergenAndRestriction() throws {
        let context = try makeInMemoryContext()
        let ingredient = Ingredient(id: "pork", canonicalName: "豚肉")
        let allergen = Allergen(id: "pork", japaneseName: "豚肉")
        let restriction = Restriction(id: "halal_pork", japaneseName: "豚由来", category: .halal)

        context.insert(ingredient)
        context.insert(allergen)
        context.insert(restriction)
        context.insert(IngredientAllergen(ingredient: ingredient, allergen: allergen, sourceIds: ["source_1"]))
        context.insert(IngredientRestriction(ingredient: ingredient, restriction: restriction, sourceIds: ["source_1"]))
        try context.save()

        let fetchedIngredient = try #require(try context.fetch(FetchDescriptor<Ingredient>()).first)

        #expect(fetchedIngredient.allergens.first?.allergen.id == "pork")
        #expect(fetchedIngredient.allergens.first?.sourceIds == ["source_1"])
        #expect(fetchedIngredient.restrictions.first?.restriction.id == "halal_pork")
        #expect(fetchedIngredient.restrictions.first?.restriction.category == .halal)
    }

    @Test func evidenceSourceCanBeSavedAndFetched() throws {
        let context = try makeInMemoryContext()
        let source = EvidenceSource(
            id: "source_1",
            name: "Test Source",
            urlString: "https://example.com",
            checkedAt: "2026-08-19",
            notes: "Test notes"
        )

        context.insert(source)
        try context.save()

        let fetchedSource = try #require(try context.fetch(FetchDescriptor<EvidenceSource>()).first)

        #expect(fetchedSource.id == "source_1")
        #expect(fetchedSource.urlString == "https://example.com")
    }

    @Test func dataImportVersionCanBeSavedAndFetched() throws {
        let context = try makeInMemoryContext()
        let version = DataImportVersion(id: "2026-08-19-initial-menu-knowledge")

        context.insert(version)
        try context.save()

        let fetchedVersions = try context.fetch(FetchDescriptor<DataImportVersion>())

        #expect(fetchedVersions.count == 1)
        #expect(fetchedVersions.first?.id == "2026-08-19-initial-menu-knowledge")
    }
}
