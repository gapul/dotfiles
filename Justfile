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
[doc('Rebuild the system and user configuration. `just rebuild force` activates even when nothing changed')]
rebuild force="":
    @just _rebuild-{{os()}} {{force}}

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
_rebuild-macos force="":
    @scripts/rebuild-macos.sh "{{force}}"

[private]
_rebuild-linux:
    #!/usr/bin/env bash
    set -euo pipefail
    # On a NixOS host with its own nixosConfigurations entry (nixos-laptop), home-manager is a
    # NixOS module, so there is no standalone homeConfigurations to switch; rebuild the system.
    host=$(hostname)
    if [ -e /etc/NIXOS ] && [ "$(nix eval "{{flake}}#nixosConfigurations" --apply "a: a ? \"$host\"" 2>/dev/null || echo false)" = true ]; then
      echo "━━━ nixos ($host, home-manager included)"
      nh os switch "{{flake}}" -H "$host" -q -Q --diff never
      echo "✓ nixos"
    else
      echo "━━━ home-manager"
      nh home switch -q -Q --diff never
      echo "✓ home-manager"
    fi

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
    #!/usr/bin/env bash
    set -euo pipefail
    # Unauthenticated GitHub API calls are capped at 60/h per IP; past that, inputs silently keep
    # their cached revision ("using cached version"). Borrow gh's token when it is logged in.
    if command -v gh >/dev/null && token=$(gh auth token 2>/dev/null) && [ -n "$token" ]; then
      export NIX_CONFIG="access-tokens = github.com=$token
    ${NIX_CONFIG:-}"
    fi
    nix flake update --quiet {{inputs}} --flake {{flake}}

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
    @# One brew per kind, not one per entry: `brew trust` takes many targets, and each brew start
    @# is about 0.4s of Ruby — 28 of them were 11s of the package lane.
    @-brew tap 2>/dev/null | grep -v '^homebrew/' | xargs brew trust >/dev/null
    @-brew trust --cask gerlero/openfoam/openfoam@2606 >/dev/null
    @-brew list --cask --full-name 2>/dev/null | grep '/' | xargs brew trust --cask >/dev/null

[private]
_upgrade-packages-macos:
    @scripts/upgrade-packages-macos.sh

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
    @scripts/maintain-macos.sh

[private]
_maintain-linux:
    @scripts/maintain-linux.sh

[private]
_maintain-user-tools:
    @if command -v tldr >/dev/null; then echo "━━━ tldr cache ━━━"; tldr --update || true; fi
    @if command -v gh >/dev/null && gh extension list 2>/dev/null | grep -q .; then echo "━━━ GitHub CLI extensions ━━━"; gh extension upgrade --all || true; fi

[private]
_maintain-windows:
    just win-bootstrap
    just win-upgrade
    @echo "Windows: gc recipe is not defined; package update completed."

# Update the GitHub pins nothing else updates (the yazi plugins, the Rosé Pine tmThemes, prh).
[private]
github-pins:
    @nix shell nixpkgs#bun -c scripts/github-pins.ts

# Update sketchybar-app-font assets from the same release.
[private]
sketchybar-font:
    @nix shell nixpkgs#bun -c scripts/sketchybar-font.ts


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
    @nix shell nixpkgs#bun -c scripts/outdated.ts

# Environment health check (run after e.g. a Determinate upgrade)
[group('Inspect')]
doctor format="":
    @scripts/doctor.sh "{{format}}"

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

# Hide backstage apps (Adobe helpers, Karabiner's driver manager) from the Applications launcher
[group('Clean')]
tidy-apps:
    "{{ justfile_directory() }}/scripts/hide-backstage-apps.sh"

# GC all layers at once (only regenerable caches; Trash and whole-home deletion are in gc-deep)
[group('Clean')]
gc:
    @scripts/gc.sh

# Interactively delete heavy regenerable data (Trash / zap of retired casks / CoreSimulator cache / podman / old build artifacts)
[group('Clean')]
gc-deep:
    @scripts/gc-deep.sh


# ─────────────────────────────────────────────
# Service (restart / restarting the menu-bar and WM stack)
# ─────────────────────────────────────────────

# NOTE: omniwm full restart = the workspace layout is reset, so only on explicit request (omniwm/all).
# Restart the menu-bar/WM stack (`just restart`=bar-related / individual: sketchybar|omniwm / all=everything)
[group('Service')]
restart what="bar":
    #!/usr/bin/env bash
    set -u
    uid=$(id -u)

    # 2 instances: the built-in bar and the external-monitor one (see darwin-chrome.nix)
    sb() {
      echo "-> sketchybar (main + ext)"
      launchctl kickstart -k "gui/$uid/org.nix-community.home.sketchybar"
      launchctl kickstart -k "gui/$uid/org.nix-community.home.sketchybar-ext"
    }
    om() {
      echo "-> OmniWM (full restart)"
      osascript -e 'quit app "OmniWM"' 2>/dev/null
      # Poll up to 4s for quit to finish (a fixed sleep would let open miss when quit is slow)
      for _ in $(seq 1 20); do pgrep -xq OmniWM || break; sleep 0.2; done
      open -a OmniWM
    }

    case "{{what}}" in
      bar)            sb ;;
      sketchybar|sb)  sb ;;
      omniwm|om|wm)   om ;;
      all)            sb; om ;;
      *) echo "usage: just restart [bar|sketchybar|omniwm|all]" >&2; exit 2 ;;
    esac
    echo "Done"


