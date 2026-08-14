import Testing
@testable import Meelyze

struct ContentViewModelTests {

    @Test func titleIsMeelyze() {
        let viewModel = ContentViewModel()
        #expect(viewModel.title == "Meelyze")
    }

}
