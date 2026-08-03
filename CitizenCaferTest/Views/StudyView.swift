import ComposableArchitecture
import SwiftUI

struct StudyView: View {
    let store: StoreOf<StudyFeature>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The circular control grows with the text so its glyph never outruns its background, and so
    /// the touch target gets larger for the people who asked for larger type.
    @ScaledMetric(relativeTo: .body) private var controlDiameter: CGFloat = 48

    var body: some View {
        VStack(spacing: Brand.Space.xl) {
            Spacer(minLength: 0)

            if let card = store.currentCard {
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
                .onTapGesture { store.send(.cardTapped) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(store.isShowingEnglish ? card.english : card.hebrew)
                .accessibilityHint("Double tap to reveal the \(store.isShowingEnglish ? "Hebrew" : "English").")
                .accessibilityAddTraits(.isButton)
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
            Label("Next", systemImage: "arrow.right")
                .brandType(.buttonLabel)
                .foregroundStyle(store.canAdvance ? Brand.charcoal : Brand.textMuted)
                .padding(.horizontal, Brand.Space.lg)
                .frame(minHeight: controlDiameter)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .background(store.canAdvance ? Brand.yellow : Brand.line, in: Capsule())
        }
        .disabled(!store.canAdvance)
        .animation(.easeInOut(duration: 0.2), value: store.canAdvance)
        .accessibilityLabel("Next card")
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
