import SwiftUI

/// What sits in the menu bar: "74° · 72°" once data arrives, a thermometer before that.
struct MenuBarLabel: View {
    let store: ThermostatStore

    var body: some View {
        if let title = store.menuBarTitle {
            Image(systemName: "snowflake")
                .accessibilityLabel("Carrier thermostats")
            Text(title)
                .monospacedDigit()
                .accessibilityLabel(accessibilityText)
        } else {
            Image(systemName: "snowflake")
                .accessibilityLabel("Carrier thermostats")
        }
    }

    private var accessibilityText: String {
        store.thermostats
            .map { "\($0.name) \(DisplayFormat.temperature($0.roomTemperature))" }
            .joined(separator: ", ")
    }
}
