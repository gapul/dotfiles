# Mopidy × rmpc 互換バックログ

macmini の自走エージェントがここを1回1項目ずつ実装する。実装したら `- [x]` にして
`verified:` に検証方法を書く。詰まったら項目の下に `blocked:` で理由を残す。

対象は configs/media/mopidy/ のパッチと nix/lib/mopidy-env.nix のみ。テストは
~/ai/mopidy-dev/build-run.sh で dev mopidy (MPD=6601 / HTTP=6681) を上げて MPD
プロトコルを実際に叩いて確認する。詳細は ~/ai/mopidy-dev/AGENT-PROMPT.md。

## TODO (上から順に)

### mopidy-mpd プロトコル (認証不要でテストしやすい・優先)
- [x] `list` のグループ化: `list Album group AlbumArtist` 等 group 修飾に対応 (rmpc の Albums/Album Artists タブが使う)
  verified: mpdlist-patch.py。パッチ済み env の mopidy を検証用スタブ backend (get_distinct 実装、
  /tmp に dist-info 付きで生成) 付きで別ポート起動し MPD で実際に確認 —
  `list Album group AlbumArtist` → `AlbumArtist: AA1 / Album: Alpha / Album: Beta / AlbumArtist: AA2 / Album: Gamma`、
  多段 group (`list Title group Album group AlbumArtist`)、group + フィルタ式併用、
  `list Album group Bogus` → `ACK Unknown tag type`、旧来の `list Album ARTIST` / `list Title artist X album Y` の回帰なし。
  dev mopidy(6601, ytmusic) でも search フィルタ式の回帰なし・Traceback 0 を確認。
- [ ] `search`/`find` の `sort` 修飾に対応 (フィルタ式の後ろの `sort -Track` 等を解釈・無視でなく反映)
- [ ] `search`/`find` の `window START:END` 修飾に対応 (ページング)
- [ ] `count` / `count ... group TAG`: 件数・総時間を返す
- [ ] プレイリスト編集系: `playlistadd` `playlistdelete` `playlistmove` `playlistclear` `rename` `rm` `save`
- [ ] `listplaylistinfo` / `listplaylist` がフルのトラック情報を返すか確認・補完
- [ ] `sticker` コマンド群 (get/set/delete/list/find): rmpc の一部機能が使う。sqlite で永続化
- [ ] `tagtypes` 応答の網羅性: rmpc が期待するタグが揃っているか確認・追加
- [ ] `readcomments`: 対応 (無ければ空 OK)
- [ ] `moveid` `swapid` `prio` `prioid`: キュー操作の網羅
- [ ] `addid` の position 指定 (`addid URI POS`) 対応
- [ ] `getvol` / `volume` (相対) 対応確認

### mopidy-ytmusic (YTM 認証要・macmini でも browser.json で可)
- [ ] `get_distinct` の実装拡充: mopidy-ytmusic は artist/albumartist (ライブラリ登録分) しか返さず
      album/genre 等は未実装なので、`list` 系が実データで空になる。ライブラリのアルバム取得を有効化する
- [ ] `ytmusic:home` のセクション item マッピング改善 (song/album/artist/playlist を取りこぼさない)
- [ ] Liked Songs: ytmusicapi 1.12.1 が get_liked_songs で失敗する件を、別エンドポイント/パースで回避
- [ ] Recently Played (history): get_history 失敗を回避して Recently Played を出す
- [ ] 検索結果のアーティスト表記が "Song" 等になる件の是正 (parseSearch の filter=None 品質)
- [ ] `ytmusic:home` を深いページまで (get_home の continuation) 取得
- [ ] アルバム/プレイリストのブラウズ時にトラックのアート(get_images)を確実に載せる

## DONE (初期実装・母艦で検証済み)
- [x] ストリーム解決を pytube→yt-dlp へ委譲 (ytdlp-patch) — verified: 再生 state=playing
- [x] any 検索が album=None で 0 件になる不具合 (search-patch) — verified: yoasobi 等ヒット
- [x] 新 MPD フィルタ式 `(Tag contains "x")` の解釈 (mpdsearch-patch) — verified: 米津37件
- [x] albumart/readpicture 実装 + offset==total 修正 (mpd-patch) — verified: JPEG全転送
- [x] binarylimit 受け (mpd-patch) — verified: rmpc 接続可
- [x] ytmusic:home (get_home) ブラウズ (home-patch) — verified: セクション→playlist
- [x] listenbrainz 空 release_name の 400 修正 (lb-patch) — verified: 400消滅
