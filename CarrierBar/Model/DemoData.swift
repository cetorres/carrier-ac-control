import Foundation

extension Thermostat {
    /// Made-up units for demo mode, used for screenshots and for trying the app without an account.
    /// No real account, serial number, or location.
    static let demoUnits: [Thermostat] = [
        Thermostat(
            id: "DEMO000001#1",
            kind: .infinity,
            systemSerial: "DEMO000001",
            zoneID: "1",
            name: "Downstairs",
            isOnline: true,
            roomTemperature: 67,
            humidity: 48,
            heatSetpoint: 70,
            coolSetpoint: 76,
            mode: "heat",
            fanMode: "off",          // Infinity reports "off" when the fan runs automatically
            activity: "home",
            isOnHold: false,
            conditioning: .heating,
            conditioningDetail: "active_heat",
            outdoorTemperature: 88,
            filterUsedPercent: 35,
            model: "SYSTXCCWIC01-B",
            firmware: "4.70",
            indoorUnitStatus: "low",
            outdoorUnitStatus: "low",
            comfortProfiles: demoProfiles,
            schedule: demoSchedule
        ),
        Thermostat(
            id: "DEMO000002#1",
            kind: .infinity,
            systemSerial: "DEMO000002",
            zoneID: "1",
            name: "Upstairs",
            isOnline: true,
            roomTemperature: 75,
            humidity: 52,
            heatSetpoint: 68,
            coolSetpoint: 74,
            mode: "cool",
            fanMode: "med",
            activity: "manual",
            isOnHold: true,
            conditioning: .cooling,
            conditioningDetail: "active_cool",
            outdoorTemperature: 88,
            filterUsedPercent: 62,
            model: "SYSTXCCWIC01-B",
            firmware: "4.70",
            indoorUnitStatus: "high",
            outdoorUnitStatus: "high",
            comfortProfiles: demoProfiles,
            schedule: demoSchedule,
            holdUntil: "18:00"
        ),
    ]

    private static let demoProfiles: [ComfortProfile] = [
        ComfortProfile(id: "home", heatSetpoint: 70, coolSetpoint: 76, fanMode: "off"),
        ComfortProfile(id: "away", heatSetpoint: 62, coolSetpoint: 82, fanMode: "off"),
        ComfortProfile(id: "sleep", heatSetpoint: 66, coolSetpoint: 78, fanMode: "low"),
        ComfortProfile(id: "wake", heatSetpoint: 70, coolSetpoint: 75, fanMode: "off"),
        ComfortProfile(id: "manual", heatSetpoint: 68, coolSetpoint: 74, fanMode: "med"),
    ]

    /// Every day: wake at 6:00, away at 8:00, home at 17:00, sleep at 22:00.
    private static let demoSchedule: [SchedulePeriod] = (0...6).flatMap { weekday in
        [(6 * 60, "wake"), (8 * 60, "away"), (17 * 60, "home"), (22 * 60, "sleep")].map {
            SchedulePeriod(weekday: weekday, minute: $0.0, profileID: $0.1)
        }
    }
}
