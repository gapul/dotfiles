# Dotfiles task runner. Use `just` to list tasks.
# https://just.systems

set shell := ["bash", "-cu"]
# Run native Windows recipes directly in PowerShell.
set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]
# Treat `#` lines in recipes as comments so they are not echoed during runs
# (otherwise every comment inside e.g. `_rebuild-macos` prints on `just rebuild`).
set ignore-comments := true

flake := justfile_directory() + "/nix"

default:
    @just --list --unsorted


# ─────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────

[group('Build')]
[doc('Rebuild the system and user configuration')]
rebuild:
    @just _rebuild-{{os()}}

[group('Build')]
[doc('Build every flake check available on this architecture')]
check-all *args:
    @cd {{flake}} && nix run .#check-all -- {{args}}

[group('Build')]
[doc('Build every flake package available on this architecture')]
build-all *args:
    @cd {{flake}} && nix run .#build-all -- {{args}}

[group('Build')]
[doc('Build the non-destructive NixOS recovery ISO (Linux builder required)')]
recovery-iso:
    @nix build {{flake}}#recovery-iso --out-link result-recovery
    @echo "ISO: {{justfile_directory()}}/result-recovery/iso/gapul-nixos-recovery.iso"

# Satisfy Homebrew's tap-trust requirement. Formulae/casks from unofficial taps
# managed by nix-darwin are refused on load by brew upgrade / install unless trusted.
# Shared because both the rebuild and upgrade(maintain) paths need it.
[private]
_rebuild-macos:
    #!/usr/bin/env bash
    set -euo pipefail
    # (No brew trust pass here: nix/hosts/darwin.nix sets HOMEBREW_NO_REQUIRE_TAP_TRUST=1 for the
    #  whole activation, and a manual `brew trust` gets overwritten by the bundle anyway. The
    #  _brew-trust-taps recipe is still needed by _upgrade-packages-macos, where `brew upgrade`
    #  runs outside the activation and does enforce trust.)
    # Tee the whole run to a fixed log so a failure can be inspected after the fact
    # without re-running — crucially the Homebrew bundle step, which runs during
    # nix-darwin activation and so is absent from `nix log <drv>`. When stdout is not
    # a TTY (git hooks, CI, an agent shell) drop nix-output-monitor's live TUI so the
    # log stays greppable plain text instead of cursor-control escape soup.
    mkdir -p "$HOME/tmp"
    log="$HOME/tmp/nix-rebuild.log"
    nom_flag=""; [ -t 1 ] || nom_flag="--no-nom"
    : > "$log"
    # taskpolicy -b drops the build to background QoS. If the build pins the CPU,
    # Ghostty's event handling misses its deadline and the global keybind's CGEventTap
    # gets disabled with kCGEventTapDisabledByTimeout, after which cmd+space stops
    # working while unfocused (Ghostty does not re-enable the tap itself: ghostty#11883).
    # Lowering the priority keeps Ghostty from starving, preventing the tap disable.
    echo "━━━ nix-darwin" | tee -a "$log"
    taskpolicy -b nh darwin switch -q -Q --diff never $nom_flag 2>&1 | tee -a "$log"
    echo "✓ nix-darwin" | tee -a "$log"
    echo "━━━ home-manager" | tee -a "$log"
    # -b hm-bak: standalone home-manager has no backupFileExtension option (that one only exists on
    # the nix-darwin/NixOS module path), and without a backup extension a newly declared home.file
    # whose target already exists is skipped — the declaration silently does nothing. That is how
    # gh-dash/config.yml and slk/config.toml stayed plain files after #153 declared them.
    taskpolicy -b nh home switch -q -Q --diff never -b hm-bak $nom_flag 2>&1 | tee -a "$log"
    echo "✓ home-manager" | tee -a "$log"
    open -a Ghostty >/dev/null 2>&1 || true

[private]
_rebuild-linux:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "━━━ home-manager"
    nh home switch -q -Q --diff never
    echo "✓ home-manager"

[private]
_rebuild-windows:
    @just win-bootstrap

# List or compare system generations.
[group('Build')]
gen action="" a="" b="":
    #!/usr/bin/env bash
    set -euo pipefail
    p=/nix/var/nix/profiles
    cur=$(readlink $p/system | sed -E 's/system-([0-9]+)-link/\1/')
    case "{{action}}" in
      "")
        for l in $p/system-*-link; do
          n=$(echo "$l" | sed -E 's#.*/system-([0-9]+)-link#\1#')
          d=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$l")
          mark=""; [ "$n" = "$cur" ] && mark="  <- current"
          printf '%4s  %s%s\n' "$n" "$d" "$mark"
        done | sort -n
        ;;
      diff)
        a="{{a}}"; b="{{b}}"; a="${a:-$((cur-1))}"; b="${b:-$cur}"
        echo "Package diff: generation $a -> $b"
        nix store diff-closures "$p/system-$a-link" "$p/system-$b-link"
        ;;
      *) echo "usage: just gen [diff [a] [b]]" >&2; exit 2 ;;
    esac

# Roll back to the previous or selected system generation.
[group('Build')]
rollback gen="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{gen}}" ]; then
      echo "-> Switching to generation {{gen}}"
      sudo darwin-rebuild --switch-generation {{gen}}
    else
      echo "-> Rolling back to previous generation"
      sudo darwin-rebuild --rollback
    fi

# Update flake inputs, then rebuild.
[group('Build')]
update *inputs:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "━━━ flake inputs"
    lock="{{flake}}/flake.lock"
    old_lock=$(mktemp)
    cp "$lock" "$old_lock"
    trap 'rc=$?; if [ $rc -ne 0 ]; then cp "$old_lock" "$lock"; echo "Restored flake.lock after failed update" >&2; fi; rm -f "$old_lock"; exit $rc' EXIT
    just _update-lock {{inputs}}
    if cmp -s "$old_lock" "$lock"; then
      echo "✓ already up to date"
    else
      echo "✓ flake.lock updated"
    fi
    just rebuild
    trap - EXIT
    rm -f "$old_lock"

[private]
_update-lock *inputs:
    @nix flake update --quiet {{inputs}} --flake {{flake}}

# Upgrade all package layers.
[group('Build')]
upgrade:
    @just _upgrade-{{os()}}

[private]
_upgrade-macos:
    @just _upgrade-nix-runtime-macos
    @just _upgrade-packages-macos
    @just update

