#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd "$repo_dir"

failures=()
exit_status=0
for step in install_all.sh stow_all.sh verify.sh; do
  if bash "$repo_dir/$step"; then :; else
    status=$?
    [[ $status != 130 ]] || exit 130
    failures+=("$step (exit $status)")
    if ((exit_status == 0)); then exit_status=$status; fi
  fi
done
if ((${#failures[@]})); then
  printf '\nSetup failures:\n' >&2
  printf '  %s\n' "${failures[@]}" >&2
fi
exit "$exit_status"
