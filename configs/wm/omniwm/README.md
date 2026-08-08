# OmniWM 設定スナップショット (追跡専用ミラー)

`~/.config/omniwm/settings.toml` の**片方向スナップショット**です。

- **本体はライブ側**。OmniWM 自身がこのファイルを書き戻す（キーはソート済み、float はフル精度、
  バージョンが上がるとキーが増減する）ので、`home.file` で store の読み取り専用シンボリックリンクに
  すると設定を保存できなくなる。だから宣言ではなくミラーで追う。
- 更新は `just app-snapshot` で **ライブ → dotfiles の一方通行**。
- 新しい mac で戻すときだけ手動で `cp configs/wm/omniwm/settings.toml ~/.config/omniwm/`。
  OmniWM が起動中に上書きすると、常駐側の状態で巻き戻されるので必ず終了してから。