[private]
_upgrade-nix-runtime-macos:
    @echo "━━━ Nix runtime"
    @if command -v determinate-nixd >/dev/null; then sudo determinate-nixd upgrade; else echo "– Determinate Nixd not installed"; fi

[private]
_brew-trust-taps:
    @-brew tap 2>/dev/null | grep -v '^homebrew/' | xargs -I% env -u XDG_CONFIG_HOME brew trust % >/dev/null
    @-env -u XDG_CONFIG_HOME brew trust --cask gerlero/openfoam/openfoam@2606 >/dev/null
    @-brew list --cask --full-name 2>/dev/null | grep '/' | xargs -I% env -u XDG_CONFIG_HOME brew trust --cask % >/dev/null

[private]
_upgrade-packages-macos:
    # Order matters: `brew update` resets the trust of unofficial taps, so run update
    # first, then trust, and run the subsequent upgrade with HOMEBREW_NO_AUTO_UPDATE=1
    # so the trust is not reset again. Skip this and update ->
    # (trust lost) -> upgrade makes qmk/qmk (formula) and y3owk1n/tap/neru (cask)
    # get refused as untrusted; the cask is swallowed by `|| true` and the final check fails.
    @brew update --quiet || true
    @just _brew-trust-taps
    @just _brew-formula-upgrade
    @echo "━━━ Homebrew casks"
    @HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --quiet --cask --greedy || true
    @just _xcode-upgrade
    @just sketchybar-font
    # The --greedy upgrade above also targets auto_updates/`version :latest` casks,
    # but those stay "outdated" forever and can never "complete" (e.g. figma-agent,
    # pear-desktop; for the latter the upstream cask errors on upgrade itself due to a
    # missing URL, swallowed by `|| true`). So judge completion with outdated without --greedy.
    # Non-greedy does not list auto_updates/latest, so it detects only missed real
    # version updates and does not break as auto_updates casks grow (previously
    # figma-agent was grep-excluded, but enumerating them breaks, so that was removed).
    @remaining=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --cask 2>/dev/null || true); if [ -n "$remaining" ]; then echo "ERROR: cask upgrade incomplete:" >&2; echo "$remaining" >&2; exit 1; fi

# Upgrade Homebrew formulae, resilient to a single broken formula (mirrors the cask handling).
# `brew upgrade --formula` aborts the whole run if ANY formula fails — e.g. concord 2.5.0, whose
# tap formula ungated `depends_on "alsa-lib"`/`"pipewire"` (Linux-only, no macOS bottle) so it
# can't install on macOS. Previously that one failure aborted `just maintain` and rolled back the
# flake update. Now individual failures are tolerated (|| true) and we fail only if a NON-pinned
# formula is still outdated (a genuine unhandled failure). Pinned-but-outdated (intentionally held,
# e.g. `brew pin concord` at 2.4.8) is fine. Names are normalized to basename because
# `brew outdated` prints tap-qualified names (chojs23/tap/concord) while `brew list --pinned`
# prints short names (concord).
[private]
_brew-formula-upgrade:
    #!/usr/bin/env bash
    set -u
    echo "━━━ Homebrew formulae"
    HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --quiet --formula || true
    pinned=$(brew list --pinned 2>/dev/null | sed 's#.*/##')
    bad=""
    for f in $(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --formula --quiet 2>/dev/null | sed 's#.*/##'); do
      printf '%s\n' "$pinned" | grep -qxF "$f" || bad="$bad $f"
    done
    if [ -n "$bad" ]; then
      echo "ERROR: formula upgrade incomplete (non-pinned):$bad" >&2
      exit 1
    fi

# Keep Xcode current via xcodes (replaces mas for Xcode). Reads Apple ID from the
# sops-decrypted files so username/password auth is non-interactive; 2FA is prompted
# only on first login / expired session. Never aborts the outer upgrade (|| true / echo)
# so a skipped 2FA prompt doesn't fail `just upgrade`.
[private]
_xcode-upgrade:
    #!/usr/bin/env bash
    set -u
    command -v xcodes >/dev/null || { echo "– xcodes not installed, skip"; exit 0; }
    echo "━━━ Xcode (xcodes)"
    aid="$HOME/.config/xcodes/apple_id"; pw="$HOME/.config/xcodes/password"
    if [ -r "$aid" ] && [ -r "$pw" ]; then
      export XCODES_USERNAME XCODES_PASSWORD
      XCODES_USERNAME=$(cat "$aid"); XCODES_PASSWORD=$(cat "$pw")
    else
      echo "– Apple ID not set in sops (xcodes/apple_id, xcodes/password); will prompt if needed"
    fi
    # --latest installs the newest release (no-op if already current) and selects it. aria2 is
    # auto-used for the parallel .xip download. On failure (e.g. skipped 2FA) don't break upgrade.
    if xcodes install --latest; then
      sudo xcodebuild -license accept 2>/dev/null || true
      sudo xcodebuild -runFirstLaunch 2>/dev/null || true
    else
      echo "– xcodes install skipped/failed (2FA or auth?); re-run: xcodes install --latest"
    fi

[private]
_upgrade-linux:
    @just update

[private]
_upgrade-windows:
    @just win-upgrade

[group('Build')]
[doc('Update, upgrade, rebuild, and garbage-collect')]
maintain:
    @just _maintain-{{os()}}

[private]
_maintain-macos:
    #!/usr/bin/env bash
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
    lock="{{flake}}/flake.lock"
    old_lock=$(mktemp)
    cp "$lock" "$old_lock"
    trap 'rc=$?; if [ $rc -ne 0 ]; then cp "$old_lock" "$lock"; echo "Restored flake.lock after failed maintain" >&2; fi; rm -f "$old_lock"; rm -rf "$maintenance_lock"; exit $rc' EXIT
    just _upgrade-nix-runtime-macos
    just _update-lock
    just _upgrade-packages-macos
    just rebuild
    just gc
    brew services cleanup || true
    just _maintain-user-tools
    just doctor || true
    trap - EXIT
    rm -f "$old_lock"
    rm -rf "$maintenance_lock"

