import Foundation

/// アプリに同梱した初期料理DB JSONを読み込み、RepositoryへImportするService。
///
/// `dataVersion`を記録することで、同じ初期データの二重Importを避ける。
final class InitialDataImportService {
    private let repository: MenuKnowledgeRepository
    private let decoder: JSONDecoder

    init(repository: MenuKnowledgeRepository, decoder: JSONDecoder = JSONDecoder()) {
        self.repository = repository
        self.decoder = decoder
    }

    func importBundledInitialDataIfNeeded(
        bundle: Bundle = .main,
        resourceName: String = "InitialMenuKnowledgeData"
    ) throws -> InitialDataImportSummary {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw InitialDataImportServiceError.resourceNotFound(resourceName: resourceName)
        }
        let data = try Data(contentsOf: url)
        return try importInitialDataIfNeeded(from: data)
    }

    func importInitialDataIfNeeded(from data: Data) throws -> InitialDataImportSummary {
        let document = try decoder.decode(InitialMenuKnowledgeDocument.self, from: data)

        guard try !repository.hasImportedDataVersion(document.dataVersion) else {
            return InitialDataImportSummary(dataVersion: document.dataVersion, didImport: false)
        }

        for ingredient in document.ingredients {
            try repository.upsertIngredient(Ingredient(
                id: ingredient.id,
                canonicalName: ingredient.canonicalName,
                aliases: ingredient.aliases
            ))
        }

        for dish in document.dishes {
            try repository.upsertDish(Dish(
                id: dish.id,
                canonicalName: dish.canonicalName,
                region: dish.region,
                aliases: dish.aliases
            ))
        }

        for dishIngredient in document.dishIngredients {
            guard let confidence = DishIngredientConfidence(rawValue: dishIngredient.confidence) else {
                throw InitialDataImportServiceError.invalidConfidence(dishIngredient.confidence)
            }
            let hiddenIngredientCategory = try dishIngredient.hiddenIngredientCategory.map { rawValue in
                guard let category = HiddenIngredientCategory(rawValue: rawValue) else {
                    throw InitialDataImportServiceError.invalidHiddenIngredientCategory(rawValue)
                }
                return category
            }

            try repository.upsertDishIngredient(
                dishId: dishIngredient.dishId,
                ingredientId: dishIngredient.ingredientId,
                confidence: confidence,
                isHiddenIngredient: dishIngredient.isHiddenIngredient,
                hiddenIngredientCategory: hiddenIngredientCategory
            )
        }

        try repository.markDataVersionImported(document.dataVersion)

        return InitialDataImportSummary(
            dataVersion: document.dataVersion,
            didImport: true,
            dishCount: document.dishes.count,
            ingredientCount: document.ingredients.count,
            dishIngredientCount: document.dishIngredients.count
        )
    }
}

struct InitialDataImportSummary: Equatable {
    let dataVersion: String
    let didImport: Bool
    let dishCount: Int
    let ingredientCount: Int
    let dishIngredientCount: Int

    init(
        dataVersion: String,
        didImport: Bool,
        dishCount: Int = 0,
        ingredientCount: Int = 0,
        dishIngredientCount: Int = 0
    ) {
        self.dataVersion = dataVersion
        self.didImport = didImport
        self.dishCount = dishCount
        self.ingredientCount = ingredientCount
        self.dishIngredientCount = dishIngredientCount
    }
}

enum InitialDataImportServiceError: Error, Equatable {
    case resourceNotFound(resourceName: String)
    case invalidConfidence(String)
    case invalidHiddenIngredientCategory(String)
}

private struct InitialMenuKnowledgeDocument: Decodable {
    let schemaVersion: Int
    let dataVersion: String
    let description: String
    let sources: [InitialMenuKnowledgeSource]
    let ingredients: [InitialMenuKnowledgeIngredient]
    let dishes: [InitialMenuKnowledgeDish]
    let dishIngredients: [InitialMenuKnowledgeDishIngredient]
}

private struct InitialMenuKnowledgeSource: Decodable {
    let id: String
    let name: String
    let url: URL
    let checkedAt: String
    let notes: String
}

private struct InitialMenuKnowledgeIngredient: Decodable {
    let id: String
    let canonicalName: String
    let aliases: [String]
    let sourceIds: [String]
}

private struct InitialMenuKnowledgeDish: Decodable {
    let id: String
    let canonicalName: String
    let region: String
    let aliases: [String]
    let sourceIds: [String]
}

private struct InitialMenuKnowledgeDishIngredient: Decodable {
    let dishId: String
    let ingredientId: String
    let confidence: String
    let isHiddenIngredient: Bool
    let hiddenIngredientCategory: String?
    let sourceIds: [String]
}
