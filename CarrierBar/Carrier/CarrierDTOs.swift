import Foundation

// Wire formats for Carrier's GraphQL API. Shapes follow the open source carrier_api
// library (github.com/dahlb/carrier_api) and its captured fixtures.

// MARK: - GraphQL envelope

struct GraphQLRequest<Variables: Encodable>: Encodable {
    let operationName: String
    let query: String
    let variables: Variables
}

struct GraphQLResponse<Payload: Decodable>: Decodable {
    let data: Payload?
    let errors: [GraphQLErrorMessage]?
}

struct GraphQLErrorMessage: Decodable {
    let message: String?
}

// MARK: - Authentication

struct AssistedLoginVariables: Encodable {
    struct Input: Encodable {
        let username: String
        let password: String
    }

    let input: Input
}

struct AssistedLoginData: Decodable {
    let assistedLogin: AssistedLoginPayload?
}

struct AssistedLoginPayload: Decodable {
    struct Tokens: Decodable {
        let tokenType: JSONScalar?
        let expiresIn: JSONScalar?
        let accessToken: JSONScalar?
        let refreshToken: JSONScalar?

        enum CodingKeys: String, CodingKey {
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    let success: JSONScalar?
    let status: JSONScalar?
    let errorMessage: JSONScalar?
    let data: Tokens?
}

struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Double?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

struct OAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Infinity systems

struct InfinitySystemsData: Decodable {
    let infinitySystems: [InfinitySystemDTO]?
}

struct InfinitySystemDTO: Decodable {
    struct Profile: Decodable {
        let serial: JSONScalar?
        let name: JSONScalar?
        let firmware: JSONScalar?
        let model: JSONScalar?
        let brand: JSONScalar?
        let indoorModel: JSONScalar?
        let outdoorModel: JSONScalar?
        let idutype: JSONScalar?
        let odutype: JSONScalar?
    }

    struct Equipment: Decodable {
        let type: JSONScalar?
        let opstat: JSONScalar?
    }

    struct ZoneStatus: Decodable {
        let id: JSONScalar?
        let rt: JSONScalar?
        let rh: JSONScalar?
        let fan: JSONScalar?
        let htsp: JSONScalar?
        let clsp: JSONScalar?
        let hold: JSONScalar?
        let enabled: JSONScalar?
        let currentActivity: JSONScalar?
        let zoneconditioning: JSONScalar?
    }

    struct Status: Decodable {
        /// The system's clock, like "2024-08-14T22:15:28-04:00". Its offset is the house's time zone.
        let localTime: JSONScalar?
        let isDisconnected: JSONScalar?
        let cfgem: JSONScalar?
        let mode: JSONScalar?
        let oat: JSONScalar?
        let filtrlvl: JSONScalar?
        let odu: Equipment?
        let idu: Equipment?
        let zones: [ZoneStatus]?
    }

    /// A comfort profile ("home", "away", "sleep", "wake", "manual", "vacation") and its settings.
    struct Activity: Decodable {
        let id: JSONScalar?
        let type: JSONScalar?
        let fan: JSONScalar?
        let htsp: JSONScalar?
        let clsp: JSONScalar?
    }

    /// When an activity starts on a day. Each day has a fixed number of periods; unused ones are disabled.
    struct Period: Decodable {
        let id: JSONScalar?
        let activity: JSONScalar?
        let time: JSONScalar?
        let enabled: JSONScalar?
    }

    struct Day: Decodable {
        let id: JSONScalar?
        let period: [Period]?
    }

    struct Program: Decodable {
        let id: JSONScalar?
        let day: [Day]?
    }

    struct ZoneConfig: Decodable {
        let id: JSONScalar?
        let name: JSONScalar?
        let enabled: JSONScalar?
        let hold: JSONScalar?
        let holdActivity: JSONScalar?
        /// When the hold ends ("HH:MM"), if it isn't held until changed.
        let otmr: JSONScalar?
        let program: Program?
        let activities: [Activity]?

