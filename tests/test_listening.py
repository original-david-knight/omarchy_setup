"""Offline checks for the listening widget's external service boundaries."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
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


if __name__ == "__main__":
    unittest.main()
