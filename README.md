# WinSet

**Vim-inspired window manager for macOS with intelligent auto-tiling and smart resize**

[![CI](https://github.com/farseenmanekhan1232/win-set/actions/workflows/ci.yml/badge.svg)](https://github.com/farseenmanekhan1232/win-set/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/farseenmanekhan1232/win-set)](https://github.com/farseenmanekhan1232/win-set/releases/latest)

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

---

## Features

- **🪟 Smart Auto-Tiling** - Windows automatically organize into optimal layouts
  - 1 window: Full screen with margins
  - 2 windows: Equal 50/50 split (configurable to golden ratio)
  - 3 windows: Master/stack layout (61.8%/38.2%)
  - 4+ windows: Grid layout with optimized aspect ratios

- **⌨️ Vim-Style Navigation** - Use `h/j/k/l` for intuitive window focus

- **🔄 Drag-Swap** - Drag any window >50px to swap its position in the layout

- **📐 Smart Resize** - Resize without fighting the layout:
  - Layout pauses during resize
  - Smooth real-time feedback
  - Automatic adaptation when released

- **🖥️ Multi-Monitor** - Full support for multiple displays with automatic window migration

- **⚡ Lightweight** - Native Swift, minimal resource usage

- **🔧 Configurable** - Customize layouts, gaps, and behaviors via `config.toml`

---

## Installation

### Option 1: Download App (Recommended)

1. Download the latest release from [GitHub Releases](https://github.com/farseenmanekhan1232/win-set/releases/latest)
2. Unzip and drag **WinSet.app** to `/Applications`
3. Open WinSet from Applications
4. Grant permissions when prompted (see [Setup](#setup))

### Option 2: Build from Source

```bash
git clone https://github.com/farseenmanekhan1232/win-set.git
cd win-set
swift build -c release
cp -r .build/release/WinSet.app /Applications/
```

---

## Setup

### Grant Accessibility Permission

WinSet requires Accessibility permission to control windows:

1. When prompted, click **"Open System Settings"**
2. Navigate to **Privacy & Security → Accessibility**
3. Enable **WinSet**
4. Restart WinSet

### Grant Input Monitoring Permission (Optional)

Required for global hotkey capture:

1. Open **System Settings → Privacy & Security → Input Monitoring**
2. Enable **WinSet**

### Start at Login

1. Click the **WinSet icon** in your menu bar (⊞)
2. Select **"Start at Login"**

---

## Usage

### Activation

Hold **Ctrl** to activate window management mode.

### Keybindings

| Key | Action |
|-----|--------|
| `Ctrl + h/j/k/l` | Focus window left/down/up/right |
| `Ctrl + Shift + h/j/k/l` | Swap with window in direction (or snap at edge) |
| `Ctrl + [` / `]` | Focus monitor left/right |
| `Ctrl + f` | Center window |
| `Ctrl + Shift + f` | Maximize window |

### Smart Swap

When you press `Shift + Direction`:

1. **If there's a window in that direction** → Swaps positions
2. **If you're at the screen edge** → Snaps to half with cycle:
   - First press: 50% width
   - Repeated: 66% → 33% → 50% → ...

### Drag-Swap

- Drag any window **>50 pixels** to swap its position in the layout
- Windows reorder based on vertical position
- Layout automatically adapts

### Smart Resize

1. Grab any window edge/corner to resize
2. Layout pauses during resize (no snap-back fighting)
3. Release → layout adapts to new size
4. Other windows redistribute to fill remaining space

---

## Layout Behavior

### 1 Window
```
┌─────────────────────┐
│                     │
│                     │
│      Single         │
│                     │
│                     │
└─────────────────────┘
```

### 2 Windows (Default: 50/50 split)
```
┌────────┬────────┐
│        │        │
│   A    │   B    │
│        │        │
│        │        │
└────────┴────────┘
```

Configurable to golden ratio (61.8%/38.2%):
```toml
useEqualSplitForTwo = false
```

### 3 Windows (Master/Stack)
```
┌────────┬────────┐
│        │   C    │
│   A    ├────────┤
│        │   D    │
│        │        │
└────────┴────────┘
```

### 4+ Windows (Grid)
```
┌────┬────┬────┐
│ A  │ B  │ C  │
├────┼────┼────┤
│ D  │ E  │ F  │
└────┴────┴────┘
```

Grid layout optimizes for:
- Fills completely where possible
- Minimal empty slots
- Balanced aspect ratios

---

## Configuration

Config file: `~/.config/winset/config.toml`

### Complete Default Configuration

```toml
# WinSet Configuration

# Modifier to hold for hotkeys (ctrl, alt, cmd, shift)
activationModifier = "ctrl"

# Gap between windows (pixels)
gaps = 10.0

# Use equal 50/50 split for 2 windows (false = golden ratio ~62/38)
useEqualSplitForTwo = true

# Enable auto-tiling: true = windows snap back after resize
# false = manual resize is preserved, other windows adjust
enableAutoTiling = true

[bindings.normal]
# Focus navigation (Ctrl + h/j/k/l)
h = "focus left"
j = "focus down"
k = "focus up"
l = "focus right"

# Swap or resize at edge (Ctrl + Shift + h/j/k/l)
# Tries to swap windows; if no window in that direction, snaps to half
"shift-h" = "swap left"
"shift-j" = "swap down"
"shift-k" = "swap up"
"shift-l" = "swap right"

# Monitor navigation
"bracketleft" = "focus monitor left"
"bracketright" = "focus monitor right"

# Window sizing
f = "center"
"shift-f" = "maximize"
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `activationModifier` | `"ctrl"` | Modifier key to activate hotkeys |
| `gaps` | `10.0` | Gap between windows in pixels |
| `useEqualSplitForTwo` | `true` | Use 50/50 split for 2 windows |
| `enableAutoTiling` | `true` | Enable automatic layout after resize |

### Reset Configuration

```bash
rm ~/.config/winset/config.toml
# WinSet will regenerate defaults on next launch
```

---

## Troubleshooting

### App won't open / "Damaged" warning

```bash
xattr -cr /Applications/WinSet.app
```

### Windows not tiling

1. Check Accessibility permission:
   **System Settings → Privacy & Security → Accessibility**
2. Make sure WinSet is running (check menu bar)
3. Check console for errors:
   ```bash
   log show --predicate 'process == "WinSet"' --last 5m
   ```

### Hotkeys not working

1. Grant **Input Monitoring** permission:
   **System Settings → Privacy & Security → Input Monitoring**
2. Make sure no other app is using the same hotkeys
3. Try a different modifier key in config

### Windows fighting during resize

This is the expected old behavior. The new smart resize should prevent this:
- Layout pauses during resize
- Smooth real-time feedback
- Automatic adaptation on release

If still experiencing issues:
```toml
enableAutoTiling = false
```

### Multi-monitor issues

1. Make sure all monitors are detected:
   ```bash
   system_profiler SPDisplaysDataType
   ```
2. Check WinSet recognizes all screens (menu bar icon → "Show Screens")

---

## Architecture

### Components

- **TilingManager** - Coordinates window events and layout updates
- **LayoutEngine** - Calculates optimal window frames
- **WindowManager** - Handles snap positions and focus operations
- **AccessibilityService** - Interacts with macOS Accessibility APIs
- **WindowObserver** - Watches for window lifecycle events
- **EventTapService** - Captures global hotkeys
- **HotkeyController** - Parses and executes commands

### Layout Selection Logic

```
windowIds.count == 1 → Single window (full with margins)
windowIds.count == 2 → Two windows (50/50 or golden ratio)
windowIds.count == 3 → Master/stack (61.8%/38.2%)
windowIds.count >= 4 → Grid (optimized aspect ratios)
```

### Event Flow

```
User Action → EventTap/WindowObserver → TilingManager
                                              ↓
                              LayoutEngine.calculateFrames()
                                              ↓
                              AccessibilityService.setWindowFrame()
```

---

## Uninstall

1. Click menu bar icon → **Quit WinSet**
2. Drag **WinSet.app** from Applications to Trash
3. Remove config: `rm -rf ~/.config/winset`
4. Remove support files: `rm -rf ~/Library/Application\ Support/winset`

---

## Contributing

PRs welcome! Key areas for contribution:

- Additional snap positions (corners, thirds)
- More layout algorithms
- UI improvements
- Documentation

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Credits

Inspired by:
- **Hyprland** - Dynamic tiling window manager
- **AeroSpace** - macOS window manager
- **yabai** - macOS window manager
- **Vim** - Modal keybindings
