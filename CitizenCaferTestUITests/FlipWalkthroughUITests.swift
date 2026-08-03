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

    /// The same leftward drag does two different things either side of the reveal: first it flips
    /// the card, and only then does it advance the deck.
    func testSwipeFlipsBeforeTheRevealAndAdvancesAfterIt() {
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

        // A locked card refuses to leave, however far you drag it — it flips instead.
        swipeCardLeft(in: app)
        Thread.sleep(forTimeInterval: 1.0)
        attach(named: "1-swipe-flipped-not-advanced")
        XCTAssertTrue(app.staticTexts["Card 1 / 10"].exists, "A swipe before the reveal must not advance.")

        // The identical gesture on the revealed card now throws it away.
        swipeCardLeft(in: app)
        XCTAssertTrue(
            app.staticTexts["Card 2 / 10"].waitForExistence(timeout: 3),
            "A swipe after the reveal advances the deck."
        )
        attach(named: "2-swipe-advanced")
    }

    /// Drags across the middle of the card, well past the 88pt throw threshold on any phone.
    private func swipeCardLeft(in app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.42))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    private func attach(named name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