# ─────────────────────────────────────────────
# secrets (sops encryption)
# ─────────────────────────────────────────────

# sops-encrypted secrets  (`just secrets [file]` = edit, `just secrets rekey` = re-encrypt every file)
# Files are split per host since #393: common / darwin / homelab, each with its own recipients.
[group('secrets')]
secrets cmd="edit" file="common":
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}/secrets"
    case "{{cmd}}" in
      edit)  sops "{{file}}.yaml" ;;                       # edit (default: common)
      # rekey every file, not just one: .sops.yaml changes usually touch several rule blocks,
      # and a file left un-rekeyed fails to decrypt on the host that just gained a recipient.
      rekey) for f in *.yaml; do echo "→ $f"; sops updatekeys -y "$f"; done ;;
      *)     echo "usage: just secrets [edit|rekey] [common|darwin|homelab]" >&2; exit 2 ;;
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
# Targets: the just recipe list, the pre-commit hook table, the shell alias table (see scripts/gen-docs.ts).
# Run this after changing a recipe/hook/alias. CI drift detection is handled by check-generated.sh.
[group('Setup')]
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    nix shell nixpkgs#bun -c bun scripts/gen-docs.ts

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

# Pull GUI-side preference changes back into the repo (live -> dotfiles).
[group('Setup')]
[doc('Sync GUI app preference changes back into dotfiles (live -> repo)')]
plist-sync:
    @nix shell nixpkgs#bun -c scripts/plist-sync.ts


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

# Declaratively apply telemetry/built-in feature settings (pinned Win11Debloat + WinUtil + baseline.psd1)
# Pass `-DryRun` `-SkipWinUtil` `-SkipWin11Debloat` `-SkipCustomApps` `-SkipBaseline` via `*flags`
[group('Windows')]
win-privacy *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/privacy/apply.ps1 {{flags}}

# Compare the machine against windows/privacy/baseline.psd1 (read-only, exits 1 on drift)
[group('Windows')]
win-privacy-verify:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/privacy/verify.ps1

# Check the privacy declarations against the pinned upstream scripts (runs on macOS/Linux)
[group('Windows')]
win-privacy-check-upstream:
    nix shell nixpkgs#bun -c windows/privacy/check-upstream.ts

# Re-pin Win11Debloat and WinUtil to their latest releases, then run the check above
[group('Windows')]
win-privacy-update-upstream:
    nix shell nixpkgs#bun -c windows/privacy/update-upstream.ts

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

# User-scope install of HackGen NF, downloaded from its GitHub release (HKCU registration, no admin required)
# Pass `-DryRun` or `-SkipHackGen` via `*flags`
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

# nssh 先へ配る Claude Code の設定は母艦を正とする。母艦で /config などを触ったらこれを走らせて
# configs/cli/claude/settings.remote.json へ吸い上げ、次の nssh でリモートへ降ろす。
# 吸い上げるのはそのファイルが既に持つ管理キーだけで、permissions はホスト所有のまま触らない
# (理由は configs/cli/claude/README.md)。
[group('Setup')]
[doc("Adopt this machine's Claude Code settings into the remote-managed keys (client wins)")]
claude-settings-adopt:
    #!/usr/bin/env bash
    set -euo pipefail
    src="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    if [ ! -f "$src" ]; then
      echo "Claude の設定が見つかりません: $src" >&2
      exit 1
    fi
    python3 scripts/merge-claude-settings.py "$src" --adopt

[private]
_theme-macos name="": (_theme-unix name)

[private]
_theme-linux name="": (_theme-unix name)

# On both Mac/WSL, nh home switch makes nvim/tmux/sketchybar/bat/atuin etc. all follow
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

