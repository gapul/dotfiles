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
- [x] `search`/`find` の `sort` 修飾に対応 (フィルタ式の後ろの `sort -Track` 等を解釈・無視でなく反映)
  verified: mpdsort-patch.py。パッチ済み env の mopidy を、search()が固定3トラックを返す
  検証用スタブ backend (pkg_resources entry_points で /tmp に dist-info 生成、別ポート6602) で
  起動し MPD で実際に確認 — `find any "Song" sort Title`→昇順(Alpha/Beta/Gamma)、
  `sort -Title`→降順、`sort Track`/`sort -Track`→track_no昇順/降順、`sort Artist`→artist名昇順、
  `sort Date`→date文字列昇順、`sort ArtistSort`→artist へフォールバック、
  `sort Bogus`→`ACK Unknown sort type`。フィルタ式構文 (`search "(any contains ...)"`) +
  sort 併用、sort+window併用(windowは無視)も確認。エッジケース `find any "sort"`
  (検索語がたまたま"sort") が誤爆しないことも確認。dev mopidy(6601, ytmusic) でも
  `search any "yoasobi" sort -Date` で回帰なし・Traceback 0 を確認 (旧来の
  `list`/`search`/フィルタ式の回帰なし)。
- [x] `search`/`find` の `window START:END` 修飾に対応 (ページング)
  verified: mpdwindow-patch.py。パッチ済み env の mopidy を、search()が固定7トラックを返す
  検証用スタブ backend (pkg_resources entry_points で /tmp に dist-info 生成、別ポート6602) で
  起動し MPD で実際に確認 — `find any "Song" window "0:3"`→Song1-3、`window "3:6"`→Song4-6、
  `window "5:"`(open-ended)→Song6-7、`sort Track window "0:2"`/`sort -Track window "0:2"`→
  ソート後にスライス、`search any "Song" window "2:4"`→Song3-4。エラー系: コロン無し
  (`window "5"`)・非数値(`window "a:b"`)・end<start(`window "5:2"`)→
  `ACK Invalid window: ...`。範囲外(`window "100:200"`)・start==end(`window "3:3"`)は
  エラーにせず空リストで正常応答 (Python スライス相当、MPD仕様どおり)。エッジケース
  `find any "window"`(検索語がたまたま"window")が誤爆しないことも確認。旧来の
  `find`/`search`(sort/window無し)、タグ/値ペア形式の回帰なし。dev mopidy(6601, ytmusic)
  でも `search any "yoasobi" window "0:2"`→2件、`sort -Date window "0:2"`併用、
  不正window→ACK、を実データで確認・Traceback 0。
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
