"""Exercise real secret detection against disposable repositories and fake secrets."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GITLEAKS = shutil.which(os.environ.get("GITLEAKS_BIN", "gitleaks"))


@unittest.skipUnless(GITLEAKS, "Gitleaks is required for scanner integration tests")
class SecretScanTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="secret-scan-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "scripts").mkdir()
        for name in (".gitleaks.toml", ".gitignore", "scripts/check_secrets.py"):
            shutil.copyfile(ROOT / name, self.root / name)
        self.git("init", "-q")
        self.git("config", "user.name", "Secret Scan Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True,
                              capture_output=True, text=True)

    def scan(self, *args):
        return subprocess.run(["python3", str(self.root / "scripts/check_secrets.py"), *args],
                              cwd=self.root, env={**os.environ, "GITLEAKS_BIN": GITLEAKS},
                              capture_output=True, text=True, timeout=20)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    @staticmethod
    def shell_default(value):
        # Assemble synthetic leaks so the test source itself remains publishable.
        expansion = "$" + "{WIFI_" + "PASSWORD" + ":-" + value + "}"
        return "PASSWORD=" + json.dumps(expansion) + "\n"

    def test_short_shell_fallback_is_blocked_without_exposing_value(self):
        value = "synthetic" + "-low-entropy"
        self.write("wifi.sh", self.shell_default(value))
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("shell-credential-default", result.stdout)
        self.assertNotIn(value, result.stdout + result.stderr)

    def test_short_literal_passcode_is_blocked(self):
        value = "12" + "34"
        self.write("settings.json", '{"passcode": "' + value + '"}')
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("literal-password", result.stdout)
        self.assertNotIn(value, result.stdout + result.stderr)

    def test_forced_credential_file_is_blocked_even_when_worktree_is_clean(self):
        self.write(".env", "SETTING=synthetic\n")
        self.assertEqual(self.scan().returncode, 0)
        self.git("add", "-f", ".env")
        (self.root / ".env").write_text("")
        result = self.scan("--staged")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("credential-file", result.stdout)

    def test_index_secret_is_not_hidden_by_an_unstaged_fix(self):
        self.write("config.sh", self.shell_default("synthetic-leak"))
        self.git("add", "config.sh")
        self.write("config.sh", 'PASSWORD="${WIFI_PASSWORD:-}"\n')
        self.assertEqual(self.scan().returncode, 0)
        self.assertEqual(self.scan("--staged").returncode, 1)

    def test_deleted_secret_is_still_detected_in_history(self):
        self.write("config.sh", self.shell_default("synthetic-leak"))
        self.git("add", ".")
        self.git("commit", "-qm", "Synthetic fixture")
        self.git("rm", "config.sh")
        self.git("commit", "-qm", "Remove fixture")
        self.assertEqual(self.scan().returncode, 0)
        result = self.scan("--history")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("shell-credential-default", result.stdout)

    def test_exact_shortcut_exception_does_not_hide_other_keys(self):
        name = "herdr/.config/herdr/config.toml"
        shortcut = 'key = ' + json.dumps('ctrl+alt+shift+down') + '\n'
        self.write(name, shortcut)
        self.assertEqual(self.scan().returncode, 0)
        token = "ghp_" + "AbCdEfGh1234567890" * 2
        self.write(name, shortcut + 'api_key = ' + json.dumps(token) + '\n')
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn(token, result.stdout + result.stderr)

    def test_binary_and_empty_credential_files_cannot_bypass_the_scan(self):
        for data in (b"", b"\x00\xff\x00"):
            with self.subTest(data=data):
                (self.root / "client.p12").write_bytes(data)
                self.git("add", "-f", "client.p12")
                result = self.scan("--staged")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("credential-file", result.stdout)

    def test_deleted_binary_credential_is_detected_in_history(self):
        (self.root / "client.p12").write_bytes(b"\x00\xff\x00")
        self.git("add", "-f", "client.p12")
        self.git("commit", "-qm", "Synthetic binary fixture")
        self.git("rm", "client.p12")
        self.git("commit", "-qm", "Remove binary fixture")
        self.assertEqual(self.scan().returncode, 0)
        result = self.scan("--history")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("credential-file", result.stdout)

    def test_empty_environment_fallback_and_public_key_are_allowed(self):
        self.write("config.sh", 'PASSWORD="${WIFI_PASSWORD:-}"\nTOKEN="$runtime_token"\n')
        self.write("ssh/.ssh/id_github.pub", "ssh-ed25519 synthetic-public-key\n")
        self.assertEqual(self.scan().returncode, 0)

    def test_scanner_failure_cannot_pass(self):
        (self.root / ".gitleaks.toml").write_text("invalid TOML = [")
        result = self.scan()
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
