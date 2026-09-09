"""GitHub review widget contract, using a disposable local API server."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest


PLUGIN = Path(__file__).resolve().parents[1] / "omarchy/.config/omarchy/plugins/david.github-work"


def call(helper, reply, args=(), status=200):
    calls = []

    class Handler(BaseHTTPRequestHandler):
        def handle_request(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            calls.append({"method": self.command, "path": self.path,
                          "auth": self.headers.get("Authorization"),
                          "body": json.loads(body) if body else None})
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(reply.encode())

        do_GET = handle_request
        do_POST = handle_request

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "config.json").write_text(json.dumps({
                "service_url": f"http://127.0.0.1:{server.server_port}/", "token": "fixture-only",
            }))
            result = subprocess.run([str(PLUGIN / helper), *args],
                env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": folder},
                text=True, capture_output=True, timeout=25)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    return result, calls


class GitHubReviewWidgetTests(unittest.TestCase):
    def test_fetch_preserves_ticket_and_both_queues(self):
        for status, busy in (("open", True), ("in_progress", True), ("pending_approval", False), ("done", False)):
            with self.subTest(status=status):
                pr = {"key": "demo/repo#3", "title": "Change", "url": "https://example.test/pr/3",
                      "line": "review requested", "draft": False}
                review = {**pr, "review": {"id": "ticket-one", "status": status, "reviewing": busy}}
                result, calls = call("fetch", json.dumps({"mine": [pr], "review": [review]}))
                self.assertEqual(result.returncode, 0, result.stderr)
                data = json.loads(result.stdout)
                self.assertEqual(data["mine"], [pr])
                self.assertEqual(data["review"], [review])
                self.assertEqual(calls[0]["path"], "/api/github")

    def test_older_response_remains_usable_without_a_ticket(self):
        result, _ = call("fetch", '{"review":[{"key":"demo/repo#3"}]}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("review", json.loads(result.stdout)["review"][0])

    def test_requests_new_or_existing_review_through_one_service_endpoint(self):
        for status, busy in (("open", True), ("in_progress", True), ("pending_approval", False)):
            with self.subTest(status=status):
                reply = json.dumps({"review": [{"key": "demo/repo#3", "review": {
                    "id": "ticket-one", "status": status, "reviewing": busy}}]})
                result, calls = call("review", reply, ["demo/repo#3"])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls, [{"method": "POST", "path": "/api/github/review",
                    "auth": "Bearer fixture-only", "body": {"key": "demo/repo#3"}}])
                self.assertEqual(result.stdout + result.stderr, "")

    def test_failures_are_not_retried_or_echoed(self):
        for status in (202, 401, 403, 404, 409, 500):
            with self.subTest(status=status):
                result, calls = call("review", '{"error":"fixture-only"}', ["demo/repo#3"], status)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(calls), 1)
                self.assertIn(f"HTTP {status}", result.stderr)
                self.assertNotIn("fixture-only", result.stdout + result.stderr)

    def test_unconfirmed_ticket_is_not_reported_as_success(self):
        for reply in ('{}', 'not json', '{"review":[{"key":"demo/repo#3"}]}',
                      '{"review":[{"key":"other","review":{"id":"one","status":"open","reviewing":true}}]}'):
            with self.subTest(reply=reply):
                result, _ = call("review", reply, ["demo/repo#3"])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("did not confirm", result.stderr)

    def test_invalid_arguments_do_not_read_configuration(self):
        for args in ([], [""], ["  "], ["one", "two"]):
            with self.subTest(args=args):
                result = subprocess.run([str(PLUGIN / "review"), *args], text=True, capture_output=True,
                    env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": "/nonexistent/widget-test"})
                self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
