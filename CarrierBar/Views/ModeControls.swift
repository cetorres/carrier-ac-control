import SwiftUI

/// The mode and fan row of a unit: a menu for each, showing the current setting.
struct ModeControls: View {
    @Environment(ThermostatStore.self) private var store
    let thermostat: Thermostat

    var body: some View {
        HStack(spacing: 6) {
            if thermostat.mode != nil {
                menu(
                    title: "Mode",
                    value: thermostat.modeText,
                    current: thermostat.mode,
                    options: thermostat.modeOptions,
                    // Infinity has one mode for the whole system, so every zone changes with it.
                    help: thermostat.kind == .infinity ? "Change the mode of the whole system" : "Change the mode"
                ) { store.setMode(of: thermostat.id, to: $0) }
            }
            if thermostat.fanMode != nil {
                menu(
                    title: "Fan",
                    value: thermostat.fanText,
                    current: thermostat.fanMode,
                    options: thermostat.fanOptions,
                    help: "Change how the fan runs"
                ) { store.setFanMode(of: thermostat.id, to: $0) }
            }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .disabled(!thermostat.isOnline)
    }

    private func menu(
        title: String,
        value: String?,
        current: String?,
        options: [Thermostat.ControlOption],
        help: String,
        choose: @escaping (String) -> Void
    ) -> some View {
        Menu {
            Section(title) {
                ForEach(options) { option in
                    // A toggle shows a checkmark on the current setting. Choosing it again does nothing.
                    Toggle(isOn: Binding(
                        get: { current?.lowercased() == option.id },
                        set: { _ in
                            if current?.lowercased() != option.id {
                                choose(option.id)
                            }
                        }
                    )) {
                        Label(option.title, systemImage: option.symbol)
                    }
                }
            }
        } label: {
            Text("\(title): \(value ?? "--")")
        }
        .fixedSize()
        .help(help)
    }
}
