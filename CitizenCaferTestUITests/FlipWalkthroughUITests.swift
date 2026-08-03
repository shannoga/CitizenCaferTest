import XCTest

/// Drives the real app to capture the card before and after the flip. Kept as a walkthrough rather
/// than a strict assertion suite — the logic is covered by the unit tests; this exists to prove the
/// screens compose and the flip reveals the English face.
final class FlipWalkthroughUITests: XCTestCase {

    func testStudyAPackAndFlipTheCard() {
        let app = XCUIApplication()
        app.launch()

        let level = app.buttons["picker.Level"]
        XCTAssertTrue(level.waitForExistence(timeout: 20), "Vocabulary should finish loading.")
        level.tap()

        app.buttons["Red"].tap()

        let start = app.buttons["Start studying"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.staticTexts["Card 1 / 10"].waitForExistence(timeout: 5), "Progress should read 1 / 10.")
        attach(named: "1-hebrew-face")

        // Tap the middle of the card rather than a text element, so the hit lands on the face.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        attach(named: "2-mid-flip")

        Thread.sleep(forTimeInterval: 1.0)
        attach(named: "3-english-face")
    }

    private func attach(named name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
