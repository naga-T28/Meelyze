import XCTest

/// 初期設定フロー（S01→S02→S04/S05→保存→プレースホルダ画面）と、Root Gateの初回起動・再起動時の
/// 挙動をE2Eで検証する。
///
/// 各テストは`UITEST_STORE_IDENTIFIER`環境変数で一意なSwiftDataストアを指定し、テスト間の状態汚染を
/// 避ける（`Meelyze/MeelyzeApp.swift`参照）。再起動後のスキップ挙動は、同一識別子のまま
/// `terminate()`/`launch()`をまたぐことで実際の永続化を検証する。
final class OnboardingFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstLaunchStartsFromDisclaimerAndReachesScanPlaceholder() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.staticTexts["Disclaimer"].waitForExistence(timeout: 5))

        completeOnboarding(in: app)

        XCTAssertTrue(app.staticTexts["Menu scanning is coming soon"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompletedSetupSkipsOnboardingAfterRestart() throws {
        let app = XCUIApplication()
        let storeIdentifier = UUID().uuidString
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = storeIdentifier
        app.launch()

        completeOnboarding(in: app)
        XCTAssertTrue(app.staticTexts["Menu scanning is coming soon"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = storeIdentifier
        app.launch()

        XCTAssertTrue(app.staticTexts["Menu scanning is coming soon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Disclaimer"].exists)
    }

    @MainActor
    private func completeOnboarding(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Disclaimer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["DisclaimerAgreeToggle"].waitForExistence(timeout: 5))
        app.buttons["DisclaimerAgreeToggle"].tap()
        app.buttons["DisclaimerContinueButton"].tap()

        XCTAssertTrue(app.buttons["LanguageRow_english"].waitForExistence(timeout: 5))
        app.buttons["LanguageRow_english"].tap()
        app.buttons["LanguageSelectionContinueButton"].tap()

        XCTAssertTrue(app.buttons["AllergenDietaryRestrictionSaveButton"].waitForExistence(timeout: 5))
        app.buttons["AllergenDietaryRestrictionSaveButton"].tap()
    }
}
