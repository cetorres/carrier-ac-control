import AppKit
import Observation
import SwiftUI
import WebKit

/// What the web sign in window is doing, shown in its status bar.
@MainActor
@Observable
final class WebSignInState {
    enum Status: Equatable {
        case waiting
        case importing
        case failed(String)
    }

    var status: Status = .waiting
}

/// Shows my.carrier.com in a window and signs CarrierBar in with the portal's session.
///
/// The portal keeps its session in localStorage (`AUTH_DATA--1`): an access token plus a refresh
/// token for Carrier's Okta client. Once the user is signed in there, the window reads that entry,
/// hands it to the importer, and closes. The window keeps its own cookies and storage, separate
/// from Safari or Chrome.
@MainActor
final class WebSignInWindowController: NSObject, NSWindowDelegate, WKUIDelegate {
    typealias Importer = @MainActor (TokenBundle) async throws -> Void

    static let portalURL = URL(string: "https://my.carrier.com/login")!
    private static let portalHost = "my.carrier.com"
    private static let readSessionScript = """
    (() => { try { return localStorage.getItem('\(TokenImport.portalStorageKey)') || ''; } catch (e) { return ''; } })()
    """

    private let state = WebSignInState()
    private var window: NSWindow?
    private var webView: WKWebView?
    private var pollTask: Task<Void, Never>?
    private var importer: Importer?
    /// A token Carrier already refused. Skipped until the portal produces a different one.
    private var rejectedAccessToken: String?

    func show(importer: @escaping Importer) {
        self.importer = importer

        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Identify as Safari so the portal doesn't treat the window as an unsupported browser.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        webView.load(URLRequest(url: Self.portalURL))
        self.webView = webView

        state.status = .waiting
        rejectedAccessToken = nil

        let hosting = NSHostingController(rootView: WebSignInView(state: state, webView: webView) { [weak self] in
            self?.reload()
        })
        hosting.sizingOptions = [.minSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = "Sign in with my.carrier.com"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 520, height: 740))
        window.center()
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        startPolling()
    }

    // MARK: - Session pickup

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.checkForSession()
            }
        }
    }

    private func checkForSession() async {
        guard let webView,
              state.status != .importing,
              webView.url?.host?.lowercased() == Self.portalHost,
              let stored = await readStoredSession(from: webView), !stored.isEmpty,
              let tokens = try? TokenImport.parse(stored),
              tokens.accessToken != rejectedAccessToken
        else { return }

        // If the portal's token is about to expire, let the portal renew it first, so the portal
        // and CarrierBar never use the same refresh token at the same moment.
        guard let claims = JWTClaims(token: tokens.accessToken),
              claims.expiresAt.timeIntervalSinceNow > 120
        else { return }

        state.status = .importing
        do {
            try await importer?(tokens)
            finish()
        } catch {
            rejectedAccessToken = tokens.accessToken
            state.status = .failed(error.localizedDescription)
        }
    }

    private func readStoredSession(from webView: WKWebView) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(Self.readSessionScript) { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
    }

    private func reload() {
        rejectedAccessToken = nil
        state.status = .waiting
        webView?.load(URLRequest(url: Self.portalURL))
    }

    /// Stops the portal page right away so it doesn't keep renewing the session CarrierBar now owns.
    private func finish() {
        window?.close()
    }

    private func tearDown() {
        pollTask?.cancel()
        pollTask = nil
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView?.uiDelegate = nil
        webView = nil
        window?.delegate = nil
        window = nil
        importer = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        tearDown()
    }

    // MARK: - WKUIDelegate

    /// Links that open a new window (like "Forgot password") load in the same view instead.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
