import Foundation
import ServiceManagement

struct LaunchAtLogin {
    static let storageKey = "launchAtLogin"

    private let defaults: UserDefaults
    let registersWithSystem: Bool
    private let updateLoginItem: (Bool) throws -> Void

    init(
        defaults: UserDefaults = .standard,
        registersWithSystem: Bool = Bundle.main.bundleURL.pathExtension == "app",
        updateLoginItem: @escaping (Bool) throws -> Void = LaunchAtLogin.updateSystemLoginItem
    ) {
        self.defaults = defaults
        self.registersWithSystem = registersWithSystem
        self.updateLoginItem = updateLoginItem
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.storageKey)
    }

    func setEnabled(_ enabled: Bool) throws {
        if registersWithSystem {
            try updateLoginItem(enabled)
        }
        defaults.set(enabled, forKey: Self.storageKey)
    }

    private static func updateSystemLoginItem(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled {
            try service.unregister()
        }
    }
}
