import XCTest

/// Plays a whole pack to its last card and proves the completion screen arrives with its three
/// ways onward. The reducers are covered by `AppFeatureTests`; this exists to prove the screens
/// actually compose — and to capture the confetti, which nothing else can assert on.
final class CompletionWalkthroughUITests: XCTestCase {

    func testFinishingAPackShowsTheCompletionScreen() {
        let app = XCUIApplication()
        app.launch()

        let level = app.buttons["picker.Level"]
        XCTAssertTrue(level.waitForExistence(timeout: 20), "Vocabulary should finish loading.")
        level.tap()
        app.buttons["Red"].tap()

        let start = app.buttons["Start studying"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.staticTexts["Card 1 / 10"].waitForExistence(timeout: 5))

        // Reveal and advance ten times. The tenth press is "Finish" rather than "Next", which is
        // the whole point of the last-card branch.
        let card = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        for index in 1...10 {
            card.tap()

            let isLast = index == 10
            let advance = app.buttons[isLast ? "Finish the deck" : "Next card"]
            XCTAssertTrue(
                advance.waitForExistence(timeout: 5),
                "Card \(index) should offer \(isLast ? "Finish" : "Next")."
            )
            advance.tap()
        }

        // Captured before the assertion so a failure still shows what actually appeared. This is
        // also the mid-burst frame, while the shards are still falling.
        attach(named: "4-completion-burst")

        // Matched across every element type: the headline collapses its children into one element,
        // and which type that surfaces as is an implementation detail of SwiftUI's bridging.
        let headline = app.descendants(matching: .any)["completion.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5), "The completion screen should arrive.")

        // Red is a single-pack level, so "keep going" is the replay button and there is no
        // "Next pack".
        XCTAssertTrue(app.buttons["completion.studyAgain"].exists)
        XCTAssertFalse(app.buttons["completion.nextPack"].exists)
        XCTAssertTrue(app.buttons["completion.backToBrowse"].exists)

        // Settled: the burst is over well inside a cell's lifetime plus the 1.5s emission.
        Thread.sleep(forTimeInterval: 6.0)
        attach(named: "5-completion-settled")

        app.buttons["completion.studyAgain"].tap()
        XCTAssertTrue(
            app.staticTexts["Card 1 / 10"].waitForExistence(timeout: 5),
            "Replaying should hand the deck back at its first card."
        )
    }

    private func attach(named name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
