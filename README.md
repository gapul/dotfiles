# dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

macOS 環境を Nix flake で declarative に管理(nix-darwin + home-manager + sops-nix)。

📖 **日常コマンドは [docs/CHEATSHEET.md](docs/CHEATSHEET.md) を参照**

---

## Fork して使う場合

```bash
# 1. Fork ボタン → 自分の repo 名で clone
git clone git@github.com:<yourname>/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 2. nix/user.nix を編集(これだけで全 nix モジュールに反映)
$EDITOR nix/user.nix
# {
#   username     = "<your-macos-username>";
#   gitUser      = "<your-github-username>";
#   gitEmail     = "<your-email>";
#   dotfilesRepo = "https://github.com/<yourname>/dotfiles.git";
# }

# 3. age 鍵を生成して .sops.yaml の public key を差し替え
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# 出力された "# public key: age1..." の行を .sops.yaml の age1... に貼り換え
$EDITOR .sops.yaml

# 4. 元の所有者の secrets は復号できないので削除して空から始める
rm secrets/secrets.yaml
# 必要な secret を追加していく(例)
sops secrets/secrets.yaml
# (sops が新しいエディタ画面を開く → 自分の secret を YAML で記述 → 保存)

# 5. 個人 brew tap を整理(任意)
$EDITOR nix/hosts/darwin.nix
# - "gapul/openutau", "gapul/zrythm" は 作者個人の fork → 削除可
# - 不要な GUI cask も削っていい(gimp, blender 等)

# 6. bootstrap 実行
bash scripts/bootstrap.sh
```

クローン後にエディタで `nix/user.nix`, `.sops.yaml`, `nix/hosts/darwin.nix` を編集すれば、他は触らずに動く設計。


## 構成

```
nix/
├── flake.nix        # entry point (darwin/nixos/home-manager 各構成 + devShell)
├── user.nix         # ユーザー名・メール等 (最初に書き換える)
├── hosts/           # マシン別: darwin.nix (メイン Mac) / macmini.nix / nixos-laptop.nix
├── home/            # home-manager: common.nix + OS 別 (darwin/linux/wsl/hyprland) + backup 系
├── lib/             # テーマ (palettes.json を SSO とする rose-pine dark/light)
└── pkgs/            # 自前パッケージ
configs/             # 各アプリの実 config (ghostty/tmux/sketchybar/nvim/karabiner/yazi/...)
secrets/secrets.yaml # SOPS で age 暗号化
.sops.yaml           # 受信者 (age pubkey)
scripts/bootstrap.sh # 新 Mac 用 0 → 1 セットアップ (Linux/WSL 版もあり)
windows/             # Windows 側セットアップ (winget/scoop/AutoHotkey/...)
mobile/              # iOS / Android (アプリ宣言・adb 設定・構成プロファイル)
esphome/             # ESP チップに載るデバイス設定 (水やり機)
tailscale/           # tailnet のポリシー (ACL / split DNS)  ※fetch して作る
nextdns/             # NextDNS のプロファイル設定           ※fetch して作る
templates/           # direnv 用 dev shell テンプレ (node/python/rust)
Justfile             # 普段使うコマンド集
```

## 起動

新しい Mac:
```bash
curl -fsSL https://raw.githubusercontent.com/gapul/dotfiles/main/scripts/bootstrap.sh | bash
```

## コマンド一覧

### 🟢 Justfile レシピ

以下は `just --list` から自動生成(レシピを変えたら `just docs` で再生成)。

