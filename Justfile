# Dotfiles task runner. Use `just` to list tasks.
# https://just.systems

set shell := ["bash", "-cu"]
# Run native Windows recipes directly in PowerShell.
set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]

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

[private]
_rebuild-macos:
    @-brew tap 2>/dev/null | grep -v '^homebrew/' | xargs -I% env -u XDG_CONFIG_HOME brew trust % >/dev/null
    @-env -u XDG_CONFIG_HOME brew trust --cask gerlero/openfoam/openfoam@2606 >/dev/null
    @-brew list --cask --full-name 2>/dev/null | grep '/' | xargs -I% env -u XDG_CONFIG_HOME brew trust --cask % >/dev/null
    # taskpolicy -b でビルドを background QoS に落とす。ビルドで CPU が張り付くと
    # Ghostty のイベント処理が締め切りに間に合わず global keybind の CGEventTap が
    # kCGEventTapDisabledByTimeout で無効化され、以後フォーカス外の cmd+space が
    # 効かなくなる (Ghostty は tap を自力再有効化しない: ghostty#11883)。優先度を
    # 下げて Ghostty を枯渇させないことで tap 無効化を予防する。
    @echo "━━━ nix-darwin"
    @taskpolicy -b nh darwin switch -q -Q --diff never
    @echo "✓ nix-darwin"
    @echo "━━━ home-manager"
    @taskpolicy -b nh home switch -q -Q --diff never
    @echo "✓ home-manager"
    @-open -a Ghostty >/dev/null 2>&1 || true

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
_upgrade-packages-macos:
    @echo "━━━ Homebrew formulae"
    @brew upgrade --quiet --formula
    @echo "━━━ Homebrew casks"
    @brew upgrade --quiet --cask --greedy || true
    @echo "━━━ App Store"
    @mas upgrade
    @just sketchybar-font
    @remaining=$(brew outdated --cask --greedy 2>/dev/null | grep -v '^figma-agent$' || true); if [ -n "$remaining" ]; then echo "ERROR: cask upgrade incomplete:" >&2; echo "$remaining" >&2; exit 1; fi

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
      # 保持者 PID が生きていれば本当に実行中。死んでいれば中断残骸なので奪う
      # (mkdir だけのロックは SIGKILL / ビルド中断で必ず stale 化するため)。
      holder=$(cat "$maintenance_lock/pid" 2>/dev/null || true)
      if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        echo "another dotfiles maintenance task is running (pid $holder)" >&2; exit 1
      fi
      echo "reclaiming stale maintenance lock (pid ${holder:-?} not running)" >&2
      rm -rf "$maintenance_lock"
      mkdir "$maintenance_lock" 2>/dev/null || { echo "failed to acquire maintenance lock" >&2; exit 1; }
    fi
    echo $$ > "$maintenance_lock/pid"
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
      # 保持者 PID が生きていれば本当に実行中。死んでいれば中断残骸なので奪う
      # (mkdir だけのロックは SIGKILL / ビルド中断で必ず stale 化するため)。
      holder=$(cat "$maintenance_lock/pid" 2>/dev/null || true)
      if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        echo "another dotfiles maintenance task is running (pid $holder)" >&2; exit 1
      fi
      echo "reclaiming stale maintenance lock (pid ${holder:-?} not running)" >&2
      rm -rf "$maintenance_lock"
      mkdir "$maintenance_lock" 2>/dev/null || { echo "failed to acquire maintenance lock" >&2; exit 1; }
    fi
    echo $$ > "$maintenance_lock/pid"
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
    tag=$(gh release view --repo "$repo" --json tagName -q .tagName)
    cur=$(awk '/pname = "sketchybar-app-font"/{getline; if (match($0,/[0-9][0-9.]*/)) print substr($0,RSTART,RLENGTH); exit}' "$dir/nix/hosts/darwin.nix")
    if [ "$tag" = "v$cur" ]; then
      exit 0
    fi
    echo "sketchybar-app-font: updating $cur -> $tag"
    gh release download "$tag" --repo "$repo" --pattern sketchybar-app-font.ttf --output "$ttf"  --clobber
    gh release download "$tag" --repo "$repo" --pattern icon_map.sh           --output "$map"  --clobber
    awk '/^### END-OF-ICON-MAP/{print; print "__icon_map \"$1\""; print "[ -r \"${BASH_SOURCE%/*}/icon_map_local.sh\" ] && source \"${BASH_SOURCE%/*}/icon_map_local.sh\""; print "echo \"$icon_result\""; exit} {print}' "$map" > "$map.tmp" && mv "$map.tmp" "$map"
    sed -i "" -E '/pname = "sketchybar-app-font"/{n;s/version = "[0-9.]+"/version = "'"${tag#v}"'"/;}' "$dir/nix/hosts/darwin.nix"
    git -C "$dir" add "$ttf" "$map" "$dir/nix/hosts/darwin.nix"
    echo "Updated ($tag). Apply with: just rebuild (automatic when run via upgrade)"


