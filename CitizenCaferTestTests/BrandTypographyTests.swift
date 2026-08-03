import SwiftUI
import UIKit
import XCTest

@testable import CitizenCaferTest

/// The typography rules in the design bible are mostly invisible at runtime: a face that fails to
/// register, a fallback that never fires, or a line height a few points short all still render
/// something. These tests hold each rule to a number.
final class BrandTypographyTests: XCTestCase {

    /// A vocabulary word carrying the marks the cards actually show.
    private let hebrewSample = "שָׁלוֹם"
    private let latinSample = "Choose what to study — Café"

    // MARK: - The faces exist

    func testEveryBrandFaceIsBundledAndRegistered() {
        XCTAssertTrue(BrandTypography.register(), "Brand fonts failed to register from the bundle.")

        for face in BrandTypography.allFaces {
            XCTAssertNotNil(UIFont(name: face, size: 17), "\(face) is not available under that name.")
        }
    }

    func testEveryRoleResolvesToItsBundledFaceAndNotASystemSubstitute() {
        for role in BrandTypography.Role.allCases {
            let font = BrandTypography.resolvedFont(for: role, at: .large)
            XCTAssertEqual(font.fontName, role.face, "\(role) fell back to \(font.fontName).")
        }
    }

    // MARK: - Assistant is the system, Fedra is the voice

    /// Fedra is used selectively — headings only. Everything functional is Assistant.
    func testOnlyHeadingRolesUseTheVoiceFace() {
        let voice = Set(BrandTypography.Display.allCases.map(\.rawValue))
        let system = Set(BrandTypography.UI.allCases.map(\.rawValue))

        for role in BrandTypography.Role.allCases {
            switch role {
            case .h1, .h2:
                XCTAssertTrue(voice.contains(role.face), "\(role) is a heading and should be Fedra.")
            default:
                XCTAssertTrue(system.contains(role.face), "\(role) is functional and should be Assistant.")
            }
        }
    }

    // MARK: - Script coverage

    /// Assistant carries every Hebrew role, the card prompt included, because the Fedra Sans Pro
    /// kit has no Hebrew. If Assistant ever lost that coverage the cards would quietly fall back
    /// to a system font mid-word.
    func testSystemVoiceCoversHebrewWithNikud() throws {
        for face in BrandTypography.UI.allCases {
            try assertCoverage(of: hebrewSample, by: face.rawValue)
        }
    }

    func testDisplayVoiceCoversTheLatinItRenders() throws {
        for face in BrandTypography.Display.allCases {
            try assertCoverage(of: latinSample, by: face.rawValue)
        }
    }

    /// Pins the split the design rests on: Fedra is Latin-only, so the Hebrew prompt must not use
    /// it. A Fedra Sans Hebrew licence would make this the test to delete.
    func testHebrewPromptDoesNotUseTheLatinOnlyVoiceFace() throws {
        for face in BrandTypography.Display.allCases {
            XCTAssertFalse(
                try covers(hebrewSample, face.rawValue),
                "\(face.rawValue) gained Hebrew — the card prompt can move onto the display voice."
            )
            XCTAssertNotEqual(BrandTypography.Role.cardPrompt.face, face.rawValue)
        }

        try assertCoverage(of: hebrewSample, by: BrandTypography.Role.cardPrompt.face)
    }

    // MARK: - "Provide fallback stacks, especially for Fedra"

    /// Every Fedra role names Assistant as its fallback, so off-script text inside a heading stays
    /// in the brand's own Hebrew face instead of dropping to the system font.
    func testVoiceRolesFallBackToTheSystemFaceBeforeTheSystemFont() throws {
        for role in BrandTypography.Role.allCases where role.face.hasPrefix("FedraSansPro") {
            let fallbacks = role.cascade
            XCTAssertFalse(fallbacks.isEmpty, "\(role) uses Fedra with no fallback stack.")

            for fallback in fallbacks {
                XCTAssertTrue(
                    BrandTypography.UI.allCases.map(\.rawValue).contains(fallback),
                    "\(role) falls back to \(fallback), which is not the brand's system face."
                )
                try assertCoverage(of: hebrewSample, by: fallback)
            }

            let resolved = BrandTypography.resolvedFont(for: role, at: .large)
            let cascade = resolved.fontDescriptor.fontAttributes[.cascadeList] as? [UIFontDescriptor]
            XCTAssertEqual(
                cascade?.count, fallbacks.count,
                "\(role)'s fallback stack never reached the resolved font."
            )
        }
    }

    // MARK: - "Keep body line-height at >= 1.4"

    func testBodyCopyClearsTheLineHeightFloorAtEveryTextSize() {
        let categories: [UIContentSizeCategory] = [.extraSmall, .large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge]

        for role in BrandTypography.Role.allCases where role.isBodyCopy {
            for category in categories {
                let font = BrandTypography.resolvedFont(for: role, at: category)
                let lineHeight = font.lineHeight + BrandTypography.lineSpacing(for: role, resolved: font)
                let ratio = lineHeight / font.pointSize

                XCTAssertGreaterThanOrEqual(
                    ratio, BrandTypography.bodyLineHeightRatio - 0.001,
                    "\(role) sets \(ratio) line height at \(category.rawValue) — below the 1.4 floor."
                )
            }
        }
    }

    /// The floor is a floor, not a target: headings and controls keep their own leading.
    func testNonBodyRolesAreNotGivenExtraLeading() {
        for role in BrandTypography.Role.allCases where !role.isBodyCopy {
            let font = BrandTypography.resolvedFont(for: role, at: .large)
            XCTAssertEqual(BrandTypography.lineSpacing(for: role, resolved: font), 0, "\(role) gained leading it shouldn't have.")
        }
    }

    // MARK: - Dynamic Type

    func testRolesScaleWithTheUsersTextSize() {
        for role in BrandTypography.Role.allCases {
            let small = BrandTypography.resolvedFont(for: role, at: .extraSmall).pointSize
            let large = BrandTypography.resolvedFont(for: role, at: .accessibilityExtraExtraExtraLarge).pointSize

            XCTAssertGreaterThan(large, small, "\(role) does not respond to Dynamic Type.")
        }
    }

    // MARK: - Helpers

    private func assertCoverage(
        of sample: String,
        by face: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(
            try covers(sample, face),
            "\(face) is missing glyphs for “\(sample)” — that text would fall back to another font.",
            file: file,
            line: line
        )
    }

    private func covers(_ sample: String, _ face: String) throws -> Bool {
        XCTAssertTrue(BrandTypography.register())
        let font = try XCTUnwrap(UIFont(name: face, size: 48) as CTFont?)
        var characters = Array(sample.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
    }
}
