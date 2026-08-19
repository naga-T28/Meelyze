import Testing
import SwiftData
@testable import Meelyze

/// SwiftDataMenuKnowledgeRepositoryが料理・食材を検索/保存できることを確認するテスト。
struct SwiftDataMenuKnowledgeRepositoryTests {

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

    @Test func upsertDishInsertsAndFetchesByID() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        let dish = Dish(
            id: "rafute",
            canonicalName: "ラフテー",
            region: "okinawa",
            aliases: ["らふてー", "豚角煮"]
        )

        try repository.upsertDish(dish)
        let fetched = try #require(try repository.dish(id: "rafute"))

        #expect(fetched.canonicalName == "ラフテー")
        #expect(fetched.region == "okinawa")
        #expect(fetched.aliases == ["らふてー", "豚角煮"])
    }

    @Test func dishesMatchingNameFindsCanonicalNameAndAlias() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        try repository.upsertDish(Dish(
            id: "goya_chanpuru",
            canonicalName: "ゴーヤーチャンプルー",
            region: "okinawa",
            aliases: ["ゴーヤチャンプルー", "ゴーヤーチャンプル"]
        ))

        #expect(try repository.dishes(matchingName: "ゴーヤーチャンプルー").map(\.id) == ["goya_chanpuru"])
        #expect(try repository.dishes(matchingName: "ゴーヤチャンプルー").map(\.id) == ["goya_chanpuru"])
        #expect(try repository.dishes(matchingName: "沖縄そば").isEmpty)
    }

    @Test func upsertDishUpdatesExistingRecord() throws {
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)

        try repository.upsertDish(Dish(id: "okinawa_soba", canonicalName: "沖縄そば", region: "okinawa"))
        try repository.upsertDish(Dish(
            id: "okinawa_soba",
            canonicalName: "沖縄そば",
            region: "okinawa",
            aliases: ["沖縄すば"]
        ))

        let allDishes = try context.fetch(FetchDescriptor<Dish>())
        #expect(allDishes.count == 1)
        #expect(allDishes.first?.aliases == ["沖縄すば"])
    }

    @Test func upsertIngredientInsertsAndFetchesByID() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        let ingredient = Ingredient(
            id: "pork",
            canonicalName: "豚肉",
            aliases: ["ポーク", "豚"]
        )

        try repository.upsertIngredient(ingredient)
        let fetched = try #require(try repository.ingredient(id: "pork"))

        #expect(fetched.canonicalName == "豚肉")
        #expect(fetched.aliases == ["ポーク", "豚"])
    }

    @Test func ingredientsMatchingNameFindsCanonicalNameAndAlias() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        try repository.upsertIngredient(Ingredient(
            id: "bonito_dashi",
            canonicalName: "かつおだし",
            aliases: ["鰹だし", "かつお出汁"]
        ))

        #expect(try repository.ingredients(matchingName: "かつおだし").map(\.id) == ["bonito_dashi"])
        #expect(try repository.ingredients(matchingName: "鰹だし").map(\.id) == ["bonito_dashi"])
        #expect(try repository.ingredients(matchingName: "卵").isEmpty)
    }

    @Test func upsertIngredientUpdatesExistingRecord() throws {
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)

        try repository.upsertIngredient(Ingredient(id: "egg", canonicalName: "卵"))
        try repository.upsertIngredient(Ingredient(id: "egg", canonicalName: "卵", aliases: ["玉子"]))

        let allIngredients = try context.fetch(FetchDescriptor<Ingredient>())
        #expect(allIngredients.count == 1)
        #expect(allIngredients.first?.aliases == ["玉子"])
    }

    @Test func upsertDishIngredientConnectsExistingDishAndIngredient() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        try repository.upsertDish(Dish(id: "rafute", canonicalName: "ラフテー", region: "okinawa"))
        try repository.upsertIngredient(Ingredient(id: "pork", canonicalName: "豚肉"))

        try repository.upsertDishIngredient(
            dishId: "rafute",
            ingredientId: "pork",
            confidence: .confirmed,
            isHiddenIngredient: false,
            hiddenIngredientCategory: nil
        )

        let fetchedDish = try #require(try repository.dish(id: "rafute"))
        let link = try #require(fetchedDish.ingredients.first)

        #expect(link.ingredient.id == "pork")
        #expect(link.confidence == .confirmed)
        #expect(link.isHiddenIngredient == false)
    }

    @Test func markDataVersionImportedRecordsImportState() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())

        #expect(try repository.hasImportedDataVersion("version-1") == false)

        try repository.markDataVersionImported("version-1")

        #expect(try repository.hasImportedDataVersion("version-1") == true)
    }
}
