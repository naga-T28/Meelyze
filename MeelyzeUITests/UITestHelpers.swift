import XCTest

/// S01→S02→S04/S05→保存までの初期設定フローを一気通貫で完了させる共通ヘルパー（英語話者・
/// アレルゲン0件選択）。`OnboardingFlowUITests` `ScanOCRFailureUITests`で共用する。
@MainActor
func completeOnboarding(in app: XCUIApplication) {
    XCTAssertTrue(app.staticTexts["Disclaimer"].waitForExistence(timeout: 5))
    let agreeToggle = app.buttons["DisclaimerAgreeToggle"]
    let disclaimerContinueButton = app.buttons["DisclaimerContinueButton"]
    let languageRow = app.buttons["LanguageRow_english"]
    XCTAssertTrue(agreeToggle.waitForExistence(timeout: 5))
    for _ in 0..<3 where !languageRow.exists && !disclaimerContinueButton.isEnabled {
        agreeToggle.tap()
        _ = waitUntil(timeout: 1) {
            languageRow.exists || disclaimerContinueButton.isEnabled
        }
    }

    XCTAssertTrue(waitUntil(timeout: 5) {
        languageRow.exists || disclaimerContinueButton.exists
    })
    if !languageRow.exists {
        XCTAssertTrue(disclaimerContinueButton.waitForEnabled(timeout: 5))
        if disclaimerContinueButton.exists {
            disclaimerContinueButton.tap()
        }
    }

    XCTAssertTrue(languageRow.waitForExistence(timeout: 5))
    app.buttons["LanguageRow_english"].tap()

    let saveButton = app.buttons["AllergenDietaryRestrictionSaveButton"]
    let languageContinueButton = app.buttons["LanguageSelectionContinueButton"]
    XCTAssertTrue(waitUntil(timeout: 5) {
        saveButton.exists || languageContinueButton.exists
    })
    if !saveButton.exists {
        XCTAssertTrue(languageContinueButton.waitForEnabled(timeout: 5))
        if languageContinueButton.exists {
            languageContinueButton.tap()
        }
    }

    XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
    app.buttons["AllergenDietaryRestrictionSaveButton"].tap()
}

private extension XCUIElement {
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

/// 要素が存在してもヒットテスト座標が確定するまで数フレームかかる場合がある（TASK-053で発見。
/// 極端なDynamic Typeサイズ等、周辺レイアウトの再計算が絡む画面で顕著）。`waitForExistence`の
/// 直後に`isHittable`を1回だけ確認すると、フルスイート実行時の負荷下で不安定になることがあるため、
/// `ResultOverlayAccessibilityUITests` `ResultOverlayStubbedUITests`など複数のUI Testで共用する。
extension XCUIElement {
    @MainActor
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
}
