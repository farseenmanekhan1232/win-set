import Foundation
import Cocoa
import ApplicationServices

/// Manages virtual workspaces by manipulating window positions
actor WorkspaceManager {
    
    static let shared = WorkspaceManager()
    
    // Notification for UI updates
    static let workspaceChangedNotification = Notification.Name("WinSetWorkspaceChanged")
    
    private let accessibilityService: AccessibilityService
    
    // State
    private(set) var activeWorkspaceByScreen: [UInt32: Int] = [:] // DisplayID -> WorkspaceID
    private var windowWorkspaces: [WindowID: Int] = [:]
    private var windowScreens: [WindowID: UInt32] = [:] // New: WindowID -> DisplayID
    private var savedPositions: [WindowID: CGRect] = [:]
    
    // Constants
    private let offScreenOffset: CGFloat = 50000
    
    // Fallback for legacy calls or untracked screens
    var defaultActiveWorkspaceId: Int {
        return activeWorkspaceByScreen.values.first ?? 1
    }
    
    init(accessibilityService: AccessibilityService = .shared) {
        self.accessibilityService = accessibilityService
        
        // Load state
        if let state = StateService.shared.load() {
            self.windowWorkspaces = state.windowWorkspaces
            self.activeWorkspaceByScreen = state.activeWorkspaceByScreen
            self.windowScreens = state.windowScreens
            
            // Validate: Ensure at least one workspace is active for main screen
            if let mainScreen = NSScreen.main {
                let id = mainScreen.displayID
                if activeWorkspaceByScreen[id] == nil {
                     activeWorkspaceByScreen[id] = 1
                }
            }
            print("Restored workspace state: ActiveByScreen=\(activeWorkspaceByScreen), Windows=\(windowWorkspaces.count)")
        } else {
            // Initial default
            if let mainScreen = NSScreen.main {
                activeWorkspaceByScreen[mainScreen.displayID] = 1
            }
        }
    }
    
    private func saveState() {
        let state = AppState(
            windowWorkspaces: windowWorkspaces,
            activeWorkspaceByScreen: activeWorkspaceByScreen,
            windowScreens: windowScreens,
            globalActiveWorkspace: 1 // Legacy/Unused
        )
        StateService.shared.save(state)
        
        // Notify UI
        Task { @MainActor in
            NotificationCenter.default.post(name: WorkspaceManager.workspaceChangedNotification, object: nil)
        }
    }
    
    // MARK: - Workspace Operations
    
    /// Switch to a specific workspace on the focused screen
    func switchToWorkspace(_ targetId: Int) async {
        guard let focusedWindow = await accessibilityService.getFocusedWindow() else {
            // Fallback to main screen if no window focused
            if let main = NSScreen.main {
                await switchToWorkspace(targetId, on: main)
            }
            return
        }
        
        // Find screen containing focused window
        // Note: AccessibilityService.screenContaining is private. We need a helper here or access it.
        // For now, let's duplicate the logic or trust NSScreen.main if focused.
        // Actually, we can use NSScreen.main as "focused screen" usually matches.
        if let screen = NSScreen.main {
            await switchToWorkspace(targetId, on: screen)
        }
    }
    
    /// Internal switch logic with screen context
    private func switchToWorkspace(_ targetId: Int, on screen: NSScreen) async {
        let screenId = screen.displayID
        let currentId = activeWorkspaceByScreen[screenId] ?? 1
        
        guard targetId != currentId else { return }
        
        // NO SWAPPING - Independent Workspaces
        
        print("Switching Screen \(screenId) from WS \(currentId) to WS \(targetId)...")
        activeWorkspaceByScreen[screenId] = targetId
        saveState()
        
        await refreshWindows()
    }
    
    /// Refresh all windows based on current state
    private func refreshWindows() async {
        let allWindows = await accessibilityService.getAllWindows()
        
        for window in allWindows {
            // CRITICAL FIX: If user manually dragged window to another screen, update our knowledge.
            // Only trust visible on-screen windows.
            if window.frame.origin.x < 10000 {
                // Window is visible. Recalculate which screen it is on.
                let currentScreenId = detectScreenId(for: window)
                if currentScreenId != windowScreens[window.id] {
                    print("Window '\(window.title)' moved to Screen \(currentScreenId). Updating.")
                    windowScreens[window.id] = currentScreenId
                }
            }
            
            // Ensure we track this window
            _ = getWorkspace(for: window) // Side effect: populates maps if missing
            
            let wsId = windowWorkspaces[window.id] ?? 1
            let screenId = windowScreens[window.id] ?? (NSScreen.main?.displayID ?? 0)
            
            // Check if this workspace is active on the window's screen
            let activeIdOnScreen = activeWorkspaceByScreen[screenId] ?? 1
            
            if wsId == activeIdOnScreen {
                // Should be visible
                await restoreWindow(window)
            } else {
                // Should be hidden
                savedPositions[window.id] = window.frame
                await moveWindowOffScreen(window)
            }
        }
    }
    
    /// Move a specific window to a target workspace
    func moveWindow(_ window: Window, toWorkspace targetId: Int) async {
        let currentWs = getWorkspace(for: window)
        // Note: We might be moving to same workspace ID but on a different screen context?
        // But workspace ID is just a number.
        // If we move to Workspace 2, we assume Workspace 2 on the window's CURRENT screen?
        // Yes, per user request "monitor independent".
        // But what if the user wants to move it to another monitor?
        // That's "Focus Monitor" -> "Move Window to Monitor".
        // This function is "Move to Workspace X (on current monitor)".
        
        guard currentWs != targetId else { return }
        
        print("Moving window '\(window.title)' to workspace \(targetId)")
        
        // Update assignment
        windowWorkspaces[window.id] = targetId
        // Screen remains same
        saveState()
        
        // Check visibility
        let screenId = windowScreens[window.id] ?? (NSScreen.main?.displayID ?? 0)
        let activeIdOnScreen = activeWorkspaceByScreen[screenId] ?? 1
        
        if targetId == activeIdOnScreen {
            await restoreWindow(window)
        } else {
            savedPositions[window.id] = window.frame
            await moveWindowOffScreen(window)
        }
    }
    
    /// Assign a window to the active workspace (used for new windows)
    func assignToActive(_ window: Window) {
        if windowWorkspaces[window.id] == nil {
            // Find which screen this window is on
            var bestScreenId: UInt32 = NSScreen.main?.displayID ?? 0
            var maxIntersection: CGFloat = 0
            
            for screen in NSScreen.screens {
                let intersection = screen.frame.intersection(window.frame)
                let area = intersection.width * intersection.height
                if area > maxIntersection {
                    maxIntersection = area
                    bestScreenId = screen.displayID
                }
            }
            
            let targetParams = activeWorkspaceByScreen[bestScreenId] ?? 1
            
            windowWorkspaces[window.id] = targetParams
            windowScreens[window.id] = bestScreenId
            saveState()
        }
    }
    
    // MARK: - Recovery & Maintenance
    
    /// Reset all windows to Workspace 1 and verify visibility
    func resetAllWorkspaces() async {
        print("RESETTING ALL WORKSPACES...")
        
        // 1. Reset all workspace tracking
        let allWindows = await accessibilityService.getAllWindows()
        
        // 2. Move everything to Workspace 1
        activeWorkspaceByScreen.removeAll()
        windowWorkspaces.removeAll()
        windowScreens.removeAll()
        savedPositions.removeAll()
        
        // Set WS 1 active on all screens
        for screen in NSScreen.screens {
            activeWorkspaceByScreen[screen.displayID] = 1
        }
        
        // 3. Restore every window
        for window in allWindows {
            // We need to re-detect screens for reset to work properly
            let screenId = getScreenId(for: window) // This logic caches the screen
            windowWorkspaces[window.id] = 1
            
            await restoreWindow(window)
        }
        
        saveState()
        print("Reset complete.")
    }
    
    /// Check for inconsistencies
    func validateState() async {
        let allWindows = await accessibilityService.getAllWindows()
        
        for window in allWindows {
            _ = getWorkspace(for: window) // Ensure tracked
            
            let wsId = windowWorkspaces[window.id] ?? 1
            let screenId = windowScreens[window.id] ?? 0
            
            // Is this workspace active on its screen?
            let activeId = activeWorkspaceByScreen[screenId] ?? 1
            let isActive = (wsId == activeId)
            
            if isActive {
                // Window SHOULD be visible.
                // Check if it's far off-screen
                if window.frame.origin.x > 10000 {
                    print("RESCUE: Window \(window.title) should be visible (WS \(wsId)) but is off-screen. Restoring.")
                    await restoreWindow(window)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    // MARK: - Helpers
    
    private func getWorkspace(for window: Window) -> Int {
        if let wsId = windowWorkspaces[window.id] {
            return wsId
        }
        // New window: Assign to active workspace of the screen it's on
        let screenId = getScreenId(for: window)
        let defaultId = activeWorkspaceByScreen[screenId] ?? 1
        
        windowWorkspaces[window.id] = defaultId
        windowScreens[window.id] = screenId
        
        return defaultId
    }
    
    private func getScreenId(for window: Window) -> UInt32 {
        if let cached = windowScreens[window.id] {
            return cached
        }
        return detectScreenId(for: window)
    }

    private func detectScreenId(for window: Window) -> UInt32 {
        // Determine screen from frame
        // Find screen with largest intersection
        var bestScreenId: UInt32 = NSScreen.main?.displayID ?? 0
        var maxIntersection: CGFloat = 0
        
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(window.frame)
            let area = intersection.width * intersection.height
            if area > maxIntersection {
                maxIntersection = area
                bestScreenId = screen.displayID
            }
        }
        
        // Cache it
        windowScreens[window.id] = bestScreenId
        return bestScreenId
    }
    
    private func moveWindowOffScreen(_ window: Window) async {
        // Move far to the right
        // We use the same coordinate conversion logic validation or just trust setWindowFrame handles global coords
        // AccessibilityService.setWindowFrame expects Global AX Coords.
        
        let offScreenFrame = CGRect(
            x: window.frame.origin.x + offScreenOffset,
            y: window.frame.origin.y, // Maintain Y to avoid menu bar interference
            width: window.frame.width,
            height: window.frame.height
        )
        
        do {
            try await accessibilityService.setWindowFrame(window, to: offScreenFrame)
        } catch {
            print("Failed to hide window: \(error)")
        }
    }
    
    private func restoreWindow(_ window: Window) async {
        guard let savedFrame = savedPositions[window.id] else {
            // No saved position (maybe new window assigned to this workspace but was never hidden?)
            // Or maybe it was off-screen since launch?
            // If it is currently on screen, do nothing.
            // If it is far off screen, bring it back to center or default.
            
            if window.frame.origin.x > 10000 {
                // It's lost in void. Bring back to Main Screen Center.
                if let mainScreen = NSScreen.screens.first {
                    let visible = mainScreen.visibleFrame
                    // Center it
                    let newFrame = CGRect(
                        x: visible.midX - window.frame.width/2,
                        y: visible.midY - window.frame.height/2,
                        width: window.frame.width,
                        height: window.frame.height
                    )
                    
                    // Convert to AX coordinates
                    // AX Y = ScreenHeight - MaxY(Cocoa)
                    // We need a helper for this or duplicate logic.
                    // For reset safety, let's just use 0,0 (Top Left) + some padding if we can't calculate perfectly
                    // Or trust accessibilityService.setWindowFrame handles a rect.
                    // Wait, accessibilityService.setWindowFrame expects AX coordinates.
                    
                    // Let's use a safe default: Top Left of main screen
                    let safeFrame = CGRect(x: 50, y: 50, width: window.frame.width, height: window.frame.height)
                    
                    do {
                        try await accessibilityService.setWindowFrame(window, to: safeFrame)
                    } catch {
                        print("Failed to rescue window: \(error)")
                    }
                    return 
                }
            }
            return
        }
        
        // Restore to saved frame
        do {
            try await accessibilityService.setWindowFrame(window, to: savedFrame)
        } catch {
            print("Failed to restore window: \(error)")
        }
    }
}
