"""herdr-tmux routing between the herdr TUI server and the Herdr desktop app."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin/bin/herdr-tmux"


class HerdrTmuxRoutingTests(unittest.TestCase):
    def run_helper(self, args, windows, extra_env=None):
        """Run with fake hyprctl and herdr-app, and a herdr socket that is absent."""
        with tempfile.TemporaryDirectory(prefix="herdr-tmux-") as folder:
            root = Path(folder)
            (root / "clients.json").write_text(json.dumps([{"class": c} for c in windows]))
            hyprctl = root / "hyprctl"
            hyprctl.write_text('#!/bin/sh\ncat "$CLIENTS"\n')
            hyprctl.chmod(0o755)
            app = root / "herdr-app"
            app.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\nprintf \'{"ok": true}\\n\'\n')
            app.chmod(0o755)
            calls = root / "calls"
            env = {**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                   "CLIENTS": str(root / "clients.json"), "CALLS": str(calls),
                   "HERDR_SOCKET_PATH": str(root / "missing.sock")}
            env.pop("HERDR_ACTIVE_WORKSPACE_ID", None)
            env.update(extra_env or {})
            result = subprocess.run([str(HELPER), *args], capture_output=True,
                                    text=True, timeout=5, env=env)
            return result, calls.read_text().splitlines() if calls.exists() else []

    def test_global_keys_drive_the_app_while_its_window_is_open(self):
        for args, command in ((["workspace", "next"], "do space.next"),
                              (["workspace", "prev"], "do space.prev"),
                              (["agent", "next"], "do agent.next")):
            with self.subTest(args=args):
                result, calls = self.run_helper(args, ["Google-chrome", "herdr-app"])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls, [command])

    def test_without_an_app_window_the_tui_server_is_used(self):
        result, calls = self.run_helper(["workspace", "next"], ["Google-chrome"])
        self.assertEqual(calls, [])
        self.assertIn("cannot reach herdr", result.stderr)

    def test_herdr_tui_keybindings_stay_on_the_tui(self):
        result, calls = self.run_helper(["agent", "next"], ["herdr-app"],
                                        {"HERDR_ACTIVE_WORKSPACE_ID": "w1"})
        self.assertEqual(calls, [])
        self.assertIn("cannot reach herdr", result.stderr)


if __name__ == "__main__":
    unittest.main()
