import Foundation
import SwiftData

/// 料理DBに保存する食材マスタ。
///
/// 料理に含まれる食材を表し、後続のアレルゲン・食事制限判定の起点になる。
@Model
final class Ingredient {
    @Attribute(.unique) var id: String
    var canonicalName: String
    var aliases: [String]
    var sourceIds: [String]
    @Relationship(deleteRule: .cascade, inverse: \IngredientAlias.ingredient)
    var aliasRecords: [IngredientAlias]
    @Relationship(deleteRule: .cascade, inverse: \DishIngredient.ingredient)
    var dishes: [DishIngredient]
    @Relationship(deleteRule: .cascade, inverse: \IngredientAllergen.ingredient)
    var allergens: [IngredientAllergen]
    @Relationship(deleteRule: .cascade, inverse: \IngredientRestriction.ingredient)
    var restrictions: [IngredientRestriction]

    init(
        id: String,
        canonicalName: String,
        aliases: [String] = [],
        sourceIds: [String] = [],
        dishes: [DishIngredient] = [],
        allergens: [IngredientAllergen] = [],
        restrictions: [IngredientRestriction] = []
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.aliases = aliases
        self.sourceIds = sourceIds
        self.aliasRecords = aliases.map { IngredientAlias(value: $0) }
        self.dishes = dishes
        self.allergens = allergens
        self.restrictions = restrictions
    }
}
