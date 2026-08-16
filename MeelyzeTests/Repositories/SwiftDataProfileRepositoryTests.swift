import Foundation
import Testing
import SwiftData
@testable import Meelyze

struct SwiftDataProfileRepositoryTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([UserProfile.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func currentProfileIsNilWhenNothingSaved() throws {
        let repository = SwiftDataProfileRepository(modelContext: try makeInMemoryContext())

        #expect(try repository.currentProfile() == nil)
    }

    @Test func savedProfileCanBeFetchedBack() throws {
        let repository = SwiftDataProfileRepository(modelContext: try makeInMemoryContext())
        let agreedAt = Date()
        let profile = UserProfile(
            hasAgreedToDisclaimer: true,
            disclaimerAgreedAt: agreedAt,
            displayLanguage: .traditionalChinese,
            allergenItems: [.egg, .milk, .shrimp],
            dietaryRestrictionCategories: [.vegan, .nonAlcoholic],
            isInitialSetupCompleted: true
        )

        try repository.save(profile)
        let fetched = try #require(try repository.currentProfile())

        #expect(fetched.hasAgreedToDisclaimer == true)
        #expect(fetched.disclaimerAgreedAt == agreedAt)
        #expect(fetched.displayLanguage == .traditionalChinese)
        #expect(fetched.allergenItems == [.egg, .milk, .shrimp])
        #expect(fetched.dietaryRestrictionCategories == [.vegan, .nonAlcoholic])
        #expect(fetched.isInitialSetupCompleted == true)
    }

    @Test func savingReplacesPreviouslySavedProfile() throws {
        let context = try makeInMemoryContext()
        let repository = SwiftDataProfileRepository(modelContext: context)

        try repository.save(UserProfile(displayLanguage: .english, allergenItems: [.egg]))
        try repository.save(UserProfile(displayLanguage: .korean, allergenItems: [.peanut, .walnut]))

        let allProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(allProfiles.count == 1)
        #expect(allProfiles.first?.displayLanguage == .korean)
        #expect(allProfiles.first?.allergenItems == [.peanut, .walnut])
    }
}
