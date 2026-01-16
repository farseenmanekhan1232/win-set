import Cocoa

// Create the application
let app = NSApplication.shared

// Set up app delegate
let delegate = AppDelegate()
app.delegate = delegate

// Hide from dock (we're a menu bar app)
app.setActivationPolicy(.accessory)

// Run the app
app.run()
