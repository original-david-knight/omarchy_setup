"""Read-only readiness checks. Exit 0=ready, 1=broken, 3=login/session needed."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


class Checks:
    def __init__(self, json_output=False):
        self.failed = 0
        self.pending = 0
        self.json_output = json_output
        self.results = []

    def check(self, label, good, remedy="", *, pending=False):
        if not good:
            if pending:
                self.pending += 1
            else:
                self.failed += 1
        self.results.append({"label": label, "status": "pass" if good else "pending" if pending else "fail", "remedy": remedy if not good else ""})
        if not self.json_output:
            print(("PASS " if good else "PENDING " if pending else "FAIL ") + label + ((": " + remedy) if not good and remedy else ""))
        return good

    def command(self, label, argv, remedy="", *, pending=False):
        try:
            result = subprocess.run(list(map(str, argv)), capture_output=True, timeout=40)
            good = result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            good = False
        return self.check(label, good, remedy, pending=pending)

    def status(self):
        if self.json_output:
            print(json.dumps({"version": 1, "failed": self.failed, "pending": self.pending, "checks": self.results}))
        else:
            print(f"{self.failed} failed; {self.pending} awaiting login/session.")
        return 1 if self.failed else 3 if self.pending else 0


def verify(checks, home):
    checks.command("supported Omarchy baseline", ["bash", ROOT / "check_baseline.sh"], "complete an Omarchy 4.x install")
    packages = []
    for filename in ("core.txt", "aur.txt"):
        packages += [line.split("#")[0].strip() for line in (ROOT / "packages" / filename).read_text().splitlines() if line.split("#")[0].strip()]
    checks.command("supplemental packages", ["pacman", "-Q", *packages], "rerun ./install_core.sh")
    commands = "ghostty google-chrome-stable brave code cursor tmux zellij herdr hunk claude codex gh asteroids dotnet yazi mpv socat spotify voxtype gcalcli vopono tailscale btm wl-copy wtype".split()
    missing = [command for command in commands if not shutil.which(command)]
    checks.check("core commands", not missing, "missing: " + ", ".join(missing))
    checks.command(".NET SDK", [home / ".dotnet/dotnet", "--list-sdks"])
    for module in ("gi", "PySide6.QtWebEngineWidgets"):
        checks.command("Python " + module, ["/usr/bin/python3", "-c", "import " + module])
    layout = home / ".config/omarchy/shell.json"
    try:
        config = json.loads(layout.read_text())
        widgets = sum((config["bar"]["layout"].get(side, []) for side in ("left", "center", "right")), [])
        ids = [item["id"] for item in widgets if "id" in item]
        checks.check("tasks bar widget", "david.tasks" in ids and "david.everything" not in ids)
        for plugin in sorted(set(i for i in ids if i.startswith("david."))):
            checks.command(plugin + " plugin", ["omarchy", "plugin", "validate", ROOT / "omarchy/.config/omarchy/plugins" / plugin])
    except (OSError, ValueError, KeyError):
        checks.check("bar layout", False, "run ./stow_all.sh")
    for command, expected, label in [(["xdg-mime", "query", "default", "x-scheme-handler/https"], "google-chrome.desktop", "default browser"), (["xdg-mime", "query", "default", "inode/directory"], "yazi.desktop", "default file manager")]:
        result = subprocess.run(command, text=True, capture_output=True)
        checks.check(label, result.returncode == 0 and result.stdout.strip() == expected, "run ./stow_all.sh")
    for unit in ("tailscaled.service", "postgresql.service", "bluetooth.service", "ensure-razer-basilisk-mouse.service", "boot-forensics.service"):
        checks.command(unit + " enabled", ["systemctl", "is-enabled", "--quiet", unit])
    graphical = checks.command("graphical session", ["systemctl", "--user", "is-active", "--quiet", "graphical-session.target"], "log in graphically and run ./activate.sh", pending=True)
    for unit in ("primary-selection-sync.service", "voxtype.service", "omarchy-tailscale-receive.service"):
        checks.command(unit + " enabled", ["systemctl", "--user", "is-enabled", "--quiet", unit])
        if graphical:
            checks.command(unit + " active", ["systemctl", "--user", "is-active", "--quiet", unit])
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        result = subprocess.run(["hyprctl", "configerrors"], text=True, capture_output=True)
        checks.check("Hyprland configuration", result.returncode == 0 and not result.stdout.strip())
    checks.check("Voxtype model", (home / ".local/share/voxtype/models/ggml-base.en.bin").is_file(), "run ./install_voice.sh")
    checks.check("Plymouth art applied", (home / ".local/state/omarchy-setup/plymouth.sha256").is_file(), "run ./activate.sh")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="emit a machine-readable readiness report")
    args = parser.parse_args()
    checks = Checks(json_output=args.json)
    verify(checks, Path.home())
    return checks.status()


if __name__ == "__main__":
    raise SystemExit(main())
