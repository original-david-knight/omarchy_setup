#!/usr/bin/env bash
set -euo pipefail

# Refresh the public handoff and backgrounds in an existing personal-setup ISO. Package
# contents and the upstream installer stay at the original image's versions.
if (($# != 2)); then
  echo 'Usage: iso/refresh.sh EXISTING.iso NEW.iso' >&2
  exit 2
fi
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source_iso=$(realpath -- "$1")
output_iso=$(realpath -m -- "$2")
[[ -f $source_iso && ! -e $output_iso ]] || { echo 'Source must exist and output must be new.' >&2; exit 1; }
for command in xorriso unsquashfs mksquashfs sha256sum sha512sum python3 sudo; do
  command -v "$command" >/dev/null || { printf 'Missing command: %s\n' "$command" >&2; exit 1; }
done
python3 "$repo_dir/scripts/install_backgrounds.py" --check
work_dir=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-iso-refresh.XXXXXX")
cleanup() {
  sudo rm -rf -- "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sudo true

xorriso -osirrox on -indev "$source_iso" \
  -extract /arch/x86_64/airootfs.sfs "$work_dir/original.sfs"
sudo unsquashfs -no-progress -processors 4 -d "$work_dir/root" "$work_dir/original.sfs"
payload=$work_dir/root/usr/share/omarchy-setup-iso
[[ -f $payload/bootstrap.sh ]] || { echo 'This is not an Omarchy personal-setup ISO.' >&2; exit 1; }
sudo install -m 0755 "$repo_dir/bootstrap.sh" "$payload/bootstrap.sh"
sudo install -m 0755 "$repo_dir/iso/omarchy-personal-setup" "$payload/omarchy-personal-setup"
sudo install -m 0755 "$repo_dir/iso/post-boot.hook" "$payload/post-boot.hook"
sudo install -m 0644 "$repo_dir/iso/omarchy-personal-setup.desktop" "$payload/omarchy-personal-setup.desktop"
sudo install -m 0644 "$repo_dir/scripts/install_backgrounds.py" "$payload/install_backgrounds.py"
sudo rm -rf -- "$payload/backgrounds"
sudo cp -a -- "$repo_dir/backgrounds" "$payload/backgrounds"
sudo chown -R root:root "$payload/backgrounds"
sudo install -m 0644 "$repo_dir/iso/personal_setup.py" \
  "$work_dir/root/usr/share/omarchy-iso/orchestrator/personal_setup.py"
sudo mksquashfs "$work_dir/root" "$work_dir/airootfs.sfs" \
  -noappend -no-progress -comp zstd -Xcompression-level 15 -b 1M -processors 4 -mem 2G
(cd "$work_dir" && sha512sum airootfs.sfs > airootfs.sha512)

# Replay preserves both the BIOS boot loader and the appended UEFI image.
xorriso -indev "$source_iso" -outdev "$output_iso" -boot_image any replay \
  -map "$work_dir/airootfs.sfs" /arch/x86_64/airootfs.sfs \
  -map "$work_dir/airootfs.sha512" /arch/x86_64/airootfs.sha512 \
  -chmod 0444 /arch/x86_64/airootfs.sfs /arch/x86_64/airootfs.sha512 -- \
  -chown 0 /arch/x86_64/airootfs.sfs /arch/x86_64/airootfs.sha512 -- \
  -chgrp 0 /arch/x86_64/airootfs.sfs /arch/x86_64/airootfs.sha512 --
(cd "$(dirname -- "$output_iso")" && sha256sum "$(basename -- "$output_iso")" > "$(basename -- "$output_iso").sha256")
{
  printf 'Refreshed UTC: %s\n' "$(date -u +%FT%TZ)"
  printf 'Base ISO: %s\n' "$(basename -- "$source_iso")"
  sha256sum "$source_iso"
  printf 'Change: public handoff and custom backgrounds; original package versions retained.\n'
  printf 'SquashFS: zstd level 15, 1 MiB blocks\n'
  printf 'Setup source: public GitHub main at first login\n'
  (cd "$repo_dir" && sha256sum bootstrap.sh iso/omarchy-personal-setup iso/post-boot.hook \
    iso/omarchy-personal-setup.desktop iso/personal_setup.py iso/refresh.sh scripts/install_backgrounds.py backgrounds/manifest.json)
} > "$output_iso.build-info"
printf '\nRefreshed ISO: %s\n' "$output_iso"
