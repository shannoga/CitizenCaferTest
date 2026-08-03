import SwiftUI

/// A card that rotates about its vertical axis to reveal a second face.
///
/// The rotation is a real 3D transform, not a cross-fade: the whole stack turns 180°, the back face
/// is pre-rotated 180° so its text never renders mirrored, and the opacity swap is a near-instant
/// change delayed to the exact midpoint of the turn, so only one face is ever visible.
///
/// Under Reduce Motion the turn is dropped and only the cross-fade remains. Both rotations have to
/// go together: the back face's pre-rotation exists solely to cancel the container's, so leaving
/// either one behind is what mirrors the text rather than what prevents it.
struct FlipCard<Front: View, Back: View>: View {
    let isFlipped: Bool
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let duration = 0.5

    var body: some View {
        ZStack {
            front.opacity(isFlipped ? 0 : 1)
            back
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        // Inner animation governs the face swap only.
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : .linear(duration: 0.001).delay(duration / 2),
            value: isFlipped
        )
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : (isFlipped ? 180 : 0)),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.4
        )
        // Outer animation governs the rotation; under Reduce Motion it animates a constant.
        .animation(reduceMotion ? nil : .easeInOut(duration: duration), value: isFlipped)
    }
}
