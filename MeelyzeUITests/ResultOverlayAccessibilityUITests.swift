import XCTest

/// S07/S08/S09のアクセシビリティ検証（TASK-053）。`docs/ui-design.md`が要求する、OSのDynamic Type
/// 最大設定でのレイアウト維持と、Appleの自動アクセシビリティ監査（コントラスト・要素ラベル等）を
/// 検証する。
///
/// **既知の制約**: VoiceOverの実際の走査順（`ResultOverlayView`が`.accessibilitySortPriority`で
/// 意図する含有の可能性が高い→判定不可→収録データ上は該当なしの順）は、標準のXCTest APIでは
/// 直接検証できない。`app.descendants(...).allElementsBoundByIndex`が返す順序で代用しようと試みたが、
/// これはaccessibility traversal順ではなくView階層順（本ケースでは`ForEach(summary.items, ...)`の
/// 配列順）を反映することが実験で判明したため、このテストは削除した（`.accessibilitySortPriority`
/// 自体が誤っているのか、検証方法が誤っているのかを区別できない誤ったテストを残さないため）。
/// VoiceOver走査順の最終確認は、実機でVoiceOverを有効にした手動確認が必要
/// （`docs/device-verification.md`の実機確認手順の一部として、別途実施する）。
final class ResultOverlayAccessibilityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Appleの自動アクセシビリティ監査（コントラスト不足・ラベル欠落・タップ領域不足等）をS08で実行する。
    @MainActor
    func testResultOverlayPassesAccessibilityAudit() throws {
        let app = launchAndCapture(analysisStubMode: "mixed")
        let retakeButton = app.buttons["ResultOverlayRetakeButton"]
        XCTAssertTrue(retakeButton.waitForExistence(timeout: 10))
        // TASK-053で判明: レイアウトが完全に安定する前に監査するとフルスイート実行時の負荷下で
        // 不安定になることがあるため、ヒットテスト座標が確定してから監査する。
        XCTAssertTrue(retakeButton.waitForHittable(timeout: 5), "Screen did not settle before running the accessibility audit")

        try app.performAccessibilityAudit()
    }

    /// OSのDynamic Type最大設定（Accessibility XXXL）でも、S08の主要要素（常時注意文・再撮影導線）が
    /// 引き続き存在し操作できることを確認する（`docs/requirements.md` NFR-4.3）。
    @MainActor
    func testResultOverlayRemainsUsableAtMaximumDynamicTypeSize() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_STORE_IDENTIFIER"] = UUID().uuidString
        app.launchEnvironment["UITEST_OCR_STUB_MODE"] = "success"
        app.launchEnvironment["UITEST_ANALYSIS_STUB_MODE"] = "mixed"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        completeOnboarding(in: app)

        XCTAssertTrue(app.buttons["ShutterButton"].waitForExistence(timeout: 5))
        app.buttons["ShutterButton"].tap()

        let retakeButton = app.buttons["ResultOverlayRetakeButton"]
        XCTAssertTrue(retakeButton.waitForExistence(timeout: 10))
        // 極端なDynamic Typeサイズでは巨大化した常時注意文（ScrollView外のoverlay）のレイアウトが
        // 数フレームかけて安定するため、`waitForExistence`直後は`isHittable`が一時的にfalseを
        // 返すことがある（要素自体は存在するがヒットテスト用のwindow座標がまだ確定していない）。
        // レイアウト安定を待つ（`UITestHelpers.swift`の共用ヘルパー）。
        XCTAssertTrue(retakeButton.waitForHittable(timeout: 5), "Retake button did not become hittable after layout settled")
        XCTAssertTrue(app.staticTexts["PersistentResultSafetyNoticeView"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["RiskBadgeView_likelyContains"].exists)
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
