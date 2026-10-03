import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install_meeting.sh"
SOURCE_PLUGIN = ROOT / "omarchy/.config/omarchy/plugins/david.meeting"


class MeetingInstallerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.config = self.root / "home/.config"
        self.plugins = self.config / "omarchy/plugins"
        self.plugins.mkdir(parents=True)
        self.shell = self.config / "omarchy/shell.json"
        self.shell.write_text(json.dumps({
            "bar": {"layout": {"right": [
                {"id": "omarchy.tray"},
                {"id": "jankeesvw.meeting-recorder"},
            ]}}
        }))
        commands = self.root / "bin"
        commands.mkdir()
        self.sudo_log = self.root / "sudo.log"
        sudo = commands / "sudo"
        sudo.write_text("""#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' \"$*\" >>\"$MEETING_TEST_SUDO_LOG\"
if [[ $1 == tee ]]; then cat >\"$MEETING_TEST_RULE\"; fi
""")
        sudo.chmod(0o755)
        self.environment = os.environ | {
            "XDG_CONFIG_HOME": str(self.config),
            "OMARCHY_SETUP_PROFILE": "desktop",
            "PATH": str(commands) + os.pathsep + os.environ["PATH"],
            "MEETING_TEST_RULE": str(self.root / "rule"),
            "MEETING_TEST_SUDO_LOG": str(self.sudo_log),
        }

    def tearDown(self):
        self.temporary.cleanup()

    def run_installer(self):
        return subprocess.run(
            [str(INSTALLER)], cwd=ROOT, env=self.environment,
            text=True, capture_output=True,
        )

    def test_install_and_repeat_preserve_recorder_and_one_meeting_widget(self):
        first = self.run_installer()
        second = self.run_installer()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        installed = self.plugins / "david.meeting"
        self.assertTrue(installed.is_symlink())
        self.assertFalse(os.path.isabs(os.readlink(installed)))
        ids = [item["id"] for item in json.loads(self.shell.read_text())["bar"]["layout"]["right"]]
        self.assertEqual(ids.count("david.meeting"), 1)
        self.assertIn("jankeesvw.meeting-recorder", ids)
        self.assertEqual(len(list(self.shell.parent.glob("shell.json.bak.*"))), 1)

    def test_laptop_installs_meeting_without_sudo_or_light_controls(self):
        self.environment["OMARCHY_SETUP_PROFILE"] = "laptop"
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.sudo_log.exists())
        self.assertTrue((self.plugins / "david.meeting").is_symlink())
        right = json.loads(self.shell.read_text())["bar"]["layout"]["right"]
        self.assertIn({"id": "david.meeting", "litra": False}, right)
        self.assertIn({"id": "jankeesvw.meeting-recorder"}, right)

    def test_switching_from_desktop_to_laptop_disables_existing_light_controls(self):
        self.assertEqual(self.run_installer().returncode, 0)
        self.sudo_log.unlink(missing_ok=True)
        self.environment["OMARCHY_SETUP_PROFILE"] = "laptop"
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.sudo_log.exists())
        right = json.loads(self.shell.read_text())["bar"]["layout"]["right"]
        self.assertEqual([item for item in right if item["id"] == "david.meeting"],
                         [{"id": "david.meeting", "litra": False}])

    def test_accepts_plugin_directory_expanded_by_stow(self):
        installed = self.plugins / "david.meeting"
        installed.mkdir()
        for source in SOURCE_PLUGIN.iterdir():
            if source.is_file():
                (installed / source.name).symlink_to(source)
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(installed.is_dir())
        self.assertFalse(installed.is_symlink())

    def test_refuses_unrelated_copy_before_sudo(self):
        installed = self.plugins / "david.meeting"
        installed.mkdir()
        (installed / "manifest.json").write_text("{}")
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to replace unrelated plugin copy", result.stderr)
        self.assertFalse(self.sudo_log.exists())


if __name__ == "__main__":
    unittest.main()
