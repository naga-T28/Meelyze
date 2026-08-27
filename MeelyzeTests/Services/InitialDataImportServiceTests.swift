import Foundation
import Testing
import SwiftData
@testable import Meelyze

/// InitialDataImportServiceがJSONをSwiftDataへImportできることを確認するテスト。
struct InitialDataImportServiceTests {

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

    @Test func importsInitialDataIntoRepository() throws {
        let context = try makeInMemoryContext()
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: context)
        let service = InitialDataImportService(repository: repository)

        let summary = try service.importInitialDataIfNeeded(from: sampleInitialData)

        #expect(summary == InitialDataImportSummary(
            dataVersion: "test-version-1",
            didImport: true,
            dishCount: 1,
            ingredientCount: 2,
            dishIngredientCount: 2
        ))

        let dish = try #require(try repository.dish(id: "okinawa_soba"))
        #expect(dish.canonicalName == "沖縄そば")
        #expect(dish.sourceIds == ["source_1"])
        #expect(dish.ingredients.count == 2)
        #expect(dish.ingredients.map { $0.ingredient.id }.sorted() == ["pork_bone_dashi", "wheat_noodle"])
        #expect(dish.ingredients.first { $0.ingredient.id == "pork_bone_dashi" }?.sourceIds == ["source_1"])
        let porkBoneDashi = try #require(try repository.ingredient(id: "pork_bone_dashi"))
        #expect(porkBoneDashi.allergens.first?.allergen.id == "pork")
        #expect(porkBoneDashi.restrictions.map { $0.restriction.id }.sorted() == ["halal_pork", "vegetarian_animal_dashi"])
        #expect(try repository.evidenceSource(id: "source_1")?.name == "Test Source")
        #expect(try repository.hasImportedDataVersion("test-version-1") == true)
    }

    @Test func skipsAlreadyImportedDataVersion() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        let service = InitialDataImportService(repository: repository)

        _ = try service.importInitialDataIfNeeded(from: sampleInitialData)
        let summary = try service.importInitialDataIfNeeded(from: sampleInitialData)

        #expect(summary == InitialDataImportSummary(dataVersion: "test-version-1", didImport: false))
    }

    @Test func rejectsUnknownConfidenceValue() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        let service = InitialDataImportService(repository: repository)

        #expect(throws: InitialDataImportServiceError.invalidConfidence("unknown")) {
            try service.importInitialDataIfNeeded(from: invalidConfidenceData)
        }
    }

    /// `MeelyzeTests`はアプリ本体にhostされたUnit Testバンドルのため、`Bundle.main`は
    /// テストバンドルではなくアプリ本体（`Meelyze`）のバンドルを指す。TASK-036で`RootView`が
    /// 起動時に呼ぶ`importBundledInitialDataIfNeeded()`のデフォルト引数と同じ経路
    /// （実際に同梱されたJSONファイル）が壊れていないことを確認する。
    @Test func importsBundledInitialDataFromAppBundle() throws {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        let service = InitialDataImportService(repository: repository)

        let summary = try service.importBundledInitialDataIfNeeded()

        #expect(summary.didImport == true)
        // FIX-012・FIX-016でデモ画像に写る実在料理を追加した際、`dataVersion`を更新した
        // （同梱JSONの`dataVersion`が実際の内容と共に更新されたことを確認する回帰アンカー）。
        #expect(summary.dataVersion == "2026-08-27-demo-dish-expansion-2")
        #expect(summary.dishCount > 0)
        #expect(summary.ingredientCount > 0)
        #expect(summary.dishIngredientCount > 0)
        #expect(try repository.hasImportedDataVersion("2026-08-27-demo-dish-expansion-2") == true)
    }

    private var sampleInitialData: Data {
        """
        {
          "schemaVersion": 1,
          "dataVersion": "test-version-1",
          "description": "Test data",
          "sources": [
            {
              "id": "source_1",
              "name": "Test Source",
              "url": "https://example.com",
              "checkedAt": "2026-08-19",
              "notes": "Test notes"
            }
          ],
          "allergens": [
            {
              "id": "pork",
              "japaneseName": "豚肉"
            },
            {
              "id": "wheat",
              "japaneseName": "小麦"
            }
          ],
          "restrictions": [
            {
              "id": "halal_pork",
              "japaneseName": "豚由来",
              "category": "halal"
            },
            {
              "id": "vegetarian_animal_dashi",
              "japaneseName": "動物性だし",
              "category": "vegetarian"
            }
          ],
          "ingredients": [
            {
              "id": "wheat_noodle",
              "canonicalName": "小麦麺",
              "aliases": ["沖縄そば麺"],
              "allergenIds": ["wheat"],
              "restrictionIds": [],
              "sourceIds": ["source_1"]
            },
            {
              "id": "pork_bone_dashi",
              "canonicalName": "豚骨だし",
              "aliases": ["豚だし"],
              "allergenIds": ["pork"],
              "restrictionIds": ["halal_pork", "vegetarian_animal_dashi"],
              "sourceIds": ["source_1"]
            }
          ],
          "dishes": [
            {
              "id": "okinawa_soba",
              "canonicalName": "沖縄そば",
              "region": "okinawa",
              "aliases": ["沖縄すば"],
              "sourceIds": ["source_1"]
            }
          ],
          "dishIngredients": [
            {
              "dishId": "okinawa_soba",
              "ingredientId": "wheat_noodle",
              "confidence": "confirmed",
              "isHiddenIngredient": false,
              "hiddenIngredientCategory": null,
              "sourceIds": ["source_1"]
            },
            {
              "dishId": "okinawa_soba",
              "ingredientId": "pork_bone_dashi",
              "confidence": "confirmed",
              "isHiddenIngredient": true,
              "hiddenIngredientCategory": "dashi",
              "sourceIds": ["source_1"]
            }
          ]
        }
        """.data(using: .utf8)!
    }

    private var invalidConfidenceData: Data {
        """
        {
          "schemaVersion": 1,
          "dataVersion": "test-version-invalid-confidence",
          "description": "Test data",
          "sources": [
            {
              "id": "source_1",
              "name": "Test Source",
              "url": "https://example.com",
              "checkedAt": "2026-08-19",
              "notes": "Test notes"
            }
          ],
          "allergens": [
            {
              "id": "pork",
              "japaneseName": "豚肉"
            }
          ],
          "restrictions": [],
          "ingredients": [
            {
              "id": "pork",
              "canonicalName": "豚肉",
              "aliases": [],
              "allergenIds": ["pork"],
              "restrictionIds": [],
              "sourceIds": ["source_1"]
            }
          ],
          "dishes": [
            {
              "id": "rafute",
              "canonicalName": "ラフテー",
              "region": "okinawa",
              "aliases": [],
              "sourceIds": ["source_1"]
            }
          ],
          "dishIngredients": [
            {
              "dishId": "rafute",
              "ingredientId": "pork",
              "confidence": "unknown",
              "isHiddenIngredient": false,
              "hiddenIngredientCategory": null,
              "sourceIds": ["source_1"]
            }
          ]
        }
        """.data(using: .utf8)!
    }
}
