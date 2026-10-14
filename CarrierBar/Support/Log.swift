import Foundation
import OSLog

/// Unified logging. Filter in Console.app by the app's bundle identifier.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cetorres.CarrierBar"

    static let api = Logger(subsystem: subsystem, category: "api")
    static let realtime = Logger(subsystem: subsystem, category: "realtime")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let web = Logger(subsystem: subsystem, category: "web")
}
