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
- Single monitor (laptop): `ghostty/`, `waybar_laptop/`, `bin_laptop/` (touchpad auto-toggle)
- Multi-monitor (desktop): `ghostty_big_screen/`, `waybar/`

`bin_laptop/` holds laptop-only scripts kept out of the shared `bin/` package. The
`autostart.conf` entry that launches `~/bin/auto-touchpad-toggle` is guarded with an
existence test, so it cleanly no-ops on machines where the package isn't stowed.

`herdr/` is stowed with `--no-folding` because herdr writes sockets, logs and
session state into `~/.config/herdr/`; folding would symlink that whole directory
into this repo.

### herdr Keybindings

`herdr/.config/herdr/config.toml` ports the bindings from `tmux/.config/tmux/tmux.conf`
(workspace = tmux session, tab = tmux window, prefix = `Ctrl-j`). herdr binds one key
per built-in action, so tmux bindings that need a second key - and the ones with no
built-in action at all (tab reordering, directional resize, theme cycling) - run
`~/bin/herdr-tmux` from `[[keys.command]]` entries, which drives herdr's socket API.

`herdr config check` only validates TOML syntax; it reports `ok` for nonsense keys
like `gibberish+zz`. To actually verify a binding, drive the TUI in a scratch session
and watch the effect over the API:

```bash
tmux new-session -d -s t -x 200 -y 50 "HERDR_SESSION=scratch herdr"
tmux send-keys -t t C-j c                      # prefix + c
HERDR_SESSION=scratch herdr tab list           # confirm it landed
HERDR_SESSION=scratch herdr server stop && herdr session delete scratch
```

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
