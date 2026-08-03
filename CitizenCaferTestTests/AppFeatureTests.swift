import ComposableArchitecture
import XCTest

@testable import CitizenCaferTest

/// The completion flow only exists as a conversation between three reducers — the study screen
/// reports that a deck is done, `AppFeature` decides what that leads to, and `BrowseFeature` is the
/// only one holding the catalogue needed to find the next pack. None of it is visible from a single
/// feature's own tests, so it is tested here at the root.
@MainActor
final class AppFeatureTests: XCTestCase {

    private var packOne: VocabSet { Fixtures.sets[0] }     // Freedom · Dark Green · Pack 1
    private var packTwo: VocabSet { Fixtures.sets[1] }     // Freedom · Dark Green · Pack 2
    private var singlePack: VocabSet { Fixtures.sets[2] }  // Foundation · Red, no packs

    /// Browse already loaded and drilled into a pack, so each test starts at the interesting part.
    private func store(selecting set: VocabSet) -> TestStoreOf<AppFeature> {
        var state = AppFeature.State()
        state.browse.loadState = .loaded(Fixtures.sets, .remote)
        state.browse.selectedTier = set.tier
        state.browse.selectedLevel = set.level
        state.browse.selectedType = set.type
        return TestStore(initialState: state) { AppFeature() }
    }

    /// Pushes the pack and plays it to the end, leaving the completion screen at path id 1.
    ///
    /// Every fixture deck is one card long, so finishing is one reveal and one tap.
    private func finishDeck(
        in store: TestStoreOf<AppFeature>,
        _ set: VocabSet,
        nextSet: VocabSet?
    ) async {
        // Assigned at an explicit id rather than appended: `append` draws a fresh
        // `StackElementID` from the same generator the reducer already advanced, so the expected
        // state would land one id ahead of the real one.
        await store.send(.browse(.startStudyingButtonTapped)) {
            $0.path[id: 0] = .study(StudyFeature.State(set: set))
        }
        await store.send(\.path[id: 0].study.cardTapped) {
            $0.path[id: 0]?.modify(\.study) {
                $0.isShowingEnglish = true
                $0.hasRevealedCurrentCard = true
            }
        }
        await store.send(\.path[id: 0].study.nextButtonTapped)
        await store.receive(\.path[id: 0].study.delegate.deckFinished) {
            $0.path[id: 1] = .completion(CompletionFeature.State(set: set, nextSet: nextSet))
        }
    }

    func testFinishingADeckPushesCompletionCarryingTheFollowingPack() async {
        let store = store(selecting: packOne)
        await finishDeck(in: store, packOne, nextSet: packTwo)

        XCTAssertEqual(store.state.path.count, 2)
        XCTAssertEqual(store.state.path[id: 1, case: \.completion]?.nextSet, packTwo)
        XCTAssertEqual(store.state.path[id: 1, case: \.completion]?.cardCount, 1)
    }

    func testFinishingTheLastPackInALevelOffersNoNextPack() async {
        let store = store(selecting: singlePack)
        await finishDeck(in: store, singlePack, nextSet: nil)

        XCTAssertNil(store.state.path[id: 1, case: \.completion]?.nextSet)
        XCTAssertEqual(store.state.path[id: 1, case: \.completion]?.packLine, "Red")
    }

    func testStudyAgainDropsCompletionAndRewindsTheDeckUnderneath() async {
        let store = store(selecting: packOne)
        await finishDeck(in: store, packOne, nextSet: packTwo)

        await store.send(\.path[id: 1].completion.studyAgainButtonTapped) {
            $0.path.pop(from: 1)
            $0.path[id: 0]?.modify(\.study) {
                $0.hasRevealedCurrentCard = false
                $0.isShowingEnglish = false
            }
        }

        // One screen deep, not two: replaying must not stack completion screens up behind you.
        XCTAssertEqual(store.state.path.count, 1)
        XCTAssertEqual(store.state.path[id: 0, case: \.study]?.index, 0)
        XCTAssertFalse(store.state.path[id: 0, case: \.study]?.canAdvance ?? true)
    }

    func testNextPackReplacesTheDeckInPlaceAndMovesTheBrowseSelectionWithIt() async {
        let store = store(selecting: packOne)
        await finishDeck(in: store, packOne, nextSet: packTwo)

        await store.send(\.path[id: 1].completion.nextPackButtonTapped) {
            $0.path.pop(from: 1)
            $0.path[id: 0] = .study(StudyFeature.State(set: self.packTwo))
            $0.browse.selectedType = 2
        }

        XCTAssertEqual(store.state.path.count, 1)
        XCTAssertEqual(store.state.path[id: 0, case: \.study]?.title, "Dark Green · Pack 2")
        // Back has to land on a browse screen that agrees with what was just studied.
        XCTAssertEqual(store.state.browse.selectedSet, packTwo)
    }

    func testBackToBrowseClearsTheWholeStack() async {
        let store = store(selecting: packOne)
        await finishDeck(in: store, packOne, nextSet: packTwo)

        await store.send(\.path[id: 1].completion.backToBrowseButtonTapped) {
            $0.path.removeAll()
        }
        XCTAssertTrue(store.state.path.isEmpty)
    }
}
