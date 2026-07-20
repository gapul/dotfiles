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
- [x] `count` / `count ... group TAG`: 件数・総時間を返す
  verified: mpdcount-patch.py。mpdlist-patch が定義する `_mpd_extract_group_params` を再利用し
  group 修飾を追加。パッチ済み env の mopidy を、7トラック(artist/album/genre違い)を返す
  検証用スタブ backend (pkg_resources entry_points で /tmp に dist-info 生成、別ポート6602) で
  起動し MPD で実際に確認 — `count group artist`(フィルタ省略)→Artist1: 3曲530s /
  Artist2: 3曲620s / Artist3: 1曲160s、`count artist "Artist2" group genre`→Jazz 2曲410s /
  Rock 1曲210s、`count genre "Rock"`(group無し)→3曲590s、`count group album group artist`
  (多段group)→album毎に正しくネスト、フィルタ式 `count "(Genre == \"Pop\")"` 単体/group併用も
  正しい件数、`count group Bogus`→`ACK Unknown tag type: Bogus`、フィルタ・group共に無い
  `count`→songs:0/playtime:0 (旧来どおり)。旧来の `find`/`search`(sort/window)/`list`(group)の
  回帰なし。dev mopidy(6601, ytmusic)でも `count any "yoasobi"`→実データで songs:2/playtime:451、
  `count any "yoasobi" group album`(ytmusicのget_distinctがalbum未実装のため空でOK応答、既知の
  別項目の制約)、`list album`/`list artist`含め Traceback 0 を確認。
- [x] プレイリスト編集系: `playlistadd` `playlistdelete` `playlistmove` `playlistclear` `rename` `rm` `save`
  verified: パッチ不要 — mopidy-mpd 3.3.0 の site-packages 内 mopidy_mpd/protocol/stored_playlists.py に
  7コマンド全て既に実装済みで、mopidy.backend.PlaylistsProvider (create/save/delete/lookup/as_list/
  get_items) と core.library.lookup さえ backend 側が備えていれば動く。検証用スタブ backend
  (mopidy.backend.PlaylistsProvider + LibraryProvider をメモリ実装、pkg_resources entry_points で
  /tmp に dist-info 生成、別ポート6602) で実際に確認 —
  `playlistadd "MyList" URI`(新規作成/既存への追加どちらも)→OK、`listplaylistinfo`で
  Title/Time等フル情報、`playlistmove "MyList" 0 1`→順序入れ替え確認、
  `playlistdelete "MyList" 0`→該当曲削除、`rename "MyList" "MyList2"`→`listplaylists`で
  新名のみ表示、`add`でカレントキューに積んでから`save "SavedList"`→そのトラック列でプレイリスト
  作成、`playlistclear`→空リストになりOK、`rm`→`listplaylists`から消える。エラー系:
  `playlistdelete`の範囲外songpos→`ACK Bad song index`、`rm`/`rename`の存在しない名前→
  `ACK No such playlist`、スラッシュ入り名前→`ACK playlist name is invalid`、from==toの
  `playlistmove`→無害にOK、を確認。dev mopidy(6601, ytmusic)でもクリーン起動・`status`/
  `listplaylists`応答・Traceback 0 を確認 (実アカウントを変更する破壊的操作はスコープ外のため
  ytmusic 側では読み取り専用コマンドのみで確認)。
- [x] `listplaylistinfo` / `listplaylist` がフルのトラック情報を返すか確認・補完
  verified: パッチ不要 — mopidy-mpd 3.3.0 の stored_playlists.py は既に `listplaylistinfo` で
  `core.core.playlists.lookup()` 後に別途 `core.library.lookup(uris=...)` を呼んで
  track を再解決・enrichし、`translator.playlist_to_mpd_format` でフル情報 (Time/Artist/
  Album/Title/Date/Track/MUSICBRAINZ_*/AlbumArtist/Composer/Performer/Genre/Disc/
  Last-Modified/X-AlbumUri) を返す実装済み。`listplaylist` は仕様通り `file:` のみ。
  検証用スタブ backend (PlaylistsProvider が bare Track(uri のみ) を返し、LibraryProvider.lookup
  が別途フルメタデータで enrich する構成、かつ1曲は library.lookup 側に存在しない「消えたリンク」
  を模擬、pkg_resources entry_points で /tmp に dist-info 生成、別ポート6602) で実際に確認 —
  `listplaylist "StubList"` → 3曲とも `file:` のみ(消えたリンク含む)、`listplaylistinfo "StubList"`
  → 存在する2曲はフルタグ(MUSICBRAINZ_ALBUMID/AlbumArtist/MUSICBRAINZ_ARTISTID/Composer/
  Performer/Genre/Disc/Last-Modified/MUSICBRAINZ_TRACKID/X-AlbumUri 等)を返し、値が無い
  フィールドは省略(translatorのtagtypeフィルタ通り)、library.lookup で解決不能な「消えたリンク」
  はクラッシュせず黙って結果から落ちる(core.library.lookupが常に空リストで初期化するため
  KeyErrorしない)ことを確認。存在しないプレイリスト名→`ACK No such playlist`。
  mopidy_ytmusic側もplaylist.lookup()がplaylistToTracks()でLibraryProvider.TRACKSキャッシュに
  フルメタデータを先に積むため、後続のcore.library.lookupはキャッシュヒットしフル情報を維持する
  ことをソース確認(mopidy_ytmusic/playlist.py, library.py)。dev mopidy(6601, ytmusic 実アカウント)
  でもクリーン起動・`status`/`listplaylists`(実アカウントにプレイリスト無し)/検索の回帰なし・
  Traceback 0 を確認。
- [x] `sticker` コマンド群 (get/set/delete/list/find): rmpc の一部機能が使う。sqlite で永続化
  verified: mpdsticker-patch.py。mopidy-mpd 3.3.0 の stickers.py は `raise MpdNotImplemented` の
  スタブのままだったため、core.data_dir 配下 (`<data_dir>/mpd/sticker.db`) の sqlite に
  (type, uri, name)->value を保存する実装に置き換え。TYPE は実際の MPD 同様 "song" のみ許可
  (それ以外は `ACK Unknown sticker domain`)。dev mopidy(6601, ytmusic) を実際に起動し MPD で確認 —
  `sticker get` (未設定)→`ACK no such sticker`、`sticker set`→OK、再度 `get`→値取得、
  上書き `set`→新値に更新、`sticker list`(複数)→`sticker: name=value`列挙、
  `sticker find song "test:uri" "rating"`→prefix一致する複数曲を`file:`+`sticker:`ペアで列挙、
  `sticker delete NAME`→OK・以後`get`/再`delete`は`ACK no such sticker`、
  `sticker delete`(NAME省略、残り全削除)→OK・`list`は空でOK(エラーにならない)、
  `sticker get playlist ...`(未対応domain)→`ACK Unknown sticker domain`、
  不明action→`ACK Unknown sticker action`。sqlite ファイル
  (`~/ai/mopidy-dev/data/mpd/sticker.db`) に実際に永続化されたことを直接クエリで確認。
  旧来の `search`/`list`/`count`/`listplaylists` の回帰なし・Traceback 0 を確認。
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