# Shared Google Drive mount ops. `just gdrive`=status / `open`=open in Finder.
# All mounts are declared in nix/home/rclone-mount.nix as LaunchAgents (the old hand-written
# ~/Library/LaunchAgents/com.gapul.rclone.* plists are retired), so remount is just a kickstart.
[group('Backup')]
gdrive cmd="status":
    #!/usr/bin/env bash
    set -euo pipefail
    remotes=(google-drive google-drive-school google-drive-work)
    mounts=("$HOME/Sync/google-drive" "$HOME/Sync/google-drive-school" "$HOME/Sync/google-drive-work")
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


# ─────────────────────────────────────────────
# Homelab (DNS / tailnet / デバイス)
# ─────────────────────────────────────────────

# Diff the repo's declarations against Cloudflare DNS: A records, tunnel CNAMEs, and mail (MX/SPF/DKIM)
[group('Homelab')]
dns *flags:
    @nix shell nixpkgs#bun -c scripts/check-dns-drift.ts {{flags}}

# Build the NixOS-WSL rootfs tarball on homeserver and bring it back (mac can't build it)
[group('Homelab')]
wsl-tarball flake="github:gapul/dotfiles?dir=nix":
    #!/usr/bin/env bash
    set -euo pipefail
    # root と Linux が要るので homeserver で作る。母艦は Mach-O なので nix でも作れない。
    ssh homeserver 'set -e; d=$(mktemp -d); cd "$d"; \
      sudo nix run --extra-experimental-features "nix-command flakes" \
        "{{flake}}#nixosConfigurations.wsl.config.system.build.tarballBuilder"; \
      echo "$d/nixos.wsl"' | tail -1 | {
      read -r remote
      scp "homeserver:$remote" /tmp/nixos.wsl
      ssh homeserver "rm -rf $(dirname "$remote")"
      echo "できた: /tmp/nixos.wsl  (Windows 側で wsl --import する。docs/NIXOS_WSL.md)"
    }

# Fetch, diff, or apply the tailnet policy file (ACL / split DNS). Needs TS_API_KEY
[group('Homelab')]
tailnet cmd="diff":
    @scripts/tailscale-policy.sh {{cmd}}

# Validate the ESPHome device configs without hardware
[group('Homelab')]
esphome:
    @nix shell nixpkgs#esphome -c ./esphome/validate.sh

# ─────────────────────────────────────────────
# Mobile (iOS / Android)
# ─────────────────────────────────────────────

# Diff apps.tsv against the device, or converge it (`just android-apps` / `install` / `verify` / `obtainium`)
[group('Mobile')]
android-apps cmd="status":
    @nix shell nixpkgs#android-tools nixpkgs#fdroidcl nixpkgs#bun -c mobile/android/apps.ts {{cmd}}

# Apply the declared Android OS settings over adb (`just android-os` = diff + apply, `just android-os --dry-run`)
[group('Mobile')]
android-os *flags:
    @nix shell nixpkgs#android-tools -c mobile/android/os.sh {{flags}}

# Generate the Kvaesitso launcher theme from palettes.json and push it to the device
[group('Mobile')]
android-launcher-theme:
    #!/usr/bin/env bash
    set -euo pipefail
    out="$(mktemp -d)/kvaesitso-theme.json"
    nix shell nixpkgs#bun -c mobile/android/launcher-theme.ts >"$out"
    nix shell nixpkgs#android-tools -c adb push "$out" /sdcard/Download/
    echo "端末で Kvaesitso → 設定 → 外観 → テーマ → インポート から選ぶ"

# Diff ios/apps.tsv against a USB-connected iPhone (`just ios-apps` / `just ios-apps verify`)
[group('Mobile')]
ios-apps cmd="status":
    @nix shell nixpkgs#ideviceinstaller nixpkgs#bun -c mobile/ios/apps.ts {{cmd}}

# Export iCloud-synced Shortcuts into the repo, or compile .cherri sources into signed shortcuts
[group('Mobile')]
ios-shortcuts cmd="status":
    @mobile/ios/shortcuts.sh {{cmd}}

# Build the declared .mobileconfig profiles and serve them on the LAN for an iPhone to install
[group('Mobile')]
ios-profiles port="8000":
    @mobile/ios/profiles/serve.sh {{port}}

# Mail profiles with their passwords filled in from sops (`mac` = open here for Mail.app, `serve` = iPhone over the tailnet)
[group('Mobile')]
mail-profiles mode="mac" port="8000":
    @mobile/ios/profiles/mail.sh {{mode}} {{port}}

# Self-check both platforms' scripts with stubbed adb / ideviceinstaller (no device needed)
[group('Mobile')]
mobile-test:
    @nix shell nixpkgs#bun -c sh -c 'mobile/android/test.sh && mobile/ios/test.sh'
