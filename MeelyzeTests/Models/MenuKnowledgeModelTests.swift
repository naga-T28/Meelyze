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
            Ingredient.self,
            DishIngredient.self,
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
            aliases: ["ゴーヤチャンプルー", "ゴーヤーチャンプル"]
        )

        context.insert(dish)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Dish>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "goya_chanpuru")
        #expect(fetched.first?.canonicalName == "ゴーヤーチャンプルー")
        #expect(fetched.first?.region == "okinawa")
        #expect(fetched.first?.aliases.contains("ゴーヤチャンプルー") == true)
    }

    @Test func ingredientCanBeSavedAndFetched() throws {
        let context = try makeInMemoryContext()
        let ingredient = Ingredient(
            id: "pork",
            canonicalName: "豚肉",
            aliases: ["ポーク", "ぶた肉", "豚"]
        )

        context.insert(ingredient)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Ingredient>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "pork")
        #expect(fetched.first?.canonicalName == "豚肉")
        #expect(fetched.first?.aliases.contains("ポーク") == true)
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
            hiddenIngredientCategory: .dashi
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
