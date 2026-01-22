import Foundation

/// Simple hotkey controller - no modes, just direct actions
/// Handles keyboard shortcuts while holding the activation modifier (default: Ctrl)
class HotkeyController {
    
    /// Commands that can be executed
    enum Command {
        case focusDirection(Direction)
        case moveToHalf(Direction)
        case snapTo(SnapPosition)
        case toggleFullscreen
        case focusMonitor(Direction)
        case moveWindowToMonitor(Direction)
        case swapWindowInDirection(Direction)
        case focusWindowNumber(Int)
        case retileScreen
    }
    
    /// Callback when a command should be executed
    var onCommand: ((Command) -> Void)?
    
    // MARK: - Key Handling
    
    /// Process a key event
    /// Returns true if the event was consumed (should not pass through to apps)
    func handleKey(_ event: KeyEvent) -> Bool {
        let config = ConfigService.shared.config
        let activationMods = KeyCombo.modifiers(from: config.activationModifier)
        
        // Only process if holding the activation modifier
        guard event.modifiers.contains(activationMods) else {
            return false
        }
        
        // Remove activation modifier from event for binding lookup
        var effectiveMods = event.modifiers
        effectiveMods.remove(activationMods)
        
        let effectiveEvent = KeyEvent(keyCode: event.keyCode, modifiers: effectiveMods)
        
        return executeBinding(effectiveEvent)
    }
    
    // MARK: - Binding Logic
    
    private func executeBinding(_ event: KeyEvent) -> Bool {
        let bindings = ConfigService.shared.config.bindings.normal
        
        for (keyString, commandName) in bindings {
            if let combo = KeyCombo(string: keyString), combo.matches(event) {
                execute(commandName: commandName)
                return true
            }
        }
        
        return false
    }
    
    private func execute(commandName: String) {
        let parts = commandName.split(separator: " ").map(String.init)
        guard let base = parts.first else { return }
        
        switch base {
        case "focus":
            if parts.count > 1 {
                switch parts[1] {
                case "left": onCommand?(.focusDirection(.left))
                case "down": onCommand?(.focusDirection(.down))
                case "up": onCommand?(.focusDirection(.up))
                case "right": onCommand?(.focusDirection(.right))
                case "monitor":
                    if parts.count > 2 {
                        switch parts[2] {
                        case "left": onCommand?(.focusMonitor(.left))
                        case "right": onCommand?(.focusMonitor(.right))
                        case "up": onCommand?(.focusMonitor(.up))
                        case "down": onCommand?(.focusMonitor(.down))
                        default: break
                        }
                    }
                default: break
                }
            }
            
        case "move":
            if parts.count > 1 {
                switch parts[1] {
                case "left": onCommand?(.moveToHalf(.left))
                case "down": onCommand?(.moveToHalf(.down))
                case "up": onCommand?(.moveToHalf(.up))
                case "right": onCommand?(.moveToHalf(.right))
                case "window":
                    if parts.count > 3 && parts[2] == "monitor" {
                        switch parts[3] {
                        case "left": onCommand?(.moveWindowToMonitor(.left))
                        case "right": onCommand?(.moveWindowToMonitor(.right))
                        case "up": onCommand?(.moveWindowToMonitor(.up))
                        case "down": onCommand?(.moveWindowToMonitor(.down))
                        default: break
                        }
                    }
                default: break
                }
            }
            
        case "swap":
            if parts.count > 1 {
                switch parts[1] {
                case "left": onCommand?(.swapWindowInDirection(.left))
                case "right": onCommand?(.swapWindowInDirection(.right))
                case "up": onCommand?(.swapWindowInDirection(.up))
                case "down": onCommand?(.swapWindowInDirection(.down))
                default: break
                }
            }
            
        case "center":
            onCommand?(.snapTo(.center))
            
        case "maximize":
            onCommand?(.snapTo(.maximize))
            
        case "retile":
            onCommand?(.retileScreen)
            
        default:
            print("Unknown command: \(commandName)")
        }
    }
}
