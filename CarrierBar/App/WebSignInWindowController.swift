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
/// hands it to the importer, and closes. Each window starts with empty, in-memory cookies and
/// storage, separate from Safari or Chrome. A kept session would go stale once CarrierBar renews
/// its refresh token, and the portal signs out when it fails to renew that stale session.
@MainActor
final class WebSignInWindowController: NSObject, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate {
    typealias Importer = @MainActor (TokenBundle) async throws -> Void

    static let portalURL = URL(string: "https://my.carrier.com/login")!
    private static let portalHost = "my.carrier.com"
    private static let readSessionScript = """
    (() => { try { return localStorage.getItem('\(TokenImport.portalStorageKey)') || ''; } catch (e) { return ''; } })()
    """

    private let state = WebSignInState()
    private var window: NSWindow?
    private var webView: WKWebView?
    /// The Google or Apple sign in popup the portal opened, if any.
    private var popupWindow: NSWindow?
    private var popupWebView: WKWebView?
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
        configuration.websiteDataStore = .nonPersistent()
        // Identify as Safari so the portal doesn't treat the window as an unsupported browser.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        #if DEBUG
        // Lets Safari's Develop menu inspect the portal page.
        webView.isInspectable = true
        #endif
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
            Log.web.error("Portal session import failed: \(error.localizedDescription, privacy: .public)")
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
        popupWindow?.close()
        pollTask?.cancel()
        pollTask = nil
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView?.uiDelegate = nil
        webView?.navigationDelegate = nil
        webView = nil
        window?.delegate = nil
        window = nil
        importer = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === popupWindow {
            // Closing the popup ends the page's sign in attempt. The portal sees it as closed and stops waiting.
            popupWebView?.stopLoading()
            popupWebView?.uiDelegate = nil
            popupWebView?.navigationDelegate = nil
            popupWebView = nil
            popupWindow?.delegate = nil
            popupWindow = nil
        } else if closing === window {
            tearDown()
        }
    }

    // MARK: - WKNavigationDelegate

    /// Logs every request, including redirects and frames inside the page, where sign in errors
    /// come back. Query strings are left out because they carry codes and tokens.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let frame = navigationAction.targetFrame?.isMainFrame == false ? "frame" : "page"
        Log.web.info("Going to \(Self.describe(navigationAction.request.url), privacy: .public) (\(frame, privacy: .public))")
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.web.info("Loaded \(Self.describe(webView.url), privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.web.error("Load failed at \(Self.describe(webView.url), privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.web.error("Load failed at \(Self.describe(webView.url), privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        Log.web.info("Redirected to \(Self.describe(webView.url), privacy: .public)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.web.error("Web content process ended, reloading")
        if webView === popupWebView {
            // Reloading the popup alone can't finish sign in, because the portal page holds the state.
            popupWindow?.close()
        } else {
            webView.reload()
        }
    }

    private static func describe(_ url: URL?) -> String {
        guard let url else { return "(no URL)" }
        var text = "\(url.host ?? "")\(url.path)"
        // OAuth errors are safe to show. Everything else in the query may be a code or token.
        let items = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            + (URLComponents(string: "?" + (url.fragment ?? ""))?.queryItems ?? [])
        if !items.isEmpty {
            text += " [\(items.map(\.name).joined(separator: ","))]"
        }
        let errors = items.filter { $0.name == "error" || $0.name == "error_description" }
        if !errors.isEmpty {
            text += " " + errors.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: " ")
        }
        return text
    }

    // MARK: - WKUIDelegate

    /// Opens pages the portal opens with `window.open` in a real popup window. Google and Apple sign
    /// in run in a popup that the portal watches for the redirect, then reads the code from and
    /// closes, so the portal page has to stay loaded and keep its handle to the popup.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // One popup at a time. A popup opening another loads it in place.
        if let popupWebView {
            popupWebView.load(navigationAction.request)
            popupWindow?.makeKeyAndOrderFront(nil)
            return nil
        }

        // WebKit requires the popup to use the configuration it passes in.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        popup.navigationDelegate = self
        #if DEBUG
        popup.isInspectable = true
        #endif

        let size = NSSize(
            width: windowFeatures.width.map { CGFloat(truncating: $0) } ?? 500,
            height: windowFeatures.height.map { CGFloat(truncating: $0) } ?? 680
        )
        let popupWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        popupWindow.title = "Sign in"
        popupWindow.contentView = popup
        popupWindow.isReleasedWhenClosed = false
        popupWindow.delegate = self
        if let window {
            // Centered over the sign in window, like a browser popup.
            let frame = window.frame
            popupWindow.setFrameOrigin(NSPoint(
                x: frame.midX - popupWindow.frame.width / 2,
                y: frame.midY - popupWindow.frame.height / 2
            ))
        } else {
            popupWindow.center()
        }
        popupWindow.makeKeyAndOrderFront(nil)

        self.popupWebView = popup
        self.popupWindow = popupWindow
        return popup
    }

    /// The portal calls `close()` on the popup once it has the code.
    func webViewDidClose(_ webView: WKWebView) {
        if webView === popupWebView {
            popupWindow?.close()
        }
    }
}
