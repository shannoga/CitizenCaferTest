# Citizen Café Flashcards — Design

Date: 2026-08-03
Budget: ~4 hours
Stack: SwiftUI (app lifecycle), iOS 17+, TCA (Point-Free Composable Architecture), URLSession + async/await, XCTest

## Goal

Native iOS app for studying Hebrew vocabulary. Users pick a tier → level → (type, when the
level has multiple packs) and flip through cards showing the Hebrew prompt and the English
answer with a real 3D rotation.

## Non-goals

Accounts, progress persistence, spaced repetition, search, audio, iPad-specific layout.

---

## 1. Data

The API returns a flat array of 23 objects, 10 pairs each:

```json
{ "tier": "Foundation", "level": "Red", "type": null, "pairs": [{ "hebrew": "...", "english": "..." }] }
```

Verified live against `GET https://hub.citizencafetlv.com/api/public/vocab`:

| Tier       | Levels                              | Types                                     |
| ---------- | ----------------------------------- | ----------------------------------------- |
| Foundation | Red, Orange, Pink, Yellow           | all `null`                                |
| Flow       | Light Blue, Blue, Lime, Green       | all `null`                                |
| Freedom    | Dark Green, Turquoise, Indigo, Purple | 4, 4, 6, `null`                         |

Domain models are plain `Codable` value types:

```swift
struct WordPair: Codable, Equatable, Identifiable { let hebrew, english: String }
struct VocabSet: Codable, Equatable, Identifiable {
  let tier: String
  let level: String
  let type: Int?
  let pairs: [WordPair]
}
```

**Tier and level stay `String`, not enums.** Picker ordering is derived from the order the
API returns (first-appearance order), which already matches the intended progression. A new
level added server-side then appears in the UI instead of breaking the decode.

The response body is saved to `Resources/vocab.json` and shipped in the app bundle as the
first-launch fallback.

---

## 2. Repository — `VocabularyClient`

Implemented as a TCA dependency client (protocol witness: a struct of closures) rather than a
Swift protocol. Same seam, same substitutability; the README explains the deviation from the
brief's wording.

```swift
enum VocabularySource: Equatable { case remote, cache, bundled }
struct VocabularyLoad: Equatable { let sets: [VocabSet]; let source: VocabularySource }

@DependencyClient
struct VocabularyClient { var load: @Sendable () async throws -> VocabularyLoad }
```

Composed from three independently-overridable sub-clients:

```swift
@DependencyClient struct VocabAPIClient     { var fetch: @Sendable () async throws -> Data }
@DependencyClient struct VocabCacheClient   { var load: @Sendable () throws -> Data?
                                              var save: @Sendable (Data) throws -> Void }
@DependencyClient struct BundledVocabClient { var load: @Sendable () throws -> Data }
```

`VocabularyClient.liveValue.load` resolves the three via `@Dependency` inside the closure, so
the strategy is a single testable function.

### Strategy (fixed order, every launch)

```
fetch
 ├─ 2xx → decode ─ ok ──→ write cache → .remote
 │                └ fail → throw .decoding          (cache untouched)
 ├─ non-2xx ────────────→ throw .http(code)         (cache untouched)
 └─ URLError classified offline
      ├─ cache hit  → .cache
      └─ cache miss → bundled → .bundled
                       └ missing → throw .noDataAvailable
```

### Errors

```swift
enum VocabularyError: Error, Equatable {
  case offline(URLError.Code)
  case http(Int)
  case decoding(String)
  case noDataAvailable
}
```

### Offline classification

Treated as connectivity failures: `.notConnectedToInternet`, `.networkConnectionLost`,
`.dataNotAllowed`, `.internationalRoamingOff`, `.callIsActive`, `.cannotFindHost`,
`.cannotConnectToHost`, `.timedOut`.

The last three are judgement calls, documented in the README: from the device they are
indistinguishable from having no route, and a false positive degrades to a cached copy of the
same data rather than to a wrong answer. Everything else — including all HTTP status failures
and all decoding failures — surfaces as an error.

### Storage

`Application Support/vocab-cache.json`, created if missing, `isExcludedFromBackup = true`.

