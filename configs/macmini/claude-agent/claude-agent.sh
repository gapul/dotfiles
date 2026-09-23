#!/usr/bin/env bash
# The entry point for claude-agent. ~/.local/bin/claude-agent points here.
#
# Everything goes through this one command: running it by hand, and the per-repository
# caller workflow on the self-hosted runner. The real files live in the nix store, so
# updates arrive by rebuilding rather than by editing what is running.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
claude-agent - automatic fixes and reviews, resident on the mac mini

  claude-agent poll                       walk repos.json and handle what it finds
  claude-agent autofix <repo> issue:<n>   implement an issue and open a pull request
  claude-agent autofix <repo> run:<id>    repair a failed Actions run
  claude-agent review  <repo> <pr>        review a pull request
  claude-agent monitor                    check the agent's own health
  claude-agent status                     show the current state
  claude-agent pause / resume             stop everything / start again

Environment
  CLAUDE_AGENT_DRY_RUN=1   post and push nothing, only log what would have happened
  CLAUDE_AGENT_REPOS=path  use a different repos.json
USAGE
}

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
  poll)    exec bash "$DIR/poller.sh" "$@" ;;
  autofix) exec bash "$DIR/run-autofix.sh" "$@" ;;
  review)  exec bash "$DIR/run-review.sh" "$@" ;;
  monitor) exec bash "$DIR/monitor.sh" "$@" ;;
  pause)
    source "$DIR/lib.sh"
    date +%s > "$STATE_DIR/PAUSE"
    echo "Stopped. Start again with claude-agent resume."
    ;;
  resume)
    source "$DIR/lib.sh"
    rm -f "$STATE_DIR/PAUSE"
    echo "Started again."
    ;;
  status)
    source "$DIR/lib.sh"
    echo "Repositories:"
    repo_list | sed 's/^/  /'
    echo
    if [ -e "$STATE_DIR/PAUSE" ]; then
      echo "State: paused"
    else
      echo "State: running"
    fi
    dry && echo "DRY-RUN is on"
    for l in "$STATE_DIR"/*.lock; do
      [ -d "$l" ] && echo "In flight: $(basename "$l" .lock)"
    done
    if [ -e "$STATE_DIR/monitor.heartbeat" ]; then
      echo "Last monitor pass: $(date -r "$(cat "$STATE_DIR/monitor.heartbeat")" '+%Y-%m-%d %H:%M:%S')"
    fi
    echo
    echo "Recent log:"
    tail -20 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    ;;
  ''|-h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
