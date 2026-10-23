#!/usr/bin/env bash
# Build Meeting Recorder from David's fork in ~/workspace and install it for
# this user. The fork is public, so a fresh machine clones it before its GitHub
# key exists; pushes use SSH once the key is configured. stow_all.sh links the
# checkout's bar plugin.
set -euo pipefail

workspace_dir="${WORKSPACE_DIR:-$HOME/workspace}"
checkout="$workspace_dir/omarchy-meeting-recorder"
fork=original-david-knight/omarchy-meeting-recorder
upstream=jankeesvw/omarchy-meeting-recorder

omarchy pkg add base-devel rust cmake clang vulkan-headers shaderc vulkan-icd-loader \
  gtk4 libadwaita libpulse ffmpeg

if [[ ! -d $checkout/.git ]]; then
  mkdir -p -- "$workspace_dir"
  git clone -o fork "https://github.com/$fork.git" "$checkout"
  git -C "$checkout" remote set-url --push fork "git@github.com:$fork.git"
  git -C "$checkout" remote add origin "git@github.com:$upstream.git"
fi

cargo build --release --locked --manifest-path "$checkout/Cargo.toml"

# Follows the fork's packaging/INSTALL.md, linking data files to the checkout.
install -Dm755 "$checkout/target/release/omarchy-meeting-recorder" "$HOME/.local/bin/omarchy-meeting-recorder"
mkdir -p -- "$HOME/.local/share/applications" "$HOME/.local/share/mime/packages"
ln -sfn -- "$checkout/data/omarchy-meeting-recorder.desktop" "$HOME/.local/share/applications/omarchy-meeting-recorder.desktop"
ln -sfn -- "$checkout/data/omarchy-meeting-recorder.xml" "$HOME/.local/share/mime/packages/omarchy-meeting-recorder.xml"
update-mime-database "$HOME/.local/share/mime"
xdg-mime default omarchy-meeting-recorder.desktop application/x-omarchy-meeting
