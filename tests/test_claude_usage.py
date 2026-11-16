import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import tempfile
import time
import unittest
from unittest import mock
import urllib.error

SCRIPT = Path(__file__).resolve().parents[1] / "bin/bin/claude-account"
TOKEN = "https://platform.claude.com/v1/oauth/token"
PROFILE = "https://api.anthropic.com/api/oauth/profile"
USAGE = "https://api.anthropic.com/api/oauth/usage"


def login(name, expired=False):
    now = int(time.time() * 1000)
    return {"accessToken": "access-" + name, "refreshToken": "refresh-" + name,
            "expiresAt": now - 1000 if expired else now + 3_600_000,
            "refreshTokenExpiresAt": now + 86_400_000, "scopes": ["user:profile"]}


def usage(general=53, fable=96):
    reset = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 86_400))
    return {"seven_day": {"utilization": general, "resets_at": reset},
            "limits": [{"kind": "weekly_scoped", "percent": fable, "resets_at": reset,
                        "scope": {"model": {"display_name": "Fable"}}}]}


class ClaudeUsageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.claude = self.home / ".claude"
        self.claude.mkdir()
        self.state = self.home / "state/claude-accounts"
        self.state.mkdir(parents=True)
        self.cache = self.home / "cache"
        self.env = {"HOME": str(self.home), "XDG_STATE_HOME": str(self.home / "state"),
                    "XDG_CACHE_HOME": str(self.cache)}
        self.code = runpy.run_path(str(SCRIPT))["main"]
        self.globals = self.code.__globals__
        self.live = self.claude / ".credentials.json"
        self.profile = self.home / ".claude.json"
        self.live.write_text(json.dumps({"claudeAiOauth": login("a"), "other": "keep"}))
        self.profile.write_text(json.dumps({"oauthAccount": {"emailAddress": "a@example.com"}, "other": "keep"}))
        self.slot("a@example.com", login("a"))
        self.slot("b@example.com", login("b"))

    def tearDown(self):
        self.temp.cleanup()

    def slot(self, email, oauth):
        (self.state / (email + ".json")).write_text(json.dumps({"email": email,
            "claudeAiOauth": oauth, "oauthAccount": {"emailAddress": email}}))

    def command(self, email, service):
        output = io.StringIO()
        with mock.patch.dict(os.environ, self.env), mock.patch.dict(self.globals, {"oauth_json": service}):
            with contextlib.redirect_stdout(output):
                self.code(["usage", email, "--json"])
        return json.loads(output.getvalue())

    def test_inactive_quota_is_cached_per_account_without_switching(self):
        before = (self.live.read_bytes(), self.profile.read_bytes())
        calls = []

        def service(url, token=None, body=None):
            calls.append((url, token))
            return usage(53, 96) if token == "access-b" else usage(20, 40)

        b = self.command("b", service)
        self.assertEqual([(row["title"], row["percent"]) for row in b["limits"]],
                         [("Weekly", .53), ("Fable Weekly", .96)])
        self.assertEqual(b["status"], "ok")
        self.command("b", service)
        self.assertEqual(calls, [(USAGE, "access-b")])
        a = self.command("a", service)
        self.assertEqual(a["limits"][0]["percent"], .2)
        self.assertEqual(calls[-1], (USAGE, "access-a"))
        self.assertEqual((self.live.read_bytes(), self.profile.read_bytes()), before)
        files = list((self.cache / "claude-accounts").glob("*.json"))
        self.assertEqual(len(files), 2)
        self.assertTrue(all(os.stat(path).st_mode & 0o777 == 0o600 for path in files))

    def test_expired_inactive_renews_verified_slot_only(self):
        self.slot("b@example.com", login("b", expired=True))
        before = (self.live.read_bytes(), self.profile.read_bytes())
        calls = []

        def service(url, token=None, body=None):
            calls.append((url, token, body))
            if url == TOKEN:
                self.assertEqual(body["refresh_token"], "refresh-b")
                self.assertEqual(body["scope"], "user:profile")
                return {"access_token": "access-b2", "refresh_token": "refresh-b2",
                        "expires_in": 28800, "account": {"email_address": "b@example.com"}}
            return usage()

        self.assertEqual(self.command("b", service)["status"], "ok")
        self.assertEqual([call[0] for call in calls], [TOKEN, USAGE])
        self.assertEqual(calls[-1][1], "access-b2")
        slot = json.loads((self.state / "b@example.com.json").read_text())
        self.assertEqual(slot["claudeAiOauth"]["refreshToken"], "refresh-b2")
        self.assertEqual((self.live.read_bytes(), self.profile.read_bytes()), before)

    def test_mismatched_identity_keeps_slot_and_live_files(self):
        self.slot("b@example.com", login("b", expired=True))
        slot_path = self.state / "b@example.com.json"
        before = (slot_path.read_bytes(), self.live.read_bytes(), self.profile.read_bytes())

        def service(url, token=None, body=None):
            return {"access_token": "access-b2", "refresh_token": "refresh-b2",
                    "expires_in": 28800, "account": {"email_address": "wrong@example.com"}}

        result = self.command("b", service)
        self.assertTrue(result["stale"])
        self.assertEqual(result["limits"], [])
        self.assertIn("different or unknown account", result["status"])
        self.assertEqual((slot_path.read_bytes(), self.live.read_bytes(), self.profile.read_bytes()), before)

    def test_rotation_persists_before_usage_failure_and_backoff(self):
        self.slot("b@example.com", login("b", expired=True))
        before = (self.live.read_bytes(), self.profile.read_bytes())
        calls = []

        def service(url, token=None, body=None):
            calls.append(url)
            if url == TOKEN:
                return {"access_token": "access-b2", "refresh_token": "refresh-b2",
                        "expires_in": 28800, "account": {"email_address": "b@example.com"}}
            raise urllib.error.HTTPError(url, 429, "secret details", {"Retry-After": "120"}, None)

        first = self.command("b", service)
        self.assertTrue(first["stale"])
        self.assertEqual(first["limits"], [])
        self.assertGreaterEqual(first["retryAt"] - int(time.time() * 1000), 119_000)
        self.assertEqual(json.loads((self.state / "b@example.com.json").read_text())
                         ["claudeAiOauth"]["refreshToken"], "refresh-b2")
        self.command("b", service)
        self.assertEqual(calls, [TOKEN, USAGE])
        self.assertNotIn("secret details", json.dumps(first))
        self.assertEqual((self.live.read_bytes(), self.profile.read_bytes()), before)

    def test_early_401_renews_once_and_verifies_profile_when_identity_omitted(self):
        before = self.live.read_bytes()
        calls = []

        def service(url, token=None, body=None):
            calls.append((url, token))
            if url == USAGE and token == "access-b":
                raise urllib.error.HTTPError(url, 401, "", {}, None)
            if url == TOKEN:
                return {"access_token": "access-b2", "expires_in": 28800}
            if url == PROFILE:
                return {"account": {"email": "b@example.com"}}
            return usage()

        self.assertEqual(self.command("b", service)["status"], "ok")
        self.assertEqual(calls, [(USAGE, "access-b"), (TOKEN, None),
                                 (PROFILE, "access-b2"), (USAGE, "access-b2")])
        oauth = json.loads((self.state / "b@example.com.json").read_text())["claudeAiOauth"]
        self.assertEqual(oauth["accessToken"], "access-b2")
        self.assertEqual(oauth["refreshToken"], "refresh-b")
        self.assertEqual(self.live.read_bytes(), before)

    def test_token_endpoint_403_reports_block_without_claiming_expired_sign_in(self):
        self.slot("b@example.com", login("b", expired=True))
        before = (self.state / "b@example.com.json").read_bytes()

        def service(url, token=None, body=None):
            raise urllib.error.HTTPError(url, 403, "Cloudflare page", {}, None)

        result = self.command("b", service)
        self.assertIn("blocked token renewal", result["status"])
        self.assertNotIn("sign in", result["status"].lower())
        self.assertEqual((self.state / "b@example.com.json").read_bytes(), before)

    def test_invalid_payload_and_elapsed_reset_never_show_full_allowance(self):
        calls = []

        def invalid(url, token=None, body=None):
            calls.append(url)
            return {"seven_day": {"utilization": "bad"}}

        failed = self.command("b", invalid)
        self.assertTrue(failed["stale"])
        self.assertEqual(failed["limits"], [])
        self.assertIn("invalid usage data", failed["status"])
        self.assertGreater(failed["retryAt"], int(time.time() * 1000))
        self.command("b", invalid)
        self.assertEqual(calls, [USAGE])

        self.command("a", lambda url, token=None, body=None: usage())
        cache = next(path for path in (self.cache / "claude-accounts").glob("*.json")
                     if json.loads(path.read_text())["email"] == "a@example.com")
        saved = json.loads(cache.read_text())
        expired = "2020-01-01T00:00:00Z"
        for limit in saved["limits"]:
            limit["resetsAt"] = expired
        saved.update(status="Anthropic is rate limiting usage checks.",
                     retryAt=int(time.time() * 1000) + 60000)
        cache.write_text(json.dumps(saved))
        stale = self.command("a", lambda url, token=None, body=None: self.fail("backoff was ignored"))
        self.assertTrue(stale["stale"])
        self.assertEqual(stale["limits"], [])


if __name__ == "__main__":
    unittest.main()
