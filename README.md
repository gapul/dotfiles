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
```

## 起動

新しい Mac:
```bash
curl -fsSL https://raw.githubusercontent.com/gapul/dotfiles/main/scripts/bootstrap.sh | bash
```

更新:
```bash
cd ~/dotfiles && git pull
sudo darwin-rebuild switch --flake ~/dotfiles/nix#yuki    # システム
home-manager switch --flake ~/dotfiles/nix#yuki -b backup  # ユーザー
```

## ポイント

- **Nix runtime**: Determinate Nix(`nix.enable = false` で共存)
- **nix-darwin と home-manager は分離**: [#1462](https://github.com/nix-darwin/nix-darwin/issues/1462) (USER check bug)回避のため
- **configs 編集 → `git add` 忘れずに**: Nix flake は git-tracked しか見ない
- **動的設定 (nvim/karabiner) は `mkOutOfStoreSymlink`**: GUI/CLI の書き戻しが dotfiles に反映
- **secrets は SOPS-nix で復号**: `~/.config/sops/age/keys.txt` が必要。Bitwarden に backup 推奨
- **direnv**: `templates/<stack>/` をプロジェクトにコピーして `direnv allow` で言語別 dev shell

## リモート

```bash
nssh user@host    # rootless Nix + 自分の dotfiles で nvim/yazi/zellij
```

## 復旧

macOS update 後 `/nix` が見えなくなったら:
```bash
sudo /usr/local/bin/determinate-nixd init
```
