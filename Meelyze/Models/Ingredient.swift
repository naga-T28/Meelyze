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
    @Relationship(deleteRule: .cascade, inverse: \DishIngredient.ingredient)
    var dishes: [DishIngredient]

    init(
        id: String,
        canonicalName: String,
        aliases: [String] = [],
        dishes: [DishIngredient] = []
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.aliases = aliases
        self.dishes = dishes
    }
}
