#!/usr/bin/env bash
# Let the desktop user drive the SteelSeries Arctis Nova Pro Omni base station's
# vendor HID interface, which the david.headset bar widget uses for ANC, volume,
# sidetone, and battery. The tag must run before the 73-seat-late-uaccess rule.
set -euo pipefail
rule=/etc/udev/rules.d/70-david-arctis-omni.rules
content='# SteelSeries Arctis Nova Pro Omni (david.headset bar widget)
KERNEL=="hidraw*", SUBSYSTEMS=="usb", ATTRS{idVendor}=="1038", ATTRS{idProduct}=="2290", TAG+="uaccess"'
if [[ ! -r $rule ]] || [[ $(<"$rule") != "$content" ]]; then
  printf '%s\n' "$content" | sudo tee "$rule" >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=hidraw --action=add
fi
echo "Arctis Nova Pro Omni access rule is installed."
