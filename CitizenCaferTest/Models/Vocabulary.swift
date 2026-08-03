import Foundation

/// One Hebrew → English flashcard.
struct WordPair: Codable, Equatable, Identifiable, Sendable {
    let hebrew: String
    let english: String

    var id: String { "\(hebrew)|\(english)" }
}

/// One content pack: a tier + level, optionally narrowed to a numbered type.
///
/// `tier` and `level` stay as `String` rather than enums on purpose — the API is the source of
/// truth for both the names and their order, so a level added server-side shows up in the UI
/// instead of failing to decode.
struct VocabSet: Codable, Equatable, Identifiable, Sendable {
    let tier: String
    let level: String
    /// `nil` means the level has a single content set and needs no type selector.
    let type: Int?
    let pairs: [WordPair]

    var id: String { "\(tier)|\(level)|\(type.map(String.init) ?? "-")" }
}

/// Which step of the load strategy produced the data. Surfaced to the UI so it can say the words
/// came from disk, and asserted in tests so each branch is verified rather than inferred.
enum VocabularySource: String, Equatable, Sendable {
    case remote, cache, bundled
}

struct VocabularyLoad: Equatable, Sendable {
    let sets: [VocabSet]
    let source: VocabularySource
}

extension Sequence where Element: Hashable {
    /// Removes duplicates while preserving first-appearance order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
