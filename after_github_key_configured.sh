#!/usr/bin/env bash
# Step two of a new machine, once ~/.ssh/id_github.pub (printed by go.sh) is
# on GitHub: point this checkout at its SSH remote and pull the private repos
# that the anonymous first clone could not reach.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd "$repo_dir"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin git@github.com:original-david-knight/omarchy_setup.git
else
  git remote add origin git@github.com:original-david-knight/omarchy_setup.git
fi
git fetch -q origin
git branch -q --set-upstream-to=origin/main main 2>/dev/null || true

./setup_workspace.sh

if [[ ${OMARCHY_SETUP_WIZARD:-0} != 1 ]]; then
cat <<'MSG'

Next: the private setup, which carries the secrets this repo cannot.

  cd ~/workspace/omarchy-setup-private && ./go.sh

MSG
fi
