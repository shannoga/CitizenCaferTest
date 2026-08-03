import ComposableArchitecture
import SwiftUI

struct StudyView: View {
    let store: StoreOf<StudyFeature>

    var body: some View {
        VStack(spacing: Brand.Space.xl) {
            Spacer(minLength: 0)

            if let card = store.currentCard {
                FlipCard(isFlipped: store.isShowingEnglish) {
                    cardFace {
                        Text(card.hebrew)
                            .font(.brandDisplay(48))
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                } back: {
                    cardFace {
                        Text(card.english)
                            .font(.title2.weight(.medium))
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

    private var controls: some View {
        HStack {
            Button {
                store.send(.shuffleButtonTapped)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .labelStyle(.iconOnly)
                    .frame(width: 48, height: 48)
                    .background(Brand.raised, in: Circle())
                    .hairlineBorder(radius: 24)
            }
            .accessibilityLabel("Shuffle the deck")

            Spacer()

            Text(store.progress)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Brand.textMuted)
                .accessibilityLabel("Card \(store.progress)")

            Spacer()

            Button {
                store.send(.nextButtonTapped)
            } label: {
                Label("Next", systemImage: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(Brand.charcoal)
                    .padding(.horizontal, Brand.Space.lg)
                    .frame(height: 48)
                    .background(Brand.yellow, in: Capsule())
            }
            .accessibilityLabel("Next card")
        }
        .tint(Brand.textPrimary)
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
