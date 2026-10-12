import SwiftUI
import WebKit

/// Contents of the web sign in window: a status bar above the my.carrier.com page.
struct WebSignInView: View {
    let state: WebSignInState
    let webView: WKWebView
    let onReload: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                statusIcon
                    .frame(width: 16, height: 16)
                Text(statusText)
                    .font(.callout)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload my.carrier.com")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            WebViewContainer(webView: webView)
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state.status {
        case .waiting:
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
        case .importing:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusText: String {
        switch state.status {
        case .waiting:
            return "Sign in to your Carrier account. This window closes by itself once you're in."
        case .importing:
            return "Signed in. Loading your thermostats…"
        case .failed(let message):
            return "\(message) Sign in again on the page, or reload it."
        }
    }
}

private struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
