# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PastePro is a Flutter desktop application designed as a Paste.app clone for Linux and Windows. It creates a system-wide hotkey-triggered overlay (Super+Shift+V) that appears at the bottom of the screen for clipboard management.

**Design Philosophy**: The UI and animations are modeled after Paste.app (pasteapp.io). ALL design changes must maintain visual parity with Paste.app's aesthetic, including:
- Smooth, polished animations (280ms easeOutCubic)
- Dark gradient backgrounds with subtle borders
- Visual card-based clipboard items
- Color-coded item types
- Hover effects and transitions
- Professional spacing and typography

## Common Commands

```bash
# Run the application on Linux
flutter run -d linux

# Run on other platforms
flutter run -d macos
flutter run -d windows

# Clean build
flutter clean && flutter run -d linux

# Get dependencies
flutter pub get

# Run tests
flutter test

# Enable desktop platform support (one-time setup)
flutter config --enable-linux-desktop
flutter config --enable-windows-desktop
```

## Architecture

### Main Application Flow

The app is a single-file Flutter application (`lib/main.dart`) that manages a system overlay window:

1. **Window Initialization**: On startup, calculates overlay dimensions (60% of screen height or 480px minimum) and positions window at bottom of primary display
2. **Hotkey Registration**: On X11: uses `hotkey_manager` package. On Wayland/Hyprland: uses Unix signals (SIGUSR1) triggered by window manager bindings
3. **Visibility Toggle**: Shows/hides overlay with smooth slide+fade animation on hotkey press
4. **Auto-hide**: Window automatically hides with animation when it loses focus
5. **System Tray (Linux only)**: Custom GTK-based tray integration via platform channel

### Key Components

- **PasteProApp**: Root stateful widget managing window lifecycle, animations, and visibility state
- **_OverlayContent**: Main UI with search bar and clipboard item list
- **_ClipboardItemCard**: Individual clipboard item cards with hover effects and animations
- **TrayBridge**: Method channel singleton for communicating with native Linux tray plugin
- **ClipboardItem**: Data model for clipboard entries (text, image, file types)

### Animation System

- **Duration**: 280ms for slide+fade animations
- **Curves**: `easeOutCubic` for slide, `easeOut` for fade
- **Behavior**: Smooth appearance from bottom with 50px translate offset
- **On Hide**: Animations reverse before window hides

### Platform-Specific Code

**Linux Native Plugin** (`linux/runner/tray_plugin.cc`):
- GTK-based system tray implementation using libappindicator/libayatana-appindicator
- Exposes `pastepro/tray` method channel with `setIcon` method
- Sends `onActivate` callbacks to Dart when tray icon is clicked

### Key Dependencies

- `window_manager`: Cross-platform window management (positioning, visibility, sizing)
- `hotkey_manager`: System-wide hotkey registration (requires libkeybinder3 on Linux)
- `screen_retriever`: Display information (size, position, multi-monitor support)

### Linux Build Requirements

```bash
# Required system packages (Arch Linux)
sudo pacman -S cmake ninja gtk3 pkg-config libkeybinder3

# For other distributions
# Ubuntu/Debian: sudo apt install cmake ninja-build libgtk-3-dev pkg-config libkeybinder-3.0-dev
# Fedora: sudo dnf install cmake ninja-build gtk3-devel pkg-config keybinder3-devel
```

### Hyprland/Wayland Setup

On Hyprland (and other Wayland compositors), libkeybinder3 doesn't work. Instead, the app uses Unix signals (SIGUSR1) for toggling.

**Setup for Hyprland:**
1. Add to `~/.config/hypr/bindings.conf`:
   ```
   bindd = CTRL SHIFT, backslash, PastePro, exec, /path/to/pastepro/pastepro-toggle.sh
   ```
2. Reload Hyprland: `hyprctl reload`
3. Press Ctrl+Shift+\ to toggle the overlay

### Important Constraints

- Window is non-resizable, skip-taskbar, and borderless
- Overlay height ratio controlled by `_overlayHeightRatio` constant (0.60)
- Window automatically repositions on screen bounds changes
- Tray functionality currently Linux-only
- Keybinding is Ctrl+Shift+\ configured in Hyprland (libkeybinder3 doesn't work on Wayland)
- App listens for SIGUSR1 signal to toggle (Wayland-compatible solution)

## Design Guidelines for Future Sessions

**CRITICAL**: This project is a Paste.app clone. All UI/UX work must match Paste.app's design:

1. **Color Palette**:
   - Primary accent: `#64FFDA` (cyan/teal)
   - Background gradient: `#1A1F2E` → `#0F1419`
   - Text colors: White with opacity variations (0.4, 0.5, 0.7, 1.0)
   - Item type colors: Text (#64FFDA), Image (#FF7597), File (#82AAFF)

2. **Animations**:
   - ALL animations must be smooth and polished
   - Default duration: 280ms
   - Use easeOutCubic for movements, easeOut for fades
   - Hover effects: 150ms transitions
   - Never use instant/jarring state changes

3. **Spacing & Layout**:
   - Consistent padding: 32px horizontal, 28px top, 24px bottom for main container
   - Card spacing: 12px between items
   - Border radius: 24px for overlay, 14-16px for cards
   - Use subtle borders with white opacity (0.05-0.12)

4. **Typography**:
   - Header: 26px, FontWeight.w700, -0.5 letter spacing
   - Search: 15px regular
   - Card content: 14px with 1.5 line height
   - Timestamps/metadata: 11-12px with reduced opacity

5. **Testing Environment**:
   - Development/testing is done on Arch Linux + OmniArch distro
   - Always test keybindings for conflicts
   - **Hyprland/Wayland**: Uses Ctrl+Shift+\ configured in Hyprland config with signal-based toggle
   - X11 fallback still attempts to register hotkeys via libkeybinder3, but primary method is now signal-based

6. **Code Style**:
   - Keep all UI code in `lib/main.dart` unless complexity demands splitting
   - Use const constructors where possible
   - Prefer composition over inheritance
   - Add TODOs for unimplemented features (e.g., actual clipboard monitoring)

## Next Steps / TODOs

- [ ] Implement actual clipboard monitoring (currently using sample data)
- [ ] Add clipboard item paste functionality
- [ ] Implement search/filter for clipboard history
- [ ] Add persistence for clipboard history
- [ ] Support image and file clipboard items
- [ ] Add Windows support and testing
- [ ] Keyboard navigation (arrow keys, Enter to paste)
- [ ] Settings panel for customization
- [ ] Multiple clipboard "pinboards" like Paste.app
