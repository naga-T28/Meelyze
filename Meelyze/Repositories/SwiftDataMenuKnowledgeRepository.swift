import Foundation
import SwiftData

/// SwiftDataの`ModelContext`を通じて料理DBを検索・保存する実装。
///
/// 名前検索は、正規化済み文字列が`canonicalName`または`aliases`に完全一致する前提で扱う。
final class SwiftDataMenuKnowledgeRepository: MenuKnowledgeRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func dish(id: String) throws -> Dish? {
        var descriptor = FetchDescriptor<Dish>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func dishes(matchingName name: String) throws -> [Dish] {
        let dishes = try modelContext.fetch(FetchDescriptor<Dish>())
        return dishes.filter { dish in
            dish.canonicalName == name || dish.aliases.contains(name)
        }
    }

    func ingredient(id: String) throws -> Ingredient? {
        var descriptor = FetchDescriptor<Ingredient>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func ingredients(matchingName name: String) throws -> [Ingredient] {
        let ingredients = try modelContext.fetch(FetchDescriptor<Ingredient>())
        return ingredients.filter { ingredient in
            ingredient.canonicalName == name || ingredient.aliases.contains(name)
        }
    }

    func upsertDish(_ dish: Dish) throws {
        if let existingDish = try self.dish(id: dish.id), existingDish !== dish {
            existingDish.canonicalName = dish.canonicalName
            existingDish.region = dish.region
            existingDish.aliases = dish.aliases
        } else if dish.modelContext == nil {
            modelContext.insert(dish)
        }
        try modelContext.save()
    }

    func upsertIngredient(_ ingredient: Ingredient) throws {
        if let existingIngredient = try self.ingredient(id: ingredient.id), existingIngredient !== ingredient {
            existingIngredient.canonicalName = ingredient.canonicalName
            existingIngredient.aliases = ingredient.aliases
        } else if ingredient.modelContext == nil {
            modelContext.insert(ingredient)
        }
        try modelContext.save()
    }

    func upsertDishIngredient(
        dishId: String,
        ingredientId: String,
        confidence: DishIngredientConfidence,
        isHiddenIngredient: Bool,
        hiddenIngredientCategory: HiddenIngredientCategory?
    ) throws {
        guard let dish = try self.dish(id: dishId), let ingredient = try self.ingredient(id: ingredientId) else {
            throw SwiftDataMenuKnowledgeRepositoryError.missingDishOrIngredient(dishId: dishId, ingredientId: ingredientId)
        }

        let existingLink = try modelContext.fetch(FetchDescriptor<DishIngredient>()).first { link in
            link.dish.id == dishId && link.ingredient.id == ingredientId
        }

        if let existingLink {
            existingLink.confidence = confidence
            existingLink.isHiddenIngredient = isHiddenIngredient
            existingLink.hiddenIngredientCategory = hiddenIngredientCategory
        } else {
            modelContext.insert(DishIngredient(
                dish: dish,
                ingredient: ingredient,
                confidence: confidence,
                isHiddenIngredient: isHiddenIngredient,
                hiddenIngredientCategory: hiddenIngredientCategory
            ))
        }
        try modelContext.save()
    }

    func hasImportedDataVersion(_ id: String) throws -> Bool {
        var descriptor = FetchDescriptor<DataImportVersion>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first != nil
    }

    func markDataVersionImported(_ id: String) throws {
        if let existingVersion = try dataImportVersion(id: id) {
            existingVersion.importedAt = Date()
        } else {
            modelContext.insert(DataImportVersion(id: id))
        }
        try modelContext.save()
    }

    private func dataImportVersion(id: String) throws -> DataImportVersion? {
        var descriptor = FetchDescriptor<DataImportVersion>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

enum SwiftDataMenuKnowledgeRepositoryError: Error, Equatable {
    case missingDishOrIngredient(dishId: String, ingredientId: String)
}
