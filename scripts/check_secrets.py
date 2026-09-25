#!/usr/bin/env python3
"""Scan publishable files (or the exact index) and optionally all Git history."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def snapshot(destination, staged=False):
    if staged:
        for entry in git("ls-files", "--stage", "-z").split(b"\0"):
            if not entry:
                continue
            meta, name = entry.split(b"\t", 1)
            mode, oid, stage = meta.split()
            if stage != b"0" or mode == b"160000":
                raise ValueError("Resolve conflicts and remove submodules before scanning")
            target = destination / os.fsdecode(name)
            target.parent.mkdir(parents=True, exist_ok=True)
            # Symlink targets are scanned as text, never followed outside the repo.
            target.write_bytes(git("cat-file", "blob", oid.decode()))
    else:
        names = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
        for name in set(names.split(b"\0")) - {b""}:
            source = ROOT / os.fsdecode(name)
            if not source.exists() and not source.is_symlink():
                continue
            target = destination / os.fsdecode(name)
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_symlink():
                target.write_text(os.readlink(source))
            elif source.is_file() and source.resolve().is_relative_to(ROOT):
                shutil.copyfile(source, target)
            else:
                raise ValueError("Cannot scan a submodule or a file outside the repository")


def scan(binary, mode, source, config, report):
    command = [binary, mode, str(source), "--config", str(config),
               "--redact=100", "--no-banner", "--no-color", "--log-level=error",
               "--ignore-gitleaks-allow", "--max-decode-depth=5", "--max-archive-depth=2",
               "--report-format=json", "--report-path", str(report)]
    if mode == "git":
        command.append("--log-opts=--all --full-history")
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    if result.returncode not in (0, 1) or not report.is_file():
        print(f"Secret scan failed (exit {result.returncode}); check Gitleaks installation/configuration.")
        return 2
    findings = json.loads(report.read_text()) or []
    for finding in findings:
        filename = finding["File"]
        if mode == "dir":
            filename = str(Path(filename).relative_to(source))
        commit = finding.get("Commit", "")[:12]
        print(f"FAIL {filename}:{finding['StartLine']} [{finding['RuleID']}] {commit}".rstrip())
    if not findings and result.returncode == 0:
        print(f"PASS {'Git history' if mode == 'git' else 'publishable files'}: no findings")
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="scan index contents, including forced additions")
    parser.add_argument("--history", action="store_true", help="also scan every local branch/tag and remote ref")
    args = parser.parse_args()
    binary = shutil.which(os.environ.get("GITLEAKS_BIN", "gitleaks"))
    if not binary:
        parser.error("Gitleaks is required; see docs/security.md")
    with tempfile.TemporaryDirectory(prefix="omarchy-secret-check-") as folder:
        scratch = Path(folder)
        files = scratch / "files"
        files.mkdir()
        snapshot(files, args.staged)
        # Check names separately: binary/empty credential stores can evade content scanners.
        config = ROOT / ".gitleaks.toml"
        try:
            rules = tomllib.loads(config.read_text())["rules"]
        except (tomllib.TOMLDecodeError, KeyError):
            print("Secret scan failed: invalid Gitleaks configuration.")
            return 2
        credential_path = next(rule["path"] for rule in rules if rule["id"] == "credential-file")
        names = {str(path.relative_to(files)) for path in files.rglob("*") if path.is_file()}
        if args.history:
            names.update(os.fsdecode(name) for name in
                         git("log", "--all", "--format=", "--name-only", "-z").split(b"\0") if name)
        blocked = [name for name in names if re.search(credential_path, name)]
        if blocked:
            for path in sorted(blocked):
                print(f"FAIL {path} [credential-file]")
            return 1
        result = scan(binary, "dir", files, config, scratch / "files.json")
        if args.history:
            result = max(result, scan(binary, "git", ROOT, ROOT / ".gitleaks.toml", scratch / "history.json"))
        return result


if __name__ == "__main__":
    raise SystemExit(main())
