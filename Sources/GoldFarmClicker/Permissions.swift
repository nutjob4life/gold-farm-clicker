import ApplicationServices
import AppKit
import Foundation

enum Permissions {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility permission prompt if not yet trusted.
    @discardableResult
    static func requestTrustPrompt() -> Bool {
        // String value of kAXTrustedCheckOptionPrompt; avoid the global CFStringRef
        // which is not concurrency-safe under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        // Works on modern macOS; falls back to the older preference pane URL.
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
