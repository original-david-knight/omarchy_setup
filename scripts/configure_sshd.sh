#!/usr/bin/env bash
# Called as root by install_services.sh.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
config=/etc/ssh/sshd_config.d/10-omarchy-setup.conf
backup=$(mktemp)
existed=0
if [[ -e $config ]]; then
  cp -p "$config" "$backup"
  existed=1
fi
restore_config() {
  if ((existed)); then cp -p "$backup" "$config"; else rm -f "$config"; fi
}
trap 'rm -f "$backup"' EXIT
install -Dm644 "$repo_dir/system/etc/ssh/sshd_config.d/10-omarchy-setup.conf" "$config"
if ! ssh-keygen -A || ! sshd -t; then
  restore_config
  exit 1
fi
# Earlier administrator settings can override a drop-in. Check the effective
# values before enabling the server; keep a running server intact on failure.
if ! effective=$(sshd -T); then
  restore_config
  exit 1
fi
for setting in 'pubkeyauthentication yes' 'authenticationmethods publickey' \
               'passwordauthentication no' 'kbdinteractiveauthentication no'; do
  if ! grep -qixF "$setting" <<< "$effective"; then
    echo "OpenSSH configuration overrides required setting: $setting" >&2
    restore_config
    exit 1
  fi
done
# Accept SSH only over Tailscale, so other devices on a shared network cannot
# reach sshd. Add the tailnet rule before removing the open one; unrelated
# firewall rules are kept.
if command -v ufw >/dev/null; then
  ufw allow in on tailscale0 to any port 22 proto tcp comment 'omarchy-setup-ssh'
  ufw delete allow 22/tcp
fi
systemctl enable sshd.service
systemctl reload-or-restart sshd.service
