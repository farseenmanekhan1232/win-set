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

    init() {}
    
    func start() {
        WindowObserver.shared.delegate = self
        WindowObserver.shared.start()
        
        // Load gaps from config
        let gaps = CGFloat(ConfigService.shared.config.gaps)
        for engine in engines.values {
            engine.gaps = gaps
        }
        
        // Discover existing windows
        discoverExistingWindows()
        
        print("TilingManager: Started")
    }
    
    private func discoverExistingWindows() {
        Task {
            let windows = await AccessibilityService.shared.getAllWindows()
            print("TilingManager: Discovered \(windows.count) existing windows")
            
            self.queue.async {
                var needsLayout = Set<CGDirectDisplayID>()
                var windowsByScreen: [CGDirectDisplayID: [WindowID]] = [:]
                
                for window in windows {
                    guard window.frame.width >= self.minWindowSize &&
                          window.frame.height >= self.minWindowSize else { continue }
                    guard !window.isFullscreen && !window.isMinimized else { continue }
                    
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
        
        for event in events {
            switch event {
            case .windowCreated(let axWin, let app):
                if let winId = getWindowID(from: axWin) {
                    let frame = getFrame(from: axWin)
                    
                    guard frame.width >= minWindowSize && frame.height >= minWindowSize else {
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
                }
                
            case .windowFocused(let axWin, _):
                if let winId = getWindowID(from: axWin) {
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
                    let frame = getFrame(from: axWin)
                    let newScreenId = getScreenID(for: frame)

                    // Only re-tile if moved to DIFFERENT screen
                    if let oldScreenId = windowScreens[winId], oldScreenId != newScreenId {
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

                let frame = getFrame(from: axWin)
                frameCache[winId] = frame

                // Start resize detection if not already active
                if !isResizingOrDragging {
                    isResizingOrDragging = true
                    resizeDragScreenId = screenId
                    print("Resize started - pausing layout")
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
        let engine = getEngine(for: screenId)
        let screenFrame = screen.visibleFrameForAX
        let targetFrames = engine.calculateFrames(for: screenFrame)
        
        print("📐 Layout Screen \(screenId): \(engine.windowIds.count) windows → \(targetFrames.count) frames")
        print("   Screen frame: \(screenFrame)")
        
        for (winId, targetFrame) in targetFrames {
            print("   Window \(winId) → \(Int(targetFrame.width))×\(Int(targetFrame.height)) at (\(Int(targetFrame.origin.x)), \(Int(targetFrame.origin.y)))")
            
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
              let screenId = resizeDragScreenId else { return }

        isResizingOrDragging = false
        resizeDragScreenId = nil

        print("Resize/Drag completed - adapting layout")

        applyAdaptedLayout(for: screenId)
    }

    /// Called when drag debounce timer fires - handles window swap
    private func handleDragSwapCompletion(movedWindow: WindowID, newFrame: CGRect) {
        let screenId = resizeDragScreenId
        let engine = engines[screenId ?? CGMainDisplayID()]
        let screen = getScreen(id: screenId ?? CGMainDisplayID())

        // Reset state early
        isResizingOrDragging = false
        resizeDragScreenId = nil

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
    private func applyAdaptedLayout(for screenId: CGDirectDisplayID) {
        guard let screen = getScreen(id: screenId),
              let engine = engines[screenId] else { return }

        // Find the window that was resized
        let resizedWindowId: WindowID? = nil
        let resizedFrame: CGRect? = nil

        // For now, use standard layout
        // A more sophisticated implementation would track which window was resized
        applyLayout(for: screenId)
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
    
    private func getScreenID(for frame: CGRect) -> CGDirectDisplayID {
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
