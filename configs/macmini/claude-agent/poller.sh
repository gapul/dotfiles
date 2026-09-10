#!/usr/bin/env bash
# Walk repos.json and hand anything worth picking up to run-autofix.sh or
# run-review.sh. launchd on the mac mini runs this every five minutes.
#
# This can fire for the same thing as the Actions path (the per-repository caller
# workflow), but both share the same record of what has been handled, so whichever
# gets there first is the only one that acts.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

paused && exit 0
acquire_lock poller 30 || { log "the previous poll is still running"; exit 0; }
setup_gh_token

# BSD date. Turn ISO8601 in UTC into epoch seconds.
epoch() { [ -n "${1:-}" ] && TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null; }
NOW="$(date +%s)"

dispatch() {
  log "→ $*"
  "$@" || log "WARN: failed: $*"
}

for repo in $(repo_list); do
  case "$(policy "$repo" trigger both)" in
    actions) log "trigger=actions, the poller leaves this one alone: $repo"; continue ;;
  esac

  # --- the first pass does nothing ------------------------------------
  # Starting cold would mean reacting to every open issue and every failed run at
  # once. The first pass only records what already exists; work starts with what
  # arrives after that.
  boot_file="$(_seen_path "$repo/bootstrap")"
  if [ ! -e "$boot_file" ]; then
    log "first pass, recording the current state only: $repo"
    for n in $(gh issue list --repo "$repo" --state open --limit 100 --json number -q '.[].number' 2>/dev/null); do
      mark_seen "$repo/issue-$n/$(gh issue view "$n" --repo "$repo" --json updatedAt -q .updatedAt 2>/dev/null)"
    done
    for id in $(gh run list --repo "$repo" --status failure --limit 50 --json databaseId -q '.[].databaseId' 2>/dev/null); do
      mark_seen "$repo/run-$id"
    done
    gh pr list --repo "$repo" --state open --limit 100 --json number,headRefOid \
      -q '.[] | "\(.number) \(.headRefOid)"' 2>/dev/null | while read -r n s; do
      mark_seen "$repo/pr-$n/$s"
    done
    mkdir -p "$(dirname "$boot_file")"
    printf '%s\n' "$NOW" > "$boot_file"
    continue
  fi
  BOOT_AT="$(cat "$boot_file" 2>/dev/null || echo "$NOW")"

  # --- issues ----------------------------------------------------------
  if is_true "$(policy "$repo" autofix_issues true)"; then
    while IFS=$'\t' read -r n created updated labels; do
      [ -z "$n" ] && continue
      case ",$labels," in *,no-claude,*) continue ;; esac
      seen "$repo/issue-$n/$updated" && continue

      act=0
      # explicitly asked for by a person
      case ",$labels," in *,claude-fix,*) act=1 ;; esac
      # opened after the first pass and not touched yet
      if [ "$act" = 0 ]; then
        c="$(epoch "$created")"
        if [ -n "$c" ] && [ "$c" -gt "$BOOT_AT" ]; then
          case ",$labels," in
            *,claude-in-progress,*|*,claude-done,*|*,claude-failed,*|*,claude-needs-info,*) ;;
            *) act=1 ;;
          esac
        fi
      fi
      # someone answered a question the bot asked (resume when the last comment is not the bot)
      if [ "$act" = 0 ]; then
        case ",$labels," in
          *,claude-needs-info,*)
            last="$(gh issue view "$n" --repo "$repo" --json comments \
              -q '.comments[-1].body' 2>/dev/null || true)"
            case "$last" in *'<!-- claude-bot -->'*) ;; '') ;; *) act=1 ;; esac
            ;;
        esac
      fi

      [ "$act" = 1 ] && dispatch "$AGENT_DIR/run-autofix.sh" "$repo" "issue:$n"
    done < <(gh issue list --repo "$repo" --state open --limit 30 \
      --json number,createdAt,updatedAt,labels \
      -q '.[] | [(.number|tostring), .createdAt, .updatedAt, ([.labels[].name]|join(","))] | @tsv' 2>/dev/null)
  fi

  # --- failed Actions runs ---------------------------------------------
  if is_true "$(policy "$repo" autofix_ci true)"; then
    while IFS=$'\t' read -r id created; do
      [ -z "$id" ] && continue
      seen "$repo/run-$id" && continue
      # do not dig up the backlog; only failures from the last twelve hours
      c="$(epoch "$created")"
      if [ -n "$c" ] && [ "$(( NOW - c ))" -gt 43200 ]; then
        mark_seen "$repo/run-$id"
        continue
      fi
      dispatch "$AGENT_DIR/run-autofix.sh" "$repo" "run:$id"
    done < <(gh run list --repo "$repo" --status failure --limit 20 \
      --json databaseId,createdAt \
      -q '.[] | [(.databaseId|tostring), .createdAt] | @tsv' 2>/dev/null)
  fi

  # --- pull request review ---------------------------------------------
  if is_true "$(policy "$repo" review true)"; then
    while IFS=$'\t' read -r n s draft; do
      [ -z "$n" ] && continue
      [ "$draft" = "true" ] && continue
      seen "$repo/pr-$n/$s" && continue
      dispatch "$AGENT_DIR/run-review.sh" "$repo" "$n"
    done < <(gh pr list --repo "$repo" --state open --limit 30 \
      --json number,headRefOid,isDraft \
      -q '.[] | [(.number|tostring), .headRefOid, (.isDraft|tostring)] | @tsv' 2>/dev/null)
  fi
done

log "poll finished"
