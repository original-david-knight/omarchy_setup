# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Hyprland window manager configuration for an Omarchy-based Arch Linux desktop. These files are deployed via GNU Stow to `~/.config/hypr/`.

## Architecture

The configuration uses a layered approach:

1. **Omarchy defaults** (sourced from `~/.local/share/omarchy/default/hypr/`) provide base behavior
2. **Theme settings** (sourced from `~/.config/omarchy/current/theme/`) control colors and visual style
3. **Local overrides** (this directory) customize behavior on top of defaults

This layering is defined in `hyprland.conf` - defaults are sourced first, then local files override them.

## File Responsibilities

| File | Purpose |
|------|---------|
| `hyprland.conf` | Main entry point, sources all other configs and defines window rules |
| `monitors.conf` | Display setup using EDID descriptors for stability across sleep/wake |
| `bindings.conf` | Application keybindings (terminal, browser, apps) |
| `input.conf` | Keyboard/mouse/touchpad settings |
| `looknfeel.conf` | Visual tweaks (gaps, rounding) |
| `autostart.conf` | Extra processes to launch at login |
| `envs.conf` | Environment variables (requires Hyprland relaunch) |
| `hypridle.conf` | Idle timeout behavior (screensaver, lock, dpms) |
| `hyprlock.conf` | Lock screen appearance and fingerprint auth |
| `hyprsunset.conf` | Night light/color temperature (disabled by default) |
| `xdph.conf` | XDG portal settings for screen sharing |

## Key Patterns

**Keybinding syntax**: `bindd = MODIFIERS, KEY, Description, exec, command`
- Use `uwsm app --` prefix for GUI applications
- Use `omarchy-launch-or-focus` to toggle existing windows
- Use `omarchy-launch-webapp` for web apps in Chrome

**Monitor configuration**: Uses EDID descriptors (`desc:Manufacturer Model Serial`) instead of port names (DP-1) for consistent behavior across system restarts.

**Window rules**: Use the new `windowrule { }` block syntax with `match:class` for targeting.

## Commands

```bash
# Reload config without restarting
hyprctl reload

# Test a keybinding
hyprctl dispatch exec <command>

# Debug monitor setup
hyprctl monitors

# Check active window class (for window rules)
hyprctl activewindow
```

## Omarchy Integration

Custom `omarchy-*` commands are available in `~/.local/share/omarchy/bin/`:
- `omarchy-launch-or-focus` - Focus existing window or launch new
- `omarchy-launch-webapp` - Open URL in dedicated Chrome window
- `omarchy-launch-editor` - Launch configured editor
- `omarchy-launch-tui` - Launch TUI app in floating terminal
- `omarchy-cmd-screenshot` - Screenshot with region/window selection
- `omarchy-lock-screen` - Lock screen and 1password

Reference: https://wiki.hyprland.org/Configuring/
