import SwiftUI
import Swiftetti
import UIKit

/// One celebratory burst of brand-yellow shards, thrown from the top edge and left to settle.
///
/// A burst, not a loop: the bible asks for restrained motion, and confetti that keeps falling
/// behind the text you're trying to read stops being celebration and starts being wallpaper.
/// `SwiftettiView` matches that shape — it emits one burst per rising edge of `trigger` and resets
/// the binding itself, so there is nothing to turn off.
///
/// Decorative by contract: hidden from assistive technology, never takes a touch, and under Reduce
/// Motion it renders nothing at all.
///
/// Nothing, rather than a motionless scatter: a still shard is no longer *moving*, but it is still
/// confetti, and the setting is a request to be spared the celebration rather than to receive a
/// quieter one. The headline and the buttons carry the screen on their own.
struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBursting = false

    var body: some View {
        Group {
            if reduceMotion {
                EmptyView()
            } else {
                SwiftettiView(
                    trigger: $isBursting,
                    // `fromTheTop` throws from above the top edge and lets everything fall, which
                    // is the motion the screen was designed around. The palette is ours.
                    settings: SwiftettiSettings.fromTheTop(),
                    colors: ConfettiPalette.brandYellows,
                    // Squares and circles only — the library's stars and hearts would be a second
                    // voice on a screen the brand already speaks for.
                    shapes: [.square, .circle]
                )
                .onAppear { isBursting = true }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Palette

/// Three tones of one token, derived in HSB from the asset catalog swatch.
///
/// Deriving beats declaring: there is no second and third hex literal to keep in step with
/// `BrandYellow`, and no `Color(hex:)` extension coming back in through the side door after it was
/// deliberately removed. If the token ever changes, the whole family follows it.
enum ConfettiPalette {
    static var brandYellows: [Color] {
        tones(of: UIColor(Brand.yellow)).map(Color.init(uiColor:))
    }

    static func tones(of color: UIColor) -> [UIColor] {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        else { return [color, color, color] }

        return [
            color,
            UIColor(
                hue: hue,
                saturation: min(1, saturation * 1.3),
                brightness: brightness * 0.86,
                alpha: alpha
            ),
            UIColor(
                hue: hue,
                saturation: saturation * 0.65,
                brightness: min(1, brightness * 1.03),
                alpha: alpha
            ),
        ]
    }
}
