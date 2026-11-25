"""Offscreen check that david.agents extends the installed stock Agents panel
and switches Claude accounts through claude-account."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_meeting_panel import WINDOW_HOST

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "omarchy/.config/omarchy/plugins/david.agents/Panel.qml"
SHELL = Path.home() / ".local/share/omarchy/shell"
STOCK = Path("/usr/share/omarchy/shell/plugins/agents/Panel.qml")

# Two saved accounts; `use` makes the named one active and logs the call.
ACCOUNTS = """#!/usr/bin/env python3
import json, os, pathlib, sys
state = pathlib.Path(os.environ["AGENTS_TEST_ACTIVE"])
if sys.argv[1:2] == ["use"]:
    with open(os.environ["AGENTS_TEST_LOG"], "a") as log:
        print("use " + sys.argv[2], file=log)
    state.write_text(sys.argv[2])
    sys.exit(0)
if sys.argv[1:2] == ["usage"]:
    with open(os.environ["AGENTS_TEST_LOG"], "a") as log:
        print("usage " + sys.argv[2], file=log)
    print(json.dumps({"email": sys.argv[2], "limits": [
        {"label": "Weekly (7-day)", "title": "Weekly", "percent": .2,
         "resetsAt": os.environ["AGENTS_TEST_RESET"]},
        {"label": "Fable Weekly", "title": "Fable Weekly", "percent": .6,
         "resetsAt": os.environ["AGENTS_TEST_RESET"]}],
        "stale": False, "fetchedAt": 1, "status": "ok", "retryAt": 0}))
    sys.exit(0)
active = state.read_text()
print(json.dumps({"active": active, "accounts": [
    {"email": e, "plan": "Max 20x", "active": e == active, "signInExpired": False}
    for e in ("a@example.com", "b@example.com")]}))
