import SwiftUI

/// One unit in the panel: name and status, the room temperature, and the details below it.
struct ThermostatCard: View {
    let thermostat: Thermostat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(thermostat.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusBadge(badge: thermostat.badge)
            }

            HStack(alignment: .center, spacing: 14) {
                Text(DisplayFormat.temperature(thermostat.roomTemperature))
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.3), value: thermostat.roomTemperature)

                VStack(alignment: .leading, spacing: 4) {
                    if let target = thermostat.targetLine {
                        Label(target.text, systemImage: target.symbol)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.2), value: target)
                    }
                    if let humidity = DisplayFormat.percent(thermostat.humidity) {
                        Label("\(humidity) humidity", systemImage: "humidity")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if thermostat.canAdjustSetpoints {
                    Spacer(minLength: 0)
                    SetpointButtons(thermostat: thermostat)
                }
            }

            if thermostat.showsScheduleControls {
                ScheduleControls(thermostat: thermostat)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                DetailRow(title: "Mode", value: thermostat.modeText)
                DetailRow(title: "Fan", value: thermostat.fanText)
                // The schedule row already says what the unit is doing.
                DetailRow(title: "Activity", value: thermostat.showsScheduleControls ? nil : thermostat.activityText)
                DetailRow(title: "Outdoor", value: thermostat.outdoorTemperature.map { DisplayFormat.temperature($0) })
                DetailRow(title: "Filter used", value: DisplayFormat.percent(thermostat.filterUsedPercent))
                DetailRow(title: "Indoor unit", value: DisplayFormat.title(thermostat.indoorUnitStatus))
                DetailRow(title: "Outdoor unit", value: DisplayFormat.title(thermostat.outdoorUnitStatus))
            }
            .font(.caption)

            if let hardware = thermostat.hardwareText {
                Text(hardware)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .opacity(thermostat.isOnline ? 1 : 0.65)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .leading)
                Text(value)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Lowers or raises the setpoint the current mode uses, one degree per click.
private struct SetpointButtons: View {
    @Environment(ThermostatStore.self) private var store
    let thermostat: Thermostat

    var body: some View {
        HStack(spacing: 6) {
            button(steps: -1, symbol: "minus", help: "Lower the temperature")
            button(steps: 1, symbol: "plus", help: "Raise the temperature")
        }
    }

    private func button(steps: Int, symbol: String, help: String) -> some View {
        Button {
            store.adjustSetpoint(of: thermostat.id, by: steps)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct StatusBadge: View {
    let badge: Thermostat.Badge

    var body: some View {
        Label(badge.title, systemImage: badge.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(badge.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badge.tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Display text

extension Thermostat {
    struct Line: Equatable {
        let text: String
        let symbol: String
    }

    struct Badge {
        let title: String
        let symbol: String
        let tint: Color
    }

    /// What the unit is aiming for, based on the system mode.
    var targetLine: Line? {
        let heat = heatSetpoint.map { DisplayFormat.temperature($0) }
        let cool = coolSetpoint.map { DisplayFormat.temperature($0) }

        switch mode?.lowercased() {
        case "cool"?:
            return cool.map { Line(text: "Cool to \($0)", symbol: "snowflake") }
        case "heat"?:
            return heat.map { Line(text: "Heat to \($0)", symbol: "flame") }
        case "auto"?:
            guard let low = heat, let high = cool else { return nil }
            return Line(text: "\(low) to \(high)", symbol: "arrow.left.and.right")
        case "off"?:
            return Line(text: "System off", symbol: "power")
        case "fanonly"?:
            return Line(text: "Fan only", symbol: "fan")
        default:
            return nil
        }
    }

    var modeText: String? {
        switch mode?.lowercased() {
        case nil:
            return nil
        case "fanonly"?:
            return "Fan only"
        default:
            return DisplayFormat.title(mode)
        }
    }

    var fanText: String? {
        switch fanMode?.lowercased() {
        case nil:
            return nil
        case "off"? where kind == .infinity:
            // Infinity reports "off" when the fan runs only with heating or cooling.
            return "Auto"
        case "med"?:
            return "Medium"
        default:
            return DisplayFormat.title(fanMode)
        }
    }

    var activityText: String {
        if let name = DisplayFormat.title(activity) {
            return isOnHold ? "\(name), on hold" : name
        }
        return isOnHold ? "On hold" : "Following schedule"
    }

    var hardwareText: String? {
        let parts = [model, firmware].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var badge: Badge {
        guard isOnline else {
            return Badge(title: "Offline", symbol: "wifi.slash", tint: .secondary)
        }
        switch conditioning {
        case .cooling:
            return Badge(title: "Cooling", symbol: "snowflake", tint: .blue)
        case .heating:
            return Badge(title: "Heating", symbol: "flame.fill", tint: .orange)
        case .idle:
            return Badge(title: "Idle", symbol: "pause.circle", tint: .secondary)
        case .unknown:
            return Badge(title: DisplayFormat.title(conditioningDetail) ?? "Unknown", symbol: "questionmark.circle", tint: .secondary)
        }
    }
}
