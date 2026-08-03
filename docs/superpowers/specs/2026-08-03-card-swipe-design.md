# Card Swipe — Design

Date: 2026-08-03
Builds on: [2026-08-03-flashcards-design.md](2026-08-03-flashcards-design.md)

## Goal

Give the study card a horizontal drag gesture, and give card changes a matching slide
transition. The gesture means two different things depending on whether the card has been
revealed:

| Card state             | Horizontal drag                                            |
| ---------------------- | ---------------------------------------------------------- |
| Not yet revealed       | Resisted travel; past the threshold it flips the card       |
| Revealed (`canAdvance`)| Left tracks the finger and throws to the next card          |

The `canAdvance` rule from the original design is unchanged: you have to look at the answer
before moving on. The swipe is a second way to obey that rule, never a way around it.

## Non-goals

Backward navigation (the deck is one-way and wraps), scrubbable/interactive flip rotation,
drag-linked card tilt, haptics, a completion screen.

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
    let onAdvance: () -> Void
    let onFlip: () -> Void
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
        onAdvance: { store.send(.cardSwiped) },
        onFlip: { store.send(.cardTapped) }
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

**Commit does not animate the offset home.** On a successful throw, `SwipeableCard` calls
`onAdvance()` and leaves `offset` where it is. Animating it back to zero would fight the removal
transition.

---

## 3. Gesture rules

Mode is locked on the first `onChanged` event of each gesture and cleared in `onEnded`, so a
flip that completes mid-drag cannot silently turn the same continuous drag into a swipe:

```swift
private enum DragMode { case advance, flip }
@State private var mode: DragMode?
@State private var offset: CGFloat = 0
```

**`.advance` mode** (entered when `canAdvance` is true at gesture start):

- Leftward translation tracks the finger 1:1.
- Rightward translation is resisted — right does not advance.
- On release, commit if `translation.width < -88` **or** `predictedEndTranslation.width < -200`
  (a flick). Otherwise spring home with `.spring(response: 0.3, dampingFraction: 0.8)`.

**`.flip` mode** (entered when `canAdvance` is false):

- Either direction is resisted, and past the threshold it flips.
- On release, if `abs(translation.width) > 60`, call `onFlip()`. Either way the offset snaps
  home over 0.15s — fast, so the slide-back does not compete with `FlipCard`'s 0.5s rotation
  for attention.

**Resistance** is shared by both modes: `translation * 0.25`, clamped to ±40pt. The locked card
visibly refuses to leave, which is the tactile counterpart to the greyed-out Next button. Same
gesture, two clearly different responses.

**Fixed thresholds, not proportional ones.** 88pt rather than 25% of the card width, so the view
needs no `GeometryReader` or width plumbing. The card is full-bleed minus `Brand.Space.lg` on
each side, so 88pt is roughly a quarter of it on every phone this ships to.

The existing `.onTapGesture` stays. Tap remains the primary way to flip; a `DragGesture` with the
default 10pt minimum distance coexists with it.

---

## 4. Reducer

One new case in `StudyFeature.Action`:

```swift
case cardSwiped
```

It does not reuse `.nextButtonTapped`. Action names in this reducer describe what the user did,
so both cases funnel into a shared private helper holding the existing guard, wrap, and reset
logic:

```swift
case .cardSwiped, .nextButtonTapped:
    return advance(&state)
```

The `guard state.canAdvance, !state.cards.isEmpty` stays inside that helper, so the swipe path is
gated in the reducer exactly as the button path already is — not only by the view.

Flip-by-drag needs no new action; it sends the existing `.cardTapped`.

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
- `.cardSwiped` after revealing advances, wraps, and resets `hasRevealedCurrentCard` and
  `isShowingEnglish` — same expectations as the `.nextButtonTapped` case.

**`FlipWalkthroughUITests`** — one addition, kept as a walkthrough with screenshot attachments
rather than a strict assertion suite, consistent with the existing file:

- Swipe left before flipping → `Card 1 / 10` still reads 1.
- Tap to flip, swipe left → reads `2 / 10`.

---

## 8. Known edge

Shuffle sets `index = 0`. If you were already on card 0, the `.id` does not change, so the deck
swaps content with no slide — a pop rather than a transition. This is accepted rather than fixed:
the slide means "next card," and a shuffle is a different event. Keying the id on a deck
generation counter as well would animate it, at the cost of implying the two actions are the
same motion.
