# Card Swipe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a horizontal drag gesture to the study card that flips an unrevealed card and throws a revealed one to the next card, with a matching slide transition shared by the Next button.

**Architecture:** A new `SwipeableCard` view wraps the existing `FlipCard` and owns horizontal position plus the drag gesture; `FlipCard` is not modified. The card is identified by `store.index` inside a `ZStack`, so changing the index — from either the swipe or the Next button — drives one asymmetric move transition. The reveal gate stays in the reducer: a new `.cardSwiped` action funnels into the same private `advance` helper as `.nextButtonTapped`.

**Tech Stack:** SwiftUI, iOS 17+, TCA (Point-Free Composable Architecture) 1.26.1, XCTest.

**Spec:** [docs/superpowers/specs/2026-08-03-card-swipe-design.md](../specs/2026-08-03-card-swipe-design.md)

## Global Constraints

- Deployment target is **iOS 17.0**. `Animation.snappy` and `.spring(response:dampingFraction:)` are available; `@Previewable` (Xcode 16 macro) is **not** to be used — previews use a nested `Harness` struct instead.
- The project uses **Xcode 16 synchronized folder groups** (`PBXFileSystemSynchronizedRootGroup`). New `.swift` files under `CitizenCaferTest/` join the target automatically. **Do not edit `project.pbxproj`.**
- The reveal gate is enforced **in the reducer**, not only in the view: `guard state.canAdvance, !state.cards.isEmpty`.
- `Views/FlipCard.swift` must not be modified. It keeps its `isFlipped: Bool` interface.
- Advancing wraps: `state.index = (state.index + 1) % state.cards.count`.
- Comments explain *why*, not *what* — match the density and voice of the surrounding files.
- All commands run from the repo root, `/Users/shani/CitizenCaferTest`.

**Build:**
```bash
xcodebuild build -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```

**Unit tests:**
```bash
xcodebuild test -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CitizenCaferTestTests 2>&1 | tail -25
```

---

## File Structure

| File | Responsibility | Change |
| --- | --- | --- |
| `CitizenCaferTest/Features/StudyFeature.swift` | Deck state and the reveal gate | Modify — add `.cardSwiped`, extract `advance` |
| `CitizenCaferTest/Views/SwipeableCard.swift` | Horizontal position + drag gesture | **Create** |
| `CitizenCaferTest/Views/StudyView.swift` | Composes the card, controls, toolbar | Modify — wrap card, add `.id`/transition |
| `CitizenCaferTest/Views/FlipCard.swift` | Y-axis rotation | **Untouched** |
| `CitizenCaferTestTests/StudyFeatureTests.swift` | Reducer tests | Modify — add swipe-gate test |
| `CitizenCaferTestUITests/FlipWalkthroughUITests.swift` | End-to-end walkthrough | Modify — add swipe walkthrough |

---

### Task 1: Reducer — `.cardSwiped` shares the Next button's gate

