import Cocoa
import Carbon.HIToolbox

/// Service for capturing global keyboard events using CGEvent taps
/// This runs with minimal overhead - the callback is called by the OS only on key events
class EventTapService {
    
    static let shared = EventTapService()
    
    /// Callback when a key event is detected
    /// Return true to consume the event (prevent it from reaching other apps)
    var onKeyEvent: ((KeyEvent) -> Bool)?
    
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start capturing global key events
    func start() -> Bool {
        guard !isRunning else { return true }
        
        // We want to intercept key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        // Create the event tap
        // Using cgSessionEventTap to capture events for the current user session
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap. Make sure Input Monitoring permission is granted.")
            return false
        }
        
        eventTap = tap
        
        // Create a run loop source and add it to the current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the event tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isRunning = true
        print("✅ Event tap started - listening for global hotkeys")
        return true
    }
    
    /// Stop capturing events
    func stop() {
        guard isRunning else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        
        print("🛑 Event tap stopped")
    }
    
    /// Check if event tap is running
    var running: Bool { isRunning }
    
    // MARK: - Event Processing
    
    /// Process a CGEvent and convert to our KeyEvent type
    fileprivate func processEvent(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let eventType = event.type
        
        // Convert CGEventFlags to NSEvent.ModifierFlags
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        
        // Get character if possible
        var characters: String? = nil
        if let nsEvent = NSEvent(cgEvent: event) {
            characters = nsEvent.charactersIgnoringModifiers
        }
        
        let keyEvent = KeyEvent(
            keyCode: keyCode,
            modifiers: modifiers,
            characters: characters,
            isKeyDown: eventType == .keyDown
        )
        
        // Only process key down events for commands
        // (we let key up events pass through)
        guard keyEvent.isKeyDown else { return false }
        
        // Call the handler and return whether to consume the event
        return onKeyEvent?(keyEvent) ?? false
    }
}

// MARK: - C Callback

/// Global callback function for the event tap
/// This must be a C-compatible function, so we use the userInfo to get back to our Swift object
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    
    // Handle special event types
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // Re-enable the tap if it gets disabled
        if let userInfo = userInfo {
            let service = Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = service.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
        
    case .keyDown, .keyUp:
        break
        
    default:
        return Unmanaged.passRetained(event)
    }
    
    // Get our service instance
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }
    
    let service = Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()
    
    // Process the event
    let shouldConsume = service.processEvent(event)
    
    if shouldConsume {
        // Return nil to consume the event (prevent it from reaching other apps)
        return nil
    } else {
        // Pass the event through
        return Unmanaged.passRetained(event)
    }
}
