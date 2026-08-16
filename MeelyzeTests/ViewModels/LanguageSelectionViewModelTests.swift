import Testing
@testable import Meelyze

struct LanguageSelectionViewModelTests {

    @Test func cannotProceedWithoutSelection() {
        let viewModel = LanguageSelectionViewModel()

        #expect(viewModel.canProceed == false)
        #expect(viewModel.selectedLanguage == nil)
    }

    @Test func exposesAllFourMVPLanguages() {
        let viewModel = LanguageSelectionViewModel()

        #expect(viewModel.availableLanguages.count == 4)
        #expect(Set(viewModel.availableLanguages) == Set(DisplayLanguage.allCases))
    }

    @Test func selectingALanguageAllowsProceeding() {
        let viewModel = LanguageSelectionViewModel()

        viewModel.select(.korean)

        #expect(viewModel.canProceed == true)
        #expect(viewModel.selectedLanguage == .korean)
        #expect(viewModel.isSelected(.korean) == true)
        #expect(viewModel.isSelected(.english) == false)
    }

    @Test func selectingAnotherLanguageReplacesThePreviousSelection() {
        let viewModel = LanguageSelectionViewModel()
        viewModel.select(.english)

        viewModel.select(.simplifiedChinese)

        #expect(viewModel.selectedLanguage == .simplifiedChinese)
        #expect(viewModel.isSelected(.english) == false)
    }
}
