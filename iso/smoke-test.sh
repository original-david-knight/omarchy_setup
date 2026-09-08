#!/usr/bin/env bash
set -euo pipefail
umask 077

cache_dir=${OMARCHY_ISO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-setup-iso}
upstream=$cache_dir/upstream
if [[ $# != 1 || ! -f $1 ]]; then
  echo 'Usage: iso/smoke-test.sh /path/to/omarchy-setup.iso' >&2
  exit 2
fi
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo 'KVM access is required for this test.' >&2; exit 1; }
for command in qemu-system-x86_64 qemu-img socat magick tesseract mkfs.vfat mcopy ssh ssh-keygen; do
  command -v "$command" >/dev/null || { printf 'Missing test command: %s\n' "$command" >&2; exit 1; }
done
available_devices=$(qemu-system-x86_64 -device help)
for device in virtio-gpu-device virtio-vga; do
  [[ $available_devices == *"name \"$device\""* ]] || {
    echo 'Install the QEMU virtio-gpu and virtio-vga display packages before testing.' >&2
    exit 1
  }
done
[[ $(git -C "$upstream" rev-parse HEAD) == 2673c613d9a71e23920e43fbb951238145e0f1e8 ]] || {
  echo 'The pinned upstream test harness is missing. Run iso/build.sh first.' >&2; exit 1;
}
export OMARCHY_INTEGRATION_ISO OMARCHY_INTEGRATION_NO_PREVIEW=true
export OMARCHY_INTEGRATION_SSH_PORT=${OMARCHY_ISO_TEST_SSH_PORT:-2332}
export OMARCHY_INTEGRATION_MEMORY=8192
OMARCHY_INTEGRATION_ISO=$(realpath -- "$1")
SCENARIO=personal-setup
# Reuse the pinned upstream QMP driver, disposable disk layout, and VM cleanup.
source "$upstream/test/integration.d/base-test.sh"
# The upstream cleanup stops QEMU but leaves its Unix socket behind.
trap 'status=$?; cleanup; rm -f -- "$QMP_SOCK"; exit "$status"' EXIT
exec 8>"$BASE_DIR/personal-setup-test.lock"
flock -n 8 || { echo 'This ISO is already being tested.' >&2; exit 1; }

log 'Checking the normal interactive USB boot'
qemu-img create -f qcow2 "$RUN_DIR/interactive.qcow2" 40G >/dev/null
cp "$OVMF_VARS_TEMPLATE" "$RUN_DIR/interactive-vars.fd"
ACTIVE_OVMF="$RUN_DIR/interactive-vars.fd"
start_vm "$RUN_DIR/interactive.qcow2" "$RUN_DIR/interactive-serial.log" \
  -drive "file=$ISO,media=cdrom,if=none,format=raw,id=cdrom0" \
  -device ide-cd,drive=cdrom0,bootindex=2
wait_for_screen 'Press Return' 180
press ret
wait_for_screen 'Keyboard' 180
capture_console 'success-interactive-installer'
stop_vm

install_phase
log 'Booting the installed system and logging into the desktop'
start_vm_from_base
wait_for_ssh 240
sleep 5
for ((attempt = 0; attempt < 24; attempt++)); do
  if ssh_guest 'pgrep -u "$(id -u)" -x Hyprland' >/dev/null; then
    break
  fi
  # The stock SDDM greeter selects the new user and focuses the password field.
  type_text "$GUEST_PASSWORD"
  press ret
  sleep 5
done
check 'Hyprland session started' ssh_guest 'pgrep -u "$(id -u)" -x Hyprland'
wait_for_screen 'Choose your desktop profile' 240
capture_console 'success-personal-setup-wizard'

check 'GitHub checkout exists' ssh_guest 'test -f ~/omarchy_setup/setup.sh && git -C ~/omarchy_setup rev-parse --verify HEAD'
check 'Checkout is current GitHub main' ssh_guest \
  'test "$(git -C ~/omarchy_setup rev-parse HEAD)" = "$(git ls-remote https://github.com/original-david-knight/omarchy_setup.git refs/heads/main | cut -f1)"'
check 'Installed bootstrap matches bundled launcher' ssh_guest \
  "test \"\$(sha256sum /usr/local/share/omarchy-setup/bootstrap.sh | cut -d' ' -f1)\" = '$(sha256sum "$(dirname -- "${BASH_SOURCE[0]}")/../bootstrap.sh" | cut -d' ' -f1)'"
check 'Pending wizard is not marked complete' ssh_guest 'test ! -e ~/.local/state/omarchy-setup/iso/complete'
check 'Private setup waits for authentication' ssh_guest 'test ! -e ~/workspace/omarchy-setup-private'
check 'First-login hook belongs to the desktop user' ssh_guest \
  'test "$(stat -c %u ~/.config/omarchy/hooks/post-boot.d/90-personal-setup)" = "$(id -u)"'
ssh_guest 'omarchy version' >"$RUN_DIR/omarchy-version.txt"
finish
