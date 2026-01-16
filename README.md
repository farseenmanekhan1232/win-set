# WinSet

**Vim-inspired window manager for macOS with Hyprland-style auto-tiling**

[![CI](https://github.com/farseenmanekhan1232/win-set/actions/workflows/ci.yml/badge.svg)](https://github.com/farseenmanekhan1232/win-set/actions/workflows/ci.yml)
[![Release](https://github.com/farseenmanekhan1232/win-set/releases/latest/badge.svg)](https://github.com/farseenmanekhan1232/win-set/releases/latest)

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
- ⚡ **Lightweight** - Native Swift, minimal resource usage

---

## Installation

### Via Homebrew (Recommended)

```bash
brew tap farseenmanekhan1232/tap
brew install winset
```

### Manual Download

Download the latest release from [GitHub Releases](https://github.com/farseenmanekhan1232/win-set/releases/latest).

---

## Setup

### 1. Grant Accessibility Permission

WinSet needs Accessibility access to manage windows:

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the **+** button
3. Add `/usr/local/bin/winset` (or drag from Finder)
4. Enable the checkbox

### 2. Grant Input Monitoring Permission

For global hotkeys:

1. Open **System Settings** → **Privacy & Security** → **Input Monitoring**
2. Add `winset` if prompted

### 3. Start WinSet

#### Option A: Run on Login (Recommended)

```bash
brew services start winset
```

This starts WinSet now and automatically on every login.

#### Option B: Run Manually

```bash
winset
```

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

Config file: `~/.config/winset/config.toml`

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

Delete the config to regenerate defaults:
```bash
rm ~/.config/winset/config.toml
```

---

## Troubleshooting

### "bad CPU type in executable"

You have an older version. Update:
```bash
brew upgrade winset
```

### Windows not tiling

1. Check Accessibility permission is granted
2. Restart WinSet: `brew services restart winset`

### Hotkeys not working

1. Check Input Monitoring permission
2. Make sure WinSet is running: `pgrep winset`

### View logs

```bash
tail -f /usr/local/var/log/winset.log
```

---

## Uninstall

```bash
brew services stop winset
brew uninstall winset
brew untap farseenmanekhan1232/tap
```

---

## Contributing

PRs welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.
