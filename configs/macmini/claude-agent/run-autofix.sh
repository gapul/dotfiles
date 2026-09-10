#!/usr/bin/env bash
# The fixing half of claude-agent. Handles both issue-driven work and failed
# GitHub Actions runs.
#
#   run-autofix.sh <owner/repo> issue:<number>
#   run-autofix.sh <owner/repo> run:<run id>
#
# The poller and the per-repository caller workflow (running on the self-hosted
# runner on this same machine) both come through here. This script always owns its
# working tree, so callers do not need to check anything out.
#
# Text posted to GitHub stays Japanese: it is prose addressed to the people reading
# those issues and pull requests.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO="${1:?usage: run-autofix.sh <owner/repo> issue:<n>|run:<id>}"
TARGET="${2:?usage: run-autofix.sh <owner/repo> issue:<n>|run:<id>}"
KIND="${TARGET%%:*}"
ID="${TARGET#*:}"
MARK="<!-- claude-bot -->"

paused && exit 0
repo_allowed "$REPO" || { log "not in repos.json, doing nothing: $REPO"; exit 0; }
setup_gh_token

BASE="$(policy "$REPO" base main)"

# Attempt cap, counted over 24 hours. Hammering at something unfixable forever is
# the worst failure mode available, so give up quietly instead.
attempts_ok() {
  local key="$1" cap="$2" f
  f="$(_seen_path "attempts/$key")"
  mkdir -p "$(dirname "$f")"
  # forget counts older than a day
  [ -e "$f" ] && [ -n "$(find "$f" -maxdepth 0 -mtime +1 2>/dev/null)" ] && rm -f "$f"
  local n
  n="$(cat "$f" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -ge "$cap" ] && { log "attempt cap reached ($cap per 24h): $key"; return 1; }
  printf '%s\n' "$(( n + 1 ))" > "$f"
  return 0
}

acquire_lock claude 60 || { log "another claude is running, deferring: $REPO $TARGET"; exit 0; }