<!-- BEGIN just-list -->
```text
    default

    [Backup]
    archive path                 # Example: `just archive ~/Downloads/old-project`
    archive-find pattern         # Example: `just archive-find "*.psd"` / `just archive-find old-project`
    archive-ls                   # List archive (--tag archive) snapshots (ID / date / original path)
    archive-stats                # Total size and file count of the archive
    backup                       # Run the warm backup now (kickstart launchd) -> follow the log (Ctrl-C ends following; backup continues)
    backup-check                 # Verify repository integrity (restic check)
    backup-ls                    # List all snapshots (distinguish warm / archive by the Tags column)
    gdrive cmd="status"          # ~/Library/LaunchAgents/com.gapul.rclone.* plists are retired), so remount is just a kickstart.
    restore snapshot dest="/"    # `just restore a81c9de1 ~/Restore`  to the specified target (expanded preserving structure) [alias: unarchive]

    [Build]
    build-all *args              # Build every flake package available on this architecture
    check-all *args              # Build every flake check available on this architecture
    gen action="" a="" b=""      # List or compare system generations.
    maintain                     # Update, upgrade, rebuild, and garbage-collect
    rebuild force=""             # Rebuild the system and user configuration. `just rebuild force` activates even when nothing changed
    recovery-iso                 # Build the non-destructive NixOS recovery ISO (Linux builder required)
    rollback gen=""              # Roll back to the previous or selected system generation.
    update *inputs               # Update flake inputs, then rebuild.
    upgrade                      # Upgrade all package layers.

    [Clean]
    gc                           # GC all layers at once (only regenerable caches; Trash and whole-home deletion are in gc-deep)
    gc-deep                      # Interactively delete heavy regenerable data (Trash / ~/tmp scratch / zap of retired casks / CoreSimulator cache / podman / old build artifacts)

    [Homelab]
    dns *flags                   # Diff the repo's declarations against Cloudflare DNS: A records, tunnel CNAMEs, and mail (MX/SPF/DKIM)
    esphome                      # Validate the ESPHome device configs without hardware
    nextdns cmd="diff"           # Fetch, diff, or apply the NextDNS profile. Needs NEXTDNS_API_KEY / NEXTDNS_PROFILE
    tailnet cmd="diff"           # Fetch, diff, or apply the tailnet policy file (ACL / split DNS). Needs TS_API_KEY

    [Inspect]
    check what=""                # Type-check / show diff  (`just check` = syntax/type-check, `just check diff` = diff build)
    doctor format=""             # Environment health check (run after e.g. a Determinate upgrade)
    fmt                          # Format code + lint across all tracked files (OS auto-detected: Mac/Linux=pre-commit, Win=PSScriptAnalyzer)
    outdated                     # List what can be updated (preview before upgrade; brew + mas + flake inputs; non-destructive)
    search query scope=""        # Package search (`just search <q>` = brew+nixpkgs, `just search <q> all` = + cargo)

    [Mobile]
    android-apps cmd="status"    # Diff apps.tsv against the device, or converge it (`just android-apps` / `install` / `verify` / `obtainium`)
    android-launcher-theme       # Generate the Kvaesitso launcher theme from palettes.json and push it to the device
    android-os *flags            # Apply the declared Android OS settings over adb (`just android-os` = diff + apply, `just android-os --dry-run`)
    ios-apps cmd="status"        # Diff ios/apps.tsv against a USB-connected iPhone (`just ios-apps` / `just ios-apps verify`)
    ios-profiles port="8000"     # Build the declared .mobileconfig profiles and serve them on the LAN for an iPhone to install
    ios-shortcuts cmd="status"   # Export iCloud-synced Shortcuts into the repo, or compile .cherri sources into signed shortcuts
    mobile-test                  # Self-check both platforms' scripts with stubbed adb / ideviceinstaller (no device needed)

    [Service]
    restart what="bar"           # Restart the menu-bar/WM stack (`just restart`=bar-related / individual: sketchybar|borders|omniwm / all=everything)

    [Setup]
    claude-settings-adopt        # Adopt this machine's Claude Code settings into the remote-managed keys (client wins)
    dev what=""                  # devShell (`just dev`=enter [shellcheck/statix available] / `just dev install`=install hooks only [non-interactive])
    docs                         # Run this after changing a recipe/hook/alias. CI drift detection is handled by check-generated.sh.
    obsidian-snapshot            # One-way snapshot of Obsidian config into public dotfiles (tracking-only, vault->dotfiles)
    plist-sync                   # Sync GUI app preference changes back into dotfiles (live -> repo)
    ssh host                     # Use remote-env on another host

    [Theme]
    theme name=""                # Render all environments with the current active in palettes.json (`just theme rose-pine-dawn` also switches active)

    [Windows]
    win-autostart-glazewm *flags # Pass `-Unregister` (delete the task) via `*flags`
    win-bootstrap *flags         # Run the native Windows bootstrap (`just win-bootstrap` / `just win-bootstrap -DryRun`)
    win-fmt                      # Lint Windows-related .ps1 with PSScriptAnalyzer (exit 1 on Warning or above)
    win-fonts *flags             # Pass `-DryRun` `-Force` (overwrite existing too) via `*flags`
    win-keymap *flags            # Pass `-DryRun` `-Clear` (delete Scancode Map and return to standard) via `*flags`
    win-locale *flags            # Pass `-DryRun` `-SkipLanguageList` `-SkipSystemLocale` `-SkipHomeLocation` via `*flags`
    win-privacy *flags           # Pass `-DryRun` `-SkipWinUtil` `-SkipWin11Debloat` via `*flags`
    win-scoop *flags             # Pass `-DryRun` `-SkipBuckets` `-SkipApps` via `*flags`
    win-status *flags            # Diff between apps.json (declaration) and winget list (actual install). exit 1 if any MISSING
    win-theme *flags             # Pass `-DryRun` `-ActivePalette rose-pine-dawn` etc. via `*flags`
    win-upgrade                  # Upgrade every app installed via winget (--silent --accept-*)
    win-verify *flags            # Verify every PackageIdentifier in winget/apps.json exists (`just win-verify` / `just win-verify -Strict`)

    [secrets]
    secrets cmd="edit"           # sops-encrypted secrets  (`just secrets` = edit, `just secrets rekey` = re-encrypt for all recipients)
```
<!-- END just-list -->

