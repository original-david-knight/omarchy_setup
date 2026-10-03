#!/usr/bin/env bash
# Resolve the setup profile consistently for installers and Stow.

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

setup_profile() {
  local profile=${OMARCHY_SETUP_PROFILE:-auto} monitor_count
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
      return 1
      ;;
  esac
  printf '%s\n' "$profile"
}
