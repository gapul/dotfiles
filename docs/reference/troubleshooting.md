# トラブルシューティングガイド

dotfilesシステムの一般的な問題と解決方法です。

## 🚨 緊急対応

### システム起動不能
```bash
# 1. 前回の設定にロールバック
sudo nix-env --rollback --profile /nix/var/nix/profiles/system

# 2. ブートローダーから安全モードで起動
# macOS: 起動時にShift長押し
# Linux: GRUB メニューから recovery mode

# 3. 最小構成で再ビルド
nix build .#darwinConfigurations.minimal.system
sudo ./result/sw/bin/darwin-rebuild switch --flake .#minimal
```

### 完全復旧手順
```bash
# 1. Nixストア修復
sudo nix-store --verify --check-contents --repair

# 2. 設定ファイル検証
nix flake check --impure

# 3. 段階的復旧
just rebuild minimal
just rebuild standard  # 成功後
just rebuild full      # 最終段階
```

## 🔧 インストール・設定問題

### Nixインストール失敗

#### 権限エラー
```bash
# 問題: Permission denied for /nix
sudo mkdir -p /nix
sudo chown $(whoami) /nix

# 再インストール実行
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

#### macOS Gatekeeper制限
```bash
# 問題: Untrusted developer warning
sudo spctl --master-disable  # 一時的無効化
# インストール後、再有効化
sudo spctl --master-enable
```

#### Linux SELinux制限
```bash
# 問題: SELinux policy violation
sudo setenforce 0          # 一時的無効化
# または 
sudo setsebool -P nix_daemon 1
```

### flake設定エラー

#### `selector 'darwinConfigurations' does not exist`
```bash
# 原因: flake.nixの場所間違い
pwd  # プロジェクトルートにいることを確認
ls -la flake.nix  # flake.nixが存在することを確認

# 解決: 正しいディレクトリに移動
cd ~/.config/dotfiles
nix run nix-darwin -- switch --flake .#default
```

#### `option defined multiple times`
```bash
# 原因: home-manager設定重複
# 調査コマンド
nix eval .#homeConfigurations.$USER.config.programs --json | jq 'keys'

# 解決: 重複するモジュールを削除
# flake.nixから重複するimportを削除
```

#### `cannot evaluate attribute 'system'`
```bash
# 原因: プラットフォーム検出失敗
nix eval .#platformInfo --json

# 解決: プラットフォーム情報を手動指定
nix run nix-darwin -- switch --flake .#default --system aarch64-darwin
```

## 🏗️ ビルド・実行問題

### パッケージビルド失敗

#### 依存関係不足
```bash
# 問題: Package X not found
nix search nixpkgs package-name

# 解決: nixpkgsバージョン確認・更新
nix flake update
nix flake lock --update-input nixpkgs
```

#### ビルド時間超過
```bash
# 問題: Build timeout
# 解決: 並列ビルド調整
export NIX_BUILD_CORES=1    # リソース制約環境
export NIX_BUILD_CORES=8    # 高性能環境

# または設定ファイルで調整
echo "max-jobs = 1" >> ~/.config/nix/nix.conf
```

#### ディスク容量不足
```bash
# 問題: No space left on device  
# 調査
df -h /nix
du -sh /nix/store | head -20

# 解決: ガベージコレクション
nix-collect-garbage -d
nix store gc --max 10GB
sudo nix-collect-garbage -d  # システム全体
```

### 実行時エラー

#### `command not found`
```bash
# 問題: インストールしたパッケージが見つからない
# 調査
echo $PATH
nix profile list

# 解決: 環境再読み込み
source ~/.zshrc  # または ~/.bashrc
# または新しいシェルセッション開始
```

#### `library not found`
```bash
# 問題: Dynamic library missing
# 調査 (macOS)
otool -L /path/to/binary

# 調査 (Linux)  
ldd /path/to/binary

# 解決: FHS環境で実行
nix-shell -p steam-run --run 'your-command'
```

## 🔒 セキュリティ・権限問題

### SOPS復号化失敗

#### Age key not found
```bash
# 問題: No age key found
# 確認
ls -la ~/.config/sops/age/keys.txt

