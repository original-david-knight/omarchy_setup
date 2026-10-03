#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
target_home=${OMARCHY_SETUP_TARGET:-$HOME}
backup_root=""
bar_only=0
case ${1:-} in
  --bar-only) bar_only=1 ;;
  '') ;;
  *) echo 'usage: stow_all.sh [--bar-only]' >&2; exit 2 ;;
esac

if [[ -z $target_home || $target_home != /* || $target_home == / ]]; then
  echo "Refusing to use an unsafe stow target: ${target_home:-<empty>}" >&2
  exit 1
fi

resolved_target_home=$(realpath -m -- "$target_home")

command -v stow >/dev/null 2>&1 || {
  echo "GNU Stow is required. Run ./install_stow.sh first." >&2
  exit 1
}

mkdir -p "$target_home"

source "$repo_dir/scripts/setup_profile.sh"
profile=$(setup_profile)

ensure_backup_root() {
  if [[ -z $backup_root ]]; then
    local backup_base="$target_home/.local/state/omarchy-setup/backups"
    mkdir -p "$backup_base"
    backup_root=$(mktemp -d "$backup_base/$(date +%Y%m%d%H%M%S).XXXXXX")
  fi
}

backup_target() {
  local relative=$1 target="$target_home/$1"
  local resolved_parent

  resolved_parent=$(realpath -m -- "$(dirname -- "$target")")
  if [[ $resolved_parent != "$resolved_target_home" && $resolved_parent != "$resolved_target_home/"* ]]; then
    echo "Refusing to move a conflict through a symlink outside $target_home: $target" >&2
    exit 1
  fi

  ensure_backup_root
  mkdir -p "$backup_root/$(dirname -- "$relative")"
  echo "Backing up conflicting target: $target"
  mv -- "$target" "$backup_root/$relative"
}

backup_conflicts() {
  local package=$1 package_dir="$repo_dir/$1"
  local source relative target

  while IFS= read -r -d '' source; do
    relative=${source#"$package_dir/"}
    target="$target_home/$relative"

    [[ -e $target || -L $target ]] || continue
    # Stow only owns relative symlinks. Absolute links and regular hardlinks
    # still conflict even when -ef says they refer to the same source file.
    if [[ -L $target && $(readlink -- "$target") != /* && $source -ef $target ]]; then
      continue
    fi
    # An older deployment may link a whole directory into the package. In that
    # case this path IS the source file, rather than a separate hardlink. Let
    # Stow handle the directory link without moving files out of the repository.
    if [[ ! -L $target && $source -ef $target && $(realpath -m -- "$target") == $(realpath -m -- "$source") ]]; then
      continue
    fi

    backup_target "$relative"
  done < <(find "$package_dir" \( -type f -o -type l \) -print0)
}

unstow_package() {
  local package=$1
  [[ -d $repo_dir/$package ]] || return 0
  stow --delete --no-folding --dir="$repo_dir" --target="$target_home" "$package"
}

stow_package() {
  local package=$1
  backup_conflicts "$package"
  stow --restow --no-folding --dir="$repo_dir" --target="$target_home" "$package"
}

validate_bar_setup() {
  local shell_config="$target_home/.config/omarchy/shell.json"
  local plugin_id plugin_dir source_plugin_dir
  local -a plugin_ids=()

  [[ -r $shell_config ]] || {
    echo "Omarchy bar config was not stowed: $shell_config" >&2
    return 1
  }

  if jq -e '
    ((.bar.layout.left // []) + (.bar.layout.center // []) + (.bar.layout.right // []))
    | any(.[]; (.id // "") == "david.everything")
  ' "$shell_config" >/dev/null; then
    echo "The retired david.everything widget is still in $shell_config" >&2
    return 1
  fi

  jq -e '
    ((.bar.layout.left // []) + (.bar.layout.center // []) + (.bar.layout.right // []))
    | any(.[]; (.id // "") == "david.tasks")
  ' "$shell_config" >/dev/null || {
    echo "The Everything-backed david.tasks widget is missing from $shell_config" >&2
    return 1
  }

  # Every custom widget in the main layout, in each per-screen layout, in the
  # service list, and the selected bar option itself must ship in this repo.
  mapfile -t plugin_ids < <(jq -r '
    [
      (((.bar.layout.left // []) + (.bar.layout.center // []) + (.bar.layout.right // []) + (.plugins // [])
        + ([.bar.screenLayouts[]?.layout | (.left // []) + (.center // []) + (.right // [])] | add // []))[]
        | select((.type // "") == "")
        | (.id // "")),
      (.bar.id // "")
    ][]
    | select(startswith("david.") or . == "jankeesvw.meeting-recorder")
  ' "$shell_config" | sort -u)

  for plugin_id in "${plugin_ids[@]}"; do
    plugin_dir="$target_home/.config/omarchy/plugins/$plugin_id"
    source_plugin_dir="$repo_dir/omarchy/.config/omarchy/plugins/$plugin_id"
    [[ -r $plugin_dir/manifest.json ]] || {
      echo "Shell plugin $plugin_id has no deployed plugin manifest at $plugin_dir" >&2
      return 1
    }
    if [[ ! -d $source_plugin_dir && $plugin_id == jankeesvw.meeting-recorder ]]; then
      source_plugin_dir=/usr/share/omarchy-meeting-recorder/plugin
    fi
    # Stow deliberately deploys symlinks, while the plugin validator rejects
    # symlinks inside its input folder. Validate the authoritative source copy.
    omarchy plugin validate "$source_plugin_dir" >/dev/null
  done

  echo "Validated Omarchy shell with ${#plugin_ids[@]} custom plugins."
}

configure_yazi() {
  local target_config_home="$target_home/.config"
  local sync_script="$target_home/bin/sync-yazi-omarchy-theme"
  local colors_file="$target_home/.local/state/omarchy/current/theme/colors.toml"

  command -v yazi >/dev/null 2>&1 || {
    echo "Yazi is not installed. Run ./install_yazi.sh first." >&2
    exit 1
  }

  if ! command -v xdg-desktop-portal-termfilechooser >/dev/null 2>&1 && \
    [[ ! -x /usr/lib/xdg-desktop-portal-termfilechooser ]] && \
    [[ ! -x /usr/local/lib/xdg-desktop-portal-termfilechooser ]]; then
    echo "The terminal file chooser portal is not installed. Run ./install_yazi.sh first." >&2
    exit 1
  fi

  if [[ ! -x $sync_script ]]; then
    echo "Yazi theme sync helper was not stowed: $sync_script" >&2
    exit 1
  fi

  # Directory launches use Yazi, and future Omarchy theme changes regenerate
  # Yazi's palette from the newly active theme.
  HOME="$target_home" XDG_CONFIG_HOME="$target_config_home" \
    xdg-mime default yazi.desktop inode/directory
  HOME="$target_home" XDG_CONFIG_HOME="$target_config_home" \
    omarchy hook install theme-set "$sync_script"

  if [[ -r $colors_file ]]; then
    HOME="$target_home" XDG_CONFIG_HOME="$target_config_home" "$sync_script"
  else
    echo "Active Omarchy colors are not present yet; the theme hook will generate Yazi's theme after the next theme change."
  fi

  # Only reload the live desktop when deploying to the current user's actual
  # home. Alternate targets are used for profile previews and setup tests.
  if [[ ${OMARCHY_SETUP_ACTIVATE:-1} == 1 && $resolved_target_home == "$(realpath -m -- "$HOME")" ]]; then
    if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
      hyprctl reload >/dev/null
      if [[ -n $(hyprctl configerrors) ]]; then
        hyprctl configerrors >&2
        exit 1
      fi
    fi

    if command -v systemctl >/dev/null 2>&1 && [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
      systemctl --user restart xdg-desktop-portal-termfilechooser.service
      systemctl --user restart xdg-desktop-portal.service
    fi
  fi
}

install_theme() {
  local source="$repo_dir/themes/beachview"
  local themes_dir="$target_home/.config/omarchy/themes"
  local target="$themes_dir/beachview"

  # `omarchy theme set` copies a theme folder's entries with `cp -r`, which
  # would copy per-file Stow links verbatim and break them. Link the whole
  # folder instead; Omarchy treats a symlinked theme as the user's own.
  mkdir -p "$themes_dir"
  if [[ -L $target && $(realpath -- "$target") == "$source" ]]; then
    return
  fi
  if [[ -e $target || -L $target ]]; then
    backup_target ".config/omarchy/themes/beachview"
  fi
  ln -s "$(realpath --relative-to="$themes_dir" -- "$source")" "$target"
}

select_theme() {
  local state="$target_home/.local/state/omarchy/current"
  local background_dir="$target_home/.config/omarchy/backgrounds/beachview"
  local current_background

  [[ ${OMARCHY_SETUP_ACTIVATE:-1} == 1 && $resolved_target_home == "$(realpath -m -- "$HOME")" ]] || return 0
  [[ $(cat "$state/theme.name" 2>/dev/null) != beachview ]] || return 0
  command -v omarchy >/dev/null 2>&1 || {
    echo "Omarchy is not installed; Beachview theme was not selected." >&2
    return 0
  }

  # Selecting a theme advances to the next of its wallpapers. When a Beachview
  # wallpaper is already showing (the bundled first-install selection), keep it.
  current_background=$(realpath -m -- "$state/background" 2>/dev/null || true)
  if [[ $current_background == "$(realpath -m -- "$background_dir")/"* ]]; then
    OMARCHY_THEME_SKIP_BACKGROUND=1 omarchy theme set Beachview
  else
    omarchy theme set Beachview
  fi
}

# Unstow mutually exclusive packages first so switching machine profiles does
# not leave links from the previous profile behind.
if (( ! bar_only )); then
  unstow_package ghostty
  unstow_package ghostty_big_screen
  unstow_package bin_laptop
fi
unstow_package omarchy_desktop
unstow_package omarchy_laptop

shared_packages=(omarchy)
if (( ! bar_only )); then
  shared_packages=(bash tmux zellij herdr omarchy hypr starship bin vscode yazi desktop)
fi
for package in "${shared_packages[@]}"; do
  stow_package "$package"
done

recorder_plugin=/usr/share/omarchy-meeting-recorder/plugin
if [[ -d $recorder_plugin ]]; then
  recorder_target="$target_home/.config/omarchy/plugins/jankeesvw.meeting-recorder"
  if [[ -e $recorder_target || -L $recorder_target ]] && [[ $(realpath -m -- "$recorder_target") != "$recorder_plugin" ]]; then
    backup_target ".config/omarchy/plugins/jankeesvw.meeting-recorder"
  fi
  ln -sfn -- "$recorder_plugin" "$recorder_target"
fi

if [[ $profile == desktop ]]; then
  if (( ! bar_only )); then stow_package ghostty_big_screen; fi
  stow_package omarchy_desktop
else
  if (( ! bar_only )); then
    stow_package ghostty
    stow_package bin_laptop
  fi
  stow_package omarchy_laptop
fi

validate_bar_setup
if (( ! bar_only )); then
  python3 "$repo_dir/scripts/configure_ssh.py" --target "$target_home"
  python3 "$repo_dir/scripts/install_backgrounds.py" --target "$target_home"
  install_theme
  select_theme
  configure_yazi
  HOME="$target_home" XDG_CONFIG_HOME="$target_home/.config" \
    xdg-mime default google-chrome.desktop x-scheme-handler/http x-scheme-handler/https text/html
  if [[ ${OMARCHY_SETUP_ACTIVATE:-1} == 1 && $resolved_target_home == "$(realpath -m -- "$HOME")" ]]; then
    bash "$repo_dir/activate.sh"
  fi
fi

echo "Stowed Omarchy setup for the $profile profile into $target_home."
if [[ -n $backup_root ]]; then
  echo "Conflicting files were preserved in $backup_root."
fi
