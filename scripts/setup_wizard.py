#!/usr/bin/env python3
"""A resumable terminal guide for the public and private Omarchy setup."""
import argparse
import contextlib
import dataclasses
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
IGNORE = {".git", "__pycache__", ".pytest_cache", "node_modules"}


class WizardError(Exception):
    pass


class Pause(Exception):
    def __init__(self, code=3):
        self.code = code


class Revisit(Exception):
    def __init__(self, step_id):
        self.step_id = step_id


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=".wizard-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


@contextlib.contextmanager
def ssh_agent(env):
    """Cache passphrases during preparation; only stop an agent we started."""
    probe = subprocess.run(["ssh-add", "-l"], env=env, stdin=subprocess.DEVNULL,
                           capture_output=True, timeout=10)
    started = probe.returncode == 2
    if started:
        result = subprocess.run(["ssh-agent", "-s"], env=env, capture_output=True,
                                text=True, check=True, timeout=10)
        for name in ("SSH_AUTH_SOCK", "SSH_AGENT_PID"):
            match = re.search(rf"(?:^|\n){name}=([^;\n]+);", result.stdout)
            if not match:
                raise WizardError("Could not start an SSH agent for installation.")
            env[name] = match[1]
    try:
        yield
    finally:
        if started:
            subprocess.run(["ssh-agent", "-k"], env=env, capture_output=True, timeout=10)


class State:
    def __init__(self, directory, restart=False):
        self.directory = directory
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        directory.chmod(0o700)
        self.lock = open(directory / "lock", "a")
        os.chmod(directory / "lock", 0o600)
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            raise WizardError("Another setup wizard is running. Return to that terminal first.")
        self.path = directory / "progress.json"
        try:
            preferences = {}
            if restart and self.path.exists():
                try:
                    old = json.loads(self.path.read_text())
                    preferences = {key: old[key] for key in ("profile", "private_repo", "workspace_dir", "answers") if key in old}
                except ValueError:
                    pass
                backup = directory / f"progress-{time.time_ns()}.json.bak"
                os.replace(self.path, backup)
            self.data = json.loads(self.path.read_text()) if self.path.exists() else {"version": 1, "steps": {}, **preferences}
            if self.data.get("version") != 1 or not isinstance(self.data.get("steps"), dict):
                raise ValueError("unsupported state")
        except (OSError, ValueError) as error:
            self.close()
            raise WizardError(f"Cannot read {self.path}. Use ./setup.sh --restart to back it up and start again.") from error

    def save(self):
        atomic_json(self.path, self.data)

    def record(self, step_id, signature, status, **details):
        self.data["steps"][step_id] = dict(signature=signature, status=status, updated=time.time(), **details)
        self.save()

    def done(self, step_id, signature):
        previous = self.data["steps"].get(step_id, {})
        return previous.get("status") == "done" and previous.get("signature") == signature

    def invalidate(self, step_id, order):
        # A resumed run may not have reached the private plan yet. Clear saved
        # future steps too, retaining only the known prefix before the selection.
        keep = set(order[:order.index(step_id)])
        for key in list(self.data["steps"]):
            if key not in keep:
                self.data["steps"].pop(key, None)
        self.save()

    def close(self):
        self.lock.close()


class UI:
    def say(self, text=""):
        print(text, flush=True)

    def header(self, phase, label, index, total):
        width = 24
        filled = width * (index - 1) // max(total, 1)
        self.say(f"\n{'=' * 64}\n{phase}  [{'#' * filled}{'-' * (width - filled)}]  {index}/{total}\n{label}\n{'=' * 64}")

    def choose(self, prompt, options, default):
        self.say(prompt)
        for key, label in options.items():
            self.say(f"  [{key}] {label}")
        while True:
            try:
                value = input(f"> [{default}] ").strip().lower() or default
            except EOFError:
                raise Pause()
            if value in options:
                return value
            self.say("Choose one of the letters shown above.")


@dataclasses.dataclass
class Result:
    code: int
    log: Path
    output: str = ""


