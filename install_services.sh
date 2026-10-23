#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
sudo systemctl enable --now tailscaled.service
sudo tailscale set --operator="$(id -un)"
# New devices still need tailscale login; verification reports that separately.
# Accept SSH only over Tailscale, so other devices on a shared network cannot
# reach sshd. Add the tailnet rule before removing the open one.
if command -v ufw >/dev/null; then
  sudo ufw allow in on tailscale0 to any port 22 proto tcp comment omarchy-setup-ssh
  sudo ufw delete allow 22/tcp
fi
sudo install -Dm755 "$repo_dir/system/usr/local/sbin/capture-prev-boot.sh" /usr/local/sbin/capture-prev-boot.sh
sudo install -Dm644 "$repo_dir/system/etc/systemd/system/boot-forensics.service" /etc/systemd/system/boot-forensics.service
sudo systemctl daemon-reload
sudo systemctl enable boot-forensics.service
