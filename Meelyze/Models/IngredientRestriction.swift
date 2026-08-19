import Foundation
import SwiftData

/// 食材と食事制限タグの関連を表すモデル。
@Model
final class IngredientRestriction {
    var ingredient: Ingredient
    var restriction: Restriction
    var sourceIds: [String]

    init(ingredient: Ingredient, restriction: Restriction, sourceIds: [String] = []) {
        self.ingredient = ingredient
        self.restriction = restriction
        self.sourceIds = sourceIds
    }
}
