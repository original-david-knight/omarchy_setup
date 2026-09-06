#!/bin/sh

set -eu

if ! command -v mise >/dev/null 2>&1; then
  yay -S --noconfirm --needed mise
fi

mise use --global aqua:modem-dev/hunk@latest
git config --global pager.diff 'hunk pager'
