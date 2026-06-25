# dotfiles 操作集
# `just` で一覧、`just <task>` で実行
# https://just.systems

set shell := ["bash", "-cu"]

flake := justfile_directory() + "/nix"

# デフォルト: タスク一覧 (定義順で表示)
default:
    @just --list --unsorted


# ─────────────────────────────────────────────
# 構築 (build / 普段使い)
# ─────────────────────────────────────────────

# システム + ユーザー 両方再構築 (普段使い)
[group('構築')]
rebuild:
    # 新 brew は HOMEBREW_REQUIRE_TAP_TRUST 既定ON + brew bundle が cask trust を毎回消すため、
    # custom tap の cask を darwin switch 前に毎回再 trust する (formula は Brewfile宣言で auto-trust)。
    -brew list --cask --full-name 2>/dev/null | grep '/' | HOMEBREW_USER_CONFIG_HOME="$HOME/.homebrew" xargs -I% brew trust --cask %
    nh darwin switch
    nh home switch

# システム世代の一覧/差分  (`just gen` = 一覧, `just gen diff [a] [b]` = 世代間パッケージ差分。sudo 不要)
[group('構築')]
gen action="" a="" b="":
    #!/usr/bin/env bash
    set -euo pipefail
    p=/nix/var/nix/profiles
    cur=$(readlink $p/system | sed -E 's/system-([0-9]+)-link/\1/')
    case "{{action}}" in
      "")  # 一覧 (現在世代に ← 印)
        for l in $p/system-*-link; do
          n=$(echo "$l" | sed -E 's#.*/system-([0-9]+)-link#\1#')
          d=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$l")
          mark=""; [ "$n" = "$cur" ] && mark="  ← current"
          printf '%4s  %s%s\n' "$n" "$d" "$mark"
        done | sort -n
        ;;
      diff)  # 世代間のパッケージ差分 (デフォルト: 直前 → 現在)
        a="{{a}}"; b="{{b}}"; a="${a:-$((cur-1))}"; b="${b:-$cur}"
        echo "世代 $a → $b のパッケージ差分:"
        nix store diff-closures "$p/system-$a-link" "$p/system-$b-link"
        ;;
      *) echo "usage: just gen [diff [a] [b]]" >&2; exit 2 ;;
    esac

# 世代をロールバック (引数なし=直前へ, `just rollback 8` で世代番号指定。sudo)
[group('構築')]
rollback gen="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{gen}}" ]; then
      echo "→ 世代 {{gen}} へ切替"
      sudo darwin-rebuild --switch-generation {{gen}}
    else
      echo "→ 直前の世代へロールバック"
      sudo darwin-rebuild --rollback
    fi

# flake input 更新 → rebuild  (引数なし=全 input, `just update nixpkgs` で個別更新)
[group('構築')]
update *inputs:
    nix flake update {{inputs}} --flake {{flake}}
    just rebuild

# 全レイヤーアップグレード (Nix + brew + cask + mas + Determinate Nix runtime)
# --greedy で自前 auto-update する cask (VS Code 等) も brew 経由で揃える
[group('構築')]
upgrade:
    brew upgrade --formula
    # cask は --greedy で自己更新型も揃える。installer manual / 自己更新 cask
    # (figma-agent 等) は brew が上げられず exit 1 にするので許容する。
    brew upgrade --cask --greedy || true
    mas upgrade
    just sketchybar-font
    just update
    @echo "Determinate Nix 本体は手動で: sudo /usr/local/bin/determinate-nixd upgrade"

