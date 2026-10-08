"""Offscreen behavior checks for the actual meeting panel and its installed Ui controls."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "omarchy/.config/omarchy/plugins/david.meeting/Panel.qml"
SHELL = Path.home() / ".local/share/omarchy/shell"

WINDOW_HOST = """import QtQuick
Item {
  required property Item anchorItem
  property var owner: null
  property QtObject bar: null
  property bool open: false
  property Item focusTarget: null
  property int contentWidth: 390
  property int contentHeight: 760
  default property alias contentItem: holder.children
  function fittedContentWidth(width, cap) { return Math.round(Math.min(width, cap || width)) }
  function fittedContentHeight(height, cap) { return Math.round(Math.min(height, cap || height)) }
  x: 0; y: 70; width: contentWidth; height: contentHeight
  visible: open
  Item { id: holder; anchors.fill: parent }
}
"""

CALENDAR = """#!/usr/bin/env python3
import datetime, json
print(json.dumps({'status':'ready','date':datetime.datetime.now().astimezone().date().isoformat(),
                  'events':[],'last_sync':'now','warning':''}))
"""

LITRA = """#!/usr/bin/env python3
import json, os, pathlib, sys
state_path = pathlib.Path(os.environ['MEETING_LIGHT_STATE'])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
with open(os.environ["MEETING_LIGHT_POLL_LOG"], "a") as log:
    print(" ".join(args), file=log)
if len(args) == 3 and args[0] == 'set':
    with open(os.environ['MEETING_COMMAND_LOG'], 'a') as log:
        print('litra ' + ' '.join(args), file=log)
    key, value = args[1:]
    state[key] = (value == 'on') if key == 'power' else int(value)
    state_path.write_text(json.dumps(state))
print(json.dumps(state))
"""

RECORDER = """#!/usr/bin/env python3
import os, sys, time
args = sys.argv[1:]
if args == ['watch']:
    print('{"state":"off"}', flush=True)
    while True: time.sleep(1)
with open(os.environ['MEETING_COMMAND_LOG'], 'a') as log:
    print('recorder ' + ' '.join(args), file=log)
"""


OPENER = """#!/bin/sh
printf '%s\\n' "$*" >> "$MEETING_OPENER_LOG"
"""


class MeetingPanelTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("quickshell") and SHELL.is_dir(), "requires installed Omarchy Shell")
    def test_panel_actions_and_source_driven_states(self):
        self.run_panel(laptop=False)

    @unittest.skipUnless(shutil.which("quickshell") and SHELL.is_dir(), "requires installed Omarchy Shell")
    def test_laptop_hides_light_controls_and_never_polls_usb(self):
        self.run_panel(laptop=True)

    def run_panel(self, laptop):
        with tempfile.TemporaryDirectory(prefix="meeting-panel-") as folder:
            workspace = Path(folder)
            (workspace / "Commons").symlink_to(SHELL / "Commons", target_is_directory=True)
            ui = workspace / "Ui"
            ui.mkdir()
            for source in (SHELL / "Ui").iterdir():
                if source.name != "KeyboardPanel.qml" and source.is_file():
                    (ui / source.name).symlink_to(source)
            (ui / "KeyboardPanel.qml").write_text(WINDOW_HOST)
            meeting = workspace / "Meeting"
            meeting.mkdir()
            shutil.copy2(PANEL, meeting / "Panel.qml")
            for name, source in (("calendar", CALENDAR), ("litra", LITRA)):
                script = meeting / name
                script.write_text(source)
                script.chmod(0o755)
            binary = workspace / "bin"
            binary.mkdir()
            recorder = binary / "omarchy-meeting-recorder"
            recorder.write_text(RECORDER)
            recorder.chmod(0o755)
            opener = binary / "open-work-url"
            opener.write_text(OPENER)
            opener.chmod(0o755)
            opener_log = workspace / "opened.log"
            opener_log.write_text("")
            shutil.copy2(Path(__file__).with_name("meeting-panel.qml"), workspace / "shell.qml")
            light_state = workspace / "light.json"
            light_state.write_text('{"status":"ready","power":false,"brightness":120,"temperature":4200}')
            command_log = workspace / "commands.log"
            command_log.write_text("")
            poll_log = workspace / "polls.log"
            poll_log.write_text("")
            for name in ("runtime", "config", "cache"):
                (workspace / name).mkdir()
            env = {**os.environ,
                "PATH": str(binary) + os.pathsep + os.environ.get("PATH", ""),
                "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "generic",
                "QT_QUICK_CONTROLS_STYLE": "Basic", "QT_STYLE_OVERRIDE": "Fusion",
                "XDG_RUNTIME_DIR": str(workspace / "runtime"),
                "XDG_CONFIG_HOME": str(workspace / "config"),
                "XDG_CACHE_HOME": str(workspace / "cache"),
                "MEETING_LIGHT_STATE": str(light_state),
                "MEETING_COMMAND_LOG": str(command_log),
                "MEETING_LIGHT_POLL_LOG": str(poll_log),
                "MEETING_TEST_OPENER": str(opener), "MEETING_OPENER_LOG": str(opener_log),
                "MEETING_TEST_LAPTOP": "1" if laptop else ""}
            env.pop("DISPLAY", None)
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["quickshell", "-p", str(workspace), "--no-color"],
                env=env, text=True, capture_output=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertIn("MEETING PANEL TEST PASSED", output,
                output + "\nCommands: " + command_log.read_text() + "\nLight: " + light_state.read_text())
            self.assertNotIn("TypeError", output)
            self.assertNotIn("ReferenceError", output)
            self.assertNotIn("Binding loop", output)
            if laptop:
                self.assertEqual(poll_log.read_text(), "")
                self.assertEqual(command_log.read_text(), "")
                self.assertEqual(opener_log.read_text(), "")
                return
            # The opener runs detached, so wait for all three launches in any order.
            deadline = time.monotonic() + 3
            while len(opener_log.read_text().splitlines()) < 3 and time.monotonic() < deadline:
                time.sleep(0.02)
            opened = sorted(opener_log.read_text().splitlines())
            self.assertEqual(len(opened), 3, opened)
            self.assertEqual(opened[0][:len("https://calendar.google.com/calendar/r/day/")],
                             "https://calendar.google.com/calendar/r/day/")
            self.assertEqual(opened[1:], ["https://meet.google.com/abc-defg-hij",
                                          "https://www.google.com/calendar/event?eid=Y3VycmVudA"])
            preview = os.environ.get("MEETING_PREVIEW_PATH")
            if preview:
                self.assertIn("MEETING PANEL PREVIEW SAVED", output, output)
                self.assertGreater(Path(preview).stat().st_size, 1000)
            self.assertEqual(command_log.read_text().splitlines(), [
                "litra set power on", "litra set brightness 129", "litra set temperature 4300",
                "recorder start", "recorder pause", "recorder stop"])


if __name__ == "__main__":
    unittest.main()
