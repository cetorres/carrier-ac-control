import Foundation

// MARK: - Comfort profiles and schedule

extension Thermostat {
    /// A comfort profile. Infinity calls these activities and Smart Thermostats call them scenes:
    /// "wake", "home", "away" and "sleep", plus Infinity's "manual" and "vacation".
    struct ComfortProfile: Identifiable, Equatable, Sendable {
        let id: String
        var heatSetpoint: Double?
        var coolSetpoint: Double?
        var fanMode: String?

        var name: String { DisplayFormat.title(id) ?? id }
    }

    /// A point in the weekly schedule where a profile starts.
    struct SchedulePeriod: Equatable, Sendable {
        /// Day of the week, 0 for Sunday through 6 for Saturday.
        let weekday: Int
        /// Minutes after midnight, in the system's time zone.
        let minute: Int
        let profileID: String
    }

    /// How long someone wants a hold to last.
    enum HoldEnd: Hashable, Sendable {
        case whenChanged
        case nextScheduledChange
        case hours(Int)
        case at(Date)
    }

    /// How long a hold lasts, in the form the unit's API takes.
    enum HoldLength: Equatable, Sendable {
        case untilChanged
        /// Infinity: until this time, "HH:MM" in the system's time.
        case untilClock(String)
        /// Smart Thermostats: for this many whole hours.
        case hours(Int)

        /// Infinity's hold end time, or nil to hold until changed.
        var clockText: String? {
            if case .untilClock(let text) = self { return text }
            return nil
        }
    }

    /// Whether the card shows the schedule row: the unit has comfort profiles or a schedule.
    var showsScheduleControls: Bool {
        !selectableProfiles.isEmpty || hasSchedule
    }

    var hasSchedule: Bool { !schedule.isEmpty }

    /// Infinity holds end at a time of day. Smart Thermostats only hold for whole hours.
    var supportsClockHolds: Bool { kind == .infinity }

    /// Profiles someone can choose to hold. Manual is what the − and + buttons set, and vacation
    /// has its own settings on the thermostat.
    var selectableProfiles: [ComfortProfile] {
        comfortProfiles.filter { $0.id != "manual" && $0.id != "vacation" }
    }

    var currentProfileID: String? { activity?.lowercased() }

    func profile(_ id: String) -> ComfortProfile? {
        comfortProfiles.first { $0.id == id }
    }

    /// The selectable profile with exactly these setpoints.
    func profileID(matchingHeat heat: Double, cool: Double) -> String? {
        selectableProfiles.first { $0.heatSetpoint == heat && $0.coolSetpoint == cool }?.id
    }

    // MARK: Schedule math

    /// The profile the schedule calls for at `date`.
    func scheduledProfileID(at date: Date) -> String? {
        for offset in stride(from: 0, through: -7, by: -1) {
            if let start = periodStarts(dayOffset: offset, from: date).last(where: { $0.date <= date }) {
                return start.period.profileID
            }
        }
        return nil
    }

    /// The next time the schedule starts a period after `date`. With `profileID`, periods that
    /// keep that same profile are skipped.
    func nextScheduledChange(after date: Date, changingFrom profileID: String? = nil) -> (date: Date, profileID: String)? {
        for offset in 0...7 {
            if let start = periodStarts(dayOffset: offset, from: date)
                .first(where: { $0.date > date && $0.period.profileID != profileID }) {
                return (start.date, start.period.profileID)
            }
        }
        return nil
    }

    // MARK: Holds

    /// How long the current hold lasts, as the unit reports it.
    var currentHoldLength: HoldLength {
        guard isOnHold else { return .untilChanged }
        switch kind {
        case .infinity:
            return holdUntil.map(HoldLength.untilClock) ?? .untilChanged
        case .smartThermostat:
            return holdHours.map(HoldLength.hours) ?? .untilChanged
        }
    }

    /// When the current hold ends, or nil when it's held until changed.
    func holdEndDate(after date: Date) -> Date? {
        switch currentHoldLength {
        case .untilChanged:
            return nil
        case .untilClock(let text):
            return nextOccurrence(of: text, after: date)
        case .hours:
            return holdEndsAt
        }
    }

