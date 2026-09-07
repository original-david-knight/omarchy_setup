#!/usr/bin/env bash
set -euo pipefail
workspace_dir="${WORKSPACE_DIR:-$HOME/workspace}"
private_dir="${OMARCHY_PRIVATE_SETUP_DIR:-$workspace_dir/omarchy-setup-private}"
case ${1:-} in
  '' | --private-only) ;;
  *) echo 'usage: setup_workspace.sh [--private-only]' >&2; exit 2 ;;
esac
mkdir -p "$workspace_dir" "$(dirname -- "$private_dir")"

if [ ! -d "$private_dir" ]; then
  git clone git@github.com:original-david-knight/omarchy-setup-private.git "$private_dir"
fi
[[ ${1:-} != --private-only ]] || exit 0

if [ ! -d "$workspace_dir"/davidknight ]; then
  git clone git@github.com:original-david-knight/davidknight.git "$workspace_dir"/davidknight
fi

if [ ! -d "$workspace_dir"/wilder ]; then
  git clone --bare git@github.com:original-david-knight/wilder.git "$workspace_dir"/wilder
fi

if [ ! -d "$workspace_dir"/wilder/main ]; then
  git -C "$workspace_dir"/wilder worktree add main main
fi
