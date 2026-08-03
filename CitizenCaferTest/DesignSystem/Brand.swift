import SwiftUI

/// Brand tokens from the Citizen Café design bible, resolved through the asset catalog so light
/// and dark appearances come from one place.
///
/// The type half of the bible lives in `BrandTypography`.
enum Brand {
    static let charcoal = Color("BrandCharcoal")
    static let line = Color("LineSubtle")
    static let surface = Color("SurfaceBase")
    static let raised = Color("SurfaceRaised")
    static let textMuted = Color("TextMuted")
    static let textPrimary = Color("TextPrimary")
    static let yellow = Color("BrandYellow")

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 12
    }

    enum Space {
        static let lg: CGFloat = 24
        static let md: CGFloat = 16
        static let sm: CGFloat = 8
        static let xl: CGFloat = 32
    }

    /// Levels are literally named after colors, so the dot just resolves the name to its asset
    /// catalog swatch.
    static func levelColor(for level: String) -> Color? {
        levelAssetNameByLevel[level].map { Color($0) }
    }

    private static let levelAssetNameByLevel: [String: String] = [
        "Red": "LevelRed",
        "Orange": "LevelOrange",
        "Pink": "LevelPink",
        "Yellow": "LevelYellow",
        "Light Blue": "LevelLightBlue",
        "Blue": "LevelBlue",
        "Lime": "LevelLime",
        "Green": "LevelGreen",
        "Dark Green": "LevelDarkGreen",
        "Turquoise": "LevelTurquoise",
        "Indigo": "LevelIndigo",
        "Purple": "LevelPurple",
    ]
}

/// The thin neutral rule that borders nearly every surface in the bible.
struct HairlineBorder: ViewModifier {
    var radius: CGFloat = Brand.Radius.control

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Brand.line, lineWidth: 1)
        }
    }
}

extension View {
    func hairlineBorder(radius: CGFloat = Brand.Radius.control) -> some View {
        modifier(HairlineBorder(radius: radius))
    }
}
