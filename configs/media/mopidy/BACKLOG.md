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
- [x] `tagtypes` 応答の網羅性: rmpc が期待するタグが揃っているか確認・追加
  verified: パッチ不要 — 調査の結果、mopidy-mpd 3.3.0 の `tagtype_list.TAGTYPE_LIST`
  (Artist/ArtistSort/Album/AlbumArtist/AlbumArtistSort/Title/Track/Name/Genre/Date/
  Composer/Performer/Comment/Disc/MUSICBRAINZ_ARTISTID/MUSICBRAINZ_ALBUMID/
  MUSICBRAINZ_ALBUMARTISTID/MUSICBRAINZ_TRACKID/X-AlbumUri) は
  `mopidy_mpd/translator.py` の `track_to_mpd_format` が実際に生成しうる全タグ
  (Artist/Album/Title/Name/Date/Track/MUSICBRAINZ_ALBUMID/AlbumArtist/
  MUSICBRAINZ_ALBUMARTISTID/MUSICBRAINZ_ARTISTID/Composer/Performer/Genre/Disc/
  MUSICBRAINZ_TRACKID/X-AlbumUri) を既に完全網羅しており(file/Time/Pos/Id/
  Last-Modified は実 MPD 同様タグではなく別枠のため対象外で正しい)、追加すべき
  空きタグは存在しない。さらに rmpc 本体 (github.com/mierak/rmpc, rmpc-mpd crate) の
  ソースを実際に確認したところ `tagtypes` コマンドは一切送信しておらず、曲メタデータは
  固定タグ enum ではなく MPD の生応答をそのまま動的 HashMap (`metadata: HashMap<String,
  MetadataTag>`) として保持する実装のため、tagtypes の網羅性自体が rmpc の動作に影響しない
  ことも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `tagtypes`(規定値)→上記18種を返す、`search any "yoasobi"` の実応答タグ(Artist/Album/
  Title/Date/AlbumArtist/X-AlbumUri等)が全て tagtypes の宣言内に収まっている、
  `tagtypes disable Genre Composer`→以後の`tagtypes`から2つ消える、`tagtypes clear`→
  空、`tagtypes all`→全復元、未知サブコマンド`tagtypes reset ...`→
  `ACK Unknown sub command`(実MPD仕様通り、reset自体が存在しないサブコマンドのため正しい
  拒否)を確認。回帰なし・Traceback 0。
- [x] `readcomments`: 対応 (無ければ空 OK)
  verified: mpdreadcomments-patch.py。mopidy-mpd 3.3.0 の music_db.py は
  `# @protocol.commands.add('readcomments')` がコメントアウトされ本体も `pass` のスタブの
  ままだったため、有効化した上で `context.core.library.lookup(uris=[uri])` から取得した
  Track の `comment` フィールド (改行区切り) を `comment: LINE` として返す実装に置き換え
  (該当 uri がライブラリに無ければ `No such song`、track はあるが comment が空なら空リストで
  OK のみ)。検証用スタブ backend (LibraryProvider.lookup が comment 付き/無しの2トラックを
  返す、pkg_resources entry_points で /tmp に dist-info 生成、別ポート6602) で実際に確認 —
  `readcomments "rcstub:withcomment"` → `comment: line one` / `comment: line two`、
  `readcomments "rcstub:nocomment"` → 空でOK、`readcomments "rcstub:doesnotexist"` →
  `ACK No such song`、引数無し `readcomments` → `ACK wrong number of arguments`(既存の
  引数検証がそのまま機能)。dev mopidy(6601, ytmusic 実アカウント) でも実データの
  track uri で `readcomments` → 空でOK(ytmusic の Track は comment 未設定のため既知の
  挙動)、存在しない ytmusic uri → `ACK No such song`(mopidy_ytmusic 側の getTrack が
  KeyError: 'videoDetails' を投げるが core.library.lookup が握り潰して空リストにする
  既存の動作 — `listplaylistinfo` 等他コマンドで同じ nonexistent uri を使っても同一の
  Traceback が出ることを確認済みで、今回の patch による新規リグレッションではない)。
  旧来の `list`/`search`/`count`/`sticker`/`tagtypes` の回帰なし。
