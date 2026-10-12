import Foundation

enum CarrierError: LocalizedError, Equatable {
    case notSignedIn
    case sessionExpired
    case accessTokenExpired
    case loginRejected(String)
    case unrecognizedToken
    case tokenMissingAccount
    case untrustedIssuer
    case http(status: Int)
    case graphQL(String)
    case invalidResponse
    case network(String)

    /// Errors that mean the current session can't be used anymore.
    var isAuthFailure: Bool {
        switch self {
        case .notSignedIn, .sessionExpired, .accessTokenExpired:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You're not signed in."
        case .sessionExpired:
            return "Your Carrier session expired. Please sign in again."
        case .accessTokenExpired:
            return "The access token expired. Sign in again, or paste the full session from my.carrier.com so CarrierBar can renew it."
        case .loginRejected(let message):
            return message
        case .unrecognizedToken:
            return "That doesn't look like a Carrier session or access token."
        case .tokenMissingAccount:
            return "That token doesn't include the account email."
        case .untrustedIssuer:
            return "That token wasn't issued by Carrier's sign in service."
        case .http(let status):
            return "Carrier returned HTTP \(status)."
        case .graphQL(let message):
            return "Carrier API error: \(message)"
        case .invalidResponse:
            return "Carrier sent a response this app couldn't read."
        case .network(let message):
            return message
        }
    }
}
