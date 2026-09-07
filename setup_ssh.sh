#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ssh_dir="$HOME/.ssh"
key="${GITHUB_PERSONAL_SSH_KEY:-$ssh_dir/id_github}"
install -d -m 700 "$ssh_dir" "$(dirname -- "$key")"
if [[ ! -f $key ]]; then
  ssh-keygen -q -t ed25519 -C "${GITHUB_PERSONAL_SSH_KEY_COMMENT:-omarchy-setup}" -N '' -f "$key"
fi
chmod 600 "$key"
if [[ ! -f $key.pub ]]; then ssh-keygen -y -f "$key" > "$key.pub"; fi
chmod 644 "$key.pub"
python3 "$repo_dir/scripts/configure_ssh.py" --target "$HOME" --identity "$key"
# IdentityFile works without starting another long-lived agent on every run.
if [[ -n ${SSH_AUTH_SOCK:-} ]]; then ssh-add "$key"; fi
if [[ ${OMARCHY_SETUP_WIZARD:-0} == 1 ]]; then
  printf '\nPersonal GitHub key is ready. The wizard will check access before starting the installs.\n'
else
  printf '\nAdd this public key to GitHub, then run ./after_github_key_configured.sh:\n'
  cat "$key.pub"
fi
