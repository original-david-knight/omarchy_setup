#!/usr/bin/env bash
set -euo pipefail
command -v omarchy >/dev/null || { echo 'A completed Omarchy Quattro installation is required.' >&2; exit 1; }
version=$(omarchy version)
[[ $version == 4.* ]] || { echo "Supported baseline: Omarchy 4.x (got $version)." >&2; exit 1; }
for cmd in bash git curl python3 jq sudo; do
  command -v "$cmd" >/dev/null || { echo "Missing baseline command: $cmd" >&2; exit 1; }
done
[[ -r ${OMARCHY_PATH:-/usr/share/omarchy}/default/hypr/bootstrap.lua ]] || {
  echo 'The Quattro Lua bootstrap is missing. Complete the Omarchy installation first.' >&2; exit 1;
}
