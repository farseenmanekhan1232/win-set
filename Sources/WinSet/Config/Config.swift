import Foundation
import TOMLKit
import Cocoa

/// Main configuration structure
struct Config: Codable {
    /// Modifier to hold for hotkeys (ctrl, alt, cmd, shift)
    var activationModifier: String = "ctrl"

    /// Gap between windows (pixels)
    var gaps: Double = 10.0

    /// Applications to ignore (by app name)
    var ignoredApps: [String] = []

    /// Key bindings
    var bindings: BindingsConfig = BindingsConfig()

    // Default config
    static let `default` = Config()
}

struct BindingsConfig: Codable {
    var normal: [String: String] = [
        "h": "focus left",
        "j": "focus down",
        "k": "focus up",
        "l": "focus right",
        "shift-h": "swap left",
        "shift-j": "swap down",
        "shift-k": "swap up",
        "shift-l": "swap right",
        "f": "center",
        "shift-f": "maximize",
        "bracketleft": "focus monitor left",
        "bracketright": "focus monitor right",
        "r": "retile"
    ]
}

enum ConfigError: Error {
    case fileNotFound
    case invalidFormat
    case permissionDenied
}
