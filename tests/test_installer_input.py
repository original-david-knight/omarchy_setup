"""Installer children must read answers from the caller, not package manifests."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class InstallerInputTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='installer-input-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.commands = self.root / 'commands'
        self.commands.mkdir()
        for name in ('install_all.sh', 'install_agent_tools.sh', 'install_vscode_extensions.sh'):
            shutil.copy2(ROOT / name, self.root / name)
        (self.root / 'packages').mkdir()
        self.manifest = self.root / 'packages/agent-tools.json'
        shutil.copy2(ROOT / 'packages/agent-tools.json', self.manifest)
        self.packages = json.loads(self.manifest.read_text())
        self.ledger = self.root / 'ledger'
        self.first_package = next(iter(self.packages))
        self.env = dict(os.environ, PATH=f'{self.commands}:/usr/bin:/bin', INPUT_TEST_LEDGER=str(self.ledger),
                        INPUT_TEST_FIRST_PACKAGE=self.first_package,
                        INPUT_TEST_LAST_PACKAGE=next(reversed(self.packages)))
        self.command('mise', '''printf 'mise %s\\n' "$*" >> "$INPUT_TEST_LEDGER"
if [[ $1 == use && ( ${@: -1} == "$INPUT_TEST_FIRST_PACKAGE@latest" || ${@: -1} == "$INPUT_TEST_LAST_PACKAGE@latest" ) ]]; then
  printf 'Continue installing %s? [y/N] ' "${@: -1}"
  IFS= read -r answer || exit 41
  [[ $answer == y ]] || exit 42
fi
''')
        self.command('omarchy', 'printf "omarchy %s\\n" "$*" >> "$INPUT_TEST_LEDGER"')

    def command(self, name, body):
        path = self.commands / name
        path.write_text('#!/bin/bash\nset -eu\n' + body + '\n')
        path.chmod(0o755)

    def run_installer(self, script, answers='y\ny\n'):
        return subprocess.run(['/bin/bash', str(self.root / script)], cwd=self.root,
                              env=self.env, input=answers, capture_output=True, text=True, timeout=15)

    def assert_all_tools_installed(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        expected = []
        for package, binary in self.packages.items():
            expected.extend([f'mise use --global {package}@latest', f'omarchy mise install {package} {binary}'])
        expected.append('mise exec npm:playwright -- playwright install chromium')
        self.assertEqual(self.ledger.read_text().splitlines(), expected)

    def test_first_and_last_package_prompts_receive_answers_without_skipping_tools(self):
        self.assert_all_tools_installed(self.run_installer('install_agent_tools.sh'))

    def test_outer_install_loop_preserves_answers_and_runs_later_steps(self):
        (self.root / 'setup').mkdir()
        (self.root / 'setup/steps.json').write_text(json.dumps({'version': 1, 'install': [
            {'script': 'install_agent_tools.sh'}, {'script': 'finish.sh'}]}))
        (self.root / 'finish.sh').write_text('touch finished\n')
        self.assert_all_tools_installed(self.run_installer('install_all.sh'))
        self.assertTrue((self.root / 'finished').exists())

    def test_failed_tool_skips_its_wrapper_but_continues_other_tools(self):
        result = self.run_installer('install_agent_tools.sh', 'n\ny\n')
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        ledger = self.ledger.read_text().splitlines()
        self.assertEqual(ledger[0], f'mise use --global {self.first_package}@latest')
        self.assertNotIn(f'omarchy mise install {self.first_package} {self.packages[self.first_package]}', ledger)
        self.assertIn(f'omarchy mise install {next(reversed(self.packages))} {self.packages[next(reversed(self.packages))]}', ledger)
        self.assertIn('Agent tool failures:', result.stderr)

    def test_outer_loop_reports_multiple_failures_after_all_steps(self):
        (self.root / 'setup').mkdir()
        (self.root / 'setup/steps.json').write_text(json.dumps({'version': 1, 'install': [
            {'script': 'one.sh'}, {'script': 'two.sh'}, {'script': 'finish.sh'}]}))
        for name, code in [('one', 42), ('two', 7), ('finish', 0)]:
            (self.root / (name + '.sh')).write_text(f'echo {name} >> "$INPUT_TEST_LEDGER"\nexit {code}\n')
        result = self.run_installer('install_all.sh')
        self.assertEqual(result.returncode, 42)
        self.assertEqual(self.ledger.read_text().splitlines(), ['one', 'two', 'finish'])
        self.assertIn('one.sh (exit 42)', result.stderr)
        self.assertIn('two.sh (exit 7)', result.stderr)

    def test_unreadable_manifest_fails_before_any_install(self):
        self.manifest.write_text('{invalid JSON')
        result = self.run_installer('install_agent_tools.sh')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.ledger.exists())

    def test_extension_installer_keeps_caller_input_and_final_unterminated_line(self):
        (self.root / 'vscode').mkdir()
        (self.root / 'vscode/extensions.txt').write_text('# fixture\n\nfirst.extension\nlast.extension')
        self.command('code', '''IFS= read -r answer || exit 41
[[ $answer == y ]] || exit 42
printf '%s\\n' "$2" >> "$INPUT_TEST_LEDGER"
''')
        result = self.run_installer('install_vscode_extensions.sh')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.ledger.read_text().splitlines(), ['first.extension', 'last.extension'])

    def test_extension_failure_does_not_skip_remaining_extensions(self):
        (self.root / 'vscode').mkdir()
        (self.root / 'vscode/extensions.txt').write_text('first.extension\nlast.extension\n')
        self.command('code', '''printf '%s\\n' "$2" >> "$INPUT_TEST_LEDGER"
[[ $2 != first.extension ]] || exit 42
''')
        result = self.run_installer('install_vscode_extensions.sh')
        self.assertEqual(result.returncode, 42)
        self.assertEqual(self.ledger.read_text().splitlines(), ['first.extension', 'last.extension'])
        self.assertIn('first.extension (exit 42)', result.stderr)


if __name__ == '__main__':
    unittest.main()
