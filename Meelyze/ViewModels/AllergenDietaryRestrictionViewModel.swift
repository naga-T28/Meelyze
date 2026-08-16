import Foundation

/// S04/S05 アレルゲン・食事制限選択画面（`AllergenDietaryRestrictionView`）の選択状態を保持する。
///
/// 特定原材料・特定原材料に準ずるもの（`AllergenItem`参照）、およびMVP対象の食事制限区分を複数選択できる。
/// 0件選択（アレルギーなし）も有効な状態として許可する。TASK-014・TASK-015で確定した同意状態・
/// 表示言語と本画面の選択結果をあわせて`UserProfile`として組み立て、`ProfileRepository`経由で保存する。
@Observable
final class AllergenDietaryRestrictionViewModel {
    let mandatoryAllergenItems = AllergenItem.mandatoryItems
    let recommendedAllergenItems = AllergenItem.recommendedItems
    let dietaryRestrictionCategories = DietaryRestrictionCategory.allCases

    private(set) var selectedAllergenItems: Set<AllergenItem> = []
    private(set) var selectedDietaryRestrictionCategories: Set<DietaryRestrictionCategory> = []
    private(set) var savedProfile: UserProfile?

    private let hasAgreedToDisclaimer: Bool
    private let disclaimerAgreedAt: Date?
    private let displayLanguage: DisplayLanguage
    private let profileRepository: ProfileRepository

    init(
        hasAgreedToDisclaimer: Bool,
        disclaimerAgreedAt: Date?,
        displayLanguage: DisplayLanguage,
        profileRepository: ProfileRepository
    ) {
        self.hasAgreedToDisclaimer = hasAgreedToDisclaimer
        self.disclaimerAgreedAt = disclaimerAgreedAt
        self.displayLanguage = displayLanguage
        self.profileRepository = profileRepository
    }

    func displayName(for item: AllergenItem) -> String {
        item.localizedName(for: displayLanguage)
    }

    func displayName(for category: DietaryRestrictionCategory) -> String {
        category.localizedName(for: displayLanguage)
    }

    func isSelected(_ item: AllergenItem) -> Bool {
        selectedAllergenItems.contains(item)
    }

    func isSelected(_ category: DietaryRestrictionCategory) -> Bool {
        selectedDietaryRestrictionCategories.contains(category)
    }

    func toggle(_ item: AllergenItem) {
        if selectedAllergenItems.contains(item) {
            selectedAllergenItems.remove(item)
        } else {
            selectedAllergenItems.insert(item)
        }
    }

    func toggle(_ category: DietaryRestrictionCategory) {
        if selectedDietaryRestrictionCategories.contains(category) {
            selectedDietaryRestrictionCategories.remove(category)
        } else {
            selectedDietaryRestrictionCategories.insert(category)
        }
    }

    /// 選択結果を`UserProfile`として組み立て、`ProfileRepository`へ保存する。0件選択でも呼び出せる。
    @discardableResult
    func saveProfile() throws -> UserProfile {
        let profile = UserProfile(
            hasAgreedToDisclaimer: hasAgreedToDisclaimer,
            disclaimerAgreedAt: disclaimerAgreedAt,
            displayLanguage: displayLanguage,
            allergenItems: Array(selectedAllergenItems),
            dietaryRestrictionCategories: Array(selectedDietaryRestrictionCategories),
            isInitialSetupCompleted: true
        )
        try profileRepository.save(profile)
        savedProfile = profile
        return profile
    }
}
