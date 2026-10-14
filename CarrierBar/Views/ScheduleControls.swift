import SwiftUI

/// The schedule row of a unit that has comfort profiles: what it's doing now, a menu to hold a
/// profile, when the hold ends, and a way back to the schedule.
struct ScheduleControls: View {
    @Environment(ThermostatStore.self) private var store
    let thermostat: Thermostat

    @State private var isPickingTime = false
    @State private var pickedTime = Date()

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            Label(thermostat.scheduleStatusText(now: now), systemImage: thermostat.isOnHold ? "pause.circle" : "calendar")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                if !thermostat.selectableProfiles.isEmpty {
                    profileMenu
                }
                if thermostat.isOnHold {
                    holdEndMenu(now: now)
                    if thermostat.hasSchedule {
                        Button("Resume") {
                            store.resumeSchedule(of: thermostat.id)
                        }
                        .help("End the hold and follow the schedule")
                    }
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .disabled(!thermostat.isOnline)
        }
    }

    private var profileMenu: some View {
        Menu {
            Section("Hold a Comfort Profile") {
                ForEach(thermostat.selectableProfiles) { profile in
                    // A toggle shows a checkmark on the current profile. Choosing any profile, the
                    // current one included, holds it.
                    Toggle(isOn: Binding(
                        get: { thermostat.currentProfileID == profile.id },
                        set: { _ in store.holdProfile(profile.id, of: thermostat.id) }
                    )) {
                        Text(thermostat.menuTitle(for: profile))
                    }
                }
            }
        } label: {
            Text(thermostat.currentProfileName ?? "Profile")
        }
        .fixedSize()
        .help("Hold a comfort profile")
    }

    private func holdEndMenu(now: Date) -> some View {
        Menu {
            // Smart Thermostats hold for whole hours, so only Infinity can end on a clock time.
            if thermostat.supportsClockHolds, let next = thermostat.nextScheduledChange(after: now) {
                Button("Until the Next Scheduled Change (\(time(next.date)))") {
                    store.setHoldEnd(of: thermostat.id, to: .nextScheduledChange)
                }
            }
            Section {
                ForEach([1, 2, 4, 8], id: \.self) { hours in
                    let title = hours == 1 ? "1 Hour" : "\(hours) Hours"
                    let end = thermostat.holdEndPreview(for: .hours(hours), now: now)
                    Button(end.map { "For \(title) (until \(time($0)))" } ?? "For \(title)") {
                        store.setHoldEnd(of: thermostat.id, to: .hours(hours))
                    }
                }
                if thermostat.supportsClockHolds {
                    Button("Until a Specific Time…") {
                        pickedTime = thermostat.holdEndDate(after: now)
                            ?? Thermostat.roundedToQuarterHour(now.addingTimeInterval(3600))
                        isPickingTime = true
                    }
                }
            }
            Section {
                Button("Until I Change It") {
                    store.setHoldEnd(of: thermostat.id, to: .whenChanged)
                }
            }
        } label: {
            Text(thermostat.holdEndDate(after: now).map { "Until \(time($0))" } ?? "Until changed")
        }
        .fixedSize()
        .help("Choose when the hold ends")
        .popover(isPresented: $isPickingTime, arrowEdge: .bottom) {
            timePicker
        }
    }

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Hold until", selection: $pickedTime, displayedComponents: .hourAndMinute)
            Text("Rounded to the nearest 15 minutes, in the thermostat's time.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") {
                    isPickingTime = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Hold") {
                    store.setHoldEnd(of: thermostat.id, to: .at(pickedTime))
                    isPickingTime = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 240)
        // Pick the time as the thermostat's clock shows it, which matters when the Mac is elsewhere.
        .environment(\.timeZone, thermostat.timeZone)
    }

    private func time(_ date: Date) -> String {
        DisplayFormat.time(date, in: thermostat.timeZone)
    }
}

// MARK: - Display text

extension Thermostat {
    var currentProfileName: String? {
        currentProfileID.map { profile($0)?.name ?? DisplayFormat.title($0) ?? $0 }
    }

    /// "Away until 6:00 PM, then Home", or "Holding Away until you change it".
    func scheduleStatusText(now: Date) -> String {
        let name = currentProfileName
        if isOnHold {
            let held = currentProfileID == "manual" ? "manual temperature" : (name ?? "temperature")
            let end = holdEndDate(after: now).map { "until \(DisplayFormat.time($0, in: timeZone))" } ?? "until you change it"
            return "Holding \(held) \(end)"
        }
        guard let name else { return "Following schedule" }
        guard let next = nextScheduledChange(after: now, changingFrom: currentProfileID) else {
            return "\(name), following schedule"
        }
        let nextName = profile(next.profileID)?.name ?? DisplayFormat.title(next.profileID) ?? next.profileID
        return "\(name) until \(DisplayFormat.time(next.date, in: timeZone)), then \(nextName)"
    }

    /// "Away · 64° to 82°", showing the setpoints the current mode uses.
    func menuTitle(for profile: ComfortProfile) -> String {
        let heat = profile.heatSetpoint.map { DisplayFormat.temperature($0) }
        let cool = profile.coolSetpoint.map { DisplayFormat.temperature($0) }
        let setpoints: String?
        switch mode?.lowercased() {
        case "heat"?:
            setpoints = heat
        case "cool"?:
            setpoints = cool
        default:
            setpoints = [heat, cool].compactMap { $0 }.joined(separator: " to ")
        }
        guard let setpoints, !setpoints.isEmpty else { return profile.name }
        return "\(profile.name) · \(setpoints)"
    }
}