# sketchybar-app-font を最新リリースへ更新 (.ttf と icon_map.sh を同一版で揃える)
# upgrade から自動で呼ばれる内部レシピ (`just sketchybar-font` 単体実行も可)
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
      echo "sketchybar-app-font: 既に最新 ($tag)。skip"
      exit 0
    fi
    echo "sketchybar-app-font: $cur → $tag へ更新"
    # .ttf と icon_map.sh を同一リリースから取得 (版ズレ防止)
    gh release download "$tag" --repo "$repo" --pattern sketchybar-app-font.ttf --output "$ttf"  --clobber
    gh release download "$tag" --repo "$repo" --pattern icon_map.sh           --output "$map"  --clobber
    # 呼び出し規約を従来式に統一 + ローカル補正(icon_map_local.sh)を source する末尾を再注入
    # (front_app.sh / space_windows.sh が単一引数で呼ぶ。OBS Studio 等の実名ズレ補正を維持)
    awk '/^### END-OF-ICON-MAP/{print; print "__icon_map \"$1\""; print "[ -r \"${BASH_SOURCE%/*}/icon_map_local.sh\" ] && source \"${BASH_SOURCE%/*}/icon_map_local.sh\""; print "echo \"$icon_result\""; exit} {print}' "$map" > "$map.tmp" && mv "$map.tmp" "$map"
    # darwin.nix の version を追従 (pname 行の直後だけを置換。他の version= は触らない)
    sed -i "" -E '/pname = "sketchybar-app-font"/{n;s/version = "[0-9.]+"/version = "'"${tag#v}"'"/;}' "$dir/nix/hosts/darwin.nix"
    # flake が見えるよう git に追跡させる (commit は手動)
    git -C "$dir" add "$ttf" "$map" "$dir/nix/hosts/darwin.nix"
    echo "✅ 更新完了 ($tag)。反映は just rebuild (upgrade 経由なら自動)"


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

# パッケージ検索  (`just search <q>` = brew+nixpkgs, `just search <q> all` = + cargo + npm)
# all は nix/brew に無い ecosystem 限定ツール (slidev 等) の発見用。既定はノイズ少なめ。
[group('確認')]
search query scope="":
    #!/usr/bin/env bash
    set -u
    if [ -z "{{query}}" ]; then echo "usage: just search <名前> [all]" >&2; exit 2; fi
    case "{{scope}}" in ""|all) ;; *) echo "usage: just search <名前> [all]" >&2; exit 2 ;; esac
    echo "━━━ Homebrew (formula + cask) ━━━"
    brew search {{query}} 2>&1 || true
    echo ""
    echo "━━━ nixpkgs (ローカル評価) ━━━"
    # nh search は search.nixos.org API 依存で不安定なため nix search を使用
    # (eval キャッシュが効くので 2 回目以降は数秒。警告は抑制)
    nix search nixpkgs {{query}} 2>/dev/null || echo "  (該当なし)"
    # all のときだけ ecosystem 限定 (cargo / npm) も横断
    if [ "{{scope}}" = "all" ]; then
      echo ""
      echo "━━━ crates.io (cargo) ━━━"
      cargo search {{query}} 2>&1 | head -10 || echo "  (該当なし)"
      echo ""
      echo "━━━ npm registry ━━━"
      npm search {{query}} 2>&1 | head -10 || echo "  (該当なし)"
    fi

# 更新可能なものを一覧 (upgrade 前のプレビュー。brew + mas + flake inputs。非破壊)
[group('確認')]
outdated:
    #!/usr/bin/env bash
    set -u
    echo "━━━ Homebrew (formula + cask, --greedy) ━━━"
    o=$(brew outdated --greedy 2>/dev/null); [ -n "$o" ] && echo "$o" || echo "  (最新)"
    echo ""
    echo "━━━ Mac App Store ━━━"
    o=$(mas outdated 2>/dev/null); [ -n "$o" ] && echo "$o" || echo "  (最新)"
    echo ""
    echo "━━━ flake inputs (lock の最終更新日) ━━━"
    if command -v jq >/dev/null; then
      nix flake metadata {{flake}} --json 2>/dev/null \
        | jq -r '.locks.nodes | to_entries[] | select(.value.locked.lastModified) | "\(.key)\t\(.value.locked.lastModified)"' \
        | while IFS=$'\t' read -r name ts; do printf '  %-22s %s\n' "$name" "$(date -r "$ts" '+%Y-%m-%d')"; done \
        | sort -k2
    else
      echo "  (jq 未 install、skip)"
    fi
    echo ""
    echo "→ 更新: just upgrade (全部) / just update <input> (個別)"

