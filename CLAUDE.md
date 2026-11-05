# CLAUDE.md

This repository provisions personal configuration on Omarchy Quattro. GNU Stow
deploys each top-level package into the user's home directory.

Follow [AGENTS.md](AGENTS.md) for the public/private setup boundary, especially
Everything App source provisioning, credentials, and account sign-in steps.

We generally commit straight to `main` in this repo rather than working on
branches. It is not a hard rule: use a branch when a change warrants one.

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

`install_hunk.sh` installs Hunk through mise and configures the global
`pager.diff` setting so `git diff` opens Hunk. It runs as part of
`install_all.sh` and can be rerun independently. Use `git --no-pager diff`
for plain output.

## Stow packages

Shared packages are `bash`, `tmux`, `zellij`, `herdr`, `herdr_app`, `omarchy`, `hypr`,
`starship`, `ssh`, `bin`, `vscode`, and `yazi`.

The selected machine profile adds:

- `laptop`: `ghostty`, `bin_laptop`, and `omarchy_laptop`
- `desktop`: `ghostty_big_screen` and `omarchy_desktop`

`bin_laptop` contains the touchpad auto-toggle helper. Hyprland's
`autostart.lua` launches it only when the executable is present.
`omarchy_laptop` also carries `~/.config/hypr/laptop-bindings.lua`, which
`bindings.lua` loads only when present. Its Ctrl+Shift+Space sends Alt+Down
(herdr's `next_workspace`) to the focused window, so it switches workspaces in
a remote herdr reached over SSH, where `herdr-tmux` would act locally.

The repository manages the Omarchy Shell bar layout through the profile-specific
`omarchy_laptop/.config/omarchy/shell.json` and
`omarchy_desktop/.config/omarchy/shell.json` files. The desktop center section
leaves a 440 px gap for the monitor's top-center webcam; the laptop layout has no
spacer and anchors the clock at the center. Shell-wide font size and horizontal
bar height are configured in `omarchy/.config/omarchy/shell.toml`; the 18 px base
font scales the stock 26 px bar to 39 px.

The desktop profile selects `david.bar` as its bar option (`bar.id`). That
plugin runs the untouched stock bar and rebinds the module lists of screens
matched by `bar.screenLayouts` (which may only use widgets also in
`bar.layout`), so the portrait side monitors show only
workspaces and the clock while the center monitor keeps `bar.layout`. Edit
`screenLayouts` by hand; the `omarchy bar` commands and widget drags only touch
`bar.layout`. See `docs/bar-screen-layouts.md`.

The Everything-backed entry in both layouts is `david.tasks`, a focused task
list plugin tracked in this repo. Click a row to open that task on the web, or
use its × button to mark it finished. It reads and creates rows through
`/api/tasks` and completes them with `PATCH /api/tasks/{id}`, using the desktop
bearer from `~/.config/everything-agent/config.json`; the
broader `david.everything` summary plugin installed by everything-app is
intentionally not in the bar.
Tasks, Jira, and both PR queues offer **Assign** to choose a project and agent;
the existing project is the default. The shared form and authenticated
`delegate` helper live in `david.tasks`, so deploy the widgets together through
`stow_all.sh --bar-only`. See `docs/everything-widgets.md` for behavior and tests.
The always-expanded `david.tray` clone is tracked alongside the task, Jira,
GitHub, and podcast widgets, so every custom ID in either layout has a matching
plugin in the public stow package. `stow_all.sh` validates that invariant.

Both profiles keep global workspace numbers instead of Omarchy 4.5's
per-monitor blocks of ten; the desktop pins 1-5 center, 6-7 right, and 8-9
left in `monitors.lua`. `bindings.lua` disables `o.workspaces.reconcile` and
rebinds Super+N with `o.rebind` (plain `o.bind` adds a second binding next to
the stock one). Both bar layouts use `david.workspaces`, a clone of the stock
widget that lists the workspaces on each monitor under their real numbers.
`stow_all.sh` restores the tracked `shell.json` if a running shell rewrites it
with defaults while the profile package is relinked.

`david.podcasts` is the unified **Listening** widget: Spotify through MPRIS,
the existing Everything podcast player, and three independently controlled
myNoise soundscapes. Its stable ID preserves both profile layouts. The
`david.media` service routes media keys to the last source played, including
podcasts through mpv-mpris. Its **EQ** shapes only those three sources through
the `listening_eq` PipeWire filter-chain sink (`desktop/.config/pipewire/`), run by
`filter-chain.service`, which `activate.sh` enables. `install_listening.sh`
installs its dependencies. See `docs/listening-widget.md` for controls,
configuration, and diagnostics.

`david.headset` controls the SteelSeries Arctis Nova Pro Omni through its base
station's vendor HID interface: ANC mode and strength, transparency, the DAC's
own volume, microphone mute (PipeWire) and sidetone, its ten EQ bands, and
battery.
Its `headset` helper is dependency-free Python; `install_headset.sh` installs
the udev rule that grants the seated user access. See `docs/headset-widget.md`.

`security-watch` (`bin`) is a nightly security review by headless Claude Code.
`security-watch.timer` (`desktop`, enabled by `activate.sh`) runs it at 04:00.
It reviews announcements since the last successful check against an inventory
of this machine, mitigates only what its action policy allows, and writes
`~/.local/state/security-watch/status.json`. The wrapper, not the model,
computes the level. The `david.security` widget, next to power in both
layouts, reads that file and turns solid red on an alert. Do not start the
service casually: it is a real Claude run with sudo. See
`docs/security-watch.md`.

`herdr-oom-guard` (`bin`, run by `herdr-oom-guard.service` in `desktop`,
enabled by `activate.sh`) protects the Herdr app's sessions. Every app pane
runs in one `hc-hold-*.service` unit, and systemd-oomd kills a whole unit, so
one runaway process used to take every session with it. The guard trips at
85% memory with 75% swap, or sustained memory pressure, and kills only the
largest pane process. `herdr-oom-guard check` shows the state and the would-be
victim. See `docs/herdr-oom-guard.md`.

`david.agents` replaces the stock `omarchy.agents` in both layouts. It loads
the untouched stock Agents panel by URL and adds an **Account** row to its
Claude Code section that switches Claude Code between saved subscription logins through
`claude-account` (`bin`). Saved logins live in
`~/.local/state/claude-accounts/`, never in the repo. See
`docs/claude-accounts.md`.

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

`tel:` links open Google Fi web calling through `bin/bin/fi-call`. The Fi page
takes no number in its URL, so the helper copies the number and sends Ctrl+V to
the new window; the user presses Enter to dial. `stow_all.sh` generates
`fi-call.desktop` with an absolute `Exec` path, because xdg-open splits `Exec`
on whitespace, and refreshes `mimeinfo.cache` so the desktop portal sees it.

## Beachview theme

`themes/beachview/` is the custom Omarchy theme, a higher-contrast fork of
Tokyo Night. `colors.toml` drives Ghostty (which loads the theme's generated
`ghostty.conf`), herdr (`terminal` theme), Neovim (generated `aether`
colorscheme), btop, and Hyprland borders (`hyprland_active_border`).
`stow_all.sh` links the whole folder to `~/.config/omarchy/themes/beachview`
rather than stowing per-file links, because `omarchy theme set` copies theme
entries with `cp -r` and would break relative file links. It then selects
Beachview when another theme is active. Its wallpapers are the bundled
`backgrounds/beachview/` images; Omarchy's stock wallpapers are not used.
Apply edits with `omarchy theme set Beachview`.
Redraw the theme picker's `preview.png` after palette, icon, or default
wallpaper changes with `python3 scripts/render_theme_preview.py`; it draws
invented content so no session data reaches the public repo.

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
tmux session, tab = tmux window, and prefix = `Ctrl-j`. Pane focus uses
prefix then `Shift-h/j/k/l` for left/down/up/right; closing a workspace uses
prefix then `Ctrl-k`. Multi-key operations run `~/bin/herdr-tmux`, which drives
herdr's socket API.

The Herdr desktop app (`herdr-app`, configured in `~/.config/herdr-app/`) is
separate from the TUI and has no prefix key of its own. `herdr_app/` stows its
`keys.json`, which repeats the TUI bindings as `ctrl-j <key>` chords plus the
direct `alt-` keys. Actions with no app command (resize, tab reordering, pane
cycling, theme cycling) are left out. So is copy mode (`ctrl-j [`): the app
cannot scroll a terminal from the keyboard, only with the mouse wheel
(herdrdev/herdr-app#160). `bin/bin/sync-herdr-app-config` copies
Ghostty's font family and size (pt converted to px) into the app's
`settings.json`. Herdr's sidebar text only grows with `zoom`, so the script
sets `zoom` to the terminal px divided by 21.33 (never below 1) and divides it back
out of the terminal `font_size`; the desktop gets 2. It also writes the active Omarchy palette to
`themes/omarchy.json`. `stow_all.sh` runs it and installs it as a `theme-set`
hook. The app reloads these files live; `herdr-app status` reports file errors.

Hyprland's Ctrl+media-Next and Shift+media-Next keys (next workspace, next
agent) run `herdr-tmux`. While a `herdr-app` window is open, it sends them to the
app (`herdr-app do space.next` / `agent.next`), because the app's spaces live in
herdr-core rather than the TUI server. Runs from TUI keybindings, which set
`HERDR_ACTIVE_*`, always stay on the TUI. While the Claude desktop app
(`com.anthropic.Claude`) has focus, Shift+media-Next instead sends the app's
next-session shortcut, Ctrl+Shift+].

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