[private]
_maintain-linux:
    #!/usr/bin/env bash
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
    lock="{{flake}}/flake.lock"
    old_lock=$(mktemp)
    cp "$lock" "$old_lock"
    trap 'rc=$?; if [ $rc -ne 0 ]; then cp "$old_lock" "$lock"; echo "Restored flake.lock after failed maintain" >&2; fi; rm -f "$old_lock"; rm -rf "$maintenance_lock"; exit $rc' EXIT
    just _update-lock
    just rebuild
    just gc
    just _maintain-user-tools
    just doctor || true
    trap - EXIT
    rm -f "$old_lock"
    rm -rf "$maintenance_lock"

[private]
_maintain-user-tools:
    @if command -v tldr >/dev/null; then echo "━━━ tldr cache ━━━"; tldr --update || true; fi
    @if command -v gh >/dev/null && gh extension list 2>/dev/null | grep -q .; then echo "━━━ GitHub CLI extensions ━━━"; gh extension upgrade --all || true; fi

[private]
_maintain-windows:
    just win-bootstrap
    just win-upgrade
    @echo "Windows: gc recipe is not defined; package update completed."

# Update sketchybar-app-font assets from the same release.
[private]
sketchybar-font:
    #!/usr/bin/env bash
    set -euo pipefail
    repo="kvndrsslr/sketchybar-app-font"
    dir="{{justfile_directory()}}"
    ttf="$dir/configs/fonts/sketchybar-app-font.ttf"
    map="$dir/configs/wm/sketchybar/plugins/icon_map.sh"
    # A transient network failure here used to abort `just maintain` entirely and roll back
    # flake.lock. The font is a nice-to-have, so treat an unreachable API as "skip", like xcodes.
    tag=$(gh release view --repo "$repo" --json tagName -q .tagName) || {
      echo "– sketchybar-app-font: release lookup failed (offline?); skipped" >&2
      exit 0
    }
    cur=$(awk '/pname = "sketchybar-app-font"/{getline; if (match($0,/[0-9][0-9.]*/)) print substr($0,RSTART,RLENGTH); exit}' "$dir/nix/hosts/darwin.nix")
    if [ "$tag" = "v$cur" ]; then
      exit 0
    fi
    echo "sketchybar-app-font: updating $cur -> $tag"
    gh release download "$tag" --repo "$repo" --pattern sketchybar-app-font.ttf --output "$ttf"  --clobber
    gh release download "$tag" --repo "$repo" --pattern icon_map.sh           --output "$map"  --clobber
    awk '/^### END-OF-ICON-MAP/{print; print "__icon_map \"$1\""; print "[ -r \"${BASH_SOURCE%/*}/icon_map_local.sh\" ] && source \"${BASH_SOURCE%/*}/icon_map_local.sh\""; print "echo \"$icon_result\""; exit} {print}' "$map" > "$map.tmp" && mv "$map.tmp" "$map"
    # gh release assets are non-executable, so restore +x; plugins run icon_map.sh
    # directly ($(...)), and without +x it fails with "permission denied" -> the
    # workspace app icons silently vanish. `chmod` before `git add` so the staged
    # mode is recorded as 100755 too.
    chmod +x "$map"
    sed -i "" -E '/pname = "sketchybar-app-font"/{n;s/version = "[0-9.]+"/version = "'"${tag#v}"'"/;}' "$dir/nix/hosts/darwin.nix"
    git -C "$dir" add "$ttf" "$map" "$dir/nix/hosts/darwin.nix"
    echo "Updated ($tag). Apply with: just rebuild (automatic when run via upgrade)"


# ─────────────────────────────────────────────
# Inspect (diff / type-check / diagnostics)
# ─────────────────────────────────────────────

# Type-check / show diff  (`just check` = syntax/type-check, `just check diff` = diff build)
[group('Inspect')]
check what="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{what}}" in
      "")   nix flake check --no-build {{flake}} ;;  # syntax/type-check (no build)
      diff) nh darwin build ;;                       # current vs. flake diff
      *)    echo "usage: just check [diff]" >&2; exit 2 ;;
    esac

# Package search  (`just search <q>` = brew+nixpkgs, `just search <q> all` = + cargo)
# all is for discovering ecosystem-only tools not in nix/brew. The default is less noisy.
[group('Inspect')]
[doc('Package search (`just search <q>` = brew+nixpkgs, `just search <q> all` = + cargo)')]
search query scope="":
    #!/usr/bin/env bash
    set -u
    if [ -z "{{query}}" ]; then echo "usage: just search <name> [all]" >&2; exit 2; fi
    case "{{scope}}" in ""|all) ;; *) echo "usage: just search <name> [all]" >&2; exit 2 ;; esac
    echo "━━━ Homebrew (formula + cask) ━━━"
    brew search {{query}} 2>&1 || true
    echo ""
    echo "━━━ nixpkgs (local eval) ━━━"
    # nh search depends on the search.nixos.org API and is flaky, so use nix search
    # (the eval cache kicks in, so subsequent runs take a few seconds; warnings suppressed)
    nix search nixpkgs {{query}} 2>/dev/null || echo "  (none)"
    # Only for all, also sweep the ecosystem-only source (cargo)
    if [ "{{scope}}" = "all" ]; then
      echo ""
      echo "━━━ crates.io (cargo) ━━━"
      cargo search {{query}} 2>&1 | head -10 || echo "  (none)"
    fi

# List what can be updated (preview before upgrade; brew + mas + flake inputs; non-destructive)
[group('Inspect')]
outdated:
    #!/usr/bin/env bash
    set -u
    echo "━━━ Homebrew (formula + cask, --greedy) ━━━"
    o=$(brew outdated --greedy 2>/dev/null); [ -n "$o" ] && echo "$o" || echo "  (up to date)"
    echo ""
    echo "━━━ Xcode (xcodes) ━━━"
    if command -v xcodes >/dev/null; then
      # auth-free preview: show what's installed. `xcodes update` (Apple login + maybe 2FA)
      # is intentionally left to `just upgrade` so this stays non-interactive.
      inst=$(xcodes installed 2>/dev/null | tr -s ' ' | paste -sd', ' - || true)
      echo "  installed: ${inst:-none}   (just upgrade -> xcodes install --latest)"
    else
      echo "  (xcodes not installed)"
    fi
    echo ""
    echo "━━━ flake inputs (lock last-modified) ━━━"
    if command -v jq >/dev/null; then
      nix flake metadata {{flake}} --json 2>/dev/null \
        | jq -r '.locks.nodes | to_entries[] | select(.value.locked.lastModified) | "\(.key)\t\(.value.locked.lastModified)"' \
        | while IFS=$'\t' read -r name ts; do printf '  %-22s %s\n' "$name" "$(date -r "$ts" '+%Y-%m-%d')"; done \
        | sort -k2
    else
      echo "  (jq not installed, skip)"
    fi
    echo ""
    echo "-> Update: just upgrade (all) / just update <input> (individual)"

