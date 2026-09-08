"""Chrome identity discovery uses disposable profiles and never launches Chrome."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('chrome_profile', str(ROOT / 'bin/bin/chrome-profile'))
spec = importlib.util.spec_from_loader(loader.name, loader)
chrome = importlib.util.module_from_spec(spec)
loader.exec_module(chrome)


class ChromeProfileTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='chrome-profile-test-')
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.state = self.home / '.config/google-chrome/Local State'
        self.state.parent.mkdir(parents=True)

    def write_cache(self, cache):
        self.state.write_text(json.dumps({'profile': {'info_cache': cache}}))

    def test_matches_signed_in_email_in_any_directory(self):
        self.write_cache({'Default': {'user_name': 'someone@example.invalid'},
                          'Profile 17': {'user_name': ' WORK@EXAMPLE.INVALID '}})
        self.assertEqual(chrome.find_profile(chrome.profile_cache(self.home), 'work@example.invalid'), 'Profile 17')
        self.assertIsNone(chrome.find_profile(chrome.profile_cache(self.home), 'missing@example.invalid'))

    def test_web_account_or_profile_label_does_not_count_as_chrome_sign_in(self):
        self.write_cache({'Default': {'name': 'work@example.invalid', 'user_name': ''}})
        self.assertIsNone(chrome.find_profile(chrome.profile_cache(self.home), 'work@example.invalid'))

    def test_retries_reuse_unsigned_profiles_without_overwriting_signed_in_accounts(self):
        self.write_cache({'Default': {'user_name': 'personal@example.invalid'},
                          'Profile 6': {'user_name': ''}})
        self.assertEqual(chrome.unsigned_profile(chrome.profile_cache(self.home), self.home), 'Profile 6')

    def test_new_profile_avoids_existing_directories_and_signed_in_profiles(self):
        (self.state.parent / 'Profile 1').mkdir()
        self.write_cache({'Default': {'user_name': 'personal@example.invalid'},
                          'Profile 2': {'user_name': 'work@example.invalid'}})
        self.assertEqual(chrome.unsigned_profile(chrome.profile_cache(self.home), self.home), 'Profile 3')

    def test_open_uses_detected_directory_and_preserves_chrome_files(self):
        self.write_cache({'Profile 9': {'user_name': 'work@example.invalid'}})
        before = self.state.read_bytes()
        with patch.object(chrome.Path, 'home', return_value=self.home), patch.object(chrome.sys, 'argv',
                ['chrome-profile', '--email', 'work@example.invalid', '--', '--new-tab', 'https://example.invalid']), \
                patch.object(chrome.subprocess, 'Popen') as launch:
            self.assertEqual(chrome.main(), 0)
        self.assertEqual(launch.call_args.args[0], ['google-chrome-stable', '--profile-directory=Profile 9', '--new-tab', 'https://example.invalid'])
        self.assertEqual(self.state.read_bytes(), before)

    def test_malformed_cache_never_launches_or_creates_a_profile(self):
        self.state.write_text('{partial write')
        with patch.object(chrome.Path, 'home', return_value=self.home), patch.object(chrome.sys, 'argv',
                ['chrome-profile', '--email', 'work@example.invalid', '--create']), \
                patch.object(chrome.subprocess, 'Popen') as launch, patch.object(chrome.sys, 'stderr'):
            self.assertEqual(chrome.main(), 3)
        launch.assert_not_called()
        self.assertEqual(self.state.read_text(), '{partial write')

    def test_work_link_discovers_moved_profile_and_retains_origin_restrictions(self):
        self.write_cache({'Profile 12': {'user_name': 'work@example.invalid'}})
        config = self.home / '.config/omarchy/work-widgets.env'
        config.parent.mkdir(parents=True)
        config.write_text('WORK_CHROME_PROFILE="Profile 1"\nWORK_CHROME_EMAIL=work@example.invalid\n'
                          'WORK_GITHUB_ORIGIN=https://github.example.invalid\nWORK_JIRA_ORIGIN=https://jira.example.invalid\n')
        config.chmod(0o600)
        commands = self.home / 'commands'
        commands.mkdir()
        ledger = self.home / 'launch'
        stub = commands / 'google-chrome-stable'
        stub.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$CHROME_TEST_LEDGER"\n')
        stub.chmod(0o755)
        env = dict(os.environ, HOME=str(self.home), WORK_WIDGETS_CONFIG=str(config),
                   CHROME_TEST_LEDGER=str(ledger), PATH=str(commands) + ':/usr/bin:/bin')
        result = subprocess.run([str(ROOT / 'bin/bin/open-work-url'), 'github'], env=env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        deadline = time.monotonic() + 3
        while not ledger.exists():
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.01)
        self.assertEqual(ledger.read_text().splitlines(),
                         ['--profile-directory=Profile 12', '--new-tab', 'https://github.example.invalid/pulls'])
        ledger.unlink()
        result = subprocess.run([str(ROOT / 'bin/bin/open-work-url'), 'https://unrelated.example.invalid'],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(ledger.exists())


if __name__ == '__main__':
    unittest.main()
