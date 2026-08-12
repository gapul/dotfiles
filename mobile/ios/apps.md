# iOS アプリ目録

一括インストールの手段は無い (App Store にも API が無い)。機種変時にこれを見ながら
入れ直すための目録。端末側で入れたものはここに書き足す。

「同期」列が埋まっているものは設定が自宅サーバ経由で戻ってくるので、
入れ直したあとにサーバの URL とアカウントだけ入れれば元に戻る。
経路の一覧は [../README.md](../README.md#アプリ設定の同期)。

| アプリ | 入手 | 用途 | 同期 |
|---|---|---|---|
| Tailscale | App Store | 自宅 tailnet | — |
| Blink Shell | App Store | ssh (母艦へ) | — |
| Obsidian | App Store | ノート | Self-hosted LiveSync |
| KeePassium | 自ビルド (SideStore) | パスワード / TOTP | Syncthing (kdbx) |
| Bitwarden | App Store | パスワード | Vaultwarden |
| ntfy | App Store | 自宅からの通知 | push.gapul.net |
| OwnTracks | App Store | 位置ログ | Dawarich |
| amgi (Anki) | 自ビルド (SideStore) | 暗記 | AnkiWeb |
| Element | App Store | Matrix | Conduit |
| Infuse / Swiftfin | App Store | 動画 | Jellyfin |
| play:Sub / substreamer | App Store | 音楽 | Navidrome |
| Reeder / Fiery Feeds | App Store | RSS | Miniflux (Fever API) |
| Home Assistant | App Store | 自宅の操作 | Home Assistant |

自ビルドの配信は [gapul/altstore-source](https://github.com/gapul/altstore-source)。
SideStore にこの source を登録しておくと更新が降ってくる。
