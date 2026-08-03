# Card Swipe — Design

Date: 2026-08-03
Builds on: [2026-08-03-flashcards-design.md](2026-08-03-flashcards-design.md)

## Goal

Give the study card a horizontal drag gesture, and give card changes a matching slide
transition. The gesture means one thing, and the reveal state decides whether it is available:

| Card state             | Horizontal drag                                            |
| ---------------------- | ---------------------------------------------------------- |
| Not yet revealed       | Resisted travel that always springs back; never advances    |
| Revealed (`canAdvance`)| Left tracks the finger and throws to the next card          |

The `canAdvance` rule from the original design is unchanged: you have to look at the answer
before moving on. The swipe is a second way to obey that rule, never a way around it.

Flipping is the tap's job alone, and a tap that flips fires a soft impact haptic.

## Non-goals

Backward navigation (the deck is one-way), scrubbable/interactive flip rotation, drag-linked
card tilt, flip-by-drag. The completion screen already exists and is not this feature's concern
beyond routing a last-card throw into it.

---

## 1. Structure

One new file, `Views/SwipeableCard.swift`, layered *outside* `FlipCard`:

- `SwipeableCard` owns horizontal position and the drag gesture.
- `FlipCard` continues to own the Y-axis rotation, unchanged.

Neither knows about the other; `StudyView` composes them. `FlipCard` keeps its `isFlipped: Bool`
interface and its existing midpoint-opacity trick — nothing in that file is touched.

```swift
struct SwipeableCard<Content: View>: View {
    let canAdvance: Bool
    /// False on the last card, where advancing finishes the deck instead of replacing the card.
    let advanceRemovesCard: Bool
    let onAdvance: () -> Void
    @ViewBuilder var content: Content
}
```

---

## 2. The transition

The card is identified by `store.index` and wrapped in a `ZStack`, so the outgoing and incoming
cards overlap instead of stacking the `VStack` to double height:

```swift
ZStack {
    SwipeableCard(
        canAdvance: store.canAdvance,
        onAdvance: { store.send(.cardSwiped) }
    ) {
        FlipCard(isFlipped: store.isShowingEnglish) { … } back: { … }
    }
    .id(store.index)
    .transition(
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    )
}
.animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: store.index)
```

`StudyView` gains one new environment property for this,
`@Environment(\.accessibilityReduceMotion) private var reduceMotion`, alongside the
`dynamicTypeSize` it already reads.

**Why the drag offset lives inside `SwipeableCard` rather than in `StudyView`.** When the index
changes, the outgoing instance is retained until its removal transition finishes, and it keeps
its own `@State`. So the offset the finger left it at composes with the `.move` transition and
the card continues from where you let go. Hoisting that offset into `StudyView` would reset it
at the moment of removal and produce a visible snap-back-then-fly.

This is also what makes the Next button and the swipe share one transition for free: both paths
do nothing but change `store.index`.

**Commit does not animate the offset home — except on the last card.** On a successful throw
`SwipeableCard` calls `onAdvance()` and leaves `offset` where it is, because the removal
transition carries the card the rest of the way and animating home would fight it.

The last card is the exception, and it is why `advanceRemovesCard` exists. There, advancing
finishes the deck rather than changing the index, so nothing is removed and no transition plays.
Left alone, the card would sit stranded off-centre — and still be stranded when the reader pops
back from the completion screen. So when `advanceRemovesCard` is false, the throw calls
`onAdvance()` *and* springs the offset home.

---

## 3. Gesture rules

There is a single behaviour, and no mode state:

```swift
@State private var offset: CGFloat = 0
```

- A **revealed card dragged left** tracks the finger 1:1. On release it commits if
  `translation.width < -88` **or** `predictedEndTranslation.width < -200` (a flick). Otherwise it
  springs home with `.spring(response: 0.3, dampingFraction: 0.8)`.
- A commit springs home too when `advanceRemovesCard` is false — see §2. Otherwise the offset is
  left alone for the removal transition.
- **Everything else** — an unrevealed card in either direction, or a rightward drag on a revealed
  one — is resisted: `translation * 0.25`, clamped to ±40pt, always springing back. Neither of
  those advances, and the locked card visibly refusing to leave is the tactile counterpart to the
  greyed-out Next button. It reads as "not yet" rather than as a dead control.

