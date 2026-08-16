import XCTest

final class MeelyzeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // TASK-017でMeelyzeApp.swiftのrootがContentViewからRootViewへ切り替わり、未設定状態の初回起動は
    // S01（免責事項）から始まるようになった。「Meelyze」の固定タイトル文言はもう表示されないため、
    // 本テストはRoot Gateの初回起動時挙動を検証する内容に更新している。
    @MainActor
    func testAppTitleIsDisplayed() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.staticTexts["免責事項"].waitForExistence(timeout: 5))
    }

}
