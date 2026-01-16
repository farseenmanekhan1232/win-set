import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var menuBarController: MenuBarController?
    private var winSetApp: App?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar
        menuBarController = MenuBarController()
        
        // Start the window manager
        winSetApp = App()
        winSetApp?.run()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("👋 WinSet shutting down...")
        winSetApp?.shutdown()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running as menu bar app
    }
}
