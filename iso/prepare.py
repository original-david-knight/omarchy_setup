#!/usr/bin/env python3
"""Add the public setup payload to a disposable upstream ISO build tree."""
import argparse
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]


def prepare(build):
    root = build / 'configs/airootfs'
    orchestrator = root / 'usr/share/omarchy-iso/orchestrator'
    main = orchestrator / 'main.py'
    source = main.read_text()
    anchor = '        ("Validating boot setup",      validate_boot),'
    if source.count(anchor) != 1 or 'stage_personal_setup' in source:
        raise RuntimeError('Upstream phase layout changed or was already patched; use a fresh pinned build tree')
    source = source.replace('from .context import InstallContext\n',
                            'from .context import InstallContext\nfrom .personal_setup import stage_personal_setup\n')
    source = source.replace(anchor, '        ("Staging personal setup",     stage_personal_setup),\n' + anchor)
    main.write_text(source)
    shutil.copy2(ROOT / 'iso/personal_setup.py', orchestrator / 'personal_setup.py')
    payload = root / 'usr/share/omarchy-setup-iso'
    payload.mkdir(parents=True)
    for source in [ROOT / 'bootstrap.sh', *(ROOT / 'iso' / name for name in (
            'omarchy-personal-setup', 'post-boot.hook', 'omarchy-personal-setup.desktop'))]:
        shutil.copy2(source, payload / source.name)
    profile = build / 'configs/profiledef.sh'
    text = profile.read_text().replace('iso_name="omarchy"', 'iso_name="omarchy-setup"')
    text = text.replace('iso_publisher="Omarchy <https://omarchy.org>"',
                        'iso_publisher="Personal Omarchy Setup <https://github.com/original-david-knight/omarchy_setup>"')
    text = text.replace('iso_application="Omarchy Installer"', 'iso_application="Omarchy Installer + Personal Setup"')
    # Bound compression resources so building does not consume the whole desktop.
    text = text.replace("  '-comp' 'zstd'", "  '-processors' '4' '-mem' '2G'\n  '-comp' 'zstd'")
    profile.write_text(text)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    prepare(parser.parse_args().build.resolve())
