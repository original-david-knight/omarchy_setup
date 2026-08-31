# CLAUDE.md

This repository provisions personal configuration on Omarchy Quattro. GNU Stow
deploys each top-level package into the user's home directory.

## Commands

```bash
# Run the complete setup (install, deploy, and activate).
./go.sh

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
`starship`, `ssh`, `bin`, `vscode`, and `yazi`.

The selected machine profile adds:

- `laptop`: `ghostty`, `bin_laptop`, and `omarchy_laptop`
- `desktop`: `ghostty_big_screen` and `omarchy_desktop`

`bin_laptop` contains the touchpad auto-toggle helper. Hyprland's
`autostart.lua` launches it only when the executable is present.

The repository manages the Omarchy Shell bar layout through the profile-specific
`omarchy_laptop/.config/omarchy/shell.json` and
`omarchy_desktop/.config/omarchy/shell.json` files. The desktop center section
leaves a 440 px gap for the monitor's top-center webcam; the laptop layout has no
spacer and anchors the clock at the center. Shell-wide font size and horizontal
bar height are configured in `omarchy/.config/omarchy/shell.toml`; the 18 px base
font scales the stock 26 px bar to 39 px.

The Everything-backed entry in both layouts is `david.tasks`, a focused task
list plugin tracked in this repo. It reads `/api/tasks` with the desktop bearer
from `~/.config/everything-agent/config.json`; the broader `david.everything`
summary plugin installed by everything-app is intentionally not in the bar.
The always-expanded `david.tray` clone is tracked alongside the task, Jira,
GitHub, and podcast widgets, so every custom ID in either layout has a matching
plugin in the public stow package. `stow_all.sh` validates that invariant.

`herdr` and `bin` must remain non-folded because those directories also hold
runtime state or files owned outside this repository. The deployment script
uses non-folding consistently for every package so profile changes and future
Omarchy-generated files do not write into the repository.

Yazi is the default directory handler and Chrome file picker. Its portal
configuration is in `yazi/`. `install_yazi.sh` installs Yazi and the portal
backend; after deployment, `stow_all.sh` sets the directory MIME default,
installs the Omarchy `theme-set` hook, generates the initial theme, reloads
Hyprland, and restarts the portal. The hook regenerates
`~/.config/yazi/theme.toml` from the active Omarchy theme's `colors.toml`.

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

## New machine

The public repo comes first because a fresh machine has no credentials:

1. `git clone https://github.com/original-david-knight/omarchy_setup ~/omarchy_setup && cd ~/omarchy_setup && ./go.sh`
   installs the packages, generates `~/.ssh/id_github` and prints its public
   key, and stows the dotfiles.
2. Add the printed key to GitHub.
3. `./after_github_key_configured.sh` switches this checkout to its SSH
   remote and clones the private repos, including
   `~/workspace/omarchy-setup-private`.
4. `cd ~/workspace/omarchy-setup-private && ./go.sh` — the private half:
   secrets, SSH keys, Postgres, and `setup_everything_app.sh`, which leaves
   Everything App built, authenticated against the hosted service, and
   running (companion, bar widgets, pm watchers, morning launcher). The
   companion installer briefly offers its stock summary widget; private setup
   re-runs this repo's stow pass afterward so the tracked task-only layout and
   its `shell.json` symlink remain authoritative.

What this repo already carries for Everything App: `autostart.lua` launches
`~/.local/bin/lifedash-open` when it exists, the stowed `shell.json` places
the task-list bar widget, and that widget and the `david.jira-work`,
`david.github-work` and `david.podcasts` plugins all read the companion's
`~/.config/everything-agent/config.json`. None of it works until the private
step has minted that config.
