"""Check SSH readiness without gating fresh installs on private account login."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("verify_setup", ROOT / "scripts/verify_setup.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class ServiceInstallerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ssh-setup-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        plan = json.loads((ROOT / "setup/steps.json").read_text())
        for step in plan["install"]:
            (self.repo / step["script"]).write_text("#!/bin/bash\nexit 0\n")
        for name in ("install_all.sh", "install_services.sh", "setup/steps.json",
                     "scripts/configure_ssh.py", "scripts/configure_sshd.sh",
                     "ssh/.ssh/authorized_keys"):
            destination = self.repo / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        commands = self.root / "commands"
        commands.mkdir()
        self.log = self.root / "commands.jsonl"
        sudo = commands / "sudo"
        # Record privileged work without starting services or changing /etc.
        sudo.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["SSH_SETUP_TEST_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
if args[0] == "bash" and Path(args[1]).name == "configure_sshd.sh":
    raise SystemExit(int(os.environ.get("SSH_SETUP_TEST_SERVER_EXIT", "0")))
''')
        sudo.chmod(0o755)
        self.env = os.environ | {
            "HOME": str(self.home), "PATH": str(commands) + os.pathsep + os.environ["PATH"],
            "SSH_SETUP_TEST_LOG": str(self.log),
        }

    def install(self):
        return subprocess.run(["bash", str(self.repo / "install_all.sh")],
                              env=self.env, cwd=self.repo, capture_output=True, text=True, timeout=15)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_full_install_plan_configures_key_based_ssh_in_an_empty_home(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        authorized = self.home / ".ssh/authorized_keys"
        self.assertEqual(authorized.read_text(), (ROOT / "ssh/.ssh/authorized_keys").read_text())
        self.assertEqual(authorized.stat().st_mode & 0o777, 0o600)
        commands = self.commands()
        server = ["bash", str(self.repo / "scripts/configure_sshd.sh")]
        tailscale = next(args for args in commands if args[:2] == ["tailscale", "set"])
        self.assertIn("--ssh=false", tailscale)
        self.assertIn("--shields-up=false", tailscale)
        self.assertLess(commands.index(server), commands.index(tailscale))

    def test_rerun_preserves_existing_keys_and_private_host_configuration(self):
        ssh = self.home / ".ssh"
        ssh.mkdir()
        # A disposable caller's key must survive both setup passes.
        authorized = ssh / "authorized_keys"
        key = self.root / "fixture-key"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
                       check=True, capture_output=True)
        existing = key.with_suffix(".pub").read_text()
        authorized.write_text(existing)
        private = "Host private-fixture\n  HostName example.invalid\n"
        (ssh / "config").write_text(private)
        for _ in range(2):
            result = self.install()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(authorized.read_text().startswith(existing))
        for key in (ROOT / "ssh/.ssh/authorized_keys").read_text().splitlines():
            self.assertEqual(authorized.read_text().splitlines().count(key), 1)
        self.assertIn(private, (ssh / "config").read_text())

    def test_server_failure_reaches_outer_installer_without_disabling_existing_access(self):
        self.env["SSH_SETUP_TEST_SERVER_EXIT"] = "42"
        result = self.install()
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertIn("install_services.sh (exit 42)", result.stderr)
        self.assertFalse(any(args[:2] == ["tailscale", "set"] for args in self.commands()))


class TailscaleReadinessTests(unittest.TestCase):
    def verify(self, prefs=None, *, service_code=0, sshd_code=0, prefs_code=0, output=None, error=None):
        if output is None:
            output = json.dumps(prefs)

        def run(argv, **kwargs):
            if argv in (["systemctl", "is-active", "--quiet", "sshd.service"],
                        ["systemctl", "is-enabled", "--quiet", "sshd.service"]):
                return subprocess.CompletedProcess(argv, sshd_code)
            if argv == ["systemctl", "is-active", "--quiet", "tailscaled.service"]:
                return subprocess.CompletedProcess(argv, service_code)
            if argv == ["tailscale", "debug", "prefs"]:
                if error:
                    raise error
                return subprocess.CompletedProcess(argv, prefs_code, output, "")
            self.fail(f"Unexpected command (sign-in must stay private): {argv}")

        checks = verifier.Checks(json_output=True)
        with patch.object(verifier.subprocess, "run", side_effect=run):
            verifier.verify_tailscale(checks)
        return checks

    def test_configured_device_passes_before_sign_in(self):
        checks = self.verify({"RunSSH": False, "ShieldsUp": False, "WantRunning": False})
        self.assertEqual((checks.failed, checks.pending), (0, 0))
        self.assertEqual(len(checks.results), 5)

    def test_intercepted_ssh_or_blocked_incoming_connections_need_repair(self):
        for prefs, label in [
            ({"RunSSH": True, "ShieldsUp": False}, "Tailscale SSH interception disabled"),
            ({"RunSSH": False, "ShieldsUp": True}, "Tailscale incoming connections allowed"),
        ]:
            with self.subTest(prefs=prefs):
                checks = self.verify(prefs)
                failures = [item for item in checks.results if item["status"] == "fail"]
                self.assertEqual([item["label"] for item in failures], [label])
                self.assertIn("./install_services.sh", failures[0]["remedy"])
                self.assertEqual(checks.pending, 0)

    def test_stopped_daemon_fails_even_if_preferences_would_be_correct(self):
        checks = self.verify({"RunSSH": False, "ShieldsUp": False}, service_code=3)
        self.assertEqual(checks.failed, 1)
        self.assertEqual(checks.results[2]["label"], "tailscaled.service active")

    def test_stopped_openssh_fails_even_with_tailscale_running(self):
        checks = self.verify({"RunSSH": False, "ShieldsUp": False}, sshd_code=3)
        self.assertEqual(checks.failed, 2)

    def test_missing_fields_and_non_boolean_values_cannot_pass(self):
        for prefs in ({}, {"RunSSH": "true", "ShieldsUp": "false"},
                      {"RunSSH": 1, "ShieldsUp": 0}):
            with self.subTest(prefs=prefs):
                self.assertEqual(self.verify(prefs).failed, 2)

    def test_failed_command_cannot_pass_with_valid_looking_output(self):
        checks = self.verify({"RunSSH": False, "ShieldsUp": False}, prefs_code=1)
        self.assertEqual(checks.failed, 1)

    def test_malformed_output_is_reported_without_echoing_preferences(self):
        for output in ("invalid json with private data", "null", "[]", '"unexpected"'):
            with self.subTest(output=output):
                checks = self.verify(output=output)
                self.assertEqual(checks.failed, 1)
                self.assertNotIn(output, json.dumps(checks.results))

    def test_missing_client_and_timeout_report_failure(self):
        for error in (FileNotFoundError(), subprocess.TimeoutExpired("tailscale", 40)):
            with self.subTest(error=error):
                checks = self.verify(error=error)
                self.assertEqual((checks.failed, checks.pending), (1, 0))


if __name__ == "__main__":
    unittest.main()
