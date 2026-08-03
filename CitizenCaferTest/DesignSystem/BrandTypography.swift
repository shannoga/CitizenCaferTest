import CoreText
import SwiftUI
import UIKit

/// The dual-type system from the Citizen Café design bible: **Assistant is the system, Fedra is
/// the voice.**
///
/// Fedra Sans Pro is used selectively — page and section titles — and Assistant carries everything
/// functional: navigation, labels, controls, body copy, metadata. No component mixes the two.
///
/// The Fedra Sans Pro kit we license is Latin/Cyrillic/Greek and has no Hebrew. That costs nothing
/// here: the bible pairs Fedra with Assistant precisely because Assistant is the Hebrew companion,
/// so the Hebrew card prompt is Assistant by design rather than by compromise. Display faces still
/// carry an explicit Assistant fallback (see `cascade`), so a Hebrew word appearing inside a title
/// lands on the brand's own Hebrew face instead of the system one.
enum BrandTypography {

    /// Voice — `font-family-brand`. Latin only, used selectively.
    enum Display: String, CaseIterable {
        case medium = "FedraSansPro-Medium"
        case bold = "FedraSansPro-Bold"
    }

    /// System — `font-family-primary`. Everything functional, and all Hebrew.
    enum UI: String, CaseIterable {
        case regular = "Assistant-Regular"
        case semibold = "Assistant-SemiBold"
        case bold = "Assistant-Bold"
    }

    /// Body copy never sets tighter than this, per the bible's line-height floor. Assistant's own
    /// line height is ~1.31em, so the roles below make up the difference with line spacing.
    static let bodyLineHeightRatio: CGFloat = 1.4

    /// The bible's structural hierarchy, one case per role. A role owns its face, its size, the
    /// text style it scales from, and whether it is body copy subject to the line-height floor.
    enum Role: CaseIterable {
        /// `display.hero` — the Hebrew prompt on the card. Assistant, because Fedra has no Hebrew.
        case cardPrompt
        /// The English answer on the card back.
        case cardAnswer
        /// `heading.h1` — major page title.
        case h1
        /// `heading.h2` — section title.
        case h2
        /// `body.default` — body copy.
        case body
        /// Body copy in a supporting size: error detail, status lines.
        case bodySmall
        /// `ui.label` — labels, navigation, controls.
        case uiLabel
        /// `button.label` — CTA and control labels.
        case buttonLabel
        /// `meta.small` — quiet metadata.
        case metaSmall
        /// `meta.small` where the value is numeric and must not jitter as it counts up.
        case metaDigits

        var face: String {
            switch self {
            case .h1, .h2: Display.bold.rawValue
            case .cardPrompt: UI.bold.rawValue
            case .cardAnswer, .buttonLabel: UI.semibold.rawValue
            case .body, .bodySmall, .metaDigits, .metaSmall, .uiLabel: UI.regular.rawValue
            }
        }

        var size: CGFloat {
            switch self {
            case .cardPrompt: 48
            case .h1: 30
            case .cardAnswer: 24
            case .h2: 22
            case .body, .buttonLabel, .uiLabel: 17
            case .bodySmall: 15
            case .metaDigits, .metaSmall: 13
            }
        }

        /// Only running copy takes the line-height floor; a title or a control label would just
        /// gain slack it doesn't need.
        var isBodyCopy: Bool {
            switch self {
            case .body, .bodySmall, .metaSmall: true
            case .buttonLabel, .cardAnswer, .cardPrompt, .h1, .h2, .metaDigits, .uiLabel: false
            }
        }

        var usesMonospacedDigits: Bool { self == .metaDigits }

        /// What this role falls back to when its face lacks a glyph. Fedra gets Assistant ahead of
        /// the system font so off-script text stays inside the brand.
        var cascade: [String] {
            switch self {
            case .h1, .h2: [UI.bold.rawValue]
            case .body, .bodySmall, .buttonLabel, .cardAnswer, .cardPrompt, .metaDigits, .metaSmall, .uiLabel: []
            }
        }

        var textStyle: UIFont.TextStyle {
            switch self {
            case .cardPrompt: .largeTitle
            case .h1: .title1
            case .cardAnswer, .h2: .title2
            case .body, .uiLabel: .body
            case .buttonLabel: .headline
            case .bodySmall: .subheadline
            case .metaDigits, .metaSmall: .footnote
            }
        }

        /// The weight to fall back on if the bundled face is ever missing from the app.
        fileprivate var systemWeight: UIFont.Weight {
            switch self {
            case .cardPrompt, .h1, .h2: .bold
            case .buttonLabel, .cardAnswer: .semibold
            case .body, .bodySmall, .metaDigits, .metaSmall, .uiLabel: .regular
            }
        }
    }

    /// Every bundled face, by the file name it ships under (which is also its PostScript name).
    static var allFaces: [String] {
        Display.allCases.map(\.rawValue) + UI.allCases.map(\.rawValue)
    }

