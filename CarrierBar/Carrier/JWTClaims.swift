import Foundation

/// The few claims CarrierBar reads from a Carrier (Okta) access token.
///
/// The signature is not verified here. Carrier's API verifies every request, and these claims
/// are only used to know whose account it is, when the token expires, and how to renew it.
struct JWTClaims: Sendable {
    /// Okta puts the account login (the email) in `sub`.
    let subject: String?
    /// Okta client the token was issued to (`cid`). Needed to renew it.
    let clientID: String?
    /// Authorization server that issued the token (`iss`).
    let issuer: String?
    let expiresAt: Date

    init?(token: String) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard let data = Data(base64Encoded: base64),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let expiry = (object["exp"] as? NSNumber)?.doubleValue
        else { return nil }

        subject = object["sub"] as? String
        clientID = object["cid"] as? String
        issuer = object["iss"] as? String
        expiresAt = Date(timeIntervalSince1970: expiry)
    }
}
