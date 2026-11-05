# Claude Code accounts

Two Claude subscriptions, one `~/.claude`. When one account's weekly limit runs
low, switch Claude Code to the other from the bar's Agents panel. Settings,
transcripts, skills, plugins, and MCP sign-ins stay shared; only the
subscription login changes.

## Using it

Open the Agents panel (the robot icon) and use the **Account** row under
**Claude Code**:

- Click an account to switch to it. The limits below (session, weekly, and
  model windows) refresh for the new account within a second.
- Tokens by day and by model do not change: they are counted from this
  machine's transcripts, which do not record the account, so they always
  cover both accounts together.
- **+ Add** opens a terminal, saves the current login, and runs
  `claude auth login`. Sign in to the other account in the browser it opens.
  Use a private window or log claude.ai out first, or the browser signs you
  straight back into the current account.
- An account marked ⟳ has a sign-in that expired from disuse. Clicking it
  runs the same sign-in flow.

New Claude sessions, `security-watch`, and agents delegated from the bar all
use the selected account. Running sessions may keep using the previous
account, so restart them after a switch.

From a terminal:

```bash
claude-account list          # * marks the account in use
claude-account use work      # an email or a unique prefix of one
claude-account add
claude-account save
```

## How it works

`bin/bin/claude-account` stores each account's login under
`~/.local/state/claude-accounts/<email>.json` (directory 0700, files 0600):
the `claudeAiOauth` entry of `~/.claude/.credentials.json` and the
`oauthAccount` profile from `~/.claude.json`. Switching saves the live login
back into its account's file, writes the chosen account's pair into place,
deletes the collector's cached limits (they belong to the previous account),
and runs `omarchy-agent-usage-update --limits-only claude`, which re-probes in
well under a second. The header reads "Account · Switching…" until it is done.
Every other key in both files is left alone. Nothing here is tracked
in the repo; a new machine starts with one account and `+ Add`.

Claude Code rotates refresh tokens, so a stored login goes stale while a
session for that account is still running. Each save therefore files the live
login under the account it actually belongs to, never under the account last
selected. A token that matches a saved one names its account directly; any
other is asked of Anthropic's `/api/oauth/profile` endpoint, cached for five
minutes. A login that can not be identified (expired and offline) is not
saved anywhere, so it can never overwrite another account's file. Opening the
panel also refiles the live login, which keeps each slot's token current.

A login left unused for a few weeks expires; `refreshTokenExpiresAt` in its
file says when. Re-adding the account replaces it.

## The panel

`david.agents` replaces `omarchy.agents` in both bar layouts. It loads the
installed stock `Panel.qml` by URL, as the shell does, and changes nothing in
it; the same technique as `david.bar`. The panel lists every agent on one page,
one section each. Whenever the stock panel builds Claude's section, the wrapper
appends the Account row to it and re-appends the stock rows after the section's
name, so the row sits between the name and the limits. If a future Omarchy
release reshapes the panel, the row is skipped with a warning in the shell log
and the stock panel keeps working.

Omarchy 4.5 ships its own account switch (the panel's + button and
`omarchy agent account`). It gives each added account a separate
`CLAUDE_CONFIG_DIR`, which only reaches `claude` launched through Omarchy's mise
wrapper; here `claude` is `~/.local/bin/claude`. Add accounts with this row's
**+ Add**, not the stock +.

The shell watches its plugin folders, which hold only symlinks, so editing the
linked `Panel.qml` does not reload it. Run `omarchy restart shell`.

Extending the stock panel as a QML type does not work in the live shell: the
shell rewrites its files to `qs://` URLs and the stock panel's inline
components then fail to resolve (`DayRow is not a type`). One side effect of
wrapping: Tab does not move from this panel to its bar neighbors.

## Tests

```bash
python3 -m unittest discover -s tests -p 'test_claude_account.py' -v
python3 -m unittest discover -s tests -p 'test_agents_accounts.py' -v
```

The first swaps logins in a scratch home. The second runs the wrapper over the
installed stock panel offscreen, checks the row's placement, and switches
accounts through a stub CLI.
