import SwiftUI

/// Horizontal drag on the study card, layered outside `FlipCard`.
///
/// The gesture means two different things depending on whether the card has been revealed, so it
/// commits to one of them on its first movement — otherwise a flip landing mid-drag would silently
/// turn the same continuous drag into a swipe. Before the reveal the card is resisted and can only
/// flip; after it, a leftward throw advances.
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
    let onFlip: () -> Void
    @ViewBuilder var content: Content

    @State private var mode: DragMode?
    @State private var offset: CGFloat = 0

    private enum DragMode { case advance, flip }

    /// Past this much leftward travel — or this much projected travel on a flick — the card leaves.
    private let throwDistance: CGFloat = 88
    private let flickDistance: CGFloat = 200
    /// A shorter reach for the flip, which is a smaller commitment than losing the card.
    private let flipDistance: CGFloat = 60
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
                let mode = self.mode ?? (canAdvance ? .advance : .flip)
                self.mode = mode

                switch mode {
                case .advance:
                    // Left tracks the finger exactly; right is refused, because right doesn't advance.
                    offset = value.translation.width < 0
                        ? value.translation.width
                        : resisted(value.translation.width)
                case .flip:
                    offset = resisted(value.translation.width)
                }
            }
            .onEnded { value in
                // Explicitly `self.mode`, because the `guard let` below shadows the name.
                defer { self.mode = nil }
                guard let mode else { return }

                switch mode {
                case .advance:
                    let thrown = value.translation.width < -throwDistance
                        || value.predictedEndTranslation.width < -flickDistance

                    if thrown { onAdvance() }

                    // A thrown card that's about to be removed keeps its offset on purpose: the
                    // parent's removal transition carries it the rest of the way, and animating
                    // home would fight that. On the last card nothing is removed, so the same
                    // throw has to put the card back itself or it would sit stranded off-centre.
                    if !thrown || !advanceRemovesCard {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                    }
                case .flip:
                    if abs(value.translation.width) > flipDistance { onFlip() }
                    // Snapped home fast, so the slide back doesn't compete with the rotation.
                    withAnimation(.easeOut(duration: 0.15)) { offset = 0 }
                }
            }
    }

    private func resisted(_ translation: CGFloat) -> CGFloat {
        min(max(translation * resistance, -resistanceLimit), resistanceLimit)
    }
}

#Preview {
    struct Harness: View {
        @State private var canAdvance = false
        @State private var isLastCard = false
        @State private var advances = 0

        var body: some View {
            VStack(spacing: 24) {
                SwipeableCard(canAdvance: canAdvance, advanceRemovesCard: !isLastCard) {
                    advances += 1
                    canAdvance = false
                } onFlip: {
                    canAdvance = true
                } content: {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(canAdvance ? Color.green.opacity(0.25) : Color.gray.opacity(0.25))
                        .frame(height: 280)
                        .overlay(Text(canAdvance ? "Throw me left" : "Drag to flip"))
                }

                // There is no parent here to remove the card on a throw, so with this off a
                // successful throw correctly leaves it lying where it landed.
                Toggle("Last card (throw springs home)", isOn: $isLastCard)

                Text("Advanced \(advances) times")
            }
            .padding()
        }
    }

    return Harness()
}
