#!/usr/bin/env bash
# auto-fix パイプライン(GitHub issue → macmini Claude Code → PR → CI → 自動マージ)の
# 健全性を Claude Code に1時間ごとに確認させる監視スクリプト。macmini の launchd で回す。
# 監視対象(GitHub Actions/runner)とは独立して動くよう、GitHub Actions ではなく
# macmini ローカルの launchd で実行する(壊れた仕組みの上に監視を載せない)。
set -uo pipefail
export PATH="/Users/gapul/.local/bin:/etc/profiles/per-user/gapul/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# claude の認証は $CLAUDE_CONFIG_DIR にある(launchd 実行では既定で入らない)。
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-/Users/gapul/.config/claude}"

REPO="mugen404/prod-record"
HEALTH_ISSUE=3
# 状態(ログと Claude の出力)は XDG の state 配下。以前はスクリプトと同じ
# $HOME/autofix-monitor に置いていたが、スクリプト自体が nix store に入って
# 読み取り専用になったので分離した。
DIR="${XDG_STATE_HOME:-$HOME/.local/state}/autofix-monitor"
LOG="$DIR/monitor.log"
mkdir -p "$DIR"
# gh auth token が transient で空を返すと、空文字が hosts.yml のトークンを上書きして
# 以降の gh が全て無認証で失敗する。非空のときだけ export し、失敗時は hosts.yml に任せる。
_t="$(gh auth token 2>/dev/null)"; [ -n "$_t" ] && export GH_TOKEN="$_t"
ts="$(date '+%Y-%m-%d %H:%M:%S')"

# --- heartbeat: 監査(この監視)が生きている証を repo 変数に刻む ---
# 外側の watchdog(GitHub-hosted, macmini から独立)がこの鮮度を見て「監査の監査」を行う。
# 単発 set が transient(API blip/トークン一時失効)で落ちると watchdog が誤って
# 「監査ダウン」と鳴る。数回リトライし、全滅時は握り潰さず monitor.log に残す。
hb_ok=0
for _i in 1 2 3; do
  if gh variable set MONITOR_HEARTBEAT --repo "$REPO" --body "$(date +%s)" >/dev/null 2>&1; then hb_ok=1; break; fi
  sleep 5
done
[ "$hb_ok" = 1 ] || echo "[$ts] WARN: heartbeat set が3回失敗(watchdog誤報の恐れ)" >> "$LOG"

# --- シグナル収集 ---
RUNNER="$(gh api "repos/$REPO/actions/runners" -q '.runners[]|select(.name=="macmini")|.status+" busy="+(.busy|tostring)' 2>/dev/null || echo 'unknown')"
INPROG="$(gh issue list --repo "$REPO" --label claude-in-progress --state open --json number,title,updatedAt 2>/dev/null || echo '[]')"
NEEDINFO="$(gh issue list --repo "$REPO" --label claude-needs-info --state open --json number,title 2>/dev/null || echo '[]')"
AF_RUNS="$(gh run list --repo "$REPO" --workflow claude-auto-fix.yml --limit 8 --json conclusion,status,createdAt,displayTitle 2>/dev/null || echo '[]')"
CI_RUNS="$(gh run list --repo "$REPO" --workflow ci.yml --limit 8 --json conclusion,status,headBranch,createdAt 2>/dev/null || echo '[]')"
PRS="$(gh pr list --repo "$REPO" --json number,title,headRefName,mergeStateStatus 2>/dev/null || echo '[]')"
# 司法(査読)の過剰ブロック/形骸化を見るための客観シグナル
REVIEW_STUCK="$(gh issue list --repo "$REPO" --label review-stuck --state open --json number,title 2>/dev/null || echo '[]')"
RECENT_MERGED="$(gh pr list --repo "$REPO" --state merged --limit 15 --json headRefName -q '[.[]|select(.headRefName|startswith("claude/"))]|length' 2>/dev/null || echo '?')"
OPEN_FIX="$(gh issue list --repo "$REPO" --label claude-fix --state open --json number -q 'length' 2>/dev/null || echo '?')"
# 能動的自己改善のON/OFF(人間のキルスイッチ)。既定ON。gh variable set AUTO_IMPROVE --body off で停止。
AUTO_IMPROVE="$(gh api "repos/$REPO/actions/variables/AUTO_IMPROVE" -q '.value' 2>/dev/null || echo on)"
# CI が green でも配信(deploy)が連続失敗していると修正が実機に届かないので、deploy 系も収集する。
# ワークフローが存在しない/取得に失敗した場合も空配列で継続する。
DEPLOY_RUNS=""
for wf in deploy-ios.yml deploy-api.yml deploy-mock.yml; do
  runs="$(gh run list --repo "$REPO" --workflow "$wf" --limit 5 --json conclusion,status,createdAt,headBranch 2>/dev/null || echo '[]')"
  DEPLOY_RUNS="$DEPLOY_RUNS
  $wf: ${runs:-[]}"
