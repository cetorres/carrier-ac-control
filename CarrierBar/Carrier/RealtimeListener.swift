import Foundation

/// Something the realtime websocket told us about.
enum RealtimeEvent: Sendable {
    /// A partial Infinity status update that can be merged directly into the current data.
    case infinityStatus(serial: String, patch: InfinityStatusPatch)
    /// Something else changed on this device (config, Smart Thermostat state, ...). Refetch to pick it up.
    case changed(serial: String)

    static func parse(_ text: String) -> RealtimeEvent? {
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        // Some messages arrive wrapped as {"deviceId": ..., "payload": {...}}.
        var message = root
        if let payload = root["payload"] as? [String: Any] {
            message = payload
            if message["deviceId"] == nil, let envelopeDevice = root["deviceId"] {
                message["deviceId"] = envelopeDevice
            }
        }

        let messageType = message["messageType"] as? String
        if messageType == "Heartbeat" { return nil }

        guard let rawDevice = message["deviceId"] else { return nil }
        let serial = "\(rawDevice)"
        guard !serial.isEmpty else { return nil }

        switch messageType {
        case "InfinityStatus"?:
            guard let patchData = try? JSONSerialization.data(withJSONObject: message),
                  let patch = try? JSONDecoder().decode(InfinityStatusPatch.self, from: patchData)
            else { return .changed(serial: serial) }
            return .infinityStatus(serial: serial, patch: patch)
        case nil where message["name"] as? String == "diagnostic-device-info":
            // Frequent equipment diagnostics. Nothing the panel shows depends on them.
            return nil
        default:
            return .changed(serial: serial)
        }
    }
}

/// Listens to Carrier's realtime websocket and reconnects with backoff when it drops.
@MainActor
final class RealtimeListener {
    var onEvent: (@MainActor (RealtimeEvent) -> Void)?
    var onConnectionChange: (@MainActor (Bool) -> Void)?

    private let urlSession = URLSession(configuration: .default)
    private var loopTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private(set) var isConnected = false

    func start(tokenProvider: @escaping () async throws -> String) {
        stop()
        loopTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let token = try await tokenProvider()
                    try await self.listen(token: token)
                    failures = 0
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    // A drop after a healthy connection retries quickly. Repeated failures back off.
                    failures = self.isConnected ? 1 : failures + 1
                    Log.realtime.notice("Realtime connection dropped: \(error.localizedDescription, privacy: .public)")
                }
                self.setConnected(false)
                let delay = min(300.0, 5.0 * pow(2.0, Double(min(failures, 6))))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        setConnected(false)
    }

    private func listen(token: String) async throws {
        var components = URLComponents(string: "wss://realtime.infinity.iot.carrier.com/")!
        components.queryItems = [URLQueryItem(name: "Token", value: token)]
        guard let url = components.url else { throw URLError(.badURL) }

        let socket = urlSession.webSocketTask(with: url)
        self.socket = socket
        socket.resume()

        let keepalive = URLSessionWebSocketTask.Message.string(#"{"action":"keepalive"}"#)

        // Carrier expects a keepalive roughly every minute.
        let heartbeat = Task { [weak socket] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(55))
                try? await socket?.send(keepalive)
            }
        }
        defer {
            heartbeat.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            if self.socket === socket { self.socket = nil }
        }

        // The first send completes once the handshake succeeds, which confirms the token was accepted.
        try await socket.send(keepalive)
        setConnected(true)

        while !Task.isCancelled {
            let message = try await socket.receive()

            let text: String
            switch message {
            case .string(let value):
                text = value
            case .data(let value):
                text = String(decoding: value, as: UTF8.self)
            @unknown default:
                continue
            }

            if text == "close cmd" { return }
            Log.realtime.debug("Message: \(text, privacy: .public)")
            if let event = RealtimeEvent.parse(text) {
                onEvent?(event)
            }
        }
    }

    private func setConnected(_ connected: Bool) {
        guard isConnected != connected else { return }
        isConnected = connected
        onConnectionChange?(connected)
    }
}
