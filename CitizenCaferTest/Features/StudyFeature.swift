import ComposableArchitecture
import Foundation

@Reducer
struct StudyFeature {
    @ObservableState
    struct State: Equatable {
        var cards: [WordPair]
        var hasRevealedCurrentCard = false
        var index = 0
        var isShowingEnglish = false
        var title: String

        init(set: VocabSet) {
            self.cards = set.pairs
            self.title = set.type.map { "\(set.level) · Pack \($0)" } ?? set.level
        }

        var currentCard: WordPair? {
            cards.indices.contains(index) ? cards[index] : nil
        }

        var progress: String { "\(min(index + 1, cards.count)) / \(cards.count)" }

        /// You have to look at the answer before moving on — that's the whole point of the drill.
        ///
        /// Gated on *having revealed* rather than on *currently showing English*, so flipping back
        /// to check the Hebrew again doesn't take the card away from you.
        var canAdvance: Bool { hasRevealedCurrentCard }
    }

    enum Action {
        case cardTapped
        case nextButtonTapped
        case shuffleButtonTapped
    }

    @Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .cardTapped:
                state.isShowingEnglish.toggle()
                if state.isShowingEnglish { state.hasRevealedCurrentCard = true }
                return .none

            case .nextButtonTapped:
                // Enforced here as well as in the view, so the rule holds regardless of how the
                // action arrives.
                guard state.canAdvance, !state.cards.isEmpty else { return .none }
                // Wraps rather than ending the deck; a completion screen was an optional item.
                state.index = (state.index + 1) % state.cards.count
                state.hasRevealedCurrentCard = false
                state.isShowingEnglish = false
                return .none

            case .shuffleButtonTapped:
                // Copied out first so the closure doesn't capture the `inout` state.
                let cards = state.cards
                state.cards = withRandomNumberGenerator { generator in
                    cards.shuffled(using: &generator)
                }
                state.index = 0
                state.hasRevealedCurrentCard = false
                state.isShowingEnglish = false
                return .none
            }
        }
    }
}
