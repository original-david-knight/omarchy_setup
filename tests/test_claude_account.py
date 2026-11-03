"""claude-account swaps logins in a scratch home and never touches the real one."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/bin/claude-account"
LATER = int(time.time() * 1000) + 3_600_000


def login(name, tier="default_claude_max_20x"):
    return {"accessToken": f"access-{name}", "refreshToken": f"refresh-{name}", "expiresAt": LATER,
            "refreshTokenExpiresAt": LATER, "rateLimitTier": tier, "subscriptionType": "max"}


def profile(email):
    return {"emailAddress": email, "displayName": email.split("@")[0]}


class ClaudeAccountTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.claude = self.home / ".claude"
        self.claude.mkdir()
        self.state = self.home / "state"
        self.bin = self.home / "bin"
        self.bin.mkdir()
        # The bar refresh is fire-and-forget; stub it so tests stay offline.
        stub = self.bin / "omarchy-agent-usage-update"
        stub.write_text('#!/bin/sh\necho "$@" >> "$HOME/refresh.log"\n')
        stub.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.state),
                        XDG_CACHE_HOME=str(self.home / ".cache"),
                        PATH=f"{self.bin}:{os.environ['PATH']}")
        self.env.pop("CLAUDE_CONFIG_DIR", None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, check=True):
        result = subprocess.run([str(SCRIPT), *args], env=self.env, capture_output=True, text=True)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def write_live(self, oauth, email):
        (self.claude / ".credentials.json").write_text(json.dumps(
            {"claudeAiOauth": oauth, "mcpOAuth": {"server": {"token": "keep"}}}))
        (self.home / ".claude.json").write_text(json.dumps({"numStartups": 7, "oauthAccount": profile(email)}))

    def write_slot(self, email, oauth):
        slots = self.state / "claude-accounts"
        slots.mkdir(parents=True, exist_ok=True)
        (slots / f"{email}.json").write_text(json.dumps(
            {"email": email, "claudeAiOauth": oauth, "oauthAccount": profile(email)}))

    def live(self):
        return (json.loads((self.claude / ".credentials.json").read_text()),
                json.loads((self.home / ".claude.json").read_text()))

    def test_use_swaps_login_and_keeps_everything_else(self):
        self.write_slot("a@example.com", login("a"))
        self.write_slot("b@example.com", login("b", "default_claude_max_5x"))
        self.write_live(login("a"), "a@example.com")
        probe_cache = self.home / ".cache/omarchy/agent-usage/claude-limits.json"
        probe_cache.parent.mkdir(parents=True)
        probe_cache.write_text('{"limits": "account a"}')

        self.run_cli("use", "b")

        # The bar re-probes at once, without account A's cached limits.
        self.assertFalse(probe_cache.exists())
        self.assertEqual((self.home / "refresh.log").read_text(), "--limits-only claude\n")

        credentials, config = self.live()
        self.assertEqual(credentials["claudeAiOauth"]["accessToken"], "access-b")
        self.assertEqual(credentials["mcpOAuth"], {"server": {"token": "keep"}})
        self.assertEqual(config["oauthAccount"]["emailAddress"], "b@example.com")
        self.assertEqual(config["numStartups"], 7)
        self.assertEqual(os.stat(self.claude / ".credentials.json").st_mode & 0o777, 0o600)

        listing = json.loads(self.run_cli("list", "--json").stdout)
        self.assertEqual(listing["active"], "b@example.com")
        self.assertEqual({a["email"]: a["plan"] for a in listing["accounts"]},
                         {"a@example.com": "Max 20x", "b@example.com": "Max 5x"})

    def test_switching_back_carries_tokens_refreshed_while_active(self):
        self.write_slot("a@example.com", login("a"))
        self.write_slot("b@example.com", login("b"))
        self.write_live(login("b"), "b@example.com")
        self.run_cli("use", "a")
        # Claude Code refreshes A's token while A is live.
        refreshed = dict(login("a"), accessToken="access-a2", refreshToken="refresh-a2")
        self.write_live(refreshed, "a@example.com")
        slots = self.state / "claude-accounts"
        # Identity of a refreshed token comes from the cache the profile
        # endpoint would fill; seed it so the test stays offline.
        key = hashlib.sha256(b"refresh-a2").hexdigest()
        (slots / ".identity-cache.json").write_text(json.dumps({key: {"email": "a@example.com", "at": time.time()}}))

        self.run_cli("use", "b")
        self.run_cli("use", "a")

        credentials, _ = self.live()
        self.assertEqual(credentials["claudeAiOauth"]["refreshToken"], "refresh-a2")

    def test_unidentified_login_is_never_filed_under_another_account(self):
        self.write_slot("a@example.com", login("a"))
        self.write_slot("b@example.com", login("b"))
        expired = dict(login("stranger"), expiresAt=1)
        self.write_live(expired, "a@example.com")

        self.run_cli("use", "b")

        slot_a = json.loads((self.state / "claude-accounts/a@example.com.json").read_text())
        self.assertEqual(slot_a["claudeAiOauth"]["refreshToken"], "refresh-a")

    def test_unknown_account_fails_without_changes(self):
        self.write_slot("a@example.com", login("a"))
        self.write_live(login("a"), "a@example.com")
        result = self.run_cli("use", "nobody", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.live()[0]["claudeAiOauth"]["accessToken"], "access-a")


if __name__ == "__main__":
    unittest.main()
