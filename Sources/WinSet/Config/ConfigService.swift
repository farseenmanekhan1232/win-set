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
        # ... (rest of default config)
        """
        
        // Write default config... (existing code)
        // ...
    }
    
    /// Save current configuration to disk
    func save() {
        do {
            let encoder = TOMLEncoder()
            let data = try encoder.encode(config)
            try data.write(to: configPath, atomically: true, encoding: .utf8)
            print("💾 Saved config to \(configPath.path)")
        } catch {
            print("⚠️ Failed to save config: \(error)")
        }
    }
    
    /// Add an app to the ignore list and save
    func ignoreApp(_ appName: String) {
        guard !config.ignoredApps.contains(appName) else { return }
        config.ignoredApps.append(appName)
        save()
        print("🚫 Added '\(appName)' to ignore list")
    }
}
