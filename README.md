# dotfiles

yuki の macOS 環境を宣言的に管理する Nix flake。

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

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `/nix` が見えない / shell でエラー | `sudo determinate-nixd init` |
| `nh: more values required` | 新ターミナル開き直す(`__HM_SESS_VARS_SOURCED` の継承で env が古い) |
| `git push` できない | dotfiles の remote が SSH 化済 → `~/.ssh/config` 確認 |
| pre-commit hook で commit blocked | leak は redact 表示、嘘陽性なら `.gitleaks.toml` の allowlist 追記 |
| `darwin-rebuild switch` で USER エラー | nix-darwin#1462 の bug。`just rebuild`(nh)で回避 |
