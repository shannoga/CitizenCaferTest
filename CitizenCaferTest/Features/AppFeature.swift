import ComposableArchitecture
import Foundation

/// All destinations reachable from the browse screen.
@Reducer
enum AppPath {
    case completion(CompletionFeature)
    case study(StudyFeature)
}

extension AppPath.State: Equatable {}

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var browse = BrowseFeature.State()
        var path = StackState<AppPath.State>()
    }

    enum Action {
        case browse(BrowseFeature.Action)
        case path(StackActionOf<AppPath>)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.browse, action: \.browse) {
            BrowseFeature()
        }
        Reduce { state, action in
            switch action {
            case .browse(.startStudyingButtonTapped):
                guard let set = state.browse.selectedSet else { return .none }
                state.path.append(.study(StudyFeature.State(set: set)))
                return .none

            // The study screen reports that a deck is done; deciding what "done" leads to is this
            // reducer's job, and resolving the following pack needs the catalogue, which lives in
            // `browse`. Neither fact is available to either child on its own.
            case .path(.element(id: let id, action: .study(.delegate(.deckFinished)))):
                guard let set = state.path[id: id, case: \.study]?.set else { return .none }
                state.path.append(
                    .completion(
                        CompletionFeature.State(set: set, nextSet: state.browse.set(after: set))
                    )
                )
                return .none

            // Drop the completion screen and hand the deck underneath back at its first card, so
            // Back still lands on browse instead of on a stack that grew by one every replay.
            case .path(.element(id: let id, action: .completion(.studyAgainButtonTapped))):
                state.path.pop(from: id)
                guard let studyID = state.path.ids.last,
                      var study = state.path[id: studyID, case: \.study]
                else { return .none }
                study.restart()
                state.path[id: studyID] = .study(study)
                return .none

            // Replaces the finished deck in place rather than popping to root and pushing again:
            // one pop transition, and the stack stays exactly one screen deep.
            case .path(.element(id: let id, action: .completion(.nextPackButtonTapped))):
                guard let next = state.path[id: id, case: \.completion]?.nextSet
                else { return .none }
                state.path.pop(from: id)
                guard let studyID = state.path.ids.last else { return .none }
                state.path[id: studyID] = .study(StudyFeature.State(set: next))
                // `set(after:)` never leaves the level, so the tier and level selections are still
                // right; only the pack moved. Keeping browse in step means Back doesn't show a
                // stale "Pack 2" behind a screen that is studying pack 3.
                state.browse.selectedType = next.type
                return .none

            case .path(.element(id: _, action: .completion(.backToBrowseButtonTapped))):
                state.path.removeAll()
                return .none

            case .browse, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
