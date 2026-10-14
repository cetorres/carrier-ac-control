import Foundation

enum DisplayFormat {
    /// "74°", or "--°" when unknown. Carrier already reports in the account's unit.
    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite, abs(value) < 1000 else { return "--°" }
        return "\(Int(value.rounded()))°"
    }

    static func percent(_ value: Double?) -> String? {
        guard let value, value.isFinite, abs(value) < 1000 else { return nil }
        return "\(Int(value.rounded()))%"
    }

    /// "6:00 PM", as a clock in `timeZone` (the thermostat's) shows it.
    static func time(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// Turns API values like "active_cool" or "low" into "Active cool" or "Low".
    static func title(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }
}
