import Cocoa
import ApplicationServices

/// Errors that can occur when interacting with Accessibility APIs
enum AccessibilityError: Error, LocalizedError {
    case permissionDenied
    case windowNotFound
    case attributeNotFound(String)
    case operationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission not granted. Please enable in System Preferences → Privacy & Security → Accessibility"
        case .windowNotFound:
            return "Window not found"
        case .attributeNotFound(let attr):
            return "Attribute not found: \(attr)"
        case .operationFailed(let msg):
            return "Operation failed: \(msg)"
        }
    }
}

/// Service for interacting with macOS Accessibility APIs
/// This provides window querying and manipulation capabilities
actor AccessibilityService {
    
    static let shared = AccessibilityService()
    
    private var hasPromptedForPermissionLoss = false
    
    private init() {}
    
    // MARK: - Permissions
    
    /// Check if we have accessibility permissions
    nonisolated func checkPermissions() -> Bool {
        // This will prompt the user if not already granted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Check permissions without prompting
    nonisolated func hasPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    // MARK: - Window Queries
    
    /// Get all visible windows across all applications
    func getAllWindows() -> [Window] {
        var windows: [Window] = []
        
        // Get all running applications
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        
        for app in runningApps {
            let appWindows = getWindows(for: app)
            windows.append(contentsOf: appWindows)
        }
        
        return windows
    }
    
    /// Get windows for a specific application
    func getWindows(for app: NSRunningApplication) -> [Window] {
        var windows: [Window] = []
        
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        
        // Ensure Manual Accessibility is enabled (workaround for Electron)
        enableManualAccessibility(for: axApp)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return []
        }
        
        for axWindow in axWindows {
            if let window = createWindow(from: axWindow, app: app) {
                windows.append(window)
            }
        }
        
        return windows
    }
    
    /// Get the currently focused window
    func getFocusedWindow() -> Window? {
        // Create systemWide element (recreating can help recover from some states)
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef)
        
        if appResult != .success {
            let error = appResult.rawValue
            if error == -25212 { // kAXErrorAPIDisabled
                  // Check if we lost trust completely
                  if !AXIsProcessTrusted() {
                      print("❌ Accessibility Permission LOST! Please re-grant permission in System Settings.")
                      
                      // Re-prompt user if we haven't already
                      if !hasPromptedForPermissionLoss {
                          print("⚠️  Attempting to re-trigger permission prompt...")
                          let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                          _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                          hasPromptedForPermissionLoss = true
                      }
                  } else {
                      print("⚠️  Accessibility API Disabled (Error -25212). Attempting 'AXManualAccessibility' workaround...")
                      
                      // WORKAROUND: Try to enable manual accessibility for the focused app (common for Electron)
                      if let frontApp = NSWorkspace.shared.frontmostApplication {
                          let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
                          enableManualAccessibility(for: axApp)
                          
                          // Retry fetching focused app
                          let retryResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef)
                          if retryResult == .success {
                              print("✅ Workaround successful! Got focused app.")
                          } else {
                              print("❌ Workaround failed. Still cannot access app. (Error: \(retryResult.rawValue))")
                              print("   Possible causes: Secure Input enabled, or app explicitly blocks Accessibility.")
                          }
                      }
                  }
            } else {
                 print("❌ Could not get focused application (error: \(error))")
            }
            
            // If retry succeeded, proceed. If not, return nil.
            if focusedAppRef == nil { return nil }
        }
        
        guard let focusedApp = focusedAppRef else { return nil }
        
        // Ensure Manual Accessibility is enabled (workaround for Electron)
        enableManualAccessibility(for: focusedApp as! AXUIElement)
        
        var focusedWindowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        
        if windowResult != .success {
            print("❌ Could not get focused window (error: \(windowResult.rawValue))")
            
            // Fallback: Try to get the first window of the app
            var windowsRef: CFTypeRef?
            let listResult = AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXWindowsAttribute as CFString, &windowsRef)
            
            if listResult == .success, let windows = windowsRef as? [AXUIElement], let firstWindow = windows.first {
                print("⚠️  Using first window as fallback")
                var pid: pid_t = 0
                AXUIElementGetPid(focusedApp as! AXUIElement, &pid)
                if let app = NSRunningApplication(processIdentifier: pid) {
                    return createWindowForFocused(from: firstWindow, app: app)
                }
            }
            return nil
        }
        
        guard let focusedWindow = focusedWindowRef else { return nil }
        
        // Get the PID of the focused app
        var pid: pid_t = 0
        AXUIElementGetPid(focusedApp as! AXUIElement, &pid)
        
        if let app = NSRunningApplication(processIdentifier: pid) {
            return createWindowForFocused(from: focusedWindow as! AXUIElement, app: app)
        }
        
        return nil
    }
    
    /// Create a Window from focused AXUIElement - doesn't require window ID
    private func createWindowForFocused(from axWindow: AXUIElement, app: NSRunningApplication) -> Window? {
        // Get window ID (may be 0 for some windows, but that's OK for focused window)
        var windowID: CGWindowID = 0
        _ = _AXUIElementGetWindow(axWindow, &windowID)
        
        // Get position
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
              let positionValue = positionRef else {
            print("❌ Could not get window position")
            return nil
        }
        var position = CGPoint.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        
        // Get size
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef else {
            print("❌ Could not get window size")
            return nil
        }
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        // Get title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? "Untitled"
        
        print("✅ Found focused window: \(title) from \(app.localizedName ?? "Unknown") - size \(size)")
        
        return Window(
            id: windowID,
            axElement: axWindow,
            frame: CGRect(origin: position, size: size),
            title: title,
            appName: app.localizedName ?? "Unknown",
            appPID: app.processIdentifier,
            isMinimized: false,
            isFullscreen: false
        )
    }
    
    // MARK: - Window Manipulation
    
    /// Focus a specific window
    func focusWindow(_ window: Window) throws {
        // First, activate the application
        if let app = NSRunningApplication(processIdentifier: window.appPID) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        // Then raise the window
        let result = AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        if result != .success && result != .actionUnsupported {
            throw AccessibilityError.operationFailed("Failed to raise window")
        }
        
        // Set as main window
        AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
    
    /// Move a window to a new position
    func moveWindow(_ window: Window, to position: CGPoint) throws {
        var pos = position
        let positionValue = AXValueCreate(.cgPoint, &pos)!
        
        let result = AXUIElementSetAttributeValue(window.axElement, kAXPositionAttribute as CFString, positionValue)
        if result != .success {
            throw AccessibilityError.operationFailed("Failed to move window: \(result.rawValue)")
        }
    }
    
    /// Resize a window
    func resizeWindow(_ window: Window, to size: CGSize) throws {
        var sz = size
        let sizeValue = AXValueCreate(.cgSize, &sz)!
        
        let result = AXUIElementSetAttributeValue(window.axElement, kAXSizeAttribute as CFString, sizeValue)
        if result != .success {
            throw AccessibilityError.operationFailed("Failed to resize window: \(result.rawValue)")
        }
    }
    
    /// Move and resize a window to a specific frame
    func setWindowFrame(_ window: Window, to frame: CGRect) throws {
        try moveWindow(window, to: frame.origin)
        try resizeWindow(window, to: frame.size)
    }
    
    /// Move and resize a window to a specific frame (raw AXUIElement version)
    func setWindowFrame(_ axElement: AXUIElement, to frame: CGRect) throws {
        // Get PID and enable Manual Accessibility for the app first
        var pid: pid_t = 0
        AXUIElementGetPid(axElement, &pid)
        if pid != 0 {
            let axApp = AXUIElementCreateApplication(pid)
            enableManualAccessibility(for: axApp)
        }
        
        // Move first (some apps require this order)
        var pos = frame.origin
        let positionValue = AXValueCreate(.cgPoint, &pos)!
        let moveResult = AXUIElementSetAttributeValue(axElement, kAXPositionAttribute as CFString, positionValue)
        // Don't throw on move failure, some windows are position-locked but can still resize
        if moveResult != .success && moveResult != .actionUnsupported {
            print("Warning: Move failed with \(moveResult.rawValue), continuing with resize...")
        }
        
        // Resize
        var sz = frame.size
        let sizeValue = AXValueCreate(.cgSize, &sz)!
        let resizeResult = AXUIElementSetAttributeValue(axElement, kAXSizeAttribute as CFString, sizeValue)
        if resizeResult != .success && resizeResult != .actionUnsupported {
            // Only throw if both move AND resize failed
            if moveResult != .success {
                throw AccessibilityError.operationFailed("Failed to set frame: move=\(moveResult.rawValue), resize=\(resizeResult.rawValue)")
            }
        }
    }
    
    /// Find a window by its unique ID (Slow - implementation iterates all windows)
    func findWindow(byId id: WindowID) -> Window? {
        return getAllWindows().first { $0.id == id }
    }
    
    // MARK: - Helpers
    
    /// Create a Window struct from an AXUIElement
    private func createWindow(from axWindow: AXUIElement, app: NSRunningApplication) -> Window? {
        // Get window ID
        var windowID: CGWindowID = 0
        _ = _AXUIElementGetWindow(axWindow, &windowID)
        
        guard windowID != 0 else { return nil }
        
        // Get position
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
              let positionValue = positionRef else {
            return nil
        }
        var position = CGPoint.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        
        // Get size
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef else {
            return nil
        }
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        // Skip tiny windows (likely hidden/utility windows)
        guard size.width > 100 && size.height > 100 else { return nil }
        
        // Get title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? "Untitled"
        
        // Get minimized state
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
        let isMinimized = (minimizedRef as? Bool) ?? false
        
        // Skip minimized windows
        guard !isMinimized else { return nil }
        
        // Get fullscreen state
        var fullscreenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, "AXFullScreen" as CFString, &fullscreenRef)
        let isFullscreen = (fullscreenRef as? Bool) ?? false
        
        return Window(
            id: windowID,
            axElement: axWindow,
            frame: CGRect(origin: position, size: size),
            title: title,
            appName: app.localizedName ?? "Unknown",
            appPID: app.processIdentifier,
            isMinimized: isMinimized,
            isFullscreen: isFullscreen
        )
    }
    
    /// Find the screen that contains the majority of a window
    private nonisolated func screenContaining(_ window: Window) -> NSScreen? {
        var maxIntersection: CGFloat = 0
        var bestScreen: NSScreen?
        
        for screen in NSScreen.screens {
            let intersection = window.frame.intersection(screen.frame)
            let area = intersection.width * intersection.height
            if area > maxIntersection {
                maxIntersection = area
                bestScreen = screen
            }
        }
        
        return bestScreen ?? NSScreen.main
    }
    
    /// Try to enable manual accessibility for Electron apps
    private func enableManualAccessibility(for app: AXUIElement) {
        let result = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if result == .success {
            print("✅ Enabled AXManualAccessibility for app")
        }
    }
}

// Private API to get CGWindowID from AXUIElement
// This is the only private API we use (same as AeroSpace)
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
