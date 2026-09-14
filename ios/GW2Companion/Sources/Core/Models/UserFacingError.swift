import Foundation

extension Error {
    /// Converts failures crossing into normal UI into intentionally written copy.
    /// Unknown errors are never forwarded verbatim because Foundation descriptions
    /// can expose implementation details such as domains, paths, and decoder keys.
    func userFacingMessage(fallback: String) -> String {
        if let error = self as? GW2APIError {
            return error.errorDescription ?? fallback
        }
        if let error = self as? BridgeConnectionError {
            return error.errorDescription ?? fallback
        }
        if let error = self as? PairingError {
            return error.errorDescription ?? fallback
        }
        if let error = self as? TodayLoadError {
            return error.errorDescription ?? fallback
        }
        if let error = self as? AcquisitionKnowledgeError {
            return error.errorDescription ?? fallback
        }
        if let error = self as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "The network connection is unavailable. Showing saved data where possible."
            case .timedOut:
                return "The request took too long. Showing saved data where possible."
            default:
                return fallback
            }
        }
        return fallback
    }
}
