import Foundation
import Security

/// What survives a relaunch. Everything except `username` is optional, so sessions saved by
/// earlier versions still load.
struct CarrierSession: Codable, Equatable, Sendable {
    /// Account email. Carrier's queries are keyed by it.
    var username: String
    /// Renews the access token. Missing when only an access token was pasted.
    var refreshToken: String?
    var accessToken: String?
    var accessTokenExpiresAt: Date?
    var tokenType: String?
    /// Okta client the tokens belong to. Defaults to the Carrier app's client.
    var clientID: String?
    /// Okta token endpoint. Defaults to Carrier's.
    var tokenEndpoint: String?
}

/// Stores the session as a single generic password item in the login Keychain.
enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.cetorres.CarrierBar"
    private static let account = "carrier-session"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> CarrierSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                Log.store.error("Keychain read failed with status \(status)")
            }
            return nil
        }
        return try? JSONDecoder().decode(CarrierSession.self, from: data)
    }

    @discardableResult
    static func save(_ session: CarrierSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }

        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "CarrierBar session"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Log.store.error("Keychain write failed with status \(status)")
        }
        return status == errSecSuccess
    }

    static func delete() {
        _ = SecItemDelete(baseQuery as CFDictionary)
    }
}
