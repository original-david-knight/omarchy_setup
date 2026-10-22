# Temporary monitor wake rollback

Recorded September 9, 2026 (America/Los_Angeles), for the desktop `cosmic`.

Current status, October 18: all four package holds have been removed. The
upgrade preview succeeds; installation, reboot, and monitor-wake validation
remain pending.

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

The temporary hold used `/etc/pacman.d/omarchy-monitor-wake-hold.conf`, included
from the `[options]` section of `/etc/pacman.conf`. Its final contents were:

```ini
IgnorePkg = aquamarine hyprland hyprtoolkit hyprland-guiutils
```

The `hyprland-guiutils` hold was added October 18 to keep it compatible with
the held toolkit. See the October 18 follow-up below.

This prevented normal Omarchy updates from reinstalling the affected versions.
It also blocked future fixed versions until explicitly removed, with no
automatic expiry. Do not force dependency-breaking updates around such a hold.
This is a local incident workaround, not a permanent setup default for other
machines. Kernel, NVIDIA driver, monitor layout, refresh-rate configuration,
and automatic lock/display-sleep settings are not part of this rollback.

## Activation and validation

Save work and reboot after installation. The running compositor retains the
old loaded library until its process exits; `hyprctl reload` does not replace it.

After reboot, check:

```sh
pacman -Q aquamarine hyprland hyprtoolkit hyprland-guiutils
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

## Follow-up: October 18, 2026

Omarchy's update failed because `hyprland-guiutils` 0.2.2-4 requires
`libhyprtoolkit.so=6-64`, while the held toolkit provides version 5.
The original hold omitted this dependent package. Added `hyprland-guiutils`
to the existing hold, retaining its installed version 0.2.2-3 and the three
rollback versions above. The previous fragment is backed up at
`/etc/pacman.d/omarchy-monitor-wake-hold.conf.bak-20261018T111926Z`.

With the effective four-package hold, `pacman -Sup --noconfirm` now resolves
the upgrade successfully and selects none of those packages. `pacman -Dk`
reports no database errors. No packages were upgraded during this repair;
rerun `omarchy update` to continue the update.

The configured stable mirror's live index now offers the fixed Aquamarine
release and compatible packages:

| Package | Configured stable repository version |
| --- | --- |
| aquamarine | 0.15.1-1 |
| hyprland | 0.56.2-4 |
| hyprtoolkit | 0.6.0-1 |
| hyprland-guiutils | 0.2.2-4 |

The [0.15.1 release notes](https://github.com/hyprwm/aquamarine/releases/tag/v0.15.1)
confirm the disconnect fix described above. A preview with the rollback hold
removed also resolves successfully. The September 21 repository limitation
has therefore cleared, but monitor wake with these versions remains untested
on this machine.

Later October 18, removed all four holds at David's request by removing the
include from `/etc/pacman.conf` and deleting the unused fragment. Both files
were backed up under
`/var/lib/omarchy-monitor-rollback/unhold-20261018T112143Z/`.
The effective `IgnorePkg` list is now empty. The actual upgrade preview
resolves successfully and selects all four repository versions listed above;
`pacman -Dk` still reports no database errors. Package installation, reboot,
and monitor-wake testing remain pending.

## Removing the hold once fixed packages reach the configured repositories

Once a fixed release and compatible packages reach the configured repositories:

1. Remove only `Include = /etc/pacman.d/omarchy-monitor-wake-hold.conf` from
   `/etc/pacman.conf` (for example, with `sudoedit /etc/pacman.conf`).
2. Delete that now-unused fragment with
   `sudo rm /etc/pacman.d/omarchy-monitor-wake-hold.conf`.
3. Run `pacman-conf IgnorePkg` and confirm these four packages are no longer
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
