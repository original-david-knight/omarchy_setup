# CLAUDE.md

This repository provisions personal configuration on Omarchy Quattro. GNU Stow
deploys each top-level package into the user's home directory.

## Commands

```bash
# Install applications and supporting packages.
./install_all.sh

# Deploy configuration. The profile is detected from connected monitors.
./stow_all.sh

# Override profile detection, including from a TTY or test home.
OMARCHY_SETUP_PROFILE=laptop ./stow_all.sh
OMARCHY_SETUP_PROFILE=desktop ./stow_all.sh

# Validate Hyprland after changing Lua config.
hyprctl reload
hyprctl configerrors
```

`stow_all.sh` is safe to rerun. It uses `--no-folding`, leaving real directories
in the home folder and creating links only for files owned by this repository.
Conflicting files are moved to
`~/.local/state/omarchy-setup/backups/<timestamp>.<suffix>/` before deployment.

## Stow packages

Shared packages are `bash`, `tmux`, `zellij`, `herdr`, `omarchy`, `hypr`,
`starship`, `ssh`, `bin`, and `vscode`.

The selected machine profile adds:

- `laptop`: `ghostty` and `bin_laptop`
- `desktop`: `ghostty_big_screen`

`bin_laptop` contains the touchpad auto-toggle helper. Hyprland's
`autostart.lua` launches it only when the executable is present.

The repository manages the Omarchy Shell bar layout through
`omarchy/.config/omarchy/shell.json`. Its center section leaves a 440 px gap
for the desktop monitor's top-center webcam, with the day and date to the left
and the time and weather to the right. Shell-wide font size and horizontal bar
height are configured in `omarchy/.config/omarchy/shell.toml`; the 18 px base
font scales the stock 26 px bar to 39 px.

`herdr` and `bin` must remain non-folded because those directories also hold
runtime state or files owned outside this repository. The deployment script
uses non-folding consistently for every package so profile changes and future
Omarchy-generated files do not write into the repository.

## Hyprland on Quattro

Hyprland configuration is Lua-based:

1. `hyprland.lua` bootstraps `/usr/share/omarchy/default/hypr/` and loads the
   packaged Omarchy defaults.
2. Local `monitors.lua`, `input.lua`, `bindings.lua`, `looknfeel.lua`, and
   `autostart.lua` override those defaults.
3. `hyprsunset.conf` and `xdph.conf` remain separate service configuration
   files and are not part of Hyprland's Lua entrypoint.

Do not restore the retired pre-Quattro `.conf` stack or edit files under
`/usr/share/omarchy/`.

Use `o.bind` for keybindings, `o.window` for window rules, and
`o.launch_on_start` for startup applications. Prefer the routed CLI form for
user-facing commands, such as `omarchy capture screenshot region`.

Monitor rules use EDID descriptions rather than connector names so the layout
survives port renumbering after sleep or reboot.

## herdr keybindings

`herdr/.config/herdr/config.toml` mirrors the tmux bindings, with workspace =
tmux session, tab = tmux window, and prefix = `Ctrl-j`. Multi-key operations
run `~/bin/herdr-tmux`, which drives herdr's socket API.

`herdr config check` only validates TOML syntax. For behavioral testing, use a
scratch session:

```bash
tmux new-session -d -s t -x 200 -y 50 "HERDR_SESSION=scratch herdr"
tmux send-keys -t t C-j c
HERDR_SESSION=scratch herdr tab list
HERDR_SESSION=scratch herdr server stop
herdr session delete scratch
```
