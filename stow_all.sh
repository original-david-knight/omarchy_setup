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

# Unstow mutually exclusive packages first so switching machine profiles does
# not leave links from the previous profile behind.
unstow_package ghostty
unstow_package ghostty_big_screen
unstow_package bin_laptop

shared_packages=(bash tmux zellij herdr omarchy hypr starship ssh bin vscode)
for package in "${shared_packages[@]}"; do
  stow_package "$package"
done

if [[ $profile == desktop ]]; then
  stow_package ghostty_big_screen
else
  stow_package ghostty
  stow_package bin_laptop
fi

echo "Stowed Omarchy setup for the $profile profile into $target_home."
if [[ -n $backup_root ]]; then
  echo "Conflicting files were preserved in $backup_root."
fi
