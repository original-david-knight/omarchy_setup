# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a dotfiles repository for an Arch Linux system running Omarchy (a Hyprland-based desktop environment). Configuration files are managed with GNU Stow, which creates symlinks from this repository to the home directory.

## Repository Structure

Each top-level directory is a "stow package" that mirrors the home directory structure:
- `bash/` - Shell configuration (.bashrc, .aliases.sh)
- `hypr/` - Hyprland window manager configs (.config/hypr/)
- `ghostty/` - Ghostty terminal emulator config (.config/ghostty/)
- `ghostty_big_screen/` - Alternative Ghostty config for larger displays
- `tmux/` - Tmux configuration (.tmux.conf)
- `starship/` - Starship prompt config (.config/starship/)
- `aaa_install_scripts/` - Installation scripts (not stowed)

## Commands

### Deploy all configurations
```bash
./aaa_stow_all.sh
```

### Deploy a single package
```bash
stow --target=../ <package-name>
# Example: stow --target=../ bash
```

### Remove a stowed package
```bash
stow -D --target=../ <package-name>
```

### Install dependencies (Arch Linux)
```bash
cd aaa_install_scripts && ./install_all.sh
```

## Key Configuration Details

**Hyprland**: The main config (`hypr/.config/hypr/hyprland.conf`) sources Omarchy defaults from `~/.local/share/omarchy/` and then applies local overrides. Custom keybindings are in `bindings.conf`, monitor setup in `monitors.conf`.

**Bash**: Sources Omarchy defaults, then applies custom aliases and PATH modifications. Uses starship for the prompt.

**Tmux**: Uses `C-j` as prefix (instead of default `C-b`), dracula theme, TPM for plugins.

**Ghostty**: Tokyo Night color scheme, CaskaydiaMono Nerd Font at size 18.
