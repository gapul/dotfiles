#!/usr/bin/env bash
#
# 既存の git レポを ghq 配下に移行する。
# 想定: ~/Dev (および他の散らばり先) にある git レポを
#       ~/ghq/<host>/<owner>/<repo> に再配置。
#
# 動作:
#   - 各レポの remote.origin.url を読む
#   - `ghq get <url>` で正しい場所に clone
#   - 元の場所はそのまま残す (安全のため手動削除推奨)
#   - 未 push の branch / 未 commit の変更があると WARN だけ出して skip
#
# 引数なし:       dry-run (何をするか表示)
# --apply:        実際に移行
# --remove-old:   --apply 完了後に元 dir を削除 (危険、安全確認後)

set -euo pipefail

SEARCH_DIRS=("$HOME/Dev")
APPLY=0
REMOVE_OLD=0

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --remove-old) REMOVE_OLD=1 ;;
    -h|--help)
      sed -n '3,18p' "$0"
      exit 0 ;;
    *)
      echo "Unknown flag: $arg" >&2
      exit 1 ;;
  esac
done

log() { printf '\033[1;34m[migrate]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[migrate]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[migrate]\033[0m %s\n' "$*" >&2; }

if ! command -v ghq >/dev/null; then
  err "ghq が無い。brew install ghq 後に実行してください。"
  exit 1
fi

GHQ_ROOT="$(ghq root)"
log "ghq root: $GHQ_ROOT"
log "検索対象: ${SEARCH_DIRS[*]}"
log "mode: $([ $APPLY -eq 1 ] && echo APPLY || echo DRY-RUN)"
echo

skipped_dirty=()
skipped_no_remote=()
already_managed=()
to_migrate=()

while IFS= read -r gitdir; do
  repodir=$(dirname "$gitdir")
  name=$(basename "$repodir")

  # 既に ghq 配下なら skip
  case "$repodir" in
    "$GHQ_ROOT"/*) already_managed+=("$repodir"); continue ;;
  esac

  remote=$(git -C "$repodir" config --get remote.origin.url 2>/dev/null || true)
  if [[ -z "$remote" ]]; then
    skipped_no_remote+=("$repodir")
    continue
  fi

  # dirty 検知
  if [[ -n "$(git -C "$repodir" status --porcelain 2>/dev/null)" ]]; then
    skipped_dirty+=("$repodir")
    continue
  fi

  # un-pushed commit 検知
  if git -C "$repodir" log --branches --not --remotes --oneline 2>/dev/null | grep -q .; then
    skipped_dirty+=("$repodir (un-pushed commits)")
    continue
  fi

  to_migrate+=("$repodir|$remote")
done < <(find "${SEARCH_DIRS[@]}" -maxdepth 4 -name .git -type d 2>/dev/null)

echo "--- Migration plan ---"
echo
log "移行する (${#to_migrate[@]} repo):"
for entry in "${to_migrate[@]}"; do
  repodir="${entry%%|*}"
  remote="${entry##*|}"
  echo "  $repodir → ghq get $remote"
done

echo
warn "skip (uncommitted/un-pushed: ${#skipped_dirty[@]} repo):"
for r in "${skipped_dirty[@]:-}"; do
  echo "  $r"
done

echo
warn "skip (no remote: ${#skipped_no_remote[@]} repo):"
for r in "${skipped_no_remote[@]:-}"; do
  echo "  $r"
done

echo
log "既に ghq 管理下 (${#already_managed[@]} repo):"
for r in "${already_managed[@]:-}"; do
  echo "  $r"
done

if [[ $APPLY -eq 0 ]]; then
  echo
  log "DRY-RUN 完了。実際に移行するには --apply を付けて再実行。"
  exit 0
fi

echo
log "Migration 実行..."
for entry in "${to_migrate[@]}"; do
  repodir="${entry%%|*}"
  remote="${entry##*|}"
  log "  $remote"
  ghq get "$remote"
  if [[ $REMOVE_OLD -eq 1 ]]; then
    log "  rm -rf $repodir"
    rm -rf "$repodir"
  fi
done

log "完了 ($([ $REMOVE_OLD -eq 1 ] && echo "元 dir も削除済" || echo "元 dir は残してます。確認後手動削除推奨"))"
