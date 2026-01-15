import Foundation
import TOMLKit
import Cocoa

/// Main configuration structure
struct Config: Codable {
    // Strategy: "toggle" (old) or "hold" (quasimode)
    var activationStrategy: String = "hold"
    
    // Modifier to hold (for "hold" strategy) or Key to press (for "toggle" strategy)
    // Default to "ctrl" for hold
    var activationModifier: String = "ctrl"
    
    // Legacy support / fallback for toggle
    var activationKey: String = "ctrl-space"
    
    var gaps: Double = 10.0
    
    // Max windows to tile per screen (0 = unlimited)
    var maxWindowsPerScreen: Int = 2
    
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
        "ctrl-shift-h": "move left",
        "ctrl-shift-j": "move bottom",
        "ctrl-shift-k": "move top",
        "ctrl-shift-l": "move right",
        "f": "center",
        "shift-f": "maximize",
        "i": "insert-mode",
        ":": "command-mode",
        "esc": "disabled-mode"
    ]
}

enum ConfigError: Error {
    case fileNotFound
    case invalidFormat
    case permissionDenied
}
