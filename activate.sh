#!/usr/bin/env bash
set -euo pipefail
# This is the live activation step, after files and binaries have been deployed.
if ! systemctl --user show-environment >/dev/null 2>&1; then
  echo 'No user systemd session. Log in graphically and run ./activate.sh.' >&2
  exit 3
fi
systemctl --user daemon-reload
for unit in primary-selection-sync.service voxtype.service omarchy-tailscale-receive.service; do
  systemctl --user enable "$unit"
  if systemctl --user is-active --quiet graphical-session.target; then
    systemctl --user start "$unit"
  fi
done
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null
  errors=$(hyprctl configerrors)
  [[ -z ${errors//[[:space:]]/} ]] || { printf '%s\n' "$errors" >&2; exit 1; }
fi
state_dir="$HOME/.local/state/omarchy-setup"
mkdir -p "$state_dir"
art_hash=$(cat "$HOME/.config/omarchy/branding/screensaver.txt" "$HOME/bin/apply-omarchy-plymouth-death-star" | sha256sum | cut -d ' ' -f 1)
if [[ ! -f $state_dir/plymouth.sha256 || $(<"$state_dir/plymouth.sha256") != "$art_hash" ]]; then
  "$HOME/bin/apply-omarchy-plymouth-death-star"
  printf '%s\n' "$art_hash" > "$state_dir/plymouth.sha256"
fi
