#!/usr/bin/env bash
# Decide which systems a pull request has to build, from the paths it touches.
#
# Reads the changed paths on stdin (one per line) and prints a JSON array of systems.
# The default is every system: a path is only allowed to narrow the set when its name says
# unambiguously which side it belongs to. Nearly everything in this repo is shared — one
# module under nix/modules/ or one file under configs/ reaches every host — so guessing
# wrong here means a broken config merges without ever being built.
#
# Self-check: scripts/ci-plan-systems.sh --demo
set -euo pipefail

ALL='["x86_64-linux","aarch64-linux","aarch64-darwin"]'
DARWIN='["aarch64-darwin"]'
LINUX='["x86_64-linux","aarch64-linux"]'

classify() {
  case "$1" in
    # macOS-only entities and the components only they import
    nix/hosts/darwin*.nix | nix/hosts/macmini.nix | nix/home/darwin.nix | nix/home/macmini.nix | \
      nix/home/workstation.nix | nix/modules/home/darwin-*.nix) echo darwin ;;
    # Linux-only entities, plus the VM tests, which only ever run there
    nix/hosts/nixos-*.nix | nix/hosts/homeserver*.nix | nix/hosts/recovery-iso.nix | \
      nix/hosts/droid.nix | nix/home/linux.nix | nix/home/wsl.nix | nix/home/hyprland.nix | \
      nix/home/restic-backup-linux.nix | nix/tests/*) echo linux ;;
    # Documentation cannot change a build; it must not be the reason a system is skipped either,
    # so it votes for nothing and a docs-only diff falls through to the default.
    docs/* | *.md) echo none ;;
    *) echo both ;;
  esac
}

plan() {
  local want_darwin=0 want_linux=0 path kind
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    kind=$(classify "$path")
    case "$kind" in
      both) echo "$ALL"; return ;;
      darwin) want_darwin=1 ;;
      linux) want_linux=1 ;;
    esac
  done
  if [ "$want_darwin" = 1 ] && [ "$want_linux" = 0 ]; then echo "$DARWIN"
  elif [ "$want_linux" = 1 ] && [ "$want_darwin" = 0 ]; then echo "$LINUX"
  else echo "$ALL"
  fi
}

if [ "${1:-}" = "--demo" ]; then
  check() {
    # shellcheck disable=SC2086 # 意図的な word splitting: 引数のパス列を 1 行 1 パスに割る
    got=$(printf '%s\n' $2 | plan)
    [ "$got" = "$3" ] || { echo "FAIL: $1: got $got want $3" >&2; exit 1; }
    echo "ok: $1"
  }
  check "darwin host only" "nix/hosts/darwin.nix" "$DARWIN"
  check "nixos host only" "nix/hosts/homeserver.nix nix/tests/homeserver-vm.nix" "$LINUX"
  check "shared module" "nix/modules/home/terminal.nix" "$ALL"
  check "config file" "configs/terminals/tmux/tmux.conf" "$ALL"
  check "both sides" "nix/hosts/darwin.nix nix/home/wsl.nix" "$ALL"
  check "docs alone" "docs/NIXOS_RECOVERY.md" "$ALL"
  check "docs with a darwin file" "docs/x.md nix/home/macmini.nix" "$DARWIN"
  check "flake" "nix/flake.nix" "$ALL"
  check "nothing" "" "$ALL"
  exit 0
fi

plan
