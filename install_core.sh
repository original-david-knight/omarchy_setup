#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
mapfile -t packages < <(sed 's/#.*//; /^[[:space:]]*$/d' "$repo_dir/packages/core.txt")
exit_status=0
if omarchy pkg add "${packages[@]}"; then :; else
  exit_status=$?
  [[ $exit_status != 130 ]] || exit 130
  echo 'Arch package installation failed; continuing with AUR packages.' >&2
fi
mapfile -t aur_packages < <(sed 's/#.*//; /^[[:space:]]*$/d' "$repo_dir/packages/aur.txt")
if omarchy pkg aur add "${aur_packages[@]}"; then :; else
  status=$?
  [[ $status != 130 ]] || exit 130
  if ((exit_status == 0)); then exit_status=$status; fi
  echo 'AUR package installation failed; see the installation log.' >&2
fi
exit "$exit_status"
