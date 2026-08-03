# Assignment Brief — Citizen Café iOS Home Assignment

Transcribed from the eight screenshots of the assignment page provided on 2026-08-03. This is the
source of truth for what was asked; `docs/superpowers/specs/` holds design decisions and `README.md`
holds the submission write-up.

---

## Overview

Create a native iOS app where users study Hebrew vocabulary using flashcards. Cards are organised by
a tier → level → type structure. The UI lets users pick a combination and flip between the Hebrew
prompt and the English answer, with a real 3D card flip animation.

> **Aim to spend no more than ~4 hours.** We don't expect every part to be equally polished.
> Prioritise the repository behaviour, state management, and the core flashcard interaction. It's
> fine to leave optional items unfinished — just note what you intentionally skipped and why in the
> README. The timer on this page is informational; we use it as a conversation point in review, not
> as a hard cutoff.

---

## Tech Stack

**Required**

- Swift 5.9+ — language baseline
- SwiftUI app lifecycle — no Storyboards, no UIKit root
- iOS 17+ — minimum deployment target
- URLSession + async/await — no third-party networking libs
- MVVM or equivalent — networking & persistence separate from UI
- XCTest — at least two focused unit tests

**Optional**

- `@Observable` — preferred; `ObservableObject` also accepted
- UIKit — only where SwiftUI can't do the job

---

## Vocabulary Taxonomy

Citizen Café teaches Hebrew through a structured progression. Learners move through three **tiers** —
Foundation, Flow, and Freedom — each split into colour-coded **levels** that represent increasing
fluency. Some Freedom levels have **types**: separate content packs at the same mastery level, so
learners can keep learning without repeating the same words.

| Tier | Description | Levels |
| --- | --- | --- |
| **Foundation** | Core vocabulary, building blocks | Red, Orange, Pink, Yellow |
| **Flow** | Conversational fluency | Light Blue, Blue, Lime, Green |
| **Freedom** | Native-level mastery, multiple content packs | Dark Green ×4, Turquoise ×4, Indigo ×6, Purple |

> **Type semantics:** A type is the same mastery level with different content — think of it as a
> content pack. Dark Green has 4 packs, Turquoise 4, Indigo 6. All other levels have a single content
> set and need no type selector.

---

## Networking & Caching

Implement a repository (behind a protocol) that loads vocabulary using this exact strategy on every
app launch:

1. **Attempt a remote fetch** — Fetch the vocabulary from the Citizen Hub API:
   `GET https://hub.citizencafetlv.com/api/public/vocab` — no auth required. Use URLSession with
   async/await.
2. **On success — decode, cache, display** — Decode the response, write it to disk (see Storage
   below), and display the result. A successful fetch always overwrites the cache.
3. **On connectivity failure — load disk cache** — If the request fails because the device is offline
   (a URLError you classify as a connectivity error), load the previously cached data from disk.
   Explain in the README which URLError cases you treat as offline.
4. **No disk cache? — load bundled fallback** — If there is no disk cache, fall back to the JSON file
   bundled in the app bundle. This guarantees the app works on first launch with no network.

### Error handling requirements

- Validate HTTP status codes — a non-2xx response is not a connectivity error.
- Distinguish connectivity failures (device offline) from HTTP errors and decoding errors. Do not
  silently fall back to cache for HTTP 4xx/5xx or invalid JSON; surface those as errors instead.
- No force unwraps or `fatalError`.
- Show a meaningful loading state while fetching and a clear error state on failure.

---

## API Contract

```
GET https://hub.citizencafetlv.com/api/public/vocab

// No authentication required.
// Response: 200 OK  Content-Type: application/json
// Body: array of level objects

[
  {
    "tier":  string,          // "Foundation" | "Flow" | "Freedom"
    "level": string,          // e.g. "Red", "Dark Green"
    "type":  number | null,   // null = single content set
                              // 1-based index for multi-pack levels
                              // (Dark Green ×4, Turquoise ×4, Indigo ×6)
    "pairs": [
      { "hebrew": string, "english": string }
      // ~10 pairs per object
    ]
  }
]

// Example objects:
// { "tier": "Foundation", "level": "Red",        "type": null, "pairs": [...] }
// { "tier": "Freedom",    "level": "Dark Green", "type": 1,    "pairs": [...] }
// { "tier": "Freedom",    "level": "Dark Green", "type": 2,    "pairs": [...] }
```

