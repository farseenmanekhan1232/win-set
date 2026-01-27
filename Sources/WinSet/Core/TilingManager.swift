import Cocoa
import Foundation

/// Coordinator that reacts to window events and updates the LayoutEngine
class TilingManager: WindowObserverDelegate {

    static let shared = TilingManager()

    private let accessibilityService = AccessibilityService.shared
    private var engines: [CGDirectDisplayID: LayoutEngine] = [:]

    // Window tracking
    private var windowScreens: [WindowID: CGDirectDisplayID] = [:]
    private var axCache: [WindowID: AXUIElement] = [:]
    private var frameCache: [WindowID: CGRect] = [:]

    private let queue = DispatchQueue(label: "com.winset.tiling", qos: .userInteractive)

    // Reconciliation timer
    private var reconciliationTimer: Timer?

    // Minimum window size to consider for tiling
    private let minWindowSize: CGFloat = 100

    // Resize/Drag state management
    private var isResizingOrDragging = false
    private var resizeDragDebounceTimer: Timer?
    private var resizeDragScreenId: CGDirectDisplayID?
    private let resizeDebounceInterval: TimeInterval = 0.15
    private let dragThreshold: CGFloat = 50
    
    // User resize tracking (for adaptive layout)
    private var activeResizeWindowId: WindowID?
    private var resizeStartFrame: CGRect?

    init() {}
    
    func start() {
        WindowObserver.shared.delegate = self
        WindowObserver.shared.start()
        
        // Load gaps from config
        let gaps = CGFloat(ConfigService.shared.config.gaps)
        for engine in engines.values {
            engine.gaps = gaps
        }
        
        // Observe Space changes (user switching desktops)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Discover existing windows
        discoverExistingWindows()
        
        print("TilingManager: Started")
    }
    
    @objc private func spaceDidChange(_ notification: Notification) {
        print("🔄 Space changed - updating window tracking")
        
        // Don't clear everything - just update tracking for the new Space
        // This preserves existing window positions
        queue.async {
            // Clear tracking caches but keep frameCache to avoid re-tiling
            // The next applyLayout will filter by on-screen status
            for (_, engine) in self.engines {
                engine.prune(keeping: [])
            }
            self.windowScreens.removeAll()
            self.axCache.removeAll()
            // Note: NOT clearing frameCache - this preserves layout state
        }
        
        // Re-discover windows on new Space WITHOUT applying layout
        discoverExistingWindowsWithoutLayout()
    }
    
    /// Discover windows but don't apply layout (used for Space changes)
    private func discoverExistingWindowsWithoutLayout() {
        Task {
            let windows = await AccessibilityService.shared.getAllWindows()
            let onScreenIds = AccessibilityService.shared.getOnScreenWindowIDs()
            print("TilingManager: Space switch - found \(onScreenIds.count) windows on current Space")
            
            self.queue.async {
                for window in windows {
                    guard !window.isFullscreen && !window.isMinimized else { continue }
                    
                    // Filter out windows on other Spaces
                    guard onScreenIds.contains(window.id) else { continue }
                    
                    // Filter Logic
                    if self.shouldIgnore(window: window.axElement, appName: window.appName, title: window.title, frame: window.frame) {
                        continue
                    }
                    
                    let screenId = self.getScreenID(for: window.frame)
                    
                    // Only add if not already tracked
                    if self.axCache[window.id] == nil {
                        self.windowScreens[window.id] = screenId
                        self.axCache[window.id] = window.axElement
                        self.getEngine(for: screenId).addWindow(window.id)
                        
                        // Store current frame (don't change position)
                        self.frameCache[window.id] = window.frame
                    }
                }
            }
        }
    }
    
    // MARK: - Window Filtering
    
