import Foundation
import ServiceManagement

@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:   return "Disabled"
        case .enabled:         return "Enabled"
        case .requiresApproval:return "Awaiting approval in System Settings"
        case .notFound:        return "App not in /Applications"
        @unknown default:      return "Unknown"
        }
    }

    /// Returns true if change applied successfully.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[caip] LoginItem toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}
