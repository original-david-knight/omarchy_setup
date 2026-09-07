#!/usr/bin/env python3
"""Own a public SSH include; preserve host configuration and authorized keys."""
import argparse
import datetime
import os
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def write(path, content, target):
    if path.exists() and not path.is_symlink() and path.read_text() == content:
        path.chmod(0o600)
        return
    if path.exists() or path.is_symlink():
        backup = target / ".local/state/omarchy-setup/backups"
        backup.mkdir(parents=True, exist_ok=True)
        folder = Path(tempfile.mkdtemp(prefix=datetime.datetime.now().strftime("%Y%m%d-%H%M%S-"), dir=backup))
        shutil.copy2(path, folder / path.name, follow_symlinks=path.exists())
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".ssh-setup-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(content)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def configure(target, identity=None):
    target = target.resolve()
    if target == Path("/"):
        raise ValueError("unsafe home directory")
    ssh = target / ".ssh"
    ssh.mkdir(parents=True, exist_ok=True)
    if not ssh.resolve().is_relative_to(target):
        raise ValueError("SSH directory resolves outside target home")
    ssh.chmod(0o700)
    includes = ssh / "config.d"
    includes.mkdir(exist_ok=True)
    if not includes.resolve().is_relative_to(target):
        raise ValueError("SSH include directory resolves outside target home")
    includes.chmod(0o700)
    key = str(identity or "~/.ssh/id_github")
    if any(char in key for char in '\n\r"'):
        raise ValueError("invalid identity path")
    public = includes / "10-omarchy-public.conf"
    # Stow should not reset a deliberate custom key selected by setup_ssh.sh.
    if identity is not None or not public.exists():
        write(public, f'Host github.com\n  HostName github.com\n  User git\n  IdentityFile "{key}"\n  IdentitiesOnly yes\n', target)
    config = ssh / "config"
    previous = config.read_text() if config.exists() else ""
    directive = "Include ~/.ssh/config.d/*.conf"
    # Include at top level, before any Host block. Private 00-* hosts win.
    lines = [line for line in previous.splitlines() if line.strip() != directive]
    write(config, directive + "\n\n" + "\n".join(lines).lstrip("\n") + ("\n" if lines else ""), target)
    authorized = ssh / "authorized_keys"
    previous = authorized.read_text() if authorized.exists() else ""
    lines = previous.splitlines()
    source = ROOT / "ssh/.ssh/authorized_keys"
    if source.exists():
        for line in source.read_text().splitlines():
            if line and line not in lines:
                lines.append(line)
    write(authorized, "\n".join(lines) + ("\n" if lines else ""), target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--identity")
    args = parser.parse_args()
    configure(args.target, args.identity)
