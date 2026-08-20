import Foundation
import SwiftData

/// 食材名の別名・表記ゆれを表すモデル。
///
/// `Ingredient.aliases`は検索用の軽量な値配列として残し、このモデルはSwiftData上でAliasを独立して扱うために使う。
@Model
final class IngredientAlias {
    var value: String
    var ingredient: Ingredient?

    init(value: String, ingredient: Ingredient? = nil) {
        self.value = value
        self.ingredient = ingredient
    }
}