### 🟪 検索

| コマンド | 説明 |
|---|---|
| `nh search <name>` | nixpkgs から package 検索(例: `nh search firefox`) |

### 🟫 リモート

| コマンド | 説明 |
|---|---|
| `nssh user@host` | rootless Nix(`nix-portable`)で nvim/yazi/tmux(自分の設定)を使う |
| `just ssh <host>` | `nssh` のショート |

### 🟥 コード品質 (git-hooks.nix + treefmt)

pre-commit フック・フォーマッタは `nix/flake.nix` で **宣言的に管理**(git-hooks.nix / treefmt-nix)。

| コマンド | 説明 |
|---|---|
| `nix fmt` | nix(nixfmt) + shell(shfmt) を整形。`nix/` 配下で実行 |
| `nix develop ./nix` | devShell 入室。`.pre-commit-config.yaml` を生成し `.git/hooks` に導入 |
| `nix flake check ./nix` | `checks.pre-commit` で nix/ を検査(CI と同じ) |
| `nix develop ./nix -c pre-commit run --all-files` | リポ全体にフックを実行 |
| `nix develop ./nix -c shellcheck scripts/*.sh` | シェルの手動チェック(任意) |
| `nix run nixpkgs#statix -- check nix` | nix lint(手動。enforced 外) |

**commit 時に自動実行されるフック**(`.git/hooks/pre-commit`):

以下は `nix/flake.nix` の `preCommit.hooks` から自動生成(フックを変えたら `just docs` で再生成)。

<!-- BEGIN hooks -->
| フック | 対象 | 除外 | 内容 |
|---|---|---|---|
| `deadnix` | `*.nix` | — | 未使用コード検出 (モジュール引数 `{ lib, ... }` は許容) |
| `gitleaks` | 全 staged | — | 機密 leak 検出 |
| `nixfmt` | `*.nix` | — | 整形チェック (未整形なら fail) |
| `shellcheck` | 全 staged | `configs/wm/sketchybar/.*`、`\.envrc$`、`configs/macmini/bin/.*`、`configs/macmini/client/.*`、`configs/macmini/setup-scripts/.*` | shell lint (.shellcheckrc に従う) |
<!-- END hooks -->

メモ:
- フックを編集するには `nix/flake.nix` の `preCommit.hooks` を変更 → `nix develop` で再生成
- `.pre-commit-config.yaml` は **生成物**(store パス依存)。`.gitignore` 済・非追跡。fork 後は `nix develop ./nix` で生成
- **flake は `nix/` サブディレクトリ**にあるため、`treefmt` フックは git ルートから root 検出に失敗する。整形フックは per-file の `nixfmt-rfc-style` を使い、`treefmt` は `nix fmt` 専用
- `shellcheck` は enforced 済。除外中の sketchybar 設定群は `nix develop ./nix -c shellcheck configs/wm/sketchybar/...` で手動チェック可
- CI は `om ci`(omnix)で回す。`checks.pre-commit` 出力(git-hooks.nix)をビルドすることでリポ全体に同じフックが走る。設定は `om.yaml` + flake 出力が単一の真実で、`.github/workflows/ci.yml` は system→runner を割り当てて `om ci run` を呼ぶだけの薄いアダプタ

### 🟨 復旧 / メンテ (生コマンド)