# ---------------------------------------------------------------- issues
run_issue() {
  local n="$ID"
  is_true "$(policy "$REPO" autofix_issues true)" || { log "autofix_issues=false: $REPO"; return 0; }

  local meta
  meta="$(gh issue view "$n" --repo "$REPO" --json number,title,body,state,updatedAt,labels 2>/dev/null)"
  [ -z "$meta" ] && { log "cannot read issue #$n: $REPO"; return 1; }

  local state labels title body updated
  state="$(jq -r .state <<<"$meta")"
  labels="$(jq -r '[.labels[].name] | join(",")' <<<"$meta")"
  title="$(jq -r .title <<<"$meta")"
  body="$(jq -r .body <<<"$meta")"
  updated="$(jq -r .updatedAt <<<"$meta")"

  [ "$state" != "OPEN" ] && { log "issue #$n is not open"; return 0; }
  case ",$labels," in *,no-claude,*) log "labelled no-claude: #$n"; return 0 ;; esac
  seen "$REPO/issue-$n/$updated" && { log "already handled: #$n ($updated)"; return 0; }
  attempts_ok "$REPO/issue-$n" 3 || return 0

  note() { gh issue comment "$n" --repo "$REPO" --body "$1
$MARK" >/dev/null 2>&1 || true; }
  label() { gh issue edit "$n" --repo "$REPO" "$@" >/dev/null 2>&1 || true; }

  if dry; then
    log "DRY-RUN: would fix issue #$n ($title)"
    mark_seen "$REPO/issue-$n/$updated"
    return 0
  fi

  label --add-label claude-in-progress
  label --remove-label claude-needs-info

  prepare_repo "$REPO" "origin/$BASE" || { label --remove-label claude-in-progress --add-label claude-failed; return 1; }
  local branch="claude/issue-${n}"
  git checkout --quiet -B "$branch" || return 1

  # Feed the thread back in as context (answers to earlier questions and so on),
  # minus the bot's own comments.
  local thread
  thread="$(gh issue view "$n" --repo "$REPO" --comments \
    --json comments -q '.comments[] | "--- " + .author.login + ":\n" + .body' 2>/dev/null | grep -v "$MARK" || true)"

  local prompt log_file
  log_file="$STATE_DIR/logs/issue-${n}.log"
  mkdir -p "$(dirname "$log_file")"
  prompt="あなたは GitHub issue を自動修正するエンジニアです。リポジトリ ${REPO} で issue #${n} を実装してください。

タイトル: ${title}

本文:
${body}

これまでのコメント (人からの追加指示・質問への回答を含む):
${thread:-（コメントなし）}

要件:
- まず、要望された機能・修正がコードベースに既に存在しないか調べること。利用者は仕様を知らないことが多い。既に同等の機能がある場合はコードを変更せず、出力の最後の行に「EXISTS: <既にある機能の説明を2〜3文で。どこにあるか含める>」と書いて終了する。
- 一部だけ足りない場合は、既にある部分は触らず、本当に必要な差分だけ実装する。
- 変更は最小限で、既存のコードスタイルに合わせる。
- 検証: $(policy "$REPO" verify_hint '関連するビルド・テストがあればローカルで実行して通すこと。')
- コミットはしないでよい (このスクリプトが行う)。
- 情報が足りず実装できない場合は、コードを一切変更せず、出力の最後の行に「QUESTION: <確認したい具体的な質問>」の形式で1行だけ書いて終了すること。推測で危険な実装をするより質問を優先する。
(EXISTS と QUESTION を同時に出さないこと。既にあるなら EXISTS を優先。)"

  log "running claude: $REPO issue #$n"
  run_claude "$prompt" "$log_file" --dangerously-skip-permissions --max-turns 60
  local rc=$?
  [ "$rc" = 90 ] && { label --remove-label claude-in-progress --add-label claude-failed; return 1; }

  if [ -z "$(git status --porcelain)" ]; then
    # No code changed. Prefer EXISTS (it already exists) over QUESTION (needs
    # information) over outright failure.
    local ex q
    ex="$(grep -a '^EXISTS:' "$log_file" | tail -1 | sed 's/^EXISTS:[[:space:]]*//')"
    q="$(grep -a '^QUESTION:' "$log_file" | tail -1 | sed 's/^QUESTION:[[:space:]]*//')"
    if [ -n "$ex" ]; then
      note "🤖 これはすでにある機能かもしれません。

${ex}

これのことでしょうか。違っていれば、この issue に返信いただければ実装します。"
      label --remove-label claude-in-progress --add-label claude-needs-info
    elif [ -n "$q" ]; then
      note "🤖 実装する前に確認させてください。

${q}

この issue に返信いただければ続きを進めます。"
      label --remove-label claude-in-progress --add-label claude-needs-info
    else
      note "🤖 確認しましたが、コード変更は生成されませんでした。指示を具体化して \`claude-fix\` ラベルを付け直すと再実行します。"
      label --remove-label claude-in-progress --add-label claude-failed
    fi
    mark_seen "$REPO/issue-$n/$updated"
    mark_seen "$REPO/issue-$n/$(gh issue view "$n" --repo "$REPO" --json updatedAt -q .updatedAt 2>/dev/null)"
    return 0
  fi

  git add -A
  git commit -q -m "fix: #${n} ${title}

Closes #${n}

🤖 auto-fixed by Claude Code on macmini"
  git push -f origin "$branch" || { label --remove-label claude-in-progress --add-label claude-failed; return 1; }

  local pr_url
  pr_url="$(open_or_create_pr "$branch" "fix: #${n} ${title}" "Closes #${n}

🤖 Claude Code (macmini) による自動修正。
$MARK")"
  if [ -z "$pr_url" ]; then
    note "🤖 修正は push しましたが (ブランチ \`${branch}\`)、PR の URL が取得できませんでした。手動で PR を作るか、\`claude-fix\` ラベルを付け直すと再実行します。"
    label --remove-label claude-in-progress --add-label claude-failed
    return 1
  fi
  label --remove-label claude-in-progress --add-label claude-done
  note "🤖 修正して PR を作成しました: ${pr_url}"
  mark_seen "$REPO/issue-$n/$updated"
  mark_seen "$REPO/issue-$n/$(gh issue view "$n" --repo "$REPO" --json updatedAt -q .updatedAt 2>/dev/null)"
  log "done: $pr_url"
}

