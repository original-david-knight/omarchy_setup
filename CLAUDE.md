# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dotfiles repository for an Arch Linux system running Omarchy (a Hyprland-based desktop environment). Configuration files are managed with GNU Stow, which creates symlinks from this repository to the home directory.

## Commands

```bash
# Deploy all configurations (auto-selects laptop vs multi-monitor variants)
./stow_all.sh

# Deploy a single package
stow --target=../ <package-name>

# Remove a stowed package
stow -D --target=../ <package-name>

# Install all dependencies on fresh system
./install_all.sh

# Reload Hyprland config without restart
hyprctl reload
```

## Architecture

### Stow Packages

Each top-level directory mirrors home directory structure. `stow_all.sh` automatically selects between variants based on monitor count:
- Single monitor: `ghostty/`, `waybar_laptop/`
- Multi-monitor: `ghostty_big_screen/`, `waybar/`

### Hyprland Configuration Layering

The Hyprland config (`hypr/.config/hypr/hyprland.conf`) uses a three-layer approach:

1. **Omarchy defaults** - Sourced from `~/.local/share/omarchy/default/hypr/` (don't edit)
2. **Theme settings** - Sourced from `~/.config/omarchy/current/theme/`
3. **Local overrides** - Files in this repo override defaults

Hyprland-specific documentation is in `hypr/.config/hypr/CLAUDE.md`.

### Key Hyprland Patterns

**Keybinding syntax**: `bindd = MODIFIERS, KEY, Description, exec, command`
- Use `uwsm app --` prefix for GUI applications
- Use `omarchy-launch-or-focus` to toggle existing windows
- Use `omarchy-launch-webapp` for web apps in Chrome

**Monitor configuration**: Uses EDID descriptors (`desc:Manufacturer Model Serial`) instead of port names (DP-1) for stability across restarts.

**Omarchy utilities** (in `~/.local/share/omarchy/bin/`):
- `omarchy-launch-or-focus` - Focus existing window or launch new
- `omarchy-launch-webapp` - Open URL in dedicated Chrome window
- `omarchy-cmd-screenshot` - Screenshot with region/window selection

## Debugging

```bash
hyprctl monitors        # Debug monitor setup
hyprctl activewindow    # Get window class for window rules
hyprctl dispatch exec <cmd>  # Test a command
```
