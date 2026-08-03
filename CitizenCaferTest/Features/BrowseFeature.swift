import ComposableArchitecture
import Foundation

@Reducer
struct BrowseFeature {
    @ObservableState
    struct State: Equatable {
        var loadState: LoadState = .loading
        var selectedLevel: String?
        var selectedTier: String?
        var selectedType: Int?

        enum LoadState: Equatable {
            case failed(String)
            case loaded([VocabSet], VocabularySource)
            case loading
        }

        // Everything below is derived from `loadState` rather than stored, so the selection and the
        // data can never disagree.

        var sets: [VocabSet] {
            guard case .loaded(let sets, _) = loadState else { return [] }
            return sets
        }

        var source: VocabularySource? {
            guard case .loaded(_, let source) = loadState else { return nil }
            return source
        }

        /// First-appearance order, which is the progression order the API already returns.
        var tiers: [String] { sets.map(\.tier).uniqued() }

        var levels: [String] {
            guard let selectedTier else { return [] }
            return sets.filter { $0.tier == selectedTier }.map(\.level).uniqued()
        }

        /// Empty for levels with a single content pack, which therefore show no type picker.
        var types: [Int] {
            guard let selectedTier, let selectedLevel else { return [] }
            return sets
                .filter { $0.tier == selectedTier && $0.level == selectedLevel }
                .compactMap(\.type)
                .sorted()
        }

        /// Gated on the level *having* packs at all, not on having more than one. A level that
        /// shipped a single numbered pack would otherwise hide the picker, leave `selectedType`
        /// at `nil`, and never match a set whose `type` is `1` — an unstudyable level with nothing
        /// on screen to explain why. The current data never produces that shape; the rule costs
        /// nothing and stops it mattering if it ever does.
        var requiresTypeSelection: Bool { !types.isEmpty }

        /// Resolves to a pack for both shapes: multi-pack levels match on `type`, single-pack levels
        /// match `nil` against `nil`.
        var selectedSet: VocabSet? {
            sets.first {
                $0.tier == selectedTier && $0.level == selectedLevel && $0.type == selectedType
            }
        }

        var canStartStudying: Bool { selectedSet != nil }

        /// The pack that follows `set` inside the same tier and level.
        ///
        /// `nil` at the end of a level, and `nil` for a single-pack level: carrying on into the
        /// *next level* is a progression decision, not a "next pack" one.
        ///
        /// Sorted rather than left in first-appearance order so it agrees with the order the Pack
        /// menu showed the reader — see `types` above.
        func set(after set: VocabSet) -> VocabSet? {
            let packs = sets
                .filter { $0.tier == set.tier && $0.level == set.level }
                .sorted { ($0.type ?? .min) < ($1.type ?? .min) }
            guard let index = packs.firstIndex(where: { $0.id == set.id }),
                  packs.indices.contains(index + 1)
            else { return nil }
            return packs[index + 1]
        }
    }

    enum Action {
        case levelSelected(String)
        case retryButtonTapped
        case startStudyingButtonTapped
        case task
        case tierSelected(String)
        case typeSelected(Int)
        case vocabularyResponse(Result<VocabularyLoad, VocabularyError>)
    }

    @Dependency(VocabularyClient.self) var vocabulary

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .levelSelected(let level):
                // A type only means something within a level, so it cannot survive the change.
                state.selectedLevel = level
                state.selectedType = nil
                return .none

            case .retryButtonTapped, .task:
                state.loadState = .loading
                return .run { send in
                    await send(.vocabularyResponse(Result { try await vocabulary.load() }
                        .mapError { $0 as? VocabularyError ?? .unknown("\($0)") }))
                }

            case .startStudyingButtonTapped:
                // Handled by the parent, which owns navigation.
                return .none

            case .tierSelected(let tier):
                // Both the level and the type belonged to the old tier, so both are now invalid.
                state.selectedTier = tier
                state.selectedLevel = nil
                state.selectedType = nil
                return .none

            case .typeSelected(let type):
                state.selectedType = type
                return .none

            case .vocabularyResponse(.failure(let error)):
                state.loadState = .failed(error.localizedDescription)
                return .none

            case .vocabularyResponse(.success(let load)):
                state.loadState = .loaded(load.sets, load.source)
                // Preselect the first tier so the level picker is immediately meaningful.
                state.selectedTier = load.sets.first?.tier
                state.selectedLevel = nil
                state.selectedType = nil
                return .none
            }
        }
    }
}
