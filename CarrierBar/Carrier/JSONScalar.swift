import Foundation

/// A tolerant JSON scalar.
///
/// Carrier's API is loose with types: the same kind of field can arrive as a string ("74"),
/// a number (75), a boolean, "on"/"off", or the literal string "None". Every scalar field is
/// decoded through this type and read with the typed accessors, so one odd value never
/// breaks the whole payload.
enum JSONScalar: Decodable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            // An object or array where a scalar was expected. Ignore it instead of failing.
            self = .null
        }
    }

    /// Text value, with Carrier's placeholder values ("None", "") treated as missing.
    var string: String? {
        switch self {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.placeholders.contains(trimmed.lowercased()) ? nil : trimmed
        case .number(let value):
            if value.isFinite, value.rounded() == value, abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return nil
        }
    }

    var double: Double? {
        switch self {
        case .number(let value):
            return value.isFinite ? value : nil
        case .string:
            guard let text = string, let value = Double(text), value.isFinite else { return nil }
            return value
        case .bool, .null:
            return nil
        }
    }

    var bool: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string:
            switch string?.lowercased() {
            case "on", "true", "yes", "1":
                return true
            case "off", "false", "no", "0":
                return false
            default:
                return nil
            }
        case .null:
            return nil
        }
    }

    private static let placeholders: Set<String> = ["", "none", "null"]
}
