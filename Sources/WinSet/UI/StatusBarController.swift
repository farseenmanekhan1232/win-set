import Cocoa

/// Simple status bar controller for the menu bar icon
class StatusBarController: NSObject, NSMenuDelegate {
    
    private var statusItem: NSStatusItem?
    
    override init() {
        super.init()
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
        
        // Ignore App - Dynamic title will be set in menuNeedsUpdate
        let ignoreItem = NSMenuItem(title: "Ignore Focused App", action: #selector(toggleIgnoreFocusedApp), keyEquivalent: "")
        ignoreItem.target = self
        ignoreItem.tag = 100 // Tag to find it easily
        menu.addItem(ignoreItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        menu.delegate = self
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let ignoreItem = menu.items.first(where: { $0.tag == 100 }) else { return }
        
        // Synchronously check frontmost app name
        if let app = NSWorkspace.shared.frontmostApplication,
           let name = app.localizedName {
            
            let isIgnored = ConfigService.shared.config.ignoredApps.contains(name)
            ignoreItem.title = isIgnored ? "Un-ignore \"\(name)\"" : "Ignore \"\(name)\""
            ignoreItem.isEnabled = true
        } else {
            ignoreItem.title = "Ignore Focused App"
            ignoreItem.isEnabled = false
        }
    }

    @objc private func toggleIgnoreFocusedApp() {
        Task {
            if let window = await AccessibilityService.shared.getFocusedWindow() {
                let appName = window.appName
                let isIgnored = ConfigService.shared.config.ignoredApps.contains(appName)
                
                if isIgnored {
                    ConfigService.shared.unignoreApp(appName)
                } else {
                    ConfigService.shared.ignoreApp(appName)
                }
                
                // Trigger retile to remove or add it back to layout
                await TilingManager.shared.retileCurrentScreen()
            } else {
                // Fallback using NSWorkspace if Accessibility fails to get window but we have an app
                 if let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName {
                     let isIgnored = ConfigService.shared.config.ignoredApps.contains(name)
                     if isIgnored {
                         ConfigService.shared.unignoreApp(name)
                     } else {
                         ConfigService.shared.ignoreApp(name)
                     }
                      await TilingManager.shared.retileCurrentScreen()
                 }
            }
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
