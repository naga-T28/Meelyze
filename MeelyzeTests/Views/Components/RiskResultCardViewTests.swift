import Testing
@testable import Meelyze

/// `RiskResultCardView`が使う`RiskTarget.localizedName(for:)`の委譲ロジックを検証する。
/// SwiftUI Viewのレイアウト・アクセシビリティ結線自体はPreview・実機/Simulator確認
/// （TASK-053、S08/S09へ組み込まれた後）で検証する。
struct RiskResultCardViewTests {
    @Test func allergenTargetDelegatesToAllergenItemLocalizedName() {
        let target = RiskTarget.allergen(.pork)
        #expect(target.localizedName(for: .english) == AllergenItem.pork.localizedName(for: .english))
    }

    @Test func dietaryRestrictionTargetDelegatesToDietaryRestrictionCategoryLocalizedName() {
        let target = RiskTarget.dietaryRestriction(.halal)
        #expect(target.localizedName(for: .english) == DietaryRestrictionCategory.halal.localizedName(for: .english))
    }

    @Test func localizedNameIsProvidedForAllMVPLanguages() {
        let languages: [DisplayLanguage] = [.english, .traditionalChinese, .simplifiedChinese, .korean]
        for language in languages {
            #expect(!RiskTarget.allergen(.pork).localizedName(for: language).isEmpty)
            #expect(!RiskTarget.dietaryRestriction(.halal).localizedName(for: language).isEmpty)
        }
    }
}
