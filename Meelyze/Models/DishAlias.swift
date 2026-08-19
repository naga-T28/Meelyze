import Foundation
import SwiftData

/// 料理名の別名・方言・表記ゆれを表すモデル。
///
/// `Dish.aliases`は検索用の軽量な値配列として残し、このモデルはSwiftData上でAliasを独立して扱うために使う。
@Model
final class DishAlias {
    var value: String
    var dish: Dish?

    init(value: String, dish: Dish? = nil) {
        self.value = value
        self.dish = dish
    }
}