# Environment health check (run after e.g. a Determinate upgrade)
[group('Inspect')]
doctor format="":
    #!/usr/bin/env bash
    set -u
    if [[ "{{format}}" == "json" || "{{format}}" == "--json" ]]; then
      brew_json=$({ "{{justfile_directory()}}/scripts/check-brew-drift.sh" --json; } 2>/dev/null || true)
      [[ -n $brew_json ]] || brew_json='{"ok":false,"error":"brew drift check failed"}'
      result=$(jq -n \
        --argjson nixMounted "$([[ $(mount | grep -c ' on /nix ') -gt 0 ]] && echo true || echo false)" \
        --argjson fstabOk "$(! grep '/nix' /etc/fstab 2>/dev/null | grep -q noauto && echo true || echo false)" \
        --argjson nixDecrypted "$(! diskutil apfs list 2>/dev/null | grep -A 6 'Nix Store' | grep -q 'FileVault: *Yes' && echo true || echo false)" \
        --argjson sketchybar "$(pgrep -fq '/opt/homebrew/opt/sketchybar/bin/sketchybar' && echo true || echo false)" \
        --argjson omniwm "$(pgrep -xq OmniWM && echo true || echo false)" \
        --argjson karabiner "$(pgrep -fq Karabiner-Core-Service && echo true || echo false)" \
        --argjson ageKey "$([[ -f $HOME/.config/sops/age/keys.txt ]] && echo true || echo false)" \
        --argjson clean "$([[ -z $(git -C {{justfile_directory()}} status --short) ]] && echo true || echo false)" \
        --argjson brew "$brew_json" \
        '{ok: ($nixMounted and $fstabOk and $nixDecrypted and $sketchybar and $omniwm and $karabiner and $ageKey and $brew.ok), checks: {nixMounted: $nixMounted, fstab: $fstabOk, nixDecrypted: $nixDecrypted, sketchybar: $sketchybar, omniwm: $omniwm, karabiner: $karabiner, ageKey: $ageKey, workingTreeClean: $clean}, brew: $brew}')
      printf '%s\n' "$result"
      jq -e '.ok' <<<"$result" >/dev/null
      exit $?
    fi
    if [[ -n "{{format}}" ]]; then echo "usage: just doctor [--json|json]" >&2; exit 2; fi
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
    check "sketchybar" 'pgrep -fq "/opt/homebrew/opt/sketchybar/bin/sketchybar"'
    check "OmniWM" 'pgrep -xq OmniWM'
    check "Karabiner Core-Service" 'pgrep -fq Karabiner-Core-Service'
    echo "== dotfiles =="
    warn "Working tree clean (no uncommitted)" '[[ -z "$(git -C {{justfile_directory()}} status --short)" ]]' "Uncommitted changes -> commit/push recommended"
    check "age private key present" '[[ -f ~/.config/sops/age/keys.txt ]]'
    echo "== Homebrew declaration drift =="
    if "{{justfile_directory()}}/scripts/check-brew-drift.sh"; then
      echo "  [ok] Homebrew matches declaration"; pass=$((pass+1))
    else
      echo "  [FAIL] Homebrew drift detected -> apply: just rebuild"; fail=$((fail+1))
    fi
    echo
    # If the bar/WM stack is down, surface a recovery path (to the restart recipe)
    down=()
    pgrep -fq "/opt/homebrew/opt/sketchybar/bin/sketchybar" || down+=(sketchybar)
    pgrep -xq OmniWM || down+=(omniwm)
    pgrep -xq borders || down+=(borders)
    if [ ${#down[@]} -gt 0 ]; then
      echo "[warn] Down: ${down[*]} -> recover: just restart (individual: just restart <name>)"
      echo
    fi
    echo "Result: $pass passed, $fail failed"
    exit $fail

# NOTE: nix fmt (treefmt in bulk) is unusable because the flake lives in nix/ and detection of the
#       tree-root flake.nix fails (see the treefmt comment in flake.nix). Run it via pre-commit, which bundles per-file hooks.
# Format code + lint across all tracked files (OS auto-detected: Mac/Linux=pre-commit, Win=PSScriptAnalyzer)
[group('Inspect')]
fmt:
    @just _fmt-{{os()}}

[private]
_fmt-macos: _fmt-unix

[private]
_fmt-linux: _fmt-unix

[private]
_fmt-unix:
    nix develop {{flake}} --command pre-commit run --all-files

# The actual work is win-fmt (single source of the command)
[private]
_fmt-windows:
    @just win-fmt


# ─────────────────────────────────────────────
# Clean (clean / GC and junk files)
# ─────────────────────────────────────────────

# GC all layers at once (only regenerable caches; Trash and whole-home deletion are in gc-deep)
[group('Clean')]
gc:
    #!/usr/bin/env bash
    set -u
    echo "━━━ Nix store (remove old generations) ━━━"
    nh clean all --keep 5 --keep-since 7d || true
    echo ""
    echo "━━━ Homebrew (downloads + old versions) ━━━"
    brew autoremove 2>&1 | tail -3 || true
    brew cleanup --prune=all 2>&1 | tail -3 || true
    echo ""
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
    echo "━━━ iOS Simulator (unavailable devices) ━━━"
    command -v xcrun >/dev/null && xcrun simctl delete unavailable 2>&1 | tail -1 || true
    du -sh ~/Library/Developer/CoreSimulator 2>/dev/null | sed 's|^|  |' || true
    echo ""
    echo "━━━ podman (stopped containers + dangling images) ━━━"
    # A stopped machine causes connection errors, so skip silently
    if command -v podman >/dev/null && podman info >/dev/null 2>&1; then
      podman system prune -f 2>&1 | tail -2 || true
    else
      echo "  (podman not available / machine stopped, skip)"
    fi
    echo ""
    echo "━━━ Electron updater leftovers (~/Library/Caches/*.ShipIt) ━━━"
    # Leftover downloaded updates from Squirrel.framework. Re-fetched on the next update
    sz=$(du -shc ~/Library/Caches/*.ShipIt 2>/dev/null | tail -1 | cut -f1)
    echo "  total: ${sz:-0}"
    rm -rf ~/Library/Caches/*.ShipIt/* 2>/dev/null || true
    echo ""
    echo "━━━ Repo junk files (.DS_Store / AppleDouble / vim swap etc.) ━━━"
    dir="{{justfile_directory()}}"
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
    n=$(find "$dir" -path "$dir/.git" -prune -o -type f \( "${fexpr[@]}" \) -print -delete | wc -l | tr -d ' ')
    echo "  $n removed"
    echo ""
    echo "━━━ Auto-backups in ~/.config (zellij *.bak etc.) ━━━"
    m=$(find ~/.config -maxdepth 3 \( -name '*.bak' -o -name '*.bak.[0-9]*' \) -type f -print -delete 2>/dev/null | wc -l | tr -d ' ')
    echo "  $m removed"
    echo ""
    echo "━━━ Dev caches (__pycache__/*.pyc/.pytest_cache etc., excl Library, regenerated) ━━━"
    tmp=$(mktemp)
    find "$HOME" \( -path "$HOME/Library" -o -name .Trash \) -prune -o -type d \( -name '__pycache__' -o -name '.pytest_cache' -o -name '.mypy_cache' -o -name '.ruff_cache' -o -name '.ipynb_checkpoints' \) -prune -print 2>/dev/null > "$tmp"
    pc=$(wc -l < "$tmp" | tr -d ' ')
    xargs -I{} rm -rf "{}" < "$tmp" 2>/dev/null; rm -f "$tmp"
    py=$(find "$HOME" \( -path "$HOME/Library" -o -name .Trash \) -prune -o -type f -name '*.pyc' -print -delete 2>/dev/null | wc -l | tr -d ' ')
    echo "  cache dirs: $pc, *.pyc: $py removed"
    echo ""
    echo "━━━ ~/.cache (uv done, status of other large items) ━━━"
    du -sh ~/.cache/*/ 2>/dev/null | sort -hr | head -5
    echo ""
    echo "━━━ Done ━━━"
    df -h / 2>&1 | head -2 | tail -1

# Interactively delete heavy regenerable data (Trash / ~/tmp scratch / zap of retired casks / CoreSimulator cache / podman / old build artifacts)
[group('Clean')]
gc-deep:
    #!/usr/bin/env bash
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
      d=$(find "$HOME" \( -path "$HOME/.Trash" -o -path "$HOME/Library" \) -prune -o -type f \( -name '.DS_Store' -o -name '._*' -o -name '*.swp' -o -name '*.swo' -o -name '*.orig' -o -name '*.rej' -o -name '*~' \) -print -delete 2>/dev/null | wc -l | tr -d ' ')
      echo "  $d removed"
    else
      echo "  skipped"
    fi
    echo ""
    echo "━━━ ~/tmp scratch (entries untouched >30 days) ━━━"
    # ~/tmp is where scratch work goes (see docs/CHEATSHEET.md). Git worktrees and clones live
    # here too, so anything holding a .git is skipped: deleting a worktree behind git's back
    # strands its metadata in the parent repo and takes any uncommitted work with it.
    tmp_root="$HOME/tmp"
    if [ ! -d "$tmp_root" ]; then
      echo "  ($tmp_root not found, skip)"
    else
      tmp_list=$(mktemp)
      find "$tmp_root" -mindepth 1 -maxdepth 1 -mtime +30 ! -exec test -e {}/.git \; -print 2>/dev/null > "$tmp_list"
      cnt=$(wc -l < "$tmp_list" | tr -d ' ')
      if [ "$cnt" -eq 0 ]; then
        echo "  None (everything is either recent or a git worktree)"
      else
        sed 's|^|  |' "$tmp_list"
        total=$(xargs -I{} du -sk "{}" < "$tmp_list" 2>/dev/null | awk '{s+=$1}END{printf "%.1fG", s/1024/1024}')
        echo "  $cnt entries, $total"
        read -rp "  Delete these? [y/N] " ans
        if [[ "$ans" == [yY] ]]; then
          xargs -I{} rm -rf -- "{}" < "$tmp_list"
          # A worktree may still have been removed by hand at some point; drop the stale metadata.
          git -C "{{justfile_directory()}}" worktree prune 2>/dev/null || true
          echo "  removed"
        else
          echo "  skipped"
        fi
      fi
      rm -f "$tmp_list"
    fi
    echo ""
    echo "━━━ Retired GUI cask data (Homebrew zap) ━━━"
    # Only pin casks moved to CLI/TUI and dropped from the declaration. --force lets the zap stanza
    # (settings, caches, etc.) run even after a normal uninstall. ollama-app is excluded because it deletes
    # the models in ~/.ollama, and unity-hub because it may share settings with the Unity CLI.
    zap_candidates=(cyberduck wireshark-app syncthing-app picview iina vlc)
    printf '  %s\n' "${zap_candidates[@]}"
    echo "  Removes app settings/caches; Cyberduck bookmarks and Wireshark profiles are included."
    echo "  Preserved: ~/.ollama models, Syncthing core config, Unity Hub/CLI metadata."
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


# ─────────────────────────────────────────────
# Service (restart / restarting the menu-bar and WM stack)
# ─────────────────────────────────────────────

# NOTE: omniwm full restart = the workspace layout is reset, so only on explicit request (omniwm/all).
#       borders config is consolidated in ~/.config/borders/bordersrc; the daemon itself is the
#       nix-declared launchd agent (org.nix-community.home.borders), so restart = kickstart.
# Restart the menu-bar/WM stack (`just restart`=bar-related / individual: sketchybar|borders|omniwm / all=everything)
[group('Service')]
restart what="bar":
    #!/usr/bin/env bash
    set -u
    uid=$(id -u)

    sb() { echo "-> sketchybar";  launchctl kickstart -k "gui/$uid/org.nix-community.home.sketchybar"; }
    bd() { echo "-> borders";     launchctl kickstart -k "gui/$uid/org.nix-community.home.borders"; }
    om() {
      echo "-> OmniWM (full restart)"
      osascript -e 'quit app "OmniWM"' 2>/dev/null
      # Poll up to 4s for quit to finish (a fixed sleep would let open miss when quit is slow)
      for _ in $(seq 1 20); do pgrep -xq OmniWM || break; sleep 0.2; done
      open -a OmniWM
    }

    case "{{what}}" in
      bar)            sb; bd ;;
      sketchybar|sb)  sb ;;
      borders|bd)     bd ;;
      omniwm|om|wm)   om ;;
      all)            sb; bd; om ;;
      *) echo "usage: just restart [bar|sketchybar|borders|omniwm|all]" >&2; exit 2 ;;
    esac
    echo "Done"


