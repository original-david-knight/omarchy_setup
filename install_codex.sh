#!/usr/bin/env bash
set -euo pipefail
# Use the same ownership as Omarchy's CLI wrappers, and actually install now.
# Do not create a second root-owned npm installation hidden behind the wrapper.
mise use --global codex@latest
omarchy mise install codex
mise exec codex -- codex --version
