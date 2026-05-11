#!/bin/sh

yay -S --noconfirm --needed git pkgconf alsa-lib vulkan-icd-loader || exit 1
export PATH="$HOME/.cargo/bin:$PATH"

if [ -x "$HOME/.cargo/bin/asteroids" ]; then
  echo "asteroids already installed at $HOME/.cargo/bin/asteroids"
else
  if ! command -v cargo >/dev/null 2>&1; then
    yay -S --noconfirm --needed rustup || exit 1
  fi

  if command -v rustup >/dev/null 2>&1; then
    rustup toolchain install stable || exit 1
    rustup default stable || exit 1
  fi

  CARGO_NET_GIT_FETCH_WITH_CLI=true cargo install --git https://github.com/original-david-knight/asteroids asteroids --locked --bin asteroids || exit 1
fi