# ─────────────────────────────────────────────
# secrets (sops encryption)
# ─────────────────────────────────────────────

# sops-encrypted secrets  (`just secrets` = edit, `just secrets rekey` = re-encrypt for all recipients)
[group('secrets')]
secrets cmd="edit":
    #!/usr/bin/env bash
    set -euo pipefail
    f="{{justfile_directory()}}/secrets/secrets.yaml"
    case "{{cmd}}" in
      edit)  sops "$f" ;;                # edit (default)
      rekey) sops updatekeys "$f" ;;     # run after changing .sops.yaml
      *)     echo "usage: just secrets [edit|rekey]" >&2; exit 2 ;;
    esac


# ─────────────────────────────────────────────
# Setup / misc
# ─────────────────────────────────────────────

# The entry shellHook installs pre-commit into .git/hooks (.pre-commit-config.yaml generation + install).
# install only needs to run once on a new Mac's first time (merged the old pre-commit-install).
# devShell (`just dev`=enter [shellcheck/statix available] / `just dev install`=install hooks only [non-interactive])
[group('Setup')]
dev what="":
    #!/usr/bin/env bash
    set -eu
    case "{{what}}" in
      "")      exec nix develop {{flake}} ;;            # enter the interactive shell
      install) nix develop {{flake}} --command true ;;  # enter = install hooks only, then exit immediately
      *)       echo "usage: just dev [install]" >&2; exit 2 ;;
    esac

