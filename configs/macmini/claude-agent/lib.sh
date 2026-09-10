#!/usr/bin/env bash
# Shared library for claude-agent. Sourced by poller / autofix / review / monitor.
#
# There are two callers: launchd on the mac mini (poller and monitor), and GitHub
# Actions on the self-hosted runner that lives on the same machine. Neither gets a
# login shell, so everything the scripts need is set up here.

# LANG has to be set. With an empty locale, bash swallows a multi-byte character
# that follows a variable reference into the variable's name: `$ts。` becomes
# `ts。: unbound variable` and the script dies under `set -u`. The predecessor of
# this agent spent a full day dead that way (2026-09).
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

_whoami="$(id -un)"
export PATH="$HOME/.local/bin:/etc/profiles/per-user/${_whoami}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
unset _whoami

# Claude's subscription OAuth credentials. launchd and the runner do not carry this,
# so state it explicitly — without it every claude call dies with "Not logged in".
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"

# The mini is headless, so there is no interactive login to authenticate through.
# Auth comes from a token minted by `claude setup-token`, placed by sops at
# activation time (secrets/common.yaml, key claude_code_oauth_token). The keychain
# route does not work over SSH.
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -r "$CLAUDE_CONFIG_DIR/oauth-token" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$(cat "$CLAUDE_CONFIG_DIR/oauth-token")"
  export CLAUDE_CODE_OAUTH_TOKEN
fi

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_JSON="${CLAUDE_AGENT_REPOS:-$AGENT_DIR/repos.json}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-agent"
SEEN_DIR="$STATE_DIR/seen"
WORK_DIR="$STATE_DIR/repos"
LOG_FILE="$STATE_DIR/agent.log"
# Log what would have happened and change nothing. This is how the agent is rolled
# out: watch it for a day before letting it post anything.
DRY_RUN="${CLAUDE_AGENT_DRY_RUN:-0}"

mkdir -p "$SEEN_DIR" "$WORK_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

dry() { [ "$DRY_RUN" != "0" ]; }
is_true() { case "${1:-}" in true|1|yes) return 0 ;; *) return 1 ;; esac; }

# Notification. Reads the same ntfy files restic and dotfiles-pull use. There is no
# screen on this machine to put a dialog on, so this is the only way anything gets
# noticed. If it is not configured, log and carry on rather than fail.
notify() {
  local title="$1" body="$2" prio="${3:-default}"
  log "NOTIFY[$prio] ${title}: ${body}"
  local url_f="$HOME/.config/ntfy/url" tok_f="$HOME/.config/ntfy/token"
  [ -r "$url_f" ] && [ -r "$tok_f" ] || return 0
  curl -fsS --max-time 15 -o /dev/null \
    -H "Authorization: Bearer $(cat "$tok_f")" \
    -H "Title: claude-agent (macmini)" \
    -H "Priority: $prio" \
    -H "Tags: warning" \
    -d "$title
$body" "$(cat "$url_f")" >/dev/null 2>&1 || true
}

# --- kill switch --------------------------------------------------------
# A PAUSE file stops everything. To stop one issue or PR, label it no-claude.
paused() {
  if [ -e "$STATE_DIR/PAUSE" ]; then
    log "PAUSE file present, doing nothing"
    return 0
  fi
  return 1
}

# --- GitHub auth --------------------------------------------------------
# `gh auth token` echoes back whatever is in GITHUB_TOKEN, so clear that first to
# get at the real user token. The Actions GITHUB_TOKEN has no workflow scope, and a
# push that touches .github/workflows is rejected without it.
#
# `gh auth token` also returns empty on a transient failure. An empty GH_TOKEN takes
# precedence over hosts.yml, so every later gh call would run unauthenticated and
# fail. Export only when it is non-empty.
setup_gh_token() {
  unset GITHUB_TOKEN
  local t
  t="$(gh auth token 2>/dev/null || true)"
  if [ -n "$t" ]; then
    export GH_TOKEN="$t"
    GH_PUSH_TOKEN="$t"
  else
    unset GH_TOKEN
    GH_PUSH_TOKEN=""
    log "WARN: gh auth token came back empty, falling back to hosts.yml"
  fi
}

