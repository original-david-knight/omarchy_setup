#!/bin/sh

sudo pacman -S --needed --noconfirm cmake meson cpio pkg-config git gcc
hyprpm update
hyprpm add https://github.com/hyprwm/hyprland-plugins
hyprpm enable hyprexpo
