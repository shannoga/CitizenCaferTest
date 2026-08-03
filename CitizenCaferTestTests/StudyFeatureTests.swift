import ComposableArchitecture
import XCTest

@testable import CitizenCaferTest

@MainActor
final class StudyFeatureTests: XCTestCase {

    private var deck: VocabSet {
        VocabSet(
            tier: "Foundation",
            level: "Red",
            type: nil,
            pairs: [
                WordPair(hebrew: "שָׁלוֹם", english: "Hello / Peace"),
                WordPair(hebrew: "תּוֹדָה", english: "Thank you"),
            ]
        )
    }

    func testNextIsBlockedUntilTheCardIsRevealed() async {
        let store = TestStore(initialState: StudyFeature.State(set: deck)) {
            StudyFeature()
        }

        XCTAssertFalse(store.state.canAdvance)

        // Tapping Next before revealing must change nothing at all — same card, same face.
        await store.send(.nextButtonTapped)
        XCTAssertEqual(store.state.index, 0)

        await store.send(.cardTapped) {
            $0.isShowingEnglish = true
            $0.hasRevealedCurrentCard = true
        }
        XCTAssertTrue(store.state.canAdvance)

        // Flipping back to check the Hebrew again must not take the card away.
        await store.send(.cardTapped) {
            $0.isShowingEnglish = false
        }
        XCTAssertTrue(store.state.canAdvance)

        await store.send(.nextButtonTapped) {
            $0.index = 1
            $0.hasRevealedCurrentCard = false
        }
        XCTAssertFalse(store.state.canAdvance, "The new card has to be revealed on its own.")
        XCTAssertEqual(store.state.currentCard?.hebrew, "תּוֹדָה")
    }

    func testShuffleResetsToAnUnrevealedFirstCard() async {
        let store = TestStore(initialState: StudyFeature.State(set: deck)) {
            StudyFeature()
        } withDependencies: {
            // Reverses a two-card deck, so the assertion is about the reset, not the ordering.
            $0.withRandomNumberGenerator = WithRandomNumberGenerator(LCRNG(seed: 0))
        }

        await store.send(.cardTapped) {
            $0.isShowingEnglish = true
            $0.hasRevealedCurrentCard = true
        }
        await store.send(.nextButtonTapped) {
            $0.index = 1
            $0.hasRevealedCurrentCard = false
            $0.isShowingEnglish = false
        }
        await store.send(.cardTapped) {
            $0.isShowingEnglish = true
            $0.hasRevealedCurrentCard = true
        }

        await store.send(.shuffleButtonTapped) {
            var rng = LCRNG(seed: 0)
            $0.cards = $0.cards.shuffled(using: &rng)
            $0.index = 0
            $0.hasRevealedCurrentCard = false
            $0.isShowingEnglish = false
        }
        XCTAssertFalse(store.state.canAdvance, "A shuffled deck starts unrevealed.")
    }
}

/// A deterministic generator so shuffling is reproducible in tests.
private struct LCRNG: RandomNumberGenerator {
    var seed: UInt64

    init(seed: UInt64) { self.seed = seed }

    mutating func next() -> UInt64 {
        seed = 2862933555777941757 &* seed &+ 3037000493
        return seed
    }
}
