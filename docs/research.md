# macOS Window Manager Research

> Research notes for building a vim-like keyboard-driven window manager for macOS

## Goal

Build a lightweight, performant window management tool with vim-like keybindings that doesn't slow down the system.

---

## Core macOS APIs

### 1. Accessibility API (AXUIElement)

The **primary API** for window manipulation. Requires user permission (System Preferences → Privacy & Security → Accessibility).

**Capabilities:**
- Get list of all windows across applications
- Read/write window position and size
- Focus windows and applications
- Query window properties (title, role, etc.)

```swift
// Get focused window
let systemWide = AXUIElementCreateSystemWide()
var focusedApp: CFTypeRef?
AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute, &focusedApp)
```

---

### 2. CGEvent / Event Taps (CoreGraphics)

For capturing **global keyboard input** even when your app isn't focused.

```swift
let eventMask = (1 << CGEventType.keyDown.rawValue)
let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(eventMask),
    callback: eventCallback,
    userInfo: nil
)
```

**Key Point:** Uses zero CPU when idle - OS calls your callback only on keypress.

---

### 3. Quartz Window Services (CGWindowListCopyWindowInfo)

For **querying window information**:

```swift
let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
```

Useful for spatial navigation (finding window to the left/right/up/down).

---

### 4. NSWorkspace / NSRunningApplication

For **application-level control**:
- Activate/focus applications
- Get list of running applications
- Launch applications

---

## Event-Driven Architecture (Recommended)

### Why Event-Driven?

| Approach | Idle CPU | Active CPU | Battery |
|----------|----------|------------|---------|
| Polling (100ms) | ~2-5% | ~5-10% | Poor |
| Polling (1s) | ~0.5-1% | ~2-5% | Medium |
| **Event-Driven** | **~0%** | ~1-2% | **Excellent** |

### Available Events

#### AXObserver Notifications
Subscribe to window/app events - the OS pushes notifications to you:

```swift
// Create observer for an app
var observer: AXObserver?
AXObserverCreate(pid, axCallback, &observer)

// Subscribe to events
AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification, nil)
AXObserverAddNotification(observer, appElement, kAXWindowMovedNotification, nil)
AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification, nil)
AXObserverAddNotification(observer, appElement, kAXWindowResizedNotification, nil)

// Add to run loop
CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
```

#### NSWorkspace Notifications

```swift
let nc = NSWorkspace.shared.notificationCenter

nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, ...)
nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, ...)
nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, ...)
nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, ...)
```

### Complete Event List

| Event Source | Events Available |
|--------------|------------------|
| **AXObserver** | `WindowCreated`, `WindowMoved`, `WindowResized`, `FocusedWindowChanged`, `UIElementDestroyed`, `ApplicationActivated`, `ApplicationDeactivated`, `TitleChanged` |
| **NSWorkspace** | `didLaunchApplication`, `didTerminateApplication`, `didActivateApplication`, `didDeactivateApplication`, `activeSpaceDidChange`, `didWake`, `willSleep`, `screensDidChange` |
| **NSScreen** | `didChangeScreenParameters` (monitor connect/disconnect) |
| **CGEvent** | `keyDown`, `keyUp`, `flagsChanged`, `mouseMoved`, etc. |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS Kernel / WindowServer              │
└──────────┬──────────────────┬───────────────────┬───────────────┘
           │                  │                   │
     ┌─────▼─────┐     ┌──────▼──────┐     ┌──────▼──────┐
     │ AXObserver│     │ NSWorkspace │     │  CGEvent    │
     │ Callback  │     │ Notification│     │    Tap      │
     └─────┬─────┘     └──────┬──────┘     └──────┬──────┘
           │                  │                   │
           └──────────────────┼───────────────────┘
                              │
                              ▼
                 ┌────────────────────────┐
                 │   Your Event Handler   │
                 │                        │
                 │  • Update cached state │
                 │  • Trigger actions     │
                 │  • Zero CPU when idle  │
                 └────────────────────────┘
```

---

## Performance Pitfalls to Avoid

### 1. Polling
```swift
// ❌ BAD: Continuous CPU usage
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    let windows = getAllWindows()
}

// ✅ GOOD: Event-driven
AXObserverAddNotification(observer, app, kAXWindowMovedNotification, nil)
```

### 2. Slow Event Tap Callbacks
```swift
// ❌ BAD: Blocks input pipeline
func eventCallback(...) {
    let windows = queryAllWindows()  // Slow!
    calculateLayout()                 // Slow!
}

