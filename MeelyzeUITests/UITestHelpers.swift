import XCTest

/// S01→S02→S04/S05→保存までの初期設定フローを一気通貫で完了させる共通ヘルパー（英語話者・
/// アレルゲン0件選択）。`OnboardingFlowUITests` `ScanOCRFailureUITests`で共用する。
@MainActor
func completeOnboarding(in app: XCUIApplication) {
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
