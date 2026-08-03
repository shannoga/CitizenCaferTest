import UIKit
import XCTest

/// The navigation title is drawn by UIKit, so nothing in the accessibility tree changes when it
/// stops being *painted* — the label keeps its text and its frame either way. This test therefore
/// measures the pixels inside the title's frame.
final class NavigationTitleUITests: XCTestCase {

    /// An opaque `scrollEdgeAppearance` used to end up drawn over the large title once the bar had
    /// been through a scroll transition, leaving the bar blank. Even a bounce on content that is
    /// too short to scroll was enough to trigger it.
    func testTitleStaysVisibleAfterScrolling() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Choose what to study"].waitForExistence(timeout: 20))

        let title = app.navigationBars.staticTexts["Citizen Café"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let frame = title.frame

        XCTAssertGreaterThan(
            inkCoverage(in: frame), 0.05,
            "The title should be drawn before any scrolling — the rest of this test is meaningless otherwise."
        )

        app.scrollViews.firstMatch.swipeUp()
        Thread.sleep(forTimeInterval: 1.5)  // Let the bounce settle and the bar finish its transition.

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "after-scrolling"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertGreaterThan(
            inkCoverage(in: frame), 0.05,
            "The navigation title stopped being drawn after scrolling."
        )
    }

    /// The share of dark pixels in a rect, in screen points. The title is near-black on the
    /// off-white brand surface, so "some ink is present" separates a drawn title from a blank bar.
    private func inkCoverage(in rect: CGRect) -> Double {
        let image = XCUIScreen.main.screenshot().image
        guard let cropped = image.cgImage?.cropping(to: rect.applying(
            CGAffineTransform(scaleX: image.scale, y: image.scale)
        )) else {
            XCTFail("Could not crop \(rect) out of the screenshot.")
            return 0
        }

        let width = cropped.width
        let height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            XCTFail("Could not build a grayscale context.")
            return 0
        }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Double(pixels.count { $0 < 128 }) / Double(width * height)
    }
}
