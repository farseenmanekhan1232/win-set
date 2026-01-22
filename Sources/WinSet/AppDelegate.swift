import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var winSetApp: App?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the window manager (handles its own status bar)
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