### Storage

Use **FileManager-based persistence** to store the cached JSON on disk. Choose between
`Library/Caches` (can be evicted by the OS) and `Application Support` (persisted across device
restores) and briefly justify that choice in your README. Other approaches (e.g. Core Data) are fine
if you have a clear reason. **UserDefaults is not appropriate** for storing the full vocabulary
dataset.

---

## What to Build

**Required**

- **Tier picker** — Selecting a tier filters the Level picker to only that tier's levels.
- **Level picker** — Selecting a level loads cards (no type), or reveals a Type picker for Dark
  Green, Turquoise, and Indigo.
- **Type picker** — Shown conditionally only for levels that have multiple content packs.
- **Flashcard viewer** — Shows the Hebrew word. Tap to flip and reveal the English. Controls: Next
  and Shuffle. Progress indicator, e.g. "3 / 10".
- **3D card flip** — The flip interaction should visually read as a 3D rotation, not a cross-fade or
  instant swap. `rotation3DEffect` is one way to achieve this.
- **Loading & error states** — Show a loading indicator while fetching. Show a meaningful error
  message on non-connectivity failures.

**Optional — bonus signals only**

Dark mode polish · Haptic feedback on flip · Swipe gesture for Next · VoiceOver labels ·
Reduce Motion handling · Completion screen · Custom fonts

> Simple and well-considered beats over-engineered. If you run short on time, prioritise the
> networking layer and the core flashcard interaction over polish items.

---

## Architecture

Use MVVM or an equivalent architecture that keeps networking and persistence out of the views. The
key requirements are:

- **Separation** — Networking and persistence live in their own types, not inside views or view
  models.
- **Dependency injection** — Pass dependencies through protocols or initialisers so they can be
  replaced in tests.
- **Testability** — At least the repository and the core state transitions should be testable
  without a live network or simulator.

> We don't prescribe exact file structure, naming conventions, or internal patterns. If you deviate
> from the above for a clear reason, explain it in the README. There is no single right answer —
> good judgment matters more than conforming to a specific framework.

---

## Tests

Include **at least two focused unit tests** using XCTest. Tests should cover real logic, not just
type instantiation. Cover at least two of the following scenarios:

- Successful remote response is decoded and cached to disk.
- Offline request (connectivity error) loads the disk cache.
- Offline first launch with no disk cache loads the bundled JSON.
- An HTTP 500 response does not silently load a stale cache.
- Invalid JSON surfaces a decoding error rather than falling back.
- Changing the tier resets an invalid level or type selection.

> Two well-written, focused tests are worth more than ten shallow ones. If you write more, great —
> but don't inflate coverage at the cost of quality.

---

## Design Guidance

Use the Design Bible as inspiration — colour system (charcoal, yellow, warm off-white), typography,
brand personality. Translate these into an **iOS-native idiom** rather than a pixel-clone of the web
version.

- Use native SwiftUI components (Menu, Picker, NavigationStack, SF Symbols). Native affordances
  matter more than visual fidelity.
- Apply brand colours via the asset catalog. Charcoal (`#1C1C1C`) as primary, yellow (`#F5C518`) as
  accent — exact values are in the Design Bible.
- System fonts are fine. Custom fonts are a bonus — include the license and justify the decision if
  you add one.

> Simple and effective beats elaborate and messy. One well-considered screen is worth more than ten
> cluttered ones.

---

## Note on colour values

The assignment page quotes charcoal as `#1C1C1C` and yellow as `#F5C518`, while explicitly deferring
to the Design Bible for exact values. The Design Bible specifies `#373230` (charcoal) and `#F9E24C`
(yellow). This implementation uses the Design Bible values, per the page's own instruction that the
exact values live there.
