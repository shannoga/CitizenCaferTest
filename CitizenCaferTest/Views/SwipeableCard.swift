import SwiftUI

/// Horizontal drag on the study card, layered outside `FlipCard`.
///
/// The gesture means one thing: a revealed card thrown to the left advances the deck. An
/// unrevealed card still follows the finger a little and refuses to leave — the tactile
/// counterpart to the greyed-out Next button, so the control reads as "not yet" rather than dead.
/// Flipping is the tap's job alone.
///
/// The offset deliberately lives here rather than in the parent. When the parent swaps the card's
/// `id`, this instance is retained until its removal transition finishes and keeps its own state,
/// so the throw continues from where the finger let go instead of snapping back to centre first.
struct SwipeableCard<Content: View>: View {
    let canAdvance: Bool
    /// False on the last card, where advancing finishes the deck instead of replacing the card —
    /// so there is no removal transition coming to carry the offset away, and the throw has to
    /// tidy up after itself.
    let advanceRemovesCard: Bool
    let onAdvance: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGFloat = 0

    /// Past this much leftward travel — or this much projected travel on a flick — the card leaves.
    private let throwDistance: CGFloat = 88
    private let flickDistance: CGFloat = 200
    /// A locked or wrong-way card follows the finger at a quarter speed, and no further than this.
    private let resistance: CGFloat = 0.25
    private let resistanceLimit: CGFloat = 40

    var body: some View {
        content
            .offset(x: offset)
            .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only a revealed card dragged left tracks the finger exactly. An unrevealed card,
                // or a rightward drag, is resisted — neither of those advances.
                offset = canAdvance && value.translation.width < 0
                    ? value.translation.width
                    : resisted(value.translation.width)
            }
            .onEnded { value in
                let thrown = canAdvance
                    && (value.translation.width < -throwDistance
                        || value.predictedEndTranslation.width < -flickDistance)

                if thrown { onAdvance() }

                // A thrown card that's about to be removed keeps its offset on purpose: the
                // parent's removal transition carries it the rest of the way, and animating home
                // would fight that. On the last card nothing is removed, so the same throw has to
                // put the card back itself or it would sit stranded off-centre.
                if !thrown || !advanceRemovesCard { returnHome() }
            }
    }

    /// Reduce Motion keeps the finger-tracking above — following a touch is direct manipulation,
    /// not unrequested motion — but drops the animated return, whose spring overshoots and bounces
    /// after the finger has already lifted.
    private func returnHome() {
        if reduceMotion {
            offset = 0
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
        }
    }

    private func resisted(_ translation: CGFloat) -> CGFloat {
        min(max(translation * resistance, -resistanceLimit), resistanceLimit)
    }
}

/// Hoisted out of `#Preview` so the interactive state has somewhere to live.
private struct SwipeableCardHarness: View {
    @State private var canAdvance = false
    @State private var isLastCard = false
    @State private var advances = 0

    var body: some View {
        VStack(spacing: 24) {
            SwipeableCard(canAdvance: canAdvance, advanceRemovesCard: !isLastCard) {
                advances += 1
                canAdvance = false
            } content: {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(canAdvance ? Color.green.opacity(0.25) : Color.gray.opacity(0.25))
                    .frame(height: 280)
                    .overlay(Text(canAdvance ? "Throw me left" : "Locked — drag resists"))
            }

            // Stands in for the tap that reveals the card, which this harness has no card to do.
            Toggle("Revealed (can advance)", isOn: $canAdvance)

            // There is no parent here to remove the card on a throw, so with this off a
            // successful throw correctly leaves it lying where it landed.
            Toggle("Last card (throw springs home)", isOn: $isLastCard)

            Text("Advanced \(advances) times")
        }
        .padding()
    }
}

#Preview {
    SwipeableCardHarness()
}

// There is no Reduce Motion variant of this preview because there can't be:
// `accessibilityReduceMotion` is a get-only environment value, so `.environment(_:_:)` won't accept
// it. To check the Reduce Motion path — drag and release short of the threshold, and the card should
// arrive back at centre with no spring and no overshoot — turn it on in the simulator under
// Settings › Accessibility › Motion, or in the canvas's accessibility inspector.
