import Foundation

/// Vim-style modal input controller
/// Handles the state machine for different input modes
class VimModeController {
    
    /// Current vim mode
    enum Mode: String {
        case disabled   // Not active, all keys pass through
        case normal     // Listening for navigation commands
        case insert     // Temporary passthrough (like vim insert mode)
        case command    // After pressing `:`, entering text command
    }
    
    /// Command that can be executed
    enum Command {
        case focusDirection(Direction)
        case moveToHalf(Direction)
        case snapTo(SnapPosition)
        case toggleFullscreen
        case enterInsertMode
        case enterCommandMode
        case enterNormalMode
        case exitToDisabled
        case exitToNormal
        case cycleWindows
        case focusWindowNumber(Int)
        case focusMonitor(Direction)
        case moveWindowToMonitor(Direction)  // Cycle window to next/prev monitor
        case swapWindowInDirection(Direction)  // Swap with window in direction
        case switchToWorkspace(Int)      // New
        case moveWindowToWorkspace(Int)  // New
        case resetWorkspaces             // New
        case debugState                  // New

    }
    
    // MARK: - State
    
    private(set) var currentMode: Mode = .disabled
    private var commandBuffer: String = ""
    
    /// Callback when mode changes
    var onModeChange: ((Mode) -> Void)?
    
    /// Callback when a command should be executed
    var onCommand: ((Command) -> Void)?
    
    /// Activation key combo (now loaded from config)
    var activationKey: KeyCombo {
        KeyCombo(string: ConfigService.shared.config.activationKey) ?? .defaultActivation
    }
    
    // MARK: - Key Handling
    
    /// Process a key event
    /// Returns true if the event was consumed (should not pass through to apps)
    func handleKey(_ event: KeyEvent) -> Bool {
        // If in command mode, handle it regardless of strategy
        if currentMode == .command {
            return handleCommandMode(event)
        }
        
        let config = ConfigService.shared.config
        
        // Strategy: Hold (Quasimode)
        if config.activationStrategy == "hold" {
            let activationMods = KeyCombo.modifiers(from: config.activationModifier)
            
            // Check if activation modifier is held
            if event.modifiers.contains(activationMods) {
                // Remove activation modifier from event for binding lookup
                var effectiveMods = event.modifiers
                effectiveMods.remove(activationMods)
                
                let effectiveEvent = KeyEvent(keyCode: event.keyCode, modifiers: effectiveMods)
                
                return handleBinding(effectiveEvent)
            }
            
            // Not holding modifier -> pass through
            return false
        }
        
        // Strategy: Toggle (Legacy)
        else {
            if currentMode == .disabled {
                return handleDisabledMode(event)
            } else if currentMode == .normal {
                return handleNormalModeLegacy(event)
            } else if currentMode == .insert {
                return handleInsertMode(event)
            }
        }
        
        return false
    }
    
    // MARK: - Binding Logic
    
