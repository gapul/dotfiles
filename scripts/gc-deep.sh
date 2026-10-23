#!/usr/bin/env bash
# `just gc-deep`: interactively delete heavy regenerable data (Trash, zap of retired casks,
# CoreSimulator cache, podman images, old build artifacts).
set -u
echo "━━━ macOS Trash (with confirmation; unrecoverable) ━━━"
sz=$(du -sh "$HOME/.Trash" 2>/dev/null | cut -f1); echo "  size: ${sz:-0}"
read -rp "  Empty Trash? [y/N] " ans
if [[ "$ans" == [yY] ]]; then
  find "$HOME/.Trash" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
  echo "  emptied"
else
  echo "  skipped"
fi
echo ""
echo "━━━ OS/editor junk across HOME (with confirmation) ━━━"
read -rp "  Delete .DS_Store/AppleDouble/swap/orig/rej/backup files? [y/N] " ans
if [[ "$ans" == [yY] ]]; then
  # -x for the same reason as the Dev caches sweep above: without it this walks the two
  # rclone Google Drive mounts under ~/Sync, which is both endless and the last place we
  # want to be deleting ._* and .DS_Store.
  d=$(find -x "$HOME" \( -path "$HOME/.Trash" -o -path "$HOME/Library" \) -prune -o -type f \( -name '.DS_Store' -o -name '._*' -o -name '*.swp' -o -name '*.swo' -o -name '*.orig' -o -name '*.rej' -o -name '*~' \) -print -delete 2>/dev/null | wc -l | tr -d ' ')
  echo "  $d removed"
else
  echo "  skipped"
fi
echo ""
echo "━━━ Retired GUI cask data (Homebrew zap) ━━━"
# Only pin casks moved to CLI/TUI and dropped from the declaration. --force lets the zap stanza
# (settings, caches, etc.) run even after a normal uninstall. unity-hub is excluded because it may
# share settings with the Unity CLI.
zap_candidates=(cyberduck wireshark-app syncthing-app picview iina vlc)
printf '  %s\n' "${zap_candidates[@]}"
echo "  Removes app settings/caches; Cyberduck bookmarks and Wireshark profiles are included."
echo "  Preserved: Syncthing core config, Unity Hub/CLI metadata."
read -rp "  Zap all listed cask data? [y/N] " ans
if [[ "$ans" == [yY] ]]; then
  brew uninstall --cask --zap --force "${zap_candidates[@]}" || true
else
  echo "  skipped"
fi
echo ""
echo "━━━ CoreSimulator dyld cache (/Library/Developer/CoreSimulator/Caches) ━━━"
# Cache regenerated when the iOS simulator runs. Left alone it grows past 10GB
sim_cache="/Library/Developer/CoreSimulator/Caches"
if [ -d "$sim_cache" ]; then
  sz=$(du -sh "$sim_cache" 2>/dev/null | cut -f1)
  echo "  size: ${sz:-?} (regenerated on next use)"
  read -rp "  Delete? (sudo required) [y/N] " ans
  if [[ "$ans" == [yY] ]]; then
    sudo rm -rf "$sim_cache" && echo "  removed ($sz)"
  else
    echo "  skipped"
  fi
else
  echo "  (not found)"
fi
echo ""
echo "━━━ podman full prune (removes all unused images; re-pull needed on next use) ━━━"
if command -v podman >/dev/null && podman info >/dev/null 2>&1; then
  podman system df 2>/dev/null | sed 's|^|  |'
  read -rp "  Prune all unused images? [y/N] " ans
  if [[ "$ans" == [yY] ]]; then
    podman system prune -af 2>&1 | tail -3
  else
    echo "  skipped"
  fi
else
  echo "  (podman not available / machine stopped, skip)"
fi
echo ""
echo "━━━ Scanning node_modules / rust target untouched >30 days (in ~/Developer) ━━━"
tmp=$(mktemp)
# Limit the scan to the dev-repo location (~/Developer = ghq root).
# Targeting all of $HOME would sweep up everyday tools that build in-place under ~/.config etc.
# (e.g. the ghostty launcher's launcher-search/target) as cleanup candidates,
# and an incident occurred where the binary was deleted and the tool could no longer start (2026-07).
scan_root="$HOME/Developer"
if [ ! -d "$scan_root" ]; then echo "  ($scan_root not found, skip)"; rm -f "$tmp"; exit 0; fi
# node_modules: prune keeps only one level of nesting; limited to those untouched for 30 days
find "$scan_root" -type d -name node_modules -prune -mtime +30 -print 2>/dev/null >> "$tmp"
# rust target: avoid false hits on generic same-named dirs; only when a Cargo.toml sits alongside
find "$scan_root" -type d -name target -prune -mtime +30 -print 2>/dev/null | \
  while read -r d; do [ -f "$(dirname "$d")/Cargo.toml" ] && echo "$d"; done >> "$tmp"
cnt=$(wc -l < "$tmp" | tr -d ' ')
if [ "$cnt" -eq 0 ]; then echo "  None (all updated within 30 days)"; rm -f "$tmp"; exit 0; fi
total=$(xargs -I{} du -sk "{}" < "$tmp" 2>/dev/null | awk '{s+=$1}END{printf "%.1fG", s/1024/1024}')
sed "s|$HOME|~|" "$tmp" | head -40
[ "$cnt" -gt 40 ] && echo "  … $((cnt-40)) more"
echo "  Total: $total / $cnt items (each project needs reinstall after deletion)"
read -rp "Delete? [y/N] " ans
if [[ "$ans" == [yY] ]]; then
  xargs -I{} rm -rf "{}" < "$tmp" 2>/dev/null
  echo "  $cnt removed (reclaimed: $total)"
else
  echo "  Aborted"
fi
rm -f "$tmp"