// ✅ GOOD: Dispatch async
func eventCallback(...) {
    DispatchQueue.main.async { handleKey(keyCode) }
    return Unmanaged.passRetained(event)
}
```

### 3. Too Many AX Calls
Each AX call is an IPC round-trip (~1-5ms). Cache aggressively.

### 4. Continuous Overlay Drawing
```swift
// ❌ BAD: Redraws every frame
override func draw(_ rect: NSRect) { ... }

// ✅ GOOD: Layer-backed, update on change
overlayView.wantsLayer = true
overlayView.layer?.contents = cachedImage
```

---

## Vim-Like Keybinding Ideas

| Key | Action |
|-----|--------|
| `h/j/k/l` | Focus window left/down/up/right |
| `H/J/K/L` | Move window left/down/up/right |
| `Ctrl+h/j/k/l` | Resize window |
| `f` | Fullscreen toggle |
| `s` | Split/tile windows |
| `w` | Cycle through windows |
| `1-9` | Jump to window by number |
| `:` | Command mode |

---

## System Requirements

- **Accessibility Permission**: Required for AXUIElement API
- **Input Monitoring Permission**: Required for CGEvent taps (global hotkeys)
- **SIP (System Integrity Protection)**: Some advanced features need SIP disabled

---

## Reference Projects

- [yabai](https://github.com/koekeishiya/yabai) - Tiling window manager
- [skhd](https://github.com/koekeishiya/skhd) - Simple hotkey daemon
- [Amethyst](https://github.com/ianyh/Amethyst) - Tiling window manager (Swift)
- [Rectangle](https://github.com/rxhanson/Rectangle) - Window snapping
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) - i3-like tiling (Swift)

---

# Existing Window Manager Deep Dive

## yabai Architecture

### Overview
- **Language**: C (low-level, maximum performance)
- **License**: MIT
- **Philosophy**: Extension to built-in macOS window manager

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                          yabai                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐   ┌─────────────────┐   ┌───────────────┐  │
│  │  Event System   │   │  Window Manager │   │  Socket IPC   │  │
│  │                 │   │                 │   │               │  │
│  │ • AXObserver    │   │ • BSP Algorithm │   │ • CLI cmds    │  │
│  │ • Signals       │   │ • Space mgmt    │   │ • External    │  │
│  │ • Rules         │   │ • Focus logic   │   │   scripts     │  │
│  └─────────────────┘   └─────────────────┘   └───────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                  Dock.app Injection (SIP)                   ││
│  │  • Mach APIs for scripting addition                         ││
│  │  • Required for: Spaces, animations, advanced features      ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### Event Handling Strategy

1. **AXObserver for Window Events**
   - Dynamically loads AXObserver functions
   - Subscribes to notifications per-application:
     - `kAXWindowCreatedNotification`
     - `kAXWindowMovedNotification`
     - `kAXFocusedWindowChangedNotification`
     - `kAXUIElementDestroyedNotification`

2. **Smart Retry Logic**
   - Early versions had infinite loop issues with `AXObserverAddNotification`
   - Now: Query app state first, then attempt subscription once
   - If fails → give up on that app (prevents CPU spin)

3. **Rules & Signals System**
   - **Rules**: Define window management based on app name/title
   - **Signals**: Async callbacks triggered by window events
   - Can emit events through socket for external tools (e.g., Übersicht)

### Why yabai Can Be Slow

| Issue | Cause | Impact |
|-------|-------|--------|
| Dock injection | Mach IPC overhead | Adds latency to space operations |
| Many observers | One per running app | Memory + event floods |
| BSP recalculation | Full tree recompute | CPU spike on window change |
| Blocking AX calls | Synchronous IPC | Blocks main thread |

### Performance Fix in Progress
- Issue [#131](https://github.com/nikitabobko/AeroSpace/issues/131): "Implement thread-per-application"
- Goal: Circumvent macOS blocking AX API calls

---

## AeroSpace Architecture

### Overview
- **Language**: Swift (95.6%)
- **License**: MIT
- **Philosophy**: i3-like, works without disabling SIP

### Key Design Decisions

#### 1. Virtual Workspace Emulation (Clever Hack!)

Instead of using macOS Spaces (which have no public API), AeroSpace:

```
Active Workspace                    Hidden Workspace
┌────────────────────┐              ┌────────────────────┐
│                    │              │                    │
│   [Window A]       │              │                    │
│   [Window B]       │              │        ┌──┐        │
│                    │              │        │AB│← Hidden│
│                    │              │        └──┘ off-screen
└────────────────────┘              └────────────────────┘
     (visible)                      (moved to corner, 1px visible)
