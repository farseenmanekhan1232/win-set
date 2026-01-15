import Cocoa

// Create the application
let app = NSApplication.shared

// We need to keep a reference to prevent deallocation
let winSetApp = App()

// Set up app delegate to handle lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        winSetApp.run()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        winSetApp.shutdown()
    }
}

let delegate = AppDelegate()
app.delegate = delegate

// Hide from dock (we're a menu bar app)
app.setActivationPolicy(.accessory)

// Run the app
app.run()
