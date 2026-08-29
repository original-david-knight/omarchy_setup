#!/usr/bin/env bash
# Step two of a new machine, once ~/.ssh/id_github.pub (printed by go.sh) is
# on GitHub: point this checkout at its SSH remote and pull the private repos
# that the anonymous first clone could not reach.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd "$repo_dir"

git remote remove origin 2>/dev/null || true
git remote add origin git@github.com:original-david-knight/omarchy_setup.git
git fetch -q origin
git branch -q --set-upstream-to=origin/main main 2>/dev/null || true

./setup_workspace.sh

cat <<'MSG'

Next: the private setup, which carries the secrets this repo cannot.

  cd ~/workspace/omarchy-setup-private && ./go.sh

MSG
