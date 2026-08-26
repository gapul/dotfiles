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
    #!/usr/bin/env bash
    set -euo pipefail
    # Activate only what actually changed. Evaluating both outPaths costs about ten seconds;
    # a switch that has nothing to do costs a minute (darwin ~15s incl. the Homebrew bundle,
    # home ~40s of relinking). Most rebuilds — every `git pull` of main via the post-merge hook —
    # change one of the two at most, and plenty change neither.
    # The catch: activation is also what repairs drift made outside nix (a hand-run `brew install`,
    # a `defaults write`, a launchd agent someone unloaded). Skipping means not repairing. That is
    # what `just rebuild force` is for, and what `just maintain` uses.
    # nh is given the same flake path the check evaluates, plus the configuration name: left to
    # itself it resolves the flake from the working directory's git root (a different tree when
    # this runs from a worktree, so check and switch would disagree forever) and picks the config
    # by hostname, which here is MacBook-Mini while the attribute is named after the user.
    # The username is only the right answer on the workstation. Both Macs report the same
    # LocalHostName, so a machine that is not the workstation has to say so out loud, in
    # ~/.config/dotfiles/host (macmini declares that file in home/macmini.nix). Getting this
    # wrong is not a no-op: on the mac mini it quietly activated the workstation config,
    # dropping the manabi tunnel and the ollama agent and pulling in the GUI cask list.
    name="$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host" 2>/dev/null || id -un)"
    sys_want=$(nix eval --raw "{{flake}}#darwinConfigurations.$name.config.system.build.toplevel.outPath")
    # Hosts whose home rides inside the darwin config (the mac mini) have no standalone
    # homeConfigurations entry; there is nothing to activate separately.
    home_want=$(nix eval --raw "{{flake}}#homeConfigurations.$name.activationPackage.outPath" 2>/dev/null || true)
    sys_have=$(readlink /run/current-system || true)
    home_have=$(readlink "$HOME/.local/state/home-manager/gcroots/current-home" || true)
    do_sys=1; do_home=1
    [ -z "$home_want" ] && do_home=0
    if [ -z "{{force}}" ]; then
      [ "$sys_want" = "$sys_have" ] && do_sys=0
      [ "$home_want" = "$home_have" ] && do_home=0
    fi
    if [ "$do_sys" = 0 ] && [ "$do_home" = 0 ]; then
      echo "✓ already current (nothing to activate; use \`just rebuild force\` to activate anyway)"
      exit 0
    fi
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
    # The build runs under a QoS clamp so it cannot starve Ghostty: if the build pins the
    # CPU, Ghostty's event handling misses its deadline and the global keybind's CGEventTap
    # is disabled with kCGEventTapDisabledByTimeout, after which cmd+space stops working
    # while unfocused (Ghostty does not re-enable the tap itself: ghostty#11883).
    # `-c utility` rather than `-b`: background QoS parks the build on the efficiency cores,
    # which made every rebuild several times slower than it needed to be. utility still yields
    # to anything user-interactive, which is all the tap needs.
    if [ "$do_sys" = 1 ]; then
      echo "━━━ nix-darwin" | tee -a "$log"
      taskpolicy -c utility nh darwin switch {{flake}} -H "$name" -q -Q --diff never $nom_flag 2>&1 | tee -a "$log"
      echo "✓ nix-darwin" | tee -a "$log"
    else
      echo "– nix-darwin unchanged" | tee -a "$log"
    fi
    if [ -z "$home_want" ]; then
      echo "– home-manager: this host has no standalone config (it rides inside nix-darwin)" | tee -a "$log"
      open -a Ghostty >/dev/null 2>&1 || true
      exit 0
    fi
    echo "━━━ home-manager" | tee -a "$log"
    # -b hm-bak: standalone home-manager has no backupFileExtension option (that one only exists on
    # the nix-darwin/NixOS module path), and without a backup extension a newly declared home.file
    # whose target already exists is skipped — the declaration silently does nothing. That is how
    # gh-dash/config.yml and slk/config.toml stayed plain files after #153 declared them.
    if [ "$do_home" = 1 ]; then
      taskpolicy -c utility nh home switch {{flake}} -c "$name" -q -Q --diff never -b hm-bak $nom_flag 2>&1 | tee -a "$log"
      echo "✓ home-manager" | tee -a "$log"
    else
      echo "– home-manager unchanged" | tee -a "$log"
    fi
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
    #!/usr/bin/env bash
    set -u
    # Xcode and the SketchyBar font share nothing with Homebrew, and this link gives roughly
    # twice the throughput over parallel connections as over one (measured: 20 MB/s single,
    # 40 MB/s over four), so they download alongside the brew work instead of after it.
    # Homebrew's own steps stay strictly serial: brew holds a lock, so a second brew process
    # would only wait or fail. Output is buffered and replayed so three downloads do not
    # interleave into unreadable soup.
    xcode_out=$(mktemp); font_out=$(mktemp)
    # </dev/null: xcodes asks for a 2FA code on stdin when the saved session has expired, and this
    # lane's output is buffered, so the question is invisible and the whole maintain waits forever
    # on an answer nobody was asked for. With no stdin it fails fast into the "re-run" message
    # below instead. sudo is unaffected — it reads the tty directly, not stdin.
    just _xcode-upgrade >"$xcode_out" 2>&1 </dev/null &
    xcode_pid=$!
    just sketchybar-font >"$font_out" 2>&1 &
    font_pid=$!
    pins_out=$(mktemp)
    just github-pins >"$pins_out" 2>&1 &
    pins_pid=$!
    # Order matters: `brew update` resets the trust of unofficial taps, so run update
    # first, then trust, and run the subsequent upgrade with HOMEBREW_NO_AUTO_UPDATE=1
    # so the trust is not reset again. Skip this and update ->
    # (trust lost) -> upgrade makes qmk/qmk (formula) and y3owk1n/tap/neru (cask)
    # get refused as untrusted; the cask is swallowed by `|| true` and the final check fails.
    brew update --quiet || true
    just _brew-trust-taps
    just _brew-formula-upgrade
    echo "━━━ Homebrew casks"
    HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --quiet --cask --greedy || true
    wait $xcode_pid || true; cat "$xcode_out"; rm -f "$xcode_out"
    wait $font_pid || true; cat "$font_out"; rm -f "$font_out"
    wait $pins_pid || true; cat "$pins_out"; rm -f "$pins_out"
    # The --greedy upgrade above also targets auto_updates/`version :latest` casks,
    # but those stay "outdated" forever and can never "complete" (e.g. figma-agent,
    # pear-desktop; for the latter the upstream cask errors on upgrade itself due to a
    # missing URL, swallowed by `|| true`). So judge completion with outdated without --greedy.
    # Non-greedy does not list auto_updates/latest, so it detects only missed real
    # version updates and does not break as auto_updates casks grow (previously
    # figma-agent was grep-excluded, but enumerating them breaks, so that was removed).
    remaining=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --cask 2>/dev/null || true)
    if [ -n "$remaining" ]; then echo "ERROR: cask upgrade incomplete:" >&2; echo "$remaining" >&2; exit 1; fi

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
    # Authenticate once for the whole run. Four things here need root — determinate-nixd,
    # xcodebuild, nh darwin switch, nh clean — and they are spread across ten-plus minutes,
    # well past sudo's five-minute timestamp, so each one raised its own Touch ID prompt
    # (the last two land after the parallel lanes, i.e. long after you walked away).
    # `sudo -v` takes the one prompt up front and the loop keeps the ticket warm until we exit.
    sudo -v
    while :; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
    sudo_keepalive=$!
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
    # No `nix flake update` here on purpose. The weekly update-flake-lock workflow opens a PR for
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
    # Same host resolution as _rebuild-macos: the username is only right on the workstation.
    name="$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host" 2>/dev/null || id -un)"
    # Only asking whether the host has a standalone home config. Evaluating activationPackage to
    # find out is the same full home-manager eval the build below does anyway — a minute idle here
    # on a quiet machine, and it was still going after twelve on a loaded one (the source-to-store
    # writer is one daemon round trip per file). `?` on the attrset never forces the value.
    home_attr=""
    [ "$(nix eval "{{flake}}#homeConfigurations" --apply "a: a ? \"$name\"" 2>/dev/null)" = true ] \
      && home_attr="{{flake}}#homeConfigurations.$name.activationPackage"
    nix_out=$(mktemp); tools_out=$(mktemp)
    nix build --no-link \
      "{{flake}}#darwinConfigurations.$name.config.system.build.toplevel" \
      $home_attr >"$nix_out" 2>&1 &
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
    just gc
    brew services cleanup || true
    just doctor || true
    trap - EXIT
    kill $sudo_keepalive 2>/dev/null || true
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

# Update the GitHub pins nothing else updates.
#
# flake.lock covers the flake inputs and nixpkgs covers what it packages, but a handful of
# things are pinned by hand: two yazi packages that are not in nixpkgs, the Rosé Pine
# tmThemes, and prh's dictionary. They used to be vendored files that `just maintain` never
# touched either, so this is not a new chore — it is the same chore, now with a hash to check.
#
# Run from the macOS lane only (BSD `sed -i ""`), like sketchybar-font. The pins it edits are
# committed, so whichever machine runs it updates them for all of them.
[private]
github-pins:
    #!/usr/bin/env bash
    set -uo pipefail
    dir="{{justfile_directory()}}"
    changed=()

    # file | repo | the line rev/hash follow
    tarballs='nix/modules/home/cli.nix|h-hg/yamb.yazi|repo = "yamb.yazi";
    nix/modules/home/cli.nix|Mintass/rose-pine.yazi|repo = "rose-pine.yazi";
    nix/lib/rose-pine-tm-theme.nix|rose-pine/tm-theme|repo = "tm-theme";'

    while IFS='|' read -r file repo anchor; do
      file="$dir/${file# }"; anchor="${anchor# }"
      # An unreachable API is a skip, not a failure — same as the font above: this runs inside
      # `just maintain`, and a pin being a week old is not worth aborting an upgrade over.
      sha=$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].sha' 2>/dev/null) || {
        echo "– $repo: commit lookup failed (offline?); skipped" >&2; continue
      }
      cur=$(grep -A1 -F "$anchor" "$file" | sed -n 's/.*rev = "\([^"]*\)".*/\1/p')
      # The pins were written short; a short rev is a prefix of the long one it names.
      case "$sha" in "$cur"*) continue ;; esac
      hash=$(nix store prefetch-file --json --unpack "https://github.com/$repo/archive/$sha.tar.gz" 2>/dev/null | jq -r .hash) || {
        echo "– $repo: prefetch failed; skipped" >&2; continue
      }
      sed -i "" -E "/$(printf '%s' "$anchor" | sed 's/[\/&]/\\&/g')/{n;s|rev = \"[^\"]*\"|rev = \"$sha\"|;n;s|hash = \"[^\"]*\"|hash = \"$hash\"|;}" "$file"
      # A rewritten rev with a stale hash is the quiet failure here: a fixed-output derivation is
      # keyed by its hash, so nix would hand out the old contents and never fetch the new ones.
      if ! grep -qF "$sha" "$file" || ! grep -qF "$hash" "$file"; then
        echo "– $repo: rewrite did not take; leaving the pin alone" >&2
        git -C "$dir" checkout -- "$file"
        continue
      fi
      echo "$repo: ${cur:-?} -> ${sha:0:7}"
      changed+=("$file")
    done <<< "$tarballs"

    # prh's dictionary is a single file, pinned by the commit in its URL.
    file="$dir/nix/home/workstation.nix"
    if sha=$(gh api "repos/prh/rules/commits?per_page=1" --jq '.[0].sha' 2>/dev/null); then
      cur=$(sed -n 's|.*raw.githubusercontent.com/prh/rules/\([0-9a-f]*\)/.*|\1|p' "$file")
      if [ "$sha" != "$cur" ]; then
        url="https://raw.githubusercontent.com/prh/rules/$sha/media/WEB%2BDB_PRESS.yml"
        if hash=$(nix store prefetch-file --json "$url" 2>/dev/null | jq -r .hash); then
          sed -i "" -E "s|(raw.githubusercontent.com/prh/rules/)[0-9a-f]+|\\1$sha|" "$file"
          sed -i "" -E "/raw.githubusercontent.com\/prh\/rules/{n;s|hash = \"[^\"]*\"|hash = \"$hash\"|;}" "$file"
          if grep -qF "$sha" "$file" && grep -qF "$hash" "$file"; then
            # Often only the commit moves: the dictionary is one file in a repository of them.
            echo "prh/rules: ${cur:0:7} -> ${sha:0:7}"
            changed+=("$file")
          else
            echo "– prh/rules: rewrite did not take; leaving the pin alone" >&2
            git -C "$dir" checkout -- "$file"
          fi
        fi
      fi
    else
      echo "– prh/rules: commit lookup failed (offline?); skipped" >&2
    fi

    if [ ${#changed[@]} -gt 0 ]; then
      git -C "$dir" add "${changed[@]}"
      echo "Updated pins. Apply with: just rebuild (automatic when run via upgrade)"
    fi

# Update sketchybar-app-font assets from the same release.
[private]
sketchybar-font:
    #!/usr/bin/env bash
    set -euo pipefail
    repo="kvndrsslr/sketchybar-app-font"
    dir="{{justfile_directory()}}"
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
    gh release download "$tag" --repo "$repo" --pattern icon_map.sh --output "$map" --clobber
    awk '/^### END-OF-ICON-MAP/{print; print "__icon_map \"$1\""; print "[ -r \"${BASH_SOURCE%/*}/icon_map_local.sh\" ] && source \"${BASH_SOURCE%/*}/icon_map_local.sh\""; print "echo \"$icon_result\""; exit} {print}' "$map" > "$map.tmp" && mv "$map.tmp" "$map"
    # gh release assets are non-executable, so restore +x; plugins run icon_map.sh
    # directly ($(...)), and without +x it fails with "permission denied" -> the
    # workspace app icons silently vanish. `chmod` before `git add` so the staged
    # mode is recorded as 100755 too.
    chmod +x "$map"
    # The font itself is fetched by nix, so what gets updated here is the pin: version, URL,
    # and hash. Prefetching is what produces the hash — a wrong one fails the build, loudly.
    hash=$(nix store prefetch-file --json "https://github.com/$repo/releases/download/$tag/sketchybar-app-font.ttf" | jq -r .hash)
    sed -i "" -E '/pname = "sketchybar-app-font"/{n;s/version = "[0-9.]+"/version = "'"${tag#v}"'"/;}' "$dir/nix/hosts/darwin.nix"
    sed -i "" -E 's|(sketchybar-app-font/releases/download/)v[0-9.]+|\1'"$tag"'|' "$dir/nix/hosts/darwin.nix"
    sed -i "" -E '/sketchybar-app-font\/releases\/download/{n;s|hash = "[^"]*"|hash = "'"$hash"'"|;}' "$dir/nix/hosts/darwin.nix"
    git -C "$dir" add "$map" "$dir/nix/hosts/darwin.nix"
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
        --argjson sketchybar "$(pgrep -xq sketchybar && echo true || echo false)" \
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
    pgrep -xq sketchybar || down+=(sketchybar)
    pgrep -fq "sketchybar-ext" || down+=(sketchybar-ext)
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

# Hide backstage apps (Adobe helpers, Karabiner's driver manager) from the Applications launcher
[group('Clean')]
tidy-apps:
    "{{ justfile_directory() }}/scripts/hide-backstage-apps.sh"

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
      # -x for the same reason as the Dev caches sweep above: without it this walks the two
      # rclone Google Drive mounts under ~/Sync, which is both endless and the last place we
      # want to be deleting ._* and .DS_Store.
      d=$(find -x "$HOME" \( -path "$HOME/.Trash" -o -path "$HOME/Library" \) -prune -o -type f \( -name '.DS_Store' -o -name '._*' -o -name '*.swp' -o -name '*.swo' -o -name '*.orig' -o -name '*.rej' -o -name '*~' \) -print -delete 2>/dev/null | wc -l | tr -d ' ')
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

    # 2 instances: the built-in bar and the external-monitor one (see darwin-chrome.nix)
    sb() {
      echo "-> sketchybar (main + ext)"
      launchctl kickstart -k "gui/$uid/org.nix-community.home.sketchybar"
      launchctl kickstart -k "gui/$uid/org.nix-community.home.sketchybar-ext"
    }
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


# ─────────────────────────────────────────────
# Homelab (DNS / tailnet / デバイス)
# ─────────────────────────────────────────────

# Diff the repo's declarations against Cloudflare DNS: A records, tunnel CNAMEs, and mail (MX/SPF/DKIM)
[group('Homelab')]
dns *flags:
    @scripts/check-dns-drift.sh {{flags}}

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
      mkdir -p ~/tmp
      scp "homeserver:$remote" ~/tmp/nixos.wsl
      ssh homeserver "rm -rf $(dirname "$remote")"
      echo "できた: ~/tmp/nixos.wsl  (Windows 側で wsl --import する。docs/NIXOS_WSL.md)"
    }

# Fetch, diff, or apply the tailnet policy file (ACL / split DNS). Needs TS_API_KEY
[group('Homelab')]
tailnet cmd="diff":
    @scripts/tailscale-policy.sh {{cmd}}

# Fetch, diff, or apply the NextDNS profile. Needs NEXTDNS_API_KEY / NEXTDNS_PROFILE
[group('Homelab')]
nextdns cmd="diff":
    @scripts/nextdns-profile.sh {{cmd}}

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
    @nix shell nixpkgs#android-tools nixpkgs#fdroidcl -c mobile/android/apps.sh {{cmd}}

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
    mobile/android/launcher-theme.py >"$out"
    nix shell nixpkgs#android-tools -c adb push "$out" /sdcard/Download/
    echo "端末で Kvaesitso → 設定 → 外観 → テーマ → インポート から選ぶ"

# Diff ios/apps.tsv against a USB-connected iPhone (`just ios-apps` / `just ios-apps verify`)
[group('Mobile')]
ios-apps cmd="status":
    @nix shell nixpkgs#ideviceinstaller -c mobile/ios/apps.sh {{cmd}}

# Export iCloud-synced Shortcuts into the repo, or compile .cherri sources into signed shortcuts
[group('Mobile')]
ios-shortcuts cmd="status":
    @mobile/ios/shortcuts.sh {{cmd}}

# Build the declared .mobileconfig profiles and serve them on the LAN for an iPhone to install
[group('Mobile')]
ios-profiles port="8000":
    @mobile/ios/profiles/serve.sh {{port}}

# Self-check both platforms' scripts with stubbed adb / ideviceinstaller (no device needed)
[group('Mobile')]
mobile-test:
    @mobile/android/test.sh && mobile/ios/test.sh
