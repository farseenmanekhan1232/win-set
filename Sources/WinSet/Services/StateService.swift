import Foundation

/// Represents the persistent state of the application
struct AppState: Codable {
    /// Window ID to Workspace ID mapping
    var windowWorkspaces: [UInt32: Int] = [:]
    
    /// Display ID to Active Workspace ID mapping
    var activeWorkspaceByScreen: [UInt32: Int] = [:]
    
    /// Window ID to Screen ID mapping (DisplayID matches CGDirectDisplayID)
    var windowScreens: [UInt32: UInt32] = [:]
    
    // Legacy single active workspace (for backward compatibility if we change model)
    var globalActiveWorkspace: Int = 1
}

/// Service for saving and loading application state
class StateService {
    
    static let shared = StateService()
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var configDir: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/winset")
    }
    
    private var stateFile: URL {
        return configDir.appendingPathComponent("state.json")
    }
    
    private init() {
        // Ensure config directory exists
        try? fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    /// Save state to disk
    func save(_ state: AppState) {
        do {
            let data = try encoder.encode(state)
            try data.write(to: stateFile)
            // print("Saved state to \(stateFile.path)")
        } catch {
            print("Failed to save state: \(error)")
        }
    }
    
    /// Load state from disk
    func load() -> AppState? {
        guard fileManager.fileExists(atPath: stateFile.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: stateFile)
            let state = try decoder.decode(AppState.self, from: data)
            print("Loaded state from \(stateFile.path)")
            return state
        } catch {
            print("Failed to load state: \(error)")
            return nil
        }
    }
}