# ─────────────────────────────────────────────
# 確認 (inspect / 差分・型チェック・診断)
# ─────────────────────────────────────────────

# 型チェック / 差分表示  (`just check` = 構文型チェック, `just check diff` = 差分ビルド)
[group('確認')]
check what="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{what}}" in
      "")   nix flake check --no-build {{flake}} ;;  # 構文/型チェック (ビルドしない)
      diff) nh darwin build ;;                       # current vs. flake の差分
      *)    echo "usage: just check [diff]" >&2; exit 2 ;;
    esac

# パッケージ検索  (`just search <q>` = brew+nixpkgs, `just search <q> all` = + cargo)
# all は nix/brew に無い ecosystem 限定ツールの発見用。既定はノイズ少なめ。
[group('確認')]
[doc('パッケージ検索 (`just search <q>` = brew+nixpkgs, `just search <q> all` = + cargo)')]
search query scope="":
    #!/usr/bin/env bash
    set -u
    if [ -z "{{query}}" ]; then echo "usage: just search <name> [all]" >&2; exit 2; fi
    case "{{scope}}" in ""|all) ;; *) echo "usage: just search <name> [all]" >&2; exit 2 ;; esac
    echo "━━━ Homebrew (formula + cask) ━━━"
    brew search {{query}} 2>&1 || true
    echo ""
    echo "━━━ nixpkgs (local eval) ━━━"
    # nh search は search.nixos.org API 依存で不安定なため nix search を使用
    # (eval キャッシュが効くので 2 回目以降は数秒。警告は抑制)
    nix search nixpkgs {{query}} 2>/dev/null || echo "  (none)"
    # all のときだけ ecosystem 限定 (cargo) も横断
    if [ "{{scope}}" = "all" ]; then
      echo ""
      echo "━━━ crates.io (cargo) ━━━"
      cargo search {{query}} 2>&1 | head -10 || echo "  (none)"
    fi

# 更新可能なものを一覧 (upgrade 前のプレビュー。brew + mas + flake inputs。非破壊)
[group('確認')]
outdated:
    #!/usr/bin/env bash
    set -u
    echo "━━━ Homebrew (formula + cask, --greedy) ━━━"
    o=$(brew outdated --greedy 2>/dev/null); [ -n "$o" ] && echo "$o" || echo "  (up to date)"
    echo ""
    echo "━━━ Mac App Store ━━━"
    o=$(mas outdated 2>/dev/null); [ -n "$o" ] && echo "$o" || echo "  (up to date)"
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