- [x] `moveid` `swapid` `prio` `prioid`: キュー操作の網羅
  verified: mpdprio-patch.py。`moveid`/`swapid` は mopidy-mpd 3.3.0 の
  current_playlist.py に既に完全実装済みと判明 (パッチ不要)。`prio`/`prioid` は
  `raise MpdNotImplemented` のスタブだったため実装: 優先度 (0-255) を tlid に
  紐付けて保存し (translator.py にモジュールレベルの揮発性ストアを追加、実 MPD も
  プロセス再起動で消える値なので妥当)、`playlistid`/`playlistinfo` 等の出力に
  non-zero のときだけ `Prio: N` を反映 (`Pos`/`Id` と同様 tagtypes 対象外の別枠
  フィールドとして常に出る)。gh search code で rmpc 本体 (mierak/rmpc,
  rmpc-mpd/src/mpd_client.rs) を確認したところ `moveid`/`swapid` は実際に送信するが
  `prio`/`prioid` は一切送信しないと判明。既知の制約: mopidy core の
  Tracklist.set_random()/next_track() (mopidy/core/tracklist.py) は優先度の概念を
  持たない単純な random.shuffle のみで、mopidy core 自体はパッチ対象外のため、
  `prio` が実際の random 再生順に影響することはない (プロトコル応答と
  playlistinfo の Prio フィールド反映のみ、rmpc は使わないため実害なし)。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、実データ(YOASOBIの
  アルバム+検索結果、Id 1-14)をキューに積んで MPD で確認 —
  `prio 50 0:2` → Id1/Id2 に `Prio: 50` が反映、`prioid 100 4 5` → Id4/Id5 に
  `Prio: 100`、`prioid 0 1` (0でリセット) → Id1 から Prio 消滅、多段レンジ
  `prio 30 6:8 10` → Id7/Id8/Id11 に正しく反映、`prio 999 0` →
  `ACK Invalid priority`、`prio 10 999`(範囲外songpos) → `ACK Bad song index`、
  `prioid 10 99999`(存在しないid) → `ACK No such song`、引数不足
  `prio 10`/`prioid 10` → `ACK wrong number of arguments`、非数値
  `prio abc 0` → `ACK incorrect arguments`。`moveid 14 0`(先頭へ移動)・
  `swapid 1 3`(入れ替え) も Pos が期待通りに変化することを確認。`list`/`count`/
  `search`(sort+window併用)/`sticker`/`readcomments`/`tagtypes` の回帰なし・
  Traceback 0 を確認。
- [x] `addid` の position 指定 (`addid URI POS`) 対応
  verified: mpdaddid-patch.py。既存実装は絶対位置 (protocol.UINT) のみ対応済みで、
  実 MPD 0.23+ の相対位置指定 (`+N`/`-N`、現在再生中の曲を基準にしたオフセット、
  musicpd.org protocol / MPD 本家 src/command/PositionArg.cxx ParseInsertPosition()
  相当) が未対応だったため実装。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し
  実データ(YOASOBI検索結果のtrack URI)で MPD プロトコルを直接叩いて確認 —
  キューが空(現在曲なし)で相対指定 `addid URI "+0"` →
  `ACK [55@0] {addid} No current song`、3曲キュー+`play 1`(pos1を再生中)の状態で
  `addid URI "+0"`→現在曲の直後(pos2)に挿入、`addid URI "-0"`→現在曲の直前に挿入され
  現在曲が1つ後ろにシフト(status の song: が+1)、境界値 `+N`(N=length-current-1)/
  `-N`(N=current)は成功しキューの先頭/末尾に正しく挿入、範囲超過
  `+N+1`/`-N-1`→`ACK [2@0] {addid} Number too large`、非数値 `+a`→
  `ACK incorrect arguments`、絶対位置指定の既存動作(範囲外→`Bad song index`、
  有効値→該当位置に挿入)は文言・挙動とも無変更で回帰なし、POSITION省略時の末尾追加・
  `addid ""`→`No such song` も回帰なし。旧来の `list album`/`count any`/`tagtypes`
  も Traceback 0 で回帰なしを確認。
- [x] `getvol` / `volume` (相対) 対応確認
  verified: mpdgetvol-patch.py。`setvol`/相対 `volume {CHANGE}` は mopidy-mpd 3.3.0 に
  既に実装済みと判明 (パッチ不要)。`getvol` (MPD 0.23+ で追加された音量単独問い合わせ、
  musicpd.org protocol "Playback options") 自体が protocol.commands に未登録で
  `ACK unknown command` になる状態だったため追加。実 MPD (src/command/PlayerCommands.cxx
  handle_getvol) と同じく `volume: N` を1行返し、ミキサー無し (get_volume()がNone) なら
  空応答で OK のみとする実装 (status コマンドの `volume: -1` フォールバックとは異なる仕様、
  musicpd.org 公式ドキュメントで "If there is no mixer, MPD will emit an empty response"
  と明記されていることを WebFetch で確認済み)。dev mopidy(6601, ytmusic 実アカウント)
  を実際に起動し MPD で確認 — `getvol`(初期)→`volume: 100`、`setvol 40`→OK、以後
  `getvol`→`volume: 40`、`volume 10`(相対+10、非推奨コマンド)→OK・`getvol`→`volume: 50`、
  `volume -100`(0へクランプ)→`getvol`→`volume: 0`、`setvol 999`(100へクランプ、既存の
  mopidy-mpd実装通りエラーにならない)→`getvol`→`volume: 100`、`setvol abc`(非数値)→
  `ACK incorrect arguments`(既存の引数検証のまま回帰なし)、`status`のvolumeフィールドも
  同じ値を返し回帰なし。旧来の `tagtypes`/`list album`/`search any`/`count any` も
  Traceback 0 で回帰なしを確認。

