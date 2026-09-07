#!/usr/bin/env bash
set -euo pipefail

out_dir="/var/log/boot-forensics"
mkdir -p "$out_dir"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_file="$out_dir/prev-boot-${stamp}.log"

{
  echo "# Boot Forensics Snapshot"
  echo "# Generated: $(date -Is)"
  echo "# Hostname: $(hostname)"
  echo "# Kernel: $(uname -r)"
  echo

  echo "== Boot List =="
  journalctl --list-boots || true
  echo

  echo "== Previous Boot: Last 400 Lines =="
  journalctl -b -1 -n 400 --no-pager || true
  echo

  echo "== Previous Boot: Kernel Warnings+ =="
  journalctl -b -1 -k -p warning --no-pager || true
  echo

  echo "== Previous Boot: Priority 0..3 =="
  journalctl -b -1 -p 0..3 --no-pager || true
  echo

  echo "== Current Boot: Previous Reset Reason =="
  journalctl -b 0 -k --no-pager | grep -F "Previous system reset reason" || true
  echo

  echo "== Recent Login/Reboot History =="
  last -x -n 80 || true
} > "$out_file"

chmod 0640 "$out_file"

# Keep only the newest 40 snapshots.
ls -1t "$out_dir"/prev-boot-*.log 2>/dev/null | tail -n +41 | xargs -r rm -f
