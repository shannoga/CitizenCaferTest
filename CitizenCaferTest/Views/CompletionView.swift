import ComposableArchitecture
import SwiftUI

struct CompletionView: View {
    let store: StoreOf<CompletionFeature>

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()

            // Behind the content, not in front of it: the charcoal-on-yellow contrast rule and the
            // bible's "restrained motion" line both object to yellow shards crossing 13pt
            // charcoal metadata.
            ConfettiBurst()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Brand.Space.xl) {
                Spacer(minLength: 0)
                headline
                Spacer(minLength: 0)
                actions
            }
            .padding(Brand.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // The deck is done; going "back" to it is not one of the ways forward. The three buttons
        // below are the only exits, which also stops the interactive swipe from stranding someone
        // on the last card of a pack they just finished.
        .navigationBarBackButtonHidden(true)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Brand.Space.sm) {
            // `.body` rather than `.metaSmall`: at 13pt these read as footnotes to the headline
            // when they are actually the sentence it completes.
            Text("You just completed")
                .brandType(.body)
                .foregroundStyle(Brand.textMuted)

            Text(store.tierLine)
                .brandType(.h1)
                .foregroundStyle(Brand.textPrimary)

            // The same dot-and-label construction as the study screen's toolbar, which ties this
            // screen back to the deck you just finished — and puts a non-yellow accent on a screen
            // that is otherwise carefully rationing yellow.
            HStack(spacing: Brand.Space.sm) {
                if let color = Brand.levelColor(for: store.set.level) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                }
                Text(store.packLine)
                    .brandType(.uiLabel)
                    .foregroundStyle(Brand.textPrimary)
            }

            Text(store.metaLine)
                .brandType(.body)
                .foregroundStyle(Brand.textMuted)
                .padding(.top, Brand.Space.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.accessibilityHeadline)
        .accessibilityAddTraits(.isHeader)
        // Puts the outcome ahead of the buttons, so VoiceOver's screen-change announcement reads
        // what happened rather than what to do about it. Deliberately not `AccessibilityFocusState`
        // in `onAppear`: focus assignment straight after a push is timing-sensitive and would need
        // a sleep to be reliable.
        .accessibilitySortPriority(2)
        .accessibilityIdentifier("completion.headline")
    }

    /// Exactly one yellow element, and it is whichever button means "keep going": the next pack
    /// when there is one, this pack again when there isn't. The bible's rule is yellow as emphasis,
    /// not wallpaper — three filled CTAs would make this screen the exception that proves it.
    private var actions: some View {
        VStack(spacing: Brand.Space.md) {
            if store.nextSet != nil {
                primaryButton("Next pack", identifier: "completion.nextPack") {
                    store.send(.nextPackButtonTapped)
                }
                secondaryButton("Study this pack again", identifier: "completion.studyAgain") {
                    store.send(.studyAgainButtonTapped)
                }
            } else {
                primaryButton("Study this pack again", identifier: "completion.studyAgain") {
                    store.send(.studyAgainButtonTapped)
                }
            }

            Button {
                store.send(.backToBrowseButtonTapped)
            } label: {
                Text("Back to Main Menu")
                    .brandType(.buttonLabel)
                    .foregroundStyle(Brand.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("completion.backToBrowse")
        }
    }

    /// The "Start studying" treatment, unchanged — charcoal on yellow, never white.
    private func primaryButton(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .brandType(.buttonLabel)
                .foregroundStyle(Brand.charcoal)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    Brand.yellow,
                    in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous)
                )
        }
        .accessibilityIdentifier(identifier)
    }

    /// The raised-surface-plus-hairline treatment the picker card already uses.
    private func secondaryButton(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .brandType(.buttonLabel)
                .foregroundStyle(Brand.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    Brand.raised,
                    in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous)
                )
                .hairlineBorder(radius: Brand.Radius.control)
        }
        .accessibilityIdentifier(identifier)
    }
}

// There is no Reduce Motion variant of this preview because there can't be:
// `accessibilityReduceMotion` is a get-only environment value, so `.environment(_:_:)` won't accept
// it. To check that path — the screen should render no confetti at all — turn Reduce Motion on in
// the simulator under Settings › Accessibility › Motion, or in the canvas's accessibility inspector.
#Preview {
    NavigationStack {
        CompletionView(
            store: Store(
                initialState: CompletionFeature.State(
                    set: VocabSet(
                        tier: "Foundation",
                        level: "Red",
                        type: 2,
                        pairs: [
                            WordPair(hebrew: "שָׁלוֹם", english: "Hello / Peace"),
                            WordPair(hebrew: "תּוֹדָה", english: "Thank you"),
                        ]
                    ),
                    nextSet: VocabSet(tier: "Foundation", level: "Red", type: 3, pairs: [])
                )
            ) {
                CompletionFeature()
            }
        )
    }
}
