import Cocoa

/// Main application class that ties everything together
class App: NSObject, NSApplicationDelegate {
    
    // Services
    private let accessibilityService = AccessibilityService.shared
    private let eventTapService = EventTapService.shared
    var hotkeyController: HotkeyController!
    var windowManager: WindowManager!
    
    // UI
    var statusBarController: StatusBarController!
    
    override init() {
        super.init()
        self.hotkeyController = HotkeyController()
        self.windowManager = WindowManager(accessibilityService: accessibilityService)
    }
    
    func run() {
        print("🚀 WinSet starting...")
        
        // Load configuration
        ConfigService.shared.load()
        
        // Check accessibility permissions - REQUIRED
        if !accessibilityService.hasPermissions() {
            print("")
            print("⚠️  ═══════════════════════════════════════════════════════════")
            print("⚠️  ACCESSIBILITY PERMISSION REQUIRED")
            print("⚠️  ═══════════════════════════════════════════════════════════")
            print("⚠️")
            print("⚠️  WinSet needs Accessibility permission to manage windows.")
            print("⚠️")
            print("⚠️  Please follow these steps:")
            print("⚠️  1. Open System Settings → Privacy & Security → Accessibility")
            print("⚠️  2. Click the '+' button")
            print("⚠️  3. Navigate to: \(Bundle.main.executablePath ?? ".build/debug/winset")")
            print("⚠️  4. Add and enable it")
            print("⚠️")
            print("⚠️  Waiting for permission to be granted...")
            print("⚠️  ═══════════════════════════════════════════════════════════")
            print("")
            
            // Trigger the system permission dialog
            _ = accessibilityService.checkPermissions()
            
            // Poll until permission is granted
            while !accessibilityService.hasPermissions() {
                Thread.sleep(forTimeInterval: 1.0)
            }
            
            print("✅ Accessibility permission granted!")
        }
        
        // Set up hotkey controller
        setupHotkeyController()
        
        // Set up event tap
        setupEventTap()
        
        // Setup menu bar
        statusBarController = StatusBarController()
        
        // Start Tiling Manager
        TilingManager.shared.start()
        
        print("✅ WinSet ready! Hold Ctrl + h/j/k/l to manage windows.")
    }
    
    private func setupHotkeyController() {
        hotkeyController.onCommand = { [weak self] command in
            guard let self = self else { return }
            
            Task {
                await self.executeCommand(command)
            }
        }
    }
    
    private func setupEventTap() {
        eventTapService.onKeyEvent = { [weak self] event in
            guard let self = self else { return false }
            return self.hotkeyController.handleKey(event)
        }

        print("📝 Checking Input Monitoring permission...")
        if !eventTapService.start() {
            print("")
            print("⚠️  ═══════════════════════════════════════════════════════════")
            print("⚠️  INPUT MONITORING PERMISSION REQUIRED")
            print("⚠️  ═══════════════════════════════════════════════════════════")
            print("⚠️")
            print("⚠️  WinSet needs Input Monitoring permission to capture hotkeys.")
            print("⚠️")
            print("⚠️  Please follow these steps:")
            print("⚠️  1. Open System Settings → Privacy & Security → Input Monitoring")
            print("⚠️  2. Click the '+' button")
            print("⚠️  3. Navigate to: \(Bundle.main.executablePath ?? ".build/debug/winset")")
            print("⚠️  4. Add and enable it")
            print("⚠️  5. Restart WinSet")
            print("⚠️  ═══════════════════════════════════════════════════════════")
            print("")
        } else {
            print("✅ Input Monitoring permission granted!")
        }
    }
    
    private func executeCommand(_ command: HotkeyController.Command) async {
        switch command {
        case .focusDirection(let direction):
            await windowManager.focusDirection(direction)
            
        case .moveToHalf(let direction):
            await windowManager.moveToHalf(direction)
            
        case .snapTo(let position):
            await windowManager.snapTo(position)
        
        case .focusMonitor(let direction):
            await windowManager.focusMonitor(direction)
        
        case .moveWindowToMonitor(let direction):
            await windowManager.moveWindowToMonitor(direction)
        
        case .swapWindowInDirection(let direction):
            let swapped = await TilingManager.shared.swapWindowInDirection(direction)
            if !swapped {
                // Smart Fallback: If swap failed (e.g. at screen edge), 
                // perform resize/snap cycle for that direction instead.
                switch direction {
                case .left: await windowManager.moveToHalf(.left)
                case .right: await windowManager.moveToHalf(.right)
                case .up: await windowManager.moveToHalf(.up)
                case .down: await windowManager.moveToHalf(.down)
                }
            }
            
        case .toggleFullscreen:
            await windowManager.toggleFullscreen()
            
        case .focusWindowNumber(let number):
            await windowManager.focusWindowNumber(number)
            
        case .retileScreen:
            await TilingManager.shared.retileCurrentScreen()
        }
    }
    
    /// Cleanup on exit
    func shutdown() {
        eventTapService.stop()
        print("👋 WinSet stopped")
    }
}
