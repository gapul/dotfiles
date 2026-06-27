# Obsidian 設定スナップショット (追跡専用ミラー)

このディレクトリは Obsidian の `.obsidian` 設定の **片方向スナップショット** です。

- **本体は vault 側** (`~/Documents/notes/.obsidian`)。ここは履歴・差分閲覧用の**読み取りミラー**。
- 更新は `just obsidian-snapshot` で **vault → dotfiles の一方通行**。
  逆向き (dotfiles → vault) には**絶対に**戻さない（戻すと二重オーナーになり同期が壊れる）。
- 日々の同期は Obsidian Git / Self-hosted LiveSync が担当。dotfiles は中身を所有しない。

## 公開リポジトリ前提の安全設計

このリポジトリは public。よって：

- **ホワイトリスト方式**: 安全と確認した json のみ収録
  (`app` `appearance` `hotkeys` `community-plugins` `core-plugins` `graph` `daily-notes` `types` `canvas`)。
- **絶対に入れない**: `plugins/*/data.json`（LiveSync の CouchDB 認証・各種 API キーが入りうる）、
  `workspace*.json`（端末状態）、`copilot-index-*` / `.smart-env`（キャッシュ）、プラグイン本体。
- `just obsidian-snapshot` は非空の秘密値を検出すると**中止**する。さらに commit 前に `gitleaks` を通す。
- 秘密ごと版管理したい設定は **sops 暗号化** (`just secrets` / `.sops.yaml`) してから置く。
