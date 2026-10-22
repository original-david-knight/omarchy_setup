"""Exercise reboot decisions with firmware, authentication, and reboot stubs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'bin/bin/reboot-to-windows'
ENTRIES = '''Boot0001* Windows Boot Manager HD(1,GPT,wrong-partition)/bootmgfw.efi
Boot000A* Windows Boot Manager HD(1,GPT,7B363525-5FE7-4457-B8AC-CF38E474E7CF)/bootmgfw.efi
'''


class RebootToWindowsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.log = self.directory / 'calls.jsonl'
        self.env = dict(os.environ, PATH=f'{self.directory}:/usr/bin:/bin',
                        REBOOT_TEST_LOG=str(self.log), REBOOT_TEST_ENTRIES=ENTRIES)
        stub = '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['REBOOT_TEST_LOG'], 'a') as log:
    log.write(json.dumps([name, *args]) + '\\n')
if name == 'omarchy':
    print(os.environ.get('REBOOT_TEST_CHOICE', 'Yes'))
    sys.exit(int(os.environ.get('REBOOT_TEST_MENU_STATUS', '0')))
if name == 'efibootmgr':
    assert args == ['-v'], 'Firmware writes must go through authentication'
    print(os.environ['REBOOT_TEST_ENTRIES'])
if name in ('pkexec', 'systemctl'):
    sys.exit('Reboot actions must use noninteractive sudo')
if name == 'sudo':
    assert args[0] == '-n', 'Password prompts are not allowed'
    if args[1] == 'efibootmgr':
        assert args == ['-n', 'efibootmgr', '--bootnext', '000A']
        sys.exit(int(os.environ.get('REBOOT_TEST_AUTH_STATUS', '0')))
    assert args == ['-n', 'systemctl', 'reboot']
    sys.exit(int(os.environ.get('REBOOT_TEST_REBOOT_STATUS', '0')))
'''
        for name in ('omarchy', 'efibootmgr', 'sudo', 'pkexec', 'systemctl', 'notify-send'):
            path = self.directory / name
            path.write_text(stub)
            path.chmod(0o755)

    def run_command(self, *args, reply=''):
        result = subprocess.run([str(SCRIPT), *args], env=self.env, input=reply,
                                capture_output=True, text=True, timeout=5)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_gui_yes_selects_correct_partition_then_reboots_without_password_prompt(self):
        result, calls = self.run_command('--gui')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [
            ['omarchy', 'menu', 'select', 'Reboot to Windows. Are you sure?', 'Yes', 'No', '--', '--width', '420'],
            ['efibootmgr', '-v'],
            ['sudo', '-n', 'efibootmgr', '--bootnext', '000A'],
            ['sudo', '-n', 'systemctl', 'reboot'],
        ])

    def test_gui_no_or_escape_never_changes_firmware(self):
        for choice, status in [('No', '0'), ('', '1')]:
            with self.subTest(choice=choice):
                self.log.unlink(missing_ok=True)
                self.env.update(REBOOT_TEST_CHOICE=choice, REBOOT_TEST_MENU_STATUS=status)
                result, calls = self.run_command('--gui')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([call[0] for call in calls], ['omarchy'])

    def test_denied_passwordless_access_reports_error_without_reboot(self):
        self.env['REBOOT_TEST_AUTH_STATUS'] = '126'
        result, calls = self.run_command('--gui')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(calls[-2:], [
            ['sudo', '-n', 'efibootmgr', '--bootnext', '000A'],
            ['notify-send', '--urgency=critical', 'Reboot to Windows', 'Could not select Windows for the next boot.'],
        ])
        self.assertNotIn(['sudo', '-n', 'systemctl', 'reboot'], calls)

    def test_missing_windows_entry_reports_error_without_changing_firmware(self):
        self.env['REBOOT_TEST_ENTRIES'] = 'Boot0001* Windows Boot Manager HD(1,GPT,wrong-partition)'
        result, calls = self.run_command('--gui')
        self.assertEqual(result.returncode, 1)
        self.assertEqual([call[0] for call in calls], ['omarchy', 'efibootmgr', 'notify-send'])
        self.assertIn('No Windows Boot Manager firmware entry found', calls[-1][-1])

    def test_failed_reboot_reports_that_windows_is_selected(self):
        self.env['REBOOT_TEST_REBOOT_STATUS'] = '1'
        result, calls = self.run_command('--gui')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(calls[-1], [
            'notify-send', '--urgency=critical', 'Reboot to Windows',
            'Windows is selected for the next boot, but the reboot failed.',
        ])

    def test_dry_run_only_reads_firmware(self):
        result, calls = self.run_command('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [['efibootmgr', '-v']])
        self.assertIn('dry run: would set BootNext=000A and reboot', result.stdout)

    def test_cli_confirmation_controls_firmware_write(self):
        for reply in ('n\n', '\n', '', 'y\n'):
            with self.subTest(reply=reply):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_command(reply=reply)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = [['efibootmgr', '-v']]
                if reply == 'y\n':
                    expected += [['sudo', '-n', 'efibootmgr', '--bootnext', '000A'],
                                 ['sudo', '-n', 'systemctl', 'reboot']]
                self.assertEqual(calls, expected)


if __name__ == '__main__':
    unittest.main()
