import SwiftUI

@main
struct CarrierBarApp: App {
    @State private var store: ThermostatStore
    @State private var settings = AppSettings()
    @State private var settingsSelection = SettingsSelection()

    init() {
        let store = ThermostatStore()
        store.start()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
                .environment(settingsSelection)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        // A Settings scene rather than a plain window: only there does a TabView get the standard
        // toolbar style tabs, with icons and a window title that follows the selected tab.
        Settings {
            SettingsView()
                .environment(store)
                .environment(settings)
                .environment(settingsSelection)
        }
    }
}
