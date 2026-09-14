"""Synthetic API contracts for the Everything App bar widgets; no account data."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest


PLUGINS = Path(__file__).resolve().parents[1] / "omarchy/.config/omarchy/plugins"


def request(plugin, helper, response, args=(), status=200, responses=None):
    calls = []

    class Handler(BaseHTTPRequestHandler):
        def handle_request(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            calls.append({"method": self.command, "path": self.path,
                          "auth": self.headers.get("Authorization"),
                          "body": json.loads(body) if body else None})
            if self.headers.get("X-Base-Revision") is not None:
                calls[-1]["revision"] = self.headers["X-Base-Revision"]
            reply_status, reply = (responses[len(calls) - 1]
                if responses and len(calls) <= len(responses) else (status, response))
            self.send_response(reply_status)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(reply.encode())

        do_GET = handle_request
        do_POST = handle_request
        do_DELETE = handle_request

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
            result = subprocess.run([str(PLUGINS / plugin / helper), *args],
                env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": folder},
                text=True, capture_output=True, timeout=25)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    return result, calls


class WidgetFetchTests(unittest.TestCase):
    def test_task_board_retains_workflows_project_context_and_completed_history(self):
        tasks = [
            {"id": "t-one", "title": "Personal task", "source": "from: Jira DEMO-1", "done": False,
             "view": "action", "can_complete": True, "revision": 4, "project_name": "Demo",
             "next_action": "Complete", "item_key": "t-one", "assignee": "owner", "status": "open"},
            {"id": "i-one", "title": "Needs review", "view": "action", "can_complete": False,
             "revision": 9, "item_key": "DEMO-2", "next_action": "Review result", "status": "pending_approval"},
            {"id": "i-two", "title": "Agent working", "view": "waiting", "can_complete": False,
             "item_key": "DEMO-3", "assignee": "worker", "status": "in_progress"},
            {"id": "t-done", "title": "Old finished task", "view": "completed", "done": True,
             "can_complete": True, "revision": 5, "next_action": "Reopen"},
            {"id": "i-cancelled", "title": "Cancelled work", "view": "completed", "done": False,
             "can_complete": False, "status": "cancelled", "next_action": "Cancelled"},
        ]
        result, calls = request("david.tasks", "fetch", json.dumps({"tasks": tasks, "open": 3, "meta": "3 open"}))
        self.assertEqual(result.returncode, 0, result.stderr)
        board = json.loads(result.stdout)
        self.assertEqual(board["open"], 3)
        self.assertEqual(len(board["tasks"]), 5)
        for original, row in zip(tasks, board["tasks"]):
            for key, value in original.items():
                self.assertEqual(row[key], value, key)
        self.assertEqual(calls, [{"method": "GET", "path": "/api/tasks", "auth": "Bearer fixture-only", "body": None}])

    def test_missing_task_capability_does_not_enable_completion(self):
        result, _ = request("david.tasks", "fetch", '{"tasks":[{"id":"unknown","title":"Unknown"}]}')
        row = json.loads(result.stdout)["tasks"][0]
        self.assertIs(row["can_complete"], False)
        self.assertEqual(row["revision"], 0)

    def test_jira_preserves_query_order_and_all_linked_task_states(self):
        issues = [
            {"key": "DEMO-9", "summary": "First", "task": None},
            {"key": "DEMO-2", "summary": "Second", "task": {"id": "t-done", "done": True}},
            {"key": "DEMO-5", "summary": "Third", "task": {"id": "t-open", "done": False}},
        ]
        result, calls = request("david.jira-work", "fetch", json.dumps({"connected": True, "issues": issues}))
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)["issues"]
        self.assertEqual([i["key"] for i in output], [i["key"] for i in issues])
        self.assertEqual([i["title"] for i in output], [i["summary"] for i in issues])
        self.assertEqual([i["task"] for i in output], [i["task"] for i in issues])
        self.assertEqual(calls[0]["path"], "/api/jira")
        self.assertEqual(calls[0]["auth"], "Bearer fixture-only")

    def test_github_still_preserves_both_queues(self):
        pr = {"key": "demo/repo#3", "title": "Change", "url": "https://example.test/pr/3",
              "line": "review requested", "draft": True}
        result, calls = request("david.github-work", "fetch", json.dumps({"connected": True, "mine": [pr], "review": [pr]}))
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["mine"], [pr])
        self.assertEqual(data["review"], [pr])
        self.assertEqual(calls[0]["path"], "/api/github")


class JiraTaskTests(unittest.TestCase):
    def test_delete_reads_linked_task_and_sends_its_revision(self):
        task_id = "jira/demo task?#"
        for done in (False, True):
            with self.subTest(done=done):
                row = json.dumps({"id": task_id, "revision": 7, "can_complete": True, "done": done})
                result, calls = request("david.jira-work", "task", "", args=["DEMO-2", "delete", task_id],
                    responses=[(200, row), (204, "")])
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = {"path": "/api/tasks/jira%2Fdemo%20task%3F%23", "auth": "Bearer fixture-only", "body": None}
                self.assertEqual(calls, [{**expected, "method": "GET"},
                    {**expected, "method": "DELETE", "revision": "7"}])
                self.assertEqual(result.stdout + result.stderr, "")

    def test_delete_does_not_write_without_a_valid_personal_task(self):
        responses = ['not json', '{}',
            '{"id":"other","revision":2,"can_complete":true}',
            '{"id":"t-linked","revision":2,"can_complete":false}',
            '{"id":"t-linked","revision":2}',
            '{"id":"t-linked","revision":0,"can_complete":true}',
            '{"id":"t-linked","revision":1.5,"can_complete":true}',
            '{"id":"t-linked","revision":"2","can_complete":true}']
        for response in responses:
            with self.subTest(response=response):
                result, calls = request("david.jira-work", "task", response, args=["DEMO-2", "delete", "t-linked"])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([call["method"] for call in calls], ["GET"])
                self.assertIn("did not confirm", result.stderr)

    def test_delete_conflicts_and_failures_are_not_retried_or_echoed(self):
        row = '{"id":"t-linked","revision":2,"can_complete":true}'
        for status in (200, 202, 401, 409, 500):
            with self.subTest(status=status):
                result, calls = request("david.jira-work", "task", "", args=["DEMO-2", "delete", "t-linked"],
                    responses=[(200, row), (status, '{"error":"fixture-only"}')])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([call["method"] for call in calls], ["GET", "DELETE"])
                self.assertIn(f"HTTP {status}", result.stderr)
                self.assertNotIn("fixture-only", result.stdout + result.stderr)
                if status == 409:
                    self.assertIn("refresh and try again", result.stderr)

    def test_delete_read_failures_do_not_write(self):
        for status in (401, 403, 500):
            with self.subTest(status=status):
                result, calls = request("david.jira-work", "task", '{"error":"fixture-only"}',
                    args=["DEMO-2", "delete", "t-linked"], status=status)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([call["method"] for call in calls], ["GET"])
                self.assertIn(f"HTTP {status}", result.stderr)
                self.assertNotIn("fixture-only", result.stdout + result.stderr)

    def test_already_deleted_task_is_successful(self):
        row = '{"id":"t-linked","revision":2,"can_complete":true}'
        for responses in ([(404, "")], [(200, row), (404, "")]):
            with self.subTest(responses=responses):
                result, calls = request("david.jira-work", "task", "", args=["DEMO-2", "delete", "t-linked"],
                    responses=responses)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(calls), len(responses))

    def test_add_or_reopen_sends_only_key_and_requires_confirmed_open_task(self):
        response = json.dumps({"issues": [{"key": "DEMO-2", "task": {"id": "t-linked", "done": False}}]})
        result, calls = request("david.jira-work", "task", response, args=["DEMO-2"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [{"method": "POST", "path": "/api/jira/task",
                                 "auth": "Bearer fixture-only", "body": {"key": "DEMO-2"}}])
        self.assertEqual(result.stdout + result.stderr, "")

    def test_success_without_the_requested_open_task_is_rejected(self):
        responses = ['{}', 'not json', '{"issues":[]}',
            '{"issues":[{"key":"DEMO-2","task":null}]}',
            '{"issues":[{"key":"DEMO-2","task":{"id":"t-linked","done":true}}]}',
            '{"issues":[{"key":"DEMO-3","task":{"id":"t-linked","done":false}}]}']
        for response in responses:
            with self.subTest(response=response):
                result, _ = request("david.jira-work", "task", response, args=["DEMO-2"])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("did not confirm", result.stderr)

    def test_failed_post_is_not_retried_or_echoed(self):
        for status in (401, 404, 409, 500):
            with self.subTest(status=status):
                result, calls = request("david.jira-work", "task", '{"error":"fixture-only"}', args=["DEMO-2"], status=status)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(calls), 1)
                self.assertIn(f"HTTP {status}", result.stderr)
                self.assertNotIn("fixture-only", result.stdout + result.stderr)

    def test_invalid_arguments_fail_without_configuration(self):
        for args in ([], [""], ["  "], ["DEMO-2", "extra"], ["DEMO-2", "delete"],
                     ["DEMO-2", "delete", ""], ["DEMO-2", "delete", "  "],
                     ["DEMO-2", "create", "extra"], ["DEMO-2", "delete", "t-one", "extra"]):
            with self.subTest(args=args):
                result = subprocess.run([str(PLUGINS / "david.jira-work/task"), *args],
                    text=True, capture_output=True,
                    env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": "/nonexistent/jira-test-config"})
                self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
