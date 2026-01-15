import Foundation
import Cocoa

/// Core window management operations
/// This is the main interface for window manipulation
class WindowManager {
    
    private let accessibilityService: AccessibilityService
    
    init(accessibilityService: AccessibilityService = .shared) {
        self.accessibilityService = accessibilityService
    }
    
    // MARK: - State
    
    private struct SnapAction {
        let windowId: WindowID
        let position: SnapPosition
        let ratio: CGFloat
        let timestamp: Date
    }
    
    private var lastSnapAction: SnapAction?
    
    // MARK: - Focus Operations
    
    /// Focus the window in the specified direction from the current window
    func focusDirection(_ direction: Direction) async {
        guard let currentWindow = await accessibilityService.getFocusedWindow() else {
            print("No focused window")
            return
        }
        
        let allWindows = await accessibilityService.getAllWindows()
        
        // Filter to windows in the specified direction
        let candidateWindows = allWindows.filter { window in
            window.id != currentWindow.id && window.isInDirection(direction, from: currentWindow)
        }
        
        guard !candidateWindows.isEmpty else {
            print("No window in direction: \(direction)")
            return
        }
        
        // Find the nearest window in that direction
        // We weight distance based on direction alignment
        let nearest = candidateWindows.min { a, b in
            weightedDistance(from: currentWindow, to: a, direction: direction) <
            weightedDistance(from: currentWindow, to: b, direction: direction)
        }
        
        if let targetWindow = nearest {
            do {
                try await accessibilityService.focusWindow(targetWindow)
                print("Focused: \(targetWindow.title) (\(targetWindow.appName))")
            } catch {
                print("Failed to focus window: \(error)")
            }
        }
    }
    
    /// Focus window by number (based on position from left to right, top to bottom)
    func focusWindowNumber(_ number: Int) async {
        let allWindows = await accessibilityService.getAllWindows()
        
        // Sort windows by position (left to right, top to bottom)
        let sortedWindows = allWindows.sorted { a, b in
            if abs(a.frame.minY - b.frame.minY) < 50 {
                // Same row, sort by X
                return a.frame.minX < b.frame.minX
            }
            // Sort by Y (remember: lower Y is higher on screen in macOS coords)
            return a.frame.minY < b.frame.minY
        }
        
        let index = number - 1
        guard index >= 0 && index < sortedWindows.count else {
            print("No window at position \(number)")
            return
        }
        
        let targetWindow = sortedWindows[index]
        do {
            try await accessibilityService.focusWindow(targetWindow)
            print("Focused window \(number): \(targetWindow.title)")
        } catch {
            print("Failed to focus window: \(error)")
        }
    }
    
    // MARK: - Move/Snap Operations
    
    /// Snap the focused window to a half of the screen
    /// Snap the focused window to a half of the screen
    @MainActor
    func moveToHalf(_ direction: Direction) async {
        let snapPosition: SnapPosition
        switch direction {
        case .left: snapPosition = .leftHalf
        case .right: snapPosition = .rightHalf
        case .up: snapPosition = .topHalf
        case .down: snapPosition = .bottomHalf
        }
        
        await snapTo(snapPosition)
    }
    
    /// Snap the focused window to a predefined position
    @MainActor
    func snapTo(_ position: SnapPosition) async {
        guard let window = await accessibilityService.getFocusedWindow() else {
            print("No focused window")
            return
        }
        
        guard let screen = screenContaining(window: window) else {
            print("Could not determine screen for window")
            return
        }

        // Determine snap ratio (Cycle: 0.5 -> 0.67 -> 0.33 -> 0.5)
        var ratio: CGFloat = 0.5
        
        // Check for repeated snap action
        if let last = lastSnapAction,
           last.windowId == window.id,
           last.position == position,
           Date().timeIntervalSince(last.timestamp) < 2.0 {
            
            // Cycle logic based on PREVIOUS intended ratio (avoids resize race conditions)
            if let lastRatio = lastSnapAction?.ratio {
                if abs(lastRatio - 0.5) < 0.01 {
                    ratio = 0.6666 // 0.5 -> 0.66
                } else if abs(lastRatio - 0.6666) < 0.01 {
                    ratio = 0.3333 // 0.66 -> 0.33
                } else {
                    ratio = 0.5 // Reset to 0.5
                }
                print("Cycling snap ratio (cached): \(String(format: "%.2f", lastRatio)) -> \(String(format: "%.2f", ratio))")
            } else {
                 // Fallback if no last ratio
                 ratio = 0.5 
            }
        } else {
            // New snap action, reset to 0.5
            ratio = 0.5
        }
        
        // Update last snap action with the NEW ratio
        lastSnapAction = SnapAction(windowId: window.id, position: position, ratio: ratio, timestamp: Date())

        // Calculate target frame
        // We need to override the width if it's a side snap
        var targetFrame = position.frame(on: screen, gaps: ConfigService.shared.config.gaps)
        
        // Only apply ratio if it's a side snap
        if [.leftHalf, .rightHalf].contains(position) && ratio != 0.5 {
             let screenFrame = screen.visibleFrame
             let gaps = ConfigService.shared.config.gaps
             let width = (screenFrame.width * ratio) - (CGFloat(gaps) * 1.5) // Adjust for gaps
             
             targetFrame.size.width = width
             
             if position == .rightHalf {
                 targetFrame.origin.x = screenFrame.maxX - width - CGFloat(gaps)
             }
        }
        
        // Convert to AX Coordinates (Global Top-Left origin)
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return }
        
