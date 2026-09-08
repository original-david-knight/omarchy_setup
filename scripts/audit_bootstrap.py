#!/usr/bin/env python3
"""Offline bootstrap probes. All writes use disposable directories.

Run with Python 3 on Omarchy; requires bash, git, jq and GNU Stow. Package
installs, authentication and desktop activation are replaced with test doubles.
FAIL means the setup does not meet that expectation; this is an audit command,
not a real clean-install acceptance test. No credentials are read.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


PUBLIC = Path(__file__).resolve().parents[1]
FAILURES = 0


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/bash\n" + text + "\n")
    path.chmod(0o755)


def environment(home, commands):
    home.mkdir(parents=True, exist_ok=True)
    return {
        "HOME": str(home), "USER": "audit", "PATH": f"{commands}:/usr/bin:/bin",
        "LANG": "C.UTF-8", "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_CACHE_HOME": str(home / ".cache"), "OMARCHY_SETUP_ACTIVATE": "0",
    }


def run(args, cwd, env):
    return subprocess.run(args, cwd=cwd, env=env, text=True,
                          capture_output=True, timeout=45)


def report(label, success, evidence):
    global FAILURES
    FAILURES += not success
    print(f"{'PASS' if success else 'FAIL'} {label}: {evidence}")


def installer_fixture(root):
    root.mkdir()
    shutil.copy2(PUBLIC / "install_all.sh", root / "install_all.sh")
    (root / "setup").mkdir()
    shutil.copy2(PUBLIC / "setup/steps.json", root / "setup/steps.json")
    for step in json.loads((root / "setup/steps.json").read_text())["install"]:
        executable(root / step["script"], ":")


def public_probes(root):
    commands = root / "commands"
    commands.mkdir()
    env = environment(root / "home", commands)

    fixture = root / "failed-package"
    installer_fixture(fixture)
    shutil.copy2(PUBLIC / "install_chrome.sh", fixture / "install_chrome.sh")
    executable(commands / "yay", "exit 42")
    result = run(["/bin/bash", "./install_all.sh"], fixture, env)
    report("public installer propagates a package failure", result.returncode != 0,
           f"package exit=42; installer exit={result.returncode}")

    fixture = root / "missing-code"
    installer_fixture(fixture)
    shutil.copy2(PUBLIC / "install_vscode_extensions.sh", fixture / "install_vscode_extensions.sh")
    executable(fixture / "install_discord.sh", 'touch "$HOME/reached-last-step"')
    executable(commands / "code", "exit 127")
    (fixture / "vscode").mkdir()
    (fixture / "vscode/extensions.txt").write_text("publisher.extension\n")
    result = run(["/bin/bash", "./install_all.sh"], fixture, env)
    reached = (root / "home/reached-last-step").exists()
    report("missing Code is reported after later installs run", result.returncode == 127 and reached,
           f"installer exit={result.returncode}; last step reached={reached}")

    fixture = root / "ssh"
    fixture.mkdir()
    env = environment(root / "ssh-home", commands)
    # Use the actual key generator in a home without .ssh. No agents are started.
    executable(commands / "ssh-agent", ":")
    executable(commands / "ssh-add", 'test -f "$1"')
    result = run(["/bin/bash", str(PUBLIC / "setup_ssh.sh")], fixture, env)
    report("GitHub key is generated in an empty home", (root / "ssh-home/.ssh/id_github").is_file(),
           f"script exit={result.returncode}; .ssh exists={(root / 'ssh-home/.ssh').exists()}")

    fixture = root / "dotnet"
    fixture.mkdir()
    env = environment(root / "dotnet-home", commands)
    executable(commands / "yay", "exit 0")
    executable(commands / "curl", r'''while (($#)); do
  if [[ $1 == -o ]]; then destination=$2; shift 2; else shift; fi
done
cat > "$destination" <<'INSTALLER'
#!/bin/bash
set -eu
while (($#)); do
  case $1 in
    --install-dir) destination=$2; shift 2 ;;
    --version) version=$2; shift 2 ;;
    --no-path) shift ;;
    *) exit 9 ;;
  esac
done
[[ $destination == "$HOME/.dotnet" ]]
mkdir -p "$destination"
printf '#!/bin/bash\necho "%s [%s/sdk]"\n' "$version" "$destination" > "$destination/dotnet"
chmod +x "$destination/dotnet"
INSTALLER
''')
    result = run(["/bin/bash", str(PUBLIC / "install_dotnet.sh")], fixture, env)
    report(".NET installer works before ~/bin is stowed", result.returncode == 0,
           f"script exit={result.returncode}; fresh home has no bin directory or installer on PATH")


def stow_probes(root):
    repo = root / "public"
    # Generated installer images are unrelated to Stow and can fill /tmp when
    # the fixture is copied a second time for the folded-directory test.
    shutil.copytree(PUBLIC, repo, ignore=shutil.ignore_patterns(".git", "__pycache__", "dist", "iso-test-results"))
    commands = root / "stow-commands"
    commands.mkdir()
    # Test actual Stow behavior while excluding desktop activation and package
    # availability, which are audited independently.
    for name in ("omarchy", "xdg-mime", "yazi", "xdg-desktop-portal-termfilechooser"):
        executable(commands / name, ":")
    target = root / "stow-target"
    env = environment(root / "stow-caller-home", commands)
    env["OMARCHY_SETUP_TARGET"] = str(target)
    conflict = target / ".config/ghostty/config"
    conflict.parent.mkdir(parents=True)
    conflict.write_text("original-config-for-audit\n")
    runtime = target / "bin/unmanaged-runtime-file"
    runtime.parent.mkdir()
    runtime.write_text("preserve-me\n")
    for profile in ("desktop", "desktop", "laptop", "desktop"):
        env["OMARCHY_SETUP_PROFILE"] = profile
        result = run(["/bin/bash", str(repo / "stow_all.sh")], repo, env)
        linked = conflict.is_symlink() and conflict.resolve().is_relative_to(repo)
        touchpad = (target / "bin/auto-touchpad-toggle").exists()
        report(f"Stow {profile} deployment/profile switch", result.returncode == 0 and linked and touchpad == (profile == "laptop"),
               f"exit={result.returncode}; Ghostty linked={linked}; touchpad helper={touchpad}")
    backups = list((target / ".local/state/omarchy-setup/backups").glob("*/.config/ghostty/config"))
    report("Stow preserves conflicts and unrelated files",
           any(p.read_text() == "original-config-for-audit\n" for p in backups) and runtime.read_text() == "preserve-me\n",
           f"original config backups={len(backups)}; runtime file preserved={runtime.exists()}")

    # The private step adds a github-fluxon host, then its companion phase runs
    # the public stow pass again. Represent that private output without keys.
    ssh_config = target / ".ssh/config"
    ssh_config.unlink()
    ssh_config.write_text("Host github-fluxon\n  HostName github.com\n  IdentityFile ~/.ssh/id_github_fluxon\n")
    result = run(["/bin/bash", str(repo / "stow_all.sh")], repo, env)
    report("public re-stow retains private SSH host",
           result.returncode == 0 and "Host github-fluxon\n" in ssh_config.read_text(),
           f"exit={result.returncode}; github-fluxon present={'Host github-fluxon' in ssh_config.read_text()}")

    # Older plugin deployment used absolute links into this same checkout.
    # Shell -ef considers them identical, but Stow does not own absolute links
    # or regular hardlinks, even when they reference the right source inode.
    relative_plugin = Path(".config/omarchy/plugins/david.podcasts")
    source_plugin = repo / "omarchy" / relative_plugin
    plugin = target / relative_plugin
    absolute_names = ("Artwork.qml", "ListeningButton.qml", "ListeningView.qml", "mynoise",
                      "soundscapes.json", "spotify-library", "spotify-window")
    for name in absolute_names:
        (plugin / name).unlink()
        (plugin / name).symlink_to(source_plugin / name)
    hardlink = plugin / "Panel.qml"
    hardlink.unlink()
    os.link(source_plugin / hardlink.name, hardlink)
    migrated_names = (*absolute_names, hardlink.name)
    source_contents = {name: (source_plugin / name).read_bytes() for name in migrated_names}
    unrelated = plugin / "local-runtime-state"
    unrelated.write_text("preserve local state\n")

    result = run(["/bin/bash", str(repo / "stow_all.sh"), "--bar-only"], repo, env)
    migrated = all((plugin / name).is_symlink() and not (plugin / name).readlink().is_absolute()
                   and (plugin / name).resolve() == source_plugin / name for name in migrated_names)
    report("Stow migrates absolute links and hardlinks to its relative links",
           result.returncode == 0 and migrated, f"exit={result.returncode}; migrated={migrated}")
    backup_base = target / ".local/state/omarchy-setup/backups"
    links_saved = all(any(p.is_symlink() and p.readlink() == source_plugin / name
                         for p in backup_base.glob(f"*/{relative_plugin}/{name}")) for name in absolute_names)
    file_saved = any(not p.is_symlink() and p.read_bytes() == source_contents[hardlink.name]
                     for p in backup_base.glob(f"*/{relative_plugin}/{hardlink.name}"))
    source_unchanged = all((source_plugin / name).read_bytes() == content for name, content in source_contents.items())
    report("legacy link migration preserves backups, source and unrelated files",
           links_saved and file_saved and source_unchanged and unrelated.read_text() == "preserve local state\n",
           f"absolute links backed up={links_saved}; hardlink backed up={file_saved}; source unchanged={source_unchanged}")
    backup_folders = set(backup_base.iterdir())
    result = run(["/bin/bash", str(repo / "stow_all.sh"), "--bar-only"], repo, env)
    report("migrated Stow links rerun without new conflict backups",
           result.returncode == 0 and set(backup_base.iterdir()) == backup_folders,
           f"exit={result.returncode}; new backup folders={len(set(backup_base.iterdir()) - backup_folders)}")

    # Reproduce the common layout with the checkout inside the target home.
    # A folded directory link must never cause the source files to be backed up.
    folded_home = root / "folded-home"
    nested_repo = folded_home / "omarchy_setup"
    shutil.copytree(repo, nested_repo)
    folded = folded_home / relative_plugin
    folded.parent.mkdir(parents=True)
    nested_source = nested_repo / "omarchy" / relative_plugin
    folded.symlink_to(os.path.relpath(nested_source, folded.parent), target_is_directory=True)
    before = {p.name: p.read_bytes() for p in nested_source.iterdir() if p.is_file()}
    env["OMARCHY_SETUP_TARGET"] = str(folded_home)
    result = run(["/bin/bash", str(nested_repo / "stow_all.sh"), "--bar-only"], nested_repo, env)
    source_unchanged = all((nested_source / name).is_file() and (nested_source / name).read_bytes() == content
                           for name, content in before.items())
    report("folded directory links retain repository source files",
           result.returncode == 0 and source_unchanged and (folded / "manifest.json").is_file(),
           f"exit={result.returncode}; source unchanged={source_unchanged}")


def private_probes(root, private):
    if not (private / "scripts/provision.py").is_file():
        print("SKIP private probes: private checkout unavailable")
        return
    # Only copy provisioning code and manifests, never private credentials.
    fixture = root / "private"
    fixture.mkdir()
    shutil.copytree(private / "scripts", fixture / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
    for name in ("sources.lock.json", "desktop.json", "setup_everything_app.sh"):
        shutil.copy2(private / name, fixture / name)
    commands = root / "private-commands"
    commands.mkdir()
    env = environment(root / "private-home", commands)
    config = root / "private-home/.config/lifedash"
    config.mkdir(parents=True)
    (config / "deploy.env").write_text("LIFEDASH_PROD_URL=https://example.invalid\nLIFEDASH_AUTH_SECRET=audit-placeholder\n")
    import json
    import importlib.util
    lock = json.loads((fixture / "sources.lock.json").read_text())
    app = root / "builds" / ("everything-" + lock["everything-app"]["revision"]) / "everything-app"
    executable(app / "scripts/install-desktop.sh", 'echo "simulated installer failure" >&2; exit 42')
    public = root / "public-fixture"
    executable(public / "stow_all.sh", '[[ $1 == --bar-only ]] || exit 7; touch "$HOME/bar-restored"')
    env.update(OMARCHY_SETUP_DIR=str(public), OMARCHY_PRIVATE_BUILD_ROOT=str(root / "builds"))
    result = run(["/bin/bash", "./setup_everything_app.sh", "--only", "desktop"], fixture, env)
    report("Everything failure propagates and restores only the public bar", result.returncode != 0 and (root / "private-home/bar-restored").exists(), f"child exit=42; setup exit={result.returncode}; bar restored={(root / 'private-home/bar-restored').exists()}")
    spec = importlib.util.spec_from_file_location("provision_fixture", fixture / "scripts/provision.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    home = root / "seed-home"
    home.mkdir()
    source = fixture / "seed.txt"
    source.write_text("fresh @@HOME@@")
    target = home / ".config/test.env"
    target.parent.mkdir()
    target.write_text("newer local credential")
    module.seed(source, target, home=home, template=True)
    report("private rerun preserves newer credentials", target.read_text() == "newer local credential", "existing file retained")
    module.seed(source, target, home=home, template=True, refresh=True)
    backups = list((home / ".local/state/omarchy-setup-private/backups").glob("*/test.env"))
    report("explicit private refresh renders home and backs up credentials", target.read_text() == "fresh " + str(home) and any(p.read_text() == "newer local credential" for p in backups), f"backups={len(backups)}")
    outside = root / "outside"
    outside.mkdir()
    (home / "escape").symlink_to(outside, target_is_directory=True)
    try:
        module.seed(source, home / "escape/secret", home=home)
        blocked = False
    except ValueError:
        blocked = True
    report("private seed refuses directory symlink escape", blocked and not (outside / "secret").exists(), f"blocked={blocked}")
    source.write_text('PLAIN=value\nQUOTED="two words"\nLITERAL="$(touch /tmp/should-not-exist)"\n')
    values = module.read_env(source)
    report("env parsing does not execute shell substitutions", values["LITERAL"] == "$(touch /tmp/should-not-exist)" and values["QUOTED"] == "two words", "literal data retained")



    # A clean public->private run seeds GoWild's env before its dev checkout.
    # Exercise actual local Git clones and a second run with those files present.
    def git_source(name, files):
        source = root / name
        source.mkdir()
        for path, value in files.items():
            (source / path).write_text(value)
        for command in (["git", "init", "-q"], ["git", "add", "."], ["git", "-c", "user.name=Setup Test", "-c", "user.email=setup@example.invalid", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture"]):
            subprocess.run(command, cwd=source, env=env, check=True, capture_output=True)
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, env=env, text=True).strip()
        return {"url": str(source), "revision": revision}
    gowild = git_source("gowild-origin", {"README.md": "source fixture\n"})
    app_spec = git_source("everything-origin", {"gowild.lock": gowild["revision"] + "\n"})
    lock.update({"golang2": gowild, "everything-app": app_spec})
    (fixture / "sources.lock.json").write_text(json.dumps(lock))
    settings = json.loads((fixture / "desktop.json").read_text())
    settings["tracker_repos"] = {name: gowild["url"] for name in ["taxes", "walking_game"]}
    (fixture / "desktop.json").write_text(json.dumps(settings))
    workspace = root / "development"
    (workspace / "golang2").mkdir(parents=True)
    (workspace / "golang2/.env").write_text("EXAMPLE=retained-placeholder\n")
    env["WORKSPACE_DIR"] = str(workspace)
    for index, label in enumerate(("seeded workspace is completed into a Git checkout", "private source setup reruns without resetting work")):
        result = run(["/bin/bash", "./setup_everything_app.sh", "--only", "repos"], fixture, env)
        good = result.returncode == 0 and (workspace / "golang2/.git").is_dir() and (workspace / "golang2/README.md").exists() and (workspace / "golang2/.env").read_text() == "EXAMPLE=retained-placeholder\n"
        if index == 1:
            good = good and (workspace / "golang2/README.md").read_text() == "uncommitted development change\n"
        report(label, good, f"setup exit={result.returncode}; private seed preserved")
        if index == 0:
            (workspace / "golang2/README.md").write_text("uncommitted development change\n")
    report("developer edits survive source reprovisioning", (workspace / "golang2/README.md").read_text() == "uncommitted development change\n", "development checkout preserved")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-repo", type=Path, default=Path.home() / "workspace/omarchy-setup-private")
    args = parser.parse_args()
    for command in ("bash", "git", "jq", "stow", "ssh-keygen"):
        if not shutil.which(command):
            parser.error(f"required command is missing: {command}")
    with tempfile.TemporaryDirectory(prefix="omarchy-bootstrap-probes-") as folder:
        root = Path(folder)
        public_probes(root)
        stow_probes(root)
        private_probes(root, args.private_repo)
    print(f"\n{FAILURES} unmet expectations; no live configuration or services changed.")
    return int(FAILURES > 0)


if __name__ == "__main__":
    raise SystemExit(main())
