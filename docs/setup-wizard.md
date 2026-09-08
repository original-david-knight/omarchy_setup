# Setup wizard

From a completed Omarchy 4.x desktop, run `./setup.sh` as your normal user.
The wizard finishes public setup before requesting GitHub access, then installs
private tools and saves account sign-ins and opening checks for the end. It uses Python's standard library and
util-linux `script`, both available on the supported baseline.

## The guided flow

1. Choose automatic, desktop or laptop configuration. Run `omarchy update -y`
   as the first setup action, before checking the updated baseline or changing
   administrator/SSH configuration. Omarchy requests sudo itself. The update
   runs in a terminal for any remaining upstream prompts; defer a reboot until
   setup finishes. Successful updates are checkpointed, so ordinary resumes do
   not repeat them. GitHub authorization comes later.
2. Install all public tools, including Chrome, apply the desktop configuration,
   and run public readiness checks. Installs stream output to the terminal and
   a private log with stdin closed and no controlling terminal. Failures are
   collected while independent steps continue. If public setup fails, fix the
   reported issues and rerun; GitHub and private setup wait until it passes.
3. Register the displayed public SSH key with personal GitHub if needed. The
   wizard can copy the key and open GitHub key settings in the installed browser.
   Fetch the private plan, restore settings/SSH identities, and authorize work
   GitHub. Account details stay in the private manifest. SSH passphrases are
   loaded into an agent for later clones; an agent started by the wizard is
   stopped on exit, while an existing agent is retained.
4. Once private preparation finishes, workspace clones, private tools, builds,
   and services run unattended. Review their installation report afterward.
5. Complete private account sign-ins and opening checks: coding CLIs, Tailscale,
   Chrome profiles, desktop applications, and MCP connections. Existing
   connections are detected automatically.
6. Review the combined final report and private readiness checks. Failed
   installs remain failures even if a later probe succeeds. Deferred account
   checks remain pending.

Connection steps start their sign-in commands or open their applications
automatically. When a probe can detect the connection, the wizard checks it
while you sign in and advances without another confirmation. Retry, pause,
and “Do this later” controls remain available. Applications without a reliable
probe still need a readiness acknowledgment. `--defer-checks` continues to skip
unverified application sign-ins without launching them.

Chrome accounts are matched by the signed-in email across every Chrome profile;
profile directory numbers are never assigned to an account by the wizard.
Required emails and personal/work GitHub CLI identities live in the private
repository. GitHub CLI checks validate both saved accounts individually, even
when only one is active.

Account steps offer “Do this later.” Declining repository access leaves its
unmet dependent steps skipped while independent work proceeds. Build
prerequisites are treated the same way. For application connections without an
automatic probe, “I opened it and verified that it works” records the local
acknowledgment used by the private verifier. Deferral never acknowledges a check.

To finish without waiting for the application checklist, start with
`./setup.sh --defer-checks`. Application probes still detect working connections;
unverified checks remain pending. Rerun without the flag to complete them.
GitHub access still happens after public setup and before private installation
with this option.

## Failures, pause and resume

An install failure never opens a retry menu or stops independent steps in the
current public or private installation pass.
The wizard records its exit code and log, skips steps with an unmet declared
prerequisite, and continues with independent steps. The public agent-tool and
extension installers also continue their remaining items. The final report
lists failures, skipped dependencies, and pending work, with log paths and
remedies. In the wizard, a failed Omarchy update blocks baseline checks,
administrator/SSH configuration, and public application installs and
configuration. Any public failure postpones GitHub/private setup until a retry
passes. The original `install_all.sh` and `go.sh` flows also collect failures.

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
subsequent checkpoints. Moving to the public-first flow with its new update
step also changes subsequent checkpoints on the first run. A profile change reapplies configuration while retaining
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
marked `phase: prepare` ahead of installs within each repository. Public
preparation, installs, and verification all finish before the GitHub handoff.
Private GitHub gates and consent choices precede private installs; application
logins/manual checks and private verifiers follow those installs. `requires` names prerequisite step IDs, such as `public.setup_ssh`.
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
