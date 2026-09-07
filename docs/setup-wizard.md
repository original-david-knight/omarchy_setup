# Setup wizard

From a completed Omarchy 4.x desktop, run `./setup.sh` as your normal user.
The wizard collects setup choices first, installs unattended, and saves account
sign-ins and opening checks for the end. It uses Python's standard library and
util-linux `script`, both available on the supported baseline.

## The guided flow

1. Choose automatic, desktop or laptop configuration and start. Baseline,
   administrator access, and personal SSH preparation happen first.
2. Add the displayed public SSH key to your personal GitHub account if needed.
   The wizard can copy the key and open GitHub's key settings. Checking access
   to the private repository confirms authorization before installs begin.
3. Fetch the private setup plan, restore its settings/SSH identities, authorize
   work GitHub access, and load the private installation plan. Account details
   stay in the private manifest. SSH passphrases are
   loaded into an agent now so later clones do not ask again. An agent started
   by the wizard is stopped when it exits; an existing agent is retained.
4. Once “Preparation finished” appears, leave the installer running. Public
   packages, configuration, private tools, builds, and services run without
   questions. Installs stream output to the terminal and a private log, with
   stdin closed and no controlling terminal. Normal package confirmations are
   handled automatically; an unexpected request for input fails the step
   instead of waiting for a reply.
5. Review the installation report. It lists failures before the final
   interactive checklist, so it is already visible when you return.
6. Complete account sign-ins and opening checks: coding CLIs, Tailscale, Chrome
   profiles, desktop applications, and MCP connections. Existing connections
   are detected automatically. These checks run after every install step.
7. Review the combined final report and readiness checks. Failed installs
   remain failures even if a later readiness probe succeeds. Deferred account
   checks remain pending.

Account steps offer “Do this later.” Declining repository access leaves its
unmet dependent steps skipped while independent work proceeds. Build
prerequisites are treated the same way. For application connections without an
automatic probe, “I opened it and verified that it works” records the local
acknowledgment used by the private verifier. Deferral never acknowledges a check.

To finish without waiting for the application checklist, start with
`./setup.sh --defer-checks`. Application probes still detect working connections;
unverified checks remain pending. Rerun without the flag to complete them.
GitHub access and setup choices still happen upfront with this option.

## Failures, pause and resume

An install failure never opens a retry menu or stops the installation pass.
The wizard records its exit code and log, skips steps with an unmet declared
prerequisite, and continues with independent steps. The public agent-tool and
extension installers also continue their remaining items. The final report
lists failures, skipped dependencies, and pending work, with log paths and
remedies. The original `install_all.sh` and `go.sh` flows also collect failures.

Fix a reported issue and rerun `./setup.sh`. Failed and skipped steps retry;
completed installs retain their checkpoints. From the final account checklist,
you can choose an earlier setup step to rerun, invalidating that step and later
checkpoints. Ctrl+C still pauses immediately and stops the running child.
Interrupted and failed steps are never considered complete. Preparation checks,
account gates, and readiness checks run again when resuming.

Android SDK licenses are accepted automatically during SDK installation.
There is no license question, including when resuming with older saved choices.
An acceptance failure is reported as an installation failure.

Changes to a script or its declared input files invalidate its checkpoint and
subsequent checkpoints. A profile change reapplies configuration while retaining
completed package installs. To rerun everything deliberately:

```sh
./setup.sh --restart
```

Restart backs up wizard progress. Each underlying installer still preserves
existing configuration according to its own rules. It does not erase application
data or private readiness acknowledgments. If a tool was removed after a
successful install, `--restart` restores it through the installation steps.

Exit codes: **0** means installation and readiness passed; **3** means only
manual work remains; **1** means an install, prerequisite, or readiness check
failed; **130** means interrupted. Failures return a nonzero exit after the final
report. The wizard prevents two concurrent runs. Startup needs a terminal except
for `--plan` or `--help`; use the original scripts for fully headless invocation.

## Preview, profiles and paths

```sh
./setup.sh --plan
./setup.sh --profile desktop
./setup.sh --profile laptop
./setup.sh --public-only
./setup.sh --defer-checks
./setup.sh --private-repo /path/to/omarchy-setup-private
```

Preview shows the preparation/install/check order, executes no commands, and
writes no state. If the private checkout is available, preview includes its
steps; otherwise those steps load after clone. `--public-only` stops after the
public checks. A subsequent plain `./setup.sh` continues the full setup.

`WORKSPACE_DIR` controls ordinary workspace clones. `--private-repo` or
`OMARCHY_PRIVATE_SETUP_DIR` controls the private setup checkout. These choices
are saved for resume. `OMARCHY_SETUP_PROFILE` can select a profile; an explicit
command-line profile takes precedence.

Progress, `report.json`, and logs live in `$XDG_STATE_HOME/omarchy-setup/wizard`,
normally `~/.local/state/omarchy-setup/wizard`. The directory is mode 0700;
progress, reports, and logs are mode 0600. Logs record terminal output, including
sign-in links printed by a tool. Hidden terminal password input is not logged.
Keep the same `XDG_STATE_HOME` when resuming if you override it.

## Existing script flow and manifests

The wizard is optional. The original sequence remains available:

```sh
cd ~/omarchy_setup
./go.sh
# Register ~/.ssh/id_github.pub with your personal GitHub account.
./after_github_key_configured.sh
cd ~/workspace/omarchy-setup-private
./go.sh
./verify.sh --all
```

The public script list is shared in `setup/steps.json`. The wizard moves scripts
marked `phase: prepare` ahead of installs. GitHub gates and consent choices are
preparation steps; application logins/manual checks are final steps; verifiers
run last. `requires` names prerequisite step IDs, such as `public.setup_ssh`.
The original script flow retains its manifest order and standalone prompts.

Both repositories must have matching changes: private preparation phases,
automatic SDK license acceptance, dependency declarations, and the verifier's `--json` mode.
The wizard preserves existing private development work and does not
currently pull over it automatically.

## Tests

```sh
python3 -m unittest discover -s tests -v
python3 scripts/audit_bootstrap.py
```

Tests use disposable homes and fixture scripts. They cover public/private
handoff, preparation/install/check ordering, multiple failures, dependency skips,
resume and changed inputs, account checks, deferred acknowledgments, private
report permissions, and interactive/unattended terminal and interrupt behavior.
They do not install packages or start live services.
