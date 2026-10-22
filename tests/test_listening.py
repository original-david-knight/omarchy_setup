"""Offline checks for the listening widget's external service boundaries."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error

PLUGIN = Path(__file__).resolve().parents[1] / "omarchy/.config/omarchy/plugins/david.podcasts"
loader = importlib.machinery.SourceFileLoader("mynoise", str(PLUGIN / "mynoise"))
spec = importlib.util.spec_from_loader(loader.name, loader)
noise = importlib.util.module_from_spec(spec)
loader.exec_module(noise)
spotify_loader = importlib.machinery.SourceFileLoader("spotify_library", str(PLUGIN / "spotify-library"))
spotify_spec = importlib.util.spec_from_loader(spotify_loader.name, spotify_loader)
spotify = importlib.util.module_from_spec(spotify_spec)
spotify_loader.exec_module(spotify)
eq_loader = importlib.machinery.SourceFileLoader("listening_eq", str(PLUGIN / "eq"))
eq_spec = importlib.util.spec_from_loader(eq_loader.name, eq_loader)
eq = importlib.util.module_from_spec(eq_spec)
eq_loader.exec_module(eq)
EQ_CONF = Path(__file__).resolve().parents[1] / "desktop/.config/pipewire/filter-chain.conf.d/70-listening-eq.conf"


class FetchTests(unittest.TestCase):
    def fetch(self, queue, shows, shows_status=200, queue_status=200):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                is_queue = self.path.endswith("/queue")
                body = json.dumps(queue if is_queue else shows).encode()
                self.send_response(queue_status if is_queue else shows_status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as folder:
                Path(folder, "config.json").write_text(json.dumps({
                    "service_url": f"http://127.0.0.1:{server.server_port}", "token": "test-only"}))
                return subprocess.run([str(PLUGIN / "fetch")], env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": folder},
                                      text=True, capture_output=True, timeout=15)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_show_art_fallback_does_not_replace_episode_art_or_progress(self):
        queue = {"entries": [
            {"episode_id": "1", "subscription_id": "show", "artwork_url": "", "position_seconds": 42},
            {"episode_id": "2", "subscription_id": "show", "artwork_url": "https://example.org/episode.jpg"}]}
        result = self.fetch(queue, {"subscriptions": [{"id": "show", "artwork_url": "https://example.org/show.jpg"}]})
        self.assertEqual(result.returncode, 0, result.stderr)
        entries = json.loads(result.stdout)["entries"]
        self.assertEqual(entries[0]["artwork_url"], "https://example.org/show.jpg")
        self.assertEqual(entries[0]["position_seconds"], 42)
        self.assertEqual(entries[1]["artwork_url"], "https://example.org/episode.jpg")

    def test_optional_show_service_failure_keeps_playable_queue(self):
        result = self.fetch({"entries": [{"episode_id": "1", "enclosure_url": "https://example.org/audio.mp3"}]}, {}, 503)
        self.assertEqual(result.returncode, 0, result.stderr)
        entry = json.loads(result.stdout)["entries"][0]
        self.assertEqual(entry["enclosure_url"], "https://example.org/audio.mp3")
        self.assertEqual(entry["artwork_url"], "")

    def test_queue_error_is_reported(self):
        result = self.fetch({}, {}, queue_status=503)
        self.assertNotEqual(result.returncode, 0)


class NoiseTests(unittest.TestCase):
    def test_invalid_commands_never_start_player(self):
        for args in [["play", "unknown"], ["volume", "coast", "nan"], ["volume", "coast", "inf"],
                     ["volume", "coast", "-1"], ["volume", "coast", "2"], ["javascript", "alert(1)"]]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                noise.validate(args)

    def test_corrupt_saved_volume_falls_back_and_never_autoplays(self):
        with tempfile.TemporaryDirectory() as folder:
            previous = noise.STATE
            noise.STATE = Path(folder)
            try:
                (noise.STATE / "volumes.json").write_text('{"coast":"broken","forest":0.6,"night":50}')
                state = noise.initial_state()
                self.assertEqual(state["coast"]["volume"], 0.35)
                self.assertEqual(state["forest"]["volume"], 0.6)
                self.assertEqual(state["night"]["volume"], 1)
                self.assertTrue(all(not s["playing"] and not s["requested"] for s in state.values()))
            finally:
                noise.STATE = previous

    def test_status_with_no_daemon_does_not_launch_browser(self):
        with tempfile.TemporaryDirectory() as folder:
            runtime = Path(folder) / "runtime"
            runtime.mkdir()
            result = subprocess.run([str(PLUGIN / "mynoise"), "status"], capture_output=True, text=True,
                env={**os.environ, "XDG_RUNTIME_DIR": str(runtime), "XDG_STATE_HOME": str(Path(folder) / "state")})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(json.loads(result.stdout)["running"])
            self.assertFalse((runtime / "david-listening").exists())


class SpotifyTests(unittest.TestCase):
    def config(self, folder):
        Path(folder, "config.json").write_text(json.dumps({"service_url": "https://example.test", "token": "private-test-token"}))

    def test_library_preserves_covers_and_filters_invalid_or_duplicate_uris(self):
        valid = {"uri": "spotify:playlist:" + "a" * 22, "name": "Focus", "artwork_url": "https://example.test/cover.jpg", "tracks_total": 10}
        data = {"playlists": [valid, valid, {"uri": "https://unexpected.test"}, None]}
        with tempfile.TemporaryDirectory() as folder:
            self.config(folder)
            with patch.dict(os.environ, {"EVERYTHING_AGENT_CONFIG_DIR": folder}), \
                 patch.object(spotify.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(data).encode())):
                result = spotify.playlists()["playlists"]
                self.assertEqual(len(result), 1)
                self.assertEqual(result[0]["artwork_url"], valid["artwork_url"])
                self.assertEqual(result[0]["tracks_total"], 10)

    def test_disconnected_library_has_reconnect_message_without_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            self.config(folder)
            with patch.dict(os.environ, {"EVERYTHING_AGENT_CONFIG_DIR": folder}), \
                 patch.object(spotify.urllib.request, "urlopen", side_effect=urllib.error.HTTPError(
                     "https://example.test", 412, "private-test-token", {}, None)):
                with self.assertRaises(RuntimeError) as result:
                    spotify.playlists()
                self.assertIn("Reconnect Spotify", str(result.exception))
                self.assertNotIn("private-test-token", str(result.exception))

    def test_invalid_playlist_never_starts_spotify(self):
        with patch.object(spotify.subprocess, "run") as run:
            for uri in ["https://example.test/playlist", "spotify:track:" + "a" * 22, "spotify:playlist:bad;echo x"]:
                with self.subTest(uri=uri), self.assertRaises(ValueError):
                    spotify.play(uri)
            run.assert_not_called()

    def test_playlist_targets_local_player_without_revealing_window(self):
        uri = "spotify:playlist:" + "a" * 22
        with patch.object(spotify.subprocess, "run", side_effect=[
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0, stdout="b true\n"),
            subprocess.CompletedProcess([], 0),
        ]) as run:
            self.assertEqual(spotify.play(uri), {"uri": uri})
            calls = [call.args[0] for call in run.call_args_list]
            self.assertEqual(calls[0][-1], "start")
            self.assertIn("org.mpris.MediaPlayer2.spotify", calls[-1])
            self.assertEqual(calls[-1][-3:], ["OpenUri", "s", uri])


class EqTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.previous = eq.STATE
        eq.STATE = Path(self.folder.name)

    def tearDown(self):
        eq.STATE = self.previous
        self.folder.cleanup()

    def test_corrupt_saved_curve_is_clamped_and_its_preset_recognized(self):
        (eq.STATE / "eq.json").write_text(json.dumps({"enabled": "yes", "bands": [30, -30, "x", None, True, 1.26, 0, 0, 0, 0]}))
        state = eq.load()
        self.assertEqual(state["bands"], [12, -12, 0, 0, 0, 1.5, 0, 0, 0, 0])
        self.assertTrue(state["enabled"])
        self.assertEqual(state["preset"], "custom")
        (eq.STATE / "eq.json").write_text(json.dumps({"bands": eq.PRESETS["voice"], "preset": "bass"}))
        self.assertEqual(eq.load()["preset"], "voice")
        (eq.STATE / "eq.json").write_text("[1, 2]")
        self.assertEqual(eq.load(), {"enabled": True, "preset": "flat", "bands": [0.0] * 10})

    def test_invalid_saved_preset_is_inferred_from_the_curve(self):
        for preset in ([], {}, 42, None):
            with self.subTest(preset=preset):
                (eq.STATE / "eq.json").write_text(json.dumps({"preset": preset, "bands": eq.PRESETS["voice"]}))
                self.assertEqual(eq.load()["preset"], "voice")

    def test_invalid_edits_change_nothing(self):
        state = eq.load()
        for args in [["set-band", "0", "1"], ["set-band", "11", "1"], ["set-band", "x", "1"], ["set-band", "2", "nan"],
                     ["set-band", "2", "12.5"], ["set-bands", "1"], ["preset", "loud"], ["enable", "maybe"], ["reset"]]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                eq.edit(state, args)
        self.assertEqual(state, eq.load())

    def test_edits_track_presets_and_power(self):
        state = eq.load()
        eq.edit(state, ["enable", "off"])
        eq.edit(state, ["preset", "bass"])
        self.assertTrue(state["enabled"], "choosing a preset turns the equalizer back on")
        eq.edit(state, ["set-band", "1", "2.26"])
        self.assertEqual(state["bands"][0], 2.5)
        self.assertEqual(state["preset"], "custom")
        eq.edit(state, ["set-bands"] + [str(v) for v in eq.PRESETS["bright"]])
        self.assertEqual(state["preset"], "bright")
        eq.edit(state, ["enable", "toggle"])
        self.assertFalse(state["enabled"])

    def test_preamp_offsets_the_largest_boost_and_off_is_flat(self):
        state = {"enabled": True, "preset": "custom", "bands": [-6, 0, 4.5, 0, 0, 0, 0, 2, 0, 0]}
        self.assertEqual(eq.target(state), (state["bands"], -4.5))
        self.assertEqual(eq.target({**state, "bands": [-3] + [0] * 9}), ([-3] + [0] * 9, 0.0))
        self.assertEqual(eq.target({**state, "enabled": False}), ([0.0] * 10, 0.0))

    def test_push_sends_every_band_and_the_preamp(self):
        with patch.object(eq.subprocess, "run") as run:
            eq.push(42, [1.5] + [0] * 9, -6)
        args = run.call_args.args[0]
        self.assertEqual(args[:4], ["pw-cli", "set-param", "42", "Props"])
        self.assertIn('"band_1:Gain" 1.50', args[4])
        self.assertIn('"band_10:Gain" 0.00', args[4])
        self.assertIn('"preamp:Mult" 0.501187', args[4])

    def live(self, gains, mult=1.0):
        return {**{f"band_{i}:Gain": g for i, g in enumerate(gains, 1)}, "preamp:Mult": mult}

    def test_apply_primes_a_fresh_sink_that_dropped_the_first_write(self):
        state = {"enabled": True, "preset": "custom", "bands": [0] * 5 + [6] + [0] * 4}
        readings = [(7, self.live([0] * 10)), (7, self.live([0] * 10)), (7, self.live(state["bands"], 10 ** (-6 / 20)))]
        with patch.object(eq, "sink", side_effect=readings), patch.object(eq, "push") as push, \
             patch.object(eq, "prime") as prime, patch.object(eq.time, "sleep"):
            self.assertTrue(eq.apply(state))
        self.assertEqual(push.call_count, 2)
        prime.assert_called_once()

    def test_apply_leaves_a_matching_sink_alone_and_reports_a_missing_one(self):
        state = eq.load()
        with patch.object(eq, "sink", return_value=(7, self.live([0] * 10))), patch.object(eq, "push") as push:
            self.assertTrue(eq.apply(state))
        push.assert_not_called()
        with patch.object(eq, "sink", return_value=None):
            self.assertIsNone(eq.apply(state))

    def test_route_moves_only_spotify_streams_that_are_elsewhere(self):
        sinks = [{"index": 3, "name": "alsa_output.headset"}, {"index": 9, "name": "listening_eq"}]
        inputs = [{"index": 20, "sink": 3, "properties": {"application.name": "Spotify"}},
                  {"index": 21, "sink": 9, "properties": {"application.name": "Spotify"}},
                  {"index": 22, "sink": 3, "properties": {"application.name": "Factorio"}}]
        replies = [subprocess.CompletedProcess([], 0, stdout=json.dumps(sinks)),
                   subprocess.CompletedProcess([], 0, stdout=json.dumps(inputs)), subprocess.CompletedProcess([], 0)]
        with patch.object(eq.subprocess, "run", side_effect=replies) as run:
            eq.route()
        self.assertEqual(run.call_args_list[-1].args[0], ["pactl", "move-sink-input", "20", "listening_eq"])
        self.assertEqual(run.call_count, 3)

    def test_status_without_pipewire_reports_unavailable(self):
        with tempfile.TemporaryDirectory() as empty:
            result = subprocess.run([sys.executable, str(PLUGIN / "eq"), "status"], capture_output=True, text=True,
                                    env={**os.environ, "PATH": empty, "XDG_STATE_HOME": self.folder.name})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(json.loads(result.stdout)["available"])

    def test_pipewire_graph_matches_the_helper(self):
        conf = EQ_CONF.read_text()
        bands = re.findall(r"name = band_(\d+) label = (\w+) control = \{ \"Freq\" = ([\d.]+)", conf)
        self.assertEqual([int(n) for n, _, _ in bands], list(range(1, 11)))
        self.assertEqual([float(f) for _, _, f in bands], [float(f) for f in eq.FREQUENCIES])
        self.assertIn("name = preamp label = linear", conf)
        self.assertIn(f'node.name = "{eq.SINK}"', conf)
        chain = re.findall(r'output = "(\w+):Out" input = "(\w+):In"', conf)
        self.assertEqual(chain, list(zip(["preamp"] + [f"band_{i}" for i in range(1, 10)], [f"band_{i}" for i in range(1, 11)])))

    def test_widget_players_target_the_sink(self):
        self.assertIn(f"--audio-device=pipewire/{eq.SINK}", (PLUGIN / "player").read_text())
        self.assertIn(f'"PULSE_SINK": "{eq.SINK}"', (PLUGIN / "mynoise").read_text())


if __name__ == "__main__":
    unittest.main()
