import ComposableArchitecture
import Foundation

@Reducer
struct StudyFeature {
    @ObservableState
    struct State: Equatable {
        var cards: [WordPair]
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
                return .none

            case .nextButtonTapped:
                guard !state.cards.isEmpty else { return .none }
                // Wraps rather than ending the deck; a completion screen was an optional item.
                state.index = (state.index + 1) % state.cards.count
                state.isShowingEnglish = false
                return .none

            case .shuffleButtonTapped:
                state.cards = withRandomNumberGenerator { generator in
                    state.cards.shuffled(using: &generator)
                }
                state.index = 0
                state.isShowingEnglish = false
                return .none
            }
        }
    }
}
