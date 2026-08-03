# Citizen Café — Hebrew Flashcards

A native iOS app for studying Hebrew vocabulary. Pick a tier → level → content pack, then flip
through cards with a real 3D rotation between the Hebrew prompt and the English answer.

Built in roughly four hours against the Citizen Hub public vocabulary API.

---

## Running it

Requires Xcode 26 and an iOS 26 simulator.

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

The only third-party dependency is
[swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture)
(1.26.1), resolved via SPM. Networking is plain `URLSession` + `async/await`, as required.

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
Features/        AppFeature → BrowseFeature, StudyFeature
Views/           AppView, BrowseView, StudyView, FlipCard
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

Twenty unit tests (XCTest) plus UI walkthroughs. None of the unit tests touch the network or the
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

**Study rules — `StudyFeatureTests`**

| Test | Asserts |
| --- | --- |
| `testNextIsBlockedUntilTheCardIsRevealed` | Next is inert before reveal, survives a flip back to Hebrew, then advances and re-locks on the new card |
| `testShuffleResetsToAnUnrevealedFirstCard` | shuffling returns to an unrevealed card at index 0, with a seeded generator so the order is deterministic |

TCA's `TestStore` is exhaustive: every state mutation must be declared or the test fails. These
aren't assertions on a couple of fields — they pin the entire state after each action.

**Typography — `BrandTypographyTests`** (10 tests) covers face registration, that every role
resolves to its bundled face rather than a system substitute, that only heading roles use the voice
face, that the Hebrew prompt never lands on the Latin-only face, that body copy clears the
line-height floor at every Dynamic Type size, and that roles scale with the user's text size.

**`FlipWalkthroughUITests`** drives the real app through load → pick level → study → flip, capturing
screenshots. It's a smoke check that the screens compose, not a logic test.

---

## Design

Tokens come from the design bible and live in the asset catalog with light and dark values:
charcoal `#373230`, yellow `#F9E24C`, warm off-white surface `#F2F1EC`, muted `#716C66`, hairline
`#D2CEC6`.

The rules I took as binding: charcoal text on yellow (never white), never a pure-white page field,
yellow as emphasis rather than wallpaper, thin borders, generous whitespace, restrained motion.
Yellow appears in exactly three places — the primary CTA, the Next button, and the retry button.

Native affordances were preferred over visual fidelity, per the brief: `Menu` pickers,
`NavigationStack`, SF Symbols, standard nav bar.

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

- **Completion screen** — Next wraps to the start of the deck instead. A completion state is a
  product decision (retry wrong cards? shuffle? exit?) that deserves more thought than the time left.
- **Haptics on flip** — one line, but untestable in the simulator, so I'd be shipping it unverified.
- **Swipe gesture for Next** — competes with the interactive back-swipe on a pushed screen; doing it
  properly means tuning gesture priority, which isn't worth the remaining budget.
- **iPad-specific layout** — the app runs on iPad but the layout is phone-first.
- **Progress persistence** — not asked for, and it implies a data model for "known" cards.

Included despite being optional, because they're cheap and the card is otherwise opaque to
assistive technology: **VoiceOver labels** on the card, controls and pickers, and **Reduce Motion**
handling on the flip.

---

## Known gaps

- The `.remote` path is exercised in tests through a stubbed `fetch`; there is no integration test
  against the live endpoint, by design — tests shouldn't depend on the network being up.
- `VocabCacheClient`'s live implementation is not covered by a test that writes to a real disk. The
  strategy around it is fully covered; the `FileManager` calls themselves are not.
- No snapshot tests. The flip is verified by the UI walkthrough and by eye.
