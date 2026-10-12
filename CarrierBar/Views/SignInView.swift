import AppKit
import SwiftUI

/// Shown until there is a saved session. Three ways in:
/// - Web: sign in at my.carrier.com in a CarrierBar window, and the session is picked up automatically
/// - Token: reuse the session from a browser that's already signed in to my.carrier.com
/// - Password: Carrier account email and password, used once and never stored
struct SignInView: View {
    enum Method: String, CaseIterable, Identifiable {
        case web = "Web"
        case token = "Token"
        case password = "Password"

        var id: Self { self }
    }

    @Environment(ThermostatStore.self) private var store
    @AppStorage("signInMethod") private var method: Method = .web

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to Carrier")
                .font(.headline)

            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Sign in with", selection: $method) {
                ForEach(Method.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch method {
            case .web:
                WebSignInSection()
            case .token:
                TokenSignInSection()
            case .password:
                PasswordSignInSection()
            }

            Divider()

            Button("Quit CarrierBar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(14)
    }
}

// MARK: - Web

private struct WebSignInSection: View {
    @Environment(ThermostatStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in at my.carrier.com in a CarrierBar window. The session is picked up as soon as you're in, and the window closes by itself.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Text("This window doesn't share your browser's sign in. To reuse that one, choose Token.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Open my.carrier.com") {
                    store.beginWebSignIn()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Token

private struct TokenSignInSection: View {
    @Environment(ThermostatStore.self) private var store

    @State private var text = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var copiedCommand = false

    private var canSubmit: Bool {
        !isWorking && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Already signed in at my.carrier.com? On that page, open the browser's JavaScript console, run this command, and paste the result below.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(TokenImport.consoleCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button {
                    copyCommand()
                } label: {
                    Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy command")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            TextField("Paste the result, or an access token", text: $text, axis: .vertical)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            Text("Afterwards, close that browser tab without signing out, so the browser and CarrierBar don't take turns renewing the same session. A bare access token works too, but only until it expires, about 30 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Paste from Clipboard") {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        text = clipboard
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Button("Use Session", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
    }

    private func copyCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(TokenImport.consoleCommand, forType: .string)
        copiedCommand = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedCommand = false
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        let pasted = text

        Task {
            do {
                try await store.signIn(sessionText: pasted)
                text = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

// MARK: - Password

private struct PasswordSignInSection: View {
    @Environment(ThermostatStore.self) private var store

    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isWorking && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Use the account from the Carrier SmartHome app. The password is used once and never stored.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Email", text: $username)
                .textContentType(.username)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Button("Sign In", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        let name = username.trimmingCharacters(in: .whitespaces)
        let secret = password

        Task {
            do {
                try await store.signIn(username: name, password: secret)
                password = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
