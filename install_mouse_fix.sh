#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd "$repo_dir"
source "$repo_dir/scripts/setup_profile.sh"
profile=$(setup_profile)

service=ensure-razer-basilisk-mouse.service
installed_files=(
  /usr/local/bin/ensure-razer-basilisk-mouse
  /etc/systemd/system/$service
  /etc/udev/rules.d/99-razer-basilisk-v3-power.rules
)

# The Basilisk and its hub chain are desktop-only. On any other machine the
# recovery service would reset whichever hub sits at the default USB path.
if [[ $profile != desktop ]]; then
  if [[ -e /etc/systemd/system/$service ]]; then
    sudo systemctl disable --now "$service"
  fi
  removed=0
  for file in "${installed_files[@]}"; do
    if [[ -e $file ]]; then
      sudo rm -f -- "$file"
      removed=1
    fi
  done
  if ((removed)); then
    sudo systemctl daemon-reload
    sudo udevadm control --reload
    echo "Removed the Basilisk recovery service from the $profile profile."
  else
    echo "Skipping the Basilisk recovery service on the $profile profile."
  fi
  exit 0
fi

sudo install -Dm755 mouse_fix/usr/local/bin/ensure-razer-basilisk-mouse /usr/local/bin/ensure-razer-basilisk-mouse
sudo install -Dm644 mouse_fix/etc/systemd/system/$service /etc/systemd/system/$service
sudo install -Dm644 mouse_fix/etc/udev/rules.d/99-razer-basilisk-v3-power.rules /etc/udev/rules.d/99-razer-basilisk-v3-power.rules

sudo systemctl daemon-reload
sudo udevadm control --reload
sudo systemctl enable --now "$service"
sudo udevadm trigger --subsystem-match=usb

echo "Installed Basilisk boot recovery service and USB power rules."
