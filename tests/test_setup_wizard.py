import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('setup_wizard', ROOT / 'scripts/setup_wizard.py')
wizard = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = wizard
spec.loader.exec_module(wizard)


class FakeUI(wizard.UI):
    def __init__(self, choices=()):
        self.choices = iter(choices)
        self.messages = []

    def say(self, text=''):
        self.messages.append(text)

    def choose(self, prompt, options, default):
        choice = next(self.choices)
        assert choice in options, (choice, options)
        return choice


class FakeRunner:
    def __init__(self, root, codes=()):
        self.env = dict(os.environ)
        self.root = root
        self.codes = iter(codes)
        self.calls = []
        self.modes = []

    def run(self, argv, cwd, label, interactive=True, stream=False):
        self.calls.append((list(map(str, argv)), label))
        self.modes.append((label, interactive, stream))
        log = self.root / (label + '.log')
        log.write_text('fixture output\n')
        return wizard.Result(next(self.codes, 0), log)


class WizardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='wizard-test-')
        self.root = Path(self.temporary.name)
        self.home = self.root / 'home'
        self.public = self.root / 'public'
        self.private = self.root / 'private'
        for path in [self.home, self.public, self.private]:
            path.mkdir()
        self.state = wizard.State(self.root / 'state')
        self.addCleanup(self.state.close)
        self.addCleanup(self.temporary.cleanup)

    def make(self, ui=None, runner=None, **kwargs):
        return wizard.Wizard(self.public, self.private, self.home, self.state,
                             ui or FakeUI(), runner or FakeRunner(self.root), **kwargs)

    def steps(self):
        for name in ['one.sh', 'two.sh']:
            (self.public / name).write_text('#!/bin/bash\nexit 0\n')
        return [{'id': 'one', 'label': 'One', 'script': 'one.sh'}, {'id': 'two', 'label': 'Two', 'script': 'two.sh'}]

    def test_failures_continue_without_questions_and_resume_retries_only_failures(self):
        steps = self.steps()
        (self.public / 'three.sh').write_text('exit 0\n')
        steps.append({'id': 'three', 'label': 'Three', 'script': 'three.sh'})
        first = FakeRunner(self.root, [42, 0, 7])
        engine = self.make(runner=first)
        engine.run_group('Public', 'public', self.public, steps)
        self.assertEqual(len(first.calls), 3)
        self.assertEqual(engine.summary(), 1)
        report = json.loads((self.state.directory / 'report.json').read_text())
        self.assertEqual(report['failed'], 2)
        self.assertEqual([s['code'] for s in report['steps']], [42, 0, 7])
        self.assertEqual((self.state.directory / 'report.json').stat().st_mode & 0o777, 0o600)
        second = FakeRunner(self.root)
        self.make(runner=second).run_group('Public', 'public', self.public, steps)
        self.assertEqual([call[1] for call in second.calls], ['public.one', 'public.three'])

    def test_revisit_clears_future_private_steps_not_reached_on_this_run(self):
        for name in ['public.one', 'public.two', 'private.build', 'private.verify']:
            self.state.record(name, 'digest', 'done')
        self.state.invalidate('public.two', ['public.one', 'public.two'])
        self.assertEqual(set(self.state.data['steps']), {'public.one'})

    def test_changed_input_invalidates_that_step_and_its_dependents(self):
        steps = self.steps()
        (self.public / 'packages.txt').write_text('one\n')
        steps[0]['inputs'] = ['packages.txt']
        self.make().run_group('Public', 'public', self.public, steps)
        (self.public / 'packages.txt').write_text('two\n')
        runner = FakeRunner(self.root)
        self.make(runner=runner).run_group('Public', 'public', self.public, steps)
        self.assertEqual(len(runner.calls), 2)

    def test_profile_change_keeps_installs_and_reapplies_configuration(self):
        steps = self.steps()
        steps[1]['profile_sensitive'] = True
        self.make(profile='desktop').run_group('Public', 'public', self.public, steps)
        runner = FakeRunner(self.root)
        self.make(runner=runner, profile='laptop').run_group('Public', 'public', self.public, steps)
        self.assertEqual([call[1] for call in runner.calls], ['public.two'])

    def test_failed_prerequisite_skips_only_dependents_and_lists_them(self):
        steps = self.steps()
        steps[1]['requires'] = ['public.one']
        steps.append({'id': 'independent', 'label': 'Independent', 'script': 'two.sh'})
        runner = FakeRunner(self.root, [42, 0])
        engine = self.make(runner=runner)
        engine.run_group('Public', 'public', self.public, steps)
        self.assertEqual([call[1] for call in runner.calls], ['public.one', 'public.independent'])
        self.assertEqual(self.state.data['steps']['public.two']['status'], 'blocked')
        self.assertEqual(engine.summary(), 1)
        self.assertIn('public.one', self.state.data['steps']['public.two']['reason'])

    def test_pending_consent_skips_dependents_without_claiming_install_failure(self):
        steps = self.steps()
        steps[0]['pending_exit_codes'] = [3]
        steps[1]['requires'] = ['public.one']
        engine = self.make(runner=FakeRunner(self.root, [3]))
        engine.run_group('Install', 'public', self.public, steps)
        self.assertEqual(engine.summary(), 3)
        self.assertEqual(self.state.data['steps']['public.two']['status'], 'blocked')
        self.assertEqual(self.state.data['steps']['public.two']['code'], 3)

    def test_ordinary_install_exit_three_is_a_failure(self):
        engine = self.make(runner=FakeRunner(self.root, [3]))
        engine.run_group('Install', 'public', self.public, self.steps()[:1])
        self.assertEqual(engine.summary(), 1)
        self.assertEqual(self.state.data['steps']['public.one']['status'], 'failed')

    def test_saved_upfront_choice_is_applied_on_resume_without_another_question(self):
        step = {'id': 'choice', 'label': 'Allow fixture option?', 'kind': 'consent', 'env': 'OMARCHY_FIXTURE_OPTION'}
        self.make(FakeUI(['y'])).run_group('Prepare', 'private', self.private, [step])
        runner = FakeRunner(self.root)
        self.make(runner=runner).run_group('Prepare', 'private', self.private, [step])
        self.assertEqual(runner.env['OMARCHY_FIXTURE_OPTION'], '1')

    def test_declining_manual_step_does_not_acknowledge_it(self):
        engine = self.make(FakeUI(['n']))
        step = {'id': 'slack', 'label': 'Slack', 'kind': 'manual', 'ack': 'slack', 'allow_later': True}
        engine.run_group('Accounts', 'private', self.private, [step])
        self.assertFalse(engine.ack_path.exists())
        self.assertEqual(self.state.data['steps']['private.slack']['status'], 'pending')
        self.make(FakeUI(['d'])).run_group('Accounts', 'private', self.private, [step])
        self.assertEqual(json.loads(engine.ack_path.read_text()), ['slack'])
        self.assertEqual(engine.ack_path.stat().st_mode & 0o777, 0o600)

    def test_github_gate_requires_actual_repository_access(self):
        (self.home / '.ssh').mkdir()
        (self.home / '.ssh/key.pub').write_text('ssh-ed25519 public-test-key\n')
        step = {'id': 'github', 'label': 'GitHub', 'kind': 'github', 'key': str(self.home / '.ssh/key.pub'), 'repo': 'git@example.invalid:private.git'}
        engine = self.make(FakeUI(['c', 'p']), FakeRunner(self.root, [128]))
        with patch.object(engine, 'probe', return_value=False):
            with self.assertRaises(wizard.Pause):
                engine.run_group('GitHub', 'handoff', self.public, [step])
        self.assertEqual(self.state.data['steps']['handoff.github']['status'], 'pending')
        engine = self.make(FakeUI(['c']), FakeRunner(self.root, [0]))
        with patch.object(engine, 'probe', return_value=False):
            engine.run_group('GitHub', 'handoff', self.public, [step])
        self.assertEqual(self.state.data['steps']['handoff.github']['status'], 'done')

    def test_final_report_never_treats_pending_or_malformed_as_ready(self):
        (self.private / 'verify.sh').write_text('#!/bin/bash\n')
        step = {'id': 'verify', 'label': 'Readiness', 'script': 'verify.sh', 'kind': 'verify', 'always': True}
        for code, output in [(3, json.dumps({'version': 1, 'failed': 0, 'pending': 1, 'checks': [{'status': 'pending', 'label': 'Account', 'remedy': 'Sign in'}]})), (0, 'not JSON')]:
            runner = FakeRunner(self.root)
            runner.run = lambda *a, **k: wizard.Result(code, self.root / 'verify.log', output)
            engine = self.make(runner=runner)
            engine.run_group('Readiness', 'private', self.private, [step])
            self.assertEqual(engine.summary(), 3 if code == 3 else 1)
            self.assertNotEqual(self.state.data['steps']['private.verify']['status'], 'done')

    def test_probe_checks_profile_identity_instead_of_file_presence(self):
        source = self.root / 'profiles.json'
        source.write_text(json.dumps({'profile': {'user_name': 'wrong@example.invalid'}}))
        probe = {'file': str(source), 'json_equals': {'path': ['profile', 'user_name'], 'value': 'right@example.invalid'}}
        self.assertFalse(self.make().probe(probe))
        source.write_text(json.dumps({'profile': {'user_name': 'right@example.invalid'}}))
        self.assertTrue(self.make().probe(probe))

    def test_state_is_private_and_concurrent_run_is_rejected(self):
        self.state.record('public.one', 'digest', 'done')
        self.assertEqual(self.state.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.state.directory.stat().st_mode & 0o777, 0o700)
        with self.assertRaises(wizard.WizardError):
            wizard.State(self.state.directory)

    def test_plan_preview_and_noninteractive_error_execute_nothing(self):
        env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.home / '.local/state'))
        command = [str(ROOT / 'setup.sh'), '--private-repo', str(self.private)]
        result = subprocess.run(command + ['--plan'], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('will load after', result.stdout)
        self.assertFalse((self.home / '.local').exists())
        result = subprocess.run(command, env=env, text=True, capture_output=True, stdin=subprocess.DEVNULL)
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.home / '.local').exists())

    def test_resume_remembers_private_checkout_and_profile(self):
        ui = FakeUI(['p', 'p'])
        location = self.root / 'another-private-checkout'
        env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.home / '.local/state'))
        for variable in ('OMARCHY_SETUP_PROFILE', 'OMARCHY_PRIVATE_SETUP_DIR', 'WORKSPACE_DIR'):
            env.pop(variable, None)
        with patch.dict(os.environ, env, clear=True), patch.object(wizard, 'UI', return_value=ui), patch('sys.stdin.isatty', return_value=True), patch('sys.stdout.isatty', return_value=True), patch('os.geteuid', return_value=1000):
            with patch.object(sys, 'argv', ['setup.sh', '--private-repo', str(location), '--profile', 'laptop']):
                self.assertEqual(wizard.main(), 3)
            with patch.object(sys, 'argv', ['setup.sh']):
                self.assertEqual(wizard.main(), 3)
        summaries = [message for message in ui.messages if 'Private checkout:' in message]
        self.assertEqual(len(summaries), 2)
        self.assertTrue(all(str(location) in message and 'Profile: laptop' in message for message in summaries))

    def test_restart_backs_up_progress_and_keeps_choices(self):
        directory = self.root / 'restart-state'
        original = wizard.State(directory)
        original.data.update(profile='laptop', private_repo='/a/private/checkout')
        original.record('public.one', 'digest', 'done')
        original.close()
        restarted = wizard.State(directory, restart=True)
        try:
            self.assertEqual(restarted.data['steps'], {})
            self.assertEqual(restarted.data['profile'], 'laptop')
            self.assertEqual(restarted.data['private_repo'], '/a/private/checkout')
            backups = list(directory.glob('*.bak'))
            self.assertEqual(len(backups), 1)
            self.assertIn('public.one', json.loads(backups[0].read_text())['steps'])
        finally:
            restarted.close()

    def test_real_script_public_to_private_handoff(self):
        # Tiny scripts exercise the complete engine; no actual installers/auth run.
        def script(root, name, body):
            (root / name).write_text('#!/bin/bash\nset -eu\n' + body)
        script(self.public, 'install.sh', 'echo public >> "$HOME/ledger"\n')
        script(self.public, 'setup_workspace.sh', 'test "$1" = --private-only\necho preparation >> "$HOME/ledger"\n')
        script(self.public, 'after_github_key_configured.sh', 'echo handoff >> "$HOME/ledger"\n')
        script(self.private, 'private.sh', 'echo private >> "$HOME/ledger"\n')
        report = json.dumps({'version': 1, 'failed': 0, 'pending': 0, 'checks': []})
        script(self.private, 'verify.sh', "printf '%s\\n' '" + report + "'\n")
        (self.public / 'setup').mkdir()
        (self.public / 'setup/steps.json').write_text(json.dumps({'version': 1, 'install': [{'id': 'install', 'label': 'Install', 'script': 'install.sh'}], 'configure': []}))
        (self.private / 'setup-wizard.json').write_text(json.dumps({'version': 1, 'work_repo': 'fixture', 'steps': [{'id': 'install', 'label': 'Private', 'script': 'private.sh'}, {'id': 'verify', 'label': 'Verify', 'script': 'verify.sh', 'kind': 'verify'}]}))
        (self.home / '.ssh').mkdir()
        (self.home / '.ssh/id_github.pub').write_text('public-test-key\n')
        runner = wizard.Runner(self.root / 'logs', dict(os.environ, HOME=str(self.home)))
        for _ in range(2):
            engine = self.make(runner=runner)
            with patch.object(engine, 'probe', return_value=True):
                self.assertEqual(engine.run(), 0)
        self.assertEqual((self.home / 'ledger').read_text().splitlines(), ['preparation', 'public', 'handoff', 'private'])
        for log in (self.root / 'logs').iterdir():
            self.assertEqual(log.stat().st_mode & 0o777, 0o600)

    def fixture_plan(self, public, private=None):
        (self.public / 'setup').mkdir(exist_ok=True)
        (self.public / 'setup/steps.json').write_text(json.dumps({'version': 1, 'install': public, 'configure': []}))
        (self.public / 'setup_workspace.sh').write_text('exit 0\n')
        (self.public / 'after_github_key_configured.sh').write_text('exit 0\n')
        if private is not None:
            (self.private / 'setup-wizard.json').write_text(json.dumps({'version': 1, 'steps': private}))
        (self.home / '.ssh').mkdir(exist_ok=True)
        (self.home / '.ssh/id_github.pub').write_text('ssh-ed25519 fixture\n')

    def test_all_preparation_precedes_installs_and_manual_checks_are_last(self):
        public = self.steps()
        public[1]['phase'] = 'prepare'
        private = [
            {'id': 'opens', 'label': 'Open fixture', 'kind': 'manual', 'ack': 'fixture'},
            {'id': 'install', 'label': 'Private install', 'script': 'install.sh'},
            {'id': 'choice', 'label': 'Allow fixture option?', 'kind': 'consent', 'env': 'OMARCHY_FIXTURE_OPTION'},
            {'id': 'prepare', 'label': 'Private preparation', 'script': 'prepare.sh', 'phase': 'prepare'},
        ]
        self.fixture_plan(public, private)
        runner = FakeRunner(self.root)
        events = []
        base_run = runner.run
        def run(*args, **kwargs):
            events.append(args[2])
            return base_run(*args, **kwargs)
        runner.run = run
        ui = FakeUI(['y', 'd'])
        base_choose = ui.choose
        def choose(prompt, options, default):
            events.append('consent' if 'y' in options else 'opening-check')
            if 'd' in options:
                self.assertTrue((self.state.directory / 'report.json').is_file())
                self.assertIn('Setup report:', '\n'.join(ui.messages))
            return base_choose(prompt, options, default)
        ui.choose = choose
        engine = self.make(ui, runner)
        with patch.object(engine, 'probe', return_value=True):
            self.assertEqual(engine.run(), 0)
        self.assertEqual(events, ['public.two', 'handoff.clone', 'consent', 'private.prepare',
                                  'public.one', 'handoff.workspaces', 'private.install', 'opening-check'])
        self.assertEqual(runner.env['OMARCHY_FIXTURE_OPTION'], '1')
        self.assertTrue(all(interactive == (label in ('public.two', 'handoff.clone', 'private.prepare'))
                            for label, interactive, _ in runner.modes))

    def test_private_checkout_failure_does_not_prevent_public_installs(self):
        public = self.steps()
        self.fixture_plan(public)
        runner = FakeRunner(self.root, [42, 0, 0])
        engine = self.make(runner=runner)
        with patch.object(engine, 'probe', return_value=True):
            self.assertEqual(engine.run(), 1)
        self.assertEqual([call[1] for call in runner.calls], ['handoff.clone', 'public.one', 'public.two'])

    def test_public_only_failures_do_not_report_success(self):
        self.fixture_plan(self.steps())
        runner = FakeRunner(self.root, [42, 0])
        self.assertEqual(self.make(runner=runner, public_only=True).run(), 1)
        self.assertEqual(len(runner.calls), 2)

    def test_deferred_checks_are_pending_without_opening_apps_or_asking(self):
        engine = self.make(defer_checks=True)
        step = {'id': 'opens', 'label': 'Open fixture', 'kind': 'manual', 'ack': 'fixture',
                'actions': [{'label': 'Open fixture', 'argv': ['do-not-run'], 'launch': True}]}
        with patch.object(engine, 'action') as action:
            engine.run_group('Final', 'private', self.private, [step])
        action.assert_not_called()
        self.assertFalse(engine.ack_path.exists())
        self.assertEqual(engine.summary(), 3)

    def test_deferred_browser_profiles_do_not_prompt_and_record_the_parent(self):
        (self.private / 'profiles.json').write_text(json.dumps([
            {'directory': 'Default', 'email': 'fixture@example.invalid'}]))
        engine = self.make(defer_checks=True)
        step = {'id': 'browser_profiles', 'label': 'Chrome profiles', 'kind': 'browser_profiles', 'file': 'profiles.json'}
        engine.run_group('Final', 'private', self.private, [step])
        self.assertEqual(self.state.data['steps']['private.browser_profiles']['status'], 'pending')
        self.assertEqual(self.state.data['steps']['private.browser.0']['status'], 'pending')
        self.assertEqual(engine.summary(), 3)

    def test_invalid_inputs_are_reported_and_independent_installs_continue(self):
        steps = self.steps()
        steps[0]['inputs'] = ['../outside']
        runner = FakeRunner(self.root)
        engine = self.make(runner=runner)
        engine.run_group('Install', 'public', self.public, steps)
        self.assertEqual([call[1] for call in runner.calls], ['public.two'])
        self.assertEqual(engine.summary(), 1)

    def test_successful_verifier_does_not_erase_failed_installs(self):
        steps = self.steps()
        steps[1]['kind'] = 'verify'
        runner = FakeRunner(self.root)
        responses = iter([wizard.Result(42, self.root / 'failed.log'),
                          wizard.Result(0, self.root / 'verify.log', json.dumps({'version': 1, 'failed': 0, 'pending': 0, 'checks': []}))])
        runner.run = lambda *a, **kw: next(responses)
        engine = self.make(runner=runner)
        engine.run_group('Public', 'public', self.public, steps)
        self.assertEqual(engine.summary(), 1)

    def test_missing_public_key_is_reported_without_aborting_other_steps(self):
        engine = self.make()
        engine.run_group('Preparation', 'handoff', self.public, [
            {'id': 'github', 'label': 'GitHub', 'kind': 'github', 'key': str(self.home / 'absent.pub'), 'repo': 'fixture'},
            self.steps()[0]])
        self.assertEqual(self.state.data['steps']['handoff.github']['status'], 'blocked')
        self.assertEqual(self.state.data['steps']['handoff.one']['status'], 'done')

    def test_unattended_runner_closes_input_and_has_no_controlling_terminal(self):
        runner = wizard.Runner(self.root / 'unattended-logs', dict(os.environ))
        child = '''import os,sys
print('INPUT=' + repr(sys.stdin.read()), flush=True)
try:
    os.open('/dev/tty', os.O_RDWR)
except OSError:
    print('NO_CONTROLLING_TTY', flush=True)
print('MISE=' + os.environ['MISE_YES'], flush=True)
print('GIT=' + os.environ['GIT_TERMINAL_PROMPT'], flush=True)
sys.exit(42)
'''
        with contextlib.redirect_stdout(io.StringIO()) as output:
            result = runner.run([sys.executable, '-c', child], self.root, 'unattended', interactive=False, stream=True)
        self.assertEqual(result.code, 42)
        self.assertIn("INPUT=''", output.getvalue())
        self.assertIn('NO_CONTROLLING_TTY', output.getvalue())
        self.assertIn('MISE=1', output.getvalue())
        self.assertIn('GIT=0', output.getvalue())
        self.assertEqual(result.log.read_text(), output.getvalue())

    def test_interrupt_exit_still_stops_the_installation_pass(self):
        runner = FakeRunner(self.root, [130, 0])
        with self.assertRaises(wizard.Pause) as stopped:
            self.make(runner=runner).run_group('Public', 'public', self.public, self.steps())
        self.assertEqual(stopped.exception.code, 130)
        self.assertEqual(len(runner.calls), 1)

    def terminal_driver(self, command, on_output):
        driver = self.root / 'driver.py'
        driver.write_text(f'''import sys
sys.path.insert(0, {str(ROOT / "scripts")!r})
from setup_wizard import Runner
import os
runner = Runner(__import__('pathlib').Path({str(self.root / 'terminal-logs')!r}), dict(os.environ))
try:
    result = runner.run({command!r}, {str(self.root)!r}, 'terminal')
    print('RESULT=' + str(result.code), flush=True)
except KeyboardInterrupt:
    print('INTERRUPTED', flush=True)
''')
        master, slave = pty.openpty()
        process = subprocess.Popen([sys.executable, driver], stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)
        collected = b''
        try:
            deadline = time.monotonic() + 15
            sent = False
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    collected += data
                    if not sent:
                        sent = on_output(collected, master, process)
                if process.poll() is not None:
                    break
            process.wait(timeout=3)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
        return collected.decode(errors='replace'), list((self.root / 'terminal-logs').glob('*.log'))

    def test_terminal_prompts_work_password_is_not_logged_and_exit_is_preserved(self):
        child = 'import getpass,sys; print("TTY="+str(sys.stdin.isatty()),flush=True); value=getpass.getpass("Password: "); print("accepted" if value=="fixture-password" else "rejected"); sys.exit(17)'
        def respond(output, master, process):
            if b'Password: ' in output:
                os.write(master, b'fixture-password\n')
                return True
            return False
        output, logs = self.terminal_driver([sys.executable, '-c', child], respond)
        self.assertIn('TTY=True', output)
        self.assertIn('RESULT=17', output)
        self.assertIn('accepted', output)
        self.assertNotIn('fixture-password', logs[0].read_text().split('Script started on', 1)[-1].split('\n', 1)[-1])

    def test_interrupt_stops_the_running_child(self):
        pid_file = self.root / 'child.pid'
        child = f'import os,time; open({str(pid_file)!r},"w").write(str(os.getpid())); print("WAITING",flush=True); time.sleep(60)'
        def interrupt(output, master, process):
            if b'WAITING' in output:
                process.send_signal(signal.SIGINT)
                return True
            return False
        output, _ = self.terminal_driver([sys.executable, '-c', child], interrupt)
        self.assertIn('INTERRUPTED', output)
        pid = int(pid_file.read_text())
        stat = Path('/proc') / str(pid) / 'stat'
        for _ in range(30):
            if not stat.exists() or stat.read_text().split()[2] == 'Z':
                break
            time.sleep(0.1)
        else:
            os.kill(pid, signal.SIGKILL)
            self.fail('interrupted installer child was left running')


if __name__ == '__main__':
    unittest.main()
