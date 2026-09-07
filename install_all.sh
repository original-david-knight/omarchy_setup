#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd "$repo_dir"
# Shared with the interactive wizard; a failed manifest read also fails setup.
step_list=$(jq -er 'if .version == 1 then .install[].script else error("unsupported setup plan") end' "$repo_dir/setup/steps.json")
# Child installers inherit stdin for confirmations; only this loop reads fd 3.
failures=()
exit_status=0
while IFS= read -r -u 3 step; do
  [[ $step =~ ^[a-z_]+\.sh$ ]] || { echo "Invalid setup script: $step" >&2; exit 1; }
  printf '\n==> %s\n' "$step"
  if bash "$step"; then :; else
    status=$?
    [[ $status != 130 ]] || exit 130
    failures+=("$step (exit $status)")
    if ((exit_status == 0)); then exit_status=$status; fi
    printf 'Failed: %s (exit %s). Continuing with the remaining installs.\n' "$step" "$status" >&2
  fi
done 3<<< "$step_list"
if ((${#failures[@]})); then
  printf '\nInstallation failures:\n' >&2
  printf '  %s\n' "${failures[@]}" >&2
  printf 'Rerun ./go.sh after addressing these failures.\n' >&2
fi
exit "$exit_status"
