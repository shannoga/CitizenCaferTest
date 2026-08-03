import ComposableArchitecture
import XCTest

@testable import CitizenCaferTest

/// Exercises the four-step load strategy. Every collaborator is overridden, so nothing here touches
/// the network or the disk. Endpoints left unstubbed are unimplemented and fail loudly if called,
/// which is itself part of each assertion.
final class VocabularyClientTests: XCTestCase {

    // MARK: - Step 1 & 2: remote success

    func testSuccessfulResponseIsDecodedAndCached() async throws {
        let cached = LockIsolated<Data?>(nil)

        let load = try await withDependencies {
            $0[VocabAPIClient.self].fetch = { Fixtures.validJSON }
            $0[VocabCacheClient.self].save = { data in cached.setValue(data) }
        } operation: {
            try await VocabularyClient.liveValue.load()
        }

        XCTAssertEqual(load.source, .remote)
        XCTAssertEqual(load.sets, Fixtures.sets)
        XCTAssertEqual(cached.value, Fixtures.validJSON, "A successful fetch must overwrite the cache.")
    }

    // MARK: - Step 3: offline falls back to disk

    func testConnectivityFailureLoadsDiskCache() async throws {
        let load = try await withDependencies {
            $0[VocabAPIClient.self].fetch = { throw URLError(.notConnectedToInternet) }
            $0[VocabCacheClient.self].load = { Fixtures.validJSON }
        } operation: {
            try await VocabularyClient.liveValue.load()
        }

        XCTAssertEqual(load.source, .cache)
        XCTAssertEqual(load.sets, Fixtures.sets)
    }

    // MARK: - Step 4: offline first launch falls back to the bundle

    func testConnectivityFailureWithoutCacheLoadsBundledJSON() async throws {
        let load = try await withDependencies {
            $0[VocabAPIClient.self].fetch = { throw URLError(.networkConnectionLost) }
            $0[VocabCacheClient.self].load = { nil }
            $0[BundledVocabClient.self].load = { Fixtures.validJSON }
        } operation: {
            try await VocabularyClient.liveValue.load()
        }

        XCTAssertEqual(load.source, .bundled)
        XCTAssertEqual(load.sets, Fixtures.sets)
    }

    // MARK: - HTTP failures are not connectivity failures

    func testHTTPErrorSurfacesAndDoesNotReadStaleCache() async throws {
        let readCache = LockIsolated(false)

        do {
            _ = try await withDependencies {
                $0[VocabAPIClient.self].fetch = { throw VocabularyError.http(500) }
                $0[VocabCacheClient.self].load = {
                    readCache.setValue(true)
                    return Fixtures.validJSON
                }
            } operation: {
                try await VocabularyClient.liveValue.load()
            }
            XCTFail("A 500 response must surface as an error.")
        } catch {
            XCTAssertEqual(error as? VocabularyError, .http(500))
        }

        XCTAssertFalse(readCache.value, "A 500 response must not silently fall back to the cache.")
    }

    /// Proves the live client — not a stub — rejects a non-2xx status.
    func testLiveAPIClientRejectsNon2xxStatusCodes() async throws {
        URLProtocolStub.result = (statusCode: 500, data: Data())
        defer { URLProtocolStub.result = nil }

        do {
            _ = try await VocabAPIClient.live(session: URLProtocolStub.session()).fetch()
            XCTFail("A 500 response must throw.")
        } catch {
            XCTAssertEqual(error as? VocabularyError, .http(500))
        }
    }

    // MARK: - Decoding failures are not connectivity failures

    func testMalformedJSONSurfacesDecodingErrorAndDoesNotReadCache() async throws {
        let readCache = LockIsolated(false)

        do {
            _ = try await withDependencies {
                $0[VocabAPIClient.self].fetch = { Fixtures.malformedJSON }
                $0[VocabCacheClient.self].load = {
                    readCache.setValue(true)
                    return Fixtures.validJSON
                }
                $0[VocabCacheClient.self].save = { _ in
                    XCTFail("Malformed data must never reach the cache.")
                }
            } operation: {
                try await VocabularyClient.liveValue.load()
            }
            XCTFail("Malformed JSON must surface as an error.")
        } catch {
            guard case .decoding = error as? VocabularyError else {
                return XCTFail("Expected a decoding error, got \(error).")
            }
        }

        XCTAssertFalse(readCache.value, "Invalid JSON must not silently fall back to the cache.")
    }
}
