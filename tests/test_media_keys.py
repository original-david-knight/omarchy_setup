"""Media-key routing without controlling any real media player."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "omarchy/.config/omarchy/plugins/david.media"


class MediaKeyTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("quickshell"), "requires Quickshell")
    def test_playback_ownership_through_pause_resume_switch_and_close(self):
        with tempfile.TemporaryDirectory(prefix="media-keys-") as folder:
            root = Path(folder)
            (root / "Media").symlink_to(MEDIA, target_is_directory=True)
            shutil.copyfile(Path(__file__).with_name("media-keys.qml"), root / "shell.qml")
            result = subprocess.run(
                ["dbus-run-session", "--", "quickshell", "-p", str(root), "--no-color"],
                capture_output=True, text=True, timeout=15,
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen"})
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("MEDIA KEY TEST PASSED", output)
        for error in ("TEST FAILED", "TypeError", "ReferenceError", "Binding loop"):
            self.assertNotIn(error, output)

    def test_helper_delegates_once_without_podcast_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            shell = root / "shell"
            shell.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\nprintf "unhandled\\n"\n')
            shell.chmod(0o755)
            podcast = root / "podcast"
            podcast.write_text('#!/bin/sh\nprintf "podcast\\n" >> "$CALLS"\n')
            podcast.chmod(0o755)
            calls = root / "calls"
            result = subprocess.run([str(ROOT / "bin/bin/media-play-pause")],
                text=True, capture_output=True, timeout=5, env={**os.environ,
                    "OMARCHY_SHELL": str(shell), "PODCAST_PLAYER": str(podcast), "CALLS": str(calls)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls.read_text().splitlines(), ["media playPause"])

    def test_profiles_enable_the_service_without_adding_another_bar_widget(self):
        for profile in ("desktop", "laptop"):
            with self.subTest(profile=profile):
                config = json.loads((ROOT / f"omarchy_{profile}/.config/omarchy/shell.json").read_text())
                self.assertIn({"id": "david.media"}, config["plugins"])
                self.assertIn("omarchy.media", config["disabledPlugins"])
                self.assertFalse(any(entry.get("id") == "david.media"
                    for entries in config["bar"]["layout"].values() for entry in entries))


if __name__ == "__main__":
    unittest.main()
