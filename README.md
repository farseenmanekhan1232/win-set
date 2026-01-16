# WinSet

**Vim-inspired window manager for macOS with Hyprland-style auto-tiling**

[![CI](https://github.com/farseenmanekhan1232/win-set/actions/workflows/ci.yml/badge.svg)](https://github.com/farseenmanekhan1232/win-set/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/farseenmanekhan1232/win-set)](https://github.com/farseenmanekhan1232/win-set/releases/latest)

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

## Features

- 🪟 **Auto-tiling** - Windows automatically tile in a BSP (Binary Space Partition) layout
- ⌨️ **Vim-style navigation** - Use `h/j/k/l` to focus windows
- 🔄 **Smart swap/resize** - Swap windows or cycle through 50%/66%/33% widths
- 🖥️ **Multi-monitor** - Full support for multiple displays
- 🎯 **Menu bar app** - Lives in your menu bar, starts at login
- ⚡ **Lightweight** - Native Swift, minimal resource usage

---

## Installation

### Option 1: Download App (Recommended)

1. **Download** the latest release from [GitHub Releases](https://github.com/farseenmanekhan1232/win-set/releases/latest)
2. **Unzip** and drag **WinSet.app** to `/Applications`
3. **Open** WinSet from Applications
4. **Grant Permission** when prompted (see [Setup](#setup))

### Option 2: Homebrew Cask

```bash
brew tap farseenmanekhan1232/tap
brew install --cask winset
```

---

## Setup

### Grant Accessibility Permission

When you first open WinSet, macOS will prompt you to grant Accessibility access:

1. Click **"Open System Settings"** in the prompt
2. Enable **WinSet** in the list
3. Restart WinSet if needed

> **Note:** This permission is required for WinSet to move and resize windows.

### Start at Login

1. Click the **WinSet icon** in your menu bar (⊞)
2. Select **"Start at Login"**

That's it! WinSet will now start automatically when you log in.

---

## Usage

### Activation

Hold **Ctrl** to activate window management mode.

### Keybindings

| Key | Action |
|-----|--------|
| `Ctrl + h/j/k/l` | Focus window left/down/up/right |
| `Ctrl + Shift + h/j/k/l` | Swap window (or resize at edge) |
| `Ctrl + [` / `]` | Focus monitor left/right |
| `Ctrl + Shift + [` / `]` | Move window to monitor |
| `Ctrl + f` | Center window |
| `Ctrl + Shift + f` | Maximize window |

### Smart Swap/Resize

When you press `Shift + Direction`:
- If there's a window in that direction → **Swaps** positions
- If you're at the edge → **Cycles width**: 50% → 66% → 33% → 50%

---

## Configuration

Config file location: `~/.config/winset/config.toml`

```toml
# Gap between windows (pixels)
gaps = 10

# Maximum windows to auto-tile per screen (0 = unlimited)
maxWindowsPerScreen = 2

# Custom keybindings
[bindings]
"h" = "focus left"
"j" = "focus down"
"k" = "focus up"
"l" = "focus right"
"shift-h" = "swap left"
"shift-j" = "swap down"
"shift-k" = "swap up"
"shift-l" = "swap right"
```

To reset to defaults:
```bash
rm ~/.config/winset/config.toml
```

---

## Troubleshooting

### App won't open / "Damaged" / "Malware" warning

Since WinSet is an open-source tool and not signed with a paid Apple Developer ID, macOS may show a warning.

**To fix:**
1. **Right-click** (or Ctrl+Click) `WinSet.app` in Applications
2. Select **Open** in the menu
3. Click **Open** in the dialog box

You only need to do this once.


### Windows not tiling

1. Check Accessibility permission in **System Settings → Privacy & Security → Accessibility**
2. Make sure WinSet is running (check menu bar)

### Hotkeys not working

1. Grant **Input Monitoring** permission if prompted
2. Make sure no other app is using the same hotkeys

---

## Uninstall

1. Click menu bar icon → **Quit WinSet**
2. Drag **WinSet.app** from Applications to Trash
3. Optionally remove config: `rm -rf ~/.config/winset`

---

## Contributing

PRs welcome! See the codebase for contribution guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.
