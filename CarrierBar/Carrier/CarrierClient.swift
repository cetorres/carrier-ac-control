import Foundation

/// Client for Carrier's private cloud API, the same backend the Carrier SmartHome app and
/// my.carrier.com use.
///
/// Gets a session, keeps its access token fresh, fetches thermostat status, and changes
/// setpoints and holds.
/// A session comes from a password sign in or from tokens taken from a my.carrier.com web session.
/// It's kept in the Keychain. Passwords are never stored.
actor CarrierClient {
    private enum Endpoint {
        static let graphQL = URL(string: "https://dataservice.infinity.iot.carrier.com/graphql")!
        static let graphQLNoAuth = URL(string: "https://dataservice.infinity.iot.carrier.com/graphql-no-auth")!
        static let oauthToken = URL(string: "https://sso.carrier.com/oauth2/default/v1/token")!
    }

    /// Okta client used by Carrier's apps and my.carrier.com. Used when a session doesn't name its own.
    private static let defaultClientID = "0oa1ce7hwjuZbfOMB4x7"

    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var session: CarrierSession?
    private var refreshTask: Task<Void, Error>?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Session

    var username: String? { session?.username }

    /// Restores a session saved in the Keychain.
    func restore(_ session: CarrierSession) {
        self.session = session
    }

    func signIn(username: String, password: String) async throws {
        let body = try encoder.encode(GraphQLRequest(
            operationName: "assistedLogin",
            query: CarrierQueries.assistedLogin,
            variables: AssistedLoginVariables(input: .init(username: username, password: password))
        ))

        var request = URLRequest(url: Endpoint.graphQLNoAuth)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, status) = try await send(request)
        guard (200..<300).contains(status) else { throw CarrierError.http(status: status) }

        let payload = try unwrap(data, operationName: "assistedLogin", as: AssistedLoginData.self).assistedLogin
        guard let result = payload,
              result.success?.bool == true,
              let tokens = result.data,
              let access = tokens.accessToken?.string,
              let refresh = tokens.refreshToken?.string
        else {
            let message = payload?.errorMessage?.string ?? "Check your username and password."
            throw CarrierError.loginRejected(message)
        }

        let claims = JWTClaims(token: access)
        adopt(CarrierSession(
            username: username,
            refreshToken: refresh,
            accessToken: access,
            accessTokenExpiresAt: claims?.expiresAt ?? Date().addingTimeInterval(tokens.expiresIn?.double ?? 1800),
            tokenType: tokens.tokenType?.string,
            clientID: claims?.clientID,
            tokenEndpoint: nil
        ))
    }

    /// Adopts tokens from an existing web session. The account comes from the token itself.
    func importSession(_ bundle: TokenBundle) throws {
        guard let claims = JWTClaims(token: bundle.accessToken) else { throw CarrierError.unrecognizedToken }
        guard let username = claims.subject, username.contains("@") else { throw CarrierError.tokenMissingAccount }
        let endpoint = try Self.tokenEndpoint(forIssuer: claims.issuer)

        let refreshToken = (bundle.refreshToken?.isEmpty ?? true) ? nil : bundle.refreshToken
        if refreshToken == nil, claims.expiresAt.timeIntervalSinceNow < 120 {
            throw CarrierError.accessTokenExpired
        }

        adopt(CarrierSession(
            username: username,
            refreshToken: refreshToken,
            accessToken: bundle.accessToken,
            accessTokenExpiresAt: claims.expiresAt,
            tokenType: bundle.tokenType,
            clientID: claims.clientID,
            tokenEndpoint: endpoint.absoluteString
        ))
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        KeychainStore.delete()
    }

    /// Returns an access token that is valid for at least another minute, renewing it if possible.
    func validAccessToken() async throws -> String {
        guard let current = session else { throw CarrierError.notSignedIn }
        if let token = current.accessToken,
           let expiry = current.accessTokenExpiresAt,
           expiry.timeIntervalSinceNow > 60 {
            return token
        }
        guard current.refreshToken != nil else { throw CarrierError.accessTokenExpired }

        try await refreshTokens()

        guard let renewed = session else { throw CarrierError.notSignedIn }
        guard let token = renewed.accessToken,
              let expiry = renewed.accessTokenExpiresAt,
              expiry.timeIntervalSinceNow > 0
        else { throw CarrierError.sessionExpired }
        return token
    }

    // MARK: - Data

    /// Fetches every thermostat on the account, from both Infinity systems and Smart Thermostats.
    func fetchThermostats() async throws -> [Thermostat] {
        guard let username = session?.username else { throw CarrierError.notSignedIn }

        var thermostats: [Thermostat] = []
        var failures: [Error] = []

        do {
            let data = try await graphQL(
                "getInfinitySystems",
                document: CarrierQueries.infinitySystems,
                variables: ["userName": username],
                as: InfinitySystemsData.self
            )
            thermostats += (data.infinitySystems ?? []).flatMap { Thermostat.makeAll(from: $0) }
        } catch {
            failures.append(error)
        }

        do {
            let data = try await graphQL(
                "getEntryLevelSystems",
                document: CarrierQueries.entryLevelSystems,
                variables: ["username": username],
                as: EntryLevelSystemsData.self
            )
            thermostats += (data.entryLevelSystems ?? []).flatMap { Thermostat.makeAll(from: $0) }
        } catch {
            failures.append(error)
        }

        if let authFailure = failures.first(where: { ($0 as? CarrierError)?.isAuthFailure == true }) {
            throw authFailure
        }
        if thermostats.isEmpty, let failure = failures.first {
            throw failure
        }
        for failure in failures {
            Log.api.notice("One system query failed: \(failure.localizedDescription, privacy: .public)")
        }

        let sorted = thermostats.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Self.disambiguated(sorted)
    }

    // MARK: - Control

    /// Holds a unit at new setpoints for `hold`, like changing the temperature on the thermostat itself.
    func setSetpoints(of thermostat: Thermostat, heat: Double, cool: Double, hold: Thermostat.HoldLength) async throws {
        switch thermostat.kind {
        case .infinity:
            try await setInfinitySetpoints(
                serial: thermostat.systemSerial,
                zoneID: thermostat.zoneID,
                heat: heat,
                cool: cool,
                fanMode: thermostat.fanMode,
                holdUntil: hold.clockText
            )
        case .smartThermostat:
            try await setEntryLevelZone(of: thermostat, heat: heat, cool: cool, hold: hold)
        }
    }

    /// Infinity holds a zone in an activity: write the "manual" activity, then hold the zone in it.
    private func setInfinitySetpoints(
        serial: String,
        zoneID: String,
        heat: Double,
        cool: Double,
        fanMode: String?,
        holdUntil: String?
    ) async throws {
        _ = try await graphQL(
            "updateInfinityZoneActivity",
            document: CarrierQueries.updateInfinityZoneActivity,
            variables: InfinityZoneActivityVariables(input: .init(
                serial: serial,
                zoneId: zoneID,
                activityType: "manual",
                htsp: Self.setpointText(heat),
                clsp: Self.setpointText(cool),
                fan: fanMode
            )),
            as: InfinityMutationData.self
        )
        try await setInfinityHold(serial: serial, zoneID: zoneID, activity: "manual", until: holdUntil)
    }

    /// Holds a zone in a comfort profile, like "away", for `hold`.
    func hold(_ thermostat: Thermostat, in profileID: String, until hold: Thermostat.HoldLength) async throws {
        switch thermostat.kind {
        case .infinity:
            try await setInfinityHold(
                serial: thermostat.systemSerial,
                zoneID: thermostat.zoneID,
                activity: profileID,
                until: hold.clockText
            )
        case .smartThermostat:
            // Smart Thermostats can't be switched to a scene. Hold the scene's setpoints instead.
            let profile = thermostat.profile(profileID)
            guard let heat = profile?.heatSetpoint ?? thermostat.heatSetpoint,
                  let cool = profile?.coolSetpoint ?? thermostat.coolSetpoint
            else { throw CarrierError.graphQL("\(DisplayFormat.title(profileID) ?? profileID) has no temperatures set.") }
            try await setEntryLevelZone(of: thermostat, heat: heat, cool: cool, hold: hold)
        }
    }

    /// Ends a hold so the zone follows its schedule again.
    func resumeSchedule(of thermostat: Thermostat) async throws {
        switch thermostat.kind {
        case .infinity:
            try await setInfinityHold(serial: thermostat.systemSerial, zoneID: thermostat.zoneID, activity: nil, until: nil)
        case .smartThermostat:
            // Send the scheduled scene's setpoints along, so the zone goes straight back to them.
            let scheduled = thermostat.scheduledProfileID(at: Date()).flatMap(thermostat.profile)
            guard let heat = scheduled?.heatSetpoint ?? thermostat.heatSetpoint,
                  let cool = scheduled?.coolSetpoint ?? thermostat.coolSetpoint
            else { throw CarrierError.graphQL("Carrier didn't report this thermostat's temperatures.") }
            try await setEntryLevelZone(of: thermostat, heat: heat, cool: cool, hold: nil)
        }
    }

    /// Holds a zone in `activity`, or turns the hold off when it's nil.
    private func setInfinityHold(serial: String, zoneID: String, activity: String?, until holdUntil: String?) async throws {
        _ = try await graphQL(
            "updateInfinityZoneConfig",
            document: CarrierQueries.updateInfinityZoneConfig,
            variables: InfinityZoneConfigVariables(input: .init(
                serial: serial,
                zoneId: zoneID,
                hold: activity == nil ? "off" : "on",
                holdActivity: activity,
                otmr: activity == nil ? nil : holdUntil
            )),
            as: InfinityMutationData.self
        )
    }

    /// Smart Thermostats take both setpoints in one change, with how long to hold them. A timed
    /// hold gives its length in hours and leaves the schedule on. A hold until changed turns the
    /// schedule off. A nil `hold` follows the schedule again.
    private func setEntryLevelZone(of thermostat: Thermostat, heat: Double, cool: Double, hold: Thermostat.HoldLength?) async throws {
        let scheduleEnabled: Bool
        let holdHours: Int
        switch hold {
        case nil:
            (scheduleEnabled, holdHours) = (true, 0)
        case .hours(let hours)?:
            (scheduleEnabled, holdHours) = (true, max(1, hours))
        case .untilChanged?, .untilClock?:
            (scheduleEnabled, holdHours) = (false, 0)
        }

        let data = try await graphQL(
            "updateEntryLevelZone",
            document: CarrierQueries.updateEntryLevelZone,
            variables: EntryLevelZoneVariables(input: .init(
                serial: thermostat.systemSerial,
                index: Int(thermostat.zoneID) ?? 0,
                clsp: .init(current: cool),
                htsp: .init(current: heat),
                scheduleEnabled: scheduleEnabled,
                holdEndTime: holdHours
            )),
            as: EntryLevelZoneUpdateData.self
        )
        if data.updateEntryLevelZone?.success?.bool == false {
            throw CarrierError.graphQL("Carrier didn't accept the new temperature.")
        }
    }

    /// Infinity takes setpoints as text: whole degrees, or halves in Celsius.
    private static func setpointText(_ value: Double) -> String {
        let halves = (value * 2).rounded() / 2
        return halves == halves.rounded() ? String(Int(halves)) : String(halves)
    }

    // MARK: - Tokens

    private func adopt(_ newSession: CarrierSession) {
        session = newSession
        if !KeychainStore.save(newSession) {
            Log.api.error("Could not save the session to the Keychain")
        }
    }

    private func refreshTokens() async throws {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func performRefresh() async throws {
        guard let current = session, let refreshToken = current.refreshToken else {
            throw CarrierError.accessTokenExpired
        }
        let endpoint = current.tokenEndpoint.flatMap { URL(string: $0) } ?? Endpoint.oauthToken

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded([
            ("client_id", current.clientID ?? Self.defaultClientID),
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("scope", "offline_access"),
        ])

        let (data, status) = try await send(request)

        // Signed out or signed in again while the request was in flight. Leave the newer state alone.
        guard let latest = session, latest.refreshToken == refreshToken else { return }

        if status == 400 || status == 401 || status == 403 {
            let oauthError = try? decoder.decode(OAuthErrorResponse.self, from: data)
            Log.api.error("Token refresh rejected (\(status)): \(oauthError?.error ?? "unknown", privacy: .public)")
            if status != 400 || oauthError?.error == "invalid_grant" {
                throw CarrierError.sessionExpired
            }
            throw CarrierError.http(status: status)
        }
        guard (200..<300).contains(status) else { throw CarrierError.http(status: status) }

        let tokens: OAuthTokenResponse
        do {
            tokens = try decoder.decode(OAuthTokenResponse.self, from: data)
        } catch {
            Log.api.error("Could not decode token response: \(String(describing: error), privacy: .public)")
            throw CarrierError.invalidResponse
        }

        var updated = latest
        updated.accessToken = tokens.accessToken
        updated.accessTokenExpiresAt = JWTClaims(token: tokens.accessToken)?.expiresAt
            ?? Date().addingTimeInterval(tokens.expiresIn ?? 1800)
        updated.tokenType = tokens.tokenType ?? updated.tokenType
        // Okta may rotate refresh tokens. Keep the newest one.
        if let rotated = tokens.refreshToken, !rotated.isEmpty {
            updated.refreshToken = rotated
        }
        adopt(updated)
    }

    /// Only Carrier's own authorization server may receive a refresh token.
    private static func tokenEndpoint(forIssuer issuer: String?) throws -> URL {
        guard let issuer else { return Endpoint.oauthToken }
        guard let url = URL(string: issuer),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "sso.carrier.com"
        else { throw CarrierError.untrustedIssuer }
        return url.appendingPathComponent("v1").appendingPathComponent("token")
    }

    // MARK: - Transport

    private func graphQL<Variables: Encodable, Response: Decodable>(
        _ operationName: String,
        document: String,
        variables: Variables,
        as responseType: Response.Type
    ) async throws -> Response {
        let body = try encoder.encode(GraphQLRequest(operationName: operationName, query: document, variables: variables))
        var retriedAfterUnauthorized = false

        while true {
            let token = try await validAccessToken()

            var request = URLRequest(url: Endpoint.graphQL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("\(authorizationScheme) \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = body

            let (data, status) = try await send(request)

            if status == 401 || status == 403 {
                guard !retriedAfterUnauthorized else { throw CarrierError.http(status: status) }
                Log.api.notice("\(operationName, privacy: .public) was unauthorized, renewing the token")
                retriedAfterUnauthorized = true
                // Treat the token as expired so the next pass renews it, or reports it as expired.
                if session?.accessToken == token {
                    session?.accessTokenExpiresAt = .distantPast
                }
                continue
            }
            guard (200..<300).contains(status) else { throw CarrierError.http(status: status) }

            return try unwrap(data, operationName: operationName, as: responseType)
        }
    }

    private var authorizationScheme: String {
        guard let type = session?.tokenType, !type.isEmpty, type.lowercased() != "bearer" else { return "Bearer" }
        return type
    }

    private func unwrap<Response: Decodable>(
        _ data: Data,
        operationName: String,
        as responseType: Response.Type
    ) throws -> Response {
        let envelope: GraphQLResponse<Response>
        do {
            envelope = try decoder.decode(GraphQLResponse<Response>.self, from: data)
        } catch {
            Log.api.error("Could not decode \(operationName, privacy: .public): \(String(describing: error), privacy: .public)")
            throw CarrierError.invalidResponse
        }

        let messages = (envelope.errors ?? []).compactMap(\.message)
        if let payload = envelope.data {
            if !messages.isEmpty {
                Log.api.notice("\(operationName, privacy: .public) returned partial errors: \(messages.joined(separator: "; "), privacy: .public)")
            }
            return payload
        }
        throw CarrierError.graphQL(messages.isEmpty ? "\(operationName) returned no data" : messages.joined(separator: "; "))
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as URLError {
            throw CarrierError.network(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func formEncoded(_ parameters: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = parameters
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    /// Two systems can share a default name like "HVAC". Add the serial's last digits so they're distinguishable.
    private static func disambiguated(_ thermostats: [Thermostat]) -> [Thermostat] {
        let counts = Dictionary(grouping: thermostats, by: \.name).mapValues(\.count)
        return thermostats.map { thermostat in
            guard counts[thermostat.name, default: 0] > 1 else { return thermostat }
            var copy = thermostat
            copy.name += " \(thermostat.systemSerial.suffix(4))"
            return copy
        }
    }
}
