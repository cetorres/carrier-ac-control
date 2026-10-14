import Foundation

/// One unit shown in the menu bar: an Infinity system zone or a Carrier Smart Thermostat,
/// normalized into the same shape.
struct Thermostat: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case infinity
        case smartThermostat
    }

    enum Conditioning: Equatable, Sendable {
        case cooling
        case heating
        case idle
        case unknown

        /// Infinity reports values like "active_cool", "prep_heat" or "idle".
        /// Smart Thermostats report text like "Idle" or "Cool Stage 1".
        init(rawStatus: String?) {
            let value = rawStatus?.lowercased() ?? ""
            if value.contains("cool") {
                self = .cooling
            } else if value.contains("heat") {
                self = .heating
            } else if value.contains("idle") || value == "off" {
                self = .idle
            } else {
                self = .unknown
            }
        }
    }

    let id: String
    let kind: Kind
    let systemSerial: String
    let zoneID: String
    var name: String
    var isOnline: Bool
    var roomTemperature: Double?
    var humidity: Double?
    var heatSetpoint: Double?
    var coolSetpoint: Double?
    var mode: String?
    var fanMode: String?
    var activity: String?
    var isOnHold: Bool
    var conditioning: Conditioning
    var conditioningDetail: String?
    var outdoorTemperature: Double?
    var filterUsedPercent: Double?
    var model: String?
    var firmware: String?
    var indoorUnitStatus: String?
    var outdoorUnitStatus: String?
    var usesCelsius: Bool = false
    /// Infinity only. Empty when the zone has none, or for Smart Thermostats.
    var comfortProfiles: [ComfortProfile] = []
    /// The weekly schedule, sorted by day and time. Empty when there is none.
    var schedule: [SchedulePeriod] = []
    /// Infinity: when the current hold ends, "HH:MM" in the system's time. Nil holds until changed.
    var holdUntil: String?
    /// Smart Thermostats: how many hours the current timed hold lasts. Nil holds until changed.
    var holdHours: Int?
    /// Smart Thermostats: when the current timed hold ends, from the minutes it reports are left.
    var holdEndsAt: Date?
    /// The time zone the system's schedule and hold times are in.
    var timeZone: TimeZone = .current
}

// MARK: - Setpoint changes

extension Thermostat {
    /// Whether this app can change the unit's setpoints: it's online and in a mode that has one.
    var canAdjustSetpoints: Bool {
        guard isOnline, heatSetpoint != nil, coolSetpoint != nil else { return false }
        switch mode?.lowercased() {
        case "heat"?, "cool"?, "auto"?:
            return true
        default:
            return false
        }
    }

    /// Moves the setpoint the current mode uses by `steps` whole degrees, keeping the other one
    /// far enough away that the system accepts the pair. In auto both move together.
    /// The unit is held for `hold`.
    /// Returns false when nothing changed, for example at the end of the allowed range.
    @discardableResult
    mutating func adjustSetpoints(by steps: Int, until hold: HoldLength) -> Bool {
        guard canAdjustSetpoints, steps != 0, let heat = heatSetpoint, let cool = coolSetpoint else { return false }
        let range: ClosedRange<Double> = usesCelsius ? 10...32 : 50...90
        let deadband: Double = usesCelsius ? 1 : 2
        let delta = Double(steps)

        var newHeat = heat
        var newCool = cool
        switch mode?.lowercased() {
        case "heat"?:
            newHeat = (heat + delta).clamped(to: range.lowerBound...(range.upperBound - deadband))
            newCool = max(cool, newHeat + deadband)
        case "cool"?:
            newCool = (cool + delta).clamped(to: (range.lowerBound + deadband)...range.upperBound)
            newHeat = min(heat, newCool - deadband)
        default:
            // Shift the pair without letting either end leave the range.
            let lowest = range.lowerBound - heat
            let highest = range.upperBound - cool
            guard lowest <= highest else { return false }
            let shift = delta.clamped(to: lowest...highest)
            newHeat = heat + shift
            newCool = cool + shift
        }

        guard newHeat != heat || newCool != cool else { return false }
        applyHeldSetpoints(heat: newHeat, cool: newCool, until: hold)
        return true
    }

