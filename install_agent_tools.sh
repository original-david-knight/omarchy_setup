#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# Parse before installing. Keep the list off stdin for standalone use; the
# wizard supplies MISE_YES and closes stdin during unattended installation.
package_list=$(jq -er 'to_entries[] | [.key, .value] | @tsv' "$repo_dir/packages/agent-tools.json")
failures=()
exit_status=0
attempt() {
  if "$@"; then return 0; else
    status=$?
    [[ $status != 130 ]] || exit 130
    failures+=("$* (exit $status)")
    if ((exit_status == 0)); then exit_status=$status; fi
    return "$status"
  fi
}
while IFS=$'\t' read -r -u 3 package binary; do
  if attempt mise use --global "$package@latest"; then
    attempt omarchy mise install "$package" "$binary" || :
  fi
done 3<<< "$package_list"
attempt mise exec npm:playwright -- playwright install chromium || :
if ((${#failures[@]})); then
  printf '\nAgent tool failures:\n' >&2
  printf '  %s\n' "${failures[@]}" >&2
fi
exit "$exit_status"
