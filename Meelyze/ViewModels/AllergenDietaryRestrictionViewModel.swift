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

    /// 画面chrome（見出し・CTA）の文言。S02で確定した表示言語で表示する。
    var navigationTitle: String {
        AllergenDietaryRestrictionText.navigationTitle.value(for: displayLanguage)
    }

    var mandatorySectionTitle: String {
        AllergenDietaryRestrictionText.mandatorySectionTitle(count: mandatoryAllergenItems.count).value(for: displayLanguage)
    }

    var recommendedSectionTitle: String {
        AllergenDietaryRestrictionText.recommendedSectionTitle(count: recommendedAllergenItems.count).value(for: displayLanguage)
    }

    var dietaryRestrictionSectionTitle: String {
        AllergenDietaryRestrictionText.dietaryRestrictionSectionTitle.value(for: displayLanguage)
    }

    var saveButtonTitle: String {
        AllergenDietaryRestrictionText.saveButton.value(for: displayLanguage)
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

/// `AllergenDietaryRestrictionView`の画面chrome文言。MVP対象4言語で固定の意味を維持する。
private enum AllergenDietaryRestrictionText {
    static let navigationTitle = LocalizedText(
        english: "Allergens & Dietary Restrictions",
        traditionalChinese: "過敏原與飲食限制",
        simplifiedChinese: "过敏原与饮食限制",
        korean: "알레르기 유발물질 및 식이 제한"
    )

    static let dietaryRestrictionSectionTitle = LocalizedText(
        english: "Dietary Restrictions",
        traditionalChinese: "飲食限制",
        simplifiedChinese: "饮食限制",
        korean: "식이 제한"
    )

    static let saveButton = LocalizedText(
        english: "Save Profile",
        traditionalChinese: "儲存個人檔案",
        simplifiedChinese: "保存个人资料",
        korean: "프로필 저장"
    )

    static func mandatorySectionTitle(count: Int) -> LocalizedText {
        LocalizedText(
            english: "Allergens (Mandatory Labeling, \(count) items)",
            traditionalChinese: "過敏原（強制標示，共\(count)項）",
            simplifiedChinese: "过敏原（强制标示，共\(count)项）",
            korean: "알레르기 유발물질 (표시 의무, \(count)개 품목)"
        )
    }

    static func recommendedSectionTitle(count: Int) -> LocalizedText {
        LocalizedText(
            english: "Allergens (Recommended Labeling, \(count) items)",
            traditionalChinese: "過敏原（建議標示，共\(count)項）",
            simplifiedChinese: "过敏原（建议标示，共\(count)项）",
            korean: "알레르기 유발물질 (표시 권장, \(count)개 품목)"
        )
    }
}
