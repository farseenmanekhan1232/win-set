import Cocoa
import Foundation

/// Coordinator class that reacts to Window Events and updates the LayoutEngine
class TilingManager: WindowObserverDelegate {
    
    static let shared = TilingManager()
    
    private let accessibilityService = AccessibilityService.shared
    private var engines: [CGDirectDisplayID: LayoutEngine] = [:]
    
    // Mapping Window -> Screen (Cache)
    private var windowScreens: [WindowID: CGDirectDisplayID] = [:]
    
    // Mapping Window -> AXUIElement (For identity checks)
    private var axCache: [WindowID: AXUIElement] = [:]
    
    // Known frames for diffing optimization
    private var frameCache: [WindowID: CGRect] = [:]
    
    private let queue = DispatchQueue(label: "com.winset.tiling", qos: .userInteractive)
    
    // Reconciliation timer
    private var reconciliationTimer: Timer?
    
    // Minimum window size to consider for tiling
    private let minWindowSize: CGFloat = 100
    
    init() {}
    
    func start() {
        WindowObserver.shared.delegate = self
        WindowObserver.shared.start()
        
        // Discover existing windows on startup
        discoverExistingWindows()
        
        // Schedule periodic reconciliation
        scheduleReconciliation()
        
        print("TilingManager: Started")
    }
    
    private func discoverExistingWindows() {
        Task {
            let windows = await AccessibilityService.shared.getAllWindows()
            print("TilingManager: Discovered \(windows.count) existing windows")
            
            self.queue.async {
                var needsLayout = Set<CGDirectDisplayID>()
                
                for window in windows {
                    // Skip tiny windows
                    guard window.frame.width >= self.minWindowSize && 
                          window.frame.height >= self.minWindowSize else {
                        continue
                    }
                    
                    // Skip fullscreen or minimized windows
                    guard !window.isFullscreen && !window.isMinimized else {
                        continue
                    }
                    
                    let screenId = self.getScreenID(for: window.frame)
                    
                    // Only add if not already tracked
                    if self.axCache[window.id] == nil {
                        print("Tiling: Discovered window \(window.id) (\(window.appName)) on screen \(screenId)")
                        self.windowScreens[window.id] = screenId
                        self.axCache[window.id] = window.axElement
                        self.getEngine(for: screenId).addWindow(window.id)
                        needsLayout.insert(screenId)
                    }
                }
                
                // Apply layouts after discovering windows
                for screenId in needsLayout {
                    self.applyLayout(for: screenId)
                }
            }
        }
    }
    
