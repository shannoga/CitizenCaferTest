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
        /// Kept whole rather than shredded into `level` and `title`: the parent needs the pack
        /// itself to build the completion screen and to find the one after it, and one stored
        /// value can't disagree with its own derivations.
        var set: VocabSet

        init(set: VocabSet) {
            self.cards = set.pairs
            self.set = set
        }

        // `self.` is load-bearing: a bare leading `set` inside a computed property is parsed as an
        // accessor introducer, not as this property.
        var level: String { self.set.level }

        var title: String {
            self.set.type.map { "\(self.set.level) · Pack \($0)" } ?? self.set.level
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

        /// The last card doesn't advance, it finishes — which is also why the button stops saying
        /// "Next" once you reach it.
        var isOnLastCard: Bool { !cards.isEmpty && index == cards.count - 1 }

        /// Hands the deck back at its first card, unrevealed. The order stays as the reader left
        /// it; re-shuffling would be a second decision nobody asked for.
        mutating func restart() {
            index = 0
            hasRevealedCurrentCard = false
            isShowingEnglish = false
        }
    }

    enum Action {
        case cardSwiped
        case cardTapped
        case delegate(Delegate)
        case nextButtonTapped
        case shuffleButtonTapped

        /// A fact this screen knows and the parent has to act on. `AppFeature` owns navigation;
        /// the study screen owns the rule for when a deck is done. Neither reaches into the other.
        ///
        /// Sibling actions stay on the plain "no-op handled by the parent" pattern
        /// (`BrowseFeature.startStudyingButtonTapped`) because they are unconditional intents. This
        /// one can't: on the last card the correct behaviour is *no mutation at all*, which from
        /// the outside is indistinguishable from Next tapped on an unrevealed card. Telling those
        /// apart in the parent would mean a second copy of `canAdvance`.
        @CasePathable
        enum Delegate: Equatable {
            case deckFinished
        }
    }

    @Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .cardTapped:
                state.isShowingEnglish.toggle()
                if state.isShowingEnglish { state.hasRevealedCurrentCard = true }
                return .none

            case .delegate:
                return .none

            case .cardSwiped, .nextButtonTapped:
                return advance(&state)

            case .shuffleButtonTapped:
                // Copied out first so the closure doesn't capture the `inout` state.
                let cards = state.cards
                state.cards = withRandomNumberGenerator { generator in
                    cards.shuffled(using: &generator)
                }
                state.restart()
                return .none
            }
        }
    }

    /// Shared by the Next button and the leftward swipe, so the gesture can't drift out of step
    /// with the rules. Both gates live here rather than in the view, and the reveal rule outranks
    /// the finish rule — hence the order.
    ///
    /// The deck doesn't wrap. On the last card nothing mutates: it's handed up exactly as the
    /// reader left it, so popping back from the completion screen lands on the card they finished
    /// on rather than somewhere they've never been.
    private func advance(_ state: inout State) -> Effect<Action> {
        guard state.canAdvance, !state.cards.isEmpty else { return .none }
        guard !state.isOnLastCard else { return .send(.delegate(.deckFinished)) }
        state.index += 1
        state.hasRevealedCurrentCard = false
        state.isShowingEnglish = false
        return .none
    }
}
