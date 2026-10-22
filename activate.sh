#!/usr/bin/env bash
set -euo pipefail
# This is the live activation step, after files and binaries have been deployed.
if ! systemctl --user show-environment >/dev/null 2>&1; then
  echo 'No user systemd session. Log in graphically and run ./activate.sh.' >&2
  exit 3
fi
systemctl --user daemon-reload
# Apply boot-only cleanup (including Herdr snapshots) on the next boot.
# Do not start it now: an active Herdr session may still be using those files.
systemctl --user enable systemd-tmpfiles-setup.service
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
# The Listening EQ sink runs in its own filter-chain daemon. Restart it only
# when its graph changed, since that briefly drops Listening playback.
eq_hash=$(cat "$HOME/.config/pipewire/filter-chain.conf.d/70-listening-eq.conf" \
  "$HOME/.config/systemd/user/filter-chain.service.d/listening-eq.conf" | sha256sum | cut -d ' ' -f 1)
systemctl --user enable filter-chain.service
if [[ -f $state_dir/listening-eq.sha256 && $(<"$state_dir/listening-eq.sha256") == "$eq_hash" ]]; then
  systemctl --user start filter-chain.service
else
  systemctl --user restart filter-chain.service
fi
printf '%s\n' "$eq_hash" > "$state_dir/listening-eq.sha256"
art_hash=$(cat "$HOME/.config/omarchy/branding/screensaver.txt" "$HOME/bin/apply-omarchy-plymouth-death-star" | sha256sum | cut -d ' ' -f 1)
if [[ ! -f $state_dir/plymouth.sha256 || $(<"$state_dir/plymouth.sha256") != "$art_hash" ]]; then
  "$HOME/bin/apply-omarchy-plymouth-death-star"
  printf '%s\n' "$art_hash" > "$state_dir/plymouth.sha256"
fi
