import Foundation
import SwiftData

/// 食事制限に関係する避けるべき属性を表すマスタ。
///
/// ハラールの豚・アルコール、ベジタリアンの動物性だし等、Rule Engineが参照するタグとして使う。
@Model
final class Restriction {
    @Attribute(.unique) var id: String
    var japaneseName: String
    var categoryRawValue: String

    init(id: String, japaneseName: String, category: DietaryRestrictionCategory) {
        self.id = id
        self.japaneseName = japaneseName
        self.categoryRawValue = category.rawValue
    }

    var category: DietaryRestrictionCategory {
        get { DietaryRestrictionCategory(rawValue: categoryRawValue) ?? .halal }
        set { categoryRawValue = newValue.rawValue }
    }
}
