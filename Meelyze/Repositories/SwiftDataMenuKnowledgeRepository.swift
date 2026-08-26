import Foundation
import SwiftData

/// SwiftDataの`ModelContext`を通じて料理DBを検索・保存する実装。
///
/// 名前検索は、正規化済み文字列が`canonicalName`または`aliases`に完全一致する前提で扱う。
final class SwiftDataMenuKnowledgeRepository: MenuKnowledgeRepository {
    private let modelContext: ModelContext
    private let nameNormalizer = MenuNameNormalizer()

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
        return dishes
            .filter { dish in
                matchesName(dish.canonicalName, query: name)
                    || dish.aliases.contains { matchesName($0, query: name) }
                    || dish.aliasRecords.contains { matchesName($0.value, query: name) }
            }
            .sorted { $0.id < $1.id }
    }

    func ingredient(id: String) throws -> Ingredient? {
        var descriptor = FetchDescriptor<Ingredient>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func allergen(id: String) throws -> Allergen? {
        var descriptor = FetchDescriptor<Allergen>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func restriction(id: String) throws -> Restriction? {
        var descriptor = FetchDescriptor<Restriction>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func evidenceSource(id: String) throws -> EvidenceSource? {
        var descriptor = FetchDescriptor<EvidenceSource>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func ingredients(matchingName name: String) throws -> [Ingredient] {
        let ingredients = try modelContext.fetch(FetchDescriptor<Ingredient>())
        return ingredients
            .filter { ingredient in
                matchesName(ingredient.canonicalName, query: name)
                    || ingredient.aliases.contains { matchesName($0, query: name) }
                    || ingredient.aliasRecords.contains { matchesName($0.value, query: name) }
            }
            .sorted { $0.id < $1.id }
    }

    func upsertDish(_ dish: Dish) throws {
        if let existingDish = try self.dish(id: dish.id), existingDish !== dish {
            existingDish.canonicalName = dish.canonicalName
            existingDish.region = dish.region
            existingDish.aliases = dish.aliases
            existingDish.sourceIds = dish.sourceIds
            replaceDishAliases(for: existingDish, aliases: dish.aliases)
        } else if dish.modelContext == nil {
            modelContext.insert(dish)
        }
        try modelContext.save()
    }

    func upsertIngredient(_ ingredient: Ingredient) throws {
        if let existingIngredient = try self.ingredient(id: ingredient.id), existingIngredient !== ingredient {
            existingIngredient.canonicalName = ingredient.canonicalName
            existingIngredient.aliases = ingredient.aliases
            existingIngredient.sourceIds = ingredient.sourceIds
            replaceIngredientAliases(for: existingIngredient, aliases: ingredient.aliases)
        } else if ingredient.modelContext == nil {
            modelContext.insert(ingredient)
        }
        try modelContext.save()
    }

    func upsertAllergen(_ allergen: Allergen) throws {
        if let existingAllergen = try self.allergen(id: allergen.id), existingAllergen !== allergen {
            existingAllergen.japaneseName = allergen.japaneseName
        } else if allergen.modelContext == nil {
            modelContext.insert(allergen)
        }
        try modelContext.save()
    }

    func upsertRestriction(_ restriction: Restriction) throws {
        if let existingRestriction = try self.restriction(id: restriction.id), existingRestriction !== restriction {
            existingRestriction.japaneseName = restriction.japaneseName
            existingRestriction.category = restriction.category
        } else if restriction.modelContext == nil {
            modelContext.insert(restriction)
        }
        try modelContext.save()
    }

    func upsertEvidenceSource(_ source: EvidenceSource) throws {
        if let existingSource = try self.evidenceSource(id: source.id), existingSource !== source {
            existingSource.name = source.name
            existingSource.urlString = source.urlString
            existingSource.checkedAt = source.checkedAt
            existingSource.notes = source.notes
        } else if source.modelContext == nil {
            modelContext.insert(source)
        }
        try modelContext.save()
    }

    func upsertDishIngredient(
        dishId: String,
        ingredientId: String,
        confidence: DishIngredientConfidence,
        isHiddenIngredient: Bool,
        hiddenIngredientCategory: HiddenIngredientCategory?,
        sourceIds: [String] = []
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
            existingLink.sourceIds = sourceIds
        } else {
            modelContext.insert(DishIngredient(
                dish: dish,
                ingredient: ingredient,
                confidence: confidence,
                isHiddenIngredient: isHiddenIngredient,
                hiddenIngredientCategory: hiddenIngredientCategory,
                sourceIds: sourceIds
            ))
        }
        try modelContext.save()
    }

    func upsertIngredientAllergen(ingredientId: String, allergenId: String, sourceIds: [String] = []) throws {
        guard let ingredient = try self.ingredient(id: ingredientId), let allergen = try self.allergen(id: allergenId) else {
            throw SwiftDataMenuKnowledgeRepositoryError.missingIngredientOrAllergen(ingredientId: ingredientId, allergenId: allergenId)
        }

        let existingLink = try modelContext.fetch(FetchDescriptor<IngredientAllergen>()).first { link in
            link.ingredient.id == ingredientId && link.allergen.id == allergenId
        }

        if let existingLink {
            existingLink.sourceIds = sourceIds
        } else {
            modelContext.insert(IngredientAllergen(ingredient: ingredient, allergen: allergen, sourceIds: sourceIds))
        }
        try modelContext.save()
    }

    func upsertIngredientRestriction(ingredientId: String, restrictionId: String, sourceIds: [String] = []) throws {
        guard let ingredient = try self.ingredient(id: ingredientId), let restriction = try self.restriction(id: restrictionId) else {
            throw SwiftDataMenuKnowledgeRepositoryError.missingIngredientOrRestriction(ingredientId: ingredientId, restrictionId: restrictionId)
        }

        let existingLink = try modelContext.fetch(FetchDescriptor<IngredientRestriction>()).first { link in
            link.ingredient.id == ingredientId && link.restriction.id == restrictionId
        }

        if let existingLink {
            existingLink.sourceIds = sourceIds
        } else {
            modelContext.insert(IngredientRestriction(ingredient: ingredient, restriction: restriction, sourceIds: sourceIds))
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

    private func matchesName(_ storedName: String, query: String) -> Bool {
        storedName == query || nameNormalizer.normalize(storedName).normalizedText == query
    }

    private func replaceDishAliases(for dish: Dish, aliases: [String]) {
        for alias in dish.aliasRecords {
            modelContext.delete(alias)
        }
        dish.aliasRecords = aliases.map { DishAlias(value: $0, dish: dish) }
    }

    private func replaceIngredientAliases(for ingredient: Ingredient, aliases: [String]) {
        for alias in ingredient.aliasRecords {
            modelContext.delete(alias)
        }
        ingredient.aliasRecords = aliases.map { IngredientAlias(value: $0, ingredient: ingredient) }
    }
}

enum SwiftDataMenuKnowledgeRepositoryError: Error, Equatable {
    case missingDishOrIngredient(dishId: String, ingredientId: String)
    case missingIngredientOrAllergen(ingredientId: String, allergenId: String)
    case missingIngredientOrRestriction(ingredientId: String, restrictionId: String)
}
