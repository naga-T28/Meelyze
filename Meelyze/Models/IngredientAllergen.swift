import Foundation
import SwiftData

/// 食材とアレルゲンの関連を表すモデル。
@Model
final class IngredientAllergen {
    var ingredient: Ingredient
    var allergen: Allergen
    var sourceIds: [String]

    init(ingredient: Ingredient, allergen: Allergen, sourceIds: [String] = []) {
        self.ingredient = ingredient
        self.allergen = allergen
        self.sourceIds = sourceIds
    }
}