    /// Registers the bundled faces with Core Text. Idempotent, and safe to call off the main
    /// thread. Returns `false` when a face is missing from the bundle — roles then fall back to
    /// system type rather than rendering in whatever Core Text substitutes.
    @discardableResult
    static func register() -> Bool {
        areFacesAvailable
    }

    /// A role resolved for a size category: the bundled face, its fallback cascade, and Dynamic
    /// Type scaling already applied.
    static func resolvedFont(for role: Role, at sizeCategory: UIContentSizeCategory) -> UIFont {
        let base = (register() ? UIFont(name: role.face, size: role.size) : nil)
            ?? .systemFont(ofSize: role.size, weight: role.systemWeight)

        return UIFontMetrics(forTextStyle: role.textStyle).scaledFont(
            for: base.cascading(to: role.cascade),
            compatibleWith: UITraitCollection(preferredContentSizeCategory: sizeCategory)
        )
    }

    /// The extra leading a role needs to clear the body line-height floor, given its already
    /// scaled font. Zero for everything that isn't running copy.
    static func lineSpacing(for role: Role, resolved font: UIFont) -> CGFloat {
        guard role.isBodyCopy else { return 0 }
        return max(0, font.pointSize * bodyLineHeightRatio - font.lineHeight)
    }
}

// MARK: - Applying a role

extension View {
    /// Applies a typography role: its face, its Dynamic Type scaling, and its line height.
    func brandType(_ role: BrandTypography.Role) -> some View {
        modifier(BrandTypeModifier(role: role))
    }
}

private struct BrandTypeModifier: ViewModifier {
    let role: BrandTypography.Role

    // Read so the font is recomputed when the user changes text size: it carries its scaling baked
    // in, so nothing else would notice the change.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let resolved = BrandTypography.resolvedFont(for: role, at: dynamicTypeSize.contentSizeCategory)
        let font = role.usesMonospacedDigits ? Font(resolved).monospacedDigit() : Font(resolved)

        return content
            .font(font)
            .lineSpacing(BrandTypography.lineSpacing(for: role, resolved: resolved))
    }
}

// MARK: - Registration

/// Evaluated once, lazily, on the first font access from any thread — including from a preview or
/// a test, neither of which runs the app's `init`.
private let areFacesAvailable: Bool = {
    let urls = BrandTypography.allFaces.compactMap(fontURL(named:))
    guard urls.count == BrandTypography.allFaces.count else {
        assertionFailure("Brand fonts missing from the bundle: falling back to system type.")
        return false
    }

    CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, _ in
        // A face that is already registered is not a failure — the app and its tests can both
        // reach this path in the same process.
        let fatal = (errors as? [Error]).map {
            $0.contains { ($0 as NSError).code != CTFontManagerError.alreadyRegistered.rawValue }
        }
        assert(fatal != true, "Brand font registration failed: \(errors)")
        return true
    }

    return BrandTypography.allFaces.allSatisfy { UIFont(name: $0, size: 12) != nil }
}()

private func fontURL(named name: String) -> URL? {
    let bundle = Bundle(for: BrandFontBundleToken.self)
    // Synchronised Xcode groups flatten resources into the bundle root; the subdirectory lookup is
    // the fallback for a folder reference.
    return bundle.url(forResource: name, withExtension: "ttf")
        ?? bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
}

/// Anchors `Bundle(for:)` to the module that owns the fonts.
private final class BrandFontBundleToken {}

// MARK: - UIKit surfaces

extension UIFont {
    /// This font with an explicit fallback stack: Core Text walks the cascade before it reaches
    /// for a system substitute.
    func cascading(to faces: [String]) -> UIFont {
        guard !faces.isEmpty else { return self }
        let fallbacks = faces.compactMap { UIFont(name: $0, size: pointSize)?.fontDescriptor }
        guard !fallbacks.isEmpty else { return self }
        return UIFont(
            descriptor: fontDescriptor.addingAttributes([.cascadeList: fallbacks]),
            size: pointSize
        )
    }
}

extension DynamicTypeSize {
    /// SwiftUI's size, in the units `UIFontMetrics` scales by.
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

extension BrandTypography {
    /// Navigation bars are drawn by UIKit, so they need the faces handed over explicitly —
    /// otherwise the one system-font island sits right above brand-typeset content. The large
    /// title is a page title (Fedra); the inline title is navigation chrome (Assistant).
    @MainActor
    static func applyNavigationBarAppearance() {
        guard register() else { return }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Brand.surface)
        appearance.shadowColor = UIColor(Brand.line)

        let primary = UIColor(Brand.textPrimary)
        let category = UIApplication.shared.preferredContentSizeCategory
        appearance.largeTitleTextAttributes = [
            .font: resolvedFont(for: .h1, at: category), .foregroundColor: primary,
        ]
        appearance.titleTextAttributes = [
            .font: resolvedFont(for: .buttonLabel, at: category), .foregroundColor: primary,
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
