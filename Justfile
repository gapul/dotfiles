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

# NOTE(rebuild の brew trust 行): activation の brew bundle は sudo で XDG_CONFIG_HOME を剥がし
#   ~/.homebrew/trust.json を読むが、対話シェルは XDG 優先で ~/.config/homebrew に逸れる。
#   そこで env -u XDG_CONFIG_HOME で ~/.homebrew に揃える。cask は新 brew が Brewfile の
#   trusted:true を無視するため毎回再 trust が必要。詳細: memory project_homebrew_trust_sudo

# システム + ユーザー 両方再構築 (普段使い)
[group('構築')]
rebuild:
    @-brew list --cask --full-name 2>/dev/null | grep '/' | xargs -I% env -u XDG_CONFIG_HOME brew trust --cask % >/dev/null
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
          mark=""; [ "$n" = "$cur" ] && mark="  <- current"
          printf '%4s  %s%s\n' "$n" "$d" "$mark"
        done | sort -n
        ;;
      diff)  # 世代間のパッケージ差分 (デフォルト: 直前 → 現在)
        a="{{a}}"; b="{{b}}"; a="${a:-$((cur-1))}"; b="${b:-$cur}"
        echo "Package diff: generation $a -> $b"
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
      echo "-> Switching to generation {{gen}}"
      sudo darwin-rebuild --switch-generation {{gen}}
    else
      echo "-> Rolling back to previous generation"
      sudo darwin-rebuild --rollback
    fi

# flake input 更新 → rebuild  (引数なし=全 input, `just update nixpkgs` で個別更新)
[group('構築')]
update *inputs:
    nix flake update {{inputs}} --flake {{flake}}
    just rebuild

# NOTE(upgrade): cask --greedy は自己更新型(VS Code 等)も brew 経由で揃える。installer manual /
#   自己更新 cask(figma-agent 等)は brew が上げられず exit 1 にするので `|| true` で許容する。

# 全レイヤーアップグレード (Nix + brew + cask + mas + Determinate Nix runtime)
[group('構築')]
upgrade:
    brew upgrade --formula
    brew upgrade --cask --greedy || true
    mas upgrade
    just sketchybar-font
    just update
    @echo "Determinate Nix runtime: upgrade manually -> sudo /usr/local/bin/determinate-nixd upgrade"

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
      exit 0 # 既に最新。何も出力しない (upgrade のノイズ削減)
    fi
    echo "sketchybar-app-font: updating $cur -> $tag"
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

# パッケージ検索  (`just search <q>` = brew+nixpkgs, `just search <q> all` = + cargo + npm)
# all は nix/brew に無い ecosystem 限定ツール (slidev 等) の発見用。既定はノイズ少なめ。
[group('確認')]
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
    # all のときだけ ecosystem 限定 (cargo / npm) も横断
    if [ "{{scope}}" = "all" ]; then
      echo ""
      echo "━━━ crates.io (cargo) ━━━"
      cargo search {{query}} 2>&1 | head -10 || echo "  (none)"
      echo ""
      echo "━━━ npm registry ━━━"
      npm search {{query}} 2>&1 | head -10 || echo "  (none)"
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
doctor:
    #!/usr/bin/env bash
    set -u
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
# コード整形 + lint を全追跡ファイルに実行 (pre-commit: nixfmt + shfmt + shellcheck 等)
[group('確認')]
fmt:
    nix develop {{flake}} --command pre-commit run --all-files


# ─────────────────────────────────────────────
# 掃除 (clean / GC・ゴミファイル)
# ─────────────────────────────────────────────

# 全レイヤー一括 GC (nix store + brew + pnpm + uv + npm + ~/.Trash 等)
[group('掃除')]
gc:
    #!/usr/bin/env bash
    set -u
    echo "━━━ Nix store (remove old generations) ━━━"
    nh clean all --keep 5 --keep-since 7d || true
    echo ""
    echo "━━━ Homebrew (downloads + old versions) ━━━"
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
    echo "━━━ cargo (large build artifacts only, keep registry) ━━━"
    command -v cargo-cache >/dev/null && cargo cache --autoclean 2>&1 | tail -2 || echo "  (cargo-cache not installed, skip)"
    echo ""
    echo "━━━ macOS Trash ━━━"
    sz=$(du -sh ~/.Trash 2>/dev/null | cut -f1); echo "  ~/.Trash size: $sz"
    rm -rf ~/.Trash/* 2>/dev/null || true
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
    echo "━━━ OS junk across $HOME (.DS_Store/._*/swap/orig etc., excl .Trash) ━━━"
    d=$(find "$HOME" -name .Trash -prune -o -type f \( -name '.DS_Store' -o -name '._*' -o -name '*.swp' -o -name '*.swo' -o -name '*.orig' -o -name '*.rej' -o -name '*~' \) -print -delete 2>/dev/null | wc -l | tr -d ' ')
    echo "  $d removed"
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

# 重い再生成可能ディレクトリを削除 (30日以上更新の無い node_modules / rust target のみ。要再 install)
[group('掃除')]
gc-deep:
    #!/usr/bin/env bash
    set -u
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
#       borders の設定は ~/.config/borders/bordersrc に集約済 (configs/wm/borders/bordersrc が単一ソース)
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

# キーマップ適用 (SharpKeys = Scancode Map 直書き + AHK スクリプト reload)
# `*flags` で `-DryRun` `-Clear` (Scancode Map 削除して standard に戻す) を渡せる
[group('Windows')]
win-keymap *flags:
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File windows/sharpkeys/apply.ps1 {{flags}}
    pwsh.exe -NoProfile -Command "Get-Process AutoHotkey* -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Process 'windows/autohotkey/keymap.ahk' -ErrorAction SilentlyContinue"

# Windows 関連 .ps1 を PSScriptAnalyzer で lint (Warning 以上で exit 1)
[group('Windows')]
win-fmt:
    pwsh.exe -NoProfile -Command "if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Install-Module PSScriptAnalyzer -Force -Scope CurrentUser }; Invoke-ScriptAnalyzer -Path windows -Recurse -Severity Warning -EnableExit -Settings windows/PSScriptAnalyzerSettings.psd1"
