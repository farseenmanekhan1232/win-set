import Cocoa

/// Status bar controller for the menu bar icon
class StatusBarController {
    
    private var statusItem: NSStatusItem?
    private let vimController: VimModeController
    
    init(vimController: VimModeController) {
        self.vimController = vimController
        setupStatusItem()
        
        // Listen for mode changes
        vimController.onModeChange = { [weak self] mode in
            self?.updateIcon()
        }
        
        // Listen for workspace changes
        NotificationCenter.default.addObserver(
            forName: WorkspaceManager.workspaceChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateIcon()
        }
    }
    
    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let mode = vimController.currentMode
        
        // Workspace feature disabled - simplified icon
        
        // Determine icon string
        let icon: String
        switch mode {
        case .disabled: icon = "○"
        case .normal:   icon = "●"
        case .insert:   icon = "◐"
        case .command:  icon = ":"
        }
        
        button.title = "WinSet \(icon)"
        
        // Update menu text
        if let menu = self.statusItem?.menu,
           let modeItem = menu.item(withTag: 100) {
            modeItem.title = "Mode: \(mode)"
        }
    }
    
    // Legacy support for onModeChange calling with mode argument
    // We redirect to the new consolidated updateIcon()
    private func updateIcon(for mode: VimModeController.Mode) {
        updateIcon()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard statusItem?.button != nil else { return }
        
        // Set initial icon
        updateIcon(for: .disabled)
        
        // Create menu
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "WinSet", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let modeItem = NSMenuItem(title: "Mode: Disabled", action: nil, keyEquivalent: "")
        modeItem.tag = 100
        menu.addItem(modeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Keybindings", action: nil, keyEquivalent: ""))
        menu.addItem(createKeybindingsSubmenu())
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    private func createKeybindingsSubmenu() -> NSMenuItem {
        let submenu = NSMenu()
        
        let bindings = [
            ("Ctrl+Space", "Toggle normal mode"),
            ("h / j / k / l", "Focus left/down/up/right"),
            ("H / J / K / L", "Snap to left/bottom/top/right half"),
            ("f", "Center window"),
            ("F", "Maximize window"),
            ("1-9", "Focus window by number"),
            (":", "Command mode"),
            ("i", "Enter insert mode (passthrough)"),
            ("Esc", "Exit to disabled mode"),
        ]
        
        for (key, description) in bindings {
            let item = NSMenuItem(title: "\(key) — \(description)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
        
        let item = NSMenuItem(title: "Show Keybindings", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
    

    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
