#!/usr/bin/env bash
set -euo pipefail
# Preserve the native install style used on this workstation.
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
curl --fail --show-error --location --retry 3 https://claude.ai/install.sh -o "$scratch/install.sh"
bash "$scratch/install.sh"
"$HOME/.local/bin/claude" --version
