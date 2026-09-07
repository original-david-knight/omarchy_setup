#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["dotnet"])' "$repo_dir/toolchains.json")
install_dir="${DOTNET_INSTALL_DIR:-$HOME/.dotnet}"
if [[ -x $install_dir/dotnet ]] && "$install_dir/dotnet" --list-sdks | awk '{print $1}' | grep -Fxq "$version"; then
  echo ".NET SDK $version is already installed."
  exit 0
fi
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
curl --fail --show-error --location --retry 3 https://dot.net/v1/dotnet-install.sh -o "$scratch/dotnet-install.sh"
bash "$scratch/dotnet-install.sh" --version "$version" --install-dir "$install_dir" --no-path
"$install_dir/dotnet" --list-sdks | awk '{print $1}' | grep -Fxq "$version"
