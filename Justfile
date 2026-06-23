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
    brew upgrade
    brew upgrade --cask --greedy
    mas upgrade
    just update
    @echo "Determinate Nix 本体は手動で: sudo /usr/local/bin/determinate-nixd upgrade"

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
