#!/usr/bin/env bash
# `just maintain` on Linux: pull, rebuild, and garbage-collect.
set -euo pipefail
maintenance_lock="$HOME/.local/state/dotfiles-maintenance.lock"
mkdir -p "$HOME/.local/state"
if ! mkdir "$maintenance_lock" 2>/dev/null; then
  # If the holder PID is alive it is genuinely running. If dead it is a leftover from an interrupt, so reclaim it
  # (a mkdir-only lock always goes stale on SIGKILL / an interrupted build).
  holder=$(cat "$maintenance_lock/pid" 2>/dev/null || true)
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    echo "another dotfiles maintenance task is running (pid $holder)" >&2; exit 1
  fi
  echo "reclaiming stale maintenance lock (pid ${holder:-?} not running)" >&2
  rm -rf "$maintenance_lock"
  mkdir "$maintenance_lock" 2>/dev/null || { echo "failed to acquire maintenance lock" >&2; exit 1; }
fi
echo $$ > "$maintenance_lock/pid"
export DOTFILES_MAINTAIN=1
# To avoid accidentally maintaining with stale config, first bring our own dotfiles up to date.
# Only on the main branch (do not pull on a feature branch or when detached). Git operations
# always target the main tree. The pull fires the post-merge/post-rewrite hook, but the
# DOTFILES_MAINTAIN=1 exported above makes the hook-side rebuild skip
# (we run just rebuild ourselves afterward, avoiding a double rebuild).
if [ "$(git -C "$HOME/.dotfiles" branch --show-current 2>/dev/null)" = "main" ]; then
  echo "━━━ git pull (--rebase --autostash)"
  git -C "$HOME/.dotfiles" pull --rebase --autostash
fi
just outdated
# shellcheck disable=SC2154 # rc is assigned inside the trap string
trap 'rc=$?; rm -rf "$maintenance_lock"; exit $rc' EXIT
# No `nix flake update` here, as in maintain-macos.sh: the update-flake-lock workflow bumps the
# lock through a PR that CI builds into cachix. A local bump left flake.lock dirty after every
# maintain and built inputs nothing had cached; `just update` is there for a bump on purpose.
just rebuild
just gc
just _maintain-user-tools
just doctor || true
trap - EXIT
rm -rf "$maintenance_lock"
