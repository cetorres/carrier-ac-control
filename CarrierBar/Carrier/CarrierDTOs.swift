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
        let isDisconnected: JSONScalar?
        let cfgem: JSONScalar?
        let mode: JSONScalar?
        let oat: JSONScalar?
        let filtrlvl: JSONScalar?
        let odu: Equipment?
        let idu: Equipment?
        let zones: [ZoneStatus]?
    }

    struct ZoneConfig: Decodable {
        let id: JSONScalar?
        let name: JSONScalar?
        let enabled: JSONScalar?
    }

    struct Config: Decodable {
        let zones: [ZoneConfig]?
    }

    let profile: Profile?
    let status: Status?
    let config: Config?
}

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

        enum CodingKeys: String, CodingKey {
            case index, mode, rt, rh, clsp, htsp
            case fanMode = "fan_mode"
            case scheduleEnabled = "schedule_enabled"
            case stageStatus = "stage_status"
            case outsideTemp = "outside_temp"
        }
    }

    let serial: JSONScalar?
    let name: JSONScalar?
    let model: JSONScalar?
    let firmware: JSONScalar?
    let temperatureUnit: JSONScalar?
    let connection: Connection?
    let zones: [Zone]?

    enum CodingKeys: String, CodingKey {
        case serial, name, model, firmware, connection, zones
        case temperatureUnit = "temp_unit_format"
    }
}
