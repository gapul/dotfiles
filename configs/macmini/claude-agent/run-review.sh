#!/usr/bin/env bash
# Read a pull request and leave a review.
#
#   run-review.sh <owner/repo> <pr number>
#
# Other people's pull requests are in scope, which is why this is the one place
# claude runs read-only. Once a fork's code is on the machine, building or testing
# it is the same thing as executing it; reading it is harmless whatever it contains.
#
# Intervention stops at comments and suggestions. Nothing is pushed to someone
# else's branch, and neither REQUEST_CHANGES nor APPROVE is ever submitted — a bot
# should not be able to block a person's pull request.
#
# The review text itself stays Japanese: it is prose for the people reading it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO="${1:?usage: run-review.sh <owner/repo> <pr>}"
PR="${2:?usage: run-review.sh <owner/repo> <pr>}"
MARK="<!-- claude-bot -->"

paused && exit 0
repo_allowed "$REPO" || { log "not in repos.json, doing nothing: $REPO"; exit 0; }
is_true "$(policy "$REPO" review true)" || { log "review=false: $REPO"; exit 0; }
setup_gh_token

ME="$(gh api user -q .login 2>/dev/null || echo gapul)"

meta="$(gh pr view "$PR" --repo "$REPO" \
  --json number,title,body,state,isDraft,author,headRefName,headRefOid,labels,additions,deletions,changedFiles 2>/dev/null)"
[ -z "$meta" ] && { log "cannot read PR #$PR: $REPO"; exit 1; }

state="$(jq -r .state <<<"$meta")"
draft="$(jq -r .isDraft <<<"$meta")"
author="$(jq -r .author.login <<<"$meta")"
title="$(jq -r .title <<<"$meta")"
body="$(jq -r .body <<<"$meta")"
sha="$(jq -r .headRefOid <<<"$meta")"
labels="$(jq -r '[.labels[].name] | join(",")' <<<"$meta")"
changed="$(jq -r .changedFiles <<<"$meta")"

[ "$state" != "OPEN" ] && { log "PR #$PR is not open"; exit 0; }
is_true "$draft" && { log "draft, skipping: PR #$PR"; exit 0; }
case ",$labels," in *,no-claude,*) log "labelled no-claude: PR #$PR"; exit 0 ;; esac

# Never review a pull request the bot itself opened, or it spends its time filing
# complaints about its own work.
case "$author" in
  claude-macmini*|*'[bot]'|github-actions) log "bot-authored, skipping: $author"; exit 0 ;;
esac
case ",$labels," in *,claude-done,*) log "opened by claude, skipping: #$PR"; exit 0 ;; esac

if [ "$author" != "$ME" ]; then
  is_true "$(policy "$REPO" review_others true)" || { log "review_others=false, skipping: $author"; exit 0; }
fi

# Key on the head SHA, so a new push gets reviewed again and the same commit does not.
seen "$REPO/pr-$PR/$sha" && { log "already reviewed: PR #$PR ($sha)"; exit 0; }

# Very large pull requests cannot be read properly, and half a review is worse than
# none, so leave them alone.
case "$changed" in ''|*[!0-9]*) changed=0 ;; esac
if [ "$changed" -gt 60 ]; then
  log "too many changed files ($changed), skipping: PR #$PR"
  mark_seen "$REPO/pr-$PR/$sha"
  exit 0
fi

if dry; then
  log "DRY-RUN: would review PR #$PR ($title, by $author, $changed files)"
  mark_seen "$REPO/pr-$PR/$sha"
  exit 0
fi

acquire_lock claude 60 || { log "another claude is running, deferring: review $REPO #$PR"; exit 0; }

diff_file="$STATE_DIR/logs/pr-${PR}.diff"
mkdir -p "$(dirname "$diff_file")"
gh pr diff "$PR" --repo "$REPO" > "$diff_file" 2>/dev/null || true
[ -s "$diff_file" ] || { log "cannot fetch the diff: PR #$PR"; exit 1; }

# Put the code under review on disk. pull/N/head works even for fork pull requests.
# The diff alone is enough to review from, so carry on if this fails.
if prepare_repo "$REPO" "origin/$(policy "$REPO" base main)"; then
  git fetch --quiet origin "pull/${PR}/head:refs/remotes/pr/${PR}" 2>/dev/null \
    && git checkout --quiet --detach "refs/remotes/pr/${PR}" 2>/dev/null \
    && log "checked PR #$PR out into the working tree"
fi

out="$STATE_DIR/logs/review-${PR}.log"
prompt="あなたは ${REPO} のコードレビュアーです。PR #${PR} をレビューしてください。

タイトル: ${title}
作成者: ${author}

本文:
${body:-（本文なし）}

