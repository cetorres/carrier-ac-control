import Foundation

/// Tokens taken from an existing Carrier web session.
struct TokenBundle: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String?
}

/// Reads tokens from whatever the user pastes.
///
/// Accepted forms:
/// - The my.carrier.com session JSON (`localStorage.getItem('AUTH_DATA--1')`), which includes a refresh token
/// - Any JSON that contains it, such as the portal's `persist:root` entry
/// - An `Authorization: Bearer …` header, `Bearer …`, or a bare access token
enum TokenImport {
    /// The localStorage key where my.carrier.com keeps its session.
    static let portalStorageKey = "AUTH_DATA--1"

    /// The command to run in the browser console on my.carrier.com.
    static let consoleCommand = "copy(localStorage.getItem('\(portalStorageKey)'))"

    static func parse(_ text: String) throws -> TokenBundle {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Console output shows strings wrapped in single quotes.
        if value.count > 1, value.hasPrefix("'"), value.hasSuffix("'") {
            value = String(value.dropFirst().dropLast())
        }

        if let bundle = bundle(fromJSONText: value, depth: 0) {
            return bundle
        }

        var token = value
        if let range = token.range(of: "bearer ", options: [.caseInsensitive, .backwards]) {
            token = String(token[range.upperBound...])
        }
        token = token.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))

        guard JWTClaims(token: token) != nil else { throw CarrierError.unrecognizedToken }
        return TokenBundle(accessToken: token, refreshToken: nil, tokenType: "Bearer")
    }

    private static func bundle(fromJSONText text: String, depth: Int) -> TokenBundle? {
        guard depth < 6,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return bundle(in: object, depth: depth)
    }

    private static func bundle(in object: Any, depth: Int) -> TokenBundle? {
        guard depth < 6 else { return nil }

        if let text = object as? String {
            // JSON stored inside a JSON string, as redux-persist and console output do.
            return bundle(fromJSONText: text, depth: depth + 1)
        }

        if let dictionary = object as? [String: Any] {
            let access = (dictionary["access_token"] as? String) ?? (dictionary["accessToken"] as? String)
            if let access, !access.isEmpty {
                let refresh = (dictionary["refresh_token"] as? String) ?? (dictionary["refreshToken"] as? String)
                let type = (dictionary["token_type"] as? String) ?? (dictionary["tokenType"] as? String)
                return TokenBundle(
                    accessToken: access,
                    refreshToken: (refresh?.isEmpty ?? true) ? nil : refresh,
                    tokenType: type
                )
            }
            for value in dictionary.values {
                if let found = bundle(in: value, depth: depth + 1) { return found }
            }
            return nil
        }

        if let array = object as? [Any] {
            for value in array {
                if let found = bundle(in: value, depth: depth + 1) { return found }
            }
        }
        return nil
    }
}
