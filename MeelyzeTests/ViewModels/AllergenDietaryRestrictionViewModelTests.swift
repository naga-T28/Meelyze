import Foundation
import Testing
@testable import Meelyze

private final class FakeProfileRepository: ProfileRepository {
    private(set) var savedProfiles: [UserProfile] = []

    func currentProfile() throws -> UserProfile? { savedProfiles.last }

    func save(_ profile: UserProfile) throws {
        savedProfiles.append(profile)
    }
}

struct AllergenDietaryRestrictionViewModelTests {

    private func makeViewModel(
        displayLanguage: DisplayLanguage = .english,
        repository: FakeProfileRepository = FakeProfileRepository()
    ) -> AllergenDietaryRestrictionViewModel {
        AllergenDietaryRestrictionViewModel(
            hasAgreedToDisclaimer: true,
            disclaimerAgreedAt: Date(),
            displayLanguage: displayLanguage,
            profileRepository: repository
        )
    }

    @Test func togglingAnAllergenItemSelectsAndDeselectsIt() {
        let viewModel = makeViewModel()

        viewModel.toggle(AllergenItem.egg)
        #expect(viewModel.isSelected(AllergenItem.egg) == true)

        viewModel.toggle(AllergenItem.egg)
        #expect(viewModel.isSelected(AllergenItem.egg) == false)
    }

    @Test func togglingADietaryRestrictionCategorySelectsAndDeselectsIt() {
        let viewModel = makeViewModel()

        viewModel.toggle(DietaryRestrictionCategory.vegan)
        #expect(viewModel.isSelected(DietaryRestrictionCategory.vegan) == true)

        viewModel.toggle(DietaryRestrictionCategory.vegan)
        #expect(viewModel.isSelected(DietaryRestrictionCategory.vegan) == false)
    }

    @Test func multipleAllergenItemsCanBeSelectedAtOnce() {
        let viewModel = makeViewModel()

        viewModel.toggle(AllergenItem.egg)
        viewModel.toggle(AllergenItem.shrimp)
        viewModel.toggle(AllergenItem.walnut)

        #expect(viewModel.selectedAllergenItems == [.egg, .shrimp, .walnut])
    }

    @Test func savingWithZeroSelectionsIsAllowed() throws {
        let repository = FakeProfileRepository()
        let viewModel = makeViewModel(repository: repository)

        let profile = try viewModel.saveProfile()

        #expect(profile.allergenItems.isEmpty)
        #expect(profile.dietaryRestrictionCategories.isEmpty)
        #expect(repository.savedProfiles.count == 1)
    }

    @Test func savingReflectsSelectedSetsAndPriorScreenStateIntoUserProfile() throws {
        let repository = FakeProfileRepository()
        let viewModel = makeViewModel(repository: repository)
        viewModel.toggle(AllergenItem.egg)
        viewModel.toggle(AllergenItem.milk)
        viewModel.toggle(DietaryRestrictionCategory.halal)

        let profile = try viewModel.saveProfile()

        #expect(Set(profile.allergenItems) == [.egg, .milk])
        #expect(Set(profile.dietaryRestrictionCategories) == [.halal])
        #expect(profile.hasAgreedToDisclaimer == true)
        #expect(profile.displayLanguage == .english)
        #expect(profile.isInitialSetupCompleted == true)
        #expect(repository.savedProfiles.last === profile)
    }

    @Test func chromeTextFollowsTheSelectedDisplayLanguage() {
        let englishViewModel = makeViewModel(displayLanguage: .english)
        let koreanViewModel = makeViewModel(displayLanguage: .korean)

        #expect(englishViewModel.navigationTitle == "Allergens & Dietary Restrictions")
        #expect(koreanViewModel.navigationTitle == "알레르기 유발물질 및 식이 제한")
        #expect(englishViewModel.navigationTitle != koreanViewModel.navigationTitle)
    }

    @Test func sectionTitlesEmbedTheActualItemCounts() {
        let viewModel = makeViewModel(displayLanguage: .english)

        #expect(viewModel.mandatorySectionTitle == "Allergens (Mandatory Labeling, \(viewModel.mandatoryAllergenItems.count) items)")
        #expect(viewModel.recommendedSectionTitle == "Allergens (Recommended Labeling, \(viewModel.recommendedAllergenItems.count) items)")
    }
}
