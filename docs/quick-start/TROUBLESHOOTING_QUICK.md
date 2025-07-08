# トラブルシューティングクイック

> 🚨 **最も頻発する問題の即座解決方法**

## 🔥 緊急対応 (1分以内)

### システムが動かない
```bash
# 1. 前の設定に戻す
just rollback

# 2. キャッシュクリア・再試行
just clean && just rebuild

# 3. 強制リセット
nix-collect-garbage -d && just rebuild
```

### パッケージが見つからない
```bash
# 1. Nixパッケージ検索
nix search nixpkgs <package-name>

# 2. フレーク更新
nix flake update

# 3. 手動インストール
nix profile install nixpkgs#<package-name>
```

### 環境変数問題
```bash
# 1. direnv再有効化
direnv allow

# 2. シェル再起動
exec $SHELL

# 3. 手動環境変数設定
source ~/.nix-profile/etc/profile.d/nix.sh
```

## ⚠️ よくある問題TOP5

### 1. **"command not found" エラー**
```bash
# 症状: インストール済みコマンドが見つからない
# 原因: PATH設定問題
# 解決:
exec $SHELL                    # シェル再起動
source ~/.nix-profile/etc/profile.d/nix.sh  # 手動PATH設定
```

### 2. **"out of disk space" エラー**
```bash
# 症状: ディスク容量不足
# 原因: Nixストア肥大化
# 解決:
nix-collect-garbage -d         # 古いビルド削除
nix store optimise             # ストア最適化
```

### 3. **"flake.lock conflicts" エラー**
```bash
# 症状: flake.lockファイル競合
# 原因: 並行更新・マージ競合
# 解決:
git checkout HEAD -- flake.lock  # flake.lockリセット
nix flake update               # 再更新
```

### 4. **"permission denied" エラー**
```bash
# 症状: 権限エラー
# 原因: Nixストア権限問題
# 解決:
sudo chown -R $USER ~/.nix-store  # 権限修正
sudo chmod -R 755 ~/.nix-store    # 権限設定
```

### 5. **"evaluation aborted" エラー**
```bash
# 症状: Nix評価エラー
# 原因: 設定ファイル構文エラー
# 解決:
nix flake check --verbose      # 詳細エラー表示
git status                     # 変更ファイル確認
git diff                       # 差分確認・修正
```

## 📞 さらなるサポート

- **詳細ガイド**: [systems/](../systems/)
- **ログ確認**: `journalctl --user -u nix-daemon`
- **コミュニティ**: [NixOS Discourse](https://discourse.nixos.org/)

*解決しない場合は詳細ドキュメントを参照してください*