        enum CodingKeys: String, CodingKey {
            case id, name, enabled, hold, holdActivity, otmr, program, activities
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(JSONScalar.self, forKey: .id)
            name = try container.decodeIfPresent(JSONScalar.self, forKey: .name)
            enabled = try container.decodeIfPresent(JSONScalar.self, forKey: .enabled)
            hold = try container.decodeIfPresent(JSONScalar.self, forKey: .hold)
            holdActivity = try container.decodeIfPresent(JSONScalar.self, forKey: .holdActivity)
            otmr = try container.decodeIfPresent(JSONScalar.self, forKey: .otmr)
            // The schedule is extra. If its shape is ever unexpected, show the unit without it
            // instead of failing the whole payload.
            program = try? container.decodeIfPresent(Program.self, forKey: .program)
            activities = try? container.decodeIfPresent([Activity].self, forKey: .activities)
        }
    }

    struct Config: Decodable {
        let zones: [ZoneConfig]?
    }

    let profile: Profile?
    let status: Status?
    let config: Config?
}

struct InfinityZoneActivityVariables: Encodable {
    /// Values left nil are left out, so the activity keeps them.
    struct Input: Encodable {
        let serial: String
        let zoneId: String
        let activityType: String
        var htsp: String?
        var clsp: String?
        var fan: String?
    }

    let input: Input
}

/// System settings for an Infinity system. Only the mode is sent.
struct InfinityConfigVariables: Encodable {
    struct Input: Encodable {
        let serial: String
        let mode: String
    }

    let input: Input
}

struct InfinityZoneConfigVariables: Encodable {
    struct Input: Encodable {
        let serial: String
        let zoneId: String
        /// "on" to hold, "off" to follow the schedule.
        let hold: String
        /// The activity to hold in. Nil when turning the hold off.
        let holdActivity: String?
        /// Hold until this time ("HH:MM", the system's time). Nil holds until the next change.
        let otmr: String?

        enum CodingKeys: String, CodingKey {
            case serial, zoneId, hold, holdActivity, otmr
        }

        /// Missing values are sent as null rather than left out, so an earlier hold's end time
        /// doesn't carry over.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(serial, forKey: .serial)
            try container.encode(zoneId, forKey: .zoneId)
            try container.encode(hold, forKey: .hold)
            try container.encode(holdActivity, forKey: .holdActivity)
            try container.encode(otmr, forKey: .otmr)
        }
    }

    let input: Input
}

struct InfinityMutationData: Decodable {}

/// Partial status pushed over the realtime websocket ("InfinityStatus" messages).
/// Only the fields present in a message are set.
struct InfinityStatusPatch: Decodable, Sendable {
    struct Zone: Decodable, Sendable {
        let id: JSONScalar?
        let rt: JSONScalar?
        let rh: JSONScalar?
        let fan: JSONScalar?
        let htsp: JSONScalar?
        let clsp: JSONScalar?
        let hold: JSONScalar?
        let currentActivity: JSONScalar?
        let zoneconditioning: JSONScalar?
    }

    let oat: JSONScalar?
    let mode: JSONScalar?
    let isDisconnected: JSONScalar?
    let zones: [Zone]?
}

// MARK: - Smart Thermostats ("entry level" systems)

struct EntryLevelSystemsData: Decodable {
    let entryLevelSystems: [EntryLevelSystemDTO]?
}

struct EntryLevelSystemDTO: Decodable {
    struct Connection: Decodable {
        let isConnected: JSONScalar?
        let deviceId: JSONScalar?
    }

    struct SetPoint: Decodable {
        let current: JSONScalar?
    }

    /// When a scene ("wake", "home", "away", "sleep") starts. Days count from 0 for Sunday.
    struct ScheduleEntry: Decodable {
        let sceneName: JSONScalar?
        let startTime: JSONScalar?
        let day: JSONScalar?

        enum CodingKeys: String, CodingKey {
            case day
            case sceneName = "scene_name"
            case startTime = "start_time"
        }
    }

    struct ComfortProfileItem: Decodable {
        let htsp: JSONScalar?
        let clsp: JSONScalar?
    }

    /// Setpoints for each scene. Scenes that aren't set up are null.
    struct ComfortProfile: Decodable {
        let wake: ComfortProfileItem?
        let home: ComfortProfileItem?
        let away: ComfortProfileItem?
        let sleep: ComfortProfileItem?
    }