        let axFrame = CGRect(
            x: targetFrame.origin.x,
            y: mainHeight - targetFrame.maxY,
            width: targetFrame.width,
            height: targetFrame.height
        )
        
        do {
            try await accessibilityService.setWindowFrame(window, to: axFrame)
            print("Snapped to \(position)")
            
            // Notify tiling manager about the ratio change for side snaps
            if [.leftHalf, .rightHalf].contains(position) {
                TilingManager.shared.updateWindowRatio(
                    windowId: window.id,
                    ratio: ratio,
                    newFrame: axFrame
                )
            }
        } catch {
            print("Failed to snap window: \(error)")
        }
    }
    
    /// Toggle fullscreen for the focused window
    func toggleFullscreen() async {
        guard let window = await accessibilityService.getFocusedWindow() else {
            print("No focused window")
            return
        }
        
        // If window is already maximized-ish, center it. Otherwise maximize.
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowCoverage = (window.frame.width * window.frame.height) / (screenFrame.width * screenFrame.height)
            
            let targetPosition: SnapPosition = windowCoverage > 0.8 ? .center : .maximize
            
            await snapTo(targetPosition)
            print(targetPosition == .maximize ? "Maximized" : "Centered")
        }
    }
    
    // MARK: - Monitor Operations
    
    /// Focus a window on the monitor in the specified direction
    @MainActor
    func focusMonitor(_ direction: Direction) async {
        guard let currentWindow = await accessibilityService.getFocusedWindow() else {
            print("No focused window to determine current screen")
            return
        }
        
        guard let curScreen = screenContaining(window: currentWindow) else { return }
        let allScreens = NSScreen.screens
        
        guard let target = findScreen(in: direction, from: curScreen, allScreens: allScreens) else {
            print("No monitor in direction \(direction)")
            return
        }
        
        let allWindows = await accessibilityService.getAllWindows()
        
        // Filter for windows on target screen
        let targetFrameFlipped = flippedFrame(for: target)
        
        let windowsOnTarget = allWindows.filter { window in
            let intersection = window.frame.intersection(targetFrameFlipped)
            return intersection.width * intersection.height > 1000 // significant overlap
        }
        
        if let bestWindow = windowsOnTarget.first {
            do {
                try await accessibilityService.focusWindow(bestWindow)
                print("Switched to monitor: \(target.localizedName) -> \(bestWindow.title)")
            } catch {
                print("Failed to focus window on target monitor: \(error)")
            }
        } else {
            print("No windows on target monitor")
        }
    }
    
    /// Move the focused window to the monitor in the specified direction
    @MainActor
    func moveWindowToMonitor(_ direction: Direction) async {
        guard let currentWindow = await accessibilityService.getFocusedWindow() else {
            print("No focused window")
            return
        }
        
        guard let curScreen = screenContaining(window: currentWindow) else {
            print("Could not determine current screen")
            return
        }
        
        let allScreens = NSScreen.screens
        
        // If only one screen, wrap around (effectively a no-op for single monitor)
        guard allScreens.count > 1 else {
            print("Only one monitor available")
            return
        }
        
        // Find target monitor: If direction fails, cycle to first/last
        var target = findScreen(in: direction, from: curScreen, allScreens: allScreens)
        
        // If no screen in direction, cycle (wrap around)
        if target == nil {
            // Sort screens by X position for left/right, Y for up/down
            let sorted = allScreens.sorted { a, b in
                let fA = flippedFrame(for: a)
                let fB = flippedFrame(for: b)
                switch direction {
                case .left, .right: return fA.origin.x < fB.origin.x
                case .up, .down: return fA.origin.y < fB.origin.y
                }
            }
            
            // Wrap around based on direction
            switch direction {
            case .right, .down:
                target = sorted.first // Wrap to first
            case .left, .up:
                target = sorted.last  // Wrap to last
            }
        }
        
        guard let targetScreen = target, targetScreen != curScreen else {
            print("No target monitor found")
            return
        }
        
        // Calculate new position: center of target screen's visible frame (in AX coords)
        let targetFrame = targetScreen.visibleFrameForAX
        let newOrigin = CGPoint(
            x: targetFrame.origin.x + (targetFrame.width - currentWindow.frame.width) / 2,
            y: targetFrame.origin.y + (targetFrame.height - currentWindow.frame.height) / 2
        )
        
        let newFrame = CGRect(origin: newOrigin, size: currentWindow.frame.size)
        
        do {
            try await accessibilityService.setWindowFrame(currentWindow, to: newFrame)
            print("Moved window to monitor: \(targetScreen.localizedName)")
        } catch {
            print("Failed to move window to monitor: \(error)")
        }
    }
    
    // MARK: - Workspace Operations
    
    /// Switch to a specific workspace
    func switchToWorkspace(_ id: Int) async {
        await WorkspaceManager.shared.switchToWorkspace(id)
        print("Switched to Workspace \(id)")
    }
    
    /// Move focused window to a specific workspace
    func moveWindowToWorkspace(_ id: Int) async {
        guard let window = await accessibilityService.getFocusedWindow() else {
            print("No focused window")
            return
        }
        
        await WorkspaceManager.shared.moveWindow(window, toWorkspace: id)
        
        // Follow the window? Or stay?
        // Typically people want to follow or stay. AeroSpace stays.
        // Let's stay in current workspace for now.
        print("Moved '\(window.title)' to Workspace \(id)")
    }
    
    // MARK: - Helpers
    
    @MainActor
    private func screenContaining(window: Window) -> NSScreen? {
        var maxIntersection: CGFloat = 0
        var bestScreen: NSScreen?
        
        for screen in NSScreen.screens {
            // Flip screen to Top-Left
            let screenFrame = flippedFrame(for: screen)
            let intersection = window.frame.intersection(screenFrame)
            let area = intersection.width * intersection.height
            if area > maxIntersection {
                maxIntersection = area
                bestScreen = screen
            }
        }
        return bestScreen
    }
    
    @MainActor
    private func findScreen(in direction: Direction, from source: NSScreen, allScreens: [NSScreen]) -> NSScreen? {
        let sourceFrame = flippedFrame(for: source)
        let center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        
        let candidates = allScreens.filter { screen in
            guard screen != source else { return false }
            let sFrame = flippedFrame(for: screen)
            let sCenter = CGPoint(x: sFrame.midX, y: sFrame.midY)
            
            switch direction {
            case .left:  return sCenter.x < center.x
            case .right: return sCenter.x > center.x
            case .up:    return sCenter.y < center.y
            case .down:  return sCenter.y > center.y
            }
        }
        
        return candidates.min { a, b in
            let fA = flippedFrame(for: a)
            let fB = flippedFrame(for: b)
            let cA = CGPoint(x: fA.midX, y: fA.midY)
            let cB = CGPoint(x: fB.midX, y: fB.midY)
            return distance(center, cA) < distance(center, cB)
        }
    }
    
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return hypot(a.x - b.x, a.y - b.y)
    }
    
    @MainActor
    private func flippedFrame(for screen: NSScreen) -> CGRect {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return screen.frame }
        let f = screen.frame
        return CGRect(x: f.origin.x, y: mainHeight - f.origin.y - f.height, width: f.width, height: f.height)
    }
    
    /// Calculate weighted distance - prefer windows that are more directly in the target direction
    private func weightedDistance(from source: Window, to target: Window, direction: Direction) -> CGFloat {
        let dx = abs(target.center.x - source.center.x)
        let dy = abs(target.center.y - source.center.y)
        
        // Weight perpendicular distance more heavily to prefer windows that are more aligned
        switch direction {
        case .left, .right:
            // Horizontal movement - weight Y distance more
            return dx + (dy * 2)
        case .up, .down:
            // Vertical movement - weight X distance more
            return (dx * 2) + dy
        }
    }
    
    /// Get all windows for debugging
    func debugPrintWindows() async {
        let windows = await accessibilityService.getAllWindows()
        print("\n=== Windows (\(windows.count)) ===")
        for (index, window) in windows.enumerated() {
            print("[\(index + 1)] \(window.appName): \(window.title)")
            print("    Frame: \(window.frame)")
        }
        print("===========================\n")
    }
}
