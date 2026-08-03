import ComposableArchitecture
import Foundation

/// All destinations reachable from the browse screen.
@Reducer
enum AppPath {
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

            case .browse, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
