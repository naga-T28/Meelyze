import XCTest

final class MeelyzeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppTitleIsDisplayed() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Meelyze"].waitForExistence(timeout: 5))
    }

}
