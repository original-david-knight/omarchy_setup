# Omarchy setup

The public half of this desktop's setup, followed by the private
`~/workspace/omarchy-setup-private` repository. Start with a completed **Omarchy
4.x / Quattro x86_64 installation**; the audited baseline is 4.0.2. These Lua
settings and shell plugins require Quattro.

```sh
git clone https://github.com/original-david-knight/omarchy_setup.git ~/omarchy_setup
cd ~/omarchy_setup
./setup.sh
```

The terminal wizard runs `omarchy update -y` first, then checks the updated
baseline and prepares administrator/SSH access. It finishes public application
installs (including Chrome), configuration,
and readiness checks before requesting GitHub access. Once public setup passes,
it fetches and prepares private setup, installs its tools, and guides account
sign-ins and opening checks. Connection actions launch automatically and
advance when their account checks pass. Application installs run unattended with live
output and private logs; failures are recorded while independent steps continue.
If Omarchy offers a reboot during its update, defer it until setup finishes.

Run `./setup.sh` again to resume. Completed steps are retained, and changes to
a script or its declared inputs cause that step and subsequent steps to run
again. Account connections and readiness are checked on every run. A profile
change reapplies configuration while retaining completed package installs.

```sh
./setup.sh --plan                 # Preview; executes nothing
./setup.sh --profile laptop       # Choose a profile explicitly
./setup.sh --public-only          # Finish the public half first
./setup.sh --restart              # Back up progress and rerun the scripts
./setup.sh --defer-checks         # Install, then leave application checks pending
```

The wizard reports completion only when installs and final readiness checks
pass. Failures and skipped dependencies appear in the final report; sign-ins
you defer remain pending. Read [the wizard guide](docs/setup-wizard.md)
for resume behavior, logs, custom paths, and the original script-driven flow.
`./go.sh` and the individual scripts remain available for that flow.

For a USB installer handoff, bundle `bootstrap.sh` and launch it in a terminal
as the new desktop user after the first graphical login. It clones this public
repository from GitHub `main` into `~/omarchy_setup`, or refreshes an existing
clean `main` checkout with a fast-forward update, then runs `setup.sh`. The
setup revision comes from GitHub at launch time, so updating setup does not
require rebuilding the USB image. Build the installer with `./iso/build.sh`;
see [the USB installer guide](docs/usb-installer.md) for the build, first-login
handoff, and VM validation.

```sh
bash /path/to/bundled/bootstrap.sh --profile laptop
```

`OMARCHY_SETUP_DIR` selects a different absolute checkout path. The bootstrap
uses public HTTPS without GitHub authentication and passes arguments to the
wizard. Local changes, other branches, and local-only commits stop the refresh
without being overwritten. If GitHub is unavailable, it waits while you connect
Wi-Fi, then continues automatically. Ctrl+C pauses setup. Run
`omarchy-personal-setup` to resume an ISO installation, or explicitly run the
existing `setup.sh` to use a cached checkout. A bootstrap `--plan` still
clones or updates files; `./setup.sh --plan` remains the read-only preview.
The USB needs only this public launcher. Private setup and credentials are
fetched later through the wizard's existing GitHub authentication handoff.

Everything App is private. Its source checkout, build setup, and passcode live
in `omarchy-setup-private`. This public repository supplies widgets and launch
hooks that read the local configuration deployed by private setup; it contains
no Everything App credentials. Account sign-ins such as Slack also run in the
private phase, after GitHub authentication and the private checkout handoff.

## What this installs

- Supplemental packages in `packages/core.txt` and `packages/aur.txt`: desktop
  dependencies, Ghostty and its font, VPN/Tailscale, voice input,
  calendar tooling, cloud CLIs, compilers and mobile build prerequisites.
- Browser/editor/terminal applications, VS Code extensions, Listening and its
  Spotify/mpv/Qt dependencies, .NET, and Asteroids. `packages/agent-tools.json`
  installs the Omarchy agent CLIs eagerly instead of leaving only first-run
  wrappers. Claude uses its native installer; Codex and the other listed agent
  tools use mise.
- Hyprland settings and bindings; desktop/laptop bars; all five custom plugins;
  Yazi and its portal/theme hook; terminal/browser/file-manager defaults;
  voice model/configuration; primary-selection bridge; Tailscale,
  Bluetooth, mouse recovery, and boot-forensics services; initial Plymouth art.

Dropbox is currently excluded from installation, bar layouts, account sign-in,
and readiness checks.

Stock widgets and standard OS services come from Omarchy. Package repositories
and agent CLIs remain rolling releases. `toolchains.json` pins .NET and the
Asteroids source; the private repository pins coupled application sources and
Android tooling. Flutter reuses the existing SDK or installs the latest stable
release when absent. This is a supported-baseline installer, not a frozen
Arch package mirror or a backup of browser sessions, databases, and user files.

## Profiles and file ownership

Automatic selection uses attached displays: multiple displays select desktop;
a single display selects laptop. To choose explicitly:

```sh
OMARCHY_SETUP_PROFILE=desktop ./go.sh
OMARCHY_SETUP_PROFILE=laptop ./stow_all.sh
```

Conflicting files are moved into `~/.local/state/omarchy-setup/backups/`.
Existing absolute symlinks into this repo are backed up too, then replaced with
relative links that Stow can manage.
Unrelated runtime files survive Stow. Profile changes remove obsolete profile
links. `./stow_all.sh --bar-only` restores the custom bar following Everything
App's first desktop installation.

SSH uses a preserved top-level config with `Include ~/.ssh/config.d/*.conf`.
Public GitHub settings belong to `10-omarchy-public.conf`; the private setup
owns `00-private.conf` and work/Render identities. Neither setup replaces the
other's hosts. Existing authorized keys are retained.

For a file deployment preview, use a disposable target and disable activation:

```sh
OMARCHY_SETUP_TARGET=/tmp/omarchy-preview OMARCHY_SETUP_PROFILE=desktop \
  OMARCHY_SETUP_ACTIVATE=0 ./stow_all.sh
```

A normal run enables and starts installed services in the graphical session,
validates Hyprland, and applies the boot art. `./activate.sh` can finish this
after logging in. Identical art does not trigger another initramfs rebuild.

## Verification

```sh
./verify.sh
python3 scripts/audit_bootstrap.py
python3 -m unittest discover -s tests -v
```

The offline bootstrap probes use real Stow and disposable homes, with package
installs and service activation replaced by test doubles. They cover failure
propagation, empty-home SSH/.NET setup, profile changes, conflict backups,
private SSH preservation, Everything failure recovery, and private credential
refresh. They do not alter the running desktop.

Real source-build validation also covers Asteroids, the personal CLI tools,
Everything backend/frontend and the Android debug APK.

See [the audit](docs/reproduction-audit.md) for original findings and the
implementation/validation follow-up. Clean OS package replay and a complete
reboot/login acceptance pass still need to be performed on a spare installation.