**No mode lock.** An earlier revision let a drag flip an unrevealed card, which meant `canAdvance`
could change mid-gesture and the same continuous drag could turn from a flip into a throw; a
`DragMode` locked on the first `onChanged` guarded against that. With flip-by-drag removed,
`canAdvance` changes only via a tap or the Next button, neither of which can happen mid-drag — so
the lock guarded against nothing and went with it.

**Fixed thresholds, not proportional ones.** 88pt rather than 25% of the card width, so the view
needs no `GeometryReader` or width plumbing. The card is full-bleed minus `Brand.Space.lg` on
each side, so 88pt is roughly a quarter of it on every phone this ships to.

The existing `.onTapGesture` stays, and is now the *only* way to flip; a `DragGesture` with the
default 10pt minimum distance coexists with it.

**The flip haptic.** The tap increments a view-local `@State flipTicks`, and
`.sensoryFeedback(.impact(flexibility: .soft), trigger: flipTicks)` fires on it. A counter rather
than `store.isShowingEnglish`, because `advance` and `restart()` both clear that flag — triggering
on it would buzz on Next and on Shuffle. View-local rather than reducer state, because feedback is
presentation, and a new `State` field mutated by `.cardTapped` would force an edit to all ten
exhaustive `TestStore` assertions that send it.

---

## 4. Reducer

One new case in `StudyFeature.Action`:

```swift
case cardSwiped
```

It does not reuse `.nextButtonTapped`. Action names in this reducer describe what the user did,
so both cases funnel into a shared private helper holding the existing logic verbatim:

```swift
case .cardSwiped, .nextButtonTapped:
    return advance(&state)
```

Both guards move into that helper unchanged, so the swipe inherits the whole rule set rather
than a copy of it — the reveal gate, and the last-card rule that finishes the deck instead of
wrapping:

```swift
private func advance(_ state: inout State) -> Effect<Action> {
    guard state.canAdvance, !state.cards.isEmpty else { return .none }
    guard !state.isOnLastCard else { return .send(.delegate(.deckFinished)) }
    state.index += 1
    state.hasRevealedCurrentCard = false
    state.isShowingEnglish = false
    return .none
}
```

A leftward throw on the last card therefore finishes the deck exactly as the Finish button does,
including the `.delegate(.deckFinished)` the parent needs to push the completion screen.

Flipping needs no new action; the tap sends the existing `.cardTapped`.

---

## 5. Reduce Motion

`FlipCard` already drops its rotation to a cross-fade. `SwipeableCard` follows: the `.move`
transition becomes `.opacity`, and the container animation shortens to `.easeInOut(duration: 0.2)`.

The drag itself stays live in both settings. Direct manipulation tracks the finger and is not
the kind of unrequested motion the setting is about.

---

## 6. Accessibility

The card keeps its existing `.accessibilityElement(children: .combine)`, label, hint, and
`.isButton` trait. The swipe is deliberately **not** exposed to VoiceOver: the Next button
already covers advancing and already explains the gate through its hint
("Flip the card to reveal the English first."). Adding a custom action would give VoiceOver users
a second path to something they can already reach, at the cost of another announcement.

---

## 7. Tests

**`StudyFeatureTests`** — two additions, matching the existing `TestStore` style:

- `.cardSwiped` before revealing is a no-op: index unchanged, no state mutation.
- `.cardSwiped` after revealing advances and resets `hasRevealedCurrentCard` and
  `isShowingEnglish`, and on the last card emits `.delegate(.deckFinished)` with no mutation —
  the same expectations the `.nextButtonTapped` tests already assert.

**`FlipWalkthroughUITests`** — one addition, kept as a walkthrough with screenshot attachments
rather than a strict assertion suite, consistent with the existing file:

- Swipe left before flipping → `Card 1 / 10` still reads 1, and `Card 2 / 10` does not exist.
  Both halves matter: the negative assertion is what makes the first one mean something.
- Tap to flip, swipe left → reads `2 / 10`.

Haptics are not covered: they cannot be felt in the simulator, so the flip haptic is verified by
hand on a device.

---

## 8. Known edge

Shuffle calls `State.restart()`, which sets `index = 0`. If you were already on card 0, the `.id`
does not change, so the deck swaps content with no slide — a pop rather than a transition. This is accepted rather than fixed:
the slide means "next card," and a shuffle is a different event. Keying the id on a deck
generation counter as well would animate it, at the cost of implying the two actions are the
same motion.
