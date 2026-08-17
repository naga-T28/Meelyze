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
    func testFirstLaunchStartsFromDisclaimerAndReachesScan() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        addCameraPermissionAlertMonitor(for: app)
        app.launch()

        XCTAssertTrue(app.staticTexts["Disclaimer"].waitForExistence(timeout: 5))

        completeOnboarding(in: app)

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompletedSetupSkipsOnboardingAfterRestart() throws {
        let app = XCUIApplication()
        let storeIdentifier = UUID().uuidString
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = storeIdentifier
        addCameraPermissionAlertMonitor(for: app)
        app.launch()

        completeOnboarding(in: app)
        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = storeIdentifier
        app.launch()

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Disclaimer"].exists)
    }

    /// S06（`ScanView`）到達時、`ScanViewModel.onAppear()`がカメラ権限を要求しSystem alertが
    /// 表示されうる。テストが停止しないよう自動的に許可する（Simulatorには実カメラがないため、
    /// 許可後も映像そのものは取得できないが、権限ダイアログ自体は実機と同じ経路を通る）。
    @MainActor
    private func addCameraPermissionAlertMonitor(for app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "Camera Permission") { alert in
            let allowButton = alert.buttons["Allow"].exists ? alert.buttons["Allow"] : alert.buttons["OK"]
            guard allowButton.exists else { return false }
            allowButton.tap()
            return true
        }
    }
}
