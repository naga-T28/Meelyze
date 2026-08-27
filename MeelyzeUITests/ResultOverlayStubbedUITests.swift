import XCTest

/// `UITEST_ANALYSIS_STUB_MODE`（TASK-052、`Meelyze/Services/UITestAnalysisStubs.swift`）で
/// `MenuAnalysisService`を決定論的なスタブへ差し替え、S08/S09の三値混在・E02・E03・処理長時間化を
/// 安定して検証する。Simulator上の実Foundation Models/DB照合結果は非決定的なため
/// （TASK-051の作業ログ参照）、本テストはそれに依存しない。
final class ResultOverlayStubbedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMixedThreeValueResultsShowAllThreeBadgeStates() throws {
        let app = launchAndCapture(analysisStubMode: "mixed")

        XCTAssertTrue(app.buttons["ResultOverlayRetakeButton"].waitForExistence(timeout: 10))
        // FIX-015: S08のタグはアイコンのみ（`RiskBadgeView(showsLabel: false)`）を表示し、独自の
        // `RiskBadgeView_*`アクセシビリティ識別子を持たない（完全な状態ラベルは`RiskResultCardView`
        // 自体の`accessibilityLabel`に含まれる）。3件のタグそれぞれの`label`に三値の完全ラベルが
        // 1件ずつ含まれることで、三値が混在して表示されていることを検証する。
        let tags = app.descendants(matching: .any).matching(identifier: "RiskResultCardView_compact")
        XCTAssertTrue(tags.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(tags.count, 3)
        let labels = (0..<tags.count).map { tags.element(boundBy: $0).label }
        XCTAssertTrue(labels.contains { $0.contains("Likely Contains") })
        XCTAssertTrue(labels.contains { $0.contains("No Match in Records") })
        XCTAssertTrue(labels.contains { $0.contains("Undetermined") })

        // 三値にかかわらず常時注意文が表示される。
        XCTAssertTrue(app.staticTexts["PersistentResultSafetyNoticeView"].exists)
        // E02バナーは三値混在シナリオ（failuresなし）では表示されない。
        XCTAssertFalse(app.descendants(matching: .any)["ErrorStateCardView_E02InlineBanner"].exists)
    }

    @MainActor
    func testE02ShowsInlineBannerWhenMenuUnderstandingUnavailable() throws {
        let app = launchAndCapture(analysisStubMode: "e02")

        XCTAssertTrue(app.buttons["ResultOverlayRetakeButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["ErrorStateCardView_E02InlineBanner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Some menu items could not be analyzed"].exists)
    }

    @MainActor
    func testE03ShowsUndeterminedCardWithReason() throws {
        let app = launchAndCapture(analysisStubMode: "e03")

        XCTAssertTrue(app.buttons["ResultOverlayRetakeButton"].waitForExistence(timeout: 10))
        // FIX-015: S08のタグは独自の`RiskBadgeView_*`識別子を持たない（上記コメント参照）。
        let tag = app.descendants(matching: .any).matching(identifier: "RiskResultCardView_compact").firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        XCTAssertTrue(tag.label.contains("Undetermined"))
        // E03は専用バナーを出さない（`docs/ui-design.md`）。
        XCTAssertFalse(app.descendants(matching: .any)["ErrorStateCardView_E02InlineBanner"].exists)
    }

    @MainActor
    func testSlowAnalysisShowsProgressViewBeforeCompleting() throws {
        let app = launchAndCapture(analysisStubMode: "slow")

        // `StubMenuAnalysisService.Mode.slow`は3秒待ってから完了するため、直後はprocessing表示が
        // 見えているはず。
        XCTAssertTrue(app.descendants(matching: .any)["AnalysisProgressView"].waitForExistence(timeout: 2))
        // 完了後はS08（ResultOverlayView）へ切り替わる。
        XCTAssertTrue(app.buttons["ResultOverlayRetakeButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["AnalysisProgressView"].exists)
    }

    @MainActor
    func testTappingResultCardNavigatesToDishDetailDeterministically() throws {
        let app = launchAndCapture(analysisStubMode: "mixed")

        XCTAssertTrue(app.buttons["ResultOverlayRetakeButton"].waitForExistence(timeout: 10))
        let resultCard = app.descendants(matching: .any).matching(identifier: "RiskResultCardView_compact").firstMatch
        XCTAssertTrue(resultCard.waitForExistence(timeout: 5))
        // TASK-053で判明: 要素は存在してもヒットテスト座標が確定するまで数フレームかかることがあり、
        // フルスイート実行時の負荷下では`waitForExistence`直後のタップが不安定になる。
        XCTAssertTrue(resultCard.waitForHittable(timeout: 5), "Result card did not become hittable after layout settled")
        resultCard.tap()

        XCTAssertTrue(app.descendants(matching: .any)["DishDetailView"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchAndCapture(analysisStubMode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launchEnvironment["UITEST_OCR_STUB_MODE"] = "success"
        app.launchEnvironment["UITEST_ANALYSIS_STUB_MODE"] = analysisStubMode
        app.launch()

        completeOnboarding(in: app)

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        app.buttons["ShutterButton"].tap()
        return app
    }
}
