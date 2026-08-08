# CodexBar 設定スナップショット (追跡専用ミラー)

`~/.config/codexbar/config.json` の**片方向スナップショット**です。

- **本体はライブ側**。CodexBar が UI 操作のたびに書き戻すので、`home.file` では壊れる。
  [omniwm](../../wm/omniwm/README.md) と同じ扱い。
- 更新は `just app-snapshot` で **ライブ → dotfiles の一方通行**。
- このリポジトリは public なので、`providers[].codexActiveSource`（Codex アカウントの UUID）は
  スナップショット時に落としている。戻したあと CodexBar 側でアカウントを選び直せば再生成される。
- 戻すときは手動で `cp configs/apps/codexbar/config.json ~/.config/codexbar/`（CodexBar 終了中に）。