class Runner:
    """Keep preparation interactive; stream unattended installs without a terminal."""
    def __init__(self, directory, env):
        self.directory = directory
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        directory.chmod(0o700)
        self.env = env

    def run(self, argv, cwd, label, interactive=True, stream=False):
        safe = re.sub(r"[^a-zA-Z0-9_.-]", "_", label)
        fd, filename = tempfile.mkstemp(prefix=safe + "-", suffix=".log", dir=self.directory)
        os.close(fd)
        log = Path(filename)
        command = list(map(str, argv))
        if interactive:
            command = ["script", "--quiet", "--return", "--flush", "--log-out", str(log), "--command", shlex.join(command)]
        env = dict(self.env, SHELL="/bin/bash")
        if not interactive:
            env.update(MISE_YES="1", GIT_TERMINAL_PROMPT="0", SSH_ASKPASS_REQUIRE="never",
                       SSH_ASKPASS="/bin/false", SUDO_ASKPASS="/bin/false",
                       OMARCHY_SETUP_UNATTENDED="1")
            env["GIT_SSH_COMMAND"] = env.get("GIT_SSH_COMMAND", "ssh") + " -oBatchMode=yes -oStrictHostKeyChecking=yes -oConnectTimeout=10"
        process = None
        try:
            process = subprocess.Popen(command, cwd=cwd, env=env,
                                       start_new_session=True,
                                       stdin=None if interactive else subprocess.DEVNULL,
                                       stdout=None if interactive else subprocess.PIPE,
                                       stderr=None if interactive else subprocess.STDOUT)
            if interactive:
                output, _ = process.communicate()
            elif stream:
                with log.open("ab") as logfile:
                    while chunk := process.stdout.read1(65536):
                        logfile.write(chunk)
                        logfile.flush()
                        sys.stdout.write(chunk.decode(errors="replace"))
                        sys.stdout.flush()
                process.wait()
                output = None
            else:
                started = time.monotonic()
                while True:
                    try:
                        output, _ = process.communicate(timeout=1)
                        break
                    except subprocess.TimeoutExpired:
                        if sys.stdout.isatty():
                            print(f"\rChecking readiness… {time.monotonic() - started:.0f}s", end="", flush=True)
                if sys.stdout.isatty():
                    print("\r" + " " * 45 + "\r", end="", flush=True)
            text = output.decode(errors="replace") if output else ""
            if not interactive and not stream:
                log.write_text(text)
            return Result(process.returncode, log, text)
        except KeyboardInterrupt:
            if process is not None:
                self.stop(process)
            raise
        except OSError as error:
            if process is not None and process.poll() is None:
                self.stop(process)
            with log.open("a") as logfile:
                logfile.write(str(error) + "\n")
            return Result(127, log, str(error))
        finally:
            if process is not None and process.stdout is not None:
                process.stdout.close()

    @staticmethod
    def stop(process):
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                return
            try:
                process.wait(timeout=3)
                return
            except subprocess.TimeoutExpired:
                pass


def phase(step):
    kind = step.get("kind", "script")
    if kind in ("github", "consent"):
        return "prepare"
    if kind in ("login", "manual", "browser_profiles"):
        return "finish"
    if kind == "verify":
        return "verify"
    return step.get("phase", "install")


def load_plan(path, section):
    try:
        data = json.loads(path.read_text())
        if data["version"] != 1 or not isinstance(data[section], list):
            raise ValueError("unsupported plan")
        ids = set()
        for step in data[section]:
            if not re.fullmatch(r"[a-zA-Z0-9_.-]+", step["id"]) or step["id"] in ids:
                raise ValueError("invalid or duplicate step ID")
            ids.add(step["id"])
            if not step.get("label"):
                raise ValueError("step needs a label")
            if step.get("kind", "script") not in {"script", "verify", "github", "login", "manual", "browser_profiles", "consent"}:
                raise ValueError("unknown step kind")
            if step.get("phase", "install") not in ("prepare", "install"):
                raise ValueError("script phase must be prepare or install")
            if not isinstance(step.get("requires", []), list) or any(
                not isinstance(item, str) or not re.fullmatch(r"[a-zA-Z0-9_.-]+", item)
                for item in step.get("requires", [])
            ):
                raise ValueError("requires must contain step IDs")
            if not isinstance(step.get("pending_exit_codes", []), list) or any(
                type(code) is not int or not 1 <= code <= 255 for code in step.get("pending_exit_codes", [])
            ):
                raise ValueError("pending_exit_codes must contain nonzero exit codes")
            if step.get("kind") == "consent" and not re.fullmatch(r"OMARCHY_[A-Z0-9_]+", step.get("env", "")):
                raise ValueError("consent must name an OMARCHY_ environment option")
            if "script" in step and (Path(step["script"]).is_absolute() or ".." in Path(step["script"]).parts):
                raise ValueError("script must be inside its repository")
        return data
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise WizardError(f"Cannot load wizard steps from {path}: {error}") from error


