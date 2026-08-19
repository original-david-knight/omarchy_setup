#!/usr/bin/env bash
set -euo pipefail

SSID="WeWorkWiFi"
IDENTITY="${WEWORK_WIFI_IDENTITY:-david@knight.fm}"
PASSWORD="${WEWORK_WIFI_PASSWORD:-plugs-harms-wood-step}"
DOMAIN_MASK="${WEWORK_WIFI_DOMAIN_MASK:-wenw.net}"
CA_CERT="${WEWORK_WIFI_CA_CERT:-/etc/ssl/certs/ca-certificates.crt}"
CONNECTION="${WEWORK_WIFI_CONNECTION:-${SSID}}"
FALLBACK_SSID="knight"
CONNECT_WAIT_SECONDS="${CONNECT_WAIT_SECONDS:-60}"
LOG_ROOT="${WEWORK_WIFI_LOG_ROOT:-/var/log/wework-wifi}"
MODE="${1:-connect}"

# Detect the wireless interface. Quattro names it wlp3s0, but do not hard-code
# a PCI path that changes with hardware.
detect_wifi_device() {
  nmcli -t -f DEVICE,TYPE device status 2>/dev/null |
    awk -F: '$2 == "wifi" { print $1; exit }'
}
DEVICE="${WIFI_DEVICE:-$(detect_wifi_device)}"

# The previously validated profile failed with "PEAP ... bad_certificate".
# Default to a less secure profile that omits certificate validation. Set
# WEWORK_WIFI_SKIP_CERT_VALIDATION=0 to restore CA/domain validation.
SKIP_CERT_VALIDATION="${WEWORK_WIFI_SKIP_CERT_VALIDATION:-1}"

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

usage() {
  cat <<EOF
Usage:
  sudo ./connect_wework_wifi.sh
  sudo ./connect_wework_wifi.sh --recover-knight

Environment:
  WEWORK_WIFI_PASSWORD=...              default: hard-coded in this script
  WEWORK_WIFI_IDENTITY=...              default: ${IDENTITY}
  WIFI_DEVICE=...                       default: autodetected (${DEVICE:-none})
  CONNECT_WAIT_SECONDS=...              default: ${CONNECT_WAIT_SECONDS}
  WEWORK_WIFI_SKIP_CERT_VALIDATION=0    use CA/domain validation
EOF
}

setup_logging() {
  START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
  RUN_ID="$(date '+%Y%m%d-%H%M%S')"
  LOG_DIR="${LOG_ROOT}/${RUN_ID}"
  LOG_FILE="${LOG_DIR}/run.log"

  install -d -m 700 -o root -g root "${LOG_DIR}"
  exec > >(tee -a "${LOG_FILE}") 2>&1

  echo "Started: ${START_TIME}"
  echo "Diagnostics directory: ${LOG_DIR}"
}

capture_cmd() {
  local stage="$1"
  local name="$2"
  shift 2

  local out="${LOG_DIR}/${stage}-${name}.txt"
  local rc=0
  {
    echo "# captured: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# command: $*"
    echo
    "$@" || rc=$?
    echo
    echo "# exit_status=${rc}"
  } >"${out}" 2>&1 || true
}

capture_profiles() {
  local stage="$1"
  local out="${LOG_DIR}/${stage}-nm-profiles-redacted.txt"

  {
    echo "# captured: $(date '+%Y-%m-%d %H:%M:%S')"
    nmcli -f NAME,UUID,TYPE,AUTOCONNECT,DEVICE connection show

    for name in "${CONNECTION}" "${FALLBACK_SSID}"; do
      echo
      echo "# connection: ${name}"
      # Without --show-secrets nmcli prints "<hidden>" for passwords.
      nmcli connection show "${name}" 2>&1 || true
    done
  } >"${out}" 2>&1 || true
}

