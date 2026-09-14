"""Offline checks for the task widget's completion API boundary."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest


PLUGIN = Path(__file__).resolve().parents[1] / "omarchy/.config/omarchy/plugins/david.tasks"


class CompleteTaskTests(unittest.TestCase):
    def complete(self, task_id, response, status=200, state=None, revision=None):
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def do_PATCH(self):
                requests.append({
                    "path": self.path,
                    "authorization": self.headers.get("Authorization"),
                    "content_type": self.headers.get("Content-Type"),
                    "revision": self.headers.get("X-Base-Revision"),
                    "body": json.loads(self.rfile.read(int(self.headers["Content-Length"]))),
                })
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(response.encode())

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as folder:
                Path(folder, "config.json").write_text(json.dumps({
                    "service_url": f"http://127.0.0.1:{server.server_port}/",
                    "token": "fixture-only",
                }))
                args = [str(PLUGIN / "complete"), task_id]
                if state is not None:
                    args.append(state)
                if revision is not None:
                    args.append(revision)
                result = subprocess.run(
                    args,
                    env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": folder},
                    text=True, capture_output=True, timeout=25,
                )
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        return result, requests

    def test_marks_only_requested_task_done_using_runtime_auth(self):
        result, requests = self.complete("t-example", '{"id":"t-example","done":true}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(requests, [{
            "path": "/api/tasks/t-example",
            "authorization": "Bearer fixture-only",
            "content_type": "application/json",
            "revision": None,
            "body": {"done": True},
        }])
        self.assertEqual(result.stdout + result.stderr, "")

    def test_id_is_encoded_as_one_path_segment(self):
        task_id = "t-space /?&#+"
        result, requests = self.complete(task_id, json.dumps({"id": task_id, "done": True}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(requests[0]["path"], "/api/tasks/t-space%20%2F%3F%26%23%2B")

    def test_reopen_sends_explicit_state_and_the_displayed_revision(self):
        result, requests = self.complete("t-example", '{"id":"t-example","done":false}',
                                         state="false", revision="7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(requests[0]["body"], {"done": False})
        self.assertEqual(requests[0]["revision"], "7")

    def test_completion_sends_the_displayed_revision(self):
        result, requests = self.complete("t-example", '{"id":"t-example","done":true}',
                                         state="true", revision="8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(requests[0]["body"], {"done": True})
        self.assertEqual(requests[0]["revision"], "8")

    def test_conflict_requests_refresh_without_retrying_the_write(self):
        result, requests = self.complete("t-example", '{}', status=409, state="false", revision="7")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refresh and try again", result.stderr)
        self.assertEqual(len(requests), 1)

    def test_http_failure_is_visible_without_echoing_response_data(self):
        for status in (401, 404, 409, 500):
            with self.subTest(status=status):
                result, requests = self.complete("t-example", '{"error":"fixture-only"}', status)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"HTTP {status}", result.stderr)
                self.assertNotIn("fixture-only", result.stdout + result.stderr)
                self.assertEqual(len(requests), 1)

    def test_success_requires_confirmation_of_requested_task(self):
        for response in ('{"id":"t-example","done":false}', '{"id":"t-other","done":true}',
                         '{}', 'not json'):
            with self.subTest(response=response):
                result, _ = self.complete("t-example", response)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("did not confirm", result.stderr)

    def test_invalid_arguments_fail_before_reading_configuration(self):
        for args in ([], [""], ["  "], ["t-example", "true", "1", "unexpected"]):
            with self.subTest(args=args):
                result = subprocess.run(
                    [str(PLUGIN / "complete"), *args], text=True, capture_output=True,
                    env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": "/nonexistent/task-test-config"},
                )
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stderr.strip(), "A task ID is required")

    def test_invalid_state_or_revision_fails_before_reading_configuration(self):
        for args in (["t-example", "toggle"], ["t-example", "false", "0"],
                     ["t-example", "true", "-1"], ["t-example", "true", "1.5"],
                     ["t-example", "true", ""], ["t-example", "true", "1\nX-Test: bad"]):
            with self.subTest(args=args):
                result = subprocess.run([str(PLUGIN / "complete"), *args], text=True, capture_output=True,
                    env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": "/nonexistent/task-test-config"})
                self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