def digest_inputs(root, step):
    digest = hashlib.sha256()
    for name in sorted(set(step.get("inputs", []) + ([step["script"]] if "script" in step else []))):
        path = root / name
        if not path.resolve().is_relative_to(root.resolve()):
            raise WizardError(f"Step input escapes its repository: {name}")
        paths = []
        if path.is_dir():
            for directory, dirs, files in os.walk(path):
                dirs[:] = sorted(set(dirs) - IGNORE)
                paths.extend(Path(directory) / f for f in sorted(files) if not f.endswith(".pyc"))
        else:
            paths = [path]
        for source in paths:
            digest.update(str(source.relative_to(root)).encode())
            digest.update(source.read_bytes() if source.is_file() else b"<missing>")
    return digest.hexdigest()


class Wizard:
    def __init__(self, public, private, home, state, ui, runner, profile="auto", public_only=False, defer_checks=False):
        self.public, self.private, self.home = public, private, home
        self.state, self.ui, self.runner = state, ui, runner
        self.profile, self.public_only = profile, public_only
        self.defer_checks = defer_checks
        self.context = {"home": str(home), "public": str(public), "private": str(private),
                        "personal_key": os.environ.get("GITHUB_PERSONAL_SSH_KEY", str(home / ".ssh/id_github")),
                        "work_key": os.environ.get("GITHUB_FLUXON_SSH_KEY", str(home / ".ssh/id_fluxon"))}
        self.order, self.available = [], []
        self.chain = "wizard-v2"
        self.pending = []
        self.ack_path = home / ".local/state/omarchy-setup-private/manual-readiness.json"

    def expand(self, value):
        if isinstance(value, list):
            return [self.expand(item) for item in value]
        if isinstance(value, dict):
            return {key: self.expand(item) for key, item in value.items()}
        if isinstance(value, str):
            for key, replacement in self.context.items():
                value = value.replace("{" + key + "}", replacement)
        return value

    def argv(self, root, step):
        return ["bash", str(root / step["script"]), *self.expand(step.get("args", []))]

    def signature(self, root, step):
        data = [self.chain, str(root), self.expand(step), digest_inputs(root, step)]
        data.append({name: self.runner.env.get(name) for name in step.get("env_inputs", [])})
        if step.get("profile_sensitive"):
            data.append(self.profile)
        self.chain = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
        return self.chain

    def run_group(self, title, namespace, root, steps):
        for index, raw in enumerate(steps, 1):
            step = self.expand(raw)
            step_id = namespace + "." + step["id"]
            self.order.append(step_id)
            self.available.append((step_id, step["label"], step.get("kind", "script")))
            kind = step.get("kind", "script")
            try:
                signature = self.signature(root, raw)
            except (OSError, ValueError, WizardError) as error:
                self.state.record(step_id, "invalid-inputs", "failed", reason=str(error))
                self.ui.say(f"  Failed: {step['label']} — {error}. Continuing.")
                continue
            dependencies = [key for key in step.get("requires", [])
                            if key not in self.order or self.state.data["steps"].get(key, {}).get("status") != "done"]
            if dependencies:
                reason = "Waiting for: " + ", ".join(dependencies)
                hard_failure = any(key not in self.order or
                                   self.state.data["steps"].get(key, {}).get("status") == "failed" or
                                   (self.state.data["steps"].get(key, {}).get("status") == "blocked" and
                                    self.state.data["steps"].get(key, {}).get("code", 1) != 3) for key in dependencies)
                self.state.record(step_id, signature, "blocked", code=1 if hard_failure else 3, reason=reason)
                self.ui.say(f"  Skipped: {step['label']} — {reason}")
                continue
            # Account gates and final checks always examine the current machine.
            cached = kind == "script" and not step.get("always") and self.state.done(step_id, signature)
            if step.get("required_paths") and not all(Path(path).exists() for path in step["required_paths"]):
                cached = False
            if cached:
                self.ui.say(f"  Done already: {step['label']}")
                continue
            self.ui.header(title, step["label"], index, len(steps))
            try:
                if kind in ("script", "verify"):
                    self.script(root, step, step_id, signature)
                elif kind == "consent":
                    self.consent(step, step_id, signature)
                else:
                    self.manual(root, step, step_id, signature, prompt=not (self.defer_checks and phase(step) == "finish"))
            except (OSError, ValueError, WizardError) as error:
                self.state.record(step_id, signature, "failed", reason=str(error))
                self.ui.say(f"  Failed: {step['label']} — {error}. Continuing.")

    def script(self, root, step, step_id, signature):
        self.state.record(step_id, signature, "running")
        start = time.monotonic()
        verify = step.get("kind") == "verify"
        interactive = phase(step) == "prepare"
        self.ui.say("Checking readiness…" if verify else "Running setup…")
        result = self.runner.run(self.argv(root, step), root, step_id,
                                 interactive=interactive, stream=not interactive and not verify)
        code, details = result.code, {}
        if verify:
            try:
                report = json.loads(result.output)
                rows = report["checks"]
                if report.get("version") != 1 or not isinstance(rows, list):
                    raise ValueError("unsupported readiness report")
                if any(row["status"] not in ("pass", "fail", "pending") for row in rows):
                    raise ValueError("unknown readiness status")
                failed = sum(row["status"] == "fail" for row in rows)
                pending = sum(row["status"] == "pending" for row in rows)
                if (report["failed"], report["pending"]) != (failed, pending) or code != (1 if failed else 3 if pending else 0):
                    raise ValueError("verification counts or exit code disagree with report")
                details["checks"] = rows
                for row in rows:
                    if row["status"] != "pass":
                        self.ui.say(f"  {row['status'].upper()}: {row['label']} — {row.get('remedy', '')}")
            except (ValueError, KeyError, TypeError):
                code = 1
                details["reason"] = "Invalid readiness report. Update both setup repositories together."
        if code == 0 and step.get("required_paths") and not all(Path(path).exists() for path in step["required_paths"]):
            code = 1
            details["reason"] = "The script finished without creating its required files."
        pending = code == 3 if verify else code in step.get("pending_exit_codes", [])
        status = "done" if code == 0 else "pending" if pending else "failed"
        self.state.record(step_id, signature, status, log=str(result.log), code=code,
                          remedy=step.get("instructions", "Rerun ./setup.sh to retry this step."), **details)
        if code in (130, -signal.SIGINT):
            raise Pause(130)
        self.ui.say(f"{'Completed' if code == 0 else 'Recorded ' + status + '; continuing'} in {time.monotonic() - start:.0f}s. Log: {result.log}")

    def consent(self, step, step_id, signature):
        answers = self.state.data.setdefault("answers", {})
        name = step["env"]
        answer = answers.get(name)
        if answer != "1":
            self.ui.say(step.get("instructions", ""))
            answer = "1" if self.ui.choose(step["label"], {"y": "Yes", "n": "No; leave dependent work pending"}, "n") == "y" else "0"
        answers[name] = self.runner.env[name] = answer
        # A declined choice is still a completed preparation decision.
        self.state.record(step_id, signature, "done", answer=answer)

    def summary(self):
        entries = []
        for step_id, label, kind in dict((item[0], item) for item in self.available).values():
            item = self.state.data["steps"].get(step_id, {})
            entries.append(dict(item, id=step_id, label=label, kind=kind))
        failed = [item for item in entries if item.get("status") == "failed"]
        blocked = [item for item in entries if item.get("status") == "blocked"]
        pending = [item for item in entries if item.get("status") in ("pending", "running")]
        report = dict(version=1, failed=len(failed), blocked=len(blocked), pending=len(pending), steps=entries)
        path = self.state.directory / "report.json"
        atomic_json(path, report)
        self.ui.say(f"\nSetup report: {len(failed)} failed; {len(blocked)} skipped for prerequisites; {len(pending)} pending.")
        for item in failed + blocked + pending:
            self.ui.say(f"  {item['status'].upper()}: {item['label']}")
            for key in ("reason", "remedy", "log"):
                if item.get(key):
                    self.ui.say(f"    {item[key]}")
        self.ui.say(f"Report: {path}\nRerun ./setup.sh to retry unfinished steps; completed installs are retained.")
        return 1 if failed or any(item.get("code", 1) != 3 for item in blocked) else 3 if pending or blocked else 0

    def revisit(self):
        entries = [(key, label) for key, label, kind in self.available if kind == "script"]
        options = {str(i): label for i, (_, label) in enumerate(entries, 1)}
        options["b"] = "Back"
        selected = self.ui.choose("Which setup step should run again? Later steps will be rechecked too.", options, "b")
        if selected != "b":
            raise Revisit(entries[int(selected) - 1][0])

    def command(self, argv):
        # The normal Codex wrapper updates on use. A login probe should inspect
        # the installed CLI without launching another package update.
        if argv[0] == "codex":
            try:
                result = subprocess.run(["mise", "where", "codex"], cwd=self.public,
                                        env=self.runner.env, capture_output=True, text=True, timeout=10)
                candidate = Path(result.stdout.strip()) / "bin/codex"
                if result.returncode == 0 and candidate.is_file():
                    return [str(candidate), *argv[1:]]
            except (OSError, subprocess.TimeoutExpired):
                pass
            return [str(self.home / ".local/bin/codex"), *argv[1:]]
        return argv

    def probe(self, probe):
        try:
            if "file" in probe:
                path = Path(probe["file"])
                if not path.is_file():
                    return False
                if "json_equals" not in probe:
                    return True
                value = json.loads(path.read_text())
            else:
                result = subprocess.run(self.command(probe["argv"]), cwd=self.public, env=self.runner.env,
                                        stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
                if result.returncode:
                    return False
                if "json_equals" not in probe:
                    return True
                value = json.loads(result.stdout)
            predicate = probe["json_equals"]
            for key in predicate["path"]:
                value = value[key]
            return value == predicate["value"]
        except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
            return False

    def acknowledged(self, name):
        try:
            return name in json.loads(self.ack_path.read_text())
        except (OSError, ValueError):
            return False

    def acknowledge(self, name):
        entries = set(json.loads(self.ack_path.read_text())) if self.ack_path.exists() else set()
        entries.add(name)
        atomic_json(self.ack_path, sorted(entries))

    def action(self, root, action, step_id):
        if action.get("launch"):
            try:
                # Desktop apps own their own lifetimes; don't wait for their windows to close.
                process = subprocess.Popen(action["argv"], cwd=root, env=self.runner.env,
                                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL, start_new_session=True)
                time.sleep(0.2)
                if process.poll() not in (None, 0):
                    self.ui.say("The application could not start. Open it from the application launcher.")
            except OSError:
                self.ui.say("The application could not start. Open it from the application launcher.")
        else:
            result = self.runner.run(self.command(action["argv"]), root, step_id + ".action")
            if result.code:
                self.ui.say(f"Action exited {result.code}. Log: {result.log}")

    def manual(self, root, step, step_id, signature, prompt=True):
        kind = step.get("kind")
        if kind == "browser_profiles":
            verified = self.browser_profiles(root, step)
            self.state.record(step_id, signature, "done" if verified else "pending")
            return
        if kind == "github":
            key = Path(step["key"])
            if not key.is_file():
                self.state.record(step_id, signature, "blocked", reason=f"Public key is missing: {key}. Rerun SSH preparation.")
                self.ui.say("SSH preparation is incomplete; this account step will be reported at the end.")
                return
            step = dict(step, probe={"argv": ["git", "-c", "core.sshCommand=ssh -oBatchMode=yes -oStrictHostKeyChecking=yes -oConnectTimeout=10", "ls-remote", "--exit-code", step["repo"], "HEAD"]})
        if step.get("probe"):
            self.ui.say("Checking the current connection…")
        if (step.get("probe") and self.probe(step["probe"])) or (step.get("ack") and self.acknowledged(step["ack"])):
            self.state.record(step_id, signature, "done")
            self.ui.say("Already connected / verified.")
            return
        if not prompt:
            self.state.record(step_id, signature, "pending", remedy=step.get("instructions", "Run ./setup.sh without --defer-checks to complete this check."))
            self.ui.say(f"Left pending: {step['label']}")
            return
        self.ui.say(step.get("instructions", ""))
        if kind == "github":
            self.ui.say(f"\nPublic key ({key}):\n{key.read_text().strip()}\n\nGitHub key settings: https://github.com/settings/ssh/new")
        while True:
            options = {"c": "Check connection"} if step.get("probe") else {"d": "I opened it and verified that it works"}
            if kind == "github":
                options.update(o="Open GitHub key settings", k="Copy the public key")
            for i, action in enumerate(step.get("actions", []), 1):
                options[str(i)] = action["label"]
            if step.get("allow_later") or kind == "github":
                options["n"] = "Do this later; leave it pending"
            options["f"] = "Rerun an earlier setup step"
            options["p"] = "Pause and resume later"
            choice = self.ui.choose("Continue when you are ready.", options, "c" if step.get("probe") else "d")
            if choice == "p":
                self.state.record(step_id, signature, "pending")
                raise Pause()
            if choice == "f":
                self.revisit()
                continue
            if choice == "n":
                self.state.record(step_id, signature, "pending")
                self.pending.append(step["label"])
                return
            if choice == "k":
                try:
                    subprocess.run(["wl-copy"], input=key.read_bytes(), check=True, env=self.runner.env)
                    self.ui.say("Public key copied. Paste it into GitHub's SSH key form.")
                except (OSError, subprocess.CalledProcessError):
                    self.ui.say("Clipboard unavailable. Copy the public key printed above.")
            elif choice == "o":
                self.action(root, {"argv": ["xdg-open", "https://github.com/settings/ssh/new"], "launch": True}, step_id)
            elif choice.isdigit():
                self.action(root, step["actions"][int(choice) - 1], step_id)
            elif choice == "d":
                self.acknowledge(step["ack"])
                self.state.record(step_id, signature, "done")
                return
            elif choice == "c":
                if kind == "github":
                    # A real terminal permits the first GitHub host-key confirmation
                    # or an existing key's passphrase. Exit 0 proves repo access.
                    command = ["git", "-c", "core.sshCommand=ssh -oConnectTimeout=10", "ls-remote", "--exit-code", step["repo"], "HEAD"]
                    success = self.runner.run(command, root, step_id + ".check").code == 0
                else:
                    success = self.probe(step["probe"])
                if success:
                    self.state.record(step_id, signature, "done")
                    self.ui.say("Connection verified.")
                    return
                self.ui.say("Connection is not ready yet. Complete the sign-in above and check again.")

    def browser_profiles(self, root, step):
        profiles = json.loads((root / step["file"]).read_text())
        steps = []
        for index, profile in enumerate(profiles):
            directory, email = profile["directory"], profile["email"]
            steps.append({"id": str(index), "label": f"Chrome: {email}", "kind": "login", "allow_later": True,
                          "instructions": f"Sign into Chrome itself as {email} in {directory}. If the check does not update, close that Chrome window and check again.",
                          "probe": {"file": str(self.home / ".config/google-chrome/Local State"), "json_equals": {"path": ["profile", "info_cache", directory, "user_name"], "value": email}},
                          "actions": [{"label": "Open this Chrome profile", "argv": ["google-chrome-stable", "--profile-directory=" + directory, "chrome://settings/people"], "launch": True}]})
        self.run_group("Chrome profiles", "private.browser", root, steps)
        return all(self.state.data["steps"].get("private.browser." + step["id"], {}).get("status") == "done" for step in steps)

    def run_phase(self, title, namespace, root, steps, selected):
        self.run_group(title, namespace, root, [step for step in steps if phase(step) == selected])

    def missing_private(self, reason):
        step_id = "handoff.private_plan"
        self.order.append(step_id)
        self.available.append((step_id, "Load the private setup plan", "script"))
        self.state.record(step_id, "missing", "blocked", reason=reason,
                          code=self.state.data["steps"].get("handoff.clone", {}).get("code", 1))

    def run(self):
        while True:
            self.order, self.available, self.chain, self.pending = [], [], "wizard-v2", []
            try:
                public = load_plan(self.public / "setup/steps.json", "install")
                load_plan(self.public / "setup/steps.json", "configure")
                public_steps = public["install"] + public["configure"]
                private_steps = []
                self.ui.say("\nPublic setup runs first: update Omarchy, install applications, apply configuration, and check readiness. GitHub access comes afterward.")
                self.run_phase("1 · Update Omarchy and prepare setup", "public", self.public, public_steps, "prepare")
                self.ui.say("\nPublic installation: you can leave this running. Failures are recorded and independent steps continue without installation prompts.")
                self.run_phase("2 · Install and configure public tools", "public", self.public, public_steps, "install")
                self.run_phase("2 · Public opening checks", "public", self.public, public_steps, "finish")
                self.run_phase("2 · Public readiness", "public", self.public, public_steps, "verify")
                code = self.summary()
                if code:
                    self.ui.say("\nFinish the public setup issues above and rerun ./setup.sh. GitHub access and private setup will follow once public setup passes.")
                    return code
                self.ui.say("\nPublic setup complete.")
                if self.public_only:
                    return 0
                ssh_dependency = ["public.setup_ssh"] if any(step["id"] == "setup_ssh" for step in public_steps) else []
                self.run_group("3 · GitHub and private checkout", "handoff", self.public, [
                    {"id": "github", "label": "Register your personal GitHub key", "kind": "github", "key": "{personal_key}.pub", "repo": "git@github.com:original-david-knight/omarchy-setup-private.git", "requires": ssh_dependency, "instructions": "Public setup is complete, including Chrome. Sign into your personal GitHub account and add this public SSH key. The wizard will check access before starting private setup."},
                    {"id": "clone", "label": "Fetch the private setup plan", "script": "setup_workspace.sh", "args": ["--private-only"], "phase": "prepare", "requires": ["handoff.github"], "destination": "{private}", "required_paths": ["{private}/setup-wizard.json"]}])
                path = self.private / "setup-wizard.json"
                if self.state.data["steps"].get("handoff.clone", {}).get("status") == "done":
                    try:
                        private = load_plan(path, "steps")
                        private_steps = private["steps"]
                        self.context["work_repo"] = os.environ.get("REKORDO_REPO_URL", private.get("work_repo", ""))
                    except WizardError as error:
                        self.missing_private(str(error))
                else:
                    self.missing_private("Complete the GitHub/private checkout preparation, then rerun ./setup.sh. Public setup is already complete.")
                self.run_phase("3 · Private preparation", "private", self.private, private_steps, "prepare")
                self.ui.say("\nPrivate preparation finished. You can leave this running. Install failures are recorded and remaining steps continue; no installation prompts will wait for input.")
                self.run_group("4 · Prepare workspaces", "handoff", self.public, [
                    {"id": "workspaces", "label": "Prepare public workspaces and Git remote", "script": "after_github_key_configured.sh", "inputs": ["setup_workspace.sh"], "requires": ["handoff.clone"]}])
                self.run_phase("4 · Install private tools", "private", self.private, private_steps, "install")

                self.ui.say("\nInstallation pass finished. Any failures are listed below before the final checks.")
                self.summary()
                self.run_phase("5 · Sign-ins and opening checks", "private", self.private, private_steps, "finish")
                self.run_phase("6 · Final readiness", "private", self.private, private_steps, "verify")
                code = self.summary()
                if code == 0:
                    self.ui.say("\nSetup complete — installation and readiness checks passed.")
                return code
            except Revisit as request:
                self.state.invalidate(request.step_id, self.order)
            except (Pause, KeyboardInterrupt):
                self.summary()
                raise


def preview(public, private, public_only=False):
    plan = load_plan(public / "setup/steps.json", "install")
    load_plan(public / "setup/steps.json", "configure")
    print("Omarchy setup — preview (no commands executed, no progress files written)\n")
    public_steps = plan["install"] + plan["configure"]
    private_steps = []
    for selected, title in [("prepare", "1 · Update Omarchy and prepare setup"),
                            ("install", "2 · Install and configure public tools"),
                            ("finish", "2 · Public opening checks"),
                            ("verify", "2 · Public readiness")]:
        print("\n" + title)
        for step in public_steps:
            if phase(step) == selected:
                print("  " + step["label"])
    if public_only:
        return
    print("\nPublic setup must pass before GitHub access and private setup.")
    print("\n3 · GitHub and private preparation")
    print("  Register personal GitHub SSH key and verify private repository access\n  Fetch the private setup plan")
    if (private / "setup-wizard.json").exists():
        private_steps = load_plan(private / "setup-wizard.json", "steps")["steps"]
        for step in private_steps:
            if phase(step) == "prepare":
                print("  " + step["label"])
    else:
        print("  Private tool and account steps will load after the checkout is fetched.")
    for selected, title in [("install", "4 · Unattended private installation; failures are collected"),
                            ("finish", "5 · Sign-ins and opening checks"),
                            ("verify", "6 · Final readiness and failure report")]:
        print("\n" + title)
        if selected == "install":
            print("  Prepare public workspaces and Git remote")
        for step in private_steps:
            if phase(step) == selected:
                print("  " + step["label"])


def main():
    parser = argparse.ArgumentParser(prog="./setup.sh", description=__doc__)
    parser.add_argument("--plan", action="store_true", help="preview the steps without executing anything")
    parser.add_argument("--restart", action="store_true", help="back up progress and rerun setup; existing configurations remain governed by each script")
    parser.add_argument("--public-only", action="store_true", help="stop after public setup verification")
    parser.add_argument("--defer-checks", action="store_true", help="save application sign-ins and opening checks for a later run")
    parser.add_argument("--profile", choices=["auto", "desktop", "laptop"])
    parser.add_argument("--private-repo", type=Path, help="private checkout location (remembered when you resume)")
    args = parser.parse_args()
    requested_private = args.private_repo or os.environ.get("OMARCHY_PRIVATE_SETUP_DIR")
    workspace = Path(os.environ.get("WORKSPACE_DIR", str(Path.home() / "workspace"))).expanduser().resolve()
    private = Path(requested_private or workspace / "omarchy-setup-private").expanduser().resolve()
    if args.plan:
        preview(ROOT, private, args.public_only)
        return 0
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        parser.error("run ./setup.sh in an interactive terminal; use --plan to preview or ./go.sh for the existing script flow")
    target = os.environ.get("OMARCHY_SETUP_TARGET")
    if target and Path(target).expanduser().resolve() != Path.home().resolve():
        parser.error("the wizard configures your current desktop; use stow_all.sh for an alternate target")
    if os.geteuid() == 0:
        parser.error("run as your desktop user; individual setup scripts request sudo when needed")
    if not shutil.which("script"):
        parser.error("util-linux 'script' is required for interactive prompts and logs")
    directory = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "omarchy-setup/wizard"
    state = State(directory, args.restart)
    ui = UI()
    try:
        workspace = Path(os.environ.get("WORKSPACE_DIR", state.data.get("workspace_dir", str(workspace)))).expanduser().resolve()
        private = Path(requested_private or state.data.get("private_repo", str(workspace / "omarchy-setup-private"))).expanduser().resolve()
        state.data.update(private_repo=str(private), workspace_dir=str(workspace))
        ui.say("\nOMARCHY SETUP\n\nUpdate Omarchy → complete public setup → GitHub/private setup → final sign-ins and opening checks.\nFailed installs are reported at the end; independent steps continue. Completed scripts are saved.\nCtrl+C pauses setup; run ./setup.sh to resume. Logs are private; password keystrokes are not recorded.")
        profile = args.profile or os.environ.get("OMARCHY_SETUP_PROFILE") or state.data.get("profile")
        if profile not in ("auto", "desktop", "laptop"):
            choice = ui.choose("Choose your desktop profile.", {"a": "Automatic — use connected displays", "d": "Desktop", "l": "Laptop"}, "a")
            profile = {"a": "auto", "d": "desktop", "l": "laptop"}[choice]
        state.data["profile"] = profile
        state.save()
        complete = sum(item.get("status") == "done" for item in state.data["steps"].values())
        ui.say(f"\nProfile: {profile}\nSaved completed steps: {complete}\nPrivate checkout: {private}\nLogs: {directory / 'logs'}")
        if ui.choose("Ready to begin?", {"s": "Start / resume setup", "p": "Pause"}, "s") == "p":
            raise Pause()
        home = Path.home()
        env = dict(os.environ, OMARCHY_SETUP_DIR=str(ROOT), OMARCHY_PRIVATE_SETUP_DIR=str(private), OMARCHY_SETUP_PROFILE=profile, WORKSPACE_DIR=str(workspace), OMARCHY_SETUP_WIZARD="1")
        env["PATH"] = ":".join(str(home / path) for path in (".local/bin", ".local/share/mise/shims", ".cargo/bin", "go/bin", ".local/flutter/bin", ".dotnet")) + ":" + env["PATH"]
        env["JAVA_HOME"] = "/usr/lib/jvm/java-21-openjdk"
        env["ANDROID_HOME"] = str(home / "Android/Sdk")
        env["ANDROID_SDK_ROOT"] = env["ANDROID_HOME"]
        with ssh_agent(env):
            return Wizard(ROOT, private, home, state, ui, Runner(directory / "logs", env), profile, args.public_only, args.defer_checks).run()
    except (Pause, KeyboardInterrupt) as stopped:
        ui.say(f"\nSetup paused. Progress is saved in {directory}.\nRun ./setup.sh again to resume.")
        return stopped.code if isinstance(stopped, Pause) else 130
    finally:
        state.close()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (WizardError, OSError, ValueError) as error:
        print(f"Setup wizard: {error}", file=sys.stderr)
        raise SystemExit(1)
