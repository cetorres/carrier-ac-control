import AppKit
import SwiftUI

/// The gear at the bottom of the panel: Settings, About, Sign Out, and Quit.
struct PanelMenu: View {
    @Environment(ThermostatStore.self) private var store
    @Environment(SettingsSelection.self) private var selection
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            Button("Settings…") { showSettings(.general) }
            Button("About \(AboutInfo.name)") { showSettings(.about) }
            if store.phase == .signedIn {
                Divider()
                Button("Sign Out") {
                    Task { await store.signOut() }
                }
            }
            Divider()
            Button("Quit \(AboutInfo.name)") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings and more")
        .accessibilityLabel("Settings and more")
    }

    /// The app has no Dock icon, so it's activated first, or the window would open behind the frontmost app.
    private func showSettings(_ tab: SettingsTab) {
        selection.tab = tab
        NSApp.activate()
        openSettings()
    }
}