### mopidy-ytmusic (YTM 認証要・macmini でも browser.json で可)
- [x] `get_distinct` の実装拡充: mopidy-ytmusic は artist/albumartist (ライブラリ登録分) しか返さず
      album/genre 等は未実装なので、`list` 系が実データで空になる。ライブラリのアルバム取得を有効化する
  verified: ytdistinct-patch.py。library.py の `get_distinct()` は field=="album" の分岐が
  丸ごとコメントアウトされたスタブのままだったため、artist/albumartist分岐 (get_library_artists)
  と同じ流儀で `ytmusicapi.get_library_albums()` を使い有効化 (アップロード分
  get_library_upload_albums は artist分岐でも常時コメントアウトのままな慣例に合わせ見送り)。
  パッチ済み env の mopidy_ytmusic.library.YTMusicLibraryProvider を実際にimportし、
  backend.api.get_library_albums を MagicMock で差し替えて直接メソッド呼び出しで確認 —
  title付き2件+title欠落1件のモック応答 → `{"Album A", "Album B"}` (title欠落は無視) を正しく
  返す、get_library_albums が例外送出 → 握りつぶして空集合(クラッシュしない)、artist分岐
  (get_library_artists) は無改変で従来通り動作、を確認。dev mopidy(6601, ytmusic 実アカウント)
  でも実際に起動しMPDで確認 — `list album`/`list Album group AlbumArtist`/`count group album`は
  実行時例外なく応答(このアカウントはアーティストをフォローしているのみでアルバムを
  ライブラリ保存していないため実データは空、既知のアカウント状態でありパッチの不具合ではない
  — mopidy.log に "YTMusic failed getting albums from library" 等のエラーが一切出ていないことで
  確認)。旧来の `search any`/`tagtypes`/`count any`/`list artist`/`listplaylists` の回帰なし・
  Traceback 0 を確認。
- [x] `ytmusic:home` のセクション item マッピング改善 (song/album/artist/playlist を取りこぼさない)
  verified: home-patch.py (既存パッチを改良)。dev mopidy(6601, ytmusic 実アカウント) を実際に
  起動し `-vvvv` で ytmusic:home:N の各アイテムのキー集合を実データでダンプして分類ミスを特定 —
  「Shows for you」セクションの全27件が `{browseId, channel, podcastId, thumbnails, title}`
  (ytmusicapi parse_podcast 相当、videoId/playlistId 無し) を持つポッドキャスト番組にも関わらず、
  従来コードは browseId の有無だけで album 判定していたため誤って `Ref.album` にマッピングされ、
  実際に `lsinfo "YouTube Music/Home/Shows for you/<番組名>"` で開くと mopidy_ytmusic に
  podcast の browse/lookup 実装が存在しないため常に空フォルダになる不具合を確認 (修正前ログで
  実証済み)。修正: `podcastId` キー or `channel` キーを持つ項目は素通しせず除外するよう分岐を追加、
  かつ artist 判定を browseId の "UC" prefix 頼みから `subscribers` キーの有無も見るよう堅牢化
  (ytmusicapi parse_related_artist は browseId+subscribers を返す)。修正後に同アカウントで再検証 —
  `lsinfo "YouTube Music/Home/Shows for you"` → 空で正常応答 (誤ったalbumフォルダが消滅)、
  「Listen again」等の他セクションでは従来通り曲は `Ref.track`、レコメンドされた関連アーティスト
  (`tosho_aTe` 等、subscribersキー保持) や関連プレイリスト (`Trending 20 Japan` 等、
  playlistId+description保持) は実際に `lsinfo` で中身が取れる正しい `Ref.artist`/`Ref.playlist`
  ディレクトリとして残ることを確認 (取りこぼしなし)。旧来の `search any`/`status`/`list album`/
  `tagtypes` の回帰なし・Traceback 0 を確認。
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
