import SwiftUI
import SwiftData

@main
struct MeelyzeApp: App {
    private let modelContainer = Self.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }

    /// UI Testからの起動制御。
    ///
    /// `UITEST_STORE_IDENTIFIER`環境変数が指定された場合、その識別子に対応する一時ディレクトリ上の
    /// 専用SwiftDataストアを使用する。テスト間の状態汚染を避けつつ、同一識別子で`terminate()`/
    /// `launch()`をまたいで状態を再現できるようにする（`MeelyzeUITests/OnboardingFlowUITests.swift`）。
    /// 環境変数が指定されない通常起動では、端末の標準永続ストアを使用する。
    private static func makeModelContainer() -> ModelContainer {
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

        guard let storeIdentifier = ProcessInfo.processInfo.environment["UITEST_STORE_IDENTIFIER"] else {
            return try! ModelContainer(for: schema)
        }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITest-\(storeIdentifier).store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
