"""Assignment contracts against a synthetic service, never the live account."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import unittest
from urllib.parse import parse_qs, urlsplit

from test_widget_apis import PLUGINS, request


TASK = {"id": "task-one", "title": "Implement the issue", "project_id": "project-one",
        "assignee": "owner", "revision": 4, "status": "open"}
OPTIONS = {"projects": [
    {"id": "project-one", "key": "DEMO", "name": "Demo", "status": "active", "repo_path": "/demo"},
    {"id": "archived", "key": "OLD", "name": "Old", "status": "archived", "repo_path": "/old"},
    {"id": "personal", "key": "ME", "name": "Personal", "status": "active", "repo_path": " "},
], "agents": [
    {"name": "worker", "enabled": True, "availability": "available"},
    {"name": "paused", "enabled": False, "availability": "available"},
    {"name": "quota", "enabled": True, "availability": "unavailable"},
    {"name": "busy", "enabled": True, "availability": "busy"},
]}


def delegate(args, reply=TASK, status=200, responses=None):
    return request("david.tasks", "delegate", json.dumps(reply), args=args,
                   status=status, responses=responses)


class WidgetAssignmentTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("quickshell") and Path("/usr/share/omarchy/shell").is_dir(), "requires Omarchy Shell")
    def test_native_form_defaults_cancel_confirm_conflict_and_cancelled_preview(self):
        calls = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                query = parse_qs(urlsplit(self.path).query)
                calls.append({"method": "GET", "path": self.path})
                if self.path == "/api/projects":
                    reply = {**OPTIONS, "projects": OPTIONS["projects"] + [
                        {"id": "project-two", "key": "SECOND", "name": "Second", "status": "active", "repo_path": "/second"}]}
                elif self.path.startswith("/api/delegation?"):
                    key = query["key"][0]
                    if key == "slow":
                        time.sleep(0.2)
                    reply = {**TASK, "title": key}
                else:
                    reply = {"tasks": [], "issues": [], "mine": [], "review": []}
                self.respond(200, reply)

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                calls.append({"method": "POST", "path": self.path, "body": body})
                if body["key"] == "stale":
                    self.respond(409, {"error": "fixture-only"})
                else:
                    self.respond(200, {**TASK, "project_id": body["project_id"], "assignee": body["assignee"], "revision": 5})

            def respond(self, status, body):
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix="widget-assignment-") as folder:
                root = Path(folder)
                for name in ("Commons", "Ui", "Services"):
                    (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
                (root / "Plugins").symlink_to(PLUGINS, target_is_directory=True)
                config = root / ".config/everything-agent"
                config.mkdir(parents=True)
                (config / "config.json").write_text(json.dumps({
                    "service_url": f"http://127.0.0.1:{server.server_port}", "token": "fixture-only"}))
                (root / ".config/omarchy").mkdir()
                (root / ".config/omarchy/plugins").symlink_to(PLUGINS, target_is_directory=True)
                shutil.copyfile(Path(__file__).with_name("assignment-form.qml"), root / "shell.qml")
                result = subprocess.run(["quickshell", "-p", str(root), "--no-color"], capture_output=True,
                    text=True, timeout=15, env={**os.environ, "HOME": str(root),
                    "EVERYTHING_AGENT_CONFIG_DIR": str(config), "QT_QPA_PLATFORM": "offscreen"})
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        output = result.stdout + result.stderr
        self.assertIn("WIDGET ASSIGNMENT TEST PASSED", output, output)
        self.assertNotIn("TypeError", output)
        self.assertNotIn("ReferenceError", output)
        self.assertNotIn("Binding loop", output)
        writes = [c for c in calls if c["method"] == "POST"]
        self.assertEqual(len(writes), 3)
        self.assertEqual(writes[0], {"method": "POST", "path": "/api/delegation", "body": {
            "source": "github", "key": "demo/repo#3", "project_id": "project-two", "assignee": "worker", "revision": 4}})
        self.assertEqual(writes[1]["body"]["key"], "stale")
        self.assertEqual(writes[2], {"method": "POST", "path": "/api/delegation", "body": {
            "source": "task", "key": "second", "project_id": "project-one", "assignee": "worker", "revision": 4}})

    def test_preview_is_read_only_and_preserves_existing_project_and_revision(self):
        for source, key in (("task", "task/one?#"), ("jira", "DEMO-1"), ("github", "demo/repo#3")):
            with self.subTest(source=source):
                result, calls = delegate(["preview", source, key], responses=[
                    (200, json.dumps(TASK)), (200, json.dumps(OPTIONS))])
                self.assertEqual(result.returncode, 0, result.stderr)
                data = json.loads(result.stdout)
                self.assertEqual(data["task"], TASK)
                self.assertEqual(data["projects"], [{"value": "project-one", "label": "DEMO · Demo"}])
                self.assertEqual([a["value"] for a in data["agents"]], ["worker", "busy"])
                self.assertEqual([c["method"] for c in calls], ["GET", "GET"])
                self.assertEqual(parse_qs(urlsplit(calls[0]["path"]).query), {"source": [source], "key": [key]})
                self.assertEqual(calls[1]["path"], "/api/projects")
                self.assertNotIn("fixture-only", result.stdout + result.stderr)

    def test_new_source_preview_retains_configured_default_without_creating_task(self):
        result, calls = delegate(["preview", "jira", "DEMO-2"], responses=[
            (200, json.dumps({**TASK, "revision": 0, "assignee": "", "status": ""})),
            (200, json.dumps(OPTIONS))])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["task"]["project_id"], "project-one")
        self.assertTrue(all(c["method"] == "GET" for c in calls))

    def test_assign_posts_chosen_values_and_the_preview_revision_once(self):
        for source in ("task", "jira", "github"):
            for revision in (0, 4):
                with self.subTest(source=source, revision=revision):
                    reply = {**TASK, "assignee": "worker", "revision": revision + 1}
                    result, calls = delegate(["assign", source, "key?#", "project-one", "worker", str(revision)], reply)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout), reply)
                    self.assertEqual(calls, [{"method": "POST", "path": "/api/delegation",
                        "auth": "Bearer fixture-only", "body": {"source": source, "key": "key?#",
                        "project_id": "project-one", "assignee": "worker", "revision": revision}}])

    def test_conflicts_and_network_errors_do_not_retry_or_echo_response_bodies(self):
        for status in (202, 301, 400, 401, 403, 404, 409, 500):
            with self.subTest(status=status):
                result, calls = delegate(["assign", "jira", "DEMO-1", "project-one", "worker", "4"],
                                         {"error": "fixture-only"}, status)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(calls), 1)
                self.assertNotIn("fixture-only", result.stdout + result.stderr)
                if status == 409:
                    self.assertIn("Reload options", result.stderr)

    def test_invalid_confirmation_is_never_success(self):
        good = {**TASK, "assignee": "worker", "revision": 5}
        for reply in ({}, {**good, "assignee": "someone-else"}, {**good, "project_id": "wrong"},
                      {**good, "revision": 3}, {**good, "revision": True}, {**good, "id": ""}):
            with self.subTest(reply=reply):
                result, calls = delegate(["assign", "task", "task-one", "project-one", "worker", "4"], reply)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("did not confirm", result.stderr)
                self.assertEqual(len(calls), 1)

    def test_bad_preview_shape_is_rejected(self):
        result, _ = delegate(["preview", "jira", "DEMO-1"], responses=[
            (200, json.dumps(TASK)), (200, '{"projects":null,"agents":[]}')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("options could not be read", result.stderr)

    def test_invalid_args_do_not_read_configuration(self):
        for args in ([], ["preview", "unknown", "one"], ["preview", "jira", " "],
                     ["assign", "jira", "one", "project", "agent", "-1"],
                     ["assign", "jira", "one", "project", "agent", "1.5"]):
            with self.subTest(args=args):
                result = subprocess.run([str(PLUGINS / "david.tasks/delegate"), *args],
                    capture_output=True, text=True, env={**os.environ, "EVERYTHING_AGENT_CONFIG_DIR": "/nonexistent/widget-test"})
                self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
