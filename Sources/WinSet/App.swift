import Cocoa

/// Main application class that ties everything together
class App: NSObject, NSApplicationDelegate, WindowObserverDelegate {
    
    // Services
    private let accessibilityService = AccessibilityService.shared
    private let eventTapService = EventTapService.shared
    var vimController: VimModeController!
    var windowManager: WindowManager!
    var windowObserver: WindowObserver!
    
    // UI
    var statusBarController: StatusBarController!
    
    override init() {
        super.init()
        self.vimController = VimModeController()
        self.windowManager = WindowManager(accessibilityService: accessibilityService)
    }
    
    func run() {
        print("🚀 WinSet starting...")
        
        // Step 0: Load configuration
        ConfigService.shared.load()
        
        // Step 1: Check accessibility permissions - REQUIRED
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
        
        // Step 2: Set up vim controller callbacks
        setupVimController()
        
        // Step 3: Set up event tap
        setupEventTap()
        
        // Setup menu bar
        statusBarController = StatusBarController(vimController: vimController)
        
        // Ensure all layouts are reset since workspaces are disabled
        Task {
            print("Disabling Workspaces: Resetting layout...")
            await WorkspaceManager.shared.resetAllWorkspaces()
        }
        
        // Setup Tiling Manager (Phase 2)
        TilingManager.shared.start()
        
        // OBSOLETE: Manual observer test
        // windowObserver = WindowObserver.shared
        // windowObserver.delegate = self
        // windowObserver.start()
        
        // Step 5: Print instructions
        printInstructions()
        
        print("✅ WinSet ready! Press Ctrl+Space to activate.")
    }
    
    private func setupVimController() {
        vimController.onModeChange = { mode in
            print("Mode: \(mode.rawValue)")
        }
        
        vimController.onCommand = { [weak self] command in
            guard let self = self else { return }
            
            Task {
                await self.executeCommand(command)
            }
        }
    }
    
    private func setupEventTap() {
        eventTapService.onKeyEvent = { [weak self] event in
            guard let self = self else { return false }
            return self.vimController.handleKey(event)
        }
        
        if !eventTapService.start() {
            print("❌ Failed to start event tap. Make sure Input Monitoring permission is granted.")
            print("   System Preferences → Privacy & Security → Input Monitoring")
        }
    }
    
    private func executeCommand(_ command: VimModeController.Command) async {
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
            
        case .switchToWorkspace(_), .moveWindowToWorkspace(_):
            print("Virtual Workspaces are currently disabled.")
           // await WorkspaceManager.shared.switchToWorkspace(id)
            
        case .enterInsertMode:
            // Visual feedback only
            print(">> INSERT MODE <<")
            
        case .enterCommandMode:
            print(">> COMMAND MODE (: to execute, Esc to cancel) <<")
            
        case .enterNormalMode:
            print(">> NORMAL MODE <<")
            
        case .exitToDisabled, .exitToNormal:
            print(">> DISABLED <<")
            
        case .cycleWindows:
            break // TODO
            
        case .resetWorkspaces:
            await WorkspaceManager.shared.resetAllWorkspaces()
            print("Layout reset.")
            
        case .debugState:
            await WorkspaceManager.shared.validateState()
            await windowManager.debugPrintWindows()
        }
    }
    
    private func printInstructions() {
        print("""
        
        ╔═══════════════════════════════════════════════════════╗
        ║                    WinSet Keybindings                 ║
        ╠═══════════════════════════════════════════════════════╣
        ║  Hold Ctrl      Activate Window Management            ║
        ║                                                       ║
        ║  While Holding Ctrl:                                  ║
        ║    h/j/k/l      Focus window left/down/up/right       ║
        ║    Shift+H/J..  Snap to left/bottom/top/right half    ║
        ║    [ / ]        Focus Monitor Left / Right            ║
        ║    1-9          Switch to Workspace 1-9               ║
        ║    Shift+1-9    Move window to Workspace 1-9          ║
        ║    f            Center window                         ║
        ║    Shift+F      Maximize window                       ║
        ║    :            Enter command mode                    ║
        ║                                                       ║
        ║  Command Mode (:):                                    ║
        ║    workspace <n> Switch Workspace                     ║
        ║    move to workspace <n> Move Window                  ║
        ║    q/quit       Exit                                  ║
        ╚═══════════════════════════════════════════════════════╝
        
        """)
    }
    
    /// Cleanup on exit
    func shutdown() {
        eventTapService.stop()
        print("👋 WinSet stopped")
    }
    
    // MARK: - WindowObserverDelegate
    func handle(events: [WindowEvent]) {
        print("--- Processed Batch: \(events.count) Events ---")
        for event in events {
            switch event {
            case .windowCreated(_, let app):
                print("  [+] Created: \(app.localizedName ?? "?")")
            case .windowDestroyed:
                print("  [-] Destroyed")
            case .windowFocused(_, let app):
                print("  [>] Focused: \(app.localizedName ?? "?")")
            case .windowMoved:
                print("  [~] Moved")
            case .windowResized:
                print("  [~] Resized")
            case .appLaunched(let app):
                print("  [*] App Launched: \(app.localizedName ?? "?")")
            case .appTerminated(let pid):
                print("  [*] App Terminated: PID \(pid)")
            }
        }
    }
}
