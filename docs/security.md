# Keeping this repository public

Credentials and private application source URLs belong in the private setup
repository or local runtime configuration. Public helpers read that configuration
at runtime. Supply both `WEWORK_WIFI_IDENTITY` and `WEWORK_WIFI_PASSWORD` through
the environment when using the Wi-Fi helper; neither has a stored default.

Install [Gitleaks](https://github.com/gitleaks/gitleaks#installing) (CI uses
8.30.1), then enable the repository's hooks in each clone:

```sh
git config --local core.hooksPath .githooks
python3 scripts/check_secrets.py
python3 scripts/check_secrets.py --history
```

The first scan includes tracked files and non-ignored new files. The commit hook
scans the exact index, including files force-added despite `.gitignore`. The push
hook and CI also scan all available history. Fetch every remote branch and tag
before a full audit. Reports print only paths, line numbers, rules and commit IDs;
temporary scanner reports are redacted. Ignored local files are not published
and are not part of the worktree scan.

Default Gitleaks rules are supplemented with checks for short literal passwords,
shell credential defaults, Wi-Fi account defaults, private app source URLs, and
credential files. The only keyboard shortcut exception is scoped to its exact
line and file. Test credentials use explicit synthetic values. Do not add broad
file exclusions or baselines to hide real findings.

If a real secret reaches Git, rotate it first. Deleting today's copy does not
remove history. Prepare and verify a separate cleaned clone before coordinating
a force-push; existing clones and GitHub pull-request/cached references may still
retain earlier commits. See [GitHub's removal guide](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
