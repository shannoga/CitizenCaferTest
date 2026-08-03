# Citizen Café — Hebrew Flashcards

A native iOS app for studying Hebrew vocabulary. Pick a tier → level → content pack, then flip
through cards with a real 3D rotation between the Hebrew prompt and the English answer.

Built in roughly four hours against the Citizen Hub public vocabulary API.

---

## Running it

Deployment target is **iOS 17.0**, per the brief. Built with Xcode 26; the only simulator runtime
installed on the development machine was iOS 26.5, so the app is compiled against 17.0 and verified
running on 26.5 — see Known gaps.

```sh
open CitizenCaferTest.xcodeproj
```

On first open, Xcode will ask you to trust the macro plugins used by the Composable Architecture
(swift-syntax macros need one-time approval). Click **Trust & Enable**. From the command line the
equivalent is:

```sh
xcodebuild build -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipMacroValidation

xcodebuild test -project CitizenCaferTest.xcodeproj -scheme CitizenCaferTest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipMacroValidation \
  -only-testing:CitizenCaferTestTests
```

Two third-party packages, both via SPM:
[swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture)
(1.26.1) for the architecture, and [Swiftetti](https://github.com/fredbenenson/Swiftetti) (MIT) for
the completion screen's confetti — see The confetti burst. Neither touches the network: **networking
is plain `URLSession` + `async/await`**, with no third-party layer over it, as required.

---

## Architecture

The brief asks for MVVM "or an equivalent architecture that keeps networking and persistence out of
the views". This uses **the Composable Architecture** — a state-machine architecture where each
screen is a `Reducer` owning an `@ObservableState`, and all side effects are expressed as values
returned from the reducer rather than performed inline. It satisfies the same three requirements the
brief names — separation, dependency injection, testability — and buys exhaustive state-transition
testing that plain MVVM doesn't give you for free.

```
Models/          VocabSet, WordPair, VocabularySource, VocabularyLoad, VocabularyError
Dependencies/    VocabularyClient (the repository) + its three collaborators
Features/        AppFeature → BrowseFeature, StudyFeature, CompletionFeature
Views/           AppView, BrowseView, StudyView, CompletionView, FlipCard, SwipeableCard, ConfettiBurst
DesignSystem/    Brand colour/space tokens, BrandTypography roles
Resources/Fonts/ The two brand families and their licences
vocab.json       Bundled fallback copy of the API response
```

**Data flows one way.** A view sends an action, the reducer computes the next state and optionally
an effect, the effect sends more actions. Views hold a `Store` and nothing else — no networking, no
persistence, no formatting decisions that depend on where the data came from.

**Navigation is state.** `startStudyingButtonTapped` does nothing in `BrowseFeature`; `AppFeature`
observes it and appends to a `StackState`. The study screen has no idea it's being pushed, and the
whole navigation stack is inspectable and testable as a value.

**Two ways a child talks to its parent, and the line between them.** Unconditional intents stay
plain — `startStudyingButtonTapped` and the completion screen's three buttons are no-ops in the
child, and `AppFeature` acts on them. A fact only the child can derive travels as an explicit
`Delegate` action: `StudyFeature` sends `.delegate(.deckFinished)` on the last card. The difference
matters because on the last card the correct child behaviour is *no mutation at all*, which from
the outside is indistinguishable from Next tapped on an unrevealed card. Telling those apart in the
parent would mean a second copy of `canAdvance` — and the reveal rule would then have two homes.

### A deliberate deviation: dependency client instead of a protocol

The brief says the repository should sit "behind a protocol". This uses a **dependency client** —
a struct of closures — instead:

```swift
@DependencyClient
struct VocabularyClient: Sendable {
    var load: @Sendable () async throws -> VocabularyLoad
}
```

This is the *protocol witness* form of the same abstraction: one seam, injected rather than
constructed, replaceable wholesale or endpoint-by-endpoint in tests. It is the idiomatic form in
this architecture, and it buys two things a protocol doesn't:

- Tests override **one endpoint at a time** (`$0[VocabCacheClient.self].load = { nil }`) without
  writing a fake class that has to implement every method.
- The generated `testValue` leaves every endpoint **unimplemented**, so a dependency I forget to
  stub fails the test loudly instead of silently returning empty data. Several assertions below rely
  on exactly this.

If a protocol is preferred, `VocabularyClient` maps onto one mechanically — the strategy body is
unchanged.

---

## Networking and caching

`VocabularyClient.liveValue.load` is the whole strategy, in one testable function. It is composed
from three smaller clients — `VocabAPIClient`, `VocabCacheClient`, `BundledVocabClient` — resolved
through `@Dependency` inside the closure.

```
fetch
 ├─ 2xx → decode ─ ok ──→ write cache → .remote
 │                └ fail → throw .decoding          (cache untouched)
 ├─ non-2xx ────────────→ throw .http(code)         (cache untouched)
 └─ URLError classified as offline
      ├─ cache hit  → .cache
      └─ cache miss → bundled → .bundled
                       └─ unreadable → throw .connectivity
```

Two details worth calling out:

**Decode happens before the cache write.** Malformed data can never poison the cache, so a bad
deploy upstream can't corrupt the offline copy that a user already has.

**A failed cache write does not fail the load.** The user still gets fresh words; they just won't
have them offline. The alternative — failing a successful fetch because a disk write failed — trades
a working screen for a purist error.

`load()` returns a `VocabularyLoad` carrying **which step produced the data**. That's what lets the
UI say "Offline — showing the words saved on this device", and it lets every test assert which
branch actually ran rather than inferring it from the payload.

### Which `URLError` cases count as offline

Only these fall back to disk:

`notConnectedToInternet`, `networkConnectionLost`, `dataNotAllowed`, `internationalRoamingOff`,
`callIsActive`, `cannotFindHost`, `cannotConnectToHost`, `timedOut`

The first five are unambiguous. The last three are judgement calls and deserve the argument:
`timedOut`, `cannotFindHost` and `cannotConnectToHost` can each be caused by something at the
server's end rather than the device's, but from the device they are indistinguishable from having no
usable route. Since the fallback is a cached copy of *the same resource*, a false positive degrades
to slightly older data rather than to a wrong answer — while a false negative shows an error screen
to someone sitting on a train with a perfectly good cache on disk. The asymmetry favours treating
them as offline.

**Everything else surfaces as an error.** A non-2xx status is not a connectivity failure and never
reads the cache. Neither does invalid JSON. Both are asserted in the tests, including a spy that
fails if the cache is so much as read on those paths.

### Storage: Application Support

The cached JSON is written to `Application Support/vocab-cache.json`, atomically, and marked
`isExcludedFromBackup`.

`Caches` was the alternative, and the reason against it is specific: the OS may evict `Caches` at any
time. If it did, an offline launch would silently fall through to the *bundled* copy, which is older
than what the user had a moment ago — a silent downgrade with no signal. Application Support is not
evicted, so the offline guarantee actually holds. It's excluded from backup because the content is
re-downloadable and shouldn't consume a user's iCloud quota, which is the concern that usually
pushes people toward `Caches` in the first place.

`UserDefaults` is not used for the dataset, per the brief.

There are no force unwraps and no `fatalError` in the app target.

---

## Tests

Twenty-nine unit tests (XCTest) plus UI walkthroughs. None of the unit tests touch the network or the
disk.

**Repository — `VocabularyClientTests`**

| Test | Asserts |
| --- | --- |
| `testSuccessfulResponseIsDecodedAndCached` | 200 decodes, cache is overwritten, source is `.remote` |
| `testConnectivityFailureLoadsDiskCache` | offline `URLError` returns cached sets, source `.cache` |
| `testConnectivityFailureWithoutCacheLoadsBundledJSON` | offline + empty cache falls back to the bundle |
| `testHTTPErrorSurfacesAndDoesNotReadStaleCache` | 500 throws **and the cache is never read** |
| `testMalformedJSONSurfacesDecodingErrorAndDoesNotReadCache` | bad JSON throws, cache neither read nor written |
| `testLiveAPIClientRejectsNon2xxStatusCodes` | the *live* client validates status codes, via a stubbed `URLProtocol` |

That last one exists because stubbing `fetch` to throw `.http(500)` proves the strategy doesn't fall
back, but proves nothing about whether status-code validation is implemented. The live client's
`URLSession` is a parameter (defaulting to `.shared`) specifically so this can be tested for real.

**State transitions — `BrowseFeatureTests`**

| Test | Asserts |
| --- | --- |
| `testChangingTierResetsInvalidLevelAndTypeSelection` | switching tier clears a now-invalid level and pack; single-pack levels need no pack and become studyable immediately |
| `testLoadFailureSurfacesErrorAndRetrySucceeds` | failure renders an error state, retry returns to loading and then succeeds |
| `testSetAfterAdvancesWithinALevelAndStopsAtTheLastPack` | `set(after:)` walks packs in order and returns `nil` at the end of a level rather than crossing into the next one |

**Study rules — `StudyFeatureTests`**

| Test | Asserts |
| --- | --- |
| `testNextIsBlockedUntilTheCardIsRevealed` | Next is inert before reveal, survives a flip back to Hebrew, then advances and re-locks on the new card |
| `testShuffleResetsToAnUnrevealedFirstCard` | shuffling returns to an unrevealed card at index 0, with a seeded generator so the order is deterministic |
| `testTheLastCardFinishesTheDeckInsteadOfWrapping` | the last card mutates nothing and sends `.delegate(.deckFinished)` |
| `testAnUnrevealedLastCardStillGoesNowhere` | the reveal rule outranks the finish rule — no state change and, because `TestStore` is exhaustive about effects, no delegate either |
| `testSwipeObeysTheSameRulesAsNext` | the swipe routes through the same `advance`, so it is inert before reveal and finishes rather than wraps on the last card |

**The completion flow — `AppFeatureTests`**

The flow only exists as a conversation between three reducers: the study screen reports a deck is
done, `AppFeature` decides what that leads to, and `BrowseFeature` holds the only catalogue that can
answer "what's the next pack?". None of it is visible from a single feature's tests.

| Test | Asserts |
| --- | --- |
| `testFinishingADeckPushesCompletionCarryingTheFollowingPack` | completion is pushed with the next pack already resolved |
| `testFinishingTheLastPackInALevelOffersNoNextPack` | a single-pack level yields `nextSet == nil`, which is what hides the button |
| `testStudyAgainDropsCompletionAndRewindsTheDeckUnderneath` | replaying leaves the stack **one** deep, not two |
| `testNextPackReplacesTheDeckInPlaceAndMovesTheBrowseSelectionWithIt` | the deck is swapped in place and `browse` stays in step, so Back isn't stale |
| `testBackToBrowseClearsTheWholeStack` | the stack empties |

TCA's `TestStore` is exhaustive: every state mutation must be declared or the test fails. These
aren't assertions on a couple of fields — they pin the entire state after each action.

**Typography — `BrandTypographyTests`** (10 tests) covers face registration, that every role
resolves to its bundled face rather than a system substitute, that only heading roles use the voice
face, that the Hebrew prompt never lands on the Latin-only face, that body copy clears the
line-height floor at every Dynamic Type size, and that roles scale with the user's text size.

**`FlipWalkthroughUITests`** drives the real app through load → pick level → study → flip, capturing
screenshots. It's a smoke check that the screens compose, not a logic test.

**`CompletionWalkthroughUITests`** plays a whole ten-card pack to its end, checks the last card's
button reads Finish rather than Next, and proves the completion screen arrives with the right ways
onward. It also captures the confetti, which nothing else can assert on.

---

## Design

Tokens come from the design bible and live in the asset catalog with light and dark values:
charcoal `#373230`, yellow `#F9E24C`, warm off-white surface `#F2F1EC`, muted `#716C66`, hairline
`#D2CEC6`.

The rules I took as binding: charcoal text on yellow (never white), never a pure-white page field,
yellow as emphasis rather than wallpaper, thin borders, generous whitespace, restrained motion.
Yellow appears in exactly four places — the primary CTA, the Next button, the retry button, and one
button on the completion screen. That last one is a rule rather than a count: **the completion
screen gets exactly one yellow element, and it is whichever button means "keep going"** — Next pack
when there is one, otherwise Study this pack again. Three filled CTAs on a celebration screen would
make it the exception that proves "emphasis, not wallpaper".

### The confetti burst

Finishing a pack throws one burst of brand-yellow shards from the top edge, which falls and settles.
A burst, not a loop: confetti still falling behind text you're trying to read stops being
celebration and becomes wallpaper. It sits *behind* the content, because the charcoal-on-yellow
contrast rule objects to yellow shards crossing 13pt charcoal metadata.

The three yellows are derived in HSB from the single `BrandYellow` swatch rather than declared as
new hex literals — there is no second and third value to keep in step, and no `Color(hex:)`
extension coming back in through the side door after it was deliberately removed.

Under Reduce Motion the whole thing degrades to a static scatter that fades in over a third of a
second, at fixed positions rather than random ones: Reduce Motion is a request for predictability.
The burst is decorative by contract — `accessibilityHidden(true)` and `allowsHitTesting(false)`
wrap both branches, so it can never be announced or swallow a tap.

The falling branch is [Swiftetti](https://github.com/fredbenenson/Swiftetti) (MIT), which renders
particles through a SwiftUI `Canvas` and emits one burst per rising edge of its trigger. It is
pinned by **revision**, not version: the repository publishes no tags, so a branch pin would be a
moving target.

Native affordances were preferred over visual fidelity, per the brief: `Menu` pickers,
`NavigationStack`, SF Symbols, standard nav bar.

### The launch screen

The brief rules out Storyboards, so there is no `LaunchScreen.storyboard`. The launch screen is
declared instead: `INFOPLIST_KEY_UILaunchScreen_Generation = YES`, which is the Xcode-native way to
say "SwiftUI app, no launch storyboard" and synthesises an empty `UILaunchScreen` dictionary into the
generated Info.plist.

That means a plain system-background field rather than a branded one, and it's worth being straight
about why. I tried carrying the brand surface across by pointing `UILaunchScreen`'s `UIColorName` at
the `SurfaceBase` asset through a base Info.plist; Xcode's Info.plist generator overwrites the key
with its own empty dictionary whichever way `_Generation` is set, so the colour never reached the
built bundle. Rather than ship a README claim the binary doesn't honour, the launch screen stays the
stock one. It's also close to what the HIG asks for — a launch screen should disappear, not
announce itself. The logo arrives a moment later in `BrowseView`'s header, where it's content rather
than a curtain.

### Typography

The bible's rule is **Assistant is the system, Fedra is the voice** — Fedra used selectively for
page and section titles, Assistant carrying everything functional, and no component mixing the two.
Both ship here as themselves:

| Family | Files | Licence |
| --- | --- | --- |
| Fedra Sans Pro | Medium, Bold | Typotheque commercial licence held by Citizen Café — **not redistributable** |
| Assistant | Regular, SemiBold, Bold | SIL Open Font License 1.1 |

Full terms are in `Resources/Fonts/LICENSES.md`. Anyone forking this repo needs their own Typotheque
licence for the Fedra files.

**Hebrew is Assistant, by design rather than by compromise.** The Fedra Sans Pro kit is
Latin/Cyrillic/Greek and has no Hebrew — which costs nothing here, because Assistant *is* the
bible's Hebrew companion to Fedra. The card prompt is therefore Assistant Bold. Display roles still
carry an explicit Assistant fallback ahead of the system font, so a Hebrew word appearing inside a
Latin title lands on the brand's own Hebrew face rather than on a system substitute.

Typography is modelled as **roles**, not raw fonts: each role owns its face, size, the text style it
scales from, its fallback cascade, and whether it takes the bible's 1.4 line-height floor. Views say
`.brandType(.cardPrompt)` and never name a font. Faces register with Core Text at first use — which
means previews and tests get them without the app's launch path running — and every role falls back
to system type if a face is ever missing from the bundle rather than rendering in whatever Core Text
substitutes.

### You have to look before you move on

Next is disabled until the current card has been revealed. Tapping through a deck without reading
the answers isn't studying, so the drill enforces the loop: see the Hebrew, commit, reveal, advance.

The gate is on *having revealed* the card, not on *currently showing English* — flipping back to
look at the Hebrew again doesn't take the card away from you. Advancing or shuffling resets it, so
each new card has to be earned on its own. The rule is enforced in the reducer as well as the view,
so it holds no matter how the action arrives, and the disabled button carries a VoiceOver hint
explaining why rather than just failing silently.

### The 3D flip

`FlipCard` rotates the whole stack 180° about the Y axis with perspective. The back face is
pre-rotated 180° so its text never renders mirrored, and the opacity swap between faces is a
near-instant change *delayed to the midpoint of the turn* — so exactly one face is visible at any
moment, and the transition reads as rotation rather than a cross-fade. Under
`accessibilityReduceMotion` it collapses to a plain cross-fade.

---

## Intentionally skipped

Optional items I chose not to build, and why:

- **iPad-specific layout** — the app runs on iPad but the layout is phone-first.
- **Progress persistence** — not asked for, and it implies a data model for "known" cards.

Everything else on the optional list is here: **dark mode** (every token carries a dark value),
**VoiceOver labels** on the card, controls and pickers, **Reduce Motion** handling on the flip, the
swipe transition and the confetti, a **completion screen**, **custom fonts**, a **swipe gesture
for Next**, and a **haptic on flip**.

The swipe needed a decision rather than just time, so it's worth spelling out. It does one thing —
a revealed card thrown to the left advances — and the reveal state decides only whether it is
available. An unrevealed card still follows the finger at a quarter speed up to 40pt and springs
back, which is the tactile counterpart to the greyed-out Next button: the control reads as "not
yet" rather than as dead. An earlier revision also let that drag flip the card, which meant one
gesture had two meanings and needed a mode locked on first movement so a mid-drag flip couldn't
silently turn into a throw; dropping flip-by-drag removed the ambiguity and the machinery with it.
It attaches with `.gesture`, not `.highPriorityGesture`, so the system's interactive back-swipe
still wins from the screen edge.

The flip haptic is a soft impact driven by a view-local counter the tap increments, rather than by
`isShowingEnglish` — advancing and shuffling both clear that flag, so triggering on it would buzz
on Next and on Shuffle. It is the one thing here the test suite cannot cover: haptics can't be felt
in the simulator, so it needs checking by hand on a device.

Both endings route through the reducer's `advance` rather than moving the index directly, so the
gesture and the Next button cannot drift out of step — which is what `testSwipeObeysTheSameRulesAsNext`
pins.

---

## Known gaps

- The `.remote` path is exercised in tests through a stubbed `fetch`; there is no integration test
  against the live endpoint, by design — tests shouldn't depend on the network being up.
- `VocabCacheClient`'s live implementation is not covered by a test that writes to a real disk. The
  strategy around it is fully covered; the `FileManager` calls themselves are not.
- No snapshot tests. The flip is verified by the UI walkthrough and by eye.
- The app targets iOS 17.0 and compiles cleanly against it with no availability diagnostics, but
  the development machine only had an iOS 26.5 simulator runtime installed, so it has not been
  *executed* on an iOS 17 device or simulator. Nothing in the code uses post-17 API — the compiler
  would have rejected it against this target — but that's a static guarantee, not a runtime one.