    /// Check if a window should be ignored
    private func shouldIgnore(window axWin: AXUIElement, appName: String?, title: String?, frame: CGRect?) -> Bool {
        // 1. Configured Ignored Apps
        let ignoredApps = ConfigService.shared.config.ignoredApps
        if let appName = appName, ignoredApps.contains(appName) {
            return true
        }
        
        // 2. Role Checking (Must be a standard window)
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWin, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String {
            if role != kAXWindowRole as String {
                print("  Ignored (Role: \(role)): \(appName ?? "?")")
                return true
            }
        }
        
        // 3. Subrole Checking
        // Ignore standard dialogs, sheets, system dialogs
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWin, kAXSubroleAttribute as CFString, &subroleRef)
        if let subrole = subroleRef as? String {
            if ["AXDialog", "AXSystemDialog", "AXFloatingWindow", "AXUnknown"].contains(subrole) {
                print("  Ignored (Subrole: \(subrole)): \(appName ?? "?")")
                return true
            }
        }
        
        // 4. Title Heuristics
        // Note: We STOPPED filtering empty titles because:
        // - Terminal emulators like Ghostty often have empty titles
        // - Some Chromium-based apps have empty titles for main windows
        // The subrole, size, and resizability checks are more reliable
        
        // 5. Size Heuristics
        // Ignore very small windows (likely tooltips, hidden helpers)
        if let frame = frame {
            // Increased threshold to 150 to catch slightly larger popups
            if frame.width < 150 || frame.height < 150 {
                 print("  Ignored (Too Small): \(appName ?? "?") - \(Int(frame.width))x\(Int(frame.height))")
                return true
            }
        }
        
        // 6. Resizability Check
        // Most tiling candidates are resizable. Spotlight-like search bars (Notion, Raycast, etc.) usually aren't.
        var resizableRef: CFTypeRef?
        // "AXResizable" is the boolean attribute
        AXUIElementCopyAttributeValue(axWin, "AXResizable" as CFString, &resizableRef)
        // Default to true if attribute is missing to be safe, but if explicit false, ignore it.
        if let resizable = resizableRef as? Bool, resizable == false {
            print("  Ignored (Not Resizable): \(appName ?? "?")")
            return true
        }
        
