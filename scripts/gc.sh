#!/usr/bin/env bash
# `just gc`: garbage-collect every layer at once (only regenerable caches; the Trash and
# whole-home sweeps are in gc-deep.sh).
set -u
# `just maintain` runs this part itself, alongside everything else (see maintain-macos.sh).
if [ -z "${DOTFILES_GC_SKIP_NIX:-}" ]; then
  echo "━━━ Nix store (remove old generations) ━━━"
  # NixOS keeps three system generations: the menu's fallback when a new one does not boot.
  # With only one, a broken boot entry left nothing to pick (nixos-laptop, 2026-10-27).
  keep=1
  [ -e /etc/NIXOS ] && keep=3
  nh clean all --keep "$keep" --keep-since 0h || true
  # The bootloader was installed by the rebuild, before this removed the older system
  # generations, so their UKIs stay in the menu with no closure behind them. Picking one
  # unlocks the disk and then drops to the initrd's emergency mode (nixos-laptop,
  # 2026-10-22). Installing it again from the remaining generation prunes them.
  if [ -e /etc/NIXOS ]; then
    sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot 2>&1 | tail -1 || true
  fi
  echo ""
fi
if command -v brew >/dev/null; then
  echo "━━━ Homebrew (downloads + old versions) ━━━"
  brew autoremove 2>&1 | tail -3 || true
  brew cleanup --prune=all 2>&1 | tail -3 || true
  echo ""
fi
echo "━━━ pnpm store ━━━"
command -v pnpm >/dev/null && pnpm store prune 2>&1 | tail -2 || true
echo ""
echo "━━━ npm cache ━━━"
command -v npm >/dev/null && npm cache clean --force 2>/dev/null && echo "  cleaned" || true
echo ""
echo "━━━ uv cache ━━━"
command -v uv >/dev/null && uv cache prune 2>&1 | tail -2 || true
echo ""
echo "━━━ cargo (large build artifacts only, keep registry) ━━━"
command -v cargo-cache >/dev/null && cargo cache --autoclean 2>&1 | tail -2 || echo "  (cargo-cache not installed, skip)"
echo ""
if [ "$(uname -s)" = Darwin ]; then
  echo "━━━ iOS Simulator (unavailable devices) ━━━"
  command -v xcrun >/dev/null && xcrun simctl delete unavailable 2>&1 | tail -1 || true
  du -sh ~/Library/Developer/CoreSimulator 2>/dev/null | sed 's|^|  |' || true
  echo ""
fi
echo "━━━ podman (stopped containers + dangling images) ━━━"
# A stopped machine causes connection errors, so skip silently
if command -v podman >/dev/null && podman info >/dev/null 2>&1; then
  podman system prune -f 2>&1 | tail -2 || true
else
  echo "  (podman not available / machine stopped, skip)"
fi
echo ""
if [ "$(uname -s)" = Darwin ]; then
  echo "━━━ Electron updater leftovers (~/Library/Caches/*.ShipIt) ━━━"
  # Leftover downloaded updates from Squirrel.framework. Re-fetched on the next update
  sz=$(du -shc ~/Library/Caches/*.ShipIt 2>/dev/null | tail -1 | cut -f1)
  echo "  total: ${sz:-0}"
  rm -rf ~/Library/Caches/*.ShipIt/* 2>/dev/null || true
  echo ""
fi
echo "━━━ Repo junk files (.DS_Store / AppleDouble / vim swap etc.) ━━━"
dir="$(cd "$(dirname "$0")/.." && pwd)"
# Name patterns of junk scattered by macOS / editors / the OS (.git excluded)
names=(
  ".DS_Store" ".AppleDouble" ".LSOverride" "._*"
  ".Spotlight-V100" ".Trashes" ".fseventsd" ".DocumentRevisions-V100"
  ".TemporaryItems" ".apdisk" ".localized"
  "Thumbs.db" "Thumbs.db:encryptable" "ehthumbs.db" "ehthumbs_vista.db" "desktop.ini"
  "*.swp" "*.swo" "*~" "*.bak" "*.orig"
)
fexpr=()
for n in "${names[@]}"; do fexpr+=( -name "$n" -o ); done
unset 'fexpr[${#fexpr[@]}-1]'  # remove the trailing -o
# .cache is root's (see .gitignore), so descending into it is only a Permission denied.
# Delete outside find: -delete implies -depth, which silently turns -prune off (BSD and GNU
# alike), so it would descend into .git and remove e.g. *.orig/*~ there.
mapfile -d '' junk < <(find "$dir" \( -path "$dir/.git" -o -name .cache \) -prune -o -type f \( "${fexpr[@]}" \) -print0)
[ ${#junk[@]} -gt 0 ] && rm -f "${junk[@]}"
echo "  ${#junk[@]} removed"
echo ""
echo "━━━ Auto-backups in ~/.config (*.bak etc.) ━━━"
m=$(find ~/.config -maxdepth 3 \( -name '*.bak' -o -name '*.bak.[0-9]*' \) -type f -print -delete 2>/dev/null | wc -l | tr -d ' ')
echo "  $m removed"
echo ""
echo "━━━ Dev caches (__pycache__/*.pyc/.pytest_cache etc., excl Library, regenerated) ━━━"
# This was two `find $HOME` passes and it was the slowest thing in `just gc` by a wide margin.
# Two reasons, both fixed here:
#   - ~/Sync holds two rclone NFS mounts of Google Drive (780Ti and 816Gi as mounted), and
#     plain `find` happily descended into them, so the sweep went out over the network and
#     the API. Measured: it had not printed a single result after 35s. --one-file-system
#     keeps it on the local volume, which is the only place these caches can be anyway.
#   - fd walks in parallel where find is serial: 2.3s against 21s for the same sweep.
# One expression instead of two passes: --prune stops fd inside a matched cache dir (so the
# .pyc under one is not listed separately — it goes with the dir), and the \.pyc$ alternative
# still catches strays lying outside a cache dir.
pc=0; py=0
while IFS= read -r p; do
  if [ -d "$p" ]; then rm -rf "$p" && pc=$((pc+1)); else rm -f "$p" && py=$((py+1)); fi
done < <(fd --hidden --no-ignore --one-file-system --prune \
  --exclude Library --exclude .Trash \
  '^(__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.ipynb_checkpoints)$|\.pyc$' \
  "$HOME" 2>/dev/null)
echo "  cache dirs: $pc, *.pyc: $py removed"
echo ""
echo "━━━ ~/.cache (uv done, status of other large items) ━━━"
du -sh ~/.cache/*/ 2>/dev/null | sort -hr | head -5
echo ""
echo "━━━ Done ━━━"
df -h / 2>&1 | head -2 | tail -1
