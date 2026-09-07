# Clean-install reproduction audit — 2026-09-07

The original public setup did not reproduce this workstation reliably. The
changes accompanying this audit address the public bootstrap, configuration,
and orchestration findings below. The remaining acceptance test is a clean
Omarchy package replay followed by graphical login, account sign-ins, and reboot.

The audit used public commit `7ab4718` and an installed Omarchy 4.0.2-1
(Quattro) baseline. These configurations require Omarchy 4.x and its Lua
bootstrap. This is a supported-baseline installer, not a frozen package mirror.

Private application revisions, source/build details, service inventories, and
the original combined audit are kept in the private setup repository under
`docs/combined-reproduction-audit.md` and `docs/reproduction-audit.md`.

## Public findings and resulting behavior

### Installer failures must remain visible without stopping independent work

The original installer sourced child scripts without reliable error handling.
A later successful command could hide an earlier failure, and a child `exit`
could terminate the entire installation before later tools were attempted.

Installers now run as independent Bash processes. Failed installs are recorded,
remaining independent steps continue, and the installation pass ends with a
nonzero result and a failure summary. Multi-tool and extension installers also
continue their remaining items. The wizard skips steps whose declared
prerequisites failed, records the reason, and retries unfinished work on resume.
A successful readiness probe cannot erase an earlier installation failure.

### SSH preparation must work in an empty home and preserve private hosts

The original key-generation script ran before `~/.ssh` existed. Public Stow
also replaced the SSH configuration installed by private setup.

Preparation now creates the required directories with restrictive permissions,
preserves existing keys, and recovers a missing public key when possible. Public
SSH settings live in `config.d/10-omarchy-public.conf`; a top-level Include
preserves separately owned private hosts. Existing authorized keys are retained.

GitHub access is prepared before the main installation pass. The private setup
owns its account details and identities. Passphrases needed for later Git
operations are loaded into an SSH agent during preparation.

### .NET installation must not depend on an already-customized PATH

The original installer downloaded into a bin directory that might not exist
and then invoked the download by its bare filename.

The installer now downloads to a temporary path, executes that path explicitly,
selects the SDK destination, and verifies the installed SDK. `toolchains.json`
records the public source/toolchain selections.

### Declared desktop behavior needs matching packages and activation

The original setup did not install every tool referenced by its bindings,
helpers, and configuration, and deployed services could remain inactive until
another graphical login.

The package manifests and installers now cover supplemental desktop tools,
terminal/font dependencies, voice input, agent CLIs, and supporting services.
Configuration includes terminal/browser/file-manager defaults and explicit
service activation. Private applications and account-dependent tools remain
owned by the private setup.

Initial Plymouth artwork application is part of setup. Applying identical art
does not trigger another initramfs rebuild. Theme maintenance still uses the
tracked post-update hook.

### Configuration deployment must preserve existing local files

Stow now handles desktop/laptop profile switches, backs up conflicting files,
and preserves unrelated runtime configuration. Absolute symlinks and regular
hardlinks are migrated to relative Stow links. Legacy directory links are
handled without moving source files out of the repository.

The bar-only mode restores the public bar independently of unrelated desktop
and SSH configuration. Alternate deployment targets support disposable previews
with activation disabled. The current session's display environment is retained.

### Setup questions and opening checks must not interrupt installation

The wizard collects profile and access choices before the main installation
pass. It fetches and loads the private plan during preparation. Account details
and application sign-in steps remain in that private manifest.

Installation runs with live output, private logs, and input closed. Failures do
not open retry menus. After all installs, the wizard prints the failure report,
runs application sign-ins and opening checks, and performs final readiness
checks. `--defer-checks` leaves the interactive application checklist for later.
See [the wizard guide](setup-wizard.md) for resume behavior and exit codes.

## Public coverage

| Area | Ownership and validation |
| --- | --- |
| Desktop packages and agent CLIs | Public package manifests and installers; failure aggregation tested |
| Hyprland, terminal, editor, and file-manager configuration | Public Stow packages; profile switching and conflict handling tested |
| Public widgets | Source and launch helpers public; credentials read from local runtime configuration |
| SSH | Public include and preserved authorized keys; private identities owned separately |
| Voice input, Bluetooth, mouse recovery, and boot diagnostics | Public configuration, installers, and activation helpers |
| Plymouth artwork | Public art and apply/update helpers |
| Private applications and sign-ins | Private manifest and provisioning; implementation details excluded here |

Dropbox is excluded from the current installation and readiness scope. Stock
widgets and standard OS services come from the supported Omarchy baseline.
Package repositories and unpinned agent CLIs remain rolling releases.

## Verification

The public and private test suites pass. The offline bootstrap audit passes all
22 expectations, including installer failure reporting, fresh-home SSH/.NET
setup, real Stow profile changes and legacy-link migration, preserved private
SSH configuration, and isolated public/private handoff probes.

The wizard tests cover upfront preparation, unattended execution, multiple
failures, skipped prerequisites, resume behavior, private report permissions,
deferred application checks, and interruption cleanup. SDK tests in the private
repository cover automatic license acceptance and propagation of SDK failures.
The public secret review found no credential values in the current working
files after removing the hardcoded Wi-Fi password; historical disclosure
findings are separate from clean-install validation.

```sh
python3 -m unittest discover -s tests -v
python3 scripts/audit_bootstrap.py
./setup.sh --plan
```

Tests and probes use disposable homes and fixture commands. They do not install
packages or change the running desktop. Full package replay on a spare Omarchy
installation, real sign-ins, graphical login, reboot, and a second complete
setup run remain required for end-to-end acceptance.
