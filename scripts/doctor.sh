#!/usr/bin/env bash
# `just doctor`: environment health check. `doctor.sh --json` (or `json`) prints the macOS
# checks as one JSON object instead.
# shellcheck disable=SC2016 # check/warn take their conditions as strings to eval
set -u
format="${1:-}"
dir="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$(uname -s)" != Darwin ]; then
  # Everything below is macOS-specific (APFS, Login Items, the bar/WM stack, Homebrew).
  if [[ -n "$format" ]]; then echo "just doctor: --json is macOS-only" >&2; exit 2; fi
  pass=0; fail=0
  check() { if eval "$2"; then echo "  [ok] $1"; pass=$((pass+1)); else echo "  [FAIL] $1"; fail=$((fail+1)); fi; }
  warn() { if eval "$2"; then echo "  [ok] $1"; else echo "  [warn] $3"; fi; }
  echo "== nix =="
  check "nix daemon reachable" 'nix store info >/dev/null 2>&1'
  if command -v systemctl >/dev/null; then
    echo "== systemd =="
    check "no failed system units" '[[ -z "$(systemctl --failed --no-legend --plain 2>/dev/null)" ]]'
    check "no failed user units" '[[ -z "$(systemctl --user --failed --no-legend --plain 2>/dev/null)" ]]'
  fi
  echo "== dotfiles =="
  warn "Working tree clean (no uncommitted)" '[[ -z "$(git -C "$dir" status --short)" ]]' "Uncommitted changes -> commit/push recommended"
  check "age private key present" '[[ -f ~/.config/sops/age/keys.txt ]]'
  echo
  echo "Result: $pass passed, $fail failed"
  exit $fail
fi
if [[ "$format" == "json" || "$format" == "--json" ]]; then
  brew_json=$({ "$dir/scripts/check-brew-drift.sh" --json; } 2>/dev/null || true)
  [[ -n $brew_json ]] || brew_json='{"ok":false,"error":"brew drift check failed"}'
  result=$(jq -n \
    --argjson nixMounted "$([[ $(mount | grep -c ' on /nix ') -gt 0 ]] && echo true || echo false)" \
    --argjson fstabOk "$(! grep '/nix' /etc/fstab 2>/dev/null | grep -q noauto && echo true || echo false)" \
    --argjson nixDecrypted "$(! diskutil apfs list 2>/dev/null | grep -A 6 'Nix Store' | grep -q 'FileVault: *Yes' && echo true || echo false)" \
    --argjson sketchybar "$(pgrep -xq sketchybar && echo true || echo false)" \
    --argjson omniwm "$(pgrep -xq OmniWM && echo true || echo false)" \
    --argjson karabiner "$(pgrep -fq Karabiner-Core-Service && echo true || echo false)" \
    --argjson ageKey "$([[ -f $HOME/.config/sops/age/keys.txt ]] && echo true || echo false)" \
    --argjson clean "$([[ -z $(git -C "$dir" status --short) ]] && echo true || echo false)" \
    --argjson brew "$brew_json" \
    '{ok: ($nixMounted and $fstabOk and $nixDecrypted and $sketchybar and $omniwm and $karabiner and $ageKey and $brew.ok), checks: {nixMounted: $nixMounted, fstab: $fstabOk, nixDecrypted: $nixDecrypted, sketchybar: $sketchybar, omniwm: $omniwm, karabiner: $karabiner, ageKey: $ageKey, workingTreeClean: $clean}, brew: $brew}')
  printf '%s\n' "$result"
  jq -e '.ok' <<<"$result" >/dev/null
  exit $?
fi
if [[ -n "$format" ]]; then echo "usage: just doctor [--json|json]" >&2; exit 2; fi
pass=0; fail=0
check() { if eval "$2"; then echo "  [ok] $1"; pass=$((pass+1)); else echo "  [FAIL] $1"; fail=$((fail+1)); fi; }
# warn: informational check that does not fail even if unmet ($3 = message when unmet)
warn() { if eval "$2"; then echo "  [ok] $1"; else echo "  [warn] $3"; fi; }
echo "== /nix mount =="
check "/nix is mounted" 'mount | grep -q " on /nix "'
check "/etc/fstab has no noauto (Login Items fix)" '! grep "/nix" /etc/fstab | grep -q noauto'
check "/nix decrypted (FileVault: No)" '! diskutil apfs list 2>/dev/null | grep -A 6 "Nix Store" | grep -q "FileVault: *Yes"'
echo "== Login Items =="
check "OmniWM registered" 'osascript -e "tell application \"System Events\" to get name of login items" | grep -q OmniWM'
check "Ghostty registered" 'osascript -e "tell application \"System Events\" to get name of login items" | grep -q Ghostty'
echo "== Key apps running =="
# Match the process name, not a path. This used to grep the full argv for
# /opt/homebrew/opt/sketchybar/bin/sketchybar — the spelling brew's own service plist uses —
# but the agent that actually starts it is home-manager's, which execs /opt/homebrew/bin/
# sketchybar. Same binary, different spelling, so the check reported [FAIL] on a bar that was
# running fine. -x is exact-name so it takes neither sketchybar-ext nor the plugin shells.
check "sketchybar" 'pgrep -xq sketchybar'
check "sketchybar-ext (external monitor bar)" 'pgrep -fq "sketchybar-ext"'
check "OmniWM" 'pgrep -xq OmniWM'
check "Karabiner Core-Service" 'pgrep -fq Karabiner-Core-Service'
echo "== dotfiles =="
warn "Working tree clean (no uncommitted)" '[[ -z "$(git -C "$dir" status --short)" ]]' "Uncommitted changes -> commit/push recommended"
check "age private key present" '[[ -f ~/.config/sops/age/keys.txt ]]'
echo "== Homebrew declaration drift =="
if "$dir/scripts/check-brew-drift.sh"; then
  echo "  [ok] Homebrew matches declaration"; pass=$((pass+1))
else
  echo "  [FAIL] Homebrew drift detected -> apply: just rebuild"; fail=$((fail+1))
fi
echo
# If the bar/WM stack is down, surface a recovery path (to the restart recipe)
down=()
pgrep -xq sketchybar || down+=(sketchybar)
pgrep -fq "sketchybar-ext" || down+=(sketchybar-ext)
pgrep -xq OmniWM || down+=(omniwm)
if [ ${#down[@]} -gt 0 ]; then
  echo "[warn] Down: ${down[*]} -> recover: just restart (individual: just restart <name>)"
  echo
fi
echo "Result: $pass passed, $fail failed"
exit $fail
