#!/usr/bin/env bash
# `just maintain` on macOS: pull, upgrade every package layer, rebuild, and garbage-collect.
set -euo pipefail
flake="$(cd "$(dirname "$0")/.." && pwd)/nix"
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
# Authenticate once for the whole run. Four things here need root — determinate-nixd,
# xcodebuild, nh darwin switch, nh clean — and they are spread across ten-plus minutes,
# well past sudo's five-minute timestamp, so each one raised its own Touch ID prompt
# (the last two land after the parallel lanes, i.e. long after you walked away).
# `sudo -v` takes the one prompt up front and the loop keeps the ticket warm until we exit.
# On a NOPASSWD host `sudo -v` still demands a password and fails without a tty, so ask
# the cheap question first.
sudo -n true 2>/dev/null || sudo -v
while :; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
sudo_keepalive=$!
# shellcheck disable=SC2154 # rc is assigned inside the trap string
trap 'rc=$?; kill $sudo_keepalive 2>/dev/null || true; rm -rf "$maintenance_lock"; exit $rc' EXIT
# `just outdated` is a read-only survey that costs ~13s of Homebrew metadata scanning, and
# the Nix runtime upgrade waits on the network the whole time. Run them together and print
# the survey when it is done, so the report still comes before anything is upgraded.
outdated_out=$(mktemp)
just outdated >"$outdated_out" 2>&1 &
outdated_pid=$!
just _upgrade-nix-runtime-macos
wait $outdated_pid || true
cat "$outdated_out"; rm -f "$outdated_out"
# The nix GC is ~25s of walking the store even when nothing is collectable, and it shares
# nothing with the rest, so it runs in the background from here and its output is replayed at
# the end. It starts after the runtime upgrade above, which restarts the daemon. It is safe
# beside the builds below: a path being fetched or built is held by the builder's temp root,
# and every build here lands on an --out-link, which is a GC root.
gc_out=$(mktemp)
nh clean all --keep 1 --keep-since 0h >"$gc_out" 2>&1 &
gc_pid=$!
# No `nix flake update` here on purpose. The hourly update-flake-lock workflow opens a PR for
# it, and CI builds that lock and pushes the results to cachix, so rebuilding on a merged lock
# is mostly downloads. Bumping the lock locally instead lands on a tree nothing has ever built
# and turns every maintain into a from-source build of every custom package. `just update`
# still exists for when the bump is actually wanted now.
# Three lanes instead of a waterfall. What forces the shape:
#   - Homebrew holds a lock, so everything brew does is one lane.
#   - nix-darwin's activation runs the Homebrew bundle, so the switch cannot overlap
#     the brew lane. Fetching/building the closure can, and does.
#   - The Nix runtime upgrade above replaces the daemon, so it stays before all of this.
# Everything else here is independent, and this link gives about twice the throughput on
# parallel connections as on one, so overlapping is worth the plumbing.
# Only the brew lane prints live. Three live downloads on one terminal is unreadable, but
# buffering all three left the terminal completely silent from here until the slowest lane
# finished — several minutes of nothing, which reads as a hang, not as progress. brew is the
# long pole and the one whose output is worth watching; the nix lane is reduced to its last
# five lines anyway and the tools lane is a few lines replayed after the switch, so neither
# is a loss. Both are collected after the brew lane, so nothing interleaves into it.
# Same host resolution as rebuild-macos.sh: the username is only right on the workstation.
name="$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host" 2>/dev/null || id -un)"
# Only asking whether the host has a standalone home config. Evaluating activationPackage to
# find out is the same full home-manager eval the build below does anyway — a minute idle here
# on a quiet machine, and it was still going after twelve on a loaded one (the source-to-store
# writer is one daemon round trip per file). `?` on the attrset never forces the value.
has_home=$(nix eval "$flake#homeConfigurations" --apply "a: a ? \"$name\"" 2>/dev/null || echo false)
# The builds land on the same out-links `just rebuild` uses: GC roots, so the nix GC running
# alongside cannot collect them, and the rebuild's own build of the same tree is then an
# eval-cache hit (~0.1s). If the package lane's github-pins edits a pin meanwhile, the
# rebuild simply evaluates the new tree.
roots="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"; mkdir -p "$roots"
nix_out=$(mktemp); tools_out=$(mktemp)
(
  [ "$has_home" = true ] &&
    nix build --out-link "$roots/rebuild-home" "$flake#homeConfigurations.$name.activationPackage" &
  nix build --out-link "$roots/rebuild-sys" "$flake#darwinConfigurations.$name.config.system.build.toplevel"
  wait
) >"$nix_out" 2>&1 &
nix_pid=$!
just _maintain-user-tools >"$tools_out" 2>&1 &
tools_pid=$!
echo "━━━ parallel: nix build (quiet) + user tools (replayed later) + packages below"
just _upgrade-packages-macos &
brew_pid=$!
wait $nix_pid || true
brew_rc=0; wait $brew_pid || brew_rc=$?
tail -5 "$nix_out"; rm -f "$nix_out"
# A failed package upgrade used to abort maintain here, and still should — but only after
# the lanes have been collected, so their output is not lost with them.
if [ "$brew_rc" -ne 0 ]; then
  wait $tools_pid || true; cat "$tools_out"; rm -f "$tools_out"
  echo "maintain: package upgrade failed (rc=$brew_rc)" >&2
  exit "$brew_rc"
fi
just rebuild force
wait $tools_pid || true; cat "$tools_out"; rm -f "$tools_out"
# Cleanup last: brew is free again only once the activation's bundle has run.
DOTFILES_GC_SKIP_NIX=1 just gc
brew services cleanup || true
wait $gc_pid || true
echo "━━━ Nix store (remove old generations) ━━━"; cat "$gc_out"; rm -f "$gc_out"
just doctor || true
trap - EXIT
kill $sudo_keepalive 2>/dev/null || true
rm -rf "$maintenance_lock"
