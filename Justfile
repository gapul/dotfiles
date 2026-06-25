# dotfiles 操作集
# `just` で一覧、`just <task>` で実行
# https://just.systems

set shell := ["bash", "-cu"]

flake := justfile_directory() + "/nix"

# デフォルト: タスク一覧
default:
    @just --list

# システム + ユーザー 両方再構築 (普段使い)
rebuild:
    nh darwin switch
    nh home switch

# flake input 更新 → rebuild (Nix管理ぶんだけ)
update:
    nix flake update --flake {{flake}}
    just rebuild

# 全レイヤーアップグレード (Nix + brew + cask + mas + Determinate Nix runtime)
# --greedy で自前 auto-update する cask (VS Code 等) も brew 経由で揃える
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
# upgrade から自動で呼ばれる。単体で走らせて just rebuild してもよい。
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

# 構文/型チェック (ビルドはしない)
check:
    nix flake check --no-build {{flake}}

# 暗号化 secrets を sops で編集
secrets-edit:
    sops {{justfile_directory()}}/secrets/secrets.yaml

# secrets を全 recipient で再暗号化 (.sops.yaml 変更後に走らせる)
secrets-rekey:
    sops updatekeys {{justfile_directory()}}/secrets/secrets.yaml

# git pre-commit hook をインストール (新Macで一度だけ)
pre-commit-install:
    pre-commit install

# 全レイヤー一括 GC (nix store + brew + pnpm + uv + npm + ~/.Trash 等)
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
    echo "━━━ ~/.cache 内 (uv は完了済、他大物の状況) ━━━"
    du -sh ~/.cache/*/ 2>/dev/null | sort -hr | head -5
    echo ""
    echo "━━━ 完了 ━━━"
    df -h / 2>&1 | head -2 | tail -1

# ゴミファイル一括削除 (.DS_Store / AppleDouble / vim swap / Thumbs.db 等)
# dotfiles 配下を再帰削除。.git は除外。dry-run は `just clean-junk dry`
clean-junk dry="":
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{justfile_directory()}}"
    # 削除対象パターン (macOS / editor / OS が撒くゴミ)
    names=(
      ".DS_Store" ".AppleDouble" ".LSOverride" "._*"
      ".Spotlight-V100" ".Trashes" ".fseventsd" ".DocumentRevisions-V100"
      ".TemporaryItems" ".apdisk" ".localized"
      "Thumbs.db" "Thumbs.db:encryptable" "ehthumbs.db" "ehthumbs_vista.db" "desktop.ini"
      "*.swp" "*.swo" "*~" "*.bak" "*.orig"
    )
    # find 用の -name OR 条件を組み立て
    expr=()
    for n in "${names[@]}"; do expr+=( -name "$n" -o ); done
    unset 'expr[${#expr[@]}-1]'  # 末尾の -o を除去
    mapfile -d '' hits < <(find "$dir" -path "$dir/.git" -prune -o -type f \( "${expr[@]}" \) -print0)
    if [ "${#hits[@]}" -eq 0 ]; then
      echo "✨ ゴミファイルなし"
      exit 0
    fi
    printf '%s\n' "${hits[@]}" | sed "s|^$dir/||"
    echo "── 計 ${#hits[@]} 件"
    if [ "{{dry}}" = "dry" ]; then
      echo "(dry-run: 削除はしていません。実削除は引数なしで)"
      exit 0
    fi
    printf '%s\0' "${hits[@]}" | xargs -0 rm -f
    echo "🗑️  ${#hits[@]} 件削除しました"

# このマシンの差分 (current vs. flake) を表示
diff:
    nh darwin build

# 環境ヘルスチェック (Determinate upgrade 後などに走らせる)
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

# remote-env を別ホストで使う
ssh host:
    nssh {{host}}
