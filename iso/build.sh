#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cache_dir=${OMARCHY_ISO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-setup-iso}
output_dir=${OMARCHY_ISO_OUTPUT_DIR:-$repo_dir/dist}
upstream_commit=2673c613d9a71e23920e43fbb951238145e0f1e8
upstream_url=https://github.com/omacom/omarchy-iso.git
builder_image=archlinux/archlinux:latest

if [[ ${1:-} == --help ]]; then
  cat <<'HELP'
Usage: iso/build.sh

Build a personal Omarchy installer ISO using the stable package mirror.
Requires Linux x86_64, Docker (with sudo access when needed), Git, Python 3,
and enough disk space for the package mirror, build tree, and ISO (~40 GB).

OMARCHY_ISO_CACHE_DIR overrides ~/.cache/omarchy-setup-iso.
OMARCHY_ISO_OUTPUT_DIR overrides this repository's dist/ directory.
The build uses a privileged container; no physical disk is written.
HELP
  exit 0
fi
[[ $# == 0 ]] || { echo 'Use iso/build.sh --help for usage.' >&2; exit 2; }
[[ $(uname -m) == x86_64 ]] || { echo 'This ISO builder requires x86_64.' >&2; exit 1; }
for command in docker git python3 tar sha256sum; do
  command -v "$command" >/dev/null || { printf 'Missing build command: %s\n' "$command" >&2; exit 1; }
done
mkdir -p -- "$cache_dir" "$output_dir"
cache_dir=$(cd -- "$cache_dir" && pwd -P)
output_dir=$(cd -- "$output_dir" && pwd -P)
exec 9>"$cache_dir/build.lock"
flock -n 9 || { echo 'An ISO build is already running in this cache.' >&2; exit 1; }

docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  docker_command=(sudo docker)
fi
"${docker_command[@]}" info >/dev/null

upstream=$cache_dir/upstream
if [[ ! -d $upstream ]]; then
  git init "$upstream"
  git -C "$upstream" remote add origin "$upstream_url"
  git -C "$upstream" fetch --depth 1 origin "$upstream_commit"
  git -C "$upstream" checkout --detach FETCH_HEAD
fi
[[ $(git -C "$upstream" rev-parse HEAD) == "$upstream_commit" ]] || {
  echo 'Cached upstream revision differs from the pinned build. Choose a fresh OMARCHY_ISO_CACHE_DIR.' >&2
  exit 1
}
git -C "$upstream" submodule update --init --recursive --depth 1

build_dir=$(mktemp -d "$cache_dir/build.XXXXXX")
mkdir -p "$build_dir/archiso" "$build_dir/release" "$cache_dir/offline-mirror" "$cache_dir/pacman"
git -C "$upstream" archive HEAD | tar -x -C "$build_dir"
git -C "$upstream/archiso" archive HEAD | tar -x -C "$build_dir/archiso"
python3 "$repo_dir/iso/prepare.py" "$build_dir"
printf 'Build tree: %s\n' "$build_dir"

"${docker_command[@]}" run --rm --privileged \
  --name "omarchy-setup-iso-$(basename "$build_dir")" \
  -e OMARCHY_ISO_REF=quattro -e OMARCHY_MIRROR=stable \
  -e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" \
  -v "$build_dir/release:/out" \
  -v "$build_dir/archiso:/archiso:ro" \
  -v "$build_dir/builder:/builder:ro" \
  -v "$build_dir/configs:/configs:ro" \
  -v "$cache_dir/offline-mirror:/var/cache/airootfs/var/cache/omarchy" \
  -v "$cache_dir/pacman:/var/cache/pacman/pkg" \
  "$builder_image" /builder/build-iso.sh

shopt -s nullglob
images=("$build_dir/release/"*.iso)
[[ ${#images[@]} == 1 ]] || { echo 'Expected exactly one completed ISO.' >&2; exit 1; }
image_name=$(basename -- "${images[0]}")
[[ ! -e $output_dir/$image_name ]] || { echo 'Output ISO already exists; select another OMARCHY_ISO_OUTPUT_DIR.' >&2; exit 1; }
mv -- "${images[0]}" "$output_dir/$image_name"
(cd -- "$output_dir" && sha256sum "$image_name" >"$image_name.sha256")
{
  printf 'upstream_url=%s\nupstream_commit=%s\n' "$upstream_url" "$upstream_commit"
  printf 'archiso_commit=%s\n' "$(git -C "$upstream/archiso" rev-parse HEAD)"
  printf 'builder_image=%s\n' "$("${docker_command[@]}" image inspect "$builder_image" --format '{{.Id}}')"
  printf 'setup_source=https://github.com/original-david-knight/omarchy_setup.git\nsetup_branch=main\n'
  printf 'built_at=%s\n' "$(date -u +%FT%TZ)"
  sha256sum "$repo_dir/bootstrap.sh" "$repo_dir/iso/omarchy-personal-setup" "$repo_dir/iso/post-boot.hook" "$repo_dir/iso/personal_setup.py"
} >"$output_dir/$image_name.build-info"
printf '\nCreated %s\nChecksum: %s\n' "$output_dir/$image_name" "$output_dir/$image_name.sha256"
