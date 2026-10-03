import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProfileTests(unittest.TestCase):
    def profile(self, laptop, monitors, override="auto"):
        with tempfile.TemporaryDirectory() as directory:
            commands = Path(directory)
            detector = commands / "omarchy-hw-laptop"
            detector.write_text(f"#!/bin/sh\nexit {0 if laptop else 1}\n")
            detector.chmod(0o755)
            result = subprocess.run(
                ["bash", "-c", 'source "$1"; fixture_monitors=$2; get_monitor_count() { echo "$fixture_monitors"; }; setup_profile',
                 "profile-test", str(ROOT / "scripts/setup_profile.sh"), str(monitors)],
                env=os.environ | {"PATH": str(commands) + os.pathsep + os.environ["PATH"],
                                  "OMARCHY_SETUP_PROFILE": override},
                text=True, capture_output=True, check=True,
            )
            return result.stdout.strip()

    def test_docked_laptop_keeps_laptop_profile(self):
        self.assertEqual(self.profile(True, 3), "laptop")

    def test_desktop_with_three_displays_uses_desktop_profile(self):
        self.assertEqual(self.profile(False, 3), "desktop")

    def test_single_display_falls_back_to_laptop_profile(self):
        self.assertEqual(self.profile(False, 1), "laptop")

    def test_explicit_profile_wins_over_hardware_detection(self):
        self.assertEqual(self.profile(True, 3, "desktop"), "desktop")


if __name__ == "__main__":
    unittest.main()
