import Foundation

enum VocabularyError: Error, Equatable, LocalizedError {
    /// The request failed in a way we treat as "the device has no usable connection".
    case connectivity(URLError.Code)
    /// A response arrived, but the status code was not 2xx. Never falls back to cache.
    case http(Int)
    /// A 2xx response arrived but could not be decoded. Never falls back to cache.
    case decoding(String)
    /// Offline with neither a disk cache nor a readable bundled copy.
    case noDataAvailable
    case invalidEndpoint
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .connectivity:
            "You appear to be offline, and there are no saved words on this device yet."
        case .http(let status):
            "The vocabulary service responded unexpectedly (\(status)). Please try again."
        case .decoding:
            "The vocabulary data could not be read. Please try again."
        case .noDataAvailable:
            "No vocabulary is available on this device yet."
        case .invalidEndpoint:
            "The vocabulary service address is not valid."
        case .unknown(let description):
            description
        }
    }
}

extension URLError {
    /// Cases treated as "the device cannot reach the network", which is the only failure the load
    /// strategy is allowed to answer from cache.
    ///
    /// `timedOut`, `cannotFindHost` and `cannotConnectToHost` are judgement calls: from the device
    /// they are indistinguishable from having no route at all, and answering them from cache
    /// degrades to a slightly older copy of the same data rather than to a wrong answer. Every
    /// other failure — including all HTTP status and decoding failures — surfaces as an error.
    var isConnectivityFailure: Bool {
        switch code {
        case .callIsActive,
             .cannotConnectToHost,
             .cannotFindHost,
             .dataNotAllowed,
             .internationalRoamingOff,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut:
            true
        default:
            false
        }
    }
}