Chosen over `Caches` because the file is the app's offline guarantee: the OS can evict
`Caches` at any point, which would silently demote a fresh cache to the older bundled copy.
Excluded from backup because the content is re-downloadable.

---

## 3. Features

```
AppFeature
├─ BrowseFeature                    (root)
└─ StackState<Path.State>
   └─ StudyFeature                  (pushed)
```

### BrowseFeature

State: `loadState: LoadState`, `selectedTier: String?`, `selectedLevel: String?`,
`selectedType: Int?`.

```swift
enum LoadState: Equatable {
  case loading
  case loaded([VocabSet], VocabularySource)
  case failed(String)
}
```

Available tiers / levels / types are computed from the loaded sets, never stored.

Actions: `.task`, `.vocabularyResponse(Result<VocabularyLoad, VocabularyError>)`,
`.tierSelected(String)`, `.levelSelected(String)`, `.typeSelected(Int)`, `.retryTapped`,
`.startStudyingTapped`.

Invariants (tested):

- selecting a tier clears `selectedLevel` and `selectedType`
- selecting a level clears `selectedType`
- a level with exactly one pack keeps `selectedType == nil` and is immediately studyable
- `startStudyingTapped` is only enabled when a unique `VocabSet` matches the selection

### StudyFeature

State: `title: String`, `cards: [WordPair]`, `index: Int`, `isFlipped: Bool`.

Actions: `.cardTapped` (flip), `.nextTapped`, `.shuffleTapped`.

- Next advances and wraps to 0 at the end; no completion screen (optional item, skipped and
  noted in the README).
- Shuffle reshuffles and returns to index 0.
- Both reset `isFlipped` to the Hebrew face.
- Shuffle goes through `@Dependency(\.withRandomNumberGenerator)` so it is deterministic
  under test.

---

## 4. Views

**BrowseView** — native `Menu` pickers for tier and level; the type row is present only when
the selected level has more than one pack. `.loading` renders a labelled `ProgressView`,
`.failed` renders the message plus a Retry button. When the source is `.cache` or `.bundled`
a quiet inline note says the words are saved/offline.

**StudyView** — the card is two faces in a `ZStack` with `rotation3DEffect` about the Y axis
and an opacity swap at 90°, so text never renders mirrored. Tap anywhere on the card to flip.
Bottom bar: `Shuffle`, progress `3 / 10`, `Next`. `accessibilityReduceMotion` collapses the
rotation to a cross-fade.

### Design tokens (asset catalog, light + dark)

| Token          | Light     | Role                                  |
| -------------- | --------- | ------------------------------------- |
| `brandYellow`  | `#F9E24C` | primary CTA, progress accent          |
| `brandCharcoal`| `#373230` | text, dark surfaces                   |
| `surfaceBase`  | `#F2F1EC` | page background                       |
| `surfaceRaised`| `#FFFFFF` | card face                             |
| `textMuted`    | `#716C66` | metadata                              |
| `lineSubtle`   | `#D2CEC6` | hairline borders, dividers            |

Rules taken from the design bible: charcoal text on yellow (never white), no pure-white page
background, yellow as emphasis rather than fill, thin borders, generous whitespace, restrained
motion.

### Typography

The bible's dual-type system, implemented as written: **Assistant is the system, Fedra is the
voice.** Fedra Sans Pro appears only on page and section titles; Assistant carries navigation,
labels, controls, body copy and metadata — and all Hebrew.

The licensed Fedra Sans Pro kit is Latin/Cyrillic/Greek with **no Hebrew**. That is not a
workaround: the bible pairs Fedra with Assistant precisely because Assistant is the Hebrew
companion, so the Hebrew card prompt is Assistant by design. Fedra roles still declare an
Assistant fallback so off-script text inside a heading stays in the brand.

`BrandTypography.Role` is one case per row of the bible's structural hierarchy, and views apply
it with `.brandType(_:)` — no view names a font or a size.

