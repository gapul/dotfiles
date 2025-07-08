# 保守コマンドクイックリファレンス

> 🔧 **日常的な保守作業の必須コマンド集**

## ⚡ 日常コマンド

### システム更新
```bash
just update              # 全体更新
just rebuild             # 設定再適用
just clean               # キャッシュクリア
```

### 健康チェック
```bash
just health              # システム健康チェック
nix store gc             # ストレージクリーンアップ
nix flake check          # 設定検証
```

### 緊急対応
```bash
just rollback            # 前の設定に戻す
just emergency-fix       # 緊急修復
nix-collect-garbage -d   # 強制クリーンアップ
```

## 🔍 トラブルシューティング

### よくある問題
| 症状 | 原因 | 解決 |
|------|------|------|
| 設定が反映されない | ビルドキャッシュ | `just clean && just rebuild` |
| Nixコマンドエラー | 権限問題 | `sudo chown -R $USER ~/.nix-store` |
| ディスク容量不足 | 古いビルド蓄積 | `nix-collect-garbage -d` |
| 環境変数未設定 | direnv未有効化 | `direnv allow` |

### 緊急連絡先
- **ログ確認**: `journalctl --user -u nix-daemon`
- **設定検証**: `nix flake check --verbose`
- **詳細ガイド**: [systems/SYSTEM_HEALTH_MONITORING.md](../systems/SYSTEM_HEALTH_MONITORING.md)

*更新頻度: 週1回 `just update` 推奨*
