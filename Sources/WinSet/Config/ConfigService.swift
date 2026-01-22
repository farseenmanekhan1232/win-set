import Foundation
import TOMLKit

/// Service for loading and saving configuration
class ConfigService {
    static let shared = ConfigService()
    
    private(set) var config: Config = .default
    
    private let configPath: URL
    
    private init() {
        // ~/.config/winset/config.toml
        let home = FileManager.default.homeDirectoryForCurrentUser
        configPath = home.appendingPathComponent(".config/winset/config.toml")
    }
    
    /// Load configuration from disk, creating default if missing
    func load() {
        do {
            if !FileManager.default.fileExists(atPath: configPath.path) {
                try createDefaultConfig()
            }
            
            let data = try Data(contentsOf: configPath)
            if let string = String(data: data, encoding: .utf8) {
                let decoder = TOMLDecoder()
                config = try decoder.decode(Config.self, from: string)
                print("✅ Loaded config from \(configPath.path)")
            }
        } catch {
            print("⚠️  Failed to load config: \(error). Using defaults.")
        }
    }
    
    private func createDefaultConfig() throws {
        let folder = configPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        let defaultConfig = """
        # WinSet Configuration

        # Modifier to hold for hotkeys (ctrl, alt, cmd, shift)
        activationModifier = "ctrl"

        # Gap between windows (pixels)
        gaps = 10.0

        # Use equal 50/50 split for 2 windows (false = golden ratio ~62/38)
        useEqualSplitForTwo = true

        # Enable auto-tiling: true = windows snap back after resize
        # false = manual resize is preserved, other windows adjust
        enableAutoTiling = true

        [bindings.normal]
        # Focus navigation (Ctrl + h/j/k/l)
        h = "focus left"
        j = "focus down"
        k = "focus up"
        l = "focus right"

        # Swap or resize at edge (Ctrl + Shift + h/j/k/l)
        # Tries to swap windows; if no window in that direction, snaps to half
        "shift-h" = "swap left"
        "shift-j" = "swap down"
        "shift-k" = "swap up"
        "shift-l" = "swap right"

        # Monitor navigation
        "bracketleft" = "focus monitor left"
        "bracketright" = "focus monitor right"

        # Window sizing
        f = "center"
        "shift-f" = "maximize"
        """
        
        try defaultConfig.write(to: configPath, atomically: true, encoding: .utf8)
        print("📝 Created default config at \(configPath.path)")
    }
}
