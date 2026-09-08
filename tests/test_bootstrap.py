"""Exercise the USB bootstrap against disposable real Git repositories."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
PUBLIC_URL = 'https://github.com/original-david-knight/omarchy_setup.git'


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='usb-bootstrap-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'upstream'
        self.checkout = self.root / 'installed setup'
        self.ledger = self.root / 'wizard-output'
        self.config = self.root / 'gitconfig'
        self.config.write_text(
            f'[url "{self.source}"]\n\tinsteadOf = {PUBLIC_URL}\n'
            '[user]\n\tname = Bootstrap Test\n\temail = bootstrap@example.invalid\n'
            '[commit]\n\tgpgSign = false\n')
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=str(self.config),
                        OMARCHY_SETUP_DIR=str(self.checkout), BOOTSTRAP_TEST_LEDGER=str(self.ledger))
        self.commands = self.root / 'commands'
        self.commands.mkdir()
        self.command('sleep', 'exec /usr/bin/sleep 0.05\n')
        self.env['PATH'] = f'{self.commands}:' + os.environ['PATH']
        self.git('init', '--initial-branch=main', str(self.source))
        shutil.copy2(ROOT / 'bootstrap.sh', self.source / 'bootstrap.sh')
        self.publish('initial')

    def git(self, *args, cwd=None):
        return subprocess.run(['git', *args], cwd=cwd, env=self.env, check=True,
                              capture_output=True, text=True, timeout=15).stdout.strip()

    def publish(self, version, status=0):
        (self.source / 'setup.sh').write_text(
            '#!/bin/bash\nset -eu\n'
            f'printf "%s\\n" "{version}" "$PWD" "$@" > "$BOOTSTRAP_TEST_LEDGER"\n'
            f'exit {status}\n')
        self.git('add', '.', cwd=self.source)
        self.git('commit', '-m', version, cwd=self.source)

    def bootstrap(self, *args, script=None):
        return subprocess.run(['bash', str(script or ROOT / 'bootstrap.sh'), *args],
                              cwd=self.root, env=self.env, capture_output=True, text=True, timeout=15)

    def clone(self):
        self.git('clone', PUBLIC_URL, str(self.checkout))

    def command(self, name, body):
        path = self.commands / name
        path.write_text('#!/bin/bash\nset -eu\n' + body)
        path.chmod(0o755)

    def start_offline(self):
        self.source.rename(self.root / 'offline')
        log = self.root / 'bootstrap.log'
        with log.open('w') as stream:
            process = subprocess.Popen(['bash', str(ROOT / 'bootstrap.sh')], cwd=self.root,
                                       env=self.env, stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=True)
        def cleanup():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 5
        while 'Checking every 5 seconds' not in log.read_text():
            self.assertIsNone(process.poll(), log.read_text())
            self.assertLess(time.monotonic(), deadline, log.read_text())
            time.sleep(0.02)
        self.assertIsNone(process.poll())
        self.assertFalse(self.ledger.exists())
        return process, log

    def assert_stopped(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.ledger.exists(), result.stdout + result.stderr)

    def test_fresh_clone_launches_wizard_in_checkout_and_forwards_arguments(self):
        result = self.bootstrap('--profile', 'laptop', '--private-repo', '/path with spaces')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.ledger.read_text().splitlines(), [
            'initial', str(self.checkout), '--profile', 'laptop', '--private-repo', '/path with spaces'])
        self.assertEqual(self.git('config', '--get', 'remote.origin.url', cwd=self.checkout), PUBLIC_URL)

    def test_existing_checkout_is_refreshed_before_running_new_wizard(self):
        self.clone()
        self.publish('updated')
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.ledger.read_text().splitlines()[0], 'updated')
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=self.checkout),
                         self.git('rev-parse', 'HEAD', cwd=self.source))

    def test_running_bootstrap_can_itself_be_replaced_during_refresh(self):
        self.clone()
        (self.source / 'bootstrap.sh').write_text('#!/bin/bash\nexit 99\n')
        self.publish('new bootstrap')
        result = self.bootstrap(script=self.checkout / 'bootstrap.sh')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.ledger.read_text().splitlines()[0], 'new bootstrap')
        self.assertIn('exit 99', (self.checkout / 'bootstrap.sh').read_text())

    def test_ssh_origin_refreshes_via_public_https(self):
        self.clone()
        self.git('remote', 'set-url', 'origin',
                 'git@github.com:original-david-knight/omarchy_setup.git', cwd=self.checkout)
        self.publish('https refresh')
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.ledger.read_text().splitlines()[0], 'https refresh')

    def test_offline_clone_waits_then_runs_after_reconnection(self):
        process, log = self.start_offline()
        (self.root / 'offline').rename(self.source)
        self.assertEqual(process.wait(timeout=5), 0, log.read_text())
        self.assertEqual(self.ledger.read_text().splitlines()[0], 'initial')
        self.assertIn('Continuing setup', log.read_text())

    def test_interrupt_while_offline_cleans_temporary_checkout(self):
        process, log = self.start_offline()
        os.killpg(process.pid, signal.SIGINT)
        self.assertEqual(process.wait(timeout=5), 130, log.read_text())
        self.assertFalse(self.checkout.exists())
        self.assertFalse(self.ledger.exists())
        self.assertEqual(list(self.root.glob('.omarchy-setup-clone.*')), [])

    def test_offline_refresh_waits_without_running_cached_setup_then_updates(self):
        self.clone()
        original = self.git('rev-parse', 'HEAD', cwd=self.checkout)
        self.publish('reconnected')
        process, log = self.start_offline()
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=self.checkout), original)
        (self.root / 'offline').rename(self.source)
        self.assertEqual(process.wait(timeout=5), 0, log.read_text())
        self.assertEqual(self.ledger.read_text().splitlines()[0], 'reconnected')

    def test_edits_made_while_waiting_are_preserved(self):
        self.clone()
        self.publish('updated')
        process, log = self.start_offline()
        (self.checkout / 'setup.sh').write_text('local work\n')
        (self.root / 'offline').rename(self.source)
        self.assertEqual(process.wait(timeout=5), 1, log.read_text())
        self.assertFalse(self.ledger.exists())
        self.assertEqual((self.checkout / 'setup.sh').read_text(), 'local work\n')

    def test_reachable_clone_error_is_bounded_and_cleans_partial_checkout(self):
        self.command('git', '''for arg in "$@"; do
  if [[ $arg == clone ]]; then
    touch "${@: -1}/partial"
    exit 42
  fi
done
exec /usr/bin/git "$@"
''')
        result = self.bootstrap()
        self.assert_stopped(result)
        self.assertIn('GitHub is reachable', result.stderr)
        self.assertEqual(list(self.root.glob('.omarchy-setup-clone.*')), [])

    def test_interrupted_clone_recovers_without_partial_files(self):
        self.env['BOOTSTRAP_TEST_ROOT'] = str(self.root)
        self.command('git', '''if [[ ! -f $BOOTSTRAP_TEST_ROOT/disconnected ]]; then
  for arg in "$@"; do
    if [[ $arg == clone ]]; then
      touch "$BOOTSTRAP_TEST_ROOT/disconnected" "${@: -1}/partial"
      mv "$BOOTSTRAP_TEST_ROOT/upstream" "$BOOTSTRAP_TEST_ROOT/offline"
      exit 42
    fi
  done
fi
if [[ -d $BOOTSTRAP_TEST_ROOT/offline ]]; then
  # The transfer's immediate connectivity check sees the outage; the next
  # probe sees the restored repository, like reconnecting Wi-Fi.
  mv "$BOOTSTRAP_TEST_ROOT/offline" "$BOOTSTRAP_TEST_ROOT/upstream"
  exit 1
fi
exec /usr/bin/git "$@"
''')
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.checkout / 'partial').exists())
        self.assertEqual(self.ledger.read_text().splitlines()[0], 'initial')

    def test_local_edits_and_untracked_files_are_preserved(self):
        self.clone()
        for filename in ('setup.sh', 'personal-file'):
            with self.subTest(filename=filename):
                path = self.checkout / filename
                path.write_text('local work\n')
                self.assert_stopped(self.bootstrap())
                self.assertEqual(path.read_text(), 'local work\n')
                if filename == 'setup.sh':
                    self.git('restore', 'setup.sh', cwd=self.checkout)

    def test_local_commits_are_preserved_when_ahead_or_diverged(self):
        self.clone()
        (self.checkout / 'local-file').write_text('local commit\n')
        self.git('add', '.', cwd=self.checkout)
        self.git('commit', '-m', 'local work', cwd=self.checkout)
        original = self.git('rev-parse', 'HEAD', cwd=self.checkout)
        self.assert_stopped(self.bootstrap())
        self.publish('diverged upstream')
        self.assert_stopped(self.bootstrap())
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=self.checkout), original)

    def test_other_branch_and_detached_head_are_preserved(self):
        self.clone()
        self.git('switch', '-c', 'work', cwd=self.checkout)
        self.assert_stopped(self.bootstrap())
        self.assertEqual(self.git('branch', '--show-current', cwd=self.checkout), 'work')
        self.git('checkout', '--detach', cwd=self.checkout)
        self.assert_stopped(self.bootstrap())

    def test_existing_non_checkout_directory_is_preserved(self):
        self.checkout.mkdir()
        keep = self.checkout / 'keep'
        keep.write_text('preserve\n')
        self.assert_stopped(self.bootstrap())
        self.assertEqual(keep.read_text(), 'preserve\n')

    def test_foreign_origin_is_rejected(self):
        self.clone()
        self.git('remote', 'set-url', 'origin', str(self.source), cwd=self.checkout)
        self.assert_stopped(self.bootstrap())

    def test_wizard_exit_status_is_preserved(self):
        self.publish('pending checks', status=3)
        result = self.bootstrap()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)

    def test_help_does_not_create_checkout(self):
        result = self.bootstrap('--help')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.checkout.exists())
        self.assertFalse(self.ledger.exists())


if __name__ == '__main__':
    unittest.main()
