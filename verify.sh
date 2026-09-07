#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.cargo/bin:$HOME/.dotnet:$PATH"
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/scripts/verify_setup.py" "$@"
