# Paste Pro

A beautiful clipboard manager for Linux and Windows, inspired by [Paste.app](https://pasteapp.io/).

## Quick Start

```bash
flutter run -d linux
```

Press **Ctrl+Shift+\\** to toggle the overlay.

## Features

- ✨ Smooth Paste.app-like animations
- 🎨 Beautiful dark gradient UI
- ⌨️ System-wide keyboard shortcut
- 🔍 Search clipboard history
- 💾 Persistent clipboard storage (coming soon)
- 🖼️ Support for text, images, and files

## Setup for Hyprland/Wayland

Since this app runs on Hyprland, keybindings work through Unix signals:

1. The app is already configured - just run it
2. Press **Ctrl+Shift+\\** to toggle
3. The binding is in `~/.config/hypr/bindings.conf`

To change the keybinding, edit your Hyprland config and point it to `pastepro-toggle.sh`.

## Build & Run

| Action                                  |                     Command                     |
| --------------------------------------- | :----------------------------------------------: |
| Run on Linux                            |               flutter run -d linux               |
| Run on macOS                            |               flutter run -d macos               |
| Run on Windows                          |              flutter run -d windows              |
| Enable Linux desktop support            |      flutter config --enable-linux-desktop      |
| Enable macOS desktop support            |      flutter config --enable-macos-desktop      |
| Enable Windows desktop support          |     flutter config --enable-windows-desktop     |
| Regenerate desktop platform scaffolding | flutter create --platforms=linux,macos,windows . |

## Requirements

**Arch Linux:**
```bash
sudo pacman -S cmake ninja gtk3 pkg-config libkeybinder3
```

**Ubuntu/Debian:**
```bash
sudo apt install cmake ninja-build libgtk-3-dev pkg-config libkeybinder-3.0-dev
```