    struct Zone: Decodable {
        let index: JSONScalar?
        let mode: JSONScalar?
        let rt: JSONScalar?
        let rh: JSONScalar?
        let clsp: SetPoint?
        let htsp: SetPoint?
        let fanMode: JSONScalar?
        let scheduleEnabled: JSONScalar?
        let stageStatus: JSONScalar?
        let outsideTemp: JSONScalar?
        let currentSceneName: JSONScalar?
        /// Length of a timed hold in hours, or 0 when there isn't one.
        let holdEndTime: JSONScalar?
        /// Minutes left in a timed hold.
        let holdCountdown: JSONScalar?
        let schedule: [ScheduleEntry]?
        let comfortProfile: ComfortProfile?

        enum CodingKeys: String, CodingKey {
            case index, mode, rt, rh, clsp, htsp, schedule
            case fanMode = "fan_mode"
            case scheduleEnabled = "schedule_enabled"
            case stageStatus = "stage_status"
            case outsideTemp = "outside_temp"
            case currentSceneName = "current_scene_name"
            case holdEndTime = "hold_end_time"
            case holdCountdown = "hold_countdown"
            case comfortProfile = "comfort_profile"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            index = try container.decodeIfPresent(JSONScalar.self, forKey: .index)
            mode = try container.decodeIfPresent(JSONScalar.self, forKey: .mode)
            rt = try container.decodeIfPresent(JSONScalar.self, forKey: .rt)
            rh = try container.decodeIfPresent(JSONScalar.self, forKey: .rh)
            clsp = try container.decodeIfPresent(SetPoint.self, forKey: .clsp)
            htsp = try container.decodeIfPresent(SetPoint.self, forKey: .htsp)
            fanMode = try container.decodeIfPresent(JSONScalar.self, forKey: .fanMode)
            scheduleEnabled = try container.decodeIfPresent(JSONScalar.self, forKey: .scheduleEnabled)
            stageStatus = try container.decodeIfPresent(JSONScalar.self, forKey: .stageStatus)
            outsideTemp = try container.decodeIfPresent(JSONScalar.self, forKey: .outsideTemp)
            currentSceneName = try container.decodeIfPresent(JSONScalar.self, forKey: .currentSceneName)
            holdEndTime = try container.decodeIfPresent(JSONScalar.self, forKey: .holdEndTime)
            holdCountdown = try container.decodeIfPresent(JSONScalar.self, forKey: .holdCountdown)
            // The schedule is extra. If its shape is ever unexpected, show the unit without it.
            schedule = try? container.decodeIfPresent([ScheduleEntry].self, forKey: .schedule)
            comfortProfile = try? container.decodeIfPresent(ComfortProfile.self, forKey: .comfortProfile)
        }
    }

    let serial: JSONScalar?
    let name: JSONScalar?
    let model: JSONScalar?
    let firmware: JSONScalar?
    let temperatureUnit: JSONScalar?
    /// Hours from UTC, like -4.
    let timezone: JSONScalar?
    let connection: Connection?
    let zones: [Zone]?

    enum CodingKeys: String, CodingKey {
        case serial, name, model, firmware, connection, zones, timezone
        case temperatureUnit = "temp_unit_format"
    }
}
struct EntryLevelZoneVariables: Encodable {
    struct SetPoint: Encodable {
        let current: Double
    }

    struct Input: Encodable {
        let serial: String
        let index: Int
        let clsp: SetPoint
        let htsp: SetPoint
        /// False holds the zone at these setpoints until changed. A timed hold keeps it true.
        let scheduleEnabled: Bool
        /// Hours a timed hold lasts. 0 for no timed hold.
        let holdEndTime: Int

        enum CodingKeys: String, CodingKey {
            case serial, index, clsp, htsp
            case scheduleEnabled = "schedule_enabled"
            case holdEndTime = "hold_end_time"
        }
    }

    let input: Input
}

/// Changes a Smart Thermostat zone's mode or fan, and nothing else. Nil values are left out,
/// so the setpoints, schedule, and hold stay as they are.
struct EntryLevelZoneModeVariables: Encodable {
    struct Input: Encodable {
        let serial: String
        let index: Int
        var mode: String?
        var fanMode: String?

        enum CodingKeys: String, CodingKey {
            case serial, index, mode
            case fanMode = "fan_mode"
        }
    }

    let input: Input
}

struct EntryLevelZoneUpdateData: Decodable {
    struct Result: Decodable {
        let success: JSONScalar?
    }

    let updateEntryLevelZone: Result?
}

