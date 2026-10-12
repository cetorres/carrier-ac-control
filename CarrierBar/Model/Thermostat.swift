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
}

// MARK: - Mapping from the API

extension Thermostat {
    /// One thermostat per enabled zone. Single zone systems use the system name.
    static func makeAll(from system: InfinitySystemDTO) -> [Thermostat] {
        guard let serial = system.profile?.serial?.string else { return [] }
        let status = system.status
        let systemName = system.profile?.name?.string ?? "Carrier"

        let zoneNames = Dictionary(
            (system.config?.zones ?? []).compactMap { zone -> (String, String)? in
                guard let id = zone.id?.string, let name = zone.name?.string else { return nil }
                return (id, name)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let zones = (status?.zones ?? []).filter { $0.enabled?.bool ?? true }

        return zones.compactMap { zone -> Thermostat? in
            guard let zoneID = zone.id?.string else { return nil }
            let name = zones.count > 1
                ? "\(systemName) · \(zoneNames[zoneID] ?? "Zone \(zoneID)")"
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
                outdoorUnitStatus: status?.odu?.opstat?.string
            )
        }
    }

    static func makeAll(from system: EntryLevelSystemDTO) -> [Thermostat] {
        guard let serial = system.serial?.string else { return [] }
        let zones = system.zones ?? []
        let systemName = system.name?.string ?? "Thermostat"

        return zones.enumerated().map { offset, zone -> Thermostat in
            let zoneID = zone.index?.string ?? String(offset)
            return Thermostat(
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
                activity: nil,
                isOnHold: zone.scheduleEnabled?.bool == false,
                conditioning: Conditioning(rawStatus: zone.stageStatus?.string),
                conditioningDetail: zone.stageStatus?.string,
                outdoorTemperature: zone.outsideTemp?.double,
                filterUsedPercent: nil,
                model: system.model?.string,
                firmware: system.firmware?.string,
                indoorUnitStatus: nil,
                outdoorUnitStatus: nil
            )
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
