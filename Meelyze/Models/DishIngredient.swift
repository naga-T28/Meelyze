import Foundation
import SwiftData

/// 料理と食材の関連について、根拠の強さを表す区分。
enum DishIngredientConfidence: String, CaseIterable, Codable {
    case confirmed
    case typical
    case variesByStore
}

/// 料理名に現れにくい隠れ食材の種類。
enum HiddenIngredientCategory: String, CaseIterable, Codable {
    case dashi
    case seasoning
    case fatOrOil
    case sauce
}

/// 「この料理にこの食材が含まれる」という中間モデル。
///
/// 隠れ食材かどうかや、含有情報の確からしさを保持して、安全側の判定に使う。
@Model
final class DishIngredient {
    var dish: Dish
    var ingredient: Ingredient
    var confidenceRawValue: String
    var isHiddenIngredient: Bool
    var hiddenIngredientCategoryRawValue: String?

    init(
        dish: Dish,
        ingredient: Ingredient,
        confidence: DishIngredientConfidence = .typical,
        isHiddenIngredient: Bool = false,
        hiddenIngredientCategory: HiddenIngredientCategory? = nil
    ) {
        self.dish = dish
        self.ingredient = ingredient
        self.confidenceRawValue = confidence.rawValue
        self.isHiddenIngredient = isHiddenIngredient
        self.hiddenIngredientCategoryRawValue = hiddenIngredientCategory?.rawValue
    }

    var confidence: DishIngredientConfidence {
        get { DishIngredientConfidence(rawValue: confidenceRawValue) ?? .typical }
        set { confidenceRawValue = newValue.rawValue }
    }

    var hiddenIngredientCategory: HiddenIngredientCategory? {
        get {
            guard let hiddenIngredientCategoryRawValue else { return nil }
            return HiddenIngredientCategory(rawValue: hiddenIngredientCategoryRawValue)
        }
        set { hiddenIngredientCategoryRawValue = newValue?.rawValue }
    }
}
