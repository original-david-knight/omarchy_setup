#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if command -v omarchy-meeting-recorder >/dev/null && [[ -r /usr/share/omarchy-meeting-recorder/plugin/manifest.json ]]; then
  exit 0
fi
omarchy pkg add base-devel gtk4 libadwaita libpulse ffmpeg
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
cp -- "$repo_dir/packaging/meeting-recorder/PKGBUILD" "$repo_dir/packaging/meeting-recorder/omarchy-meeting-recorder.install" "$build_dir/"
cd -- "$build_dir"
makepkg --syncdeps --install --needed --noconfirm
command -v omarchy-meeting-recorder >/dev/null
