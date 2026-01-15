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
        
        # Strategy: "hold" (default) or "toggle" (old style)
        activationStrategy = "hold"
        
        # Modifier to hold for "hold" strategy (ctrl, alt, cmd, shift, fn)
        activationModifier = "ctrl"
        
        # Legacy: for "toggle" strategy
        activationKey = "ctrl-space"
        
        # Gap between windows (pixels)
        gaps = 10.0
        
        [bindings.normal]
        h = "focus left"
        j = "focus down"
        k = "focus up"
        l = "focus right"
        
        "shift-h" = "move left"
        "shift-j" = "move bottom"
        "shift-k" = "move top"
        "shift-l" = "move right"
        
        "bracketleft" = "focus monitor left"
        "bracketright" = "focus monitor right"
        
        f = "center"
        "shift-f" = "maximize"
        
        # Workspaces
        "1" = "workspace 1"
        "2" = "workspace 2"
        "3" = "workspace 3"
        "4" = "workspace 4"
        
        "shift-1" = "move to workspace 1"
        "shift-2" = "move to workspace 2"
        "shift-3" = "move to workspace 3"
        "shift-4" = "move to workspace 4"
        
        i = "insert-mode"
        ":" = "command-mode"
        esc = "disabled-mode" 
        """
        
        try defaultConfig.write(to: configPath, atomically: true, encoding: .utf8)
        print("📝 Created default config at \(configPath.path)")
    }
}
