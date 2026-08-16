import Foundation
import SwiftData

/// 初回設定（免責同意・表示言語・アレルゲン・食事制限）を表す単一プロファイル。
///
/// MVPは複数プロファイルの切替に対応しない（FR-5.4、`docs/mvp-scope.md`）ため、常に1件のみが
/// 永続化される前提でよい。単一レコードの保証は`ProfileRepository`実装側の責務とする。
@Model
final class UserProfile {
    var hasAgreedToDisclaimer: Bool
    var disclaimerAgreedAt: Date?
    var displayLanguageRawValue: String
    var allergenItemRawValues: [String]
    var dietaryRestrictionCategoryRawValues: [String]
    var isInitialSetupCompleted: Bool

    init(
        hasAgreedToDisclaimer: Bool = false,
        disclaimerAgreedAt: Date? = nil,
        displayLanguage: DisplayLanguage = .english,
        allergenItems: [AllergenItem] = [],
        dietaryRestrictionCategories: [DietaryRestrictionCategory] = [],
        isInitialSetupCompleted: Bool = false
    ) {
        self.hasAgreedToDisclaimer = hasAgreedToDisclaimer
        self.disclaimerAgreedAt = disclaimerAgreedAt
        self.displayLanguageRawValue = displayLanguage.rawValue
        self.allergenItemRawValues = allergenItems.map(\.rawValue)
        self.dietaryRestrictionCategoryRawValues = dietaryRestrictionCategories.map(\.rawValue)
        self.isInitialSetupCompleted = isInitialSetupCompleted
    }

    var displayLanguage: DisplayLanguage {
        get { DisplayLanguage(rawValue: displayLanguageRawValue) ?? .english }
        set { displayLanguageRawValue = newValue.rawValue }
    }

    var allergenItems: [AllergenItem] {
        get { allergenItemRawValues.compactMap(AllergenItem.init(rawValue:)) }
        set { allergenItemRawValues = newValue.map(\.rawValue) }
    }

    var dietaryRestrictionCategories: [DietaryRestrictionCategory] {
        get { dietaryRestrictionCategoryRawValues.compactMap(DietaryRestrictionCategory.init(rawValue:)) }
        set { dietaryRestrictionCategoryRawValues = newValue.map(\.rawValue) }
    }
}
