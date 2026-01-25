import Cocoa

/// Simple status bar controller for the menu bar icon
class StatusBarController {
    
    private var statusItem: NSStatusItem?
    
    init() {
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem?.button else { return }
        
        // Use SF Symbol for clean icon
        if let image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "WinSet") {
            image.isTemplate = true
            button.image = image
        } else {
            // Fallback to text if SF Symbol unavailable
            button.title = "⊞"
        }
        
        // Create menu
        let menu = NSMenu()
        
        // Title
        let titleItem = NSMenuItem(title: "WinSet", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Keybindings help
        menu.addItem(createKeybindingsSubmenu())
        
        // ... existing menu items
        menu.addItem(NSMenuItem.separator())
        
        // Ignore App
        let ignoreItem = NSMenuItem(title: "Ignore Focused App", action: #selector(ignoreFocusedApp), keyEquivalent: "")
        ignoreItem.target = self
        menu.addItem(ignoreItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    private func createKeybindingsSubmenu() -> NSMenuItem {
        let submenu = NSMenu()
        
        let bindings = [
            ("Ctrl + h/j/k/l", "Focus left/down/up/right"),
            ("Ctrl + Shift + H/J/K/L", "Snap to half"),
            ("Ctrl + f", "Center window"),
            ("Ctrl + Shift + F", "Maximize window"),
            ("Ctrl + [ / ]", "Focus monitor left/right"),
            ("Ctrl + r", "Re-tile screen")
        ]
        
        for (key, description) in bindings {
            let item = NSMenuItem(title: "\(key) — \(description)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
        
        let item = NSMenuItem(title: "Keybindings", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func ignoreFocusedApp() {
        Task {
            if let window = await AccessibilityService.shared.getFocusedWindow() {
                let appName = window.appName
                
                // Add to ignore list
                ConfigService.shared.ignoreApp(appName)
                
                // Trigger retile to remove it from layout immediately
                await TilingManager.shared.retileCurrentScreen()
                
                // Optional: Show alert/notification?
                // For now, just print logic is handled in ConfigService
            }
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
