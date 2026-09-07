#!/usr/bin/env bash
set -euo pipefail
target_user=$(id -un)
temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$target_user" > "$temporary"
sudo visudo -cf "$temporary"
sudo install -o root -g root -m 0440 "$temporary" "/etc/sudoers.d/$target_user"
