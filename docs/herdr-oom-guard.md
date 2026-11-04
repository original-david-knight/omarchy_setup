# Herdr OOM guard

## Why

The Herdr desktop app runs every pane inside one transient systemd unit,
`hc-hold-<id>.service`, under `app.slice`. systemd-oomd watches `app.slice`
and, when memory and swap are both over 90% or memory pressure stays over 50%
for 20 seconds, it kills the largest unit **as a whole**. On 2026-11-03 at
22:42 one runaway process in a pane grew the holder unit to 45.8 GB of RAM
plus 41.3 GB of swap. systemd-oomd then killed all 529 processes in the unit,
including every Claude Code session.

## What it does

`herdr-oom-guard run` (`herdr-oom-guard.service`) polls once a second and
trips when either:

- memory is at least 85% used **and** swap at least 75% used, or
- `app.slice` full memory pressure (avg10) is at least 30% for 5 seconds.

It then picks the process in any `hc-hold-*.service` cgroup with the largest
`VmRSS + VmSwap`, skipping `herdr-core` itself and anything under 512 MiB.
It sends that process SIGTERM, then SIGKILL after 5 seconds, and waits 15
seconds before it acts again. The service runs in `session.slice`, outside
the slice that systemd-oomd kills from.

Every kill is logged with the victim's full command line and shown as a
critical desktop notification. That record shows which job was leaking.

## Use

```bash
herdr-oom-guard check                     # current levels and would-be victim
journalctl --user -u herdr-oom-guard      # kills, with command lines
python3 -m unittest tests.test_herdr_oom_guard
```

Thresholds can be overridden with `HERDR_OOM_GUARD_MEM_LIMIT`,
`HERDR_OOM_GUARD_SWAP_LIMIT` (fractions) and `HERDR_OOM_GUARD_PRESSURE_LIMIT`
(percent) in a drop-in for the service.

Panes of the herdr TUI under tmux are separate `tmux-spawn-*.scope` units, so
systemd-oomd already kills them one at a time. The guard does not watch them.

## Recovering sessions

Claude Code conversations survive the kill. Run `claude --resume` in each
project directory. To list sessions that were active before a given time:

```bash
find ~/.claude/projects -maxdepth 2 -name '*.jsonl' -newermt '<start>' ! -newermt '<kill time>'
```
