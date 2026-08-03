import ComposableArchitecture
import SwiftUI

struct StudyView: View {
    let store: StoreOf<StudyFeature>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AccessibilityFocusState private var isCardFocused: Bool

    /// Drives the flip haptic, and lives here rather than in `State` because it is presentation,
    /// not domain. Triggering on `isShowingEnglish` instead would be wrong twice over: `advance`
    /// clears it, so Next would buzz, and `restart()` clears it, so Shuffle would too.
    @State private var flipTicks = 0

    /// The circular control grows with the text so its glyph never outruns its background, and so
    /// the touch target gets larger for the people who asked for larger type.
    @ScaledMetric(relativeTo: .body) private var controlDiameter: CGFloat = 48

    var body: some View {
        VStack(spacing: Brand.Space.xl) {
            Spacer(minLength: 0)

            if let card = store.currentCard {
                // A ZStack so the outgoing and incoming cards overlap during the transition instead
                // of stacking the VStack to twice the height.
                ZStack {
                    SwipeableCard(
                        canAdvance: store.canAdvance,
                        // The last card finishes the deck rather than being replaced, so there's no
                        // removal transition coming and the throw has to put the card back itself.
                        advanceRemovesCard: !store.isOnLastCard,
                        onAdvance: { store.send(.cardSwiped) }
                    ) {
                        FlipCard(isFlipped: store.isShowingEnglish) {
                            cardFace {
                                Text(card.hebrew)
                                    .brandType(.cardPrompt)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }
                        } back: {
                            cardFace {
                                Text(card.english)
                                    .brandType(.cardAnswer)
                                    .foregroundStyle(Brand.textMuted)
                            }
                        }
                        .onTapGesture {
                            flipTicks += 1
                            store.send(.cardTapped)
                        }
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: flipTicks)
                        .accessibilityElement(children: .combine)
                        // Carries the language the face is written in, so a Hebrew word is spoken
                        // by a Hebrew voice inside an otherwise English app.
                        .accessibilityLabel(Text(store.cardAccessibilityLabel))
                        .accessibilityValue("Card \(store.progress)")
                        .accessibilityHint("Double tap to reveal the \(store.isShowingEnglish ? "Hebrew" : "English").")
                        .accessibilityAddTraits(.isButton)
                        // VoiceOver owns horizontal swipes, so the drag gesture never reaches these
                        // readers. This puts the same move on the card the gesture lives on — the
                        // reducer applies the reveal gate either way.
                        .accessibilityAction(named: store.isOnLastCard ? "Finish the deck" : "Next card") {
                            store.send(.nextButtonTapped)
                        }
                        .accessibilityFocused($isCardFocused)
                    }
                    // Identity is the whole mechanism: the Next button and the swipe both do nothing
                    // but change the index, so they share one transition for free.
                    .id(store.index)
                    .transition(cardTransition)
                }
                .animation(cardAnimation, value: store.index)
                // Advancing swaps the card's `id`, which destroys the element VoiceOver was sitting
                // on and drops focus back to the top of the screen. This hands it to the card that
                // replaced it, which is where the reader already was.
                .onChange(of: store.index) { isCardFocused = true }
            } else {
                Text("This pack has no words yet.")
                    .brandType(.body)
                    .foregroundStyle(Brand.textMuted)
            }

            Spacer(minLength: 0)

            controls
        }
        .padding(Brand.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.surface)
        .navigationTitle(store.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The bar's title-text styling comes from `UINavigationBarAppearance`, so a custom
            // principal view has to match it by hand rather than relying on `.navigationTitle`.
            ToolbarItem(placement: .principal) {
                HStack(spacing: Brand.Space.sm) {
                    if let color = Brand.levelColor(for: store.level) {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                    }
                    Text(store.title)
                        .brandType(.buttonLabel)
                        .foregroundStyle(Brand.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Broken out rather than written inline so the ternary has an explicit type to resolve the
    /// leading-dot cases against.
    private var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }

    private var cardAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy
    }

    private func cardFace<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .multilineTextAlignment(.center)
            .foregroundStyle(Brand.textPrimary)
            .padding(Brand.Space.xl)
            .frame(maxWidth: .infinity, minHeight: 280)
            .background(Brand.raised, in: RoundedRectangle(cornerRadius: Brand.Radius.card, style: .continuous))
            .hairlineBorder(radius: Brand.Radius.card)
    }

    /// One row while the labels fit; at accessibility sizes Next takes its own full-width line
    /// rather than pushing the counter under the shuffle button and running off the screen.
    private var controls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Brand.Space.md) {
                    HStack {
                        shuffleButton
                        Spacer()
                        progress
                    }
                    nextButton.frame(maxWidth: .infinity)
                }
            } else {
                HStack {
                    shuffleButton
                    Spacer()
                    progress
                    Spacer()
                    nextButton
                }
            }
        }
        .tint(Brand.textPrimary)
    }

    private var shuffleButton: some View {
        Button {
            store.send(.shuffleButtonTapped)
        } label: {
            Label("Shuffle", systemImage: "shuffle")
                .labelStyle(.iconOnly)
                .frame(width: controlDiameter, height: controlDiameter)
                .background(Brand.raised, in: Circle())
                .hairlineBorder(radius: controlDiameter / 2)
        }
        .accessibilityLabel("Shuffle the deck")
    }

    private var progress: some View {
        Text(store.progress)
            .brandType(.metaDigits)
            .foregroundStyle(Brand.textMuted)
            .accessibilityLabel("Card \(store.progress)")
    }

    private var nextButton: some View {
        Button {
            store.send(.nextButtonTapped)
        } label: {
            // The last card finishes rather than advances, so the button stops promising a card
            // that isn't coming.
            Label(
                store.isOnLastCard ? "Finish" : "Next",
                systemImage: store.isOnLastCard ? "checkmark" : "arrow.right"
            )
            .brandType(.buttonLabel)
            .foregroundStyle(store.canAdvance ? Brand.charcoal : Brand.textMuted)
            .padding(.horizontal, Brand.Space.lg)
            .frame(minHeight: controlDiameter)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            .background(store.canAdvance ? Brand.yellow : Brand.line, in: Capsule())
        }
        .disabled(!store.canAdvance)
        .animation(.easeInOut(duration: 0.2), value: store.canAdvance)
        .accessibilityLabel(store.isOnLastCard ? "Finish the deck" : "Next card")
        .accessibilityHint(store.canAdvance ? "" : "Flip the card to reveal the English first.")
    }
}

#Preview {
    NavigationStack {
        StudyView(
            store: Store(
                initialState: StudyFeature.State(
                    set: VocabSet(
                        tier: "Foundation",
                        level: "Red",
                        type: nil,
                        pairs: [
                            WordPair(hebrew: "שָׁלוֹם", english: "Hello / Peace"),
                            WordPair(hebrew: "תּוֹדָה", english: "Thank you"),
                        ]
                    )
                )
            ) {
                StudyFeature()
            }
        )
    }
}