    private func scheduleReconciliation() {
        DispatchQueue.main.async {
            self.reconciliationTimer?.invalidate()
            self.reconciliationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.reconcileAll()
            }
        }
    }
    
    func stop() {
        WindowObserver.shared.stop()
        DispatchQueue.main.async {
            self.reconciliationTimer?.invalidate()
            self.reconciliationTimer = nil
        }
    }
    
    /// Swap the focused window with the window in the specified direction
    /// Returns: true if swap occurred, false if no window found in that direction
    func swapWindowInDirection(_ direction: Direction) async -> Bool {
        guard let focusedWindow = await accessibilityService.getFocusedWindow() else {
            print("Tiling: No focused window for swap")
            return false
        }
        
        let focusedId = focusedWindow.id
        
        guard let screenId = windowScreens[focusedId] else {
            print("Tiling: Focused window not tracked")
            return false
        }
        
        let engine = getEngine(for: screenId)
        guard let screen = getScreen(id: screenId) else { return false }
        
        let targetFrames = engine.calculateFrames(for: screen.visibleFrameForAX)
        guard let focusedFrame = targetFrames[focusedId] else { return false }
        
        let focusedCenter = CGPoint(x: focusedFrame.midX, y: focusedFrame.midY)
        
        // Find the nearest window in the specified direction
        var bestCandidate: WindowID?
        var bestDistance: CGFloat = .infinity
        
        for (otherId, otherFrame) in targetFrames {
            guard otherId != focusedId else { continue }
            
            let otherCenter = CGPoint(x: otherFrame.midX, y: otherFrame.midY)
            
            // Check if other window is in the correct direction
            let isInDirection: Bool
            switch direction {
            case .left:  isInDirection = otherCenter.x < focusedCenter.x
            case .right: isInDirection = otherCenter.x > focusedCenter.x
            case .up:    isInDirection = otherCenter.y < focusedCenter.y  // AX coords: lower Y is higher
            case .down:  isInDirection = otherCenter.y > focusedCenter.y
            }
            
            guard isInDirection else { continue }
            
            let distance = hypot(otherCenter.x - focusedCenter.x, otherCenter.y - focusedCenter.y)
            if distance < bestDistance {
                bestDistance = distance
                bestCandidate = otherId
            }
        }
        
        if let targetId = bestCandidate {
            queue.async {
                engine.swapWindows(focusedId, targetId)
                self.applyLayout(for: screenId)
            }
            return true
        } else {
            print("Tiling: No window in direction \(direction) to swap with")
            return false
        }
    }
    
    /// Update the BSP split ratio for a window (called after manual snap)
    func updateWindowRatio(windowId: WindowID, ratio: CGFloat, newFrame: CGRect) {
        queue.async {
            guard let screenId = self.windowScreens[windowId] else { return }
            let engine = self.getEngine(for: screenId)
            
            // Update the split ratio
            engine.updateSplitRatio(for: windowId, newRatio: ratio)
            
            // Update frame cache to prevent diffing from reverting
            self.frameCache[windowId] = newFrame
            
            // Apply layout to other windows
            self.applyLayout(for: screenId)
        }
    }
    
    // MARK: - WindowObserverDelegate
    
    func handle(events: [WindowEvent]) {
        queue.async {
            self.processEvents(events)
        }
    }
    
    private func processEvents(_ events: [WindowEvent]) {
        var needsLayout = Set<CGDirectDisplayID>()
        
        for event in events {
            switch event {
            case .windowCreated(let axWin, let app):
                // We need to resolve WindowID and Screen
                if let winId = getWindowID(from: axWin) {
                    let frame = getFrame(from: axWin)
                    
                    // Filter: Skip tiny windows (tooltips, menus, etc.)
                    guard frame.width >= minWindowSize && frame.height >= minWindowSize else {
                        continue
                    }
                    
                    let screenId = getScreenID(for: frame)
                    let engine = getEngine(for: screenId)
                    
                    // Check max windows per screen limit
                    let maxWindows = ConfigService.shared.config.maxWindowsPerScreen
                    if maxWindows > 0 && engine.windowIds.count >= maxWindows {
                        print("Tiling: Screen \(screenId) at max capacity (\(maxWindows)), ignoring window \(winId)")
                        continue
                    }
                    
                    print("Tiling: Adding Window \(winId) (\(app.localizedName ?? "Unknown")) to Screen \(screenId)")
                    
                    windowScreens[winId] = screenId
                    axCache[winId] = axWin // Cache for identity check
                    
                    engine.addWindow(winId)
                    engine.focusWindow(winId)
                    
                    needsLayout.insert(screenId)
                }
                
            case .windowDestroyed(let element):
                // "Smart" Destruction:
                // Check if this element matches any of our tracked windows.
                // AXUIElement equality (CFEqual) works even on dead elements?
                // Often yes, they are tokens.
                
                var foundId: WindowID?
                for (id, cachedElement) in axCache {
                    if CFEqual(element, cachedElement) {
                        foundId = id
                        break
                    }
                }
                
                if let id = foundId {
                    print("Tiling: Window \(id) Destroyed. Removing.")
                    if let screenId = windowScreens[id] {
                        getEngine(for: screenId).removeWindow(id)
                        windowScreens.removeValue(forKey: id)
                        axCache.removeValue(forKey: id)
                        frameCache.removeValue(forKey: id)
                        needsLayout.insert(screenId)
                    }
                } else {
                    // It was likely a tooltip, menu, or untracked window. Ignore.
                    // print("Tiling: Ignored destruction of untracked element.")
                }
                
            case .windowFocused(let axWin, _):
                 if let winId = getWindowID(from: axWin) {
                     let frame = getFrame(from: axWin)
                     let screenId = getScreenID(for: frame)
                     
                     // Helper: If we didn't track it yet (started before us), add different?
                     if axCache[winId] == nil {
                         axCache[winId] = axWin
                         windowScreens[winId] = screenId
                         getEngine(for: screenId).addWindow(winId)
                         needsLayout.insert(screenId)
                     }
                     
                     getEngine(for: screenId).focusWindow(winId)
                 }

            case .windowMoved(let axWin):
                // Handle window movement: check for monitor change OR position swap
                if let winId = getWindowID(from: axWin) {
                    let frame = getFrame(from: axWin)
                    let newScreenId = getScreenID(for: frame)
                    
                    // Check if changed screen
                    if let oldScreenId = windowScreens[winId], oldScreenId != newScreenId {
                        print("Tiling: Window \(winId) moved monitors \(oldScreenId) -> \(newScreenId)")
                        getEngine(for: oldScreenId).removeWindow(winId)
                        getEngine(for: newScreenId).addWindow(winId)
                        windowScreens[winId] = newScreenId
                        
                        needsLayout.insert(oldScreenId)
                        needsLayout.insert(newScreenId)
                    } else if let screenId = windowScreens[winId] {
                        // Same screen - check if user is trying to swap with another window
                        let engine = getEngine(for: screenId)
                        
                        // Find if moved window overlaps significantly with another window's target position
                        if let screen = getScreen(id: screenId) {
                            let targetFrames = engine.calculateFrames(for: screen.visibleFrameForAX)
                            
                            for (otherId, otherFrame) in targetFrames {
                                guard otherId != winId else { continue }
                                
                                // Check overlap: if moved window's center is inside other's target frame
                                let movedCenter = CGPoint(x: frame.midX, y: frame.midY)
                                if otherFrame.contains(movedCenter) {
                                    print("Tiling: Swapping \(winId) with \(otherId)")
                                    engine.swapWindows(winId, otherId)
                                    needsLayout.insert(screenId)
                                    break
                                }
                            }
                        }
                    }
                    
                    // Update frame cache so we don't fight the user immediately
                    frameCache[winId] = frame
                }

            case .windowResized:
                 // Update split ratios?
                 break
                
            default:
                break
            }
        }
        
        // Apply Layouts
        for screenId in needsLayout {
            applyLayout(for: screenId)
        }
    }
    
    // MARK: - Core Logic
    
    private func getEngine(for screenId: CGDirectDisplayID) -> LayoutEngine {
        if let engine = engines[screenId] {
            return engine
        }
        let newEngine = LayoutEngine()
        engines[screenId] = newEngine
        return newEngine
    }
    
    private func applyLayout(for screenId: CGDirectDisplayID) {
        guard let screen = getScreen(id: screenId) else { return }
        let engine = getEngine(for: screenId)
        
        // Use visibleFrameForAX for correct coordinate system (top-left origin for AX API)
        let screenFrame = screen.visibleFrameForAX
        let targetFrames = engine.calculateFrames(for: screenFrame)
        
        // Debug logging
        print("Tiling: applyLayout for screen \(screenId)")
        print("  visibleFrame (Cocoa): \(screen.visibleFrame)")
        print("  screenFrame (AX): \(screenFrame)")
        print("  Engine windows: \(engine.windowIds)")
        print("  Target frames: \(targetFrames.count)")
        
        for (winId, targetFrame) in targetFrames {
            // Diffing optimization
            if let current = frameCache[winId],
               abs(current.origin.x - targetFrame.origin.x) < 1.0,
               abs(current.origin.y - targetFrame.origin.y) < 1.0,
               abs(current.width - targetFrame.width) < 1.0,
               abs(current.height - targetFrame.height) < 1.0 {
                // No change needed
                print("  Window \(winId): no change needed (diff < 1px)")
                continue
            }
            
            // Check if we have a cached AXUIElement
            guard let axElement = axCache[winId] else {
                print("  Window \(winId): ❌ NO cached AXUIElement, skipping!")
                continue
            }
            print("  Window \(winId): applying frame -> \(targetFrame)")
            
            // Capture values for the async task
            let capturedWinId = winId
            let capturedFrame = targetFrame
            let capturedElement = axElement
            
            Task {
                do {
                    try await AccessibilityService.shared.setWindowFrame(capturedElement, to: capturedFrame)
                    // Update frame cache on the queue for thread safety
                    self.queue.async {
                        self.frameCache[capturedWinId] = capturedFrame
                    }
                } catch {
                    print("Failed to tile window \(capturedWinId): \(error)")
                }
            }
        }
    }
    
    private func reconcileAll() {
        Task {
            // Get all actual windows
            let windows = await AccessibilityService.shared.getAllWindows()
            let validIds = Set(windows.map { $0.id })
            
            print("Tiling: Reconciling. Valid windows: \(validIds.count)")
            
            // For each engine, remove dead windows
            for (screenId, engine) in engines {
                // Prune dead windows
                engine.prune(keeping: validIds)
                
                // Add any new windows that were missed (fallback)
                // Filter windows belonging to this screen
                 let screen = getScreen(id: screenId)
                 let visible = screen?.visibleFrame ?? CGRect.zero
                
                 let screenWindows = windows.filter { win in
                     if let s = screen {
                          return win.frame.intersects(visible)
                     }
                     return false
                 }
                
                // Ensure they are in tree
                // LayoutEngine doesn't support efficient "contains", so we rely on idempotency?
                // addWindow blindly adds. We need to check existence.
                // We'll trust that Prune handles removal.
                // For addition, we'd need to know if it's already there.
                // LayoutEngine V1 doesn't track set of IDs efficiently.
                // Let's rely on Pruning for now to fix Destructive instability.
                // Missed additions will be caught by "Focused" or "Created" events eventually.
                
                applyLayout(for: screenId)
            }
        }
    }

    // MARK: - Helpers
    
    private func getWindowID(from element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        let result = _AXUIElementGetWindow(element, &id)
        return result == .success ? id : nil
    }
    
    private func getFrame(from element: AXUIElement) -> CGRect {
        // ... (AXValue logic duplication, or use helper)
        // For brevity in this file:
        var pos = CGPoint.zero
        var size = CGSize.zero
        
        var posRef: CFTypeRef?; AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        if let val = posRef as! AXValue? { AXValueGetValue(val, .cgPoint, &pos) }
        
        var sizeRef: CFTypeRef?; AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        if let val = sizeRef as! AXValue? { AXValueGetValue(val, .cgSize, &size) }
        
        return CGRect(origin: pos, size: size)
    }
    
    private func getScreenID(for frame: CGRect) -> CGDirectDisplayID {
        // Use CoreGraphics for thread-safe display detection
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        // Get all displays that intersect with the window frame
        let result = CGGetDisplaysWithRect(frame, UInt32(displays.count), &displays, &displayCount)
        
        guard result == .success, displayCount > 0 else {
            return CGMainDisplayID()
        }
        
        // If only one display intersects, return it
        if displayCount == 1 {
            return displays[0]
        }
        
        // Multiple displays intersect - find the one with the largest overlap
        var bestDisplay = displays[0]
        var maxArea: CGFloat = 0
        
        for i in 0..<Int(displayCount) {
            let displayID = displays[i]
            let displayBounds = CGDisplayBounds(displayID)
            let intersection = frame.intersection(displayBounds)
            let area = intersection.width * intersection.height
            
            if area > maxArea {
                maxArea = area
                bestDisplay = displayID
            }
        }
        
        return bestDisplay
    }
    
    private func getScreen(id: CGDirectDisplayID) -> NSScreen? {
        return NSScreen.screens.first { $0.displayID == id }
    }
}
