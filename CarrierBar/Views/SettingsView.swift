import AppKit
import Observation
import SwiftUI

/// Which tab the Settings window is showing.
enum SettingsTab: String, Hashable {
    case general, about
}

/// Lets the panel open Settings on a particular tab.
///
/// The window is built once and reused, so the tab can't be passed in when it opens. It has to be
/// state the window is already watching.
@MainActor
@Observable
final class SettingsSelection {
    var tab: SettingsTab = .general
}

struct SettingsView: View {
    @Environment(SettingsSelection.self) private var selection

    var body: some View {
        @Bindable var selection = selection
        TabView(selection: $selection.tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        // A TabView of Forms has no height of its own, so without this the window shrinks to almost nothing.
        .frame(width: 480, height: 400)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ThermostatStore.self) private var store

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))

                if settings.launchAtLoginNeedsApproval {
                    HStack {
                        Text("Allow CarrierBar in System Settings to finish turning this on.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Open Login Items…") {
                            settings.openLoginItemsSettings()
                        }
                    }
                }
            }

            Section("Account") {
                if store.phase == .signedIn, let username = store.username {
                    LabeledContent("Signed in as") {
                        HStack {
                            Text(username)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Button("Sign Out") {
                                Task { await store.signOut() }
                            }
                        }
                    }
                } else {
                    Text("Not signed in. Click CarrierBar in the menu bar to sign in.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = settings.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { settings.refreshLoginItem() }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .accessibilityLabel("\(AboutInfo.name) icon")
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(AboutInfo.name)
                            .font(.system(size: 18, weight: .semibold))
                        Text("Version \(AboutInfo.version) (\(AboutInfo.build))")
                            .foregroundStyle(.secondary)
                    }
                }

                Text(AboutInfo.appInfo)

                LabeledContent {
                    AboutLink("Carlos E. Torres", destination: AboutInfo.authorURL)
                } label: {
                    Label("Author", systemImage: "person.circle.fill")
                }
                LabeledContent {
                    AboutLink("Visit website", destination: AboutInfo.appURL)
                } label: {
                    Label("More info", systemImage: "info.circle.fill")
                }
                LabeledContent {
                    AboutLink("Get in touch", destination: AboutInfo.contactURL)
                } label: {
                    Label("Questions, bugs, suggestions?", systemImage: "questionmark.circle.fill")
                }
                LabeledContent {
                    AboutLink("Support the author", destination: AboutInfo.supportURL)
                } label: {
                    Label("Love the app?", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                }
            } footer: {
                VStack(spacing: 4) {
                    Text(AboutInfo.disclaimer)
                    Text("© \(Date.now.formatted(.dateTime.year())) \(AboutInfo.copyrightHolder)")
                }
                .multilineTextAlignment(.center)
            }
        }
        .formStyle(.grouped)
    }
}

/// A link that shows the pointing hand while the pointer is over it.
private struct AboutLink: View {
    let title: String
    let destination: URL

    init(_ title: String, destination: URL) {
        self.title = title
        self.destination = destination
    }

    var body: some View {
        Link(title, destination: destination)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
