import AppKit
import Observation

/// App state: session, thermostats, and how they stay fresh.
///
/// Freshness comes from three sources: a full fetch on launch and on demand, live patches from
/// Carrier's realtime websocket, and a slow poll as a safety net (faster when the websocket is down).
@MainActor
@Observable
final class ThermostatStore {
    enum Phase: Equatable {
        case starting
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .starting
    private(set) var thermostats: [Thermostat] = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var isLive = false
    private(set) var username: String?

    private let client = CarrierClient()
    private let realtime = RealtimeListener()
    private let webSignIn = WebSignInWindowController()

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var setpointEdits: [Thermostat.ID: SetpointEdit] = [:]
    @ObservationIgnored private var setpointSends: [Thermostat.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var holdEdits: [Thermostat.ID: HoldEdit] = [:]

    /// A setpoint change made here that Carrier may not report back yet.
    private struct SetpointEdit: Equatable {
        let heat: Double
        let cool: Double
        var hold: Thermostat.HoldLength
        var sentAt: Date?
    }

    /// A hold or resume made here that Carrier may not report back yet.
    fileprivate struct HoldEdit: Equatable {
        /// The profile to hold, or nil to resume the schedule.
        let profileID: String?
        let hold: Thermostat.HoldLength
        var sentAt: Date?
    }

    /// Temperatures for the menu bar, in panel order. Nil until there is data to show.
    var menuBarTitle: String? {
        guard !thermostats.isEmpty else { return nil }
        return thermostats
            .map { DisplayFormat.temperature($0.roomTemperature) }
            .joined(separator: "·")
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        realtime.onEvent = { [weak self] event in
            self?.handle(event)
        }
        realtime.onConnectionChange = { [weak self] connected in
            self?.isLive = connected
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }

        Task { await bootstrap() }
    }

    private func bootstrap() async {
        if isDemo {
            loadDemo()
            return
        }
        guard let session = KeychainStore.load() else {
            phase = .signedOut
            return
        }
        await client.restore(session)
        username = session.username
        phase = .signedIn
        await refresh()
        if phase == .signedIn {
            startBackgroundUpdates()
        }
    }

    // MARK: - Demo mode

    /// Shows sample data instead of a real account, for screenshots and for trying the app.
    /// Turn it on with the launch argument `-DemoMode YES` (the "CarrierBar Demo" scheme does this).
    /// Demo mode never reads, writes, or deletes the saved session, and makes no network requests.
    private let isDemo = UserDefaults.standard.bool(forKey: "DemoMode")

    private func loadDemo() {
        thermostats = Thermostat.demoUnits
        username = "demo@example.com"
        lastUpdated = Date()
        errorMessage = nil
        isLive = true
        phase = .signedIn
    }

    // MARK: - Session

    func signIn(username: String, password: String) async throws {
        if isDemo { return loadDemo() }
        try await client.signIn(username: username, password: password)
        try await activateSession()
    }

    /// Signs in with text pasted from a browser: the my.carrier.com session JSON or an access token.
    func signIn(sessionText: String) async throws {
        if isDemo { return loadDemo() }
        let tokens = try TokenImport.parse(sessionText)
        try await signIn(tokens: tokens)
    }

    func signIn(tokens: TokenBundle) async throws {
        if isDemo { return loadDemo() }
        try await client.importSession(tokens)
        try await activateSession()
    }

    /// Opens my.carrier.com in a window and signs in with its session as soon as one exists.
    func beginWebSignIn() {
        if isDemo { return loadDemo() }
        webSignIn.show { [weak self] tokens in
            guard let self else { return }
            try await self.signIn(tokens: tokens)
        }
    }

    /// Confirms a new session works by loading the thermostats, then starts live updates.
    /// If loading fails, the session is discarded and the error goes back to the sign in screen.
    private func activateSession() async throws {
        do {
            let loaded = try await client.fetchThermostats()
            thermostats = loaded
            lastUpdated = Date()
            username = await client.username
            errorMessage = nil
            phase = .signedIn
            startBackgroundUpdates()
        } catch {
            await client.signOut()
            throw error
        }
    }

    func signOut() async {
        await signOut(message: nil)
    }

    private func signOut(message: String?) async {
        stopBackgroundUpdates()
        setpointSends.values.forEach { $0.cancel() }
        setpointSends = [:]
        setpointEdits = [:]
        holdEdits = [:]
        thermostats = []
        lastUpdated = nil
        username = nil
        errorMessage = message
        phase = .signedOut
        // Demo mode has no session of its own, so leave any real one in the Keychain alone.
        if !isDemo {
            await client.signOut()
        }
    }

    // MARK: - Refreshing

    func refresh() async {
        guard phase == .signedIn else { return }
        if isDemo {
            lastUpdated = Date()
            return
        }
        guard !isRefreshing else {
            // A refresh is already running. Run once more when it finishes so nothing is missed.
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshQueued = false
            await performRefresh()
        } while refreshQueued && phase == .signedIn
    }

    /// Used when the panel opens, so it never shows stale data for long.
    func refreshIfStale(maxAge: TimeInterval = 60) {
        guard phase == .signedIn else { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge { return }
        Task { await refresh() }
    }

    private func performRefresh() async {
        do {
            thermostats = withPendingEdits(try await client.fetchThermostats())
            lastUpdated = Date()
            errorMessage = nil
        } catch let error as CarrierError where error.isAuthFailure {
            await signOut(message: error == .notSignedIn ? nil : error.errorDescription)
        } catch {
            Log.store.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Control

    /// Nudges a unit's setpoint by whole degrees. The panel updates right away. The change is sent
    /// once the taps pause, so several quick taps become a single request.
    /// The hold lasts as long as `Thermostat.defaultHoldLength` says.
    func adjustSetpoint(of id: Thermostat.ID, by steps: Int) {
        guard phase == .signedIn, let index = thermostats.firstIndex(where: { $0.id == id }) else { return }
        var thermostat = thermostats[index]
        let hold = thermostat.defaultHoldLength
        guard thermostat.adjustSetpoints(by: steps, until: hold),
              let heat = thermostat.heatSetpoint,
              let cool = thermostat.coolSetpoint
        else { return }
        thermostats[index] = thermostat
        if isDemo { return }

        // This replaces any profile hold still on its way.
        holdEdits[id] = nil
        setpointEdits[id] = SetpointEdit(heat: heat, cool: cool, hold: hold)
        setpointSends[id]?.cancel()
        setpointSends[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            self.setpointSends[id] = nil
            await self.sendSetpoints(of: id)
        }
    }

    private func sendSetpoints(of id: Thermostat.ID) async {
        guard let edit = setpointEdits[id],
              let thermostat = thermostats.first(where: { $0.id == id })
        else { return }

        do {
            try await client.setSetpoints(of: thermostat, heat: edit.heat, cool: edit.cool, hold: edit.hold)
            // Keep showing the new values until Carrier reports them, which can take a little while.
            if setpointEdits[id] == edit {
                setpointEdits[id]?.sentAt = Date()
            }
            errorMessage = nil
        } catch let error as CarrierError where error.isAuthFailure {
            await signOut(message: error == .notSignedIn ? nil : error.errorDescription)
            return
        } catch {
            Log.store.error("Setpoint change failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't change \(thermostat.name): \(error.localizedDescription)"
            // Show what the unit is really set to, unless a newer change is already on its way.
            if setpointEdits[id] == edit {
                setpointEdits[id] = nil
            }
        }
        scheduleRefresh()
    }

    /// Holds a zone in a comfort profile, for as long as `Thermostat.defaultHoldLength` says.
    func holdProfile(_ profileID: String, of id: Thermostat.ID) {
        guard let thermostat = thermostats.first(where: { $0.id == id }) else { return }
        discardSetpointEdit(of: id)
        changeHold(of: id, to: HoldEdit(profileID: profileID, hold: thermostat.defaultHoldLength))
    }

    /// Changes when the current hold ends, keeping the profile or manual temperature it holds.
    func setHoldEnd(of id: Thermostat.ID, to end: Thermostat.HoldEnd) {
        guard let index = thermostats.firstIndex(where: { $0.id == id }),
              thermostats[index].isOnHold,
              let profileID = thermostats[index].currentProfileID
        else { return }
        let hold = thermostats[index].holdLength(for: end)

        // A temperature change still waiting to go out carries the new end with it.
        if setpointEdits[id] != nil {
            setpointEdits[id]?.hold = hold
            if setpointSends[id] != nil {
                thermostats[index].applyHoldLength(hold)
                return
            }
        }
        changeHold(of: id, to: HoldEdit(profileID: profileID, hold: hold))
    }

    /// Ends a hold so the zone follows its schedule again.
    func resumeSchedule(of id: Thermostat.ID) {
        discardSetpointEdit(of: id)
        changeHold(of: id, to: HoldEdit(profileID: nil, hold: .untilChanged))
    }

    /// Shows a hold change right away, then sends it.
    private func changeHold(of id: Thermostat.ID, to edit: HoldEdit) {
        guard phase == .signedIn, let index = thermostats.firstIndex(where: { $0.id == id }) else { return }
        thermostats[index].apply(edit)
        if isDemo { return }

        holdEdits[id] = edit
        Task { await sendHold(of: id, edit) }
    }

    private func sendHold(of id: Thermostat.ID, _ edit: HoldEdit) async {
        guard let thermostat = thermostats.first(where: { $0.id == id }) else { return }

        do {
            if let profileID = edit.profileID {
                try await client.hold(thermostat, in: profileID, until: edit.hold)
            } else {
                try await client.resumeSchedule(of: thermostat)
            }
            if holdEdits[id] == edit {
                holdEdits[id]?.sentAt = Date()
            }
            errorMessage = nil
        } catch let error as CarrierError where error.isAuthFailure {
            await signOut(message: error == .notSignedIn ? nil : error.errorDescription)
            return
        } catch {
            Log.store.error("Hold change failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't change \(thermostat.name): \(error.localizedDescription)"
            if holdEdits[id] == edit {
                holdEdits[id] = nil
            }
        }
        scheduleRefresh()
    }

    /// Drops a temperature change made here, including one still waiting to be sent, because a
    /// profile hold or resume replaces it.
    private func discardSetpointEdit(of id: Thermostat.ID) {
        setpointSends[id]?.cancel()
        setpointSends[id] = nil
        setpointEdits[id] = nil
    }

    /// Lays changes made here over fetched data until Carrier reports them, so the panel doesn't
    /// jump back to the old setpoint or hold while the system catches up.
    private func withPendingEdits(_ fetched: [Thermostat]) -> [Thermostat] {
        guard !setpointEdits.isEmpty || !holdEdits.isEmpty else { return fetched }
        return fetched.map { thermostat in
            var copy = thermostat

            if let edit = holdEdits[thermostat.id] {
                let confirmed = edit.profileID.map {
                    copy.isOnHold && copy.currentProfileID == $0 && copy.currentHoldLength == edit.hold
                } ?? !copy.isOnHold
                if confirmed || Self.isExpired(edit.sentAt) {
                    holdEdits[thermostat.id] = nil
                } else {
                    copy.apply(edit)
                }
            }

            if let edit = setpointEdits[thermostat.id] {
                let confirmed = copy.heatSetpoint == edit.heat && copy.coolSetpoint == edit.cool
                if confirmed || Self.isExpired(edit.sentAt) {
                    setpointEdits[thermostat.id] = nil
                } else {
                    copy.applyHeldSetpoints(heat: edit.heat, cool: edit.cool, until: edit.hold)
                }
            }
            return copy
        }
    }

    /// Carrier normally reports a change within seconds. After this long, trust what it reports.
    private static func isExpired(_ sentAt: Date?) -> Bool {
        sentAt.map { Date().timeIntervalSince($0) > 90 } ?? false
    }

    // MARK: - Background updates

    private func startBackgroundUpdates() {
        stopBackgroundUpdates()

        let client = self.client
        realtime.start(tokenProvider: {
            try await client.validAccessToken()
        })

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: Duration = (self?.isLive ?? false) ? .seconds(300) : .seconds(60)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }

    private func stopBackgroundUpdates() {
        realtime.stop()
        pollTask?.cancel()
        pollTask = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        isLive = false
    }

    private func handle(_ event: RealtimeEvent) {
        switch event {
        case .infinityStatus(let serial, let patch):
            var updated = thermostats
            var matched = false
            for index in updated.indices
            where updated[index].kind == .infinity && updated[index].systemSerial == serial {
                updated[index].apply(patch)
                matched = true
            }
            if matched {
                thermostats = withPendingEdits(updated)
                lastUpdated = Date()
            } else {
                scheduleRefresh()
            }
        case .changed:
            scheduleRefresh()
        }
    }

    /// Coalesces bursts of realtime messages into a single fetch.
    private func scheduleRefresh() {
        guard pendingRefresh == nil else { return }
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            self.pendingRefresh = nil
            await self.refresh()
        }
    }

    private func handleWake() {
        guard phase == .signedIn, !isDemo else { return }
        Task {
            // Give the network a moment to come back after sleep.
            try? await Task.sleep(for: .seconds(5))
            guard self.phase == .signedIn else { return }
            self.startBackgroundUpdates()
            await self.refresh()
        }
    }
}

private extension Thermostat {
    mutating func apply(_ edit: ThermostatStore.HoldEdit) {
        if let profileID = edit.profileID {
            applyHold(of: profileID, until: edit.hold)
        } else {
            applyResume()
        }
    }
}
