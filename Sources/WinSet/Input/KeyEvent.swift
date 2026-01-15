import Cocoa
import Carbon.HIToolbox

/// Key event for processing
struct KeyEvent {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let characters: String?
    let isKeyDown: Bool
    
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String? = nil, isKeyDown: Bool = true) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
        self.isKeyDown = isKeyDown
    }
    
    /// Common key codes
    static let keyH: UInt16 = 4
    static let keyJ: UInt16 = 38
    static let keyK: UInt16 = 40
    static let keyL: UInt16 = 37
    static let keyF: UInt16 = 3
    static let keyI: UInt16 = 34
    static let keyEscape: UInt16 = 53
    static let keyColon: UInt16 = 41  // semicolon key, shift gives colon
    static let keySpace: UInt16 = 49
    static let keyReturn: UInt16 = 36
    static let key1: UInt16 = 18
    static let key2: UInt16 = 19
    static let key3: UInt16 = 20
    static let key4: UInt16 = 21
    static let key5: UInt16 = 23
    static let key6: UInt16 = 22
    static let key7: UInt16 = 26
    static let key8: UInt16 = 28
    static let key9: UInt16 = 25
    
    var isShiftPressed: Bool {
        modifiers.contains(.shift)
    }
    
    var isControlPressed: Bool {
        modifiers.contains(.control)
    }
    
    var isCommandPressed: Bool {
        modifiers.contains(.command)
    }
    
    var isOptionPressed: Bool {
        modifiers.contains(.option)
    }
}

/// Key combination for hotkeys
struct KeyCombo: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    
    /// Default activation key: Ctrl + Space
    static let defaultActivation = KeyCombo(keyCode: KeyEvent.keySpace, modifiers: .control)
    
    func matches(_ event: KeyEvent) -> Bool {
        return event.keyCode == keyCode && 
               event.modifiers.intersection([.control, .option, .command, .shift]) == modifiers.intersection([.control, .option, .command, .shift])
    }
    
    
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    
    /// Initialize from string format like "ctrl-space", "shift-h"
    init?(string: String) {
        let parts = string.lowercased().split(separator: "-").map(String.init)
        guard let keyString = parts.last else { return nil }
        
        let mods = KeyCombo.modifiers(from: parts.dropLast().joined(separator: "-"))
        
        guard let code = KeyCombo.keyCode(from: keyString) else { return nil }
        
        self.keyCode = code
        self.modifiers = mods
    }
    
    /// Parse modifiers from string
    static func modifiers(from string: String) -> NSEvent.ModifierFlags {
        var mods: NSEvent.ModifierFlags = []
        let parts = string.lowercased().split(separator: "-")
        for part in parts {
            switch part {
            case "ctrl", "control": mods.insert(.control)
            case "shift": mods.insert(.shift)
            case "cmd", "command": mods.insert(.command)
            case "opt", "alt", "option": mods.insert(.option)
            case "fn": mods.insert(.function)
            default: break
            }
        }
        return mods
    }
    
    private static func keyCode(from string: String) -> UInt16? {
        switch string {
        case "a": return 0x00
        case "s": return 0x01
        case "d": return 0x02
        case "f": return 0x03
        case "h": return 0x04
        case "g": return 0x05
        case "z": return 0x06
        case "x": return 0x07
        case "c": return 0x08
        case "v": return 0x09
        case "b": return 0x0B
        case "q": return 0x0C
        case "w": return 0x0D
        case "e": return 0x0E
        case "r": return 0x0F
        case "y": return 0x10
        case "t": return 0x11
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "6": return 0x16
        case "5": return 0x17
        case "equal": return 0x18
        case "9": return 0x19
        case "7": return 0x1A
        case "minus": return 0x1B
        case "8": return 0x1C
        case "0": return 0x1D
        case "bracketright": return 0x1E
        case "o": return 0x1F
        case "u": return 0x20
        case "bracketleft": return 0x21
        case "i": return 0x22
        case "p": return 0x23
        case "l": return 0x25
        case "j": return 0x26
        case "quote": return 0x27
        case "k": return 0x28
        case "semicolon": return 0x29
        case "backslash": return 0x2A
        case "comma": return 0x2B
        case "slash": return 0x2C
        case "n": return 0x2D
        case "m": return 0x2E
        case "period": return 0x2F
        case "space": return 0x31
        case "esc", "escape": return 0x35
        case "colon": return 0x29 // same as semicolon, modifier handled separately
        default: return nil
        }
    }
}