# Open the pull request. gh occasionally fails transiently without returning a URL,
# so retry a few times and pick up an existing PR if there is one. Only the URL goes
# to stdout.
open_or_create_pr() {
  local branch="$1" title="$2" body="$3" url out attempt
  for attempt in 1 2 3; do
    url="$(gh pr list --repo "$REPO" --head "$branch" --json url -q '.[0].url' 2>/dev/null)"
    [ -n "$url" ] && { printf '%s\n' "$url"; return 0; }
    out="$(gh pr create --repo "$REPO" --base "$BASE" --head "$branch" \
      --title "$title" --body "$body" 2>&1)"
    log "gh pr create (attempt ${attempt}): $out"
    url="$(printf '%s\n' "$out" | grep -o 'https://github.com/[^[:space:]]*/pull/[0-9][0-9]*' | tail -1)"
    [ -n "$url" ] && { printf '%s\n' "$url"; return 0; }
    sleep 5
  done
  return 1
}

# ------------------------------------------------- failed Actions runs
# Infrastructure failures are separated out: no code change fixes a dead runner, a
# broken network, a rate limit, a full disk, or a job that ran out of time.
infra_failure() {
  grep -qaE 'lost communication with the server|has not been able to communicate|Waiting for a runner|no space left on device|Could not resolve host|429 Too Many Requests|You have exceeded a secondary rate limit|The operation was canceled|exceeded the maximum execution time|The runner has received a shutdown signal' "$1"
}

