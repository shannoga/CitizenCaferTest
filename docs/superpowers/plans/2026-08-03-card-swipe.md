# Card Swipe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a horizontal drag gesture to the study card that flips an unrevealed card and throws a revealed one to the next card, with a matching slide transition shared by the Next button.

**Architecture:** A new `SwipeableCard` view wraps the existing `FlipCard` and owns horizontal position plus the drag gesture; `FlipCard` is not modified. The card is identified by `store.index` inside a `ZStack`, so changing the index — from either the swipe or the Next button — drives one asymmetric move transition. Both rules stay in the reducer: a new `.cardSwiped` action funnels into the same private `advance` helper as `.nextButtonTapped`, inheriting the reveal gate and the last-card finish rather than copying either.

**Tech Stack:** SwiftUI, iOS 17+, TCA (Point-Free Composable Architecture) 1.26.1, XCTest.

**Spec:** [docs/superpowers/specs/2026-08-03-card-swipe-design.md](../specs/2026-08-03-card-swipe-design.md)

## Global Constraints

- Deployment target is **iOS 17.0**. `Animation.snappy` and `.spring(response:dampingFraction:)` are available; `@Previewable` (Xcode 16 macro) is **not** to be used — previews use a nested `Harness` struct instead.
- The project uses **Xcode 16 synchronized folder groups** (`PBXFileSystemSynchronizedRootGroup`). New `.swift` files under `CitizenCaferTest/` join the target automatically. **Do not edit `project.pbxproj`.**
- The reveal gate is enforced **in the reducer**, not only in the view: `guard state.canAdvance, !state.cards.isEmpty`.
- `Views/FlipCard.swift` must not be modified. It keeps its `isFlipped: Bool` interface.
- **The deck does not wrap.** The last card finishes it via `.send(.delegate(.deckFinished))` with no state mutation at all. Preserve `StudyFeature.Action.Delegate` and its explanatory comment exactly as they stand — this plan only adds a case alongside them.
- The working tree carries an in-progress completion-screen feature (`CompletionFeature`, `CompletionView`, `ConfettiBurst`, `AppFeatureTests`). Do not revert, restructure, or commit those files; commit only the paths named in each task's `git add`.
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
    /// The swipe inherits the whole rule set rather than a copy of it: the reveal gate, and the
    /// last card finishing the deck instead of wrapping.
    func testSwipeObeysTheSameRulesAsNext() async {
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
        XCTAssertTrue(store.state.isOnLastCard)

        await store.send(.cardTapped) {
            $0.isShowingEnglish = true
            $0.hasRevealedCurrentCard = true
        }

        // Throwing the last card finishes rather than wraps — no mutation, just the delegate.
        await store.send(.cardSwiped)
        await store.receive(\.delegate.deckFinished)

        XCTAssertEqual(store.state.index, 1)
        XCTAssertTrue(store.state.hasRevealedCurrentCard)
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

Three surgical edits to `CitizenCaferTest/Features/StudyFeature.swift`. **Do not** rewrite the `Action` enum wholesale — the `Delegate` case and its long explanatory comment must survive untouched, as must the `case .delegate: return .none` branch.

**3a.** Add one case at the top of `enum Action`, keeping the existing alphabetical order:

```swift
    enum Action {
        case cardSwiped
        case cardTapped
```

**3b.** Replace the whole `case .nextButtonTapped:` branch — its comments, both guards, `state.index += 1`, both resets, and its `return .none` — with this pair of lines:

```swift
            case .cardSwiped, .nextButtonTapped:
                return advance(&state)
```

**3c.** Add the helper immediately after the closing brace of `var body`, before the struct's closing brace. Its body is exactly the code deleted in 3b, moved rather than rewritten:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CitizenCaferTestTests 2>&1 | tail -25
```

Expected: **PASS**, and critically all four pre-existing `StudyFeatureTests` methods must still pass unchanged — `testNextIsBlockedUntilTheCardIsRevealed`, `testTheLastCardFinishesTheDeckInsteadOfWrapping`, `testAnUnrevealedLastCardStillGoesNowhere`, `testShuffleResetsToAnUnrevealedFirstCard`. Extracting `advance` is a pure refactor; if any of those four change behaviour, the extraction was not verbatim.

- [ ] **Step 5: Commit**

```bash
git add CitizenCaferTest/Features/StudyFeature.swift CitizenCaferTestTests/StudyFeatureTests.swift
git commit -m "Add cardSwiped action sharing the Next button's rules"
```

Only those two paths — the working tree's completion-screen files are not part of this commit.

---

### Task 2: `SwipeableCard` — the gesture and its two modes

**Files:**
- Create: `CitizenCaferTest/Views/SwipeableCard.swift`

**Interfaces:**
- Consumes: nothing at compile time — the view is generic over its content and takes plain closures.
- Produces: `SwipeableCard(canAdvance:advanceRemovesCard:onAdvance:onFlip:content:)`, where `canAdvance: Bool`, `advanceRemovesCard: Bool`, `onAdvance: () -> Void`, `onFlip: () -> Void`, and `content` is a `@ViewBuilder`. Task 3 consumes exactly this signature and passes `advanceRemovesCard: !store.isOnLastCard`.

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
    /// False on the last card, where advancing finishes the deck instead of replacing the card —
    /// so there is no removal transition coming to carry the offset away, and the throw has to
    /// tidy up after itself.
    let advanceRemovesCard: Bool
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
                    let thrown = value.translation.width < -throwDistance
                        || value.predictedEndTranslation.width < -flickDistance

                    if thrown { onAdvance() }

                    // A thrown card that's about to be removed keeps its offset on purpose: the
                    // parent's removal transition carries it the rest of the way, and animating
                    // home would fight that. On the last card nothing is removed, so the same
                    // throw has to put the card back itself or it would sit stranded off-centre.
                    if !thrown || !advanceRemovesCard {
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
        @State private var isLastCard = false
        @State private var advances = 0

        var body: some View {
            VStack(spacing: 24) {
                SwipeableCard(canAdvance: canAdvance, advanceRemovesCard: !isLastCard) {
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

                // There is no parent here to remove the card on a throw, so with this off a
                // successful throw correctly leaves it lying where it landed.
                Toggle("Last card (throw springs home)", isOn: $isLastCard)

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
2. Green card, drag right — it moves at most 40pt and springs back without incrementing.
3. Green card, **"Last card" on**, drag left past ~88pt — the counter increments *and* the card springs back to centre. This is the branch the real last card depends on.
4. Green card, **"Last card" off**, drag left past ~88pt — the counter increments and the card stays where it landed. Correct here: in the real app the parent removes it at this moment, and the removal transition takes over.

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
- Consumes: `SwipeableCard(canAdvance:advanceRemovesCard:onAdvance:onFlip:content:)` from Task 2; `StudyFeature.Action.cardSwiped` from Task 1; the pre-existing `StudyFeature.State.isOnLastCard`.
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
                        // The last card finishes the deck rather than being replaced, so there's no
                        // removal transition coming and the throw has to put the card back itself.
                        advanceRemovesCard: !store.isOnLastCard,
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
5. Reach card 10 of 10 (the button reads **Finish**), reveal it, and throw it left — the completion screen appears **and** the card springs back to centre. Pop back from the completion screen and confirm the card is centred, not stranded off to the left.

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
