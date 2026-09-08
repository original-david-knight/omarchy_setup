#!/usr/bin/env bash
set -euo pipefail

# Keep the running bootstrap in a function: refreshing this checkout may replace
# bootstrap.sh itself before the wizard starts.
main() {
  local repo_url=https://github.com/original-david-knight/omarchy_setup.git
  local setup_dir=${OMARCHY_SETUP_DIR:-$HOME/omarchy_setup}
  local origin branch clone_dir='' revision

  if [[ ${1:-} == --help ]]; then
    cat <<'HELP'
Usage: bootstrap.sh [setup.sh arguments]

Clone or refresh omarchy_setup from GitHub main, then start its setup wizard.
Run in a terminal as your desktop user after Omarchy installation.
OMARCHY_SETUP_DIR overrides the checkout path (default: ~/omarchy_setup).
If GitHub is unavailable, setup waits and resumes when connectivity returns.
Connect Wi-Fi using the desktop network menu; Ctrl+C pauses setup.

Examples:
  ./bootstrap.sh
  ./bootstrap.sh --profile laptop
  ./bootstrap.sh --public-only --plan

All arguments are passed to setup.sh. Even --plan refreshes the checkout;
run ./setup.sh --plan directly for a preview that writes nothing.
HELP
    exit 0
  fi

  command -v git >/dev/null || { echo 'Git is required. Complete the Omarchy installation first.' >&2; exit 1; }
  command -v timeout >/dev/null || { echo 'GNU timeout is required. Complete the Omarchy installation first.' >&2; exit 1; }
  [[ $setup_dir == /* ]] || { echo 'OMARCHY_SETUP_DIR must be an absolute path.' >&2; exit 1; }

  trap '[[ -z ${clone_dir:-} ]] || rm -rf -- "$clone_dir"' EXIT
  trap 'printf "\nSetup paused. Run omarchy-personal-setup or bootstrap.sh to resume.\n"; exit 130' INT
  trap 'exit 143' TERM

  github_available() {
    timeout --signal=TERM --kill-after=2s 15s env GIT_TERMINAL_PROMPT=0 \
      git ls-remote --exit-code "$repo_url" refs/heads/main >/dev/null 2>&1
  }

  wait_for_github() {
    local waiting=false
    until github_available; do
      if [[ $waiting == false ]]; then
        printf '\nWaiting for internet access to GitHub.\n'
        printf 'Connect Wi-Fi from the desktop network menu. Keep this window open; setup will resume automatically.\n'
        printf 'Checking every 5 seconds. Press Ctrl+C to pause.\n'
        waiting=true
      fi
      sleep 5
    done
    [[ $waiting == false ]] || printf '\nGitHub is reachable. Continuing setup...\n'
  }

  transfer() {
    local operation=$1 failures=0
    shift
    while :; do
      wait_for_github
      if GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 "$@"; then
        return 0
      fi
      # A disconnected transfer can leave a partial clone. Only remove the
      # temporary directory created by this invocation, never an existing repo.
      if [[ $operation == clone ]]; then
        rm -rf -- "$clone_dir"
        mkdir -- "$clone_dir"
      fi
      if ! github_available; then
        failures=0
        continue
      fi
      failures=$((failures + 1))
      if ((failures >= 3)); then
        echo 'GitHub is reachable, but the Git transfer keeps failing. Resolve the error above and retry setup.' >&2
        return 1
      fi
      printf 'Git transfer failed. Retrying in 5 seconds...\n'
      sleep 5
    done
  }

  if [[ ! -e $setup_dir && ! -L $setup_dir ]]; then
    mkdir -p -- "$(dirname -- "$setup_dir")"
    clone_dir=$(mktemp -d "$(dirname -- "$setup_dir")/.omarchy-setup-clone.XXXXXX")
    printf 'Downloading setup from GitHub main...\n'
    transfer clone clone --branch main --single-branch -- "$repo_url" "$clone_dir" || exit 1
    mv -T -- "$clone_dir" "$setup_dir"
    clone_dir=''
  else
    # Do not mistake a directory inside another checkout for this repository.
    if [[ ! -d $setup_dir ]] ||
      [[ $(git -C "$setup_dir" rev-parse --show-toplevel 2>/dev/null || true) != "$(cd -- "$setup_dir" && pwd -P)" ]]; then
      echo 'The setup destination exists but is not a Git checkout. Choose another OMARCHY_SETUP_DIR.' >&2
      exit 1
    fi
    origin=$(git -C "$setup_dir" config --get remote.origin.url || true)
    case $origin in
      https://github.com/original-david-knight/omarchy_setup.git | https://github.com/original-david-knight/omarchy_setup | \
        git@github.com:original-david-knight/omarchy_setup.git | ssh://git@github.com/original-david-knight/omarchy_setup.git) ;;
      *) echo 'The setup checkout origin is not the public omarchy_setup repository. Choose another OMARCHY_SETUP_DIR.' >&2; exit 1 ;;
    esac
    branch=$(git -C "$setup_dir" symbolic-ref --quiet --short HEAD || true)
    if [[ $branch != main || -n $(git -C "$setup_dir" status --porcelain --untracked-files=all) ]]; then
      echo 'Setup has local changes or is not on main. Preserve your work and return to a clean main checkout before refreshing.' >&2
      exit 1
    fi
    printf 'Refreshing setup from GitHub main...\n'
    # Always use public HTTPS, even when this checkout normally uses SSH.
    if ! transfer fetch -C "$setup_dir" fetch --no-tags "$repo_url" refs/heads/main:refs/remotes/origin/main; then
      printf 'To explicitly use the cached version, run: bash %q\n' "$setup_dir/setup.sh" >&2
      exit 1
    fi
    # The user may have edited or switched this checkout while Wi-Fi was down.
    if [[ $(git -C "$setup_dir" symbolic-ref --quiet --short HEAD || true) != main ||
      -n $(git -C "$setup_dir" status --porcelain --untracked-files=all) ]]; then
      echo 'Setup changed while waiting. Preserve your work and return to a clean main checkout before refreshing.' >&2
      exit 1
    fi
    if ! git -C "$setup_dir" merge-base --is-ancestor HEAD refs/remotes/origin/main; then
      echo 'Local main has commits outside GitHub main. Preserve your work before refreshing; no reset was performed.' >&2
      exit 1
    fi
    git -C "$setup_dir" merge --ff-only refs/remotes/origin/main
  fi

  [[ -f $setup_dir/setup.sh ]] || { echo 'The checkout does not contain setup.sh.' >&2; exit 1; }
  revision=$(git -C "$setup_dir" rev-parse --short HEAD)
  printf '\nStarting setup at revision %s\n' "$revision"
  cd -- "$setup_dir"
  exec bash ./setup.sh "$@"
}

main "$@"
