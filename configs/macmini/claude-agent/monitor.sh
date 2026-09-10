#!/usr/bin/env bash
# Check once an hour that claude-agent itself is still alive.
#
# Deliberately not run through the thing it watches (GitHub Actions). Monitoring
# built on top of the broken system goes quiet exactly when the system breaks, so
# this runs from launchd on the mac mini instead.
#
# Calling claude on every pass would be waste, so a cheap shell pass looks for the
# failures that are visible without it. When nothing is wrong it writes a heartbeat
# and stops; claude only gets involved when something is.
#
# The prompt stays Japanese: what it produces is read by a person.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_gh_token
HEARTBEAT="$STATE_DIR/monitor.heartbeat"
NOW="$(date +%s)"
date +%s > "$HEARTBEAT"

ANOMALY=""
DETAIL=""
add() { ANOMALY="${ANOMALY}$1; "; DETAIL="${DETAIL}
- $1"; }

# --- machine-wide -------------------------------------------------------
# Is the poller running at all? When launchd drops it, nothing happens and nothing
# says so.
if [ -e "$LOG_FILE" ]; then
  last_log="$(stat -f %m "$LOG_FILE" 2>/dev/null || echo 0)"
  if [ "$(( NOW - last_log ))" -gt 1800 ]; then
    add "the poller has not written a log line in over 30 minutes (launchd may have stopped it)"
  fi
else
  add "there is no log file; the agent has never run"
fi

# An expired login turns the whole thing into a system that quietly does nothing.
if [ -e "$LOG_FILE" ] && tail -500 "$LOG_FILE" | grep -q 'not authenticated'; then
  add "Claude Code is not authenticated (claude setup-token needs redoing)"
fi
if ! gh auth status >/dev/null 2>&1; then
  add "gh is not authenticated"
fi

# A kill switch left on and forgotten about
if [ -e "$STATE_DIR/PAUSE" ]; then
  paused_at="$(stat -f %m "$STATE_DIR/PAUSE" 2>/dev/null || echo "$NOW")"
  [ "$(( NOW - paused_at ))" -gt 86400 ] && add "PAUSE has been in place for more than a day"
fi

# A lock nobody released
for l in "$STATE_DIR"/*.lock; do
  [ -d "$l" ] || continue
  [ -n "$(find "$l" -maxdepth 0 -mmin +90 2>/dev/null)" ] && add "a lock has been held for over 90 minutes: $(basename "$l")"
done

# --- per repository -----------------------------------------------------
for repo in $(repo_list); do
  # For repositories that use self-hosted runners, check that one is online.
  runners="$(gh api "repos/${repo}/actions/runners" -q '[.runners[] | select(.status=="online")] | length' 2>/dev/null || echo "")"
  total="$(gh api "repos/${repo}/actions/runners" -q '.runners | length' 2>/dev/null || echo "")"
  if [ -n "$total" ] && [ "$total" != "0" ] && [ "${runners:-0}" = "0" ]; then
    add "$repo: ${total} runners are registered but none are online"
  fi

  # Leftovers from a job that died
  stale="$(gh issue list --repo "$repo" --label claude-in-progress --state open --json updatedAt \
    -q '[.[] | select((now - (.updatedAt|fromdateiso8601)) > 3600)] | length' 2>/dev/null || echo 0)"
  case "$stale" in ''|*[!0-9]*) stale=0 ;; esac
  [ "$stale" -gt 0 ] && add "$repo: ${stale} issues have been claude-in-progress for over an hour"

  # Pull requests the agent opened that are stuck on a failing check
  stuck="$(gh pr list --repo "$repo" --state open --limit 30 --json headRefName,statusCheckRollup \
    -q '[.[] | select(.headRefName | startswith("claude/")) | select([.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length > 0)] | length' 2>/dev/null || echo 0)"
  case "$stuck" in ''|*[!0-9]*) stuck=0 ;; esac
  [ "$stuck" -gt 0 ] && add "$repo: ${stuck} claude/* pull requests are stuck with failing checks"
done

if [ -z "$ANOMALY" ]; then
  log "monitor: healthy (shell pass only, claude not called)"
  exit 0
fi

log "monitor: anomaly: ${ANOMALY}escalating to claude"

if dry; then
  log "DRY-RUN: would call claude to investigate here"
  exit 0
fi

acquire_lock claude 60 || { log "another claude is running, investigating on the next pass"; exit 0; }

out="$STATE_DIR/logs/monitor.log"
mkdir -p "$(dirname "$out")"
prompt="あなたは macmini 上で動く自動修正・自動レビュー基盤 (claude-agent) の監視担当です。
シェルによる一次判定で次の異常が出ています。

${DETAIL}

対象リポジトリ: $(repo_list | tr '\n' ' ')
状態ディレクトリ: ${STATE_DIR} (agent.log にポーラーと修正の記録、logs/ に各実行の出力)

やること:
1. gh コマンドと ${STATE_DIR} のログを読んで、何が起きているかを特定する。
2. 自分で直せる範囲なら直す。具体的には次まで。
   - セルフホスト runner が落ちている場合の再起動 (~/actions-runner/svc.sh stop; ~/actions-runner/svc.sh start)
   - 90分以上残っている ${STATE_DIR} 配下のロックディレクトリの削除
   - 停滞している claude-in-progress ラベルの掛け直し (claude-failed へ)
3. リポジトリのコードには一切触らないこと。基盤の復旧だけが仕事で、コードの修正は run-autofix.sh の仕事。
4. 最後に、次の1行だけの形式で結果を書くこと。

REPORT: <何が起きていたか / 何をしたか / 人がやる必要が残っているか を1〜3文で>

人手が要るもの (認証の失効、GitHub 側の設定、ハードウェア) は自分で解決しようとせず、REPORT に書いて終わること。"

run_claude "$prompt" "$out" --dangerously-skip-permissions --max-turns 30
rc=$?
report="$(grep -a '^REPORT:' "$out" | tail -1 | sed 's/^REPORT:[[:space:]]*//')"
if [ "$rc" = 90 ]; then
  # run_claude has already sent the not-authenticated notification
  exit 1
fi
notify "claude-agent: anomaly detected" "${ANOMALY}
${report:-(claude returned no REPORT line; see $out)}" high
log "monitor: ${report:-no REPORT line}"
