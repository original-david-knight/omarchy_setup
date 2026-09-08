"""Stage only the public first-login payload in the installed system."""
import os
from pathlib import Path
import shutil


PAYLOAD = Path('/usr/share/omarchy-setup-iso')
HOOK = Path('.config/omarchy/hooks/post-boot.d/90-personal-setup')


def _copy(source, destination, mode=0o755):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    destination.chmod(mode)


def stage_personal_setup(ctx):
    target = ctx.target.resolve()
    if target == Path('/'):
        raise RuntimeError('Personal setup must be staged into an installation target, not the live system')
    _copy(PAYLOAD / 'bootstrap.sh', target / 'usr/local/share/omarchy-setup/bootstrap.sh')
    _copy(PAYLOAD / 'omarchy-personal-setup', target / 'usr/local/bin/omarchy-personal-setup')
    _copy(PAYLOAD / 'omarchy-personal-setup.desktop',
          target / 'usr/local/share/applications/omarchy-personal-setup.desktop', 0o644)
    # Deferred-owner installs and later new users receive the same hook.
    _copy(PAYLOAD / 'post-boot.hook', target / 'etc/skel' / HOOK)
    if ctx.defer_provisioning:
        return
    entries = [line.split(':') for line in (target / 'etc/passwd').read_text().splitlines()]
    entry = next((entry for entry in entries if entry[0] == ctx.username), None)
    if entry is None or len(entry) != 7:
        raise RuntimeError('Cannot find the installed desktop user for the setup handoff')
    uid, gid = int(entry[2]), int(entry[3])
    home = target / entry[5].lstrip('/')
    if not home.resolve().is_relative_to(target) or not home.is_dir():
        raise RuntimeError('The installed user home is outside the installation target or missing')
    hook = home / HOOK
    # Set ownership of newly created directories only; preserve existing config.
    missing = []
    parent = hook.parent
    while not parent.exists():
        missing.append(parent)
        parent = parent.parent
    _copy(PAYLOAD / 'post-boot.hook', hook)
    for path in [*missing, hook]:
        os.chown(path, uid, gid)
