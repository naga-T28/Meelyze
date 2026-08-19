import Foundation
import SwiftData

/// 料理DBに保存する料理マスタ。
///
/// OCR/LLMで抽出した料理名を、`id`・正規名・別名で照合するための土台になる。
@Model
final class Dish {
    @Attribute(.unique) var id: String
    var canonicalName: String
    var region: String
    var aliases: [String]
    @Relationship(deleteRule: .cascade, inverse: \DishIngredient.dish)
    var ingredients: [DishIngredient]

    init(
        id: String,
        canonicalName: String,
        region: String,
        aliases: [String] = [],
        ingredients: [DishIngredient] = []
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.region = region
        self.aliases = aliases
        self.ingredients = ingredients
    }
}
