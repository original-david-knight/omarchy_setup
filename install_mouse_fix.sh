#!/bin/sh

sudo install -Dm755 mouse_fix/usr/local/bin/ensure-razer-basilisk-mouse /usr/local/bin/ensure-razer-basilisk-mouse
sudo install -Dm644 mouse_fix/etc/systemd/system/ensure-razer-basilisk-mouse.service /etc/systemd/system/ensure-razer-basilisk-mouse.service
sudo install -Dm644 mouse_fix/etc/udev/rules.d/99-razer-basilisk-v3-power.rules /etc/udev/rules.d/99-razer-basilisk-v3-power.rules

sudo systemctl daemon-reload
sudo udevadm control --reload
sudo systemctl enable --now ensure-razer-basilisk-mouse.service
sudo udevadm trigger --subsystem-match=usb

echo "Installed Basilisk boot recovery service and USB power rules."