# 環境ヘルスチェック (Determinate upgrade 後などに走らせる)
[group('確認')]
doctor:
    #!/usr/bin/env bash
    set -u
    pass=0; fail=0
    check() { if eval "$2"; then echo "  ✅ $1"; pass=$((pass+1)); else echo "  ❌ $1"; fail=$((fail+1)); fi; }
    echo "== /nix マウント =="
    check "/nix がマウントされてる" 'mount | grep -q " on /nix "'
    check "/etc/fstab に noauto が無い (Login Items 対策)" '! grep "/nix" /etc/fstab | grep -q noauto'
    check "/nix が復号化済 (FileVault: No)" '! diskutil apfs list 2>/dev/null | grep -A 6 "Nix Store" | grep -q "FileVault: *Yes"'
    echo "== Login Items =="
    check "AeroSpace 登録済" 'osascript -e "tell application \"System Events\" to get name of login items" | grep -q AeroSpace'
    check "Ghostty 登録済" 'osascript -e "tell application \"System Events\" to get name of login items" | grep -q Ghostty'
    echo "== 主要アプリ実行中 =="
    check "sketchybar" 'pgrep -fq "/opt/homebrew/opt/sketchybar/bin/sketchybar"'
    check "AeroSpace" 'pgrep -fq AeroSpace.app'
    check "Karabiner Core-Service" 'pgrep -fq Karabiner-Core-Service'
    echo "== dotfiles =="
    check "未 commit 変更なし" '[[ -z "$(git -C {{justfile_directory()}} status --short)" ]]'
    check "age 秘密鍵存在" '[[ -f ~/.config/sops/age/keys.txt ]]'
    echo
    echo "Result: $pass passed, $fail failed"
    exit $fail


# ─────────────────────────────────────────────
# 掃除 (clean / GC・ゴミファイル)
# ─────────────────────────────────────────────

# 全レイヤー一括 GC (nix store + brew + pnpm + uv + npm + ~/.Trash 等)
[group('掃除')]
gc:
    #!/usr/bin/env bash
    set -u
    echo "━━━ Nix store (古い世代削除) ━━━"
    nh clean all --keep 5 --keep-since 7d || true
    echo ""
    echo "━━━ Homebrew (downloads + 古い version) ━━━"
    brew cleanup --prune=all 2>&1 | tail -3 || true
    echo ""
    echo "━━━ pnpm store ━━━"
    command -v pnpm >/dev/null && pnpm store prune 2>&1 | tail -2 || true
    echo ""
    echo "━━━ uv cache ━━━"
    command -v uv >/dev/null && uv cache prune 2>&1 | tail -2 || true
    echo ""
    echo "━━━ npm cache ━━━"
    command -v npm >/dev/null && npm cache verify 2>&1 | tail -2 || true
    echo ""
    echo "━━━ cargo (大物 build artifacts のみ、registry 維持) ━━━"
    command -v cargo-cache >/dev/null && cargo cache --autoclean 2>&1 | tail -2 || echo "  (cargo-cache 未 install、skip)"
    echo ""
    echo "━━━ macOS ゴミ箱 ━━━"
    sz=$(du -sh ~/.Trash 2>/dev/null | cut -f1); echo "  ~/.Trash size: $sz"
    rm -rf ~/.Trash/* 2>/dev/null || true
    echo ""
    echo "━━━ リポジトリ内ゴミファイル (.DS_Store / AppleDouble / vim swap 等) ━━━"
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
    echo "  🗑️  $n 件削除"
    echo ""
    echo "━━━ ~/.cache 内 (uv は完了済、他大物の状況) ━━━"
    du -sh ~/.cache/*/ 2>/dev/null | sort -hr | head -5
    echo ""
    echo "━━━ 完了 ━━━"
    df -h / 2>&1 | head -2 | tail -1


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

# remote-env を別ホストで使う
[group('セットアップ')]
ssh host:
    nssh {{host}}

# git pre-commit hook をインストール (新Macで一度だけ。内部レシピ)
[private]
pre-commit-install:
    pre-commit install