    private func handleBinding(_ event: KeyEvent) -> Bool {
        // Check configured bindings
        let bindings = ConfigService.shared.config.bindings.normal
        
        for (keyString, commandName) in bindings {
            if let combo = KeyCombo(string: keyString), combo.matches(event) {
                execute(commandName: commandName)
                return true
            }
        }
        
        // Number keys defaults (Workspaces) - DISABLED
        // switch event.keyCode {
        // case KeyEvent.key1...KeyEvent.key9:
        //     return false // Pass through
        // default: break
        // }
            
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
                case "bottom": onCommand?(.moveToHalf(.down))
                case "top": onCommand?(.moveToHalf(.up))
                case "right": onCommand?(.moveToHalf(.right))
                case "window":
                    // "move window monitor left/right"
                    if parts.count > 3 && parts[2] == "monitor" {
                        switch parts[3] {
                        case "left": onCommand?(.moveWindowToMonitor(.left))
                        case "right": onCommand?(.moveWindowToMonitor(.right))
                        case "up": onCommand?(.moveWindowToMonitor(.up))
                        case "down": onCommand?(.moveWindowToMonitor(.down))
                        default: break
                        }
                    }
                case "to": 
                    // "move to workspace X"
                     if parts.count > 3 && parts[2] == "workspace", let id = Int(parts[3]) {
                         onCommand?(.moveWindowToWorkspace(id))
                     }
                default: break
                }
            }
            
        case "workspace":
            if parts.count > 1, let id = Int(parts[1]) {
                 onCommand?(.switchToWorkspace(id))
            }
            
        case "center": onCommand?(.snapTo(.center))
        
        case "swap":
            // "swap left/right/up/down"
            if parts.count > 1 {
                switch parts[1] {
                case "left": onCommand?(.swapWindowInDirection(.left))
                case "right": onCommand?(.swapWindowInDirection(.right))
                case "up": onCommand?(.swapWindowInDirection(.up))
                case "down": onCommand?(.swapWindowInDirection(.down))
                default: break
                }
            }
        case "maximize": onCommand?(.snapTo(.maximize))
            
        case "insert-mode":
            onCommand?(.enterInsertMode)
            setMode(.insert)
            
        case "command-mode":
            commandBuffer = ""
            onCommand?(.enterCommandMode)
            setMode(.command)
            
        case "disabled-mode":
            setMode(.disabled)
            
        default: 
            print("Unknown command: \(commandName)")
        }
    }
    
    // MARK: - Legacy Mode Handlers

    private func handleNormalModeLegacy(_ event: KeyEvent) -> Bool {
        // Activation key toggles back to disabled mode
        if activationKey.matches(event) {
            setMode(.disabled)
            return true
        }
        
        // Escape exits to disabled mode (hardcoded fallback)
        if event.keyCode == KeyEvent.keyEscape {
            setMode(.disabled)
            return true
        }

        return handleBinding(event)
    }
    
    private func handleDisabledMode(_ event: KeyEvent) -> Bool {
        if activationKey.matches(event) {
            setMode(.normal)
            onCommand?(.enterNormalMode)
            return true
        }
        return false
    }
    
    private func handleInsertMode(_ event: KeyEvent) -> Bool {
        // In insert mode, only activation key exits back to normal
        if activationKey.matches(event) {
            setMode(.normal)
            return true
        }
        
        // Escape also exits to normal mode
        if event.keyCode == KeyEvent.keyEscape {
            setMode(.normal)
            return true
        }
        
        // All other keys pass through
        return false
    }
    
    private func handleCommandMode(_ event: KeyEvent) -> Bool {
        let keyCode = event.keyCode
        
        // Escape cancels command mode
        if keyCode == KeyEvent.keyEscape {
            commandBuffer = ""
            setMode(.normal)
            return true
        }
        
        // Return executes the command
        if keyCode == KeyEvent.keyReturn {
            executeCommand(commandBuffer)
            commandBuffer = ""
            setMode(.normal)
            return true
        }
        
        // Add character to buffer
        if let chars = event.characters {
            commandBuffer += chars
        }
        
        return true
    }
    
    // MARK: - Command Execution
    
    private func executeCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespaces).lowercased()
        
        switch trimmed {
        case "q", "quit":
            setMode(.disabled)
            
        case "left", "l":
            onCommand?(.snapTo(.leftHalf))
            
        case "right", "r":
            onCommand?(.snapTo(.rightHalf))
            
        case "top", "t":
            onCommand?(.snapTo(.topHalf))
            
        case "bottom", "b":
            onCommand?(.snapTo(.bottomHalf))
            
        case "max", "maximize", "m":
            onCommand?(.snapTo(.maximize))
            
        case "center", "c":
            onCommand?(.snapTo(.center))
            
        case "tl", "topleft":
            onCommand?(.snapTo(.topLeft))
            
        case "tr", "topright":
            onCommand?(.snapTo(.topRight))
            
        case "bl", "bottomleft":
            onCommand?(.snapTo(.bottomLeft))
            
        case "br", "bottomright":
            onCommand?(.snapTo(.bottomRight))
            
        case "workspace":
            // "workspace 1" via command mode
            // We need to parse remaining parts
             // Simplified: just workspace name? 
             // Logic in executeCommand is simple string matching.
             // We can improve it to handle args if needed.
             // For now, let's just stick to what `execute` does or what keys do.
             break

        default:
            // Try to match complex commands if simple match fails?
             if trimmed.hasPrefix("workspace ") {
                 if let id = Int(trimmed.dropFirst(10)) {
                     onCommand?(.switchToWorkspace(id))
                 }
             } else if trimmed.hasPrefix("move to workspace ") {
                 if let id = Int(trimmed.dropFirst(18)) {
                     onCommand?(.moveWindowToWorkspace(id))
                 }
             } else if trimmed.hasPrefix("focus monitor ") {
                 // ...
             } else {
                 print("Unknown command: \(command)")
             }
        }
    }
    
    // MARK: - Helpers
    
    private func setMode(_ mode: Mode) {
        guard mode != currentMode else { return }
        currentMode = mode
        onModeChange?(mode)
    }
    
    /// Get description of current mode for UI
    var modeDescription: String {
        switch currentMode {
        case .disabled: return "○"
        case .normal: return "●"
        case .insert: return "○ INSERT"
        case .command: return ":\(commandBuffer)"
        }
    }
}