# Use remote-env on another host
[group('Setup')]
ssh host:
    nssh {{host}}

# A hand-written command list in the README drifts from the Justfile, so treat `just --list` as the single source and
# regenerate the <!-- BEGIN/END <name> --> blocks in README / CHEATSHEET from config (SSOT).
# Targets: the just recipe list, the pre-commit hook table, the shell alias table (see scripts/gen-docs.py).
# Run this after changing a recipe/hook/alias. CI drift detection is handled by check-generated.sh.
[group('Setup')]
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    python3 scripts/gen-docs.py

# One-way snapshot of Obsidian config into public dotfiles (tracking-only, vault->dotfiles)
# - Copy only whitelisted safe json. The vault side is authoritative (this is a read-only mirror).
# - plugins/*/data.json (LiveSync's CouchDB creds, various API keys, etc.), workspace, and caches are
#   never included by design. If any non-empty secret value is detected, abort and do not push to public.
# - Always run `gitleaks` before commit. For config you want to keep with its secrets, use sops encryption (`just secrets`).
[group('Setup')]
[doc('One-way snapshot of Obsidian config into public dotfiles (tracking-only, vault->dotfiles)')]
obsidian-snapshot:
    #!/usr/bin/env bash
    set -euo pipefail
    src="$HOME/Documents/notes/.obsidian"
    dst="{{justfile_directory()}}/configs/apps/obsidian"
    [ -d "$src" ] || { echo "vault not found: $src" >&2; exit 1; }
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

    # ★Whitelist: only settings confirmed safe (include only safe items rather than excluding dangerous ones)
    for f in app.json appearance.json hotkeys.json \
             community-plugins.json core-plugins.json \
             graph.json daily-notes.json types.json canvas.json; do
      [ -f "$src/$f" ] && cp -f "$src/$f" "$tmp/$f"
    done

    # ★Secret guard: if a non-empty secret value ("key": "value") is detected, abort without pushing to the public repo
    if grep -rEil '"(api[_-]?key|secret|token|password|passphrase|access[_-]?key|couchdb_[a-z]+)"[[:space:]]*:[[:space:]]*"[^"]+"' "$tmp"; then
      echo "🛑 Secret-like value detected. Aborting snapshot (protecting public)" >&2; exit 1
    fi

    mkdir -p "$dst"
    rsync -a --delete --exclude='README.md' "$tmp/" "$dst/"
    echo "✅ snapshot -> $dst"
    echo "   After git add, run gitleaks before committing."

# One-way snapshot of app-owned config files into the repo (live -> dotfiles).
# These apps rewrite their own config, so home.file (a read-only store symlink) would break them —
# the repo copy is a tracking mirror, same contract as obsidian-snapshot above.
# Restore on a fresh machine is a manual `cp` (see the README next to each file).
[group('Setup')]
[doc('Snapshot app-owned config files into dotfiles (live -> repo)')]
app-snapshot:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{justfile_directory()}}"
    changed=0
    # OmniWM: plain copy. The file is WM layout/hotkeys only, nothing account-bound.
    src="$HOME/.config/omniwm/settings.toml"; dst="$dir/configs/wm/omniwm/settings.toml"
    if [ -f "$src" ]; then
      cmp -s "$src" "$dst" || { cp -f "$src" "$dst"; echo "  updated configs/wm/omniwm/settings.toml"; changed=1; }
    else
      echo "– omniwm: no live config, skipped"
    fi
    # CodexBar: drop codexActiveSource (holds the Codex account UUID) before it reaches a public repo.
    src="$HOME/.config/codexbar/config.json"; dst="$dir/configs/apps/codexbar/config.json"
    if [ -f "$src" ]; then
      tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
      jq -S --indent 2 'del(.providers[].codexActiveSource)' "$src" > "$tmp"
      cmp -s "$tmp" "$dst" || { cp -f "$tmp" "$dst"; echo "  updated configs/apps/codexbar/config.json"; changed=1; }
    else
      echo "– codexbar: no live config, skipped"
    fi
    if [ "$changed" -eq 0 ]; then
      echo "✓ tracked app configs already match the live files"
    else
      git -C "$dir" --no-pager diff --stat -- configs
      echo "Review the diff, then commit on a branch as usual."
    fi

