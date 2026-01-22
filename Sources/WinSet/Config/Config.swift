import Foundation
import TOMLKit
import Cocoa

/// Main configuration structure
struct Config: Codable {
    /// Modifier to hold for hotkeys (ctrl, alt, cmd, shift)
    var activationModifier: String = "ctrl"

    /// Gap between windows (pixels)
    var gaps: Double = 10.0

    /// Use equal 50/50 split for 2 windows instead of golden ratio
    var useEqualSplitForTwo: Bool = true

    /// When true: windows snap back to layout after resize
    /// When false: manual resize is preserved, other windows adjust
    var enableAutoTiling: Bool = true

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
        "bracketright": "focus monitor right"
    ]
}

enum ConfigError: Error {
    case fileNotFound
    case invalidFormat
    case permissionDenied
}
