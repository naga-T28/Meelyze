import Foundation

/// 料理DBへのアクセスを担うProtocol。
///
/// ViewModelやServiceはこのProtocol経由で料理・食材を検索し、SwiftDataの具体実装には直接依存しない。
protocol MenuKnowledgeRepository {
    /// 料理IDで料理を検索する。該当がなければ`nil`を返す。
    func dish(id: String) throws -> Dish?

    /// 正規名または別名に一致する料理を検索する。
    func dishes(matchingName name: String) throws -> [Dish]

    /// 食材IDで食材を検索する。該当がなければ`nil`を返す。
    func ingredient(id: String) throws -> Ingredient?

    /// アレルゲンIDでアレルゲンを検索する。該当がなければ`nil`を返す。
    func allergen(id: String) throws -> Allergen?

    /// 食事制限タグIDでタグを検索する。該当がなければ`nil`を返す。
    func restriction(id: String) throws -> Restriction?

    /// 情報源IDで情報源を検索する。該当がなければ`nil`を返す。
    func evidenceSource(id: String) throws -> EvidenceSource?

    /// 正規名または別名に一致する食材を検索する。
    func ingredients(matchingName name: String) throws -> [Ingredient]

    /// 初期データImportなどで料理を保存する。同じIDの料理があれば置き換える。
    func upsertDish(_ dish: Dish) throws

    /// 初期データImportなどで食材を保存する。同じIDの食材があれば置き換える。
    func upsertIngredient(_ ingredient: Ingredient) throws

    /// 初期データImportなどでアレルゲンを保存する。同じIDのアレルゲンがあれば置き換える。
    func upsertAllergen(_ allergen: Allergen) throws

    /// 初期データImportなどで食事制限タグを保存する。同じIDのタグがあれば置き換える。
    func upsertRestriction(_ restriction: Restriction) throws

    /// 初期データImportなどで情報源を保存する。同じIDの情報源があれば置き換える。
    func upsertEvidenceSource(_ source: EvidenceSource) throws

    /// 料理と食材の関連を保存する。同じ料理ID・食材IDの関連があれば置き換える。
    func upsertDishIngredient(
        dishId: String,
        ingredientId: String,
        confidence: DishIngredientConfidence,
        isHiddenIngredient: Bool,
        hiddenIngredientCategory: HiddenIngredientCategory?,
        sourceIds: [String]
    ) throws

    /// 食材とアレルゲンの関連を保存する。同じ食材ID・アレルゲンIDの関連があれば置き換える。
    func upsertIngredientAllergen(ingredientId: String, allergenId: String, sourceIds: [String]) throws

    /// 食材と食事制限タグの関連を保存する。同じ食材ID・タグIDの関連があれば置き換える。
    func upsertIngredientRestriction(ingredientId: String, restrictionId: String, sourceIds: [String]) throws

    /// 指定した初期データバージョンがImport済みであれば`true`を返す。
    func hasImportedDataVersion(_ id: String) throws -> Bool

    /// 指定した初期データバージョンをImport済みとして記録する。
    func markDataVersionImported(_ id: String) throws
}