差分:
\`\`\`diff
$(cat "$diff_file")
\`\`\`

作業ディレクトリにはこの PR の内容がチェックアウトされているので、周辺のコードを読んで判断してよい。ただしファイルの読み取りと検索しかできない (ビルドもテストも実行できない)。

見るところ:
- 正しさ。この変更で壊れる入力・状態・境界条件はないか。
- 要件との食い違い。PR の本文や関連 issue が言っていることと、実際の差分がずれていないか。
- 既にあるものの再実装。このリポジトリに同じことをする関数やユーティリティが既にないか。
- 見落としやすい抜け。エラー処理、後始末、並行実行、非互換な変更。

やらないこと:
- 好みの問題 (命名の趣味、フォーマット、コメントの多寡) は指摘しない。
- 「〜かもしれません」で終わる曖昧な指摘は書かない。実際に壊れる筋道を示せないなら黙る。
- 指摘が無いなら無いと言う。数を揃えようとしない。

出力は、最後に次の形式のブロックを1つだけ出すこと。前後に説明を書いてよいが、投稿されるのはこのブロックだけ。

<<<REVIEW_JSON
{
  \"summary\": \"全体の所見を2〜4文。指摘が無い場合もここに理由を書く。\",
  \"comments\": [
    {
      \"path\": \"差分に出てくるファイルパス\",
      \"line\": 差分で追加された行の、新しいファイルでの行番号 (整数),
      \"severity\": \"blocker\" または \"suggestion\",
      \"body\": \"何がどう壊れるかを1〜3文で\",
      \"suggestion\": \"その行を置き換えるコード。示せない場合はこのキーごと省略する\"
    }
  ]
}
REVIEW_JSON

line は必ず、差分の中で + が付いている行 (追加された行) の新ファイル側の行番号にすること。文脈行や削除行を指すと投稿が拒否される。指摘が無いときは comments を空配列にする。"

log "claude 実行: review $REPO PR #$PR"
run_claude "$prompt" "$out" --allowedTools "Read,Grep,Glob" --max-turns 40
rc=$?
[ "$rc" = 90 ] && exit 1

# Pull out the last REVIEW_JSON block.
json="$(awk '/^<<<REVIEW_JSON$/{flag=1; buf=""; next} /^REVIEW_JSON$/{flag=0; last=buf; next} flag{buf = buf $0 "\n"} END{printf "%s", last}' "$out")"
if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
  log "could not extract REVIEW_JSON: $out"
  notify "claude-agent: malformed review output" "$REPO #$PR. Log: $out"
  exit 1
fi

summary="$(jq -r '.summary // ""' <<<"$json")"
count="$(jq -r '(.comments // []) | length' <<<"$json")"

if [ "$count" = "0" ]; then
  log "nothing to report: $REPO #$PR"
  mark_seen "$REPO/pr-$PR/$sha"
  exit 0
fi

# Build the inline comments. A suggestion becomes the fenced block that GitHub
# renders with a "Commit suggestion" button.
payload="$(jq -c --arg mark "$MARK" --arg sum "$summary" '
  {
    event: "COMMENT",
    body: ("🤖 Claude Code (macmini) によるレビューです。\n\n" + $sum + "\n\n" + $mark),
    comments: [ .comments[] | {
      path: .path,
      line: (.line | tonumber),
      side: "RIGHT",
      body: (
        ((if .severity == "blocker" then "**要修正**: " else "" end) + .body)
        + (if (.suggestion // "") == "" then "" else "\n\n```suggestion\n" + .suggestion + "\n```" end)
      )
    } ]
  }' <<<"$json")"

if printf '%s' "$payload" | gh api "repos/${REPO}/pulls/${PR}/reviews" --input - >/dev/null 2>&1; then
  log "posted the review: $REPO #$PR ($count comments)"
else
  # The API rejects a line that is not part of the diff. Rather than lose the
  # review, put the whole thing in the body.
  log "inline comments were rejected, posting as a single comment: $REPO #$PR"
  fallback="$(jq -r --arg mark "$MARK" '
    "🤖 Claude Code (macmini) によるレビューです。\n\n" + (.summary // "") + "\n\n"
    + ([.comments[] | "- `" + .path + ":" + (.line|tostring) + "` " + .body
        + (if (.suggestion // "") == "" then "" else "\n\n```suggestion\n" + .suggestion + "\n```" end)] | join("\n"))
    + "\n\n(行コメントとして投稿できなかったため本文にまとめています)\n" + $mark' <<<"$json")"
  gh pr comment "$PR" --repo "$REPO" --body "$fallback" >/dev/null 2>&1 \
    || { log "posting the comment failed as well: $REPO #$PR"; exit 1; }
fi

mark_seen "$REPO/pr-$PR/$sha"
