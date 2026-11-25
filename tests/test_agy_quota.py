"""Unit tests for bin/bin/agy-quota in a scratch home without real network calls."""
import contextlib
import datetime
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

SCRIPT = Path(__file__).resolve().parents[1] / "bin/bin/agy-quota"


def future_iso(hours):
    instant = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=hours)
    return instant.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def quota_response(weekly_rem=0.8242, session_rem=0.9836, third_party_rem=1.0,
                   weekly_hours=126.3, session_hours=4.5, include_gemini=True):
    groups = []
    if include_gemini:
        groups.append({
            "displayName": "Gemini Models",
            "buckets": [
                {
                    "bucketId": "gemini-weekly",
                    "displayName": "Weekly Limit Remaining",
                    "refreshWindowLabel": "weekly",
                    "remainingFraction": weekly_rem,
                    "resetTime": future_iso(weekly_hours),
                },
                {
                    "bucketId": "gemini-5h",
                    "displayName": "Five Hour Limit Remaining",
                    "refreshWindowLabel": "5h",
                    "remainingFraction": session_rem,
                    "resetTime": future_iso(session_hours),
                },
            ],
        })
    third_party_buckets = [
        {
            "bucketId": "3p-weekly",
            "displayName": "Weekly Limit Remaining",
            "refreshWindowLabel": "weekly",
            "remainingFraction": third_party_rem,
        },
        {
            "bucketId": "3p-5h",
            "displayName": "Five Hour Limit Remaining",
            "refreshWindowLabel": "5h",
            "remainingFraction": 1.0,
        },
    ]
    if third_party_rem < 1.0:
        third_party_buckets[0]["resetTime"] = future_iso(100)
    groups.append({
        "displayName": "Claude and GPT models",
        "buckets": third_party_buckets,
    })
    return {"quotaSummary": {"groups": groups}}


class AgyQuotaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agy-quota-test-")
        self.home = Path(self.temp.name)
        self.agy_dir = self.home / ".gemini/antigravity-cli"
        self.agy_dir.mkdir(parents=True)
        self.cache = self.home / "cache"
        self.state = self.home / "state"
        self.env = {
            "HOME": str(self.home),
            "AGY_DIR": str(self.agy_dir),
            "XDG_CACHE_HOME": str(self.cache),
            "XDG_STATE_HOME": str(self.state),
        }
        self.code = runpy.run_path(str(SCRIPT))["main"]
        self.globals = self.code.__globals__
        self.write_oauth_file()

    def tearDown(self):
        self.temp.cleanup()

    def write_oauth_file(self, expired=False, with_refresh=True, email="user@example.com"):
        delta = -1 if expired else 1
        expiry = (datetime.datetime.now(datetime.timezone.utc)
                  + datetime.timedelta(hours=delta)).isoformat()
        payload = {
            "token": {
                "access_token": "synthetic-access",
                "refresh_token": "synthetic-refresh" if with_refresh else "",
                "expiry": expiry,
            },
            "id_token_email": email,
            "auth_method": "consumer",
        }
        (self.agy_dir / "antigravity-oauth-token").write_text(json.dumps(payload))

    def run_cli(self, args, fetcher, logins_override=None):
        output = io.StringIO()
        patches = {"fetch_quota_status": fetcher}
        if logins_override is not None:
            patches["logins"] = logins_override
        else:
            # Ensure tests read the scratch token file, never the host keyring.
            patches["subprocess"] = mock.Mock(check_output=mock.Mock(side_effect=OSError("no keyring")))
        with mock.patch.dict(os.environ, self.env), mock.patch.dict(self.globals, patches):
            with contextlib.redirect_stdout(output):
                self.code(args)
        return output.getvalue()

    def test_parses_gemini_windows_and_caches_privately(self):
        calls = []

        def service(token):
            calls.append(token)
            return quota_response(0.8242, 0.9836)

        first = json.loads(self.run_cli(["--json"], service))
        self.assertFalse(first["stale"])
        self.assertEqual(first["status"], "ok")
        self.assertEqual(
            [(row["title"], row["remainingFraction"], row["percent"]) for row in first["limits"]],
            [("Weekly", 0.8242, 0.1758), ("Session", 0.9836, 0.0164)],
        )
        # Second call reuses the cache without hitting the network.
        second = json.loads(self.run_cli(["--json"], service))
        self.assertEqual(calls, ["synthetic-access"])
        self.assertEqual(second["limits"], first["limits"])
        # --force bypasses the cache.
        self.run_cli(["--json", "--force"], service)
        self.assertEqual(len(calls), 2)

        files = [p for p in (self.cache / "agy-quota").glob("*.json")]
        self.assertEqual(len(files), 1)
        self.assertEqual(os.stat(files[0]).st_mode & 0o777, 0o600)
        self.assertNotIn("synthetic-access", files[0].read_text())
        self.assertNotIn("synthetic-refresh", files[0].read_text())

    def test_includes_touched_third_party_group_and_handles_omitted_zero_fraction(self):
        payload = quota_response(0.0, 0.5, third_party_rem=0.75)
        # Simulate proto3 omitting remainingFraction when 0.0.
        del payload["quotaSummary"]["groups"][0]["buckets"][0]["remainingFraction"]
        result = json.loads(self.run_cli(["--json"], lambda token: payload))
        self.assertEqual(
            [(row["title"], row["remainingFraction"], row["percent"]) for row in result["limits"]],
            [("Weekly", 0.0, 1.0), ("Session", 0.5, 0.5), ("Claude/GPT Weekly", 0.75, 0.25)],
        )

    def test_missing_gemini_group_is_rejected_not_substituted(self):
        result = json.loads(self.run_cli(["--json"], lambda token: quota_response(include_gemini=False)))
        self.assertTrue(result["stale"])
        self.assertEqual(result["limits"], [])
        self.assertIn("invalid Antigravity quota data", result["status"])

    def test_sync_usage_updates_agy_json_in_stock_order(self):
        usage_dir = self.state / "omarchy/agents/usage"
        usage_dir.mkdir(parents=True)
        record_path = usage_dir / "agy.json"
        record_path.write_text(json.dumps({
            "schemaVersion": 1,
            "id": "agy",
            "name": "Antigravity",
            "tierLabel": "Ultra",
            "todayPrompts": 12,
            "limits": [
                {"label": "Session (5-hour)", "title": "Session", "percent": 0.0, "resetsAt": ""},
                {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.0, "resetsAt": ""},
            ],
            "limitsStale": False,
            "limitsFetchedAt": 0,
        }))

        self.run_cli(["--json", "--sync-usage"], lambda token: quota_response(0.8242, 0.9836))
        synced = json.loads(record_path.read_text())
        self.assertEqual(synced["todayPrompts"], 12)
        self.assertEqual(synced["tierLabel"], "Ultra")
        self.assertEqual(
            [(row["title"], row["percent"]) for row in synced["limits"]],
            [("Session", 0.0164), ("Weekly", 0.1758)],
        )
        self.assertTrue(all(row["resetsAt"] for row in synced["limits"]))
        self.assertFalse(synced["limitsStale"])

    def test_rate_limit_backoff_and_stale_cache_drops_expired_resets(self):
        self.run_cli(["--json"], lambda token: quota_response(0.82, 0.98))
        calls = []

        def throttled(token):
            calls.append(token)
            raise urllib.error.HTTPError(
                "https://aicode.googleapis.com/v1alpha:fetchQuotaStatus",
                429, "secret-upstream-msg", {"Retry-After": "120"}, None,
            )

        stale = json.loads(self.run_cli(["--json", "--force"], throttled))
        self.assertTrue(stale["stale"])
        self.assertEqual(len(stale["limits"]), 2)
        self.assertGreaterEqual(stale["retryAt"] - int(time.time() * 1000), 119_000)
        self.assertNotIn("secret-upstream-msg", json.dumps(stale))

        # Backoff prevents immediate re-query without --force.
        self.run_cli(["--json"], throttled)
        self.assertEqual(len(calls), 1)

        # Mutate cached reset times into the past and verify expired limits are dropped.
        cache_file = next((self.cache / "agy-quota").glob("*.json"))
        saved = json.loads(cache_file.read_text())
        for row in saved["limits"]:
            row["resetsAt"] = "2020-01-01T00:00:00+00:00"
        cache_file.write_text(json.dumps(saved))

        after_reset = json.loads(self.run_cli(["--json"], throttled))
        self.assertTrue(after_reset["stale"])
        self.assertEqual(after_reset["limits"], [])

    def test_lapsed_token_keeps_cached_limits_stale_without_network(self):
        self.run_cli(["--json"], lambda token: quota_response(0.82, 0.98))
        self.write_oauth_file(expired=True, with_refresh=True)

        result = json.loads(self.run_cli(["--json", "--force"], lambda token: self.fail("should not fetch")))
        self.assertTrue(result["stale"])
        self.assertEqual(len(result["limits"]), 2)
        self.assertIn("lapsed", result["status"])


if __name__ == "__main__":
    unittest.main()
