#!/usr/bin/env python3
"""Compare declared desktop setup with this machine without reading credentials."""
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home()
PACKAGES = ("bash", "tmux", "zellij", "herdr", "omarchy", "hypr", "starship",
            "bin", "vscode", "yazi", "desktop", "ghostty_big_screen", "omarchy_desktop")


def main():
    differences = []
    for package in PACKAGES:
        for source in sorted((ROOT / package).rglob("*")):
            if not source.is_file() or source.name.startswith(".") or ".bak" in source.name:
                continue
            relative = source.relative_to(ROOT / package)
            target = HOME / relative
            if not target.is_file():
                differences.append({"path": str(relative), "status": "missing"})
            elif source.read_bytes() != target.read_bytes():
                differences.append({"path": str(relative), "status": "different"})
    profiles = {}
    for profile in ("desktop", "laptop"):
        config = json.loads((ROOT / f"omarchy_{profile}/.config/omarchy/shell.json").read_text())
        layouts = [config["bar"]["layout"], *(s["layout"] for s in config["bar"].get("screenLayouts", []))]
        widgets = config.get("plugins", []) + [{"id": config["bar"].get("id", "")}]
        for layout in layouts:
            for section in ("left", "center", "right"):
                widgets += layout.get(section, [])
        missing = []
        for plugin in sorted({w.get("id", "") for w in widgets}):
            if plugin.startswith("david."):
                source = ROOT / "omarchy/.config/omarchy/plugins" / plugin
            elif plugin == "jankeesvw.meeting-recorder":
                source = Path("/usr/share/omarchy-meeting-recorder/plugin")
            else:
                continue
            if not (source / "manifest.json").is_file():
                missing.append(plugin)
        profiles[profile] = {"missing_plugins": missing}
    published = subprocess.check_output(
        ["git", "ls-remote", "https://github.com/original-david-knight/omarchy_setup.git", "refs/heads/main"],
        text=True, timeout=30).split()[0]
    local = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    print(json.dumps({"profiles": profiles, "desktop_config_differences": differences,
                      "local_commit": local, "published_commit": published}, indent=2))
    return int(any(p["missing_plugins"] for p in profiles.values()))


if __name__ == "__main__":
    raise SystemExit(main())
