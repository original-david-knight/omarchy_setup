#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
sudo systemctl enable --now tailscaled.service
# Key-only OpenSSH, reachable only over Tailscale (scripts/configure_sshd.sh).
python3 "$repo_dir/scripts/configure_ssh.py" --target "$HOME"
sudo bash "$repo_dir/scripts/configure_sshd.sh"
# Set only these preferences, preserving DNS, routes, and exit-node choices.
# Tailscale SSH would intercept port 22 and can demand a browser check, and
# shields-up would block every incoming connection while still showing up.
sudo tailscale set --operator="$(id -un)" --ssh=false --shields-up=false
# New devices sign in later; tailscale-keepalive prompts until they do.
sudo install -Dm755 "$repo_dir/system/usr/local/sbin/capture-prev-boot.sh" /usr/local/sbin/capture-prev-boot.sh
sudo install -Dm644 "$repo_dir/system/etc/systemd/system/boot-forensics.service" /etc/systemd/system/boot-forensics.service
sudo systemctl daemon-reload
sudo systemctl enable boot-forensics.service
