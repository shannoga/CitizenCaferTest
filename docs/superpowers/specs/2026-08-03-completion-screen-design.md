# Completion screen — design

**Date:** 2026-08-03
**Status:** built

## Problem

The study session had no ending. `StudyFeature.nextButtonTapped` wrapped modularly, so a reader who
finished the last card was silently returned to card 1 with no acknowledgement that they had
finished anything. The original README listed this as a deliberate deferral, on the grounds that a
completion state is a product decision. This spec makes that decision.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Headline | Tier-led: "You just completed" / **"Foundation Level"** / "Red · Pack 2" / "10 cards studied" | The tier is the thing worth being told you're inside of. Pack is omitted when `type == nil`. |
| Presentation | A pushed `AppPath.completion` destination | Follows the existing browse → study pattern; keeps the whole flow inspectable as a value. Rejected: an overlay inside `StudyFeature` (hides navigation in a child) and `fullScreenCover` (the app uses no sheets anywhere). |
| Actions | Next pack (when one exists), Study this pack again, Back to Main Menu | Covers the three things a reader plausibly wants next. |
| Confetti | One ~1.5 s burst that settles | "Restrained motion". A permanent loop behind text is wallpaper, not celebration. |

## Structure

`CompletionFeature.State` holds an **answer, not a question**: the finished `VocabSet` and
`nextSet: VocabSet?`, both resolved by `AppFeature` at push time. The screen never sees the
catalogue — it has no business knowing what a `sets` array is.

`AppFeature` is the only place that holds both the finished pack and the loaded catalogue, so it
owns all four transitions. `BrowseFeature.State.set(after:)` resolves the following pack within the
same tier and level, sorted numerically to agree with the order the Pack menu showed the reader.
It deliberately stops at the end of a level: continuing into the *next level* is a progression
decision, not a "next pack" one.

### Why `deckFinished` is a `Delegate` action

The repo's established pattern is a plain no-op action handled by the parent
(`BrowseFeature.startStudyingButtonTapped`). The completion screen's three buttons keep that
pattern, because they are unconditional intents.

`deckFinished` cannot. On the last card the correct child behaviour is **no mutation at all**, which
from the parent's side is indistinguishable from Next tapped on an unrevealed card. Separating them
in the parent would require re-implementing `canAdvance`, giving the reveal rule two homes and a
way to drift. So the fact travels explicitly.

### Stack transitions

- **Study again** — pop completion, then `restart()` the deck underneath. Leaves the stack one deep,
  so replaying can't stack completion screens up behind you.
- **Next pack** — pop completion and replace the study element *in place*, rather than popping to
  root and pushing again: one pop transition, and the stack stays one deep. `browse.selectedType`
  moves with it so Back doesn't show a stale "Pack 2" behind a screen studying pack 3.
- **Back to Main Menu** — clear the stack.

The system back button is hidden. The deck is done; going "back" to it isn't one of the ways
forward, and hiding it also stops the interactive swipe from stranding someone on the last card of a
pack they just finished.

## Design system compliance

Type roles, top to bottom: `.body` (17) → `.h1` (Fedra Bold 30) → `.uiLabel` (17, preceded by the
level dot) → `.body` (17). The level dot reuses `Brand.levelColor(for:)` with the same construction
as the study screen's toolbar — a non-yellow accent that ties the screen back to the deck just
finished.

**Yellow economy.** The bible's rule is yellow as emphasis, not wallpaper, and yellow appeared in
exactly three places app-wide. This screen adds exactly one: the button that means "keep going" —
Next pack when there is one, otherwise Study this pack again. The second button takes the
raised-surface-plus-hairline treatment; "Back to Main Menu" is unfilled. Charcoal on yellow, never
white.

## Confetti

Three yellows derived in HSB from the single `BrandYellow` swatch — no second and third hex literal
to keep in step, and no reintroduced `Color(hex:)` extension. Drawn behind the content, because the
contrast rule objects to yellow shards crossing 13pt charcoal metadata.

The falling branch uses [Swiftetti](https://github.com/fredbenenson/Swiftetti) (MIT), a SwiftUI
`Canvas` particle renderer, with the `fromTheTop` settings and squares/circles only — the library's
stars and hearts would be a second voice on a screen the brand already speaks for. It is pinned by
**revision**: the repository publishes no tags, so a branch pin would be a moving target.

A hand-rolled `CAEmitterLayer` was built first and is the reason `ConfettiBurst` exists as a wrapper
type at all — the seam meant swapping the renderer touched one file and left the palette, the
Reduce Motion fallback, and the decorative contract untouched.

Reduce Motion replaces the fall with a static scatter fading in over 0.35 s, at fixed positions:
Reduce Motion is a request for predictability. Both branches are wrapped in
`accessibilityHidden(true)` and `allowsHitTesting(false)`.

### Accessibility

The headline collapses to one element with an explicit label — "You just completed Foundation Level,
Red, pack 2. 10 cards studied." Read line by line, VoiceOver stops four times and pronounces "·" as
punctuation. `.accessibilitySortPriority(2)` puts the outcome ahead of the buttons so the
screen-change announcement says what happened rather than what to do about it. Deliberately not
`AccessibilityFocusState` in `onAppear`: focus assignment straight after a push is timing-sensitive
and would need a sleep to be reliable.

## Trade-off accepted

Swiftetti is a young, single-commit, untagged repository. Pinning by revision makes the build
reproducible, but the dependency is unproven and adds a third-party package for what is a bonus
visual flourish. The alternative — the hand-rolled emitter — carries no dependency but had an
unresolved rendering bug at the time of the decision.
