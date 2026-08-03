import Foundation

@testable import CitizenCaferTest

enum Fixtures {
    static let sets = [
        VocabSet(
            tier: "Freedom",
            level: "Dark Green",
            type: 1,
            pairs: [WordPair(hebrew: "מִשְׁפָּט", english: "Sentence")]
        ),
        VocabSet(
            tier: "Freedom",
            level: "Dark Green",
            type: 2,
            pairs: [WordPair(hebrew: "רַעְיוֹן", english: "Idea")]
        ),
        VocabSet(
            tier: "Foundation",
            level: "Red",
            type: nil,
            pairs: [WordPair(hebrew: "שָׁלוֹם", english: "Hello / Peace")]
        ),
    ]

    static let validJSON = Data(
        """
        [
          { "tier": "Freedom", "level": "Dark Green", "type": 1,
            "pairs": [{ "hebrew": "מִשְׁפָּט", "english": "Sentence" }] },
          { "tier": "Freedom", "level": "Dark Green", "type": 2,
            "pairs": [{ "hebrew": "רַעְיוֹן", "english": "Idea" }] },
          { "tier": "Foundation", "level": "Red", "type": null,
            "pairs": [{ "hebrew": "שָׁלוֹם", "english": "Hello / Peace" }] }
        ]
        """.utf8
    )

    static let malformedJSON = Data(#"[{ "tier": "Foundation", "level": }]"#.utf8)
}

/// Intercepts requests so the live API client can be exercised without a network.
final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var result: (statusCode: Int, data: Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let result = Self.result,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: result.statusCode,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}
