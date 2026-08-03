import ComposableArchitecture
import XCTest

@testable import CitizenCaferTest

@MainActor
final class BrowseFeatureTests: XCTestCase {

    func testChangingTierResetsInvalidLevelAndTypeSelection() async {
        let store = TestStore(initialState: BrowseFeature.State()) {
            BrowseFeature()
        } withDependencies: {
            $0[VocabularyClient.self].load = {
                VocabularyLoad(sets: Fixtures.sets, source: .remote)
            }
        }

        await store.send(.task)
        await store.receive(\.vocabularyResponse.success) {
            $0.loadState = .loaded(Fixtures.sets, .remote)
            // The first tier is preselected so the level picker is immediately meaningful.
            $0.selectedTier = "Freedom"
        }

        // Drill into a Freedom pack that only exists under Freedom.
        await store.send(.levelSelected("Dark Green")) {
            $0.selectedLevel = "Dark Green"
        }
        await store.send(.typeSelected(2)) {
            $0.selectedType = 2
        }
        XCTAssertTrue(store.state.requiresTypeSelection)
        XCTAssertTrue(store.state.canStartStudying)

        // Switching tier invalidates both: "Dark Green" and pack 2 don't exist under Foundation.
        await store.send(.tierSelected("Foundation")) {
            $0.selectedTier = "Foundation"
            $0.selectedLevel = nil
            $0.selectedType = nil
        }
        XCTAssertFalse(store.state.canStartStudying)

        // A single-pack level needs no type and is studyable as soon as the level is chosen.
        await store.send(.levelSelected("Red")) {
            $0.selectedLevel = "Red"
        }
        XCTAssertFalse(store.state.requiresTypeSelection)
        XCTAssertTrue(store.state.canStartStudying)
        XCTAssertEqual(store.state.selectedSet?.pairs.first?.english, "Hello / Peace")
    }

    func testLoadFailureSurfacesErrorAndRetrySucceeds() async {
        let shouldFail = LockIsolated(true)

        let store = TestStore(initialState: BrowseFeature.State()) {
            BrowseFeature()
        } withDependencies: {
            $0[VocabularyClient.self].load = {
                if shouldFail.value { throw VocabularyError.http(500) }
                return VocabularyLoad(sets: Fixtures.sets, source: .remote)
            }
        }

        await store.send(.task)
        await store.receive(\.vocabularyResponse.failure) {
            $0.loadState = .failed(VocabularyError.http(500).localizedDescription)
        }
        XCTAssertFalse(store.state.canStartStudying)

        shouldFail.setValue(false)

        await store.send(.retryButtonTapped) {
            $0.loadState = .loading
        }
        await store.receive(\.vocabularyResponse.success) {
            $0.loadState = .loaded(Fixtures.sets, .remote)
            $0.selectedTier = "Freedom"
        }
    }

    func testSetAfterAdvancesWithinALevelAndStopsAtTheLastPack() {
        var state = BrowseFeature.State()
        state.loadState = .loaded(Fixtures.sets, .remote)

        let packOne = Fixtures.sets[0]     // Freedom · Dark Green · Pack 1
        let packTwo = Fixtures.sets[1]     // Freedom · Dark Green · Pack 2
        let singlePack = Fixtures.sets[2]  // Foundation · Red, no packs

        XCTAssertEqual(state.set(after: packOne), packTwo)
        // Also proves it never crosses into another tier: Foundation · Red is the very next
        // element of the array, and it is not the answer.
        XCTAssertNil(state.set(after: packTwo), "The last pack in a level has no successor.")
        XCTAssertNil(
            state.set(after: singlePack),
            "A single-pack level is finished when it's finished."
        )
    }
}