# 解決: 年齢キー作成・配置  
age-keygen -o ~/.config/sops/age/keys.txt
# 公開キーを.sops.yamlに追加
```

#### 権限エラー
```bash
# 問題: Permission denied
# 調査
ls -la secrets/

# 解決: 適切な権限設定
chmod 600 secrets/*.yaml
chown $(whoami):$(whoami) secrets/
```

### SSH・GPG問題

#### SSH agent not running
```bash
# 問題: SSH key not loaded
# 確認
ssh-add -l

# 解決: agent起動・キー追加
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
```

#### GPG signing failure
```bash
# 問題: Git commit signing failed
# 確認
gpg --list-secret-keys

# 解決: GPG agent設定
export GPG_TTY=$(tty)
echo "use-agent" >> ~/.gnupg/gpg.conf
```

## 🌐 プラットフォーム固有問題

### macOS固有

#### SIP (System Integrity Protection)
```bash
# 問題: Operation not permitted
# 調査
csrutil status

# 対処: SIPを無効化せず、適切な権限で実行
sudo nix-daemon
# または権限のある場所にインストール
```

#### Homebrew競合
```bash
# 問題: Conflicting package versions
# 調査
brew list | grep -E "(git|curl|python)"

# 解決: Nix環境を優先
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
# ~/.zshrcに追加
```

### Linux固有

#### systemd サービス失敗
```bash
# 問題: Service failed to start
# 調査
systemctl status service-name
journalctl -u service-name

# 解決: 手動起動・設定確認
systemctl --user daemon-reload
systemctl --user start service-name
```

#### AppArmor/SELinux制限
```bash
# 問題: Access denied by security policy
# 調査 (AppArmor)
sudo aa-status

# 調査 (SELinux)
getenforce
ausearch -m avc

# 解決: プロファイル調整（慎重に）
sudo aa-complain /path/to/profile
```

### WSL固有

#### Windows PATH混入
```bash
# 問題: Windows executables in PATH
# 調査
echo $PATH | tr ':' '\n' | grep -i windows

# 解決: PATH クリーンアップ
export PATH="/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
```

#### ファイルシステム権限
```bash
# 問題: Cannot set permissions
# 解決: WSL設定調整
echo -e "[automount]\nenabled = true\noptions = \"metadata,umask=22,fmask=11\"" | sudo tee -a /etc/wsl.conf
# WSL再起動が必要
```

### Android固有

#### Termux制限
```bash
# 問題: Cannot access /data/data/
# 解決: Termux API使用
pkg install termux-api

# または権限のあるディレクトリ使用
export HOME=/data/data/com.termux/files/home
```

#### リソース不足
```bash
# 問題: Out of memory
# 調査
free -m
df -h

# 解決: 軽量設定使用
export DOTFILES_PROFILE=minimal
```

## 🔧 デバッグツール・コマンド

### Nix関連
```bash
# 設定検証
nix flake check --impure
nix eval .#platformInfo --json

# ビルド詳細表示
nix build --show-trace --verbose

# 依存関係調査
nix why-depends /nix/store/... /nix/store/...
nix-tree

# キャッシュ状態
nix path-info --all --closure-size
```

### システム状態
```bash
# プロセス確認
ps aux | grep -E "(nix-daemon|home-manager)"

# ファイルシステム
lsof +D /nix
netstat -tulpn | grep nix

# ログ確認  
journalctl -f -u nix-daemon
tail -f ~/.local/state/home-manager/logs/
```

### パフォーマンス
```bash
# リソース使用量
htop
iotop
iftop

# Nixビルド統計
nix-build --dry-run 2>&1 | grep "built:"
```

## 📞 サポート・コミュニティ

### 公式リソース
- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [NixOS Wiki](https://nixos.wiki/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)

### コミュニティ
- [NixOS Discourse](https://discourse.nixos.org/)
- [r/NixOS](https://reddit.com/r/NixOS)
- [Matrix Chat](https://matrix.to/#/#nixos:nixos.org)

### バグレポート
```bash
# 環境情報収集
nix-shell -p nix-info --run "nix-info -m"
just health-check > system-info.txt

# GitHub Issue作成時に添付
```

---

*最終更新: 2025年7月2日*