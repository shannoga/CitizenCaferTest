import ComposableArchitecture
import Foundation

/// The repository. Modelled as a dependency client — a protocol witness erased to a struct of
/// closures — rather than a Swift protocol, which is the Composable Architecture idiom for the
/// same seam: one abstraction, swappable wholesale or endpoint-by-endpoint in tests.
@DependencyClient
struct VocabularyClient: Sendable {
    var load: @Sendable () async throws -> VocabularyLoad
}

extension VocabularyClient: DependencyKey {
    static var liveValue: VocabularyClient {
        VocabularyClient(
            load: {
                @Dependency(VocabAPIClient.self) var api
                @Dependency(VocabCacheClient.self) var cache
                @Dependency(BundledVocabClient.self) var bundled

                let decoder = JSONDecoder()

                do {
                    let data = try await api.fetch()

                    // Decode before caching, so malformed data can never poison the cache.
                    let sets: [VocabSet]
                    do {
                        sets = try decoder.decode([VocabSet].self, from: data)
                    } catch {
                        throw VocabularyError.decoding("\(error)")
                    }

                    // A failed write shouldn't fail an otherwise successful load; the user still
                    // gets fresh words, they just won't have them offline.
                    try? cache.save(data)

                    return VocabularyLoad(sets: sets, source: .remote)
                } catch let urlError as URLError where urlError.isConnectivityFailure {
                    // Offline is the *only* failure allowed to answer from disk. HTTP and decoding
                    // failures fall through this catch and propagate to the caller.
                    if let cached = try? cache.load(),
                       let cached,
                       let sets = try? decoder.decode([VocabSet].self, from: cached) {
                        return VocabularyLoad(sets: sets, source: .cache)
                    }

                    guard let data = try? bundled.load(),
                          let sets = try? decoder.decode([VocabSet].self, from: data)
                    else {
                        throw VocabularyError.connectivity(urlError.code)
                    }

                    return VocabularyLoad(sets: sets, source: .bundled)
                }
            }
        )
    }

    static var testValue: VocabularyClient { VocabularyClient() }
}
