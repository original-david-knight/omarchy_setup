"""Offline checks for security-watch: level rules, status.json lifecycle, and the bar widget's QML."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

# The script has no .py suffix; keep its bytecode cache out of the stowed bin folder.
sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "bin/bin/security-watch"
PLUGIN = REPO / "omarchy/.config/omarchy/plugins/david.security"
loader = importlib.machinery.SourceFileLoader("security_watch", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
security_watch = importlib.util.module_from_spec(spec)
loader.exec_module(security_watch)

PAM = {
    "id": "CVE-2025-6020", "title": "pam_namespace path traversal", "severity": "high",
    "status": "affected", "component": "pam 1.7.1-1",
    "detail": "Local users can escalate through pam_namespace; no fixed Arch package yet.",
    "youShould": None, "references": ["https://security.archlinux.org/AVG-2901"],
}
ZDI = {
    "id": "ZDI-CAN-33367", "title": "Kernel netlink and tc local privilege escalation", "severity": "high",
    "status": "mitigated", "component": "linux 7.2.8-9-omarchy",
    "detail": "nlmon and act_pedit are blocked by /etc/modprobe.d/security-zdi-can-33367.conf.",
    "youShould": None, "references": ["https://lkml.iu.edu/2610.2/14824.html"],
}
CHROME_ACTION = {
    "summary": "Upgraded google-chrome to fix an exploited V8 bug",
    "command": "sudo pacman -Syu --noconfirm",
    "revert": "sudo pacman -U /var/cache/pacman/pkg/google-chrome-156.0.8078.40-1-x86_64.pkg.tar.zst",
}

FAKE_CLAUDE = textwrap.dedent(f"""\
    #!{sys.executable}
    import json, os, sys
    from pathlib import Path
    Path("prompt.txt").write_text(sys.stdin.read())
    Path("argv.json").write_text(json.dumps(sys.argv[1:]))
    mode = os.environ["FAKE_CLAUDE_MODE"]
    if mode == "crash":
        print("API Error: overloaded", file=sys.stderr)
        sys.exit(1)
    review = json.loads(os.environ["FAKE_CLAUDE_REVIEW"])
    Path("report.md").write_text("# Security review\\n")
    print(json.dumps({{
        "type": "result", "subtype": "success", "is_error": False, "num_turns": 41,
        "duration_ms": 812345, "session_id": "5f0c9a52-6f1e-4c1b-9a8e-2f9d1d0c7e11",
        "total_cost_usd": 3.21, "permission_denials": [], "terminal_reason": "completed",
        "result": json.dumps(review), "structured_output": review,
    }}))
    """)


def review(summary, findings, actions=()):
    return {"summary": summary, "findings": list(findings), "actions": list(actions)}


class LevelTest(unittest.TestCase):
    def test_levels(self):
        cases = [
            ([], [], "clear"),
            ([ZDI], [], "clear"),
            ([dict(PAM, status="not-affected"), dict(PAM, status="fixed")], [], "clear"),
            ([ZDI, PAM], [], "notice"),
            ([dict(PAM, status="exploitable")], [], "alert"),
            ([dict(ZDI, status="fixed", youShould="Remove the ZDI-CAN-33367 modprobe block.")], [], "alert"),
            ([PAM], [CHROME_ACTION], "alert"),
        ]
        for findings, actions, expected in cases:
            with self.subTest(findings=[f["status"] for f in findings], actions=len(actions)):
                self.assertEqual(security_watch.level(findings, actions), expected)


class RunTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        fakebin = self.tmp / "bin"
        fakebin.mkdir()
        tools = {
            "claude": FAKE_CLAUDE,
            "uname": "#!/bin/sh\necho 'Linux desk 7.2.8-9-omarchy #1 SMP PREEMPT_DYNAMIC x86_64 GNU/Linux'\n",
            "checkupdates": "#!/bin/sh\nexit 2\n",
        }
        for name, body in tools.items():
            (fakebin / name).write_text(body)
            (fakebin / name).chmod(0o755)
        self.env = {"PATH": str(fakebin), "HOME": str(self.tmp), "XDG_STATE_HOME": str(self.tmp / "state")}
        self.status_path = self.tmp / "state/security-watch/status.json"

    def run_watch(self, mode="ok", reply=None, command="run"):
        env = dict(self.env, FAKE_CLAUDE_MODE=mode, FAKE_CLAUDE_REVIEW=json.dumps(reply))
        return subprocess.run([sys.executable, str(SCRIPT), command], env=env,
                              capture_output=True, text=True, timeout=60)

    def status(self):
        return json.loads(self.status_path.read_text())

    def test_successful_run_writes_result(self):
        done = self.run_watch(reply=review("One high pam advisory has no fix yet.", [PAM, ZDI]))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout, "notice: One high pam advisory has no fix yet.\n")
        status = self.status()
        run_dir = Path(status["run"]["dir"])
        self.assertEqual(status, {
            "schema": 1,
            "run": {"state": "done", "startedAt": status["run"]["startedAt"],
                    "finishedAt": status["run"]["finishedAt"], "error": None, "dir": str(run_dir)},
            "result": {
                "checkedAt": status["run"]["startedAt"], "since": None, "level": "notice",
                "summary": "One high pam advisory has no fix yet.",
                "findings": [PAM, ZDI], "actions": [], "report": str(run_dir / "report.md"),
            },
        })
        self.assertEqual(run_dir.parent, self.tmp / "state/security-watch/runs")
        self.assertEqual((run_dir / "inventory/kernel.txt").read_text(),
                         "Linux desk 7.2.8-9-omarchy #1 SMP PREEMPT_DYNAMIC x86_64 GNU/Linux\n")
        notes = (run_dir / "inventory/NOTES.txt").read_text()
        self.assertIn("checkupdates.txt: exit 2: \n", notes)
        self.assertIn("packages.txt: pacman is not installed\n", notes)
        self.assertIn("This is the first review.", (run_dir / "prompt.txt").read_text())
        self.assertEqual(json.loads((run_dir / "claude.json").read_text())["structured_output"]["findings"],
                         [PAM, ZDI])

        shown = self.run_watch(command="status")
        self.assertEqual(shown.stdout.splitlines()[0], "notice: One high pam advisory has no fix yet.")

    def test_failed_claude_keeps_previous_result(self):
        self.run_watch(reply=review("Nothing pressing.", [PAM]))
        previous = self.status()["result"]
        done = self.run_watch(mode="crash")
        self.assertEqual(done.returncode, 1)
        status = self.status()
        self.assertEqual(status["result"], previous)
        self.assertEqual(status["run"]["state"], "failed")
        self.assertEqual(status["run"]["error"], "claude exited 1: API Error: overloaded")

    def test_malformed_review_is_a_failed_run(self):
        bad = review("Chrome is on fire.", [dict(PAM, severity="urgent")])
        done = self.run_watch(reply=bad)
        self.assertEqual(done.returncode, 1)
        status = self.status()
        self.assertIsNone(status["result"])
        self.assertEqual(status["run"]["state"], "failed")
        self.assertEqual(status["run"]["error"],
                         "review.findings[0].severity is 'urgent', not one of critical, high, medium, low")

    def test_since_advances_only_on_success(self):
        self.run_watch(reply=review("Nothing pressing.", [PAM]))
        first = self.status()["result"]["checkedAt"]
        time.sleep(1.1)
        self.run_watch(mode="crash")
        self.assertNotEqual(self.status()["run"]["startedAt"], first)
        time.sleep(1.1)
        done = self.run_watch(reply=review("Chrome patched for an exploited bug.", [PAM], [CHROME_ACTION]))
        self.assertEqual(done.returncode, 0, done.stderr)
        result = self.status()["result"]
        self.assertEqual(result["since"], first)
        self.assertEqual(result["level"], "alert")
        self.assertEqual(result["actions"], [CHROME_ACTION])
        prompt = (Path(self.status()["run"]["dir"]) / "prompt.txt").read_text()
        self.assertIn(f"published since {first} (the last successful check)", prompt)
        self.assertIn('"title": "pam_namespace path traversal"', prompt)


class PanelTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("qmllint"), "requires qmllint")
    def test_panel_lints(self):
        result = subprocess.run(["qmllint", "-I", "/usr/lib/qt6/qml", "Panel.qml"],
                                cwd=PLUGIN, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("omarchy"), "requires Omarchy")
    def test_manifest_validates(self):
        result = subprocess.run(["omarchy", "plugin", "validate", str(PLUGIN)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