        // 7. Standard Window Buttons Check
        // Main windows usually have a minimize button. Dialogs/Popups/Splash screens usually don't.
        var minBtnRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWin, kAXMinimizeButtonAttribute as CFString, &minBtnRef)
        // If we can't get the minimize button, it's likely a custom/non-standard window.
        if minBtnRef == nil {
             print("  Ignored (No Minimize Button): \(appName ?? "?")")
             return true
        }
        
        return false
    }

    // MARK: - Window Discovery & Events

    private func discoverExistingWindows() {
        Task {
            let windows = await AccessibilityService.shared.getAllWindows()
            let onScreenIds = AccessibilityService.shared.getOnScreenWindowIDs()
            print("TilingManager: Discovered \(windows.count) AX windows")
            print("  On-screen IDs from CGWindowList: \(onScreenIds.sorted())")
            print("  AX window IDs: \(windows.map { $0.id }.sorted())")
            
            self.queue.async {
                var needsLayout = Set<CGDirectDisplayID>()
                var windowsByScreen: [CGDirectDisplayID: [WindowID]] = [:]
                
                for window in windows {
                    guard !window.isFullscreen && !window.isMinimized else { continue }
                    
                    // Filter out windows on other Spaces/Desktops
                    guard onScreenIds.contains(window.id) else {
                        print("  ⏭️ Skipping window \(window.id) (\(window.appName)) - not in on-screen set")
                        continue
                    }
                    
                    // Filter Logic
                    if self.shouldIgnore(window: window.axElement, appName: window.appName, title: window.title, frame: window.frame) {
                        continue
                    }
                    
                    let screenId = self.getScreenID(for: window.frame)
                    
                    if self.axCache[window.id] == nil {
                        print("  → Window \(window.id) (\(window.appName)) → Screen \(screenId)")
                        self.windowScreens[window.id] = screenId
                        self.axCache[window.id] = window.axElement
                        self.getEngine(for: screenId).addWindow(window.id)
                        needsLayout.insert(screenId)
                        
                        windowsByScreen[screenId, default: []].append(window.id)
                    }
                }
                
                // Log per-screen summary
                for (screenId, winIds) in windowsByScreen {
                    let engine = self.getEngine(for: screenId)
                    print("  📺 Screen \(screenId): \(winIds.count) windows, engine has \(engine.windowIds.count)")
                }
                
                for screenId in needsLayout {
                    self.applyLayout(for: screenId)
                }
            }
        }
    }
    
    // MARK: - Public API
    
    /// Manually re-tile all windows on the current screen (hotkey command)
    func retileCurrentScreen() async {
        guard let focusedWindow = await accessibilityService.getFocusedWindow() else {
            print("No focused window to determine screen")
            return
        }
        
        let screenId = getScreenID(for: focusedWindow.frame)
        
        print("🔄 Re-tiling screen \(screenId)")
        queue.async {
            // Check if the focused window is missing from our tracking (e.g. was ignored)
            if self.axCache[focusedWindow.id] == nil {
                // Try to add it now
                if !self.shouldIgnore(window: focusedWindow.axElement, appName: focusedWindow.appName, title: focusedWindow.title, frame: focusedWindow.frame) {
                     print("  → Adding previously ignored window \(focusedWindow.id) (\(focusedWindow.appName))")
                     self.windowScreens[focusedWindow.id] = screenId
                     self.axCache[focusedWindow.id] = focusedWindow.axElement
                     self.getEngine(for: screenId).addWindow(focusedWindow.id)
                }
            }
            
            self.applyLayout(for: screenId)
        }
    }
    
    /// Swap the focused window with the window in the specified direction
    func swapWindowInDirection(_ direction: Direction) async -> Bool {
        guard let focusedWindow = await accessibilityService.getFocusedWindow() else {
            return false
        }

        let focusedId = focusedWindow.id
        guard let screenId = windowScreens[focusedId] else { return false }

        let engine = getEngine(for: screenId)
        guard let screen = getScreen(id: screenId) else { return false }

        // Get the actual current frame of the focused window (in AX coordinates)
        let focusedFrame: CGRect
        if let cachedFrame = frameCache[focusedId] {
            focusedFrame = cachedFrame
        } else {
            focusedFrame = focusedWindow.frame
        }
        let focusedCenter = CGPoint(x: focusedFrame.midX, y: focusedFrame.midY)

        // Get actual frames for all windows on this screen from frameCache
        var actualFrames: [WindowID: CGRect] = [:]
        for windowId in engine.windowIds {
            if let cachedFrame = frameCache[windowId] {
                actualFrames[windowId] = cachedFrame
            }
        }

        // If we don't have cached frames for all windows, fall back to calculated frames
        if actualFrames.count < engine.windowIds.count {
            let calculatedFrames = engine.calculateFrames(for: screen.visibleFrameForAX)
            for (windowId, calculatedFrame) in calculatedFrames {
                actualFrames[windowId] = frameCache[windowId] ?? calculatedFrame
            }
        }

        // Find nearest window in direction using ACTUAL positions
        var bestCandidate: WindowID?
        var bestDistance: CGFloat = .infinity

        for (otherId, otherFrame) in actualFrames {
            guard otherId != focusedId else { continue }

            let otherCenter = CGPoint(x: otherFrame.midX, y: otherFrame.midY)

            let isInDirection: Bool
            switch direction {
            case .left:  isInDirection = otherCenter.x < focusedCenter.x
            case .right: isInDirection = otherCenter.x > focusedCenter.x
            case .up:    isInDirection = otherCenter.y < focusedCenter.y
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
                print("🔄 Swapping window \(focusedId) with \(targetId)")
                engine.swapWindows(focusedId, targetId)
                self.applyLayout(for: screenId)
            }
            return true
        } else {
            print("⚠️ No window found in \(direction.rawValue) direction to swap with")
        }

        return false
    }
    
    // MARK: - WindowObserverDelegate
    
    func handle(events: [WindowEvent]) {
        queue.async {
            self.processEvents(events)
        }
    }
    
    private func processEvents(_ events: [WindowEvent]) {
        var needsLayout = Set<CGDirectDisplayID>()
        
        // Get current on-screen windows for Space filtering
        let onScreenIds = accessibilityService.getOnScreenWindowIDs()
        
        for event in events {
            switch event {
            case .windowCreated(let axWin, let app):
                if let winId = getWindowID(from: axWin) {
                    // Filter out windows on other Spaces/Desktops
                    guard onScreenIds.contains(winId) else {
                        print("Tiling: Skipping window \(winId) (\(app.localizedName ?? "?")) - on different Space")
                        continue
                    }
                    
                    let frame = getFrame(from: axWin)
                    
                    // Filter Logic (fetch title lazily if needed, but app name is available)
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String
                    
                    if shouldIgnore(window: axWin, appName: app.localizedName, title: title, frame: frame) {
                        print("Tiling: Ignoring new window \(winId) (\(app.localizedName ?? "?"))")
                        continue
                    }
                    
                    let screenId = getScreenID(for: frame)
                    let engine = getEngine(for: screenId)
                    
                    print("Tiling: Adding window \(winId) (\(app.localizedName ?? "?"))")
                    
                    windowScreens[winId] = screenId
                    axCache[winId] = axWin
                    engine.addWindow(winId)
                    
                    needsLayout.insert(screenId)
                }
                
            case .windowDestroyed(let element):
                var foundId: WindowID?
                for (id, cachedElement) in axCache {
                    if CFEqual(element, cachedElement) {
                        foundId = id
                        break
                    }
                }
                
                if let id = foundId {
                    print("Tiling: Removing window \(id)")
                    if let screenId = windowScreens[id] {
                        getEngine(for: screenId).removeWindow(id)
                        windowScreens.removeValue(forKey: id)
                        axCache.removeValue(forKey: id)
                        frameCache.removeValue(forKey: id)
                        needsLayout.insert(screenId)
                    }
                    // Safety: ensure it's removed from ALL screens just in case of desync
                    // (Handle Ghost Window Edge Case: iterate all engines?)
                    // Actually, 'windowScreens' is our truth. If it was wrong, we rely on prune() later.
                }
                
            case .windowFocused(let axWin, let app):
                if let winId = getWindowID(from: axWin) {
                    // Check if on current Space
                    guard onScreenIds.contains(winId) else {
                        // Window focused but on different Space - remove from tiling if present
                        if let existingScreen = windowScreens[winId] {
                            print("Tiling: Removing window \(winId) - now on different Space")
                            getEngine(for: existingScreen).removeWindow(winId)
                            windowScreens.removeValue(forKey: winId)
                            axCache.removeValue(forKey: winId)
                            frameCache.removeValue(forKey: winId)
                            needsLayout.insert(existingScreen)
                        }
                        continue
                    }
                    
                    // Check if ignored - if so, do nothing? or ensure it's removed?
                    // Ideally, if an ignored window gets focus, we just don't tile it.
                    // But if it WAS tiled and now is ignored (config change?), we should remove it.
                    // For now, simpler check:
                    
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String
                    
                    if shouldIgnore(window: axWin, appName: app.localizedName, title: title, frame: nil) {
                         // Ensure it's NOT in our tiling system if it was somehow added
                         if let existingScreen = windowScreens[winId] {
                             getEngine(for: existingScreen).removeWindow(winId)
                             windowScreens.removeValue(forKey: winId)
                             axCache.removeValue(forKey: winId)
                             needsLayout.insert(existingScreen)
                         }
                         continue
                    }
                    
                    let frame = getFrame(from: axWin)
                    let screenId = getScreenID(for: frame)
                    
                    if axCache[winId] == nil {
                        axCache[winId] = axWin
                        windowScreens[winId] = screenId
                        getEngine(for: screenId).addWindow(winId)
                        needsLayout.insert(screenId)
                    }
                    
                    getEngine(for: screenId).focusWindow(winId)
                }
                
            case .windowMoved(let axWin):
                if let winId = getWindowID(from: axWin) {
                    // Ignored check not strictly needed here if we trust it wasn't added,
                    // but good for safety if we want to support dynamic ignoring.
                    if windowScreens[winId] == nil { continue }
                    
                    let frame = getFrame(from: axWin)
                    
                    // Force re-check screen ID on every move event
                    let newScreenId = getScreenID(for: frame)
                    
                    if let oldScreenId = windowScreens[winId], oldScreenId != newScreenId {
                        print("Tiling: Window \(winId) moved screens: \(oldScreenId) -> \(newScreenId)")
                        getEngine(for: oldScreenId).removeWindow(winId)
                        getEngine(for: newScreenId).addWindow(winId)
                        windowScreens[winId] = newScreenId
                        needsLayout.insert(oldScreenId)
                        needsLayout.insert(newScreenId)
                        
                        for screenId in needsLayout {
                            applyLayout(for: screenId)
                        }
                        return
                    }
                    
                    // Check for significant move (drag threshold)
                    let oldPosition = frameCache[winId]?.origin ?? frame.origin
                    let distance = hypot(
                        frame.origin.x - oldPosition.x,
                        frame.origin.y - oldPosition.y
                    )
                    
                    if distance > dragThreshold {
                        // Significant drag detected - update position in real-time
                        frameCache[winId] = frame
                        
                        if !isResizingOrDragging {
                            isResizingOrDragging = true
                            resizeDragScreenId = windowScreens[winId]
                            print("Drag started - pausing layout")
                        }
                        
                        // Debounce for swap decision
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.resizeDragDebounceTimer?.invalidate()
                            self.resizeDragDebounceTimer = Timer.scheduledTimer(
                                withTimeInterval: 0.2,
                                repeats: false
                            ) { _ in
                                self.handleDragSwapCompletion(movedWindow: winId, newFrame: frame)
                            }
                        }
                    } else {
                        // Minor move - just update cache
                        frameCache[winId] = frame
                    }
                }
                
            case .windowResized(let axWin):
                // Update frame cache and debounce resize handling
                guard let winId = getWindowID(from: axWin),
                      let screenId = windowScreens[winId] else { return }
                
                let newFrame = getFrame(from: axWin)
                let oldFrame = frameCache[winId]
                
                // Track the window being resized for adaptive layout
                if activeResizeWindowId == nil {
                    activeResizeWindowId = winId
                    resizeStartFrame = oldFrame ?? newFrame
                    print("📏 Resize started for window \(winId)")
                }
                
                frameCache[winId] = newFrame
                
                // Start resize detection if not already active
                if !isResizingOrDragging {
                    isResizingOrDragging = true
                    resizeDragScreenId = screenId
                }
                
                // Debounce - only apply layout after user stops resizing
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.resizeDragDebounceTimer?.invalidate()
                    self.resizeDragDebounceTimer = Timer.scheduledTimer(
                        withTimeInterval: self.resizeDebounceInterval,
                        repeats: false
                    ) { _ in
                        self.finishResizeDrag()
                    }
                }
                
            default:
                break
            }
        }
        
        for screenId in needsLayout {
            applyLayout(for: screenId)
        }
    }
    
    // MARK: - Layout Application
    
    private func getEngine(for screenId: CGDirectDisplayID) -> LayoutEngine {
        if let engine = engines[screenId] {
            return engine
        }
        let newEngine = LayoutEngine()
        newEngine.gaps = CGFloat(ConfigService.shared.config.gaps)
        engines[screenId] = newEngine
        return newEngine
    }
    
    private func applyLayout(for screenId: CGDirectDisplayID) {
        guard let screen = getScreen(id: screenId) else { 
            print("⚠️ applyLayout: Screen \(screenId) not found")
            return 
        }
        
        // LAZY VALIDATION: Prune any windows that are no longer valid
        let engine = getEngine(for: screenId)
        
        // Get current on-screen windows (filters by Space)
        let onScreenIds = accessibilityService.getOnScreenWindowIDs()
        
        // We need to check if windows still exist AND are on current Space.
        // AXUIElementGetPid checks validity.
        
        var validIds = Set<WindowID>()
        for windowId in engine.windowIds {
            // First check: window must be on current Space
            guard onScreenIds.contains(windowId) else {
                print("⏭️ Window \(windowId) not on current Space - removing from layout")
                windowScreens.removeValue(forKey: windowId)
                axCache.removeValue(forKey: windowId)
                frameCache.removeValue(forKey: windowId)
                continue
            }
            
            if let element = axCache[windowId] {
                var pid: pid_t = 0
                let err = AXUIElementGetPid(element, &pid)
                if err == .success && pid > 0 {
                    validIds.insert(windowId)
                } else {
                    print("👻 Ghost window detected during layout: \(windowId) - removing")
                    // Clean up cache
                    windowScreens.removeValue(forKey: windowId)
                    axCache.removeValue(forKey: windowId)
                    frameCache.removeValue(forKey: windowId)
                }
            }
        }
        
        // Update engine with valid windows
        engine.prune(keeping: validIds)
        
        let screenFrame = screen.visibleFrameForAX
        let targetFrames = engine.calculateFrames(for: screenFrame)
        
        print("📐 Layout Screen \(screenId): \(engine.windowIds.count) windows → \(targetFrames.count) frames")
        
        for (winId, targetFrame) in targetFrames {
            // Skip if no change needed
            if let current = frameCache[winId],
               abs(current.origin.x - targetFrame.origin.x) < 2,
               abs(current.origin.y - targetFrame.origin.y) < 2,
               abs(current.width - targetFrame.width) < 2,
               abs(current.height - targetFrame.height) < 2 {
                continue
            }
            
            guard let axElement = axCache[winId] else { continue }
            
            Task {
                do {
                    try await AccessibilityService.shared.setWindowFrame(axElement, to: targetFrame)
                    self.queue.async {
                        self.frameCache[winId] = targetFrame
                    }
                } catch {
                    print("Failed to tile window \(winId): \(error)")
                }
            }
        }
    }

    // MARK: - Resize/Drag Handling

    /// Called when resize debounce timer fires
    private func finishResizeDrag() {
        guard isResizingOrDragging,
              let screenId = resizeDragScreenId else {
            cleanupResizeState()
            return
        }
        
        // Check if this was a resize (has activeResizeWindowId) or just a drag
        if let resizedWindowId = activeResizeWindowId,
           let newFrame = frameCache[resizedWindowId] {
            print("📐 Resize completed - adapting layout around window \(resizedWindowId)")
            applyAdaptedLayout(for: screenId, preservingWindow: resizedWindowId, withFrame: newFrame)
        } else {
            // Just a minor move or something - apply standard layout
            applyLayout(for: screenId)
        }
        
        cleanupResizeState()
    }
    
    /// Clean up all resize/drag tracking state
    private func cleanupResizeState() {
        isResizingOrDragging = false
        resizeDragScreenId = nil
        activeResizeWindowId = nil
        resizeStartFrame = nil
    }

    /// Called when drag debounce timer fires - handles window swap
    private func handleDragSwapCompletion(movedWindow: WindowID, newFrame: CGRect) {
        let screenId = resizeDragScreenId
        let engine = engines[screenId ?? CGMainDisplayID()]
        let screen = getScreen(id: screenId ?? CGMainDisplayID())

        // Reset state early
        cleanupResizeState()

        guard let engine = engine,
              let screen = screen else {
            return
        }

        // Get current layout to understand window positions
        let currentFrames = engine.calculateFrames(for: screen.visibleFrameForAX)

        // Find where the moved window should be in the order based on Y position
        let movedCenterY = newFrame.midY

        var newOrder: [WindowID] = []
        var insertAfterCount = 0

        for windowId in engine.windowIds {
            guard windowId != movedWindow,
                  let otherFrame = currentFrames[windowId] else { continue }

            // Windows above the moved position come first
            if otherFrame.midY < movedCenterY {
                newOrder.append(windowId)
                insertAfterCount += 1
            }
        }

        // Insert moved window at the appropriate position
        newOrder.insert(movedWindow, at: min(insertAfterCount, newOrder.count))

        // Add any windows that were below but not yet added
        for windowId in engine.windowIds {
            if !newOrder.contains(windowId) && windowId != movedWindow {
                newOrder.append(windowId)
            }
        }

        // Update engine's window order
        engine.reorderWindows(newOrder)

        print("Drag complete - window swapped to position \(insertAfterCount)")

        // Apply new layout with updated order
        applyLayout(for: screenId ?? CGMainDisplayID())
    }

    /// Apply adapted layout that preserves user's resize while redistributing other windows
    private func applyAdaptedLayout(for screenId: CGDirectDisplayID, preservingWindow: WindowID, withFrame preservedFrame: CGRect) {
        guard let screen = getScreen(id: screenId),
              let engine = engines[screenId] else { return }
        
        let screenFrame = screen.visibleFrameForAX
        let targetFrames = engine.calculateAdaptedFrames(
            for: screenFrame,
            preservedWindow: preservingWindow,
            preservedFrame: preservedFrame
        )
        
        print("📐 Adapted Layout Screen \(screenId): preserving window \(preservingWindow) at \(Int(preservedFrame.width))x\(Int(preservedFrame.height))")
        
        for (winId, targetFrame) in targetFrames {
            guard let axElement = axCache[winId] else { continue }
            
            Task {
                do {
                    try await AccessibilityService.shared.setWindowFrame(axElement, to: targetFrame)
                    self.queue.async {
                        self.frameCache[winId] = targetFrame
                    }
                } catch {
                    print("Failed to tile window \(winId): \(error)")
                }
            }
        }
    }

    private func reconcileAll() {
        Task {
            let windows = await AccessibilityService.shared.getAllWindows()
            let validIds = Set(windows.map { $0.id })
            
            for (screenId, engine) in engines {
                engine.prune(keeping: validIds)
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
        var pos = CGPoint.zero
        var size = CGSize.zero
        
        var posRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        if let val = posRef as! AXValue? { AXValueGetValue(val, .cgPoint, &pos) }
        
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        if let val = sizeRef as! AXValue? { AXValueGetValue(val, .cgSize, &size) }
        
        return CGRect(origin: pos, size: size)
    }
    
    /// Determine which screen contains the majority of the window
    /// UPDATED: Uses center point for better dragging experience
    private func getScreenID(for frame: CGRect) -> CGDirectDisplayID {
        // Use center point of the window
        let center = CGPoint(x: frame.midX, y: frame.midY)
        
        // Iterate all displays to find which one contains the center point
        // Using CGGetDisplaysWithPoint is more reliable than intersection for "mental model"
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        let result = CGGetDisplaysWithPoint(center, UInt32(displays.count), &displays, &displayCount)
        
        if result == .success && displayCount > 0 {
            return displays[0]
        }
        
        // Fallback to intersection if center point is somehow off-screen
        // (e.g. window is mostly off-screen but visible part intersects)
        return getScreenIDFallback(for: frame)
    }
    
    private func getScreenIDFallback(for frame: CGRect) -> CGDirectDisplayID {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        let result = CGGetDisplaysWithRect(frame, UInt32(displays.count), &displays, &displayCount)
        
        guard result == .success, displayCount > 0 else {
            return CGMainDisplayID()
        }
        
        if displayCount == 1 {
            return displays[0]
        }
        
        var bestDisplay = displays[0]
        var maxArea: CGFloat = 0
        
        for i in 0..<Int(displayCount) {
            let displayBounds = CGDisplayBounds(displays[i])
            let intersection = frame.intersection(displayBounds)
            let area = intersection.width * intersection.height
            
            if area > maxArea {
                maxArea = area
                bestDisplay = displays[i]
            }
        }
        
        return bestDisplay
    }
    
    private func getScreen(id: CGDirectDisplayID) -> NSScreen? {
        return NSScreen.screens.first { $0.displayID == id }
    }
}
