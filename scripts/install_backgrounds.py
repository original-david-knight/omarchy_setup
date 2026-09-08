#!/usr/bin/env python3
"""Install the bundled wallpapers and select the default once per new install."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def inventory(source):
    manifest = json.loads((source / "manifest.json").read_text())
    if manifest.get("version") != 1 or not manifest.get("files"):
        raise ValueError("unsupported or empty background manifest")
    files = []
    for entry in manifest["files"]:
        relative = Path(entry["path"])
        path = source / relative
        if (relative.is_absolute() or ".." in relative.parts or len(relative.parts) != 2
                or not path.resolve().is_relative_to(source.resolve())):
            raise ValueError("background path is outside the bundle")
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError("background checksum mismatch: " + str(relative))
        files.append(relative)
    selected = Path(manifest["selected"])
    if selected not in files or len(files) != len(set(files)):
        raise ValueError("invalid background selection or duplicate files")
    return files, selected


def install(source, home, *, record=True):
    """Return changed paths so the ISO can assign the new user's ownership."""
    home = home.resolve()
    if home == Path("/") or not home.is_dir():
        raise ValueError("background target must be an existing user home")
    files, selected = inventory(source)
    changed = []
    backup = None

    def directory(path):
        if not path.resolve().is_relative_to(home):
            raise ValueError("background target escapes the user home")
        missing = []
        while not path.exists():
            missing.append(path)
            path = path.parent
        for path in reversed(missing):
            path.mkdir(mode=0o755)
            changed.append(path)

    def preserve(path):
        nonlocal backup
        if not path.exists() and not path.is_symlink():
            return
        if backup is None:
            base = home / ".local/state/omarchy-setup/backups"
            directory(base)
            backup = Path(tempfile.mkdtemp(prefix="backgrounds-", dir=base))
            changed.append(backup)
        target = backup / path.relative_to(home)
        directory(target.parent)
        shutil.move(path, target)
        changed.append(target)

    backgrounds = home / ".config/omarchy/backgrounds"
    for relative in files:
        target = backgrounds / relative
        directory(target.parent)
        if target.is_file() and not target.is_symlink() and target.read_bytes() == (source / relative).read_bytes():
            continue
        preserve(target)
        shutil.copyfile(source / relative, target)
        target.chmod(0o644)
        changed.append(target)

    marker = home / ".local/state/omarchy-setup/backgrounds.json"
    if not marker.is_file():
        link = home / ".local/state/omarchy/current/background"
        directory(link.parent)
        desired = backgrounds / selected
        if not link.is_symlink() or link.resolve() != desired.resolve():
            preserve(link)
            link.symlink_to(os.path.relpath(desired, link.parent))
            changed.append(link)
        if record:
            directory(marker.parent)
            marker.write_text(json.dumps({"version": 1, "selected": selected.as_posix()}) + "\n")
            marker.chmod(0o644)
            changed.append(marker)
    if backup:
        print("Previous background files preserved in " + str(backup))
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "backgrounds")
    parser.add_argument("--target", type=Path, default=Path(os.environ.get("OMARCHY_SETUP_TARGET", Path.home())))
    parser.add_argument("--check", action="store_true", help="verify bundled image checksums without installing")
    args = parser.parse_args()
    if args.check:
        files, _ = inventory(args.source)
        print(f"Verified {len(files)} bundled backgrounds.")
        return
    install(args.source, args.target)
    print("Custom backgrounds installed; later wallpaper choices are preserved.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit("Background setup: " + str(error))
