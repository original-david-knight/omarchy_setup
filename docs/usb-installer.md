# USB installer

`./iso/build.sh` builds a bootable x86_64 Omarchy installer that opens this
repository's setup wizard after the first desktop login. Omarchy's normal
installer collects disk, encryption, keyboard, and account choices. After the
installed system boots, the launcher downloads this public repository from
GitHub `main` and starts `setup.sh` in a terminal as the new user.

GitHub authentication and the private setup checkout happen inside the wizard,
after the Omarchy update and all public installation, configuration, and checks.
The image bundles the public bootstrap, terminal launcher, desktop entry,
post-boot hook, wallpaper installer, and all 12 custom backgrounds. It contains
no personal setup checkout, private application sources, credentials, browser
sessions, or account data. The installer module that copies these files is also public.

Backgrounds retain their theme folders under `~/.config/omarchy/backgrounds`.
The initial selection is the starry-sky image with two children,
`tokyo-night/Gemini_Generated_Image_3252l33252l33252.png`. The installer copies
the images and stages a portable background link for both direct and deferred
user creation. First login reapplies this selection after Omarchy's finalizer,
before waiting for network access. A local completion marker preserves later
wallpaper choices when setup runs again. Existing conflicting files are backed
up, and additional user images are retained.

## Build

```sh
./iso/build.sh
```

The builder requires Linux x86_64, Git, Python 3, Docker, and about 40 GB of
free disk space. It uses Docker through sudo when the user cannot access the
Docker socket. The privileged build container receives only the disposable
upstream build tree, output directory, and dedicated package caches. It does
not mount the user's home or write a physical disk.

Build inputs:

- ISO installer source: `omacom/omarchy-iso` commit
  `2673c613d9a71e23920e43fbb951238145e0f1e8` and its pinned Archiso submodule.
- Omarchy and Arch packages: the upstream stable package mirror at build time.
- Setup scripts: GitHub `main` at first login, refreshed again on retries.
- Backgrounds: this checkout's `backgrounds/manifest.json` and the image files
  it lists, verified by SHA-256 before building.

The installer source is pinned; the package mirror and setup repository remain
rolling. This is not a fully reproducible package snapshot. The output includes
a SHA-256 checksum and build information recording the installer commit,
container image ID, and bundled script hashes.

Output goes into `dist/`, which Git ignores. Build trees and package caches
stay under `~/.cache/omarchy-setup-iso` so later builds can reuse downloads.
Override them with absolute paths in `OMARCHY_ISO_OUTPUT_DIR` and
`OMARCHY_ISO_CACHE_DIR`. Existing output images are not overwritten.

To refresh the public handoff and bundled backgrounds in an existing personal-setup ISO without
downloading packages again:

```sh
./iso/refresh.sh dist/omarchy-setup-2026.09.07-r2-x86_64.iso \
  dist/omarchy-setup-2026.09.08-x86_64.iso
```

This requires sudo, xorriso, and squashfs-tools. It retains the base image's
package versions and BIOS/UEFI boot entries, replaces the public handoff and backgrounds,
and regenerates the filesystem checksum and ISO checksum. Its temporary tree
is removed on exit. Public wizard changes must still be published to GitHub
for the launcher to download them; the ISO does not contain a setup checkout.

## First login and recovery

The installer adds `90-personal-setup` to the user's Omarchy `post-boot.d`
hooks and to `/etc/skel` for deferred-owner installations. It installs the
launcher as `/usr/local/bin/omarchy-personal-setup` and the bootstrap under
`/usr/local/share/omarchy-setup`.

The launcher waits for Omarchy's initial desktop finalizer, then opens the
setup flow. Connect to the internet using Omarchy's network menu if needed.
The bootstrap waits until it can reach the public repository, checking again
every five seconds (each network probe has a 15-second timeout). Keep the
terminal open while you connect Wi-Fi; setup continues automatically. A dropped
clone or fetch retries after reconnection. Repeated Git errors with working
connectivity still report failure, preserving any existing checkout.

Press Ctrl+C to pause. Run `omarchy-personal-setup`, choose **Finish Omarchy
Setup** from the application launcher, or log in again to resume. The exact
installed bootstrap is `/usr/local/share/omarchy-setup/bootstrap.sh`; after its
first successful download, the wizard is `~/omarchy_setup/setup.sh`. Older USB
installations can use the same restart command once Wi-Fi is connected.
A bootstrap or bundled-background change requires rebuilding the ISO to update
the offline payload; wizard changes and backgrounds installed through the public
setup are picked up from GitHub on the next launch.

Only a successful wizard exit creates
`~/.local/state/omarchy-setup/iso/complete` (under `XDG_STATE_HOME` when set).
Failures, interruptions, and deferred account checks leave setup pending.
Completed wizard steps retain their usual checkpoints. A lock prevents two
setup launchers from running the wizard together. Once complete, the boot hook
does nothing; run `~/omarchy_setup/setup.sh` directly for later setup changes.

## Verification

```sh
python3 -m unittest discover -s tests -p 'test_bootstrap.py' -v
python3 -m unittest discover -s tests -p 'test_iso_handoff.py' -v
```

The tests use disposable Git repositories and installation targets. They check
GitHub refresh behavior, user ownership, deferred-owner hook staging, terminal
launch, retry behavior, completion markers, and concurrent launch suppression.

Before writing the ISO to a USB, verify its checksum from the output directory:

```sh
sha256sum -c omarchy-setup-*.iso.sha256
```

Run VM acceptance with:

```sh
./iso/smoke-test.sh dist/omarchy-setup-YYYY.MM.DD-x86_64.iso
```

This requires KVM, QEMU, OVMF firmware, socat, ImageMagick, Tesseract with English
data, and mtools. On Omarchy, install the test dependencies with:

```sh
omarchy pkg add qemu-system-x86 qemu-img qemu-hw-display-virtio-gpu \
  qemu-hw-display-virtio-vga edk2-ovmf socat imagemagick \
  tesseract tesseract-data-eng mtools
```

It reuses the pinned upstream test harness from the build cache.
The test first checks the normal interactive installer, then installs onto a
disposable virtual disk using a separate test configuration drive, reboots,
logs in, and checks that the real setup wizard opens with a current GitHub
checkout. Test accounts and SSH keys stay in disposable VM artifacts under the
build cache; they are never added to the deliverable ISO. Screenshots and logs
are saved under the cached upstream checkout's `test-runs/` directory.
Private application installation and account sign-ins require the owner's
authentication afterward.
