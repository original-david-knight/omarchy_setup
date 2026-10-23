# Security watch

`security-watch` reviews this machine against new security announcements
every night at 04:00. Headless Claude Code (Opus) does the review. When a danger
is extreme and exploitable here, the run mitigates it itself. The
`david.security` bar widget shows the result and turns solid red when something
needs you.

## What a run does

`security-watch run` (in `bin/bin/`, deployed to `~/bin`):

1. Creates `runs/<UTC timestamp>/` and marks `status.json` as running. The
   previous result stays in place.
2. Gathers an inventory into `inventory/`: `uname -a`, `/etc/os-release`,
   `pacman -Q`, `arch-audit --json`, `arch-audit --upgradable`, `checkupdates`,
   listening sockets, running system and user services, `lsmod`, Flatpaks, the
   contents of `/etc/modprobe.d/security-*.conf`, and security sysctls. A
   missing tool or nonzero exit becomes a line in `inventory/NOTES.txt`. It
   never fails the run. (`checkupdates` exits 2 when nothing is pending.)
3. Runs `claude -p --model opus --permission-mode bypassPermissions
   --output-format json --json-schema …` in the run directory, with a 50-minute
   limit. The prompt gives the review window, the inventory, the sources (Arch
   security tracker, CISA KEV, oss-security, kernel channels, Omarchy, browser
   vendors), the previous findings to carry forward, and the action policy
   below. The raw reply is saved as `claude.json`. Its `structured_output`
   field holds the review.
4. Validates that review at the boundary. An unknown severity or status, a
   missing field, or an extra field fails the run.
5. Computes the level, writes `status.json`, sends a critical desktop
   notification on an alert, and prunes run directories older than 90 days.

The review window starts at the previous successful run's `checkedAt`, which
is the start time of that run. The first review covers every unfixed advisory
that affects installed versions, plus the last 30 days of announcements. A
failed or interrupted run leaves the previous result and window untouched, so
the next run simply covers the longer window.

The kernel is a custom `-omarchy` build. The Arch tracker does not cover it, so
the prompt sends Claude to kernel and Omarchy channels for it.

## Action policy

Claude acts only when all of these hold:

- Severity is critical, or high and actively exploited per CISA KEV or the
  vendor.
- This device runs an affected version.
- The vulnerable component is reachable here: a loaded module, a running or
  listening service, an installed browser, or a local privilege escalation.
  Untrusted code and coding agents run on this machine, so local escalation
  counts.
- No fix is already in place.

Allowed actions, most preferred first:

- A full `sudo pacman -Syu --noconfirm`, never a partial `-Sy <pkg>`.
- If the fix has not reached the configured mirror, the vendor-signed package
  from an official Arch mirror via `sudo pacman -U <url>` with signature checks
  on.
- Blocking a kernel module in `/etc/modprobe.d/security-<id>.conf`
  (`install <module> /bin/false`), unloading it if unused, and rebuilding boot
  images with `sudo limine-mkinitcpio`.
- Stopping and disabling a vulnerable service.
- A ufw deny rule.
- A sysctl in `/etc/sysctl.d/90-security-<id>.conf`.

Never: reboot, shut down or suspend; delete user data; touch credentials, keys
or sudoers; uninstall packages; edit `/usr/share/omarchy`; `git push`; disable
the firewall or updates; end the desktop session; act on medium or low
severity.

Every change is listed in the result's `actions` with the exact command and
its exact revert. Claude also writes `FOLLOWUP-<id>.md` in the run directory,
in the style of `SECURITY-MITIGATION-FOLLOWUP.md`. Anything that needs you, such
as rebooting into a fixed kernel or removing a mitigation that is no longer
needed, goes in that finding's `youShould`.

## State files

Everything lives under `${XDG_STATE_HOME:-~/.local/state}/security-watch/`:

- `status.json` is the widget's only input, replaced atomically.
- `runs/<timestamp>/` holds `inventory/`, `claude.json`, `report.md`, and any
  `FOLLOWUP-<id>.md`.

`status.json` has this shape:

```json
{
  "schema": 1,
  "run": {"state": "running | done | failed", "startedAt": "ISO", "finishedAt": "ISO or null",
          "error": "string or null", "dir": "run directory"},
  "result": {
    "checkedAt": "ISO", "since": "ISO or null",
    "level": "clear | notice | alert",
    "summary": "one line",
    "findings": [{"id": "", "title": "", "severity": "critical | high | medium | low",
                  "status": "exploitable | affected | mitigated | fixed | not-affected",
                  "component": "", "detail": "", "youShould": "string or null", "references": []}],
    "actions": [{"summary": "", "command": "", "revert": ""}],
    "report": "path to report.md"
  }
}
```

`result` is the last successful review, or null before the first one. The
level comes from the wrapper, never the model. It is `alert` if any action was
taken, any finding is `exploitable`, or any finding has a `youShould`. It is
`notice` if any finding is `affected`. Otherwise it is `clear`.

## Running it

`security-watch.timer` (in the `desktop` package) fires `security-watch.service`
at 04:00. It is persistent, so a machine asleep at 04:00 runs the review on
wake. `activate.sh` enables the timer. `arch-audit` is in `packages/core.txt`.

```sh
systemctl --user start --no-block security-watch.service   # run now
journalctl --user -u security-watch.service -f            # follow it
security-watch status                                      # print the last result
systemctl --user list-timers security-watch.timer          # next run
```

The service holds `%t/security-watch.lock`, so a manual start during a timer
run is a quiet no-op. A run is a real Claude session with passwordless sudo
under the action policy, not a dry run.

## Reading the widget

The bar shows a shield:

| State   | Shown when                                     | Look                        |
| ------- | ---------------------------------------------- | --------------------------- |
| alert   | the last result's level is `alert`             | solid red badge, alert shield |
| failed  | the last run failed                            | amber shield with a slash   |
| stale   | the last success is more than 36 hours old     | amber outline shield        |
| running | a run is in progress                           | normal colour, sync shield  |
| notice  | something is `affected`, nothing needed of you | normal colour, half shield  |
| clear   | nothing affects this machine                   | normal colour, check shield |
| never   | no `status.json` yet                           | dimmed outline shield       |

An alert stays red through later running or failed runs until a successful
review clears it. Notice looks calm on purpose. Arch nearly always has a
medium advisory waiting on a fix, and that should not look alarming. The
tooltip gives the summary, the check's age, and the finding count.

Left click opens the panel. It shows the summary and window, then **You
should** items in red boxes, then the changes made with their revert commands
(selectable for copying), then findings sorted by severity and status. Click a
finding to open its first reference. **Run check now** starts the service.
**Open report** opens `report.md` with `omarchy launch editor`.

The widget re-reads `status.json` when it changes and every minute.

## Tests

```sh
python3 -m unittest tests.test_security_watch -v
```

The tests run the real script with a fake `claude` on `PATH`. They cover the
level rules, a successful run's exact `status.json`, a crashed Claude, a
malformed review, the window advancing only on success, and `qmllint` plus
`omarchy plugin validate` for the widget.
