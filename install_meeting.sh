#!/usr/bin/env bash
# Install access and the user plugin for the Logitech Litra Glow meeting widget.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$repo_dir/scripts/setup_profile.sh"
profile=$(setup_profile)
source_plugin="$repo_dir/omarchy/.config/omarchy/plugins/david.meeting"
config_home=${XDG_CONFIG_HOME:-"${HOME:?HOME is required}/.config"}
plugins_dir="$config_home/omarchy/plugins"
installed_plugin="$plugins_dir/david.meeting"

[[ -r $source_plugin/manifest.json && -r $source_plugin/Panel.qml && \
   -x $source_plugin/litra && -x $source_plugin/calendar ]] || {
  echo "The david.meeting plugin is incomplete at $source_plugin" >&2
  exit 1
}

rule=/etc/udev/rules.d/70-david-litra-glow.rules
content='# Logitech Litra Glow (david.meeting bar widget)
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", SUBSYSTEMS=="usb", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c900", TAG+="uaccess"'
mkdir -p -- "$plugins_dir"
physical_plugins=$(realpath -- "$plugins_dir")
expected_plugin=$(realpath -- "$source_plugin")
relative_plugin=$(realpath --relative-to="$physical_plugins" -- "$expected_plugin")
plugin_state=missing
if [[ -L $installed_plugin ]]; then
  if [[ $(realpath -m -- "$installed_plugin") != "$expected_plugin" ]]; then
    echo "Refusing to replace unrelated plugin symlink: $installed_plugin" >&2
    exit 1
  fi
  plugin_state=linked
elif [[ -d $installed_plugin ]]; then
  while IFS= read -r -d '' source_file; do
    relative_file=${source_file#"$source_plugin/"}
    if [[ ! $source_file -ef $installed_plugin/$relative_file ]]; then
      echo "Refusing to replace unrelated plugin copy: $installed_plugin" >&2
      exit 1
    fi
  done < <(find "$source_plugin" -type f -print0)
  plugin_state=stowed
elif [[ -e $installed_plugin ]]; then
  echo "Refusing to replace unrelated plugin copy: $installed_plugin" >&2
  exit 1
fi

if [[ $profile == desktop ]] && { [[ ! -r $rule ]] || [[ $(<"$rule") != "$content" ]]; }; then
  printf '%s\n' "$content" | sudo tee "$rule" >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=hidraw --action=add
fi

if [[ $plugin_state == linked ]]; then
  if [[ $(readlink -- "$installed_plugin") != "$relative_plugin" ]]; then
    replacement="$plugins_dir/.david.meeting.$$.link"
    trap 'rm -f -- "$replacement"' EXIT
    ln -s -- "$relative_plugin" "$replacement"
    mv -Tf -- "$replacement" "$installed_plugin"
    trap - EXIT
  fi
elif [[ $plugin_state == missing ]]; then
  ln -s -- "$relative_plugin" "$installed_plugin"
fi

shell_config="$config_home/omarchy/shell.json"
if [[ -e $shell_config ]]; then
  resolved_shell=$(realpath -- "$shell_config")
  python3 - "$shell_config" "$resolved_shell" "$profile" <<'PY'
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

logical_path = Path(sys.argv[1])
path = Path(sys.argv[2])
config = json.loads(path.read_text())
right = config.setdefault("bar", {}).setdefault("layout", {}).setdefault("right", [])
entry = next((item for item in right if isinstance(item, dict) and item.get("id") == "david.meeting"), None)
litra = sys.argv[3] == "desktop"
changed = entry is None or entry.get("litra") != litra
if entry is None:
    after = next((i for i, item in enumerate(right) if isinstance(item, dict) and item.get("id") == "jankeesvw.meeting-recorder"), None)
    if after is None:
        after = next((i for i, item in enumerate(right) if isinstance(item, dict) and str(item.get("id", "")).endswith("tray")), -1)
    entry = {"id": "david.meeting"}
    right.insert(after + 1, entry)
if changed:
    entry["litra"] = litra
    backup = logical_path.with_name(logical_path.name + ".bak." + str(time.time_ns()))
    shutil.copy2(path, backup)
    handle, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(handle, "w") as output:
            json.dump(config, output, indent=2, ensure_ascii=False)
            output.write("\n")
        os.chmod(temporary, path.stat().st_mode)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
PY
fi

echo "The david.meeting plugin is installed for the $profile profile."