run_ci() {
  local id="$ID"
  is_true "$(policy "$REPO" autofix_ci true)" || { log "autofix_ci=false: $REPO"; return 0; }

  local meta
  meta="$(gh run view "$id" --repo "$REPO" \
    --json databaseId,workflowName,headBranch,headSha,conclusion,event,createdAt 2>/dev/null)"
  [ -z "$meta" ] && { log "cannot read run $id: $REPO"; return 1; }

  local wf branch sha conclusion
  wf="$(jq -r .workflowName <<<"$meta")"
  branch="$(jq -r .headBranch <<<"$meta")"
  sha="$(jq -r .headSha <<<"$meta")"
  conclusion="$(jq -r .conclusion <<<"$meta")"

  [ "$conclusion" != "failure" ] && { log "run $id did not fail ($conclusion)"; return 0; }

  # Never react to claude-agent's own workflows. This is where the loop of trying to
  # fix its own failure forever gets cut.
  local ignore
  ignore="$(jq -r --arg r "$REPO" 'first(.repos[] | select(.repo == $r)) | (.ignore_workflows // []) | join("\n")' "$REPOS_JSON" 2>/dev/null)"
  while IFS= read -r w; do
    [ -n "$w" ] && [ "$w" = "$wf" ] && { log "own workflow, ignoring: $wf"; return 0; }
  done <<<"$ignore"

  seen "$REPO/run-$id" && { log "already handled: run $id"; return 0; }

  # If the same workflow on the same branch has succeeded since, it is already
  # fixed. A flaky run that passed on retry drops out here too.
  local newer_ok
  newer_ok="$(gh run list --repo "$REPO" --workflow "$wf" --branch "$branch" --limit 10 \
    --json databaseId,conclusion,createdAt \
    -q "[.[] | select(.databaseId > ${id} and .conclusion == \"success\")] | length" 2>/dev/null || echo 0)"
  case "$newer_ok" in ''|*[!0-9]*) newer_ok=0 ;; esac
  if [ "$newer_ok" -gt 0 ]; then
    log "a later run succeeded, nothing to do (flaky or already fixed): $wf / $branch"
    mark_seen "$REPO/run-$id"
    return 0
  fi

  attempts_ok "$REPO/ci/${wf}/${branch}" 2 || { mark_seen "$REPO/run-$id"; return 0; }

  local log_raw="$STATE_DIR/logs/run-${id}.txt"
  mkdir -p "$(dirname "$log_raw")"
  gh run view "$id" --repo "$REPO" --log-failed > "$log_raw" 2>/dev/null || true
  if [ ! -s "$log_raw" ]; then
    log "no failure log for run $id; the job probably never started, treating as infrastructure"
    notify "claude-agent: CI failed with no log" "$REPO / $wf / $branch run $id died without leaving a failure log." high
    mark_seen "$REPO/run-$id"
    return 0
  fi
  if infra_failure "$log_raw"; then
    log "infrastructure failure, leaving the code alone: $wf / $branch"
    notify "claude-agent: CI failed on infrastructure" "$REPO / $wf / $branch (run $id). Runner, network or rate limit. Log: $log_raw" high
    mark_seen "$REPO/run-$id"
    return 0
  fi

  if dry; then
    log "DRY-RUN: would fix $wf in $REPO ($branch, run $id)"
    mark_seen "$REPO/run-$id"
    return 0
  fi

  # Decide where the fix lands. A failure on a pull request branch gets a commit on
  # that branch so the PR moves forward; a failure on the base branch gets its own
  # branch and a new PR.
  local work_branch new_branch=0
  if [ "$branch" = "$BASE" ] || [ -z "$branch" ]; then
    work_branch="claude/ci-${id}"
    new_branch=1
    prepare_repo "$REPO" "$sha" || return 1
    git checkout --quiet -B "$work_branch" || return 1
  else
    work_branch="$branch"
    prepare_repo "$REPO" "origin/$BASE" || return 1
    git checkout --quiet -B "$work_branch" "origin/$work_branch" || {
      log "branch $work_branch is not on origin (looks like a fork PR), leaving it alone"
      mark_seen "$REPO/run-$id"
      return 0
    }
  fi

  local prompt log_file
  log_file="$STATE_DIR/logs/ci-${id}.log"
  prompt="あなたは壊れた CI を直すエンジニアです。リポジトリ ${REPO} のワークフロー「${wf}」が、ブランチ ${branch} (commit ${sha}) で失敗しました。

以下は失敗したジョブのログです (末尾 400 行)。

$(tail -400 "$log_raw")

要件:
- 失敗の根本原因を直すこと。
- テストを削る、skip する、アサーションを緩める、continue-on-error を足す、といった「通すためだけの変更」は禁止。それをしたくなったら、代わりに何もせず最後の行に「UNCLEAR: <理由>」と書いて終了すること。
- 変更は失敗の原因に関係する範囲だけに絞る。ついでの整理はしない。
- 検証: $(policy "$REPO" verify_hint '直したら、落ちていたのと同じコマンドをローカルで実行して通ることを確かめること。')
- コミットはしないでよい (このスクリプトが行う)。
- 原因が特定できない場合も、コードを変更せず最後の行に「UNCLEAR: <調べたことと、分からなかった点>」と1行で書いて終了すること。"

  log "running claude: $REPO CI $wf (run $id)"
  run_claude "$prompt" "$log_file" --dangerously-skip-permissions --max-turns 60
  local rc=$?
  [ "$rc" = 90 ] && return 1

  if [ -z "$(git status --porcelain)" ]; then
    local unclear
    unclear="$(grep -a '^UNCLEAR:' "$log_file" | tail -1 | sed 's/^UNCLEAR:[[:space:]]*//')"
    notify "claude-agent: could not fix CI" "$REPO / $wf / $branch (run $id)
${unclear:-no code change was produced}" high
    mark_seen "$REPO/run-$id"
    return 0
  fi

  git add -A
  git commit -q -m "fix(ci): repair the failing ${wf} run

Failed run: https://github.com/${REPO}/actions/runs/${id}

🤖 auto-fixed by Claude Code on macmini"
  git push origin "$work_branch" || { log "push failed: $work_branch"; return 1; }

  if [ "$new_branch" = 1 ]; then
    local pr_url
    pr_url="$(open_or_create_pr "$work_branch" "fix(ci): repair the failing ${wf} run" "${BASE} で「${wf}」が失敗していたので直しました。

失敗した run: https://github.com/${REPO}/actions/runs/${id}

🤖 Claude Code (macmini) による自動修正。
$MARK")"
    log "done: ${pr_url:-failed to create the PR}"
  else
    log "done: pushed a fix to $work_branch (the existing PR reruns CI)"
  fi
  mark_seen "$REPO/run-$id"
}

case "$KIND" in
  issue) run_issue ;;
  run)   run_ci ;;
  *) log "unknown target: $TARGET"; exit 2 ;;
esac
