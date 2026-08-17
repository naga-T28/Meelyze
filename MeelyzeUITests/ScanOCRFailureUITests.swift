import XCTest

/// OCR失敗時（0件抽出）のE01フォールバックUIと、「再撮影」でS06へ戻る挙動を検証する。また、
/// OCRが1件以上取得できた場合（低Confidenceを含む）にE01を表示しないことも検証する。
///
/// Simulatorには実カメラがなく実Visionの結果も制御できないため、`CameraService` `OCRService`は
/// `UITEST_OCR_STUB_MODE`環境変数でスタブに差し替える
/// （`Meelyze/Services/UITestScanStubs.swift`、`Meelyze/Views/RootView.swift`参照）。
final class ScanOCRFailureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testZeroObservationsShowsE01AndRetakeReturnsToScan() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launchEnvironment["UITEST_OCR_STUB_MODE"] = "empty"
        app.launch()

        completeOnboarding(in: app)

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        app.buttons["ShutterButton"].tap()

        XCTAssertTrue(app.staticTexts["Couldn't read the menu text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Adjust the brightness, angle, and distance, then take the photo again."].exists)
        XCTAssertTrue(app.staticTexts["Find a bright place"].exists)
        XCTAssertTrue(app.staticTexts["Shoot from a front-facing angle"].exists)
        XCTAssertTrue(app.staticTexts["Get closer to the dish names"].exists)
        XCTAssertTrue(app.buttons["OCRFailureRetakeButton"].exists)

        app.buttons["OCRFailureRetakeButton"].tap()

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Couldn't read the menu text"].exists)
    }

    @MainActor
    func testOneOrMoreObservationsDoesNotShowE01() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launchEnvironment["UITEST_OCR_STUB_MODE"] = "success"
        app.launch()

        completeOnboarding(in: app)

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        app.buttons["ShutterButton"].tap()

        // OCRが1件以上取得できた場合（低Confidenceを含む）は全体失敗にせず、E01を表示しない。
        XCTAssertFalse(app.staticTexts["Couldn't read the menu text"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
    }
}