# --- locking ------------------------------------------------------------
# macOS has no flock, so lean on mkdir being atomic. A lock left behind by an
# abnormal exit is reclaimed after a while — being stuck forever is worse than the
# small risk of two runs overlapping.
LOCK_HELD=""
acquire_lock() {
  local name="$1" stale_min="${2:-60}"
  local lock="$STATE_DIR/${name}.lock"
  if [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin "+${stale_min}" 2>/dev/null)" ]; then
    log "reclaiming a stale lock: $name"
    rmdir "$lock" 2>/dev/null || true
  fi
  mkdir "$lock" 2>/dev/null || return 1
  LOCK_HELD="$lock"
  trap 'release_lock' EXIT
  trap 'release_lock; exit 143' INT TERM
  return 0
}
release_lock() {
  [ -n "$LOCK_HELD" ] && rmdir "$LOCK_HELD" 2>/dev/null
  LOCK_HELD=""
}

# --- what has already been handled --------------------------------------
# Keys are repo/kind/id. A PR review key carries the head SHA, so a new push gets
# reviewed again while the same commit never does.
_seen_path() { printf '%s/%s\n' "$SEEN_DIR" "${1//\//__}"; }
seen()      { [ -e "$(_seen_path "$1")" ]; }
mark_seen() { date +%s > "$(_seen_path "$1")"; }

# --- repos.json ---------------------------------------------------------
repo_list() {
  jq -r '.repos[] | select(.enabled != false) | .repo' "$REPOS_JSON" 2>/dev/null
}

repo_allowed() {
  jq -e --arg r "$1" '[.repos[] | select(.repo == $r and (.enabled != false))] | length > 0' \
    "$REPOS_JSON" >/dev/null 2>&1
}

# jq's // treats false as absent, so it cannot be used for boolean policies that
# default to true. Branch on has() instead.
policy() {
  local repo="$1" key="$2" default="$3" out
  out="$(jq -r --arg r "$repo" --arg k "$key" --arg d "$default" '
    first(.repos[] | select(.repo == $r)) as $x
    | if $x == null then $d
      elif ($x | has($k)) then ($x[$k] | tostring)
      else $d end
  ' "$REPOS_JSON" 2>/dev/null)"
  printf '%s\n' "${out:-$default}"
}

# --- working copies -----------------------------------------------------
# Cloning per task is too slow, so keep one checkout per repository and reuse it.
# Only one claude runs at a time (global lock), so nothing contends for the tree.
repo_dir() { printf '%s/%s\n' "$WORK_DIR" "${1//\//__}"; }

# Land on a clean checkout of the given ref and cd there. Ignored files
# (node_modules and friends) are kept: removing them only makes every run slower,
# and they are not a source of contamination.
prepare_repo() {
  local repo="$1" ref="$2" dir
  dir="$(repo_dir "$repo")"
  if [ ! -d "$dir/.git" ]; then
    log "cloning $repo"
    git clone --quiet "https://github.com/${repo}.git" "$dir" || return 1
  fi
  cd "$dir" || return 1
  # Push with the token embedded in the URL. Under launchd the osxkeychain helper
  # cannot reach the login keychain and fails with "failed to store: -25308".
  git config --local credential.helper ""
  git config --local user.name "claude-macmini[bot]"
  git config --local user.email "claude-macmini@users.noreply.github.com"
  if [ -n "${GH_PUSH_TOKEN:-}" ]; then
    git remote set-url origin "https://x-access-token:${GH_PUSH_TOKEN}@github.com/${repo}.git"
  fi
  git fetch --quiet --prune origin || return 1
  git reset --quiet --hard HEAD 2>/dev/null || true
  git clean --quiet -fd 2>/dev/null || true
  git checkout --quiet -B "__base" "$ref" 2>/dev/null || {
    log "ERROR: cannot check out $ref in $repo"
    return 1
  }
  return 0
}

# --- running claude -----------------------------------------------------
# First argument is the prompt, second is where to write the output, the rest are
# passed through to claude.
run_claude() {
  local prompt="$1" out="$2"; shift 2
  if dry; then
    log "DRY-RUN: would call claude here (log=$out, args=$*)"
    printf 'DRY-RUN\n' > "$out"
    return 0
  fi
  claude -p "$prompt" "$@" > "$out" 2>&1
  local rc=$?
  # An expired login produces a system that quietly does nothing, so make sure it
  # is impossible to miss.
  if grep -qa 'Not logged in' "$out"; then
    notify "claude-agent: not authenticated" "Claude Code on the mac mini is not logged in. Re-run claude setup-token and update the sops secret." high
    return 90
  fi
  return $rc
}