done

# --- 安価なシェル三面待ち(トークン節約) ---
# 監視の価値は異常検知。平常時に毎時フル claude 分析(30ターン)を回すのは無駄なので、
# シェルで判る明確な異常が無ければ claude を呼ばず、heartbeat + HEALTHY で終える。
# heartbeat は上で既に書いてあるので watchdog は満たされたまま。異常時だけ claude が精査する。
ANOMALY=""
printf '%s' "$RUNNER" | grep -q online || ANOMALY="${ANOMALY}runner offline; "
AF_LATEST="$(gh run list --repo "$REPO" --workflow claude-auto-fix.yml --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null)"
[ "$AF_LATEST" = failure ] && ANOMALY="${ANOMALY}auto-fix最新失敗; "
printf '%s' "$REVIEW_STUCK" | grep -q '"number"' && ANOMALY="${ANOMALY}review-stuck; "
for wf in deploy-ios.yml deploy-api.yml; do
  l="$(gh run list --repo "$REPO" --workflow "$wf" --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null)"
  [ "$l" = failure ] && ANOMALY="${ANOMALY}${wf}最新失敗; "
done
# 死んだジョブの残骸: 60分以上更新の無い claude-in-progress
STALE="$(gh issue list --repo "$REPO" --label claude-in-progress --state open --json updatedAt \
  -q '[.[]|select((now-(.updatedAt|fromdateiso8601))>3600)]|length' 2>/dev/null || echo 0)"
[ "${STALE:-0}" -gt 0 ] && ANOMALY="${ANOMALY}停滞in-progress${STALE}件; "

if [ -z "$ANOMALY" ]; then
  echo "[$ts] verdict=HEALTHY (shell-triage / claude skip・トークン節約)" >> "$LOG"
  exit 0
fi
echo "[$ts] anomaly: ${ANOMALY}→ claudeで精査" >> "$LOG"

read -r -d '' PROMPT <<EOF || true
あなたは自動修正パイプライン(GitHub issue → macmini 上の Claude Code → ブランチ → PR → CI → 自動マージ)の監視担当です。
現在時刻: $ts。以下のスナップショットを評価し、システムが正常か判断してください。必要なら gh コマンドで追加調査して構いません。

[runner] $RUNNER
[claude-in-progress の issue] $INPROG
[claude-needs-info の issue(人の返信待ち。正常)] $NEEDINFO
[直近 auto-fix 実行] $AF_RUNS
[直近 CI 実行] $CI_RUNS
[直近 deploy 実行]$DEPLOY_RUNS
[オープン中の PR] $PRS

異常の例:
- runner が online でない
- claude-in-progress の issue が1時間以上更新されていない(ジョブがハング/クラッシュ)
- 直近の auto-fix / ci が failure 続き
- deploy 系ワークフロー(deploy-ios / deploy-api / deploy-mock)が直近 3 回以上連続 failure
  (CI が green でも配信が届いていない状態なので異常)