    /// What to send Carrier for a hold end. Infinity holds end on a quarter hour, so its times are
    /// rounded to one. Smart Thermostats get whole hours, rounded up.
    func holdLength(for end: HoldEnd, now: Date = Date()) -> HoldLength {
        let date: Date
        switch end {
        case .whenChanged:
            return .untilChanged
        case .nextScheduledChange:
            guard let next = nextScheduledChange(after: now) else { return .untilChanged }
            date = next.date
        case .hours(let hours):
            if kind == .smartThermostat { return .hours(max(1, hours)) }
            date = now.addingTimeInterval(Double(hours) * 3600)
        case .at(let chosen):
            date = chosen
        }

        switch kind {
        case .infinity:
            let parts = scheduleCalendar.dateComponents([.hour, .minute], from: Self.roundedToQuarterHour(date))
            return .untilClock(Self.clockText(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
        case .smartThermostat:
            return .hours(max(1, Int((date.timeIntervalSince(now) / 3600).rounded(.up))))
        }
    }

    /// When a hold for `end` would end, for showing in menus.
    func holdEndPreview(for end: HoldEnd, now: Date = Date()) -> Date? {
        switch holdLength(for: end, now: now) {
        case .untilChanged:
            return nil
        case .untilClock(let text):
            return nextOccurrence(of: text, after: now)
        case .hours(let hours):
            return now.addingTimeInterval(Double(hours) * 3600)
        }
    }

    /// The length a new hold gets. An existing hold keeps its end. Otherwise an Infinity hold
    /// lasts until the next scheduled change, as it does when the temperature is changed on the
    /// thermostat itself, and a Smart Thermostat holds until changed.
    var defaultHoldLength: HoldLength {
        if isOnHold {
            // A Smart Thermostat restarts its countdown with each change. Keep about the time that's left.
            if kind == .smartThermostat, let end = holdEndsAt {
                return .hours(max(1, Int((end.timeIntervalSinceNow / 3600).rounded(.up))))
            }
            return currentHoldLength
        }
        return kind == .infinity ? holdLength(for: .nextScheduledChange) : .untilChanged
    }

    static func roundedToQuarterHour(_ date: Date) -> Date {
        let quarter: TimeInterval = 15 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / quarter).rounded() * quarter)
    }

    private var scheduleCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The next time the system's clock reads `text` ("HH:MM") after `date`.
    private func nextOccurrence(of text: String, after date: Date) -> Date? {
        guard let minutes = Self.minutes(fromClock: text) else { return nil }
        let calendar = scheduleCalendar
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let time = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  time > date
            else { continue }
            return time
        }
        return nil
    }

    /// The schedule's periods on the day `dayOffset` days from `date`, with their start times, in order.
    private func periodStarts(dayOffset: Int, from date: Date) -> [(date: Date, period: SchedulePeriod)] {
        let calendar = scheduleCalendar
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)) else { return [] }
        let weekday = calendar.component(.weekday, from: day) - 1
        return schedule
            .filter { $0.weekday == weekday }
            .compactMap { period in
                calendar.date(bySettingHour: period.minute / 60, minute: period.minute % 60, second: 0, of: day)
                    .map { ($0, period) }
            }
    }

    // MARK: Local changes

    /// Shows the unit held in a profile, as it reports itself after the change.
    mutating func applyHold(of profileID: String, until hold: HoldLength) {
        isOnHold = true
        activity = profileID
        applyHoldLength(hold)
        // Manual keeps whatever was set by hand. Other profiles bring their own setpoints.
        guard profileID != "manual", let profile = profile(profileID) else { return }
        applySetpoints(of: profile)
    }

    /// Shows the unit back on its schedule, in whatever profile the schedule calls for now.
    mutating func applyResume(at date: Date = Date()) {
        isOnHold = false
        applyHoldLength(.untilChanged)
        guard let scheduled = scheduledProfileID(at: date) else { return }
        activity = scheduled
        if let profile = profile(scheduled) {
            applySetpoints(of: profile)
        }
    }

    mutating func applyHoldLength(_ hold: HoldLength, now: Date = Date()) {
        holdUntil = hold.clockText
        if case .hours(let hours) = hold {
            holdHours = hours
            holdEndsAt = now.addingTimeInterval(Double(hours) * 3600)
        } else {
            holdHours = nil
            holdEndsAt = nil
        }
    }

    private mutating func applySetpoints(of profile: ComfortProfile) {
        heatSetpoint = profile.heatSetpoint ?? heatSetpoint
        coolSetpoint = profile.coolSetpoint ?? coolSetpoint
        fanMode = profile.fanMode ?? fanMode
    }
}

