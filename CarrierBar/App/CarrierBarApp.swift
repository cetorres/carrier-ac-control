import SwiftUI

@main
struct CarrierBarApp: App {
    @State private var store: ThermostatStore

    init() {
        let store = ThermostatStore()
        store.start()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
