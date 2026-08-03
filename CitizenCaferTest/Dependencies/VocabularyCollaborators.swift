import ComposableArchitecture
import Foundation

// The three collaborators the load strategy is built from. Each is its own dependency client so a
// test can replace exactly one of them and leave the others unimplemented — an unstubbed endpoint
// fails the test loudly instead of quietly returning empty data.

// MARK: - Remote

@DependencyClient
struct VocabAPIClient: Sendable {
    /// Returns the raw response body, having already validated the status code.
    var fetch: @Sendable () async throws -> Data
}

extension VocabAPIClient: DependencyKey {
    static let endpoint = URL(string: "https://hub.citizencafetlv.com/api/public/vocab")

    /// The session is a parameter so status-code validation can be tested against a stubbed
    /// protocol without reaching the network.
    static func live(session: URLSession = .shared) -> VocabAPIClient {
        VocabAPIClient(
            fetch: {
                guard let url = endpoint else { throw VocabularyError.invalidEndpoint }
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw VocabularyError.unknown("The response was not an HTTP response.")
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw VocabularyError.http(http.statusCode)
                }
                return data
            }
        )
    }

    static var liveValue: VocabAPIClient { live() }

    static var testValue: VocabAPIClient { VocabAPIClient() }
}

// MARK: - Disk cache

@DependencyClient
struct VocabCacheClient: Sendable {
    /// `nil` means "nothing cached yet", which is different from "reading the cache failed".
    var load: @Sendable () throws -> Data?
    var save: @Sendable (Data) throws -> Void
}

extension VocabCacheClient: DependencyKey {
    static var liveValue: VocabCacheClient {
        // Application Support rather than Caches: this file is the app's offline guarantee, and
        // the OS may evict Caches at any point, which would silently demote a fresh cache to the
        // older bundled copy. Excluded from backup because the content is re-downloadable.
        @Sendable func fileURL() throws -> URL {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return directory.appendingPathComponent("vocab-cache.json")
        }

        return VocabCacheClient(
            load: {
                let url = try fileURL()
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return try Data(contentsOf: url)
            },
            save: { data in
                var url = try fileURL()
                try data.write(to: url, options: .atomic)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try url.setResourceValues(values)
            }
        )
    }

    static var testValue: VocabCacheClient { VocabCacheClient() }
}

// MARK: - Bundled fallback

@DependencyClient
struct BundledVocabClient: Sendable {
    var load: @Sendable () throws -> Data
}

extension BundledVocabClient: DependencyKey {
    static var liveValue: BundledVocabClient {
        BundledVocabClient(
            load: {
                guard let url = Bundle.main.url(forResource: "vocab", withExtension: "json") else {
                    throw VocabularyError.noDataAvailable
                }
                return try Data(contentsOf: url)
            }
        )
    }

    static var testValue: BundledVocabClient { BundledVocabClient() }
}