"""

AGY_QUOTA = """#!/usr/bin/env python3
import json, os
print(json.dumps({
    "limits": [
        {"bucketId": "gemini-weekly", "label": "Weekly (7-day)", "title": "Weekly",
         "percent": 0.1758, "remainingFraction": 0.8242,
         "resetsAt": os.environ["AGENTS_TEST_AGY_WEEKLY_RESET"]},
        {"bucketId": "gemini-5h", "label": "Session (5-hour)", "title": "Session",
         "percent": 0.0164, "remainingFraction": 0.9836,
         "resetsAt": os.environ["AGENTS_TEST_AGY_SESSION_RESET"]},
    ],
    "stale": False,
    "fetchedAt": 1,
    "status": "ok",
    "retryAt": 0,
}))
"""

RECORD = {"schemaVersion": 1, "id": "claude", "name": "Claude Code", "ready": True,
          "tierLabel": "Max 20x", "limits": [], "totalPrompts": 5, "totalSessions": 1}


class AgentsAccountsTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("quickshell") and SHELL.is_dir() and STOCK.is_file(),
                         "requires installed Omarchy Shell")
    def test_account_row_joins_stock_panel_and_switches(self):
        self.run_panel(separate_popup=False)

    @unittest.skipUnless(shutil.which("quickshell") and SHELL.is_dir() and STOCK.is_file(),
                         "requires installed Omarchy Shell")
    def test_account_row_in_separate_popup_window(self):
        self.run_panel(separate_popup=True)

    def run_panel(self, separate_popup):
        with tempfile.TemporaryDirectory(prefix="agents-panel-") as folder:
            workspace = Path(folder)
            (workspace / "Commons").symlink_to(SHELL / "Commons", target_is_directory=True)
            ui = workspace / "Ui"
            ui.mkdir()
            for source in (SHELL / "Ui").iterdir():
                if source.name != "KeyboardPanel.qml" and source.is_file():
                    (ui / source.name).symlink_to(source)
            host = WINDOW_HOST
            if separate_popup:
                host = host.replace("Item {\n", "Item {\n  id: host\n", 1).replace(
                    "  Item { id: holder; anchors.fill: parent }\n"
                    "  Loader { id: loader; anchors.fill: parent; active: contentRequested; sourceComponent: content }",
                    "  Window {\n"
                    "    visible: host.open; width: host.contentWidth; height: host.contentHeight\n"
                    "    Item { id: holder; anchors.fill: parent }\n"
                    "    Loader { id: loader; anchors.fill: parent; active: host.contentRequested; sourceComponent: host.content }\n"
                    "  }")
            (ui / "KeyboardPanel.qml").write_text(host)
            (workspace / "Agents").mkdir()
            shutil.copy2(PANEL, workspace / "Agents/Panel.qml")
            shutil.copy2(Path(__file__).with_name("agents-panel.qml"), workspace / "shell.qml")

            home_bin = workspace / "bin"
            home_bin.mkdir()
            cli = home_bin / "claude-account"
            cli.write_text(ACCOUNTS)
            cli.chmod(0o755)
            agy_cli = home_bin / "agy-quota"
            agy_cli.write_text(AGY_QUOTA)
            agy_cli.chmod(0o755)
            update = home_bin / "omarchy-agent-usage-update"
            update.write_text("#!/bin/sh\nexit 0\n")
            update.chmod(0o755)
            usage = workspace / "state/omarchy/agents/usage"
            usage.mkdir(parents=True)
            import datetime
            now = datetime.datetime.now(datetime.timezone.utc)
            reset = (now + datetime.timedelta(days=1)).isoformat()
            agy_weekly_reset = (now + datetime.timedelta(hours=126, minutes=17)).isoformat()
            agy_session_reset = (now + datetime.timedelta(hours=4, minutes=28)).isoformat()
            claude_record = dict(RECORD, limits=[
                {"label": "Weekly (7-day)", "percent": .53, "resetsAt": reset},
                {"label": "Fable Weekly", "title": "Fable Weekly", "percent": .96, "resetsAt": reset}])
            agy_record = dict(RECORD, id="agy", name="Antigravity", tierLabel="Ultra", limits=[
                {"label": "Session (5-hour)", "title": "Session", "percent": 0.0, "resetsAt": ""},
                {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.0, "resetsAt": ""}])
            (usage / "claude.json").write_text(json.dumps(claude_record))
            (usage / "agy.json").write_text(json.dumps(agy_record))
            (usage / "codex.json").write_text(json.dumps(dict(RECORD, id="codex", name="Codex")))
            active = workspace / "active"
            active.write_text("a@example.com")
            log = workspace / "commands.log"
            log.write_text("")
            for name in ("runtime", "config", "cache"):
                (workspace / name).mkdir()

            env = {**os.environ,
                "HOME": str(workspace), "PATH": str(home_bin) + os.pathsep + os.environ.get("PATH", ""),
                "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "generic",
                "QT_QUICK_CONTROLS_STYLE": "Basic", "QT_STYLE_OVERRIDE": "Fusion",
                "XDG_RUNTIME_DIR": str(workspace / "runtime"),
                "XDG_CONFIG_HOME": str(workspace / "config"),
                "XDG_CACHE_HOME": str(workspace / "cache"),
                "XDG_STATE_HOME": str(workspace / "state"),
                "AGENTS_TEST_ACTIVE": str(active), "AGENTS_TEST_LOG": str(log),
                "AGENTS_TEST_RESET": reset,
                "AGENTS_TEST_AGY_WEEKLY_RESET": agy_weekly_reset,
                "AGENTS_TEST_AGY_SESSION_RESET": agy_session_reset,
                "AGENTS_TEST_SEPARATE_POPUP": "1" if separate_popup else "0"}
            if os.environ.get("AGENTS_TEST_SCREENSHOT"):
                env["AGENTS_TEST_SCREENSHOT"] = os.environ["AGENTS_TEST_SCREENSHOT"]
            if os.environ.get("AGENTS_TEST_AGY_SCREENSHOT"):
                env["AGENTS_TEST_AGY_SCREENSHOT"] = os.environ["AGENTS_TEST_AGY_SCREENSHOT"]
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["quickshell", "-p", str(workspace), "--no-color"],
                env=env, text=True, capture_output=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertIn("AGENTS PANEL TEST PASSED", output, output)
            self.assertNotIn("TypeError", output)
            self.assertNotIn("ReferenceError", output)
            self.assertEqual(log.read_text(), "usage b@example.com\nuse b@example.com\n")


if __name__ == "__main__":
    unittest.main()