// MARK: - Mapping from the API

extension Thermostat {
    private static let profileOrder = ["home", "away", "sleep", "wake", "manual", "vacation"]

    private static func sortedProfiles(_ profiles: [ComfortProfile]) -> [ComfortProfile] {
        profiles.sorted {
            (profileOrder.firstIndex(of: $0.id) ?? profileOrder.count) < (profileOrder.firstIndex(of: $1.id) ?? profileOrder.count)
        }
    }

    static func comfortProfiles(from activities: [InfinitySystemDTO.Activity]?) -> [ComfortProfile] {
        sortedProfiles((activities ?? []).compactMap { activity -> ComfortProfile? in
            guard let id = (activity.type?.string ?? activity.id?.string)?.lowercased() else { return nil }
            return ComfortProfile(
                id: id,
                heatSetpoint: activity.htsp?.double,
                coolSetpoint: activity.clsp?.double,
                fanMode: activity.fan?.string
            )
        })
    }

    /// Smart Thermostats have a fixed set of scenes. Ones that aren't set up are null.
    static func comfortProfiles(from profile: EntryLevelSystemDTO.ComfortProfile?) -> [ComfortProfile] {
        guard let profile else { return [] }
        let scenes: [(String, EntryLevelSystemDTO.ComfortProfileItem?)] = [
            ("home", profile.home), ("away", profile.away), ("sleep", profile.sleep), ("wake", profile.wake),
        ]
        return scenes.compactMap { id, item in
            guard let item, item.htsp?.double != nil || item.clsp?.double != nil else { return nil }
            return ComfortProfile(id: id, heatSetpoint: item.htsp?.double, coolSetpoint: item.clsp?.double, fanMode: nil)
        }
    }

    static func schedule(from program: InfinitySystemDTO.Program?) -> [SchedulePeriod] {
        let days = program?.day ?? []
        return sortedSchedule(days.enumerated().flatMap { offset, day -> [SchedulePeriod] in
            // Days are numbered from Sunday. Fall back to their order if the id isn't a number or a name.
            guard let weekday = weekday(fromDayID: day.id?.string) ?? (offset < 7 ? offset : nil) else { return [] }
            return (day.period ?? []).compactMap { period in
                guard period.enabled?.bool ?? true,
                      let profileID = period.activity?.string?.lowercased(),
                      let minute = period.time?.string.flatMap(minutes(fromClock:))
                else { return nil }
                return SchedulePeriod(weekday: weekday, minute: minute, profileID: profileID)
            }
        })
    }

    static func schedule(from entries: [EntryLevelSystemDTO.ScheduleEntry]?) -> [SchedulePeriod] {
        sortedSchedule((entries ?? []).compactMap { entry in
            guard let weekday = entry.day?.double.map({ Int($0) }), (0...6).contains(weekday),
                  let profileID = entry.sceneName?.string?.lowercased(),
                  let minute = entry.startTime?.string.flatMap(minutes(fromClock:))
            else { return nil }
            return SchedulePeriod(weekday: weekday, minute: minute, profileID: profileID)
        })
    }

    private static func sortedSchedule(_ periods: [SchedulePeriod]) -> [SchedulePeriod] {
        periods.sorted { ($0.weekday, $0.minute) < ($1.weekday, $1.minute) }
    }

    private static func weekday(fromDayID id: String?) -> Int? {
        guard let id else { return nil }
        if let number = Int(id) {
            return (0...6).contains(number) ? number : nil
        }
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return names.firstIndex { id.lowercased().hasPrefix($0) }
    }

    /// Minutes after midnight from "HH:MM" (or "HH:MM:SS").
    static func minutes(fromClock text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]), (0..<24).contains(hour),
              let minute = Int(parts[1]), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// "HH:MM", the way Infinity writes times.
    static func clockText(minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    /// The fixed offset at the end of a timestamp like "2024-08-14T22:15:28-04:00".
    /// Nil when there isn't one, or it's UTC ("Z"), which says nothing about the house.
    static func timeZone(fromLocalTime text: String?) -> TimeZone? {
        guard let text, let match = text.firstMatch(of: /([+-])(\d{2}):?(\d{2})$/),
              let hours = Int(match.2), let minutes = Int(match.3)
        else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (match.1 == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }
}
