#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
revision=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["asteroids_revision"])' "$repo_dir/toolchains.json")
omarchy pkg add git pkgconf alsa-lib vulkan-icd-loader rust
export PATH="$HOME/.cargo/bin:$PATH"
CARGO_NET_GIT_FETCH_WITH_CLI=true cargo install --git https://github.com/original-david-knight/asteroids \
  --rev "$revision" --locked --bin asteroids --root "$HOME/.cargo" asteroids
[[ -x $HOME/.cargo/bin/asteroids ]]