- claude/* の PR が CI 失敗で滞留している
(claude-needs-info で人の返信待ちなのは正常。空の状態も正常)

【監査(三権分立)】あなたは監査役として、司法(査読claude)も監督します:
[review-stuck の issue(司法と行政が3ラウンドで収束せず)] $REVIEW_STUCK
[直近マージされた claude/* PR 数(15件中)] $RECENT_MERGED
[open の claude-fix issue 数] $OPEN_FIX
- 過剰ブロックの疑い: open の claude-fix が複数あるのに **直近マージが 0** / review-stuck が増えている
  → 司法が厳しすぎて健全な PR まで止めている可能性。直近PRの査読コメント(gh pr view <PR> --json comments、
  'claude-review' マーカー)を実際に読み、指摘が些細な好みや過度な要求(不要な回帰テスト強制等)なら「過剰ブロック」と判断。
- 形骸化の疑い: 査読が常に APPROVE(実質ノーチェック)になっていないか。
- review-stuck は人手/監査案件として #$HEALTH_ISSUE に報告。
- 司法自体に不具合・改善余地(厳しすぎる/緩すぎる基準など)があれば、直接編集せず
  claude-fix ラベルの issue を立てる(claude-review.sh のプロンプト調整など。重複回避・1回1件)。

対応:
- runner が offline/欠落なら復旧を試みる:
  ~/actions-runner/svc.sh stop; ~/actions-runner/svc.sh start
- **異常があるときだけ** issue #$HEALTH_ISSUE に日本語で「何が異常か・実施した対応・残る懸念」を1コメントで投稿する:
  gh issue comment $HEALTH_ISSUE --repo $REPO --body '...(末尾に <!-- claude-bot --> を付ける)'
- 正常なら issue にはコメントしない。

さらに(自己改善): 自動修正システム自体(.github/workflows/claude-auto-fix.yml, ci.yml,
deploy-ios.yml, .github/scripts/claude-auto-fix.sh, ops/autofix-monitor.sh)の
不具合・改善余地を、直近の失敗パターンや claude-failed の issue から探すこと。
- **改善点が見つかったら自分で直接編集せず**、gh でその改善内容を説明する GitHub issue を
  立てる(claude-fix ラベルを付ける)。パイプライン本体が PR+CI 経由で安全に直す。
  例: gh issue create --repo $REPO --label claude-fix --title '...' --body '...(末尾に <!-- claude-bot -->)'
- ただし **重複を避ける**: gh issue list で既に同主旨の open issue(特に claude-* ラベル)が
  あれば新規に立てない。1回の実行で立てる改善 issue は最大1件。
- パイプライン自体(.github/*)の変更は特に慎重に(壊すとシステムが止まる)。

【能動的自己改善(人間を介さずループを回す)】AUTO_IMPROVE=$AUTO_IMPROVE / open claude-fix=$OPEN_FIX
- **AUTO_IMPROVE が on** かつ **open の claude-fix が 2 件以下**(パイプラインが暇)なら、
  プロダクト/パイプラインを1歩進める改善を**自分で見つけて claude-fix issue を1件**立てる。
  こうすれば人間なしで「バックログ減る→改善を足す→行政が実装→司法が査読→マージ」が回り続ける。
  ネタ源(優先度順): ①observ済みの実バグ/退行 ②docs/SPEC.md と実装の乖離・未実装 ③コードの TODO/FIXME
  ④UX・信頼性の明らかな穴。**高価値・低リスク・スコープ明確**なものだけ(曖昧なら立てない=make-work防止)。
  受け入れ条件を必ず書く。人間の介入は claude-needs-info(追加質問)への返信だけで済むように。
- AUTO_IMPROVE=off、または claude-fix が3件以上のときは新規に立てない(キューを消化させる)。
- 1回の監視実行で新規に立てる issue は(不具合報告+改善)合わせて最大1件。

- 出力の最後の行に、正常なら HEALTHY、異常なら UNHEALTHY とだけ書いて終了。
EOF

echo "[$ts] monitor start" >> "$LOG"
# claude -p が稀にハングする(過去に9.5時間ハングした実績あり)。launchd の StartInterval は
# 前 run が終わるまで次を出さないため、1 run のハングで以降の毎時監視が全て止まり監査が
# 丸ごと死ぬ。macOS には timeout/gtimeout バイナリが無いので、バックグラウンド実行+キラーで
# バイナリ非依存の壁時計制限(600s)をかける。stdin も塞いで対話待ちで固まらないようにする。
CLAUDE_OUT="$DIR/claude-out.$$"
claude -p "$PROMPT" --dangerously-skip-permissions --max-turns 30 </dev/null >"$CLAUDE_OUT" 2>&1 &
cpid=$!
( sleep 600; kill -TERM "$cpid" 2>/dev/null; sleep 10; kill -KILL "$cpid" 2>/dev/null ) &
kpid=$!
wait "$cpid" 2>/dev/null
kill "$kpid" 2>/dev/null; wait "$kpid" 2>/dev/null || true
RESULT="$(cat "$CLAUDE_OUT" 2>/dev/null)"; rm -f "$CLAUDE_OUT"
[ -n "$RESULT" ] || echo "[$ts] WARN: claude が無応答/timeout(600s)で打ち切り" >> "$LOG"
VERDICT="$(printf '%s' "$RESULT" | grep -aoE 'HEALTHY|UNHEALTHY' | tail -1)"
{
  echo "[$ts] verdict=${VERDICT:-?}"
  printf '%s\n' "$RESULT" | tail -c 1500
  echo "----"
} >> "$LOG"
