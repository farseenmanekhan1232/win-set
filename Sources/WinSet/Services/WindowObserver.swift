import Cocoa
import ApplicationServices

/// Events triggered by the windowing system
enum WindowEvent {
    case windowCreated(window: AXUIElement, app: NSRunningApplication)
    case windowDestroyed(element: AXUIElement) // Pass the zombie element for identity comparison
    case windowFocused(window: AXUIElement, app: NSRunningApplication)
    case windowMoved(window: AXUIElement)
    case windowResized(window: AXUIElement)
    case appLaunched(app: NSRunningApplication)
    case appTerminated(pid: pid_t)
}

protocol WindowObserverDelegate: AnyObject {
    func handle(events: [WindowEvent])
}

/// Watches for window lifecycle events across all applications
class WindowObserver {
    
    static let shared = WindowObserver()
    
    weak var delegate: WindowObserverDelegate?
    
    private var observers: [pid_t: AXObserver] = [:]
    private let queue = DispatchQueue(label: "com.winset.observer", qos: .userInteractive)
    private var eventBuffer: [WindowEvent] = []
    private var bufferTimer: Timer?
    
    // Coalescing window: how long to wait before processing a batch
    private let debounceInterval: TimeInterval = 0.05 // 50ms
    
    init() {
        setupWorkspaceObservers()
    }
    
    func start() {
        print("WindowObserver: Starting observation...")
        // Observe all currently running apps
        for app in NSWorkspace.shared.runningApplications {
            if app.activationPolicy == .regular {
                watchApp(app)
            }
        }
    }
    
    func stop() {
        print("WindowObserver: Stopping...")
        observers.removeAll() // AXObservers are CFTypes, might need explicit removal/invalidation if we were stricter
    }
    
    private func setupWorkspaceObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func appLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        
        print("Observer: App Launched: \(app.localizedName ?? "Unknown")")
        queueEvent(.appLaunched(app: app))
        watchApp(app)
    }
    
    @objc private func appTerminated(_ notification: Notification) {
         guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        print("Observer: App Terminated: \(app.localizedName ?? "Unknown")")
        queueEvent(.appTerminated(pid: app.processIdentifier))
        
        // Remove observer
        if let observer = observers[app.processIdentifier] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers.removeValue(forKey: app.processIdentifier)
        }
    }
    
    private func watchApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }
        
        var observer: AXObserver?
        let error = AXObserverCreate(pid, axCallback, &observer)
        
        guard error == .success, let axObserver = observer else {
            print("Failed to create observer for \(app.localizedName ?? "Unknown"): \(error.rawValue)")
            return
        }
        
        observers[pid] = axObserver
        
        // Register notifications
        let notifications = [
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXFocusedWindowChangedNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification
        ]
        
        let axApp = AXUIElementCreateApplication(pid)
        
        // Context to pass self to callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        for notif in notifications {
            AXObserverAddNotification(axObserver, axApp, notif as CFString, selfPtr)
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }
    
    // MARK: - Event Handling
    
    private func queueEvent(_ event: WindowEvent) {
        queue.async {
            self.eventBuffer.append(event)
            self.scheduleFlush()
        }
    }
    
    private func scheduleFlush() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.bufferTimer?.invalidate()
            self.bufferTimer = Timer.scheduledTimer(withTimeInterval: self.debounceInterval, repeats: false) { _ in
                self.flushEvents()
            }
        }
    }
    
    private func flushEvents() {
        queue.async {
            guard !self.eventBuffer.isEmpty else { return }
            let events = self.eventBuffer
            self.eventBuffer.removeAll()
            
            DispatchQueue.main.async {
                print("WindowObserver: Flushing \(events.count) events")
                self.delegate?.handle(events: events)
            }
        }
    }
    
    fileprivate func handleAXCallback(element: AXUIElement, notification: String, context: UnsafeMutableRawPointer?) {
        guard let _ = context else { return }
        
        // We can try to get the PID from element to find the app
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        
        // Find NSRunningApplication (expensive? Cached?)
        // AccessibilityService fetches this too.
        let app = NSRunningApplication(processIdentifier: pid)
        
        switch notification {
        case kAXWindowCreatedNotification:
            if let app = app { queueEvent(.windowCreated(window: element, app: app)) }
            
        case kAXUIElementDestroyedNotification:
            // Pass the element itself (even if invalid, we might use it for pointer comparison if cached)
            queueEvent(.windowDestroyed(element: element))
            
        case kAXFocusedWindowChangedNotification:
            if let app = app { queueEvent(.windowFocused(window: element, app: app)) }
            
        case kAXWindowMovedNotification:
            queueEvent(.windowMoved(window: element))
            
        case kAXWindowResizedNotification:
            queueEvent(.windowResized(window: element))
            
        default:
            break
        }
    }
}

// C-Convention Callback
func axCallback(observer: AXObserver, element: AXUIElement, notification: CFString, context: UnsafeMutableRawPointer?) {
    // Unmanaged to get self back
    guard let context = context else { return }
    let watcher = Unmanaged<WindowObserver>.fromOpaque(context).takeUnretainedValue()
    watcher.handleAXCallback(element: element, notification: notification as String, context: context)
}
