#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
extensions_file="$repo_dir/vscode/extensions.txt"
command -v code >/dev/null || { echo 'VS Code is required; run install_vscode.sh.' >&2; exit 1; }
[[ -r $extensions_file ]] || { echo "Missing $extensions_file" >&2; exit 1; }
# Leave stdin available to Code instead of passing it the extension list.
failures=()
exit_status=0
while IFS= read -r -u 3 extension || [[ -n $extension ]]; do
  case "$extension" in '' | \#*) continue ;; esac
  if code --install-extension "$extension" --force; then :; else
    status=$?
    [[ $status != 130 ]] || exit 130
    failures+=("$extension (exit $status)")
    if ((exit_status == 0)); then exit_status=$status; fi
  fi
done 3< "$extensions_file"
if ((${#failures[@]})); then
  printf '\nVS Code extension failures:\n' >&2
  printf '  %s\n' "${failures[@]}" >&2
fi
exit "$exit_status"
