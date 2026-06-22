# dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

macOS 環境を Nix flake で declarative に管理(nix-darwin + home-manager + sops-nix)。

📖 **日常コマンドは [docs/CHEATSHEET.md](docs/CHEATSHEET.md) を参照**

---

## Fork して使う場合

```bash
# 1. Fork ボタン → 自分の repo 名で clone
git clone git@github.com:<yourname>/dotfiles.git ~/dotfiles
cd ~/dotfiles

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

# 4. yuki の secrets は復号できないので削除して空から始める
rm secrets/secrets.yaml
# 必要な secret を追加していく(例)
sops secrets/secrets.yaml
# (sops が新しいエディタ画面を開く → 自分の secret を YAML で記述 → 保存)

# 5. 個人 brew tap を整理(任意)
$EDITOR nix/darwin.nix
# - "gapul/openutau", "gapul/zrythm" は yuki 個人の fork → 削除可
# - 不要な GUI cask も削っていい(brave-browser, gimp, blender 等)

# 6. bootstrap 実行
bash scripts/bootstrap.sh
```

クローン後にエディタで `user.nix`, `.sops.yaml`, `darwin.nix` を編集すれば、他は触らずに動く設計。


## 構成

```
nix/                 # 3ファイルだけ
├── flake.nix        # entry point
├── darwin.nix       # macOS (system, fonts, homebrew)
└── home.nix         # user (zsh, git, programs, configs/symlinks)
configs/             # 各アプリの実 config (ghostty/zellij/aerospace/sketchybar/nvim/karabiner/yazi/...)
secrets/secrets.yaml # SOPS で age 暗号化
.sops.yaml           # 受信者 (age pubkey)
scripts/bootstrap.sh # 新 Mac 用 0 → 1 セットアップ
templates/           # direnv 用 dev shell テンプレ (node/python/rust)
Justfile             # 普段使うコマンド集
```

## 起動

新しい Mac:
```bash
curl -fsSL https://raw.githubusercontent.com/gapul/dotfiles/main/scripts/bootstrap.sh | bash
```

## コマンド一覧

### 🟢 設定 / ビルド (Justfile)

| コマンド | 説明 |
|---|---|
| `just` | レシピ一覧 |
| `just rebuild` | システム + ユーザー両方再構築(普段使い) |
| `just update` | flake input 更新 → rebuild(Nix管理ぶんだけ最新化) |
| `just upgrade` | brew/cask/mas/Nix 全レイヤー最新化(--greedy で cask 全部更新) |
| `just check` | 構文/型チェック(ビルドはしない) |
| `just diff` | 現在のシステムと flake の差分 |
| `just gc` | 古い世代削除 + nix store gc(`--keep 5 --keep-since 7d`) |

### 🟦 機密 (SOPS)

| コマンド | 説明 |
|---|---|
| `just secrets-edit` | sops で `secrets/secrets.yaml` を透過的に編集 |
| `just secrets-rekey` | `.sops.yaml` を変更後の再暗号化 |

### 🟪 検索

| コマンド | 説明 |
|---|---|
| `nh search <name>` | nixpkgs から package 検索(例: `nh search firefox`) |

### 🟫 リモート

| コマンド | 説明 |
|---|---|
| `nssh user@host` | rootless Nix(`nix-portable`)で nvim/yazi/zellij(自分の設定) |
| `just ssh <host>` | `nssh` のショート |

### 🟥 pre-commit

| コマンド | 説明 |
|---|---|
| `just pre-commit-install` | gitleaks hook を `.git/hooks/pre-commit` に |

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