| コマンド | 説明 |
|---|---|
| `just doctor` | 環境ヘルスチェック(/nix マウント・Login Items・fstab 状態) |
| `sudo /usr/local/bin/determinate-nixd init` | macOS update 後 `/nix` が見えない時 |
| `sudo /usr/local/bin/determinate-nixd upgrade` | Determinate Nix runtime 本体を更新(数ヶ月に1回) |
| `nh darwin switch` | システムだけ rebuild(`just rebuild` の半分) |
| `nh home switch` | ユーザーだけ rebuild |
| `nh clean all` | 古い世代を一括削除 |

## ポイント

- **Nix runtime**: Determinate Nix(`nix.enable = false` で共存)
- **nix-darwin と home-manager は分離**: [#1462](https://github.com/nix-darwin/nix-darwin/issues/1462) (USER check bug)回避のため
- **configs 編集 → `git add` 忘れずに**: Nix flake は git-tracked しか見ない
- **動的設定 (nvim/karabiner) は `mkOutOfStoreSymlink`**: GUI/CLI の書き戻しが dotfiles に反映
- **secrets は SOPS-nix で復号**: `~/.config/sops/age/keys.txt` が必要。Bitwarden に backup 推奨
- **direnv**: `templates/<stack>/` をプロジェクトにコピーして `direnv allow` で言語別 dev shell

## 設計判断: `/nix` を復号化 + `fstab` から `noauto` 削除

Determinate Nix のデフォルト構成は:
1. `/nix` ボリュームを FileVault 暗号化
2. `/etc/fstab` に `noauto` を付与
3. launchd デーモン `org.nixos.darwin-store` で遅延マウント

この設計は **launchd daemon ベースの起動**(`nix-darwin` の PR #1052 で `wait4path` 自動付与)を前提にしているが、**Login Items / GUI 自動復元 / restoring Terminal は wait4path 範囲外**。Ghostty・AeroSpace・sketchybar を Login Items で常駐させてる構成では、boot 直後に /nix がまだマウントされず config 読み込み失敗する。

[deep-research](https://github.com/LnL7/nix-darwin/issues/774) によると、これはコミュニティで何年も解決してない有名な問題。 `lilyball` は login shell を C wrapper で包んでる、`astratagem` は「Nix で yabai 入れるのやめた」と発言してる。

**対処** (現状の構成):
- `/nix` ボリュームを `diskutil apfs decryptVolume "Nix Store"` で復号化
- `/etc/fstab` から `noauto` を削除 → macOS の `automountd` が起動序盤にマウント
- Login Items が起動するときには /nix は既にマウント済 → config 読める

**トレードオフ**:
- ✅ Login Items 問題が完全解決
- ✅ `wait4path` 経路で漏れる GUI / 復元 Terminal も解決
- ⚠️ Determinate 公式サポート外設定(upgrade で fstab 書き戻される可能性 → bootstrap.sh で自動修正)
- ⚠️ ボリューム暗号化が外れる
  - 実害は無い(/nix の中身は nixpkgs 公開バイナリ、Mac 本体は FileVault でカバー済)

**自動修復**: `bootstrap.sh` が新規 install 時に自動で復号化 + `noauto` 削除する。`just doctor` で日常チェック可能。Determinate upgrade 後はとくに `just doctor` 推奨。

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| 再起動後に sketchybar / Ghostty / launcher が config 読まない | `just doctor` で /nix マウント状態確認、`fstab` に `noauto` 戻ってたら `sudo sed -i '' 's/,noauto//' /etc/fstab` |
| `/nix` が見えない / shell でエラー | `sudo determinate-nixd init` または `sudo diskutil mount "Nix Store"` |
| `nh: more values required` | 新ターミナル開き直す(`__HM_SESS_VARS_SOURCED` の継承で env が古い) |
| `git push` できない | dotfiles の remote が SSH 化済 → `~/.ssh/config` 確認 |
| pre-commit hook で commit blocked | leak は redact 表示、嘘陽性なら `.gitleaks.toml` の allowlist 追記 |
| `darwin-rebuild switch` で USER エラー | nix-darwin#1462 の bug。`just rebuild`(nh)で回避 |
| Ghostty config の一部設定が無視される(`quick-terminal-position` 等が default のまま) | Ghostty 1.3.1 は invalid な行(例: `quick-terminal-screen = mouse`、`global:f18=...`)で**parse 中断**。+show-config で適用状態確認、config の上から 1 行ずつ消して原因特定 |
