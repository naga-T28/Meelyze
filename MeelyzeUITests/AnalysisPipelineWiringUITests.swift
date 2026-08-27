import XCTest

/// OCR成功後、`ScanView`が実際に`MenuAnalysisViewModel`を呼び出し、同一スキャン内の状態置換で
/// S06（撮影）からS07/S08相当の表示へ切り替わること（TASK-043）を検証する。
///
/// TASK-048以降、`.completed`状態は実際の`ResultOverlayView`（S08、識別子
/// `ResultOverlayRetakeButton`）を表示するようになった。`.noRecognizableText`・`.failed`は
/// TASK-049がS07の実画面へ置き換えるまで`AnalysisResultPlaceholderView`の暫定表示
/// （識別子`AnalysisPlaceholderRetakeButton`）のままである。Simulator環境ではFoundation Models・
/// DB照合の実際の結果次第でどちらの状態に到達するか確定できないため、本テストはいずれかの
/// 「再撮影」導線が表示されることをもって「解析が呼び出され、非processing状態へ到達した」ことを
/// 判定する。UI Testスタブによる`MenuAnalysisService`自体の決定論的な差し替え（三値混在・E02/E03の
/// 再現）はTASK-052の範囲とする。
final class AnalysisPipelineWiringUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSuccessfulOCRTriggersAnalysisAndReachesNonProcessingState() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launchEnvironment["UITEST_OCR_STUB_MODE"] = "success"
        app.launch()

        completeOnboarding(in: app)

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        app.buttons["ShutterButton"].tap()

        // OCR成功直後はprocessing（暫定表示はidentifierを持たないProgressViewのみ）を経て、
        // completed（S08 ResultOverlayView）・failed（暫定表示）のいずれかへ遷移し、
        // その状態の「再撮影」導線が表示される。
        XCTAssertTrue(
            waitForEitherRetakeAffordance(in: app, timeout: 20),
            "Expected analysis to reach a non-processing (completed/failed) state within timeout"
        )

        // 同一スキャン内の状態置換により、S06のシャッターへは戻っていない（別画面がスタックしていない）。
        XCTAssertFalse(app.buttons["ShutterButton"].exists)
    }

    @MainActor
    func testRetakeFromAnalysisResultReturnsToIdleScanState() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launchEnvironment["UITEST_OCR_STUB_MODE"] = "success"
        app.launch()

        completeOnboarding(in: app)

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        app.buttons["ShutterButton"].tap()

        XCTAssertTrue(waitForEitherRetakeAffordance(in: app, timeout: 20))
        if app.buttons["ResultOverlayRetakeButton"].exists {
            app.buttons["ResultOverlayRetakeButton"].tap()
        } else {
            app.buttons["AnalysisPlaceholderRetakeButton"].tap()
        }

        // 再撮影操作でS06（idle、シャッターボタン表示）へ戻る。
        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
    }

    /// S08のオーバーレイ結果カード（TASK-048）をタップするとS09（`DishDetailView`, TASK-051）へ
    /// 遷移することを確認する。`ResultOverlayRetakeButton`が表示された（=`.completed`へ到達した）
    /// 場合のみ検証し、`.failed`など暫定表示のままの場合はこの検証をスキップする
    /// （Simulator上でどちらへ到達するかは環境依存のため）。
    @MainActor
    func testTappingResultCardNavigatesToDishDetail() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launchEnvironment["UITEST_OCR_STUB_MODE"] = "success"
        app.launch()

        completeOnboarding(in: app)

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        app.buttons["ShutterButton"].tap()

        XCTAssertTrue(waitForEitherRetakeAffordance(in: app, timeout: 20))
        try XCTSkipUnless(app.buttons["ResultOverlayRetakeButton"].exists, "Did not reach .completed state in this environment")

        // `RiskResultCardView`は`.accessibilityElement(children: .combine)`でButtonを結合しており、
        // 結果としてXCUIElementの種別が`.buttons`以外（`.other`等）になる場合があるため、種別を
        // 限定せず探す。Simulator環境ではFoundation Modelsの実際の生成結果次第で`summary.items`が
        // 0件になり得る（E02バナー等で示されるだけでカード自体が1件も存在しない）ため、その場合は
        // このテストの検証対象外としてスキップする。決定論的な保証はTASK-052のUI Testスタブ拡張後に
        // 追加する。
        let resultCard = app.descendants(matching: .any).matching(identifier: "RiskResultCardView_compact").firstMatch
        try XCTSkipUnless(resultCard.waitForExistence(timeout: 5), "No dish item was produced in this environment (summary.items was empty)")
        // TASK-053で判明: 要素は存在してもヒットテスト座標が確定するまで数フレームかかることがある。
        XCTAssertTrue(resultCard.waitForHittable(timeout: 5), "Result card did not become hittable after layout settled")
        resultCard.tap()

        // `DishDetailView`はScrollViewのルートに識別子を付与しているため、要素種別を限定せず探す。
        XCTAssertTrue(app.descendants(matching: .any)["DishDetailView"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForEitherRetakeAffordance(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.buttons["ResultOverlayRetakeButton"].exists || app.buttons["AnalysisPlaceholderRetakeButton"].exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return app.buttons["ResultOverlayRetakeButton"].exists || app.buttons["AnalysisPlaceholderRetakeButton"].exists
    }
}