| Role          | Bible role     | Face               | Size | Scales from  | Line height |
| ------------- | -------------- | ------------------ | ---- | ------------ | ----------- |
| `cardPrompt`  | `display.hero` | Assistant Bold     | 48   | `.largeTitle`| natural     |
| `cardAnswer`  | —              | Assistant SemiBold | 24   | `.title2`    | natural     |
| `h1`          | `heading.h1`   | Fedra Sans Bold    | 30   | `.title1`    | natural     |
| `h2`          | `heading.h2`   | Fedra Sans Bold    | 22   | `.title2`    | natural     |
| `body`        | `body.default` | Assistant Regular  | 17   | `.body`      | ≥ 1.4       |
| `bodySmall`   | `body.default` | Assistant Regular  | 15   | `.subheadline`| ≥ 1.4      |
| `uiLabel`     | `ui.label`     | Assistant Regular  | 17   | `.body`      | natural     |
| `buttonLabel` | `button.label` | Assistant SemiBold | 17   | `.headline`  | natural     |
| `metaSmall`   | `meta.small`   | Assistant Regular  | 13   | `.footnote`  | ≥ 1.4       |
| `metaDigits`  | `meta.small`   | Assistant Regular  | 13   | `.footnote`  | natural     |

**Line height.** Assistant sets ~1.31em on its own, so body roles add the difference as line
spacing to clear the bible's 1.4 floor. Headings and control labels keep their natural leading —
the floor is a floor, not a target. No role sets negative tracking.

**Fallback stacks.** Fedra roles carry an explicit Core Text cascade to Assistant, so a missing
glyph lands on the brand's own Hebrew face before the system font. If a face were dropped from
the bundle entirely, roles fall back to the system font at their declared weight.

**Registration.** Five static weights live in `Resources/Fonts/` (`LICENSES.md` records that
Fedra is a Typotheque licence and not redistributable; Assistant ships with its OFL notice).
They register through `CTFontManagerRegisterFontURLs` from a lazy global, not `UIAppFonts` — the
target generates its Info.plist, and lazy registration also covers SwiftUI previews and unit
tests, neither of which runs the app's `init`. `UINavigationBar` gets the faces explicitly
through `UINavigationBarAppearance`: Fedra for the large title, Assistant for inline chrome.

**Dynamic Type.** Every role resolves through `UIFontMetrics` against the reader's current size
category, recomputed when it changes, so brand type scales exactly like system type — verified to
AX5. Two layouts adapt with it: the picker rows stack their value under the title, and the study
controls give Next its own full-width line, instead of wrapping mid-word or running off-screen.

---

## 5. Tests (XCTest, `CitizenCaferTestTests`)

Repository, via `withDependencies` — no network, no disk, no simulator:

1. 200 + valid JSON → decodes, writes the cache, reports `.remote`
2. offline `URLError` + cache present → returns cached sets, reports `.cache`
3. offline + no cache → returns bundled sets, reports `.bundled`
4. HTTP 500 → throws `.http(500)` **and the cache is never read** (spy asserts)
5. malformed JSON → throws `.decoding`, cache never read

Reducer, via `TestStore`:

6. selecting a tier resets a level and type that belonged to the previous tier

Typography, in-process:

7. every bundled face registers and resolves under its PostScript name
8. every face has glyphs for Hebrew with nikud — otherwise the cards would silently fall back
   to a substitute font

Well past the required two; 1–6 are exactly the scenarios the brief enumerates.

---

## 6. Build order and budget

| Step                                                       | Est. |
| ---------------------------------------------------------- | ---- |
| xcode-select, add TCA via SPM, folders, colors, bundled JSON | 25m  |
| Models + `VocabularyClient` + sub-clients + live impls       | 50m  |
| `AppFeature`, `BrowseFeature`, `StudyFeature`                | 45m  |
| `BrowseView`, `StudyView`, flip card                         | 50m  |
| Tests                                                        | 35m  |
| README                                                       | 20m  |

Priority if time runs short: repository behaviour and the flip interaction come first; visual
polish and the optional list come last.

## 7. Intentionally skipped (for the README)

Completion screen, haptics, swipe-to-advance, iPad layout, progress persistence.
VoiceOver labels and Reduce Motion are included because they are cheap and the card is
otherwise opaque to assistive technology.