    /// Shows the unit held at these setpoints, as it reports itself after a manual change.
    mutating func applyHeldSetpoints(heat: Double, cool: Double, until hold: HoldLength) {
        heatSetpoint = heat
        coolSetpoint = cool
        isOnHold = true
        switch kind {
        case .infinity:
            activity = "manual"
        case .smartThermostat:
            activity = profileID(matchingHeat: heat, cool: cool) ?? "manual"
        }
        applyHoldLength(hold)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Mapping from the API

extension Thermostat {
    /// One thermostat per enabled zone. Single zone systems use the system name.
    static func makeAll(from system: InfinitySystemDTO) -> [Thermostat] {
        guard let serial = system.profile?.serial?.string else { return [] }
        let status = system.status
        let systemName = system.profile?.name?.string ?? "Carrier"

        let zoneConfigs = Dictionary(
            (system.config?.zones ?? []).compactMap { zone -> (String, InfinitySystemDTO.ZoneConfig)? in
                guard let id = zone.id?.string else { return nil }
                return (id, zone)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let timeZone = Self.timeZone(fromLocalTime: status?.localTime?.string) ?? .current
        let zones = (status?.zones ?? []).filter { $0.enabled?.bool ?? true }

        return zones.compactMap { zone -> Thermostat? in
            guard let zoneID = zone.id?.string else { return nil }
            let config = zoneConfigs[zoneID]
            let name = zones.count > 1
                ? "\(systemName) · \(config?.name?.string ?? "Zone \(zoneID)")"
                : systemName

            return Thermostat(
                id: "\(serial)#\(zoneID)",
                kind: .infinity,
                systemSerial: serial,
                zoneID: zoneID,
                name: name,
                isOnline: !(status?.isDisconnected?.bool ?? false),
                roomTemperature: zone.rt?.double,
                humidity: zone.rh?.double,
                heatSetpoint: zone.htsp?.double,
                coolSetpoint: zone.clsp?.double,
                mode: status?.mode?.string,
                fanMode: zone.fan?.string,
                activity: zone.currentActivity?.string,
                isOnHold: zone.hold?.bool ?? false,
                conditioning: Conditioning(rawStatus: zone.zoneconditioning?.string),
                conditioningDetail: zone.zoneconditioning?.string,
                outdoorTemperature: status?.oat?.double,
                filterUsedPercent: status?.filtrlvl?.double,
                model: system.profile?.model?.string,
                firmware: system.profile?.firmware?.string,
                indoorUnitStatus: status?.idu?.opstat?.string,
                outdoorUnitStatus: status?.odu?.opstat?.string,
                usesCelsius: status?.cfgem?.string?.uppercased() == "C",
                comfortProfiles: Self.comfortProfiles(from: config?.activities),
                schedule: Self.schedule(from: config?.program),
                holdUntil: config?.otmr?.string.flatMap(Self.minutes(fromClock:)).map(Self.clockText(minutes:)),
                timeZone: timeZone
            )
        }
    }

    static func makeAll(from system: EntryLevelSystemDTO) -> [Thermostat] {
        guard let serial = system.serial?.string else { return [] }
        let zones = system.zones ?? []
        let systemName = system.name?.string ?? "Thermostat"

        let timeZone = system.timezone?.double
            .flatMap { TimeZone(secondsFromGMT: Int(($0 * 3600).rounded())) } ?? .current

        return zones.enumerated().map { offset, zone -> Thermostat in
            let zoneID = zone.index?.string ?? String(offset)
            // A timed hold reports its length in hours and leaves the schedule on.
            // A hold until changed turns the schedule off.
            let holdHours = zone.holdEndTime?.double.map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            let isOnHold = zone.scheduleEnabled?.bool == false || holdHours != nil
            var thermostat = Thermostat(
                id: "\(serial)#\(zoneID)",
                kind: .smartThermostat,
                systemSerial: serial,
                zoneID: zoneID,
                name: zones.count > 1 ? "\(systemName) · Zone \(zoneID)" : systemName,
                isOnline: system.connection?.isConnected?.bool ?? true,
                roomTemperature: zone.rt?.double,
                humidity: zone.rh?.double,
                heatSetpoint: zone.htsp?.current?.double,
                coolSetpoint: zone.clsp?.current?.double,
                mode: zone.mode?.string,
                fanMode: zone.fanMode?.string,
                activity: zone.currentSceneName?.string?.lowercased(),
                isOnHold: isOnHold,
                conditioning: Conditioning(rawStatus: zone.stageStatus?.string),
                conditioningDetail: zone.stageStatus?.string,
                outdoorTemperature: zone.outsideTemp?.double,
                filterUsedPercent: nil,
                model: system.model?.string,
                firmware: system.firmware?.string,
                indoorUnitStatus: nil,
                outdoorUnitStatus: nil,
                usesCelsius: system.temperatureUnit?.string?.uppercased().hasPrefix("C") ?? false,
                comfortProfiles: Self.comfortProfiles(from: zone.comfortProfile),
                schedule: Self.schedule(from: zone.schedule),
                holdHours: isOnHold ? holdHours : nil,
                holdEndsAt: isOnHold && holdHours != nil
                    ? zone.holdCountdown?.double.map { Date().addingTimeInterval($0 * 60) }
                    : nil,
                timeZone: timeZone
            )
            // A hold leaves the scene name on the scheduled one. Name the hold after the profile
            // its setpoints match, or call it manual.
            if isOnHold, let heat = thermostat.heatSetpoint, let cool = thermostat.coolSetpoint {
                thermostat.activity = thermostat.profileID(matchingHeat: heat, cool: cool) ?? "manual"
            }
            return thermostat
        }
    }

    /// Merges a realtime status update. Only fields present in the message change.
    mutating func apply(_ patch: InfinityStatusPatch) {
        if let value = patch.oat?.double { outdoorTemperature = value }
        if let value = patch.mode?.string { mode = value }
        if let value = patch.isDisconnected?.bool { isOnline = !value }

        guard let zone = patch.zones?.first(where: { $0.id?.string == zoneID }) else { return }
        if let value = zone.rt?.double { roomTemperature = value }
        if let value = zone.rh?.double { humidity = value }
        if let value = zone.htsp?.double { heatSetpoint = value }
        if let value = zone.clsp?.double { coolSetpoint = value }
        if let value = zone.fan?.string { fanMode = value }
        if let value = zone.currentActivity?.string { activity = value }
        if let value = zone.hold?.bool { isOnHold = value }
        if let value = zone.zoneconditioning?.string {
            conditioning = Conditioning(rawStatus: value)
            conditioningDetail = value
        }
    }
}
