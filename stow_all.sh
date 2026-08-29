#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
target_home=${OMARCHY_SETUP_TARGET:-$HOME}
profile=${OMARCHY_SETUP_PROFILE:-auto}
backup_root=""

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

get_monitor_count() {
  local count=0 status
  local -a statuses=()

  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    count=$(hyprctl monitors -j 2>/dev/null | jq -r 'length' 2>/dev/null || true)
    if [[ $count =~ ^[0-9]+$ ]] && ((count > 0)); then
      printf '%s\n' "$count"
      return
    fi
  fi

  shopt -s nullglob
  statuses=(/sys/class/drm/*/status)
  shopt -u nullglob
  for status in "${statuses[@]}"; do
    if [[ $(<"$status") == connected ]]; then
      ((count += 1))
    fi
  done

  # A headless/TTY run cannot reliably distinguish the machines. Selecting the
  # laptop profile is the conservative fallback and can be overridden below.
  ((count > 0)) || count=1
  printf '%s\n' "$count"
}

case $profile in
  auto)
    monitor_count=$(get_monitor_count)
    if ((monitor_count > 1)); then
      profile=desktop
    else
      profile=laptop
    fi
    ;;
  desktop | laptop) ;;
  *)
    echo "OMARCHY_SETUP_PROFILE must be auto, desktop, or laptop (got: $profile)." >&2
    exit 1
    ;;
esac

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
    if [[ -e $target && $source -ef $target ]]; then
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
  if [[ $resolved_target_home == "$(realpath -m -- "$HOME")" ]]; then
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

# Unstow mutually exclusive packages first so switching machine profiles does
# not leave links from the previous profile behind.
unstow_package ghostty
unstow_package ghostty_big_screen
unstow_package bin_laptop

shared_packages=(bash tmux zellij herdr omarchy hypr starship ssh bin vscode yazi)
for package in "${shared_packages[@]}"; do
  stow_package "$package"
done

if [[ $profile == desktop ]]; then
  stow_package ghostty_big_screen
else
  stow_package ghostty
  stow_package bin_laptop
fi

configure_yazi

echo "Stowed Omarchy setup for the $profile profile into $target_home."
if [[ -n $backup_root ]]; then
  echo "Conflicting files were preserved in $backup_root."
fi
