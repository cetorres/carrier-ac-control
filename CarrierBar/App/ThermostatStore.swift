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

    // MARK: - Session

    func signIn(username: String, password: String) async throws {
        try await client.signIn(username: username, password: password)
        try await activateSession()
    }

    /// Signs in with text pasted from a browser: the my.carrier.com session JSON or an access token.
    func signIn(sessionText: String) async throws {
        let tokens = try TokenImport.parse(sessionText)
        try await signIn(tokens: tokens)
    }

    func signIn(tokens: TokenBundle) async throws {
        try await client.importSession(tokens)
        try await activateSession()
    }

    /// Opens my.carrier.com in a window and signs in with its session as soon as one exists.
    func beginWebSignIn() {
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
        thermostats = []
        lastUpdated = nil
        username = nil
        errorMessage = message
        phase = .signedOut
        await client.signOut()
    }

    // MARK: - Refreshing

    func refresh() async {
        guard phase == .signedIn else { return }
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
            thermostats = try await client.fetchThermostats()
            lastUpdated = Date()
            errorMessage = nil
        } catch let error as CarrierError where error.isAuthFailure {
            await signOut(message: error == .notSignedIn ? nil : error.errorDescription)
        } catch {
            Log.store.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
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
                thermostats = updated
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
        guard phase == .signedIn else { return }
        Task {
            // Give the network a moment to come back after sleep.
            try? await Task.sleep(for: .seconds(5))
            guard self.phase == .signedIn else { return }
            self.startBackgroundUpdates()
            await self.refresh()
        }
    }
}