collect_diagnostics() {
  local stage="${1//[^A-Za-z0-9_.-]/_}"

  [[ -n "${LOG_DIR:-}" && -d "${LOG_DIR}" ]] || return 0
  echo "Collecting diagnostics: ${stage}"

  {
    echo "stage=${stage}"
    echo "mode=${MODE}"
    echo "captured=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "started=${START_TIME}"
    echo "ssid=${SSID}"
    echo "connection=${CONNECTION}"
    echo "identity=${IDENTITY}"
    echo "domain_mask=${DOMAIN_MASK}"
    echo "ca_cert=${CA_CERT}"
    echo "skip_cert_validation=${SKIP_CERT_VALIDATION}"
    echo "device=${DEVICE}"
    echo "fallback_ssid=${FALLBACK_SSID}"
    echo "connect_wait_seconds=${CONNECT_WAIT_SECONDS}"
    echo
    uname -a
    echo
    id
  } >"${LOG_DIR}/${stage}-summary.txt" 2>&1 || true

  capture_profiles "${stage}"
  capture_cmd "${stage}" "rfkill" rfkill list
  capture_cmd "${stage}" "ip-brief-link" ip -brief link
  capture_cmd "${stage}" "ip-brief-addr" ip -brief addr
  capture_cmd "${stage}" "ip-route-all" ip route show table all
  capture_cmd "${stage}" "iw-link" iw dev "${DEVICE}" link
  capture_cmd "${stage}" "nmcli-general" nmcli general status
  capture_cmd "${stage}" "nmcli-device" nmcli -f ALL device status
  capture_cmd "${stage}" "nmcli-device-show" nmcli device show "${DEVICE}"
  capture_cmd "${stage}" "nmcli-wifi-list" nmcli -f ALL device wifi list --rescan no
  capture_cmd "${stage}" "resolvectl-status" resolvectl status
  capture_cmd "${stage}" "systemctl-nm" systemctl status NetworkManager --no-pager -l
  capture_cmd "${stage}" "systemctl-supplicant" systemctl status wpa_supplicant --no-pager -l
  capture_cmd "${stage}" "systemctl-resolved" systemctl status systemd-resolved --no-pager -l
  capture_cmd "${stage}" "journal-network" journalctl -u NetworkManager -u wpa_supplicant -u systemd-resolved --since "${START_TIME}" --no-pager -o short-precise
  capture_cmd "${stage}" "dmesg" dmesg --ctime
}

on_exit() {
  local status=$?
  trap - EXIT
  collect_diagnostics "exit-${status}"
  echo "Diagnostics saved in: ${LOG_DIR}"
  exit "${status}"
}

connected_ssid() {
  nmcli -t -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null |
    awk -F: '$1 == "yes" { sub(/^yes:/, ""); print; exit }'
}

device_ipv4() {
  ip -o -4 addr show dev "${DEVICE}" scope global 2>/dev/null | awk 'NR == 1 { print $4 }'
}

wait_for_connection() {
  local wanted="$1"
  local deadline=$((SECONDS + CONNECT_WAIT_SECONDS))
  local current=""
  local ipv4=""

  while (( SECONDS < deadline )); do
    current="$(connected_ssid || true)"
    ipv4="$(device_ipv4 || true)"

    if [[ "${current}" == "${wanted}" && -n "${ipv4}" ]]; then
      echo "${DEVICE} is connected to ${wanted} with IPv4 ${ipv4}."
      return 0
    fi

    echo "Waiting for ${wanted}: current_ssid=${current:-none} ipv4=${ipv4:-none}"
    sleep 2
  done

  return 1
}

ensure_nm_running() {
  systemctl reset-failed NetworkManager >/dev/null 2>&1 || true
  systemctl start NetworkManager >/dev/null 2>&1 || true
  nmcli radio wifi on >/dev/null 2>&1 || true
  nmcli device set "${DEVICE}" managed yes >/dev/null 2>&1 || true
}

connection_exists() {
  nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$1"
}

disable_wework_profile() {
  echo "Disabling ${CONNECTION} so it cannot steal autoconnect during fallback..."
  if connection_exists "${CONNECTION}"; then
    nmcli connection modify "${CONNECTION}" connection.autoconnect no >/dev/null 2>&1 || true
    nmcli connection down "${CONNECTION}" >/dev/null 2>&1 || true
    nmcli connection delete "${CONNECTION}" >/dev/null 2>&1 || true
    echo "Removed the ${CONNECTION} connection profile."
  fi
}

enable_fallback_autoconnect() {
  nmcli connection modify "${FALLBACK_SSID}" connection.autoconnect yes >/dev/null 2>&1 || true
}

connect_profile() {
  local name="$1"
  local rc=0

  ensure_nm_running

  echo "Scanning for Wi-Fi networks..."
  timeout 20s nmcli device wifi rescan >/dev/null 2>&1 || true
  sleep 3

  echo "Bringing up ${name} on ${DEVICE}..."
  timeout 50s nmcli connection up "${name}" ifname "${DEVICE}" || rc=$?
  if (( rc != 0 )); then
    echo "nmcli connection up ${name} exited with status ${rc}; waiting anyway in case association continues."
  fi

  wait_for_connection "$(profile_ssid "${name}")"
}

profile_ssid() {
  nmcli -t -g 802-11-wireless.ssid connection show "$1" 2>/dev/null || echo "$1"
}

