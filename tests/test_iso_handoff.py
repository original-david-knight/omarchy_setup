"""Verify installed handoff files and completion/retry behavior without a desktop."""
import importlib.util
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('personal_setup', ROOT / 'iso/personal_setup.py')
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)


class StagingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='iso-staging-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.target = self.root / 'target'
        (self.target / 'etc').mkdir(parents=True)
        self.home = self.target / 'home/tester'
        self.home.mkdir(parents=True)
        (self.target / 'etc/passwd').write_text(
            f'tester:x:{os.getuid()}:{os.getgid()}::/home/tester:/bin/bash\n')
        self.payload = self.root / 'payload'
        self.payload.mkdir()
        for name in ('omarchy-personal-setup', 'post-boot.hook', 'omarchy-personal-setup.desktop'):
            shutil.copy2(ROOT / 'iso' / name, self.payload / name)
        shutil.copy2(ROOT / 'bootstrap.sh', self.payload / 'bootstrap.sh')
        shutil.copy2(ROOT / 'scripts/install_backgrounds.py', self.payload / 'install_backgrounds.py')
        shutil.copytree(ROOT / 'backgrounds', self.payload / 'backgrounds')
        self.ctx = SimpleNamespace(target=self.target, username='tester', defer_provisioning=False)
        patcher = patch.object(staging, 'PAYLOAD', self.payload)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_direct_install_gets_public_payload_and_owned_hook(self):
        staging.stage_personal_setup(self.ctx)
        hook = self.home / staging.HOOK
        self.assertEqual(hook.read_bytes(), (self.payload / 'post-boot.hook').read_bytes())
        self.assertEqual(hook.stat().st_uid, os.getuid())
        self.assertEqual(hook.stat().st_mode & 0o777, 0o755)
        bootstrap = self.target / 'usr/local/share/omarchy-setup/bootstrap.sh'
        self.assertEqual(bootstrap.read_bytes(), (ROOT / 'bootstrap.sh').read_bytes())
        self.assertEqual(sorted(p.name for p in bootstrap.parent.iterdir()), ['backgrounds', 'bootstrap.sh', 'install_backgrounds.py'])
        background = self.home / '.local/state/omarchy/current/background'
        self.assertTrue(background.is_file())
        self.assertFalse(background.readlink().is_absolute())
        self.assertEqual(background.lstat().st_uid, os.getuid())
        self.assertEqual(len(list((self.home / '.config/omarchy/backgrounds').glob('*/*'))), 7)
        self.assertFalse((self.home / '.local/state/omarchy-setup/backgrounds.json').exists())
        self.assertTrue((self.target / 'etc/skel' / staging.HOOK).is_file())
        self.assertFalse((self.home / 'omarchy_setup').exists())

    def test_deferred_owner_gets_skeleton_hook_without_creating_an_account(self):
        self.ctx.defer_provisioning = True
        self.ctx.username = ''
        shutil.rmtree(self.home)
        (self.target / 'etc/passwd').unlink()
        staging.stage_personal_setup(self.ctx)
        self.assertTrue((self.target / 'etc/skel' / staging.HOOK).is_file())
        self.assertEqual(list((self.target / 'home').iterdir()), [])
        shutil.copytree(self.target / 'etc/skel', self.home, symlinks=True)
        self.assertTrue((self.home / '.local/state/omarchy/current/background').is_file())

    def test_staging_keeps_unrelated_configuration(self):
        config = self.home / '.config/omarchy/hooks/post-boot.d/existing'
        config.parent.mkdir(parents=True)
        config.write_text('keep this hook\n')
        staging.stage_personal_setup(self.ctx)
        staging.stage_personal_setup(self.ctx)
        self.assertEqual(config.read_text(), 'keep this hook\n')

    def test_live_root_is_rejected_before_any_write(self):
        self.ctx.target = Path('/')
        with self.assertRaisesRegex(RuntimeError, 'not the live system'):
            staging.stage_personal_setup(self.ctx)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='iso-launcher-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.commands = self.root / 'commands'
        self.commands.mkdir()
        self.state = self.root / 'state'
        self.complete = self.state / 'omarchy-setup/iso/complete'
        self.ledger = self.root / 'ledger'
        self.home = self.root / 'home'
        self.home.mkdir()
        self.background_installer = self.root / 'install_backgrounds.py'
        self.env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.state),
                        PATH=f'{self.commands}:/usr/bin:/bin', HANDOFF_LEDGER=str(self.ledger))
        self.bootstrap = self.root / 'fixture-bootstrap.sh'
        self.bootstrap.write_text('#!/bin/bash\nprintf "%s\\n" "$@" >> "$HANDOFF_LEDGER"\nexit "${HANDOFF_STATUS:-0}"\n')
        self.launcher = self.root / 'launcher'
        self.launcher.write_text((ROOT / 'iso/omarchy-personal-setup').read_text().replace(
            'bootstrap=/usr/local/share/omarchy-setup/bootstrap.sh',
            'bootstrap=' + shlex.quote(str(self.bootstrap))).replace(
            '/usr/local/share/omarchy-setup/install_backgrounds.py', str(self.background_installer)).replace(
            '/usr/local/share/omarchy-setup/backgrounds', str(ROOT / 'backgrounds')))
        self.command('pgrep', 'exit 1')
        self.command('omarchy-launch-terminal', 'printf "terminal %s\\n" "$*" >> "$HANDOFF_LEDGER"')

    def command(self, name, body):
        path = self.commands / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def run_launcher(self, *args):
        return subprocess.run(['bash', str(self.launcher), *args], env=self.env,
                              input='\n', capture_output=True, text=True, timeout=10)

    def test_success_marks_complete_and_later_logins_do_nothing(self):
        result = self.run_launcher('--profile', 'laptop')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.ledger.read_text().splitlines(), ['--profile', 'laptop'])
        self.assertTrue(self.complete.is_file())
        self.assertEqual(self.complete.stat().st_mode & 0o777, 0o600)
        self.ledger.unlink()
        self.assertEqual(self.run_launcher('--launch').returncode, 0)
        self.assertFalse(self.ledger.exists())

    def test_failed_pending_and_interrupted_setup_can_retry(self):
        for status in ('1', '3', '130'):
            with self.subTest(status=status):
                self.env['HANDOFF_STATUS'] = status
                result = self.run_launcher()
                self.assertEqual(result.returncode, int(status), result.stdout + result.stderr)
                self.assertFalse(self.complete.exists())
        self.env['HANDOFF_STATUS'] = '0'
        self.assertEqual(self.run_launcher().returncode, 0)
        self.assertTrue(self.complete.is_file())

    def test_finish_repairs_completed_setup_without_running_installers_or_resetting_progress(self):
        progress = self.state / 'omarchy-setup/wizard/progress.json'
        progress.parent.mkdir(parents=True)
        progress.write_text('{"fixture": "completed progress"}\n')
        result = subprocess.run([str(ROOT / 'setup.sh'), '--finish'], env=self.env,
                                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.complete.is_file())
        self.assertEqual(progress.read_text(), '{"fixture": "completed progress"}\n')
        self.assertEqual(self.run_launcher('--launch').returncode, 0)
        self.assertFalse(self.ledger.exists())

    def test_boot_hook_requests_an_interactive_terminal(self):
        result = self.run_launcher('--launch')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.ledger.read_text().strip(),
                         'terminal /usr/local/bin/omarchy-personal-setup')
        self.assertFalse(self.complete.exists())

    def test_bundled_background_is_selected_even_when_bootstrap_cannot_finish(self):
        shutil.copy2(ROOT / 'scripts/install_backgrounds.py', self.background_installer)
        self.env['HANDOFF_STATUS'] = '3'
        result = self.run_launcher()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertTrue((self.home / '.local/state/omarchy/current/background').is_file())
        self.assertTrue((self.home / '.local/state/omarchy-setup/backgrounds.json').is_file())
        self.assertFalse(self.complete.exists())

    def test_second_launcher_does_not_run_during_active_setup(self):
        import fcntl
        lock = self.complete.parent / 'launcher.lock'
        lock.parent.mkdir(parents=True)
        with lock.open('w') as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.ledger.exists())
        self.assertFalse(self.complete.exists())


if __name__ == '__main__':
    unittest.main()
