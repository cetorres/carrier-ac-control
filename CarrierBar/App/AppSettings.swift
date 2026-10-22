import Foundation
import Observation
import ServiceManagement

/// Preferences shown in the Settings window.
@MainActor
@Observable
final class AppSettings {
    /// Whether CarrierBar opens when you log in. macOS keeps this, not the app, so it's read back
    /// from `SMAppService` after every change, and whenever Settings opens.
    private(set) var launchAtLogin = false
    /// macOS registered the login item but it waits for approval in System Settings › General › Login Items.
    private(set) var launchAtLoginNeedsApproval = false
    /// Shown in Settings rather than logged and forgotten.
    var lastError: String?

    init() {
        refreshLoginItem()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.store.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            lastError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        refreshLoginItem()
    }

    /// Picks up changes made in System Settings while the app was running.
    func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// App details for the About tab, read from the bundle where possible.
enum AboutInfo {
    static let authorURL = URL(string: "https://cetorres.com")!
    static let appURL = URL(string: "https://github.com/cetorres/carrier-ac-control")!
    static let supportURL = URL(string: "https://buymeacoffee.com/cetorres")!
    static let contactURL = URL(string: "https://cetorres.com/contact?subject=CarrierBar%20support")!
    static let appInfo = "Shows the temperature of each Carrier unit on your account in the menu bar, and lets you change its temperature, mode, fan, and comfort profile from there."
    static let disclaimer = "CarrierBar is an independent project, not affiliated with or supported by Carrier."
    static let copyrightHolder = "Carlos E. Torres"

    /// Prefers the display name, which is how the app is written everywhere else.
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "CarrierBar"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
