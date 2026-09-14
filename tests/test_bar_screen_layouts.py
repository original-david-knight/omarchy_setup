"""Offline checks for the david.bar per-screen layout wrapper."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGINS = ROOT / "omarchy/.config/omarchy/plugins"
PLUGIN = PLUGINS / "david.bar"
MODEL = PLUGIN / "ScreenLayouts.js"

# Logical geometry Quickshell reports for the desktop monitors after
# Hyprland's transforms: the side monitors are rotated into portrait.
LEFT = {"name": "DP-1", "model": "VG27AQL1A", "serialNumber": "", "width": 1440, "height": 2560}
RIGHT = {"name": "DP-3", "model": "VG27AQL1A", "serialNumber": "", "width": 1440, "height": 2560}
CENTER = {"name": "DP-2", "model": "LG ULTRAGEAR+", "serialNumber": "", "width": 5120, "height": 2160}


def desktop_bar():
    return json.loads((ROOT / "omarchy_desktop/.config/omarchy/shell.json").read_text())["bar"]


def layout_ids(layout):
    return [entry["id"] for section in ("left", "center", "right") for entry in layout.get(section, [])]


@unittest.skipUnless(shutil.which("node"), "requires Node.js")
class ScreenLayoutModelTests(unittest.TestCase):
    def evaluate(self, body, **values):
        script = "const S = require(process.argv[1]); const V = JSON.parse(process.argv[2]);" \
            f"console.log(JSON.stringify((() => {{ {body} }})()));"
        result = subprocess.run(["node", "-e", script, str(MODEL), json.dumps(values)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_orientation_follows_logical_size(self):
        self.assertEqual(self.evaluate("return S.orientationOf(V.s)", s=LEFT), "portrait")
        self.assertEqual(self.evaluate("return S.orientationOf(V.s)", s=CENTER), "landscape")
        self.assertEqual(self.evaluate("return S.orientationOf(V.s)", s={"name": "X"}), "")

    def test_match_forms(self):
        cases = [
            ("portrait", LEFT, True), ("portrait", CENTER, False), ("landscape", CENTER, True),
            ("dp-1", LEFT, True), ("DP-1", RIGHT, False),
            ({"name": ["DP-1", "DP-3"]}, RIGHT, True), ({"name": ["DP-1", "DP-3"]}, CENTER, False),
            ({"model": "vg27aql1a", "orientation": "portrait"}, LEFT, True),
            ({"model": "vg27aql1a", "orientation": "landscape"}, LEFT, False),
            ({"serialNumber": "ABC"}, LEFT, False),
        ]
        for match, screen, expected in cases:
            with self.subTest(match=match, screen=screen["name"]):
                self.assertEqual(self.evaluate(
                    "return S.screenMatches(V.screen, S.normalizeMatch(V.match))",
                    screen=screen, match=match), expected)

    def test_invalid_matches_are_rejected(self):
        for match in ("", {}, {"orientation": "sideways"}, {"name": []}, {"other": "x"}, 7, None):
            with self.subTest(match=match):
                self.assertIsNone(self.evaluate("return S.normalizeMatch(V.match)", match=match))

    def test_parse_drops_invalid_entries_with_warnings(self):
        config = {"screenLayouts": [
            {"name": "sides", "match": "portrait", "layout": {"left": ["omarchy.workspaces", "", 3],
                                                              "center": [{"id": "omarchy.clock", "format": "HH:mm"}]}},
            {"name": "broken", "match": {"orientation": "diagonal"}, "layout": {}},
            {"match": "landscape"},
            "not an object",
        ]}
        parsed, warnings = self.evaluate(
            "const w = []; const p = S.parse(V.config, m => w.push(m)); return [p, w]", config=config)
        self.assertEqual([layout["name"] for layout in parsed], ["sides"])
        self.assertEqual(parsed[0]["layout"], {
            "left": [{"id": "omarchy.workspaces"}],
            "center": [{"id": "omarchy.clock", "format": "HH:mm"}],
            "right": [],
        })
        self.assertEqual(len(warnings), 3)
        self.assertIn("broken", warnings[0])
        self.assertIn("#3", warnings[1])
        self.assertIn("#4", warnings[2])
        self.assertEqual(self.evaluate("return S.parse(V.config)", config={}), [])
        self.assertEqual(self.evaluate("return S.parse(V.config)", config=None), [])

    def test_first_matching_layout_wins(self):
        config = {"screenLayouts": [
            {"name": "left only", "match": "DP-1", "layout": {"left": ["omarchy.workspaces"]}},
            {"name": "portrait", "match": "portrait", "layout": {"center": ["omarchy.clock"]}},
        ]}
        body = "const l = S.parse(V.config); return V.screens.map(s => { const r = S.layoutFor(l, s); return r ? r.name : null })"
        self.assertEqual(self.evaluate(body, config=config, screens=[LEFT, RIGHT, CENTER]),
                         ["left only", "portrait", None])

    def test_desktop_profile_gives_portrait_screens_a_compact_layout(self):
        body = ("const l = S.parse(V.bar, m => { throw new Error(m) });"
                "return V.screens.map(s => { const r = S.layoutFor(l, s); return r ? S.layoutIds(r.layout) : null })")
        sides = [["omarchy.workspaces", "omarchy.clock"]] * 2
        self.assertEqual(self.evaluate(body, bar=desktop_bar(), screens=[LEFT, RIGHT, CENTER]), sides + [None])

    def test_describe_screen(self):
        self.assertEqual(self.evaluate("return S.describeScreen(V.s)", s=LEFT), "DP-1 1440x2560 portrait (VG27AQL1A)")


class ProfileConfigTests(unittest.TestCase):
    def test_desktop_selects_the_wrapper_bar_with_a_portrait_layout(self):
        bar = desktop_bar()
        self.assertEqual(bar["id"], "david.bar")
        self.assertEqual([entry["match"] for entry in bar["screenLayouts"]], ["portrait"])
        portrait = bar["screenLayouts"][0]["layout"]
        self.assertEqual(layout_ids(portrait), ["omarchy.workspaces", "omarchy.clock"])
        main_clock = next(entry for entry in bar["layout"]["center"] if entry["id"] == "omarchy.clock")
        self.assertEqual(portrait["center"][0], main_clock)

    def test_every_screen_layout_widget_is_deployable(self):
        for entry in desktop_bar()["screenLayouts"]:
            for widget in layout_ids(entry["layout"]):
                with self.subTest(widget=widget):
                    if widget.startswith("david."):
                        self.assertTrue((PLUGINS / widget / "manifest.json").is_file())
                    else:
                        self.assertTrue(widget.startswith("omarchy."))

    def test_laptop_keeps_the_stock_bar(self):
        bar = json.loads((ROOT / "omarchy_laptop/.config/omarchy/shell.json").read_text())["bar"]
        self.assertNotIn("id", bar)
        self.assertNotIn("screenLayouts", bar)


class PluginFilesTests(unittest.TestCase):
    def test_manifest_declares_a_bar_option(self):
        manifest = json.loads((PLUGIN / "manifest.json").read_text())
        self.assertEqual(manifest["id"], "david.bar")
        self.assertEqual(manifest["kinds"], ["bar"])
        self.assertEqual(manifest["entryPoints"], {"bar": "Bar.qml"})
        self.assertTrue((PLUGIN / "Bar.qml").is_file())

    @unittest.skipUnless(shutil.which("qmllint"), "requires qmllint")
    def test_wrapper_lints(self):
        result = subprocess.run(["qmllint", "-I", "/usr/lib/qt6/qml", "Bar.qml"],
                                cwd=PLUGIN, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("omarchy"), "requires Omarchy")
    def test_manifest_validates(self):
        result = subprocess.run(["omarchy", "plugin", "validate", str(PLUGIN)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