restore_fallback() {
  echo "Restoring hard-coded fallback Wi-Fi: ${FALLBACK_SSID}"
  disable_wework_profile
  ensure_nm_running
  enable_fallback_autoconnect

  connection_exists "${FALLBACK_SSID}" ||
    die "no saved NetworkManager connection named ${FALLBACK_SSID}"

  if connect_profile "${FALLBACK_SSID}"; then
    echo "Restored ${FALLBACK_SSID}."
    return 0
  fi

  collect_diagnostics "fallback-normal-failed"

  echo "Normal fallback failed; trying a harder reset." >&2
  nmcli device disconnect "${DEVICE}" >/dev/null 2>&1 || true
  nmcli radio wifi off >/dev/null 2>&1 || true
  sleep 3
  nmcli radio wifi on >/dev/null 2>&1 || true
  systemctl restart NetworkManager || true
  sleep 5
  enable_fallback_autoconnect

  if connect_profile "${FALLBACK_SSID}"; then
    echo "Restored ${FALLBACK_SSID} after hard reset."
    return 0
  fi

  echo "Fallback ${FALLBACK_SSID} did not come back cleanly." >&2
  return 1
}

write_wework_profile() {
  echo "Writing NetworkManager profile for ${SSID}..."

  # Recreate from scratch so a stale profile cannot keep failing settings.
  nmcli connection delete "${CONNECTION}" >/dev/null 2>&1 || true

  nmcli connection add \
    type wifi \
    con-name "${CONNECTION}" \
    ifname "${DEVICE}" \
    ssid "${SSID}" \
    -- \
    connection.autoconnect no \
    wifi-sec.key-mgmt wpa-eap \
    802-1x.eap peap \
    802-1x.identity "${IDENTITY}" \
    802-1x.phase2-auth mschapv2 \
    802-1x.password "${PASSWORD}" >/dev/null

  if [[ "${SKIP_CERT_VALIDATION}" == "1" ]]; then
    # No CA cert: NetworkManager needs this to stop refusing the profile.
    nmcli connection modify "${CONNECTION}" \
      802-1x.ca-cert "" \
      802-1x.domain-suffix-match "" \
      802-1x.system-ca-certs no
  else
    nmcli connection modify "${CONNECTION}" \
      802-1x.ca-cert "${CA_CERT}" \
      802-1x.domain-suffix-match "${DOMAIN_MASK}"
  fi

  # Store the password in the system keystore so a root/headless run works
  # without a Secret Agent prompting for it.
  nmcli connection modify "${CONNECTION}" 802-1x.password-flags 0
}

require_common_commands() {
  need_cmd awk
  need_cmd date
  need_cmd dmesg
  need_cmd grep
  need_cmd install
  need_cmd ip
  need_cmd iw
  need_cmd journalctl
  need_cmd nmcli
  need_cmd resolvectl
  need_cmd rfkill
  need_cmd systemctl
  need_cmd tee
  need_cmd timeout
}

case "${MODE}" in
  connect | --connect)
    MODE="connect"
    ;;
  --recover-knight | recover-knight)
    MODE="recover-knight"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "unknown mode: ${MODE}"
    ;;
esac

[[ "${EUID}" -eq 0 ]] || die "run this as root, e.g. sudo ./connect_wework_wifi.sh"

setup_logging
trap on_exit EXIT
require_common_commands

[[ -n "${DEVICE}" ]] || die "no wireless device found"
[[ -e "/sys/class/net/${DEVICE}" ]] || die "wireless device not found: ${DEVICE}"
systemctl is-active --quiet NetworkManager ||
  die "NetworkManager is not running; Omarchy Quattro manages Wi-Fi with it"
if [[ "${SKIP_CERT_VALIDATION}" != "1" ]]; then
  [[ -r "${CA_CERT}" ]] || die "CA certificate bundle not found: ${CA_CERT}"
fi

echo "Mode: ${MODE}"
echo "Device: ${DEVICE}"
echo "Target Wi-Fi: ${SSID}"
echo "Fallback Wi-Fi: ${FALLBACK_SSID}"
echo "Current Wi-Fi: $(connected_ssid || true)"
echo "Certificate validation skipped: ${SKIP_CERT_VALIDATION}"

collect_diagnostics "before"

if [[ "${MODE}" == "recover-knight" ]]; then
  if restore_fallback; then
    collect_diagnostics "fallback-restored"
    echo "Recovered ${FALLBACK_SSID}."
    exit 0
  fi

  collect_diagnostics "fallback-failed"
  die "failed to restore ${FALLBACK_SSID}"
fi

[[ -n "${PASSWORD}" ]] || die "password cannot be empty"

write_wework_profile
collect_diagnostics "after-profile-write"

if [[ "${SKIP_CERT_VALIDATION}" == "1" ]]; then
  echo "Warning: trying ${SSID} without CA/domain certificate validation."
fi

if connect_profile "${CONNECTION}"; then
  collect_diagnostics "wework-connected"
  echo "Connected to ${SSID}."
  exit 0
fi

echo "Could not confirm a working ${SSID} connection." >&2
collect_diagnostics "wework-failed"

if restore_fallback; then
  collect_diagnostics "fallback-restored"
  die "restored ${FALLBACK_SSID}; ${SSID} did not connect"
fi

collect_diagnostics "fallback-failed"
die "failed to connect ${SSID}; failed to restore ${FALLBACK_SSID}"
