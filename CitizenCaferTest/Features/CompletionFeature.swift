import ComposableArchitecture
import Foundation

/// The screen shown after the last card of a pack.
///
/// It holds an answer, not a question: the pack that was finished and the pack that follows it,
/// both resolved by `AppFeature` at push time. Nothing here goes looking through the catalogue —
/// this screen has no business knowing what a `sets` array is.
@Reducer
struct CompletionFeature {
    @ObservableState
    struct State: Equatable {
        /// `nil` at the end of a level, which is what hides the "Next pack" button.
        var nextSet: VocabSet?
        var set: VocabSet

        init(set: VocabSet, nextSet: VocabSet?) {
            self.set = set
            self.nextSet = nextSet
        }

        // `self.` throughout: a bare leading `set` inside a computed property is parsed as an
        // accessor introducer rather than as this property.

        var cardCount: Int { self.set.pairs.count }

        /// The tier leads, because the tier is the thing worth being told you're inside of.
        var tierLine: String { "\(self.set.tier) Level" }

        /// Matches `StudyFeature.State.title` exactly, so the screen you land on names the pack
        /// the same way the screen you came from did.
        var packLine: String {
            self.set.type.map { "\(self.set.level) · Pack \($0)" } ?? self.set.level
        }

        var metaLine: String { "\(cardCount) \(cardCount == 1 ? "card" : "cards") studied" }

        /// Spoken as one sentence. Read line by line, VoiceOver stops four times and pronounces
        /// "·" as punctuation; this says the same thing the way a person would.
        var accessibilityHeadline: String {
            let pack = self.set.type.map { "\(self.set.level), pack \($0)" } ?? self.set.level
            return "You just completed \(self.set.tier) Level, \(pack). \(metaLine)."
        }
    }

    enum Action {
        case backToBrowseButtonTapped
        case nextPackButtonTapped
        case studyAgainButtonTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            // All three are unconditional navigation intents with no precondition this screen
            // owns, so the parent handles them — the same arrangement as
            // `BrowseFeature.startStudyingButtonTapped`. (Contrast `StudyFeature.Delegate`, which
            // exists precisely because only the child can decide when a deck is finished.)
            case .backToBrowseButtonTapped, .nextPackButtonTapped, .studyAgainButtonTapped:
                return .none
            }
        }
    }
}