```

**Benefits**:
- No SIP disable required
- Instant workspace switching (no animations)
- Unlimited workspaces
- Full programmatic control

#### 2. Tree-Based Window Layout

```
                    Workspace Root
                         │
              ┌──────────┴──────────┐
              │                     │
         Container (H)         Container (V)
         ┌────┴────┐           ┌────┴────┐
         │         │           │         │
      Window    Window      Window    Window
```

- Containers have layout (tiles/accordion) and orientation (H/V)
- Windows are always leaf nodes
- Supports normalization for consistent tree structure

#### 3. Accessibility API Usage

- Uses **only public APIs** (unlike yabai)
- Single private API: `_AXUIElementGetWindow` (to get window IDs)
- This is why SIP remains enabled

### Event/Callback System

AeroSpace supports these callbacks in config:

```toml
# Window detected callback
[[on-window-detected]]
if.app-id = 'com.apple.Safari'
run = 'move-node-to-workspace S'

# Focus changed callback
[on-focus-changed]
run = 'exec-and-forget sketchybar --trigger focus_changed'

# Workspace change callback
exec-on-workspace-change = ['exec-and-forget', 'update_statusbar.sh']
```

### Current Limitations (Pre-1.0)

| Issue | Description |
|-------|-------------|
| [#131](https://github.com/nikitabobko/AeroSpace/issues/131) | **Performance**: AX API blocks, need thread-per-app |
| [#1215](https://github.com/nikitabobko/AeroSpace/issues/1215) | **Stability**: Mutable tree → immutable persistent tree |
| [#1012](https://github.com/nikitabobko/AeroSpace/issues/1012) | **Hotkeys**: Investigating CGEvent.tapCreate for global hotkeys |

---

## Comparison: yabai vs AeroSpace

| Aspect | yabai | AeroSpace |
|--------|-------|-----------|
| **Language** | C | Swift |
| **SIP Required** | Yes (for full features) | No |
| **Spaces Approach** | Native + Dock injection | Virtual (position hack) |
| **Event Handling** | AXObserver + Rules/Signals | AXObserver + Callbacks |
| **Hotkey Daemon** | External (skhd) | Built-in |
| **Config Format** | Shell-style | TOML |
| **Private APIs** | Many (Mach injection) | One (`_AXUIElementGetWindow`) |
| **CPU When Idle** | Low (event-driven) | Low (event-driven) |
| **Known Perf Issue** | Blocking AX, many observers | Blocking AX calls |

---

## Lessons for Our Implementation

### What to Adopt

1. **Event-driven architecture** (both use it)
2. **Virtual workspace approach** (AeroSpace) - simpler, no SIP
3. **TOML config** (clean, human-readable)
4. **Thread-per-app pattern** (planned in both) - avoid blocking main thread

### What to Avoid

1. **Dock.app injection** (yabai) - complex, fragile, needs SIP disabled
2. **Synchronous AX calls on main thread** - causes lag
3. **Polling** - neither does this, and neither should we
4. **Too many observers** - cache state, minimize subscriptions

### Optimal Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Lightweight Window Manager                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. CGEvent Tap (Hotkeys)     ──▶ Main Thread (UI, state)       │
│     └─ Minimal callback                                         │
│     └─ Async dispatch                                           │
│                                                                 │
│  2. AXObserver (Window Events) ──▶ Background Thread Pool       │
│     └─ One per active app                                       │
│     └─ Thread-per-app for AX calls                              │
│                                                                 │
│  3. Window State Cache        ──▶ Updated by events only        │
│     └─ Never poll                                               │
│     └─ Query cache, not system                                  │
│                                                                 │
│  4. Vim Modal Input           ──▶ State machine                 │
│     └─ Normal mode: listen for commands                         │
│     └─ Command mode: `:` prefix for complex commands            │
│                                                                 │
│  5. Virtual Workspaces        ──▶ AeroSpace-style               │
│     └─ Position windows off-screen                              │
│     └─ No SIP required                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
