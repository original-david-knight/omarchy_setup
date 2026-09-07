#!/usr/bin/env bash
set -euo pipefail
# python is used by ~/bin/herdr-tmux, the helper behind herdr's tmux keybindings
yay -S --noconfirm --needed herdr python