# Pull GUI-side preference changes back into the repo (live -> dotfiles).
# darwin-apps.nix imports these plists wholesale on activation, so anything changed in an app's
# own UI is silently reverted by the next rebuild unless it is captured here.
# Only keys the repo file already tracks are updated: these apps also store volatile state
# (window frames, status item positions, color panel geometry) that would add churn on every run.
# To start tracking a new key, add it to the repo plist once (`plutil -insert`), then this picks it up.
[group('Setup')]
[doc('Sync GUI app preference changes back into dotfiles (live -> repo)')]
plist-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{justfile_directory()}}"
    # Same set darwin-apps.nix imports. Add a line here when an import is added there.
    pairs=(
      "org.p0deje.Maccy configs/clipboard/maccy/Maccy.plist"
      "net.mtgto.inputmethod.macSKK configs/ime/skk/macSKK.plist"
      "io.github.gitusp.azoo-key-skkserv configs/ime/skk/azoo-key-skkserv.plist"
    )
    changed=0
    for pair in "${pairs[@]}"; do
      set -- $pair; domain="$1"; rel="$2"; repo="$dir/$rel"
      [ -f "$repo" ] || { echo "– $rel: not in repo, skipped"; continue; }
      live=$(defaults export "$domain" - 2>/dev/null | plutil -convert json -o - - 2>/dev/null) || live=""
      # An app that was never launched (or a sandbox not yet created) exports an empty dict.
      # Overwriting from that would quietly wipe the tracked settings, so skip instead.
      if [ -z "$live" ] || [ "$(jq 'keys|length' <<<"$live")" -eq 0 ]; then
        echo "– $domain: no live prefs, skipped"; continue
      fi
      old=$(plutil -convert json -o - "$repo")
      # read-loop, not `for`: some keys contain spaces ("NSStatusItem VisibleCC Item-0")
      while IFS= read -r key; do
        lv=$(jq -c --arg k "$key" '.[$k]' <<<"$live")
        rv=$(jq -c --arg k "$key" '.[$k]' <<<"$old")
        [ "$lv" = "null" ] && continue    # dropped on the live side: keep the tracked value
        [ "$lv" = "$rv" ] && continue
        plutil -replace "$key" -json "$lv" "$repo"
        echo "  $rel  $key: $rv -> $lv"
        changed=1
      done < <(jq -r 'keys[]' <<<"$old")
    done
    if [ "$changed" -eq 0 ]; then
      echo "✓ tracked plist keys already match the live prefs"
    else
      git -C "$dir" --no-pager diff --stat -- configs
      echo "Review the diff, then commit on a branch as usual."
    fi


# ─────────────────────────────────────────────
# Windows (native pwsh)
# ─────────────────────────────────────────────

# Run the native Windows bootstrap (`just win-bootstrap` / `just win-bootstrap -DryRun`)
[group('Windows')]
win-bootstrap *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/bootstrap.ps1 {{flags}}

# Verify every PackageIdentifier in winget/apps.json exists (`just win-verify` / `just win-verify -Strict`)
[group('Windows')]
win-verify *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/winget/verify.ps1 {{flags}}

# Diff between apps.json (declaration) and winget list (actual install). exit 1 if any MISSING
[group('Windows')]
win-status *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/winget/status.ps1 {{flags}}

# Upgrade every app installed via winget (--silent --accept-*)
[group('Windows')]
win-upgrade:
    pwsh.exe -NoProfile -Command "winget upgrade --all --silent --accept-package-agreements --accept-source-agreements"

# Declaratively apply telemetry/built-in feature settings (Win11Debloat + WinUtil)
# Pass `-DryRun` `-SkipWinUtil` `-SkipWin11Debloat` via `*flags`
[group('Windows')]
win-privacy *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/privacy/apply.ps1 {{flags}}

# Declaratively apply Scoop buckets + apps (for sideloading MS Store-only apps)
# Pass `-DryRun` `-SkipBuckets` `-SkipApps` via `*flags`
[group('Windows')]
win-scoop *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/scoop/apply.ps1 {{flags}}

# Declaratively apply locale / language (en-US UI / UTF-8 / SKK only / US Region)
# Pass `-DryRun` `-SkipLanguageList` `-SkipSystemLocale` `-SkipHomeLocation` via `*flags`
[group('Windows')]
win-locale *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/locale/apply.ps1 {{flags}}

# User-scope install of .ttf / .otf from configs/fonts/ (HKCU registration, no admin required)
# Pass `-DryRun` `-Force` (overwrite existing too) via `*flags`
[group('Windows')]
win-fonts *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/fonts/apply.ps1 {{flags}}

# Render the theme (palette) from palettes.json into each config
# Pass `-DryRun` `-ActivePalette rose-pine-dawn` etc. via `*flags`
[group('Windows')]
win-theme *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/theme/apply.ps1 {{flags}}


# ─────────────────────────────────────────────
# Theme (cross-OS, unified switching with palettes.json as SSO)
# ─────────────────────────────────────────────

# Render all environments with the current active in palettes.json (can also switch active via arg)
#   `just theme`                   = re-apply all environments with the current active
#   `just theme rose-pine-dawn`    = switch to light and render + rebuild all environments
# NOTE: shebang recipes do not work because Windows' just requires cygpath, so
#       this cross-OS recipe dispatches immediately and puts the bash logic in _theme-unix.
[group('Theme')]
[doc('Render all environments with the current active in palettes.json (`just theme rose-pine-dawn` also switches active)')]
theme name="":
    @just _theme-{{os()}} "{{name}}"

[private]
_theme-macos name="": (_theme-unix name)

[private]
_theme-linux name="": (_theme-unix name)

# On both Mac/WSL, nh home switch makes nvim/zellij/sketchybar/bat/atuin etc. all follow
[private]
_theme-unix name="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{name}}" ]; then
      # Rewrite the active field in palettes.json
      sed -i.bak 's/"active": *"[^"]*"/"active": "{{name}}"/' configs/theme/palettes.json
      rm -f configs/theme/palettes.json.bak
      echo "→ palettes.json active = {{name}}"
    fi
    nh home switch

# Write the active back here rather than in apply.ps1 (paired with the unix-side sed; UTF-8 without BOM).
# The actual render is win-theme (renders zebar / glazewm / WT / wezterm in one go)
[private]
_theme-windows name="":
    @if ('{{name}}' -ne '') { $p = Resolve-Path 'configs/theme/palettes.json'; $c = (Get-Content $p -Raw -Encoding UTF8) -replace '"active":\s*"[^"]*"', '"active": "{{name}}"'; [System.IO.File]::WriteAllText($p, $c, [System.Text.UTF8Encoding]::new($false)); Write-Host ('-> palettes.json active = {{name}}') }
    @just win-theme

