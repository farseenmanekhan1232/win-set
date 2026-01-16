import Cocoa
import ServiceManagement

class MenuBarController {
    
    private var statusItem: NSStatusItem!
    private var isEnabled = true
    
    init() {
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "WinSet")
            button.image?.isTemplate = true
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Enabled toggle
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = isEnabled ? .on : .off
        menu.addItem(enabledItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Start at Login
        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Keybindings help
        let helpItem = NSMenuItem(title: "Keybindings...", action: #selector(showKeybindings), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        
        // About
        let aboutItem = NSMenuItem(title: "About WinSet", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit WinSet", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func toggleEnabled() {
        isEnabled.toggle()
        
        if let menu = statusItem.menu, let item = menu.items.first {
            item.state = isEnabled ? .on : .off
        }
        
        // TODO: Actually enable/disable tiling
        print("WinSet \(isEnabled ? "enabled" : "disabled")")
    }
    
    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        
        do {
            if service.status == .enabled {
                try service.unregister()
                print("Removed from Login Items")
            } else {
                try service.register()
                print("Added to Login Items")
            }
        } catch {
            print("Failed to toggle login item: \(error)")
        }
        
        // Update menu
        if let menu = statusItem.menu {
            for item in menu.items where item.title == "Start at Login" {
                item.state = isLoginItemEnabled() ? .on : .off
            }
        }
    }
    
    private func isLoginItemEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    @objc private func showKeybindings() {
        let alert = NSAlert()
        alert.messageText = "WinSet Keybindings"
        alert.informativeText = """
        Hold Ctrl to activate, then:
        
        h/j/k/l        Focus window left/down/up/right
        Shift+H/J/K/L  Swap or resize window
        [ / ]          Focus monitor left/right
        Shift+[ / ]    Move window to monitor
        f              Center window
        Shift+F        Maximize window
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