**Files:**
- Modify: `CitizenCaferTest/Features/StudyFeature.swift:34-72`
- Test: `CitizenCaferTestTests/StudyFeatureTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `StudyFeature.Action.cardSwiped` — sent by `SwipeableCard`'s `onAdvance` closure in Task 3. Existing `StudyFeature.Action.cardTapped` is reused unchanged for flip-by-drag.

- [ ] **Step 1: Write the failing test**

Append this method to `StudyFeatureTests`, after `testNextIsBlockedUntilTheCardIsRevealed`:

```swift
    func testSwipeObeysTheSameRevealGateAsNext() async {
        let store = TestStore(initialState: StudyFeature.State(set: deck)) {
            StudyFeature()
        }

        // A swipe on an unrevealed card has to be as inert as tapping Next.
        await store.send(.cardSwiped)
        XCTAssertEqual(store.state.index, 0)

        await store.send(.cardTapped) {
            $0.isShowingEnglish = true
            $0.hasRevealedCurrentCard = true
        }

        await store.send(.cardSwiped) {
            $0.index = 1
            $0.hasRevealedCurrentCard = false
            $0.isShowingEnglish = false
        }
        XCTAssertFalse(store.state.canAdvance, "The new card has to be revealed on its own.")
        XCTAssertEqual(store.state.currentCard?.hebrew, "תּוֹדָה")

        // Swiping off the last card wraps, exactly as Next does.
        await store.send(.cardTapped) {
            $0.isShowingEnglish = true
            $0.hasRevealedCurrentCard = true
        }
        await store.send(.cardSwiped) {
            $0.index = 0
            $0.hasRevealedCurrentCard = false
            $0.isShowingEnglish = false
        }
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CitizenCaferTestTests/StudyFeatureTests 2>&1 | tail -25
```

Expected: **compile failure** — `type 'StudyFeature.Action' has no member 'cardSwiped'`.

- [ ] **Step 3: Add the action and extract the shared helper**

In `CitizenCaferTest/Features/StudyFeature.swift`, replace the `Action` enum and the `body` property with:

```swift
    enum Action {
        case cardSwiped
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

            case .cardSwiped, .nextButtonTapped:
                return advance(&state)

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

    /// Shared by the Next button and the leftward swipe. The gate lives here rather than in the
    /// view, so the rule holds regardless of which gesture the intent arrived through.
    private func advance(_ state: inout State) -> Effect<Action> {
        guard state.canAdvance, !state.cards.isEmpty else { return .none }
        // Wraps rather than ending the deck; a completion screen was an optional item.
        state.index = (state.index + 1) % state.cards.count
        state.hasRevealedCurrentCard = false
        state.isShowingEnglish = false
        return .none
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CitizenCaferTestTests 2>&1 | tail -25
```

Expected: **PASS**, including the pre-existing `testNextIsBlockedUntilTheCardIsRevealed` and `testShuffleResetsToAnUnrevealedFirstCard` — the extracted `advance` must not have changed their behaviour.

- [ ] **Step 5: Commit**

```bash
git add CitizenCaferTest/Features/StudyFeature.swift CitizenCaferTestTests/StudyFeatureTests.swift
git commit -m "Add cardSwiped action sharing the Next button's reveal gate"
```

---

### Task 2: `SwipeableCard` — the gesture and its two modes

**Files:**
- Create: `CitizenCaferTest/Views/SwipeableCard.swift`

**Interfaces:**
- Consumes: nothing at compile time — the view is generic over its content and takes plain closures.
- Produces: `SwipeableCard(canAdvance:onAdvance:onFlip:content:)`, where `canAdvance: Bool`, `onAdvance: () -> Void`, `onFlip: () -> Void`, and `content` is a `@ViewBuilder`. Task 3 consumes exactly this signature.

There is no unit test for this task: SwiftUI gesture state is not reachable from XCTest. It is verified by the build plus the interactive `#Preview` harness here, and end-to-end by the UI test in Task 4.

- [ ] **Step 1: Create the file**

Create `CitizenCaferTest/Views/SwipeableCard.swift`:

```swift
import SwiftUI

/// Horizontal drag on the study card, layered outside `FlipCard`.
///
/// The gesture means two different things depending on whether the card has been revealed, so it
/// commits to one of them on its first movement — otherwise a flip landing mid-drag would silently
/// turn the same continuous drag into a swipe. Before the reveal the card is resisted and can only
/// flip; after it, a leftward throw advances.
///
/// The offset deliberately lives here rather than in the parent. When the parent swaps the card's
/// `id`, this instance is retained until its removal transition finishes and keeps its own state,
/// so the throw continues from where the finger let go instead of snapping back to centre first.
struct SwipeableCard<Content: View>: View {
    let canAdvance: Bool
    let onAdvance: () -> Void
    let onFlip: () -> Void
    @ViewBuilder var content: Content

    @State private var mode: DragMode?
    @State private var offset: CGFloat = 0

    private enum DragMode { case advance, flip }

    /// Past this much leftward travel — or this much projected travel on a flick — the card leaves.
    private let throwDistance: CGFloat = 88
    private let flickDistance: CGFloat = 200
    /// A shorter reach for the flip, which is a smaller commitment than losing the card.
    private let flipDistance: CGFloat = 60
    /// A locked or wrong-way card follows the finger at a quarter speed, and no further than this.
    private let resistance: CGFloat = 0.25
    private let resistanceLimit: CGFloat = 40

    var body: some View {
        content
            .offset(x: offset)
            .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                let mode = self.mode ?? (canAdvance ? .advance : .flip)
                self.mode = mode

                switch mode {
                case .advance:
                    // Left tracks the finger exactly; right is refused, because right doesn't advance.
                    offset = value.translation.width < 0
                        ? value.translation.width
                        : resisted(value.translation.width)
                case .flip:
                    offset = resisted(value.translation.width)
                }
            }
            .onEnded { value in
                // Explicitly `self.mode`, because the `guard let` below shadows the name.
                defer { self.mode = nil }
                guard let mode else { return }

                switch mode {
                case .advance:
                    if value.translation.width < -throwDistance
                        || value.predictedEndTranslation.width < -flickDistance {
                        // Left where it is on purpose: the parent's removal transition carries the
                        // card the rest of the way, and animating home would fight it.
                        onAdvance()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                    }
                case .flip:
                    if abs(value.translation.width) > flipDistance { onFlip() }
                    // Snapped home fast, so the slide back doesn't compete with the rotation.
                    withAnimation(.easeOut(duration: 0.15)) { offset = 0 }
                }
            }
    }

    private func resisted(_ translation: CGFloat) -> CGFloat {
        min(max(translation * resistance, -resistanceLimit), resistanceLimit)
    }
}

#Preview {
    struct Harness: View {
        @State private var canAdvance = false
        @State private var advances = 0

        var body: some View {
            VStack(spacing: 24) {
                SwipeableCard(canAdvance: canAdvance) {
                    advances += 1
                    canAdvance = false
                } onFlip: {
                    canAdvance = true
                } content: {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(canAdvance ? Color.green.opacity(0.25) : Color.gray.opacity(0.25))
                        .frame(height: 280)
                        .overlay(Text(canAdvance ? "Throw me left" : "Drag to flip"))
                }

                Text("Advanced \(advances) times")
            }
            .padding()
        }
    }

    return Harness()
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. Do **not** add the file to `project.pbxproj` — synchronized folder groups pick it up.

- [ ] **Step 3: Verify the two modes in the preview**

Open `CitizenCaferTest/Views/SwipeableCard.swift` in Xcode and resume the canvas. Confirm by hand:

1. Grey card, drag either way — it moves a little (max 40pt), springs back, and the label flips to "Throw me left" once you release past ~60pt.
2. Green card, drag left — it tracks the finger exactly, and releasing past ~88pt increments the counter.
3. Green card, drag right — it moves at most 40pt and springs back without incrementing.

- [ ] **Step 4: Commit**

```bash
git add CitizenCaferTest/Views/SwipeableCard.swift
git commit -m "Add SwipeableCard: resisted drag flips, leftward throw advances"
```

---

### Task 3: Wire the card into `StudyView` with the shared transition

**Files:**
- Modify: `CitizenCaferTest/Views/StudyView.swift:7-11` (environment), `:17-40` (card), and add two computed properties.

**Interfaces:**
- Consumes: `SwipeableCard(canAdvance:onAdvance:onFlip:content:)` from Task 2; `StudyFeature.Action.cardSwiped` from Task 1.
- Produces: nothing consumed by later tasks — Task 4 drives this through the UI only.

- [ ] **Step 1: Add the Reduce Motion environment property**

In `StudyView`, immediately after the existing `@Environment(\.dynamicTypeSize)` line, add:

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- [ ] **Step 2: Add the two motion properties**

These come first so the body in Step 3 has them to refer to. Add to `StudyView`, immediately before the existing `private func cardFace`:

```swift
    /// Broken out rather than written inline so the ternary has an explicit type to resolve the
    /// leading-dot cases against.
    private var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }

    private var cardAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy
    }
```

- [ ] **Step 3: Replace the card branch of the body**

Replace the whole `if let card = store.currentCard { … }` block — currently lines 17–36, from `if let card = store.currentCard {` through the `} else {` that follows `.accessibilityAddTraits(.isButton)` — with:

```swift
            if let card = store.currentCard {
                // A ZStack so the outgoing and incoming cards overlap during the transition instead
                // of stacking the VStack to twice the height.
                ZStack {
                    SwipeableCard(
                        canAdvance: store.canAdvance,
                        onAdvance: { store.send(.cardSwiped) },
                        onFlip: { store.send(.cardTapped) }
                    ) {
                        FlipCard(isFlipped: store.isShowingEnglish) {
                            cardFace {
                                Text(card.hebrew)
                                    .brandType(.cardPrompt)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }
                        } back: {
                            cardFace {
                                Text(card.english)
                                    .brandType(.cardAnswer)
                                    .foregroundStyle(Brand.textMuted)
                            }
                        }
                        .onTapGesture { store.send(.cardTapped) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(store.isShowingEnglish ? card.english : card.hebrew)
                        .accessibilityHint("Double tap to reveal the \(store.isShowingEnglish ? "Hebrew" : "English").")
                        .accessibilityAddTraits(.isButton)
                    }
                    // Identity is the whole mechanism: the Next button and the swipe both do nothing
                    // but change the index, so they share one transition for free.
                    .id(store.index)
                    .transition(cardTransition)
                }
                .animation(cardAnimation, value: store.index)
            } else {
```

- [ ] **Step 4: Build and run the existing tests**

```bash
xcodebuild test -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CitizenCaferTestTests 2>&1 | tail -25
```

Expected: `** TEST SUCCEEDED **`, all pre-existing tests still passing.

- [ ] **Step 5: Verify in the simulator**

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcodebuild build -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/cc-swipe-build 2>&1 | tail -5
xcrun simctl install booted /tmp/cc-swipe-build/Build/Products/Debug-iphonesimulator/CitizenCaferTest.app
xcrun simctl launch booted com.shani.CitizenCaferTest
```

If the bundle identifier differs, read it from the build settings:
`xcodebuild -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest -showBuildSettings 2>/dev/null | grep PRODUCT_BUNDLE_IDENTIFIER`

Navigate Level → Red → Start studying, then confirm by hand:

1. Drag the unrevealed card — resisted, springs back, flips past ~60pt.
2. Drag the revealed card left — it follows the finger and throws off to the left while the next card slides in from the right.
3. Tap **Next** — the same slide plays.
4. Drag the revealed card right — resisted, springs back, index unchanged.

- [ ] **Step 6: Commit**

```bash
git add CitizenCaferTest/Views/StudyView.swift
git commit -m "Give the study card a swipe gesture and a shared slide transition"
```

---

### Task 4: UI walkthrough for the gate

**Files:**
- Modify: `CitizenCaferTestUITests/FlipWalkthroughUITests.swift`

**Interfaces:**
- Consumes: the running app from Task 3. Reuses the file's existing `private func attach(named:)` helper.
- Produces: nothing.

- [ ] **Step 1: Write the walkthrough test**

Append this method to `FlipWalkthroughUITests`, after `testStudyAPackAndFlipTheCard` and before the private `attach` helper:

```swift
    /// The same leftward drag does two different things either side of the reveal: first it flips
    /// the card, and only then does it advance the deck.
    func testSwipeFlipsBeforeTheRevealAndAdvancesAfterIt() {
        let app = XCUIApplication()
        app.launch()

        let level = app.buttons["picker.Level"]
        XCTAssertTrue(level.waitForExistence(timeout: 20), "Vocabulary should finish loading.")
        level.tap()

        app.buttons["Red"].tap()

        let start = app.buttons["Start studying"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.staticTexts["Card 1 / 10"].waitForExistence(timeout: 5), "Progress should read 1 / 10.")

        // A locked card refuses to leave, however far you drag it — it flips instead.
        swipeCardLeft(in: app)
        Thread.sleep(forTimeInterval: 1.0)
        attach(named: "1-swipe-flipped-not-advanced")
        XCTAssertTrue(app.staticTexts["Card 1 / 10"].exists, "A swipe before the reveal must not advance.")

        // The identical gesture on the revealed card now throws it away.
        swipeCardLeft(in: app)
        XCTAssertTrue(
            app.staticTexts["Card 2 / 10"].waitForExistence(timeout: 3),
            "A swipe after the reveal advances the deck."
        )
        attach(named: "2-swipe-advanced")
    }

    /// Drags across the middle of the card, well past the 88pt throw threshold on any phone.
    private func swipeCardLeft(in app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.42))
        from.press(forDuration: 0.05, thenDragTo: to)
    }
```

- [ ] **Step 2: Run the UI test**

```bash
xcodebuild test -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CitizenCaferTestUITests/FlipWalkthroughUITests 2>&1 | tail -30
```

Expected: **PASS**, both walkthrough methods.

If the first `swipeCardLeft` advances the deck instead of flipping it, the mode lock in `SwipeableCard` is resolving `canAdvance` too late — check that `mode` is set on the *first* `onChanged` and cleared only in `onEnded`.

- [ ] **Step 3: Run the whole suite**

```bash
xcodebuild test -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **` — the pre-existing 20 unit tests plus the one added in Task 1, and all UI tests.

- [ ] **Step 4: Commit**

```bash
git add CitizenCaferTestUITests/FlipWalkthroughUITests.swift
git commit -m "Add UI walkthrough proving swipe flips before the reveal and advances after"
```

---

## Out of scope (from the spec's non-goals)

Backward navigation, scrubbable flip rotation, drag-linked tilt, haptics. Shuffling while already on card 0 pops rather than slides — accepted, not a defect.