# 環境ヘルスチェック (Determinate upgrade 後などに走らせる)
[group('確認')]
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
        --argjson aerospace "$(pgrep -fq AeroSpace.app && echo true || echo false)" \
        --argjson karabiner "$(pgrep -fq Karabiner-Core-Service && echo true || echo false)" \
        --argjson ageKey "$([[ -f $HOME/.config/sops/age/keys.txt ]] && echo true || echo false)" \
        --argjson clean "$([[ -z $(git -C {{justfile_directory()}} status --short) ]] && echo true || echo false)" \
        --argjson brew "$brew_json" \
        '{ok: ($nixMounted and $fstabOk and $nixDecrypted and $sketchybar and $aerospace and $karabiner and $ageKey and $brew.ok), checks: {nixMounted: $nixMounted, fstab: $fstabOk, nixDecrypted: $nixDecrypted, sketchybar: $sketchybar, aerospace: $aerospace, karabiner: $karabiner, ageKey: $ageKey, workingTreeClean: $clean}, brew: $brew}')
      printf '%s\n' "$result"
      jq -e '.ok' <<<"$result" >/dev/null
      exit $?
    fi
    if [[ -n "{{format}}" ]]; then echo "usage: just doctor [--json|json]" >&2; exit 2; fi
    pass=0; fail=0
    check() { if eval "$2"; then echo "  [ok] $1"; pass=$((pass+1)); else echo "  [FAIL] $1"; fail=$((fail+1)); fi; }
    # warn: 満たさなくても fail にしない情報系チェック ($3 = 未達時メッセージ)
    warn() { if eval "$2"; then echo "  [ok] $1"; else echo "  [warn] $3"; fi; }
    echo "== /nix mount =="
    check "/nix is mounted" 'mount | grep -q " on /nix "'
    check "/etc/fstab has no noauto (Login Items fix)" '! grep "/nix" /etc/fstab | grep -q noauto'
    check "/nix decrypted (FileVault: No)" '! diskutil apfs list 2>/dev/null | grep -A 6 "Nix Store" | grep -q "FileVault: *Yes"'
    echo "== Login Items =="
    check "AeroSpace registered" 'osascript -e "tell application \"System Events\" to get name of login items" | grep -q AeroSpace'
    check "Ghostty registered" 'osascript -e "tell application \"System Events\" to get name of login items" | grep -q Ghostty'
    echo "== Key apps running =="
    check "sketchybar" 'pgrep -fq "/opt/homebrew/opt/sketchybar/bin/sketchybar"'
    check "AeroSpace" 'pgrep -fq AeroSpace.app'
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
    # バー/WM 系が落ちていれば復旧導線を出す (restart レシピへ)
    down=()
    pgrep -fq "/opt/homebrew/opt/sketchybar/bin/sketchybar" || down+=(sketchybar)
    pgrep -fq AeroSpace.app || down+=(aerospace)
    pgrep -xq borders || down+=(borders)
    if [ ${#down[@]} -gt 0 ]; then
      echo "[warn] Down: ${down[*]} -> recover: just restart (individual: just restart <name>)"
      echo
    fi
    echo "Result: $pass passed, $fail failed"
    exit $fail

# NOTE: nix fmt (treefmt 一括) は flake が nix/ にあり tree-root の flake.nix 検出に失敗するため
#       使えない (flake.nix の treefmt コメント参照)。per-file フックを束ねた pre-commit 経由で走らせる。
# コード整形 + lint を全追跡ファイルに実行 (OS 自動判別: Mac/Linux=pre-commit, Win=PSScriptAnalyzer)
[group('確認')]
fmt:
    @just _fmt-{{os()}}

[private]
_fmt-macos: _fmt-unix

[private]
_fmt-linux: _fmt-unix

[private]
_fmt-unix:
    nix develop {{flake}} --command pre-commit run --all-files

# 実体は win-fmt (コマンドの単一ソース)
[private]
_fmt-windows:
    @just win-fmt


# ─────────────────────────────────────────────
# 掃除 (clean / GC・ゴミファイル)
# ─────────────────────────────────────────────

# 全レイヤー一括 GC (再生成可能なcacheのみ。Trashやホーム全体の削除は gc-deep)
[group('掃除')]
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
    # machine 停止中は接続エラーになるので黙ってスキップ
    if command -v podman >/dev/null && podman info >/dev/null 2>&1; then
      podman system prune -f 2>&1 | tail -2 || true
    else
      echo "  (podman not available / machine stopped, skip)"
    fi
    echo ""
    echo "━━━ Electron updater leftovers (~/Library/Caches/*.ShipIt) ━━━"
    # Squirrel.framework が残すダウンロード済みアップデートの残骸。次回アップデート時に再取得される
    sz=$(du -shc ~/Library/Caches/*.ShipIt 2>/dev/null | tail -1 | cut -f1)
    echo "  total: ${sz:-0}"
    rm -rf ~/Library/Caches/*.ShipIt/* 2>/dev/null || true
    echo ""
    echo "━━━ Repo junk files (.DS_Store / AppleDouble / vim swap etc.) ━━━"
    dir="{{justfile_directory()}}"
    # macOS / editor / OS が撒くゴミの名前パターン (.git は除外)
    names=(
      ".DS_Store" ".AppleDouble" ".LSOverride" "._*"
      ".Spotlight-V100" ".Trashes" ".fseventsd" ".DocumentRevisions-V100"
      ".TemporaryItems" ".apdisk" ".localized"
      "Thumbs.db" "Thumbs.db:encryptable" "ehthumbs.db" "ehthumbs_vista.db" "desktop.ini"
      "*.swp" "*.swo" "*~" "*.bak" "*.orig"
    )
    fexpr=()
    for n in "${names[@]}"; do fexpr+=( -name "$n" -o ); done
    unset 'fexpr[${#fexpr[@]}-1]'  # 末尾の -o を除去
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

# 重い再生成可能データを対話削除 (廃止caskのzap / CoreSimulator cache / podman / 古いbuild成果物)
[group('掃除')]
gc-deep:
    #!/usr/bin/env bash
    set -u
    echo "━━━ macOS Trash (復旧不能になるため確認付き) ━━━"
    sz=$(du -sh "$HOME/.Trash" 2>/dev/null | cut -f1); echo "  size: ${sz:-0}"
    read -rp "  Empty Trash? [y/N] " ans
    if [[ "$ans" == [yY] ]]; then
      find "$HOME/.Trash" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
      echo "  emptied"
    else
      echo "  skipped"
    fi
    echo ""
    echo "━━━ OS/editor junk across HOME (確認付き) ━━━"
    read -rp "  Delete .DS_Store/AppleDouble/swap/orig/rej/backup files? [y/N] " ans
    if [[ "$ans" == [yY] ]]; then
      d=$(find "$HOME" \( -path "$HOME/.Trash" -o -path "$HOME/Library" \) -prune -o -type f \( -name '.DS_Store' -o -name '._*' -o -name '*.swp' -o -name '*.swo' -o -name '*.orig' -o -name '*.rej' -o -name '*~' \) -print -delete 2>/dev/null | wc -l | tr -d ' ')
      echo "  $d removed"
    else
      echo "  skipped"
    fi
    echo ""
    echo "━━━ Retired GUI cask data (Homebrew zap) ━━━"
    # CLI/TUIへ移行して宣言から外したcaskだけを固定指定。--force により通常uninstall後も
    # zap stanza (設定・cache等)を実行できる。ollama-appは ~/.ollama のモデルを消すため、
    # unity-hubはUnity CLIと設定を共有しうるため、意図的に対象外。
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
    # iOS シミュレータ実行時に再生成されるキャッシュ。放置すると 10GB 超えになる
    sim_cache="/Library/Developer/CoreSimulator/Caches"
    if [ -d "$sim_cache" ]; then
      sz=$(du -sh "$sim_cache" 2>/dev/null | cut -f1)
      echo "  size: ${sz:-?} (使用時に再生成される)"
      read -rp "  Delete? (要 sudo) [y/N] " ans
      if [[ "$ans" == [yY] ]]; then
        sudo rm -rf "$sim_cache" && echo "  removed ($sz)"
      else
        echo "  skipped"
      fi
    else
      echo "  (not found)"
    fi
    echo ""
    echo "━━━ podman full prune (未使用イメージ全削除, 次回使用時に要再 pull) ━━━"
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
    echo "━━━ Scanning node_modules / rust target untouched >30 days ━━━"
    tmp=$(mktemp)
    # ~/Library は tool 内部 (typescript/pnpm 等のキャッシュ) なので除外。プロジェクトのみ対象。
    prune=( \( -path "$HOME/Library" -o -path "$HOME/.cache" -o -name .Trash \) -prune )
    # node_modules: ネストは prune で1階層のみ。30日触っていないもの限定
    find "$HOME" "${prune[@]}" -o -type d -name node_modules -prune -mtime +30 -print 2>/dev/null >> "$tmp"
    # rust target: 同名の汎用ディレクトリ誤爆を避け、隣に Cargo.toml がある場合のみ
    find "$HOME" "${prune[@]}" -o -type d -name target -prune -mtime +30 -print 2>/dev/null | \
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
# サービス (restart / メニューバー・WM 系の再起動)
# ─────────────────────────────────────────────

# NOTE: aerospace はフル再起動 = ワークスペース配置がリセットされるので明示指定 (aerospace/all) 時のみ。
#       borders の設定は ~/.config/borders/bordersrc に集約済 (nix/home/darwin.nix の home.file が単一ソース)
#       なので引数なし `borders` で起動すれば bordersrc が読まれる。
# メニューバー/WM 系を再起動 (`just restart`=バー周り / 個別: sketchybar|borders|aerospace / all=全部)
[group('サービス')]
restart what="bar":
    #!/usr/bin/env bash
    set -u
    uid=$(id -u)

    sb() { echo "-> sketchybar";  launchctl kickstart -k "gui/$uid/homebrew.mxcl.sketchybar"; }
    bd() { echo "-> borders";     pkill -x borders 2>/dev/null; sleep 0.3; (borders >/dev/null 2>&1 &); }
    as() {
      echo "-> AeroSpace (full restart -> revives borders/sketchybar triggers)"
      osascript -e 'quit app "AeroSpace"' 2>/dev/null
      # quit 完了を最大 4s ポーリングで待つ (sleep 固定だと終了が遅いと open が空振りする)
      for _ in $(seq 1 20); do pgrep -fq AeroSpace.app || break; sleep 0.2; done
      open -a AeroSpace
    }

    case "{{what}}" in
      bar)            sb; bd ;;
      sketchybar|sb)  sb ;;
      borders|bd)     bd ;;
      aerospace|as)   as ;;
      all)            sb; bd; as ;;
      *) echo "usage: just restart [bar|sketchybar|borders|aerospace|all]" >&2; exit 2 ;;
    esac
    echo "Done"


# ─────────────────────────────────────────────
# secrets (sops 暗号化)
# ─────────────────────────────────────────────

# sops 暗号化 secrets  (`just secrets` = 編集, `just secrets rekey` = 全 recipient 再暗号化)
[group('secrets')]
secrets cmd="edit":
    #!/usr/bin/env bash
    set -euo pipefail
    f="{{justfile_directory()}}/secrets/secrets.yaml"
    case "{{cmd}}" in
      edit)  sops "$f" ;;                # 編集 (デフォルト)
      rekey) sops updatekeys "$f" ;;     # .sops.yaml 変更後に走らせる
      *)     echo "usage: just secrets [edit|rekey]" >&2; exit 2 ;;
    esac


# ─────────────────────────────────────────────
# セットアップ / その他
# ─────────────────────────────────────────────

# 入室時の shellHook で pre-commit を .git/hooks に導入 (.pre-commit-config.yaml 生成 + install)。
# install は新 Mac 初回に一度だけ走らせれば良い (旧 pre-commit-install を統合)。
# devShell (`just dev`=入室[shellcheck/statix 使用可] / `just dev install`=hook導入のみ[非対話])
[group('セットアップ')]
dev what="":
    #!/usr/bin/env bash
    set -eu
    case "{{what}}" in
      "")      exec nix develop {{flake}} ;;            # 対話シェルに入る
      install) nix develop {{flake}} --command true ;;  # 入室=hook導入のみで即終了
      *)       echo "usage: just dev [install]" >&2; exit 2 ;;
    esac

# remote-env を別ホストで使う
[group('セットアップ')]
ssh host:
    nssh {{host}}

# README のコマンド一覧は手書きだと Justfile と乖離するので `just --list` を単一ソースとし、
# README / CHEATSHEET の <!-- BEGIN/END <name> --> ブロックを設定 (SSOT) から再生成。
# 対象: just レシピ一覧・pre-commit フック表・shell alias 表 (scripts/gen-docs.py 参照)。
# レシピ/フック/alias を変えたらこれを実行。CI の乖離検知は check-generated.sh が担う。
[group('セットアップ')]
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    python3 scripts/gen-docs.py

# Obsidian 設定を public dotfiles へ片方向スナップショット (追跡専用・vault→dotfiles)
# ・ホワイトリストの安全な json のみコピー。本体は vault 側 (ここは読み取り用ミラー)。
# ・plugins/*/data.json (LiveSync の CouchDB 認証・各種 API キー等)・workspace・キャッシュは
#   原理的に含めない。万一の非空な秘密値を検出したら中止し public へ出さない。
# ・commit 前に `gitleaks` を必ず通すこと。秘密ごと残したい設定は sops 暗号化 (`just secrets`)。
[group('セットアップ')]
[doc('Obsidian 設定を public dotfiles へ片方向スナップショット (追跡専用・vault→dotfiles)')]
obsidian-snapshot:
    #!/usr/bin/env bash
    set -euo pipefail
    src="$HOME/Documents/notes/.obsidian"
    dst="{{justfile_directory()}}/configs/apps/obsidian"
    [ -d "$src" ] || { echo "vault not found: $src" >&2; exit 1; }
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

    # ★ホワイトリスト: 安全と確認した設定のみ (危険な物を除くのではなく安全な物だけ入れる)
    for f in app.json appearance.json hotkeys.json \
             community-plugins.json core-plugins.json \
             graph.json daily-notes.json types.json canvas.json; do
      [ -f "$src/$f" ] && cp -f "$src/$f" "$tmp/$f"
    done

    # ★秘密ガード: 非空の秘密値 ("key": "value") を検出したら公開リポジトリへ出さず中止
    if grep -rEil '"(api[_-]?key|secret|token|password|passphrase|access[_-]?key|couchdb_[a-z]+)"[[:space:]]*:[[:space:]]*"[^"]+"' "$tmp"; then
      echo "🛑 秘密らしき値を検出。スナップショット中止 (public 保護)" >&2; exit 1
    fi

    mkdir -p "$dst"
    rsync -a --delete --exclude='README.md' "$tmp/" "$dst/"
    echo "✅ snapshot -> $dst"
    echo "   git add 後、commit 前に gitleaks を通してください。"


# ─────────────────────────────────────────────
# Windows (native pwsh)
# ─────────────────────────────────────────────

# Windows ネイティブの bootstrap を実行 (`just win-bootstrap` / `just win-bootstrap -DryRun`)
[group('Windows')]
win-bootstrap *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/bootstrap.ps1 {{flags}}

# winget/apps.json の全 PackageIdentifier 実在検証 (`just win-verify` / `just win-verify -Strict`)
[group('Windows')]
win-verify *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/winget/verify.ps1 {{flags}}

# apps.json (宣言) と winget list (実 install) の差分。MISSING があれば exit 1
[group('Windows')]
win-status *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/winget/status.ps1 {{flags}}

# winget 経由で入れた全 app をアップグレード (--silent --accept-*)
[group('Windows')]
win-upgrade:
    pwsh.exe -NoProfile -Command "winget upgrade --all --silent --accept-package-agreements --accept-source-agreements"

# テレメトリ/標準機能の declarative 適用 (Win11Debloat + WinUtil)
# `*flags` で `-DryRun` `-SkipWinUtil` `-SkipWin11Debloat` を渡せる
[group('Windows')]
win-privacy *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/privacy/apply.ps1 {{flags}}

# Scoop で bucket + app を declarative に適用 (MS Store 専用 app の sideload 用)
# `*flags` で `-DryRun` `-SkipBuckets` `-SkipApps` を渡せる
[group('Windows')]
win-scoop *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/scoop/apply.ps1 {{flags}}

# ロケール / 言語を declarative に適用 (en-US UI / UTF-8 / SKK のみ / US Region)
# `*flags` で `-DryRun` `-SkipLanguageList` `-SkipSystemLocale` `-SkipHomeLocation` を渡せる
[group('Windows')]
win-locale *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/locale/apply.ps1 {{flags}}

# configs/fonts/ の .ttf / .otf を user-scope install (HKCU 登録、管理者不要)
# `*flags` で `-DryRun` `-Force` (既存も上書き) を渡せる
[group('Windows')]
win-fonts *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/fonts/apply.ps1 {{flags}}

# テーマ (palette) を palettes.json から各 config に render
# `*flags` で `-DryRun` `-ActivePalette rose-pine-dawn` 等を渡せる
[group('Windows')]
win-theme *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/theme/apply.ps1 {{flags}}


# ─────────────────────────────────────────────
# テーマ (OS 横断、palettes.json を SSO とした統一切替)
# ─────────────────────────────────────────────

# 全環境を palettes.json の現 active で render (引数で active 切替も可)
#   `just theme`                   = 現在 active で全環境を再 apply
#   `just theme rose-pine-dawn`    = light に切替えて全環境を render + rebuild
# NOTE: shebang レシピは Windows の just が cygpath を要求して動かないため、
#       OS 横断のこのレシピは即ディスパッチし、bash 処理は _theme-unix に置く。
[group('テーマ')]
[doc('全環境を palettes.json の現 active で render (`just theme rose-pine-dawn` で active 切替も可)')]
theme name="":
    @just _theme-{{os()}} "{{name}}"

[private]
_theme-macos name="": (_theme-unix name)

[private]
_theme-linux name="": (_theme-unix name)

# Mac/WSL とも nh home switch で nvim/zellij/sketchybar/bat/atuin 等が全部追従
[private]
_theme-unix name="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{name}}" ]; then
      # palettes.json の active field を書き換え
      sed -i.bak 's/"active": *"[^"]*"/"active": "{{name}}"/' configs/theme/palettes.json
      rm -f configs/theme/palettes.json.bak
      echo "→ palettes.json active = {{name}}"
    fi
    nh home switch

# active の書き戻しは apply.ps1 ではなくここで行う (unix 側の sed と対に。BOM 無し UTF-8)。
# render 実体は win-theme (zebar / glazewm / WT / wezterm を一括 render)
[private]
_theme-windows name="":
    @if ('{{name}}' -ne '') { $p = Resolve-Path 'configs/theme/palettes.json'; $c = (Get-Content $p -Raw -Encoding UTF8) -replace '"active":\s*"[^"]*"', '"active": "{{name}}"'; [System.IO.File]::WriteAllText($p, $c, [System.Text.UTF8Encoding]::new($false)); Write-Host ('-> palettes.json active = {{name}}') }
    @just win-theme

# キーマップ適用 (SharpKeys = Scancode Map 直書き + AHK スクリプト reload)
# `*flags` で `-DryRun` `-Clear` (Scancode Map 削除して standard に戻す) を渡せる
[group('Windows')]
win-keymap *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/sharpkeys/apply.ps1 {{flags}}
    pwsh.exe -NoProfile -Command "Get-Process AutoHotkey* -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Process 'windows/autohotkey/keymap.ahk' -ErrorAction SilentlyContinue"

# GlazeWM のログイン時自動起動を Task Scheduler に登録 (1 回 password 入力)
# `*flags` で `-Unregister` (タスク削除) を渡せる
[group('Windows')]
win-autostart-glazewm *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/tasks/setup-glazewm-autostart.ps1 {{flags}}

# Windows 関連 .ps1 を PSScriptAnalyzer で lint (Warning 以上で exit 1)
[group('Windows')]
win-fmt:
    pwsh.exe -NoProfile -Command "if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Install-Module PSScriptAnalyzer -Force -Scope CurrentUser }; Invoke-ScriptAnalyzer -Path windows -Recurse -Severity Warning -EnableExit -Settings windows/PSScriptAnalyzerSettings.psd1"

# ─────────────────────────────────────────────
# バックアップ / アーカイブ (restic 1 リポジトリ: google-drive:restic-backup・暗号化)
#   warm = 無タグ・日次自動 (restic-backup.nix) / cold = --tag archive・手動・永久保持。
#   重複排除・整合性検証・鍵を共有。共有用 ~/Cloud/GoogleDrive マウント操作もここに集約。
# ─────────────────────────────────────────────

# restic 環境 (warm/cold 共通)。$HOME は実行時に bash が展開する
restic_env := 'export RESTIC_REPOSITORY="rclone:google-drive:restic-backup" RESTIC_PASSWORD_FILE="$HOME/.config/restic/password" RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"'

# ── warm: 現役ファイル (日次自動。以下は手動操作) ──

# warm バックアップを今すぐ実行 (launchd を kickstart) → ログ追尾 (Ctrl-C で追尾終了・backupは継続)
[group('バックアップ')]
backup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ restic warm backup を起動 (launchd kickstart)..."
    launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.restic-backup"
    echo "起動済。ログ追尾 (Ctrl-C で終了・バックアップは継続):"
    exec tail -f "$HOME/Library/Logs/restic-backup.log"

# 全スナップショット一覧 (Tags 列で warm / archive を区別)
[group('バックアップ')]
backup-ls:
    @{{restic_env}}; restic snapshots

# リポジトリ整合性検証 (restic check)
[group('バックアップ')]
backup-check:
    @{{restic_env}}; restic check

# ── cold: アーカイブ (使わなくなったファイルを退避・永久保持) ──

# 使わなくなったファイル/フォルダを restic へ退避しローカルを解放 (--tag archive・永久保持)。
# 例: `just archive ~/Downloads/old-project`
[group('バックアップ')]
archive path:
    #!/usr/bin/env bash
    set -euo pipefail
    {{restic_env}}
    src="{{path}}"
    [ -e "$src" ] || { echo "存在しない: $src" >&2; exit 1; }
    src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"   # 絶対パス化
    sz="$(du -sh "$src" 2>/dev/null | cut -f1)"
    echo "アーカイブ対象: $src ($sz)"
    read -rp "restic へ退避後ローカルを削除します。続行? (y/N) " a
    [[ "$a" == [yY] ]] || { echo "中止"; exit 0; }
    if restic backup --tag archive "$src"; then
      echo "✓ 退避完了 (--tag archive・永久保持)。ローカルを削除します。"
      rm -rf "$src"
      echo "✓ ローカル削除: $src"
      echo "  一覧: just archive-ls  /  復元: just restore <snapshotID>"
    else
      echo "✗ restic backup 失敗。ローカルは削除していません。" >&2
      exit 1
    fi

# アーカイブ (--tag archive) の snapshot 一覧 (ID / 日付 / 元パス)
[group('バックアップ')]
archive-ls:
    @{{restic_env}}; restic snapshots --tag archive

# アーカイブの総容量・ファイル数
[group('バックアップ')]
archive-stats:
    @{{restic_env}}; restic stats --tag archive

# アーカイブ内をファイル名で検索 (restic find・FUSE不要)。どの snapshot に在るか分かる。
# 例: `just archive-find "*.psd"` / `just archive-find old-project`
[group('バックアップ')]
archive-find pattern:
    @{{restic_env}}; restic find --tag archive "{{pattern}}"

# ── 共通: 復元 / 共有マウント ──

# snapshot から復元 (warm/cold 共通)。既定は元の絶対パスへ。`unarchive` も同義。
# 例: `just restore a81c9de1`            元の場所へ
#     `just restore a81c9de1 ~/Restore`  指定先へ (構造を保って展開)
[group('バックアップ')]
restore snapshot dest="/":
    #!/usr/bin/env bash
    set -euo pipefail
    {{restic_env}}
    restic restore "{{snapshot}}" --target "{{dest}}"
    echo "✓ 復元: snapshot {{snapshot}} → {{dest}}"

alias unarchive := restore

# 共有用 ~/Cloud/GoogleDrive マウント操作。`just gdrive`=状態 / `remount`=再マウント / `open`=Finderで開く
[group('バックアップ')]
gdrive cmd="status":
    #!/usr/bin/env bash
    set -euo pipefail
    mp="$HOME/Cloud/GoogleDrive"
    case "{{cmd}}" in
      status)  mount | grep -q " $mp " && echo "✓ マウント中: $mp" || echo "✗ 未マウント: $mp" ;;
      remount) launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.rclone-gdrive" && echo "→ 再マウント要求 (数秒後 just gdrive で確認)" ;;
      open)    open "$mp" ;;
      *)       echo "usage: just gdrive [status|remount|open]" >&2; exit 2 ;;
    esac
