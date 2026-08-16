import Testing
@testable import Meelyze

struct DisclaimerViewModelTests {

    @Test func cannotProceedWithoutAgreement() {
        let viewModel = DisclaimerViewModel()

        #expect(viewModel.canProceed == false)
        #expect(viewModel.agreedAt == nil)
    }

    @Test func canProceedAfterAgreeing() {
        let viewModel = DisclaimerViewModel()

        viewModel.hasAgreed = true

        #expect(viewModel.canProceed == true)
        #expect(viewModel.agreedAt != nil)
    }

    @Test func revokingAgreementClearsTimestampAndBlocksProceeding() {
        let viewModel = DisclaimerViewModel()
        viewModel.hasAgreed = true

        viewModel.hasAgreed = false

        #expect(viewModel.canProceed == false)
        #expect(viewModel.agreedAt == nil)
    }
}