# Apply keymap (SharpKeys = write Scancode Map directly + reload AHK script)
# Pass `-DryRun` `-Clear` (delete Scancode Map and return to standard) via `*flags`
[group('Windows')]
win-keymap *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/sharpkeys/apply.ps1 {{flags}}
    pwsh.exe -NoProfile -Command "Get-Process AutoHotkey* -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Process 'windows/autohotkey/keymap.ahk' -ErrorAction SilentlyContinue"

# Register GlazeWM login auto-start in Task Scheduler (password entered once)
# Pass `-Unregister` (delete the task) via `*flags`
[group('Windows')]
win-autostart-glazewm *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/tasks/setup-glazewm-autostart.ps1 {{flags}}

# Lint Windows-related .ps1 with PSScriptAnalyzer (exit 1 on Warning or above)
[group('Windows')]
win-fmt:
    pwsh.exe -NoProfile -Command "if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Install-Module PSScriptAnalyzer -Force -Scope CurrentUser }; Invoke-ScriptAnalyzer -Path windows -Recurse -Severity Warning -EnableExit -Settings windows/PSScriptAnalyzerSettings.psd1"

# ─────────────────────────────────────────────
# Backup / archive (a single restic repository: google-drive:restic-backup, encrypted)
#   warm = untagged, daily automatic (restic-backup.nix) / cold = --tag archive, manual, kept forever.
#   Dedup, integrity verification, and key are shared. The ~/Sync/google-drive-* mount ops are consolidated here too.
# ─────────────────────────────────────────────

# restic environment (shared by warm/cold). The values' only source is ~/.config/restic/env generated by nix
# (nix/lib/restic-common.nix). RESTIC_ARCHIVE_TAG also comes from here.
restic_env := 'source "$HOME/.config/restic/env"'

# ── warm: active files (daily automatic; the below are manual ops) ──

# Run the warm backup now (kickstart launchd) -> follow the log (Ctrl-C ends following; backup continues)
[group('Backup')]
backup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ Starting restic warm backup (launchd kickstart)..."
    launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.restic-backup"
    echo "Started. Following log (Ctrl-C to stop following; backup continues):"
    exec tail -f "$HOME/Library/Logs/restic-backup.log"

# List all snapshots (distinguish warm / archive by the Tags column)
[group('Backup')]
backup-ls:
    @{{restic_env}}; restic snapshots

# Verify repository integrity (restic check)
[group('Backup')]
backup-check:
    @{{restic_env}}; restic check

# ── cold: archive (evacuate files no longer used, kept forever) ──

# Evacuate files/folders no longer used into restic and free local space (--tag archive, kept forever).
# Example: `just archive ~/Downloads/old-project`
[group('Backup')]
archive path:
    #!/usr/bin/env bash
    set -euo pipefail
    {{restic_env}}
    src="{{path}}"
    [ -e "$src" ] || { echo "does not exist: $src" >&2; exit 1; }
    src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"   # make absolute path
    sz="$(du -sh "$src" 2>/dev/null | cut -f1)"
    echo "Archive target: $src ($sz)"
    read -rp "Local files will be deleted after evacuation to restic. Continue? (y/N) " a
    [[ "$a" == [yY] ]] || { echo "aborted"; exit 0; }
    if restic backup --tag "$RESTIC_ARCHIVE_TAG" "$src"; then
      echo "✓ Evacuation complete (--tag archive, kept forever). Deleting local files."
      rm -rf "$src"
      echo "✓ Local deleted: $src"
      echo "  List: just archive-ls  /  Restore: just restore <snapshotID>"
    else
      echo "✗ restic backup failed. Local files were not deleted." >&2
      exit 1
    fi

# List archive (--tag archive) snapshots (ID / date / original path)
[group('Backup')]
archive-ls:
    @{{restic_env}}; restic snapshots --tag "$RESTIC_ARCHIVE_TAG"

# Total size and file count of the archive
[group('Backup')]
archive-stats:
    @{{restic_env}}; restic stats --tag "$RESTIC_ARCHIVE_TAG"

# Search the archive by filename (restic find, no FUSE needed). Shows which snapshot it is in.
# Example: `just archive-find "*.psd"` / `just archive-find old-project`
[group('Backup')]
archive-find pattern:
    @{{restic_env}}; restic find --tag "$RESTIC_ARCHIVE_TAG" "{{pattern}}"

# ── shared: restore / shared mount ──

# Restore from a snapshot (shared by warm/cold). Defaults to the original absolute path. `unarchive` is a synonym.
# Example: `just restore a81c9de1`            to the original location
#          `just restore a81c9de1 ~/Restore`  to the specified target (expanded preserving structure)
[group('Backup')]
restore snapshot dest="/":
    #!/usr/bin/env bash
    set -euo pipefail
    {{restic_env}}
    restic restore "{{snapshot}}" --target "{{dest}}"
    echo "✓ Restored: snapshot {{snapshot}} → {{dest}}"

alias unarchive := restore

# Shared GoogleDrive mount ops (separate personal/school mounts). `just gdrive`=status / `open`=open in Finder
# Both mounts are declared in nix/home/rclone-mount.nix as LaunchAgents (the old hand-written
# ~/Library/LaunchAgents/com.gapul.rclone.* plists are retired), so remount is just a kickstart.
[group('Backup')]
gdrive cmd="status":
    #!/usr/bin/env bash
    set -euo pipefail
    remotes=(google-drive-personal google-drive-school)
    mounts=("$HOME/Sync/google-drive-personal" "$HOME/Sync/google-drive-school")
    case "{{cmd}}" in
      status)
        for mp in "${mounts[@]}"; do
          mount | grep -q " $mp " && echo "✓ Mounted: $mp" || echo "✗ Not mounted: $mp"
        done ;;
      open)
        for mp in "${mounts[@]}"; do [ -d "$mp" ] && open "$mp" || echo "✗ Not mounted: $mp" >&2; done ;;
      remount)
        for r in "${remotes[@]}"; do
          launchctl kickstart -k "gui/$UID/org.nix-community.home.rclone-$r" && echo "↻ $r"
        done ;;
      *)       echo "usage: just gdrive [status|open|remount]" >&2; exit 2 ;;
    esac
