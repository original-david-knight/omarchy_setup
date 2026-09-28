# Temporary monitor wake rollback

Recorded September 9, 2026 (America/Los_Angeles), for the desktop `cosmic`.

## Situation

Twice in succession, returning after idle left only the left ASUS monitor
working. The center LG and right ASUS remained connected, but Hyprland
reported both at `0x0@60`, with `disabled=false` and `dpmsStatus=true`.
The previous incident required a reboot.

The local log shows DisplayPort disconnect/reconnect events after display
sleep. The center and right monitors exchanged display controllers (CRTCs),
then every mode test failed with `Invalid argument`. DPMS cycling, monitor
disable/enable, configuration reload, lower refresh rates, DDC power cycling,
and renderer reload did not restore the displays. The kernel log showed no
system suspend/resume during this incident.

This closely matches [Aquamarine #386](https://github.com/hyprwm/aquamarine/issues/386),
including a [desktop monitor-sleep reproduction](https://github.com/hyprwm/aquamarine/issues/386#issuecomment-5600741615).
It is a strong diagnosis, not yet a locally verified fix. A
[separate NVIDIA report](https://github.com/hyprwm/aquamarine/issues/391)
also reports success reverting the same package set.

The affected upgrade was installed locally on September 8 at 13:19 PDT.
Hardware: RTX 4090, NVIDIA driver 610.57.04; kernel 7.2.3-arch1-3.

## Rollback and update hold

Installation status: installed September 9, 2026 at 23:39 PDT. All three
package versions and the effective pacman update hold were verified.
Package signature/integrity checks and dependency resolution passed;
`pacman -Dk` reported no database errors. An upgrade preview selected none
of the held packages. The installed Hyprland resolves `libaquamarine.so.13`
with no missing shared libraries.

| Package | Affected version | Rollback version |
| --- | --- | --- |
| aquamarine | 0.15.0-2 | 0.14.0-2 |
| hyprland | 0.56.2-2 | 0.56.2-1 |
| hyprtoolkit | 0.5.4-5 | 0.5.4-4 |

These three packages must move together: the Hyprland and hyprtoolkit
rebuilds depend on Aquamarine's changed shared-library ABI. The rollback
uses their signed packages already in `/var/cache/pacman/pkg`.

The temporary hold is `/etc/pacman.d/omarchy-monitor-wake-hold.conf`, included
from the `[options]` section of `/etc/pacman.conf`. It contains:

```ini
IgnorePkg = aquamarine hyprland hyprtoolkit
```

This prevents normal Omarchy updates from reinstalling the affected versions.
**It also blocks future fixed versions until explicitly removed.** It has no
automatic expiry. Do not force dependency-breaking updates around the hold.
This is a local incident workaround, not a permanent setup default for other
machines. Kernel, NVIDIA driver, monitor layout, refresh-rate configuration,
and automatic lock/display-sleep settings are not part of this rollback.

## Activation and validation

Save work and reboot after installation. The running compositor retains the
old loaded library until its process exits; `hyprctl reload` does not replace it.

After reboot, check:

```sh
pacman -Q aquamarine hyprland hyprtoolkit
pacman-conf IgnorePkg
hyprctl version
hyprctl monitors all
```

Confirm all three displays have their expected resolutions, then verify that
they survive the normal idle/lock/display-sleep cycle. Record the result here.

Original September 9 validation status: reboot and an idle/wake test were still
pending. See the September 21 follow-up below for the current running version.

## Follow-up: September 21, 2026

**Recommendation: keep all three holds for now. The matching upstream bug has
a released fix, but this machine's configured stable repositories still offer
the affected versions.**

- [PR #410](https://github.com/hyprwm/aquamarine/pull/410) merged September 15
  and closed [issue #386](https://github.com/hyprwm/aquamarine/issues/386).
  It explicitly disables the kernel display output before disconnect cleanup,
  addressing the stale-CRTC mechanism identified in this incident.
- [Aquamarine v0.15.1](https://github.com/hyprwm/aquamarine/releases/tag/v0.15.1),
  published September 17 UTC, includes that fix. Arch's normal `extra`
  repository has [0.15.1-1](https://archlinux.org/packages/extra/x86_64/aquamarine/).
  The earlier [PR #395](https://github.com/hyprwm/aquamarine/pull/395) remains
  unmerged; #410 is the shipped fix.
- A [September 19 NVIDIA RTX report](https://github.com/omacom/omarchy/issues/11249#issuecomment-5743230408)
  confirms DisplayPort wake works after manually installing 0.15.1-1.
  An [Intel report](https://github.com/hyprwm/aquamarine/issues/386#issuecomment-5711421996)
  also confirms repeated monitor power-cycle recovery. However, a
  [September 18 Panther Lake/xe report](https://github.com/hyprwm/aquamarine/issues/386#issuecomment-5735809983)
  still describes hotplug failure on 0.15.1, with a pending-page-flip error;
  whether that is the same bug is unconfirmed. The separate hybrid-NVIDIA
  [issue #391](https://github.com/hyprwm/aquamarine/issues/391) remains open.

Live repository indexes were downloaded and inspected September 21 at about
15:59 UTC, independently of the local pacman cache. `/etc/pacman.d/mirrorlist`
uses `https://stable-mirror.omarchy.org/$repo/os/$arch`. Its
[extra index](https://stable-mirror.omarchy.org/extra/os/x86_64/extra.db)
still has:

| Package | Configured stable repository version |
| --- | --- |
| aquamarine | 0.15.0-2 |
| hyprland | 0.56.2-2 |
| hyprtoolkit | 0.5.4-5 |

The live [Omarchy package index](https://pkgs.omarchy.org/stable/x86_64/omarchy.db)
contains no override for these packages. Simply removing the holds and updating
would therefore reinstall the affected set.

Local checks still show the three rollback versions installed and held.
`hyprctl version` confirms the running compositor uses Aquamarine 0.14.0, and
all three monitors currently report their expected resolutions. No sleep/wake
test or test of 0.15.1 was performed during this investigation. No packages,
holds, repository settings, or system package databases were changed.

## Removing the hold once fixed packages reach the configured repositories

Once a fixed release and compatible packages reach the configured repositories:

1. Remove only `Include = /etc/pacman.d/omarchy-monitor-wake-hold.conf` from
   `/etc/pacman.conf` (for example, with `sudoedit /etc/pacman.conf`).
2. Delete that now-unused fragment with
   `sudo rm /etc/pacman.d/omarchy-monitor-wake-hold.conf`.
3. Run `pacman-conf IgnorePkg` and confirm these three packages are no longer
   held; preserve any unrelated holds added later.
4. Run `omarchy update` to update the compatible package set together.
5. Reboot, repeat the display/idle checks, and update this note with the fixed
   versions and verification result.

## Local evidence and backups

Monitor-only diagnostic snapshots, selected backend log lines, and the
investigation notes are under
`~/.local/state/omarchy-setup/monitor-recovery/`.

The privileged rollback saved the original pacman configuration and installed
package versions under
`/var/lib/omarchy-monitor-rollback/20260910T063900Z/` before changes, and the
resulting package versions after installation.
Use those backups for comparison; restoring the entire old pacman configuration
later could discard unrelated subsequent edits.
