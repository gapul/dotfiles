# Mopidy × rmpc 互換バックログ

macmini の自走エージェントがここを1回1項目ずつ実装する。実装したら `- [x]` にして
`verified:` に検証方法を書く。詰まったら項目の下に `blocked:` で理由を残す。

対象は configs/media/mopidy/ のパッチと nix/lib/mopidy-env.nix のみ。テストは
~/ai/mopidy-dev/build-run.sh で dev mopidy (MPD=6601 / HTTP=6681) を上げて MPD
プロトコルを実際に叩いて確認する。詳細は ~/ai/mopidy-dev/AGENT-PROMPT.md。

## TODO (上から順に)

- [x] `mopidy_mpd/translator.py`の`track_to_mpd_format()`が、MPD 0.24+の`Added`タグを
  参照経路によって完全に独立した2系統の揮発性ストアで返しており、同一曲(同一uri)でも
  find/search経由かキュー経由かで値が食い違い、さらにキューへの出し入れのたびに値が
  変わってしまう不具合。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  `mpdadded-patch.py`が導入したキュー内Added(`_queue_added`、tlidキー、曲がキューへ
  追加されるたびに新しい現在時刻でスタンプ)と、`mpdlibraryadded-patch.py`が導入した
  キュー外Added(`_library_added`、uriキー、このMPDセッションで最初にそのuriを返した
  時刻を不変に保持)は完全に独立しており、`track_to_mpd_format()`は`position`/`tlid`が
  ある(キュー経由)かどうかでどちらを読むか分岐している。`mpdlibraryadded-patch.py`
  自身のコメントも「同一uriがキューにも同時に載っている場合、キュー側は独立した
  `_queue_added`を引き続き使う」と明記しており自覚済みだったが、未修正のまま残されて
  いた(`mpdsavecreatedefault-patch.py`等と同型の「既存コメントは検証済みの証拠に
  ならない」パターンの再発)。
  実MPD仕様からの裏付け: 実MPD本体(gh rawで`src/queue/Queue.hxx`を確認)の
  `Queue::Item`構造体は`id`/`song`/`version`/`priority`のみでAdded相当のフィールドが
  一切無く、実MPDには「キューへの追加時刻」という概念自体が存在しない。
  `src/song/DetachedSong.hxx`のコメント("The time stamp when the file was added to
  db")の通り、`playlistinfo`が表示するAddedもfind/lsinfoと全く同じ、曲固有(DB登録
  時刻)の値を経路によらず再利用しているだけと確認した。
  rmpc側の実害: rmpc本体(mierak/rmpc)の`SongProperty::Added()`
  (`rmpc/src/config/theme/properties.rs`)は`rmpc/src/ui/dir_or_song.rs`の
  `CmpByProp::cmp(a.added, b.added)`からキュー/検索結果/タグブラウザ/
  ストアドプレイリストいずれのペインでも同一の意味論のソート・カラム表示プロパティ
  として参照されるため、経路による食い違いはキューへの出し入れだけでソート順が
  不安定に変化する実害がある。
  実機確認(dev mopidy、TCP 6601、実ytmusicアカウント、`ytmusic:track:qivRUhepWVA`):
  `find file "URI"`のAddedは`2026-07-25T06:54:43Z`で終始不変。修正前の実装だと
  `addid`直後の`playlistinfo`は別の(その場でスタンプされた)値になり、`clear`後に
  同じuriを再`addid`するとさらに別の値に変わることをコード上確認した上で、修正後は
  `find`→`addid`→`playlistinfo`→`clear`→再`addid`→`playlistinfo`→再`find`の
  全6回が`2026-07-25T06:54:43Z`で完全一致することを実機で確認。`playlistid`
  (Pos/Id付きの同型出力)・`save`→`listplaylistinfo`(ストアドプレイリスト経由)でも
  同一値であることを確認。回帰: `ping`/`status`/`tagtypes`/`stats`baseline無影響。
  mopidy.log clean(0 new ERROR/Traceback、唯一のERRORは`save`によるプレイリスト
  作成が本テストアカウントのYTMusic書き込み権限不足でHTTP 401になる、
  point 79/80から既知の無関係なノイズ)。
  修正: `mpdaddedunify-patch.py`。`track_to_mpd_format()`のキュー分岐(position/tlid
  有)のAdded取得を、tlidキーの`get_added()`から`mpdlibraryadded-patch.py`が導入した
  uriキーの`get_or_stamp_library_added()`に一本化する1行の変更のみ。`_queue_added`/
  `stamp_added`/`sync_added`/`get_added`の書き込み経路(add/addid/findadd/searchadd/
  load/actor.py)は読まれなくなるだけで実害が無いため、blast radius最小化のため
  他ファイルは無変更のまま残した。`nix/lib/mopidy-env.nix`の`mpdPatched`リスト末尾
  (`mpdplaylistclearguard-patch.py`の直後)に登録。
  verified: `~/ai/mopidy-dev/build-run.sh`でdev mopidy起動、TCP 6601へ生ソケットで
  接続し`find`/`addid`/`playlistinfo`/`clear`/再`addid`/`playlistid`/`save`+
  `listplaylistinfo`を実行してAdded値が全経路・全キュー操作を通じて完全一致する
  ことを確認。offline検証としてnix storeビルド済み`translator.py`を隔離コピー
  (chmod u+wで書き込み権限付与)へパッチ適用しast.parse成功・べき等性(2回目は
  "already patched"でskip)も確認済み。

- [x] `mopidy_ytmusic/library.py`の`parseSearch()`(`search()`経由、"any"/genre/date/
  track_no/`_META_SEARCH_FIELDS`等filter=Noneで呼ぶ全ての検索パスが通る共通パーサ)の
  if/elifチェーンがresultType "song"/"video"/"episode"/"album"/"artist"の5種類しか
  処理しておらず、ytmusicapi 1.12.0の`ALL_RESULT_TYPES`に含まれるresultType "station"
  (再生シード曲付きのラジオ/ミックス局)を素通しし黙って捨てている不具合。
  TODO全項目消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任・再検証を経て)新規発見。当初の候補("podcast"=番組そのものへの分岐追加)は
  実ソース(`ytmusicapi/parsers/search.py`)を直接確認した結果、`videoId`(再生可能データ)
  を一切持たない非再生コンテナ(`browseId`のみ)であり、`home-patch.py`が同じ理由で
  「Shows for you」をHomeから意図的に除外している設計と同根の「構造的にnon-Track」で
  あることが判明し却下、サブエージェントを再開してより厳密な基準(実際にvideoId等の
  再生可能データを持つのに握りつぶされている)で再調査させ本項目を発見した。
  実害確認: `ytmusicapi/parsers/search.py`の`parse_search_result()`は136-138行目
  `elif result_type == "station": search_result["videoId"] = nav(data,
  NAVIGATION_VIDEO_ID); search_result["playlistId"] = nav(data, NAVIGATION_PLAYLIST_ID)`
  で実在・再生可能なvideoId(実watchEndpointのシード曲)を設定する(title/thumbnailsは
  全resultType共通ロジックで付与)。つまりstationは即再生可能なTrackとして扱えるデータ
  (実videoId)を持つが、`parseSearch()`にはresultType "station"用の分岐が無く、
  if/elifチェーンをどれにも一致せず素通りし例外も出さず黙って捨てられる(既存の
  try/exceptにも捕捉されない。resultTypeの除外名リストに"station"という文字列自体は
  既に含まれていた(artist名誤表記フィルタ用、`{"song", "video", ..., "station", ...}`)が、
  resultType自体の分岐は一度も実装されていなかった)。
  実機確認(dev mopidy、実ytmusicアカウント、TCP 6601)では多数の検索語(ジャンル名/
  ムード名/「Radio」「Mix」を含む語/公式ステーション名等、計40種類超)を試したが
  この開発アカウント・リージョンではresultType "station"を含む応答を一件も再現できな
  かった(検索結果自体が1〜4件と少なく、"Top result"カードがstation型になる語を
  引けなかった)ため、`~/ai/mopidy-dev/AGENT-PROMPT.md`の指針(データ不足時はオフライン
  検証に切り替える)に従い、`object.__new__(YTMusicLibraryProvider)`でbackend依存を
  回避してインスタンス化し、実際のパーサ(`ytmusicapi/parsers/search.py`)が
  resultType "station"に対して設定する実フィールドのみを模した合成データ(`resultType`/
  `title`/`videoId`/`playlistId`/`thumbnails`)を`parseSearch()`に直接投入して検証した。
  修正前(パッチ未適用)は該当resultTypeが素通りしtracksが空になることをコード上確認済み、
  修正後は`SearchResult.tracks`に`uri=ytmusic:track:<videoId>`
  `name=<title>` `artists=frozenset()` `album=None` `date="0000"` `length=0`の
  Trackが1件正しく生成され、`IMAGES`キャッシュにもサムネイルが登録されることを確認。
  `videoId`欠落時は例外を出さず静かにスキップされる回帰チェックも実施。加えて実機
  (TCP 6601)で`search any "YOASOBI"`(既存song/album分岐)が本パッチ適用後も従来通り
  3件(1 album-placeholder + 2 real tracks)を返すことを確認、`ping`/`status`baseline
  も無影響。mopidy.log clean(0 new ERROR/Traceback、クリーン起動)。
  修正: `ytsearchstationresult-patch.py`。video/episode分岐と同型で`station`分岐を
  `ytsearchepisoderesult-patch.py`が追加したepisode分岐の直後(album分岐の直前)に
  追加。stationにはartists/durationのデータが無いため`artists=[]`・
  `_yt_track_length_ms()`の既存の安全な0フォールバックに委ね、album/playlistId
  (ラジオの継続queue)は捏造せず/使わずNoneのまま据え置き、即再生可能な1曲のTrackとして
  拾う最小修正に留めた(playlistIdをブラウズ可能なプレイリストとして扱う本格対応は
  別スコープ)。`nix/lib/mopidy-env.nix`の`ytmusicPatched`リスト末尾
  (`ytsearchepisoderesult-patch.py`の直後)に登録。
  verified: object.__new__(YTMusicLibraryProvider)によるオフライン合成データ検証
  (修正前は素通り→tracks空、修正後はTrack 1件正しく生成を確認) + 実機TCP 6601での
  既存song/album検索の無回帰確認 + mopidy.log clean。実resultType "station"応答は
  このdevアカウント・リージョンでは40検索語超を試しても再現できず、真の意味での
  live end-to-endは不可能だったため、パーサの実フィールド仕様に基づく合成データでの
  検証に留める(実データが得られ次第、追加確認が望ましい残課題として記録)。

- [x] `playlistclear {NAME}`(mopidy_mpd/protocol/stored_playlists.py)が対象プレイリスト
  未存在時、実MPDと異なり黙って新規プレイリストを作成しOKを返してしまう不具合。
  TODO全項目消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任を経て)新規発見。`mpdplaylistcreateguard-patch.py`は同じ箇所の
  `context.core.playlists.create(name).get()`戻り値None(生成失敗)未チェックによる
  素のAttributeError(接続切断)は既に修正済みだが、そのパッチ自身・対応する
  BACKLOG.md項目(上記の直後、5695行目付近)のコメントはいずれも「未存在なら
  新規作成する経路」自体を既存仕様として受け入れており、実MPD準拠性は一度も
  確認されていなかった。実MPD本体(gh rawで`src/command/PlaylistCommands.cxx`
  `handle_playlistclear()`を確認)は`spl_clear(name)`を呼び、`src/PlaylistFile.cxx`
  `spl_clear()`は`TruncateFile(path_fs)`(`O_CREAT`無し)を試み、ファイル不在
  (ENOENT)なら`PlaylistError(PlaylistResult::NO_SUCH_LIST, "No such playlist")`を
  投げる(=作成しない)ことを確認。`doc/protocol.rst`でも`playlistadd`の項目には
  "NAME.m3u will be created if it does not exist"と明記されているのに対し、直下の
  `playlistclear`の項目には同様の記述が無く、これは意図的な非対称
  (`playlistadd`は`APPEND_OR_CREATE`、`playlistclear`は非作成の`TruncateFile`)と
  確認。BACKLOG.mdを"playlistclear"で全27件検索し、唯一の関連項目
  (`mpdplaylistcreateguard-patch.py`)はNone未チェッククラッシュのみを対象とし
  この具体的な非準拠には未着手だったことを確認済み。
  実害: rmpc等が誤って未存在のプレイリスト名へ`playlistclear`を送ると、ACKも
  警告も無く空の新規プレイリストがサイレントに作成されてしまう(実MPDなら
  `ACK [50@0] {playlistclear} No such playlist`で拒否されユーザーに可視化される)。
  修正: `mpdplaylistclearguard-patch.py`。`_get_playlist(context, name,
  must_exist=False)` + `playlists.create()`フォールバックを削除し、他の兄弟
  コマンド(`listplaylist`/`listplaylistinfo`/`rm`等)と同じ`_get_playlist(context,
  name)`(`must_exist=True`既定、無ければ`exceptions.MpdNoExistError("No such
  playlist")`を送出、real MPDと同じACKコード50)に置き換え。docstringの
  "The playlist will be created if it does not exist."も実態に合わせ削除。
  verified: オフライン検証(既存ビルド済みnix store envから`mopidy_mpd`パッケージ
  全体をバイトコピーで隔離しパッチ適用、`ast.parse()`で構文確認、2回連続適用で
  "already patched, skip"となり冪等なことを確認)の上で、
  `~/ai/mopidy-dev/build-run.sh`でdev mopidyをビルド・起動(クリーン起動、
  mopidy.logに新規ERROR/Traceback無し)。実機確認(TCP 6601、mopidy-ytmusic実
  アカウント): 未存在プレイリスト名`AutoAgentClearTestXYZ`への`playlistclear`は
  修正前`OK`(`listplaylists`に新規作成されるバグを確認)、修正後
  `ACK [50@0] {playlistclear} No such playlist`(`listplaylists`は無変更のまま
  作成されないことを確認)。回帰確認: `search any "YOASOBI"`の実uriで
  `playlistadd`した既存プレイリストへの`playlistclear`は引き続き`OK`で全曲
  クリアされ`listplaylistinfo`が空になることを確認(既存プレイリストに対する
  本来の動作は無変更)、`rm`での後始末も無変更。rmpc本体
  (`mpd_client_ext.rs create_playlist()`の`save→playlistclear→add`ワークアラウンド
  経路、`mpdsavecreatedefault-patch.py`によりMODE省略の`save`は常に新規作成する
  ため直後の`playlistclear`は必ず既存プレイリストに対して実行される)も同じ
  シーケンスを実機で再現し無回帰であることを確認(`save`→`playlistclear`→
  `playlistadd`→`listplaylistinfo`で12曲が正しく保存されることを確認)。
  `ping`基準応答も無変更。
- [x] `save {NAME}`(mopidy_mpd/protocol/stored_playlists.py、`mpdversion-patch.py`が
  MPD 0.24+の`[MODE]`引数を実装)がMODE省略時、実MPD(MODE省略時はcreate扱いで既存なら
  拒否)と異なり「無ければ作成・あれば上書き」という旧来mopidy挙動のまま黙って既存
  プレイリストを上書きしていた不具合。`mpdversion-patch.py`自身のコメントは「旧来の
  rmpc呼び出し・過去backlogで検証済みのsave単体動作の回帰を避けるため、実MPDの
  『MODE省略時はcreate扱いで存在すればエラー』という仕様はあえて踏襲しない」と明記して
  いたが、これはrmpc本体(mierak/rmpc)が実際にMODE省略saveをどう使うか未検証のまま
  書かれた判断だったと判明。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任・2段階の追加深掘りを経て)新規発見。
  実際にrmpcをcloneして確認すると、3箇所全てでMODE省略(None)の
  `save_queue_as_playlist`を呼んでおり、いずれも実MPDの「既存なら拒否」という安全装置に
  暗黙に依存している: `rmpc/src/ui/panes/queue.rs`(「Save queue as playlist」メニュー、
  InputModalのタイトルは"Create new playlist" — 新規作成前提のUI)、
  `rmpc/src/core/command.rs`(`rmpc save NAME` CLI/キーバインドコマンド)、
  `rmpc/src/shared/mpd_client_ext.rs`の`create_playlist()`(「新規プレイリストへ追加」
  のコンテキストメニューが使うワークアラウンド: MPDは空プレイリストを作成できないため
  save→playlistclear→複数addをcommand_listで実行。既存名を再利用してしまうとsaveが
  黙って上書きし、直後のplaylistclearで元の内容が完全消去される)。エラーは
  `rmpc/src/core/client.rs`→`event_loop.rs`の`status_error!`でユーザーに可視化される
  設計であり、「既存名なら弾かれてユーザーに通知される」ことを前提にしている。
  実MPD本体(gh rawで`src/command/PlaylistCommands.cxx`の`handle_save()`:
  `PlaylistSaveMode mode = PlaylistSaveMode::CREATE;`がMODE省略時のデフォルト、
  `src/PlaylistSave.cxx`の`spl_save_queue()`がCREATEモードで`FileExists()`なら
  `PlaylistError(PlaylistResult::LIST_EXISTS, "Playlist already exists")`を投げることを
  確認)。BACKLOG.mdの唯一の既存記述(`mpdversion-patch.py`導入時のコメント、上記
  引用箇所)はmopidy内部の回帰回避の理由付けのみで、実MPD準拠性やrmpc側の依存には
  一切触れておらず、この具体的なサブケースへの既出カバレッジではないと確認済み。
  実害: rmpcの「Save」コンテキストメニューで既存プレイリスト名を(誤って)入力すると、
  save(MODE省略)が警告もACKも無く現在のキューで上書きし、直後のplaylistclear+addで
  元の保存内容が完全に失われる。同じ危険は素の「Save queue as playlist」モーダルと
  `rmpc save` CLIコマンドでも起こり得る。
  修正: `mpdsavecreatedefault-patch.py`。MODE省略時を`"create"`と同一に扱う条件式
  (`mode == "create"` → `mode in ("create", None)`)へ1行変更し、古い前提を記述して
  いたdocstringも修正。`mpdplaylisteditrace-patch.py`がsave()本体全体を
  `with _stored_playlist_edit_lock:`で1段階インデントしていたため、アンカーは
  `mpdversion-patch.py`が導入した元のインデントではなく実際のビルド後ソース
  (既存ビルド済みenvから直接抽出)に合わせて8スペースインデントで記述。
  verified: オフライン検証(既存ビルド済みnix store envから`mopidy_mpd`パッケージ全体を
  バイトコピーで隔離しパッチ適用、`ast.parse()`で構文確認、2回連続適用で
  "already patched, skip"となり冪等なことを確認)の上で、
  `~/ai/mopidy-dev/build-run.sh`でdev mopidyをビルド・起動(クリーン起動)。
  実機確認(TCP 6601、mopidy-ytmusic実アカウント): 存在しない新規プレイリスト名への
  `save "NAME"`(MODE省略)は修正前後とも`OK`(作成)で無変更、`listplaylistinfo`で25件の
  実トラックが保存されたことを確認。その後キューを別内容(重複含む30件)に変更し同じ
  既存名へ`save "NAME"`(MODE省略)を再送すると、修正前は`OK`で黙って上書きされていたが
  修正後は`ACK [56@0] {save} Playlist already exists`となり、直後の`listplaylistinfo`で
  元の25件が完全に無変更のまま保持されていることを確認(データ消失を防止)。
  回帰確認: `save "NAME" "replace"`(既存名、MODEを明示指定)は引き続き`OK`で上書き、
  `save "NAME2"`(未使用の新規名、MODE省略)は引き続き`OK`で新規作成、
  `save "NAME" "create"`(既存名、MODE明示"create")は修正前と同じ`ACK Playlist already
  exists`で無変更。`status`/`ping`/`tagtypes`の基本応答にも異常無し。mopidy.log新規
  ERROR/Tracebackは0件(save失敗時のYTMusic API 401ログはこのテストアカウントの既知の
  pre-existing挙動、本パッチ検証とは無関係)、クリーン起動。

- [x] `subscribe`/`unsubscribe`(mopidy_mpd/protocol/channels.py、`mpdchannels-patch.py`
  導入)が発火する idle `"subscription"` 通知が、`_mpdchannels_notify("subscription")`
  = `mopidy.listener.send(MpdSession, ...)` による無条件全パーティション broadcast
  のままで、mixer/output(`mpdidlemixerpartition-patch.py`)や
  crossfade/mixrampdb/mixrampdelay/replay_gain_mode(`mpdcrossfadeidlepartition-patch.py`)
  で既に対応済みのパーティション限定配送から漏れていた不具合。`mpdchannels-patch.py`
  自身のコメントは「idle `"subscription"` は実MPDの`idle_add(IDLE_SUBSCRIPTION)`同様、
  全セッションへの無条件ブロードキャストが正しい仕様」と明記していたが、これは実MPD
  ソースの誤読だったと判明。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawで`src/client/Subscribe.cxx`の`Client::Subscribe()`/
  `Client::Unsubscribe()`を確認)はいずれも`partition->EmitIdle(IDLE_SUBSCRIPTION)`を
  呼ぶ。`Partition::EmitIdle`(`src/Partition.hxx`)は自パーティション限定のメソッドで
  あり、真にグローバルな`idle_add()`(`src/Idle.cxx`、`global_instance->EmitIdle(flags)`)
  とは別物(`IDLE_SUBSCRIPTION`は`idle_add()`側では未使用)。`IDLE_MESSAGE`(idle
  `"message"`)はセッション単位の別機構`Client::IdleAdd()`であり、こちらは
  `_mpdchannels_notify_targeted`が既に正しく個別配送対応済み。
  BACKLOG.mdを`"IDLE_SUBSCRIPTION"`/`"subscription.*partition"`/`"_mpdchannels_notify"`
  で検索し、`mpdchannelpartition-patch.py`(channels/sendmessageの購読データ可視性の
  みを対象、idle通知配送範囲は明示的に対象外と自己コメントに明記)以外に既出無しを
  確認済み。
  修正: `mpdchannelsidlepartition-patch.py`。新規ヘルパー追加は不要、
  `mpdcrossfadeidlepartition-patch.py`が確立済みの`translator.partition_idle_targets(partition)`
  と`mpdchannels-patch.py`自身が既に持つ`_mpdchannels_notify_targeted()`(pykka
  ProxyCall直接tell()個別配送)を組み合わせるだけで、`subscribe()`/`unsubscribe()`の
  `_mpdchannels_notify("subscription")`を発火元セッションのパーティションだけへの
  個別配送に置き換え。
  verified: `~/ai/mopidy-dev/build-run.sh`でビルドしたdev mopidy(TCP 6601)へ3接続
  (A=default, B/C=newpartition zoneXへpartition切替)。修正前提として、B(zoneX)を
  `idle subscription`購読状態にしA(default)で`subscribe fooA`/`unsubscribe fooA`を
  実行しても、Bが誤起床しないことを確認(実際にPythonソケットスクリプトで
  修正後のchannels.pyに対し実施、`recv`が2秒タイムアウトすることでNoneToOKの
  「起床しない」を確認)。対照として同一パーティション内(C)は`subscribe`/
  `unsubscribe`で正しく`changed: subscription`起床することを確認(個別配送機構
  自体が機能している証明)。regression: `repeat`(全体broadcastのまま)は引き続き
  他パーティションも起床、`ping`/`status`/`channels`ベースライン無影響、
  mopidy.log新規ERROR/Traceback0件、クリーン起動。オフラインでも
  `ast.parse`済み・冪等再実行で"already patched, skip"確認済み。

- [x] `plchanges`(mopidy_mpd/protocol/current_playlist.py)のバージョン一致
  (メタデータ更新のみ)分岐で、直前の`mpdplchangesrange-patch.py`が導入した
  リトライループ内の範囲判定`if not (start <= position < end):`が
  `position is None`をガードしておらず、TOCTOUレース(`get_current_tl_track()`と
  `tracklist.index()`の間に別接続がトラックを削除等)で`position`が`None`に
  なると`int <= NoneType`比較で捕捉されない`TypeError`を送出し、ACKにすら
  ならずTCP接続ごと切断されうる回帰。TODO/既知の残課題を全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を2段階経て、
  「パッチ間相互作用による退行」という切り口を起点に)新規発見。
  同じ関数のループ後フォールバック分岐には`if position is None or not
  (start <= position < end):`という正しいガードが既にあり(range引数パッチ
  自身が追加)、ループ内分岐だけが同じガードを欠いていた非対称。旧実装
  (range引数未対応版)ではこの分岐は比較を経由せず直接
  `translator.track_to_mpd_format(tl_track, ..., position=position, ...)`を
  呼んでおり`position=None`は黙って許容されていた(Pos:/Id:欠落のみ)ため、
  この`TypeError`はrangeパッチが新規に持ち込んだ回帰と判断した
  (`mopidy/core/tracklist.py`の`index()`実装を確認: `tl_track`がトラック
  リストから消えていると`ValueError`を捕捉して`None`を返す仕様)。
  BACKLOG.mdを"plchanges"/"TypeError"/"position is None"等で検索し既出無しを
  確認済み。
  修正: mpdplchangesnoneguard-patch.py。フォールバック分岐と全く同じ
  `position is None or`ガードをループ内分岐にも追加。
  verified: `~/ai/mopidy-dev/build-run.sh`でビルドしたenvの実ソースが
  期待通り2箇所とも`if position is None or not (start <= position < end):`
  になっていることを確認、mopidy.log新規ERROR/Traceback0件でクリーン起動、
  TCP 6601で`searchadd artist "YOASOBI"`(25曲)+`plchanges "0"`が全曲を
  正しく返す回帰確認。加えて実際のTOCTOUレース(実配信中のstream_title変化+
  同時に別接続でトラック削除)を再現するのはタイミング依存で困難なため、
  実際にビルドされたenvのpython3.13(dev mopidyプロセスの実行環境変数
  GI_TYPELIB_PATH/GST_PLUGIN_SYSTEM_PATH_1_0を借用)で`mopidy_mpd.protocol.
  current_playlist.plchanges()`を疑似context(`tracklist.index()`が`None`を
  返すよう細工)で直接呼び出し、修正前のコード(該当行だけ一時的に
  ガード無しへ戻したコピー)では`TypeError: '<=' not supported between
  instances of 'int' and 'NoneType'`が実際に発生し、修正後のコード
  (実際にビルドされたenv)では例外を投げず`None`を返すことを確認した。
  同じ疑似contextでposition在圏内/範囲外の通常ケースもそれぞれ正しく
  トラック情報/`None`を返すことを確認(range機能自体への回帰無し)。

- [x] `plchanges`/`plchangesposid`(mopidy_mpd/protocol/current_playlist.py)が
  MPD 0.20+で追加された任意の`[START:END]`範囲引数を一切受け付けず
  `wrong number of arguments`にACKしてしまう不具合。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。実MPD本体(gh rawでsrc/command/QueueCommands.cxxの
  `handle_plchanges()`/`handle_plchangesposid()`を確認): `args.ParseOptional(1,
  RangeArg::All())`で任意のRangeを受け取り、`playlist_print_changes_info`/
  `_position`(src/PlaylistPrint.cxx)が`range.ClipRelaxed(queue.GetLength())`
  (src/protocol/RangeArg.hxx、endをlengthへ・startをendへ超過分だけ黙って
  クランプしACKにはしない=playlistinfo等のCheckClipとは異なる緩い方式)の上で
  `queue_print_changes_info`/`_position`(src/queue/Print.cxx)が
  `for (i=start;i<end;i++) if (queue.IsNewerAtPosition(i, version)) ...`と
  範囲外の位置をそもそも走査対象から除外する。mopidy_mpd側は元々`version`の
  1引数しか受け付けず(`@protocol.commands.add("plchanges",
  version=protocol.INT)`)、3つ目以降のトークンがあるとdispatcherの
  `inspect.signature(func).bind()`がTypeErrorとなり`wrong number of
  arguments`としてACKされ、範囲指定自体が一切不可能だった。BACKLOG.md全体を
  "plchanges"/"START:END"/"RangeArg"で検索し既出無しを確認済み(plchanges/
  plchangesposidを触る既存パッチ(mpdcurrentsongrace-patch.py/
  mpdplchangesposidfuture-patch.py等)はいずれもTOCTOUレース・未来バージョン
  判定などversion比較ロジックのみで範囲引数は未対応と確認)。
  修正: mpdplchangesrange-patch.py。両コマンドに`songrange=protocol.RANGE`
  (デフォルト`slice(0, None)`=全件、既存の`listplaylistinfo`と同じ流儀)を
  追加。共有ヘルパー`_mpd_plchanges_clip_range(songrange, length)`で実MPDの
  `ClipRelaxed`と同じ「endをlengthへ、startをend(クランプ後)へ、それぞれ
  超過分のみ黙ってクランプ」を行い、`version < tracklist_version`(全曲
  「変更」)分岐は`translator.tracks_to_mpd_format(..., start=, end=)`
  (既存のstart/end引数がPos:フィールドも絶対位置のまま保つ)へ委譲、version
  一致のメタデータ更新1曲分岐・リトライ後fallback分岐・plchangesposidの
  enumerateループは対象positionが範囲外なら何も返さない(real MPDの「範囲外
  は素通り」と同じ)。バージョン比較ロジック自体(TOCTOU retry・未来
  バージョン判定)は無変更。
  verified: オフライン検証(`/tmp`へ隔離コピーしパッチ適用、`ast.parse()`で
  構文確認、2回連続適用で"already patched, skip"となり冪等なことを確認)の
  上で、dev mopidyをビルド・起動(mopidy.log新規ERROR/Traceback0件、クリーン
  起動)。実機確認(TCP 6601、mopidy-ytmusic実アカウント、`clear`+
  `searchadd artist "YOASOBI"`で15曲実データキュー→`delete "0"`で1曲削除し
  version/lengthを変化): `plchanges "<旧version>"`(範囲無し)は修正前後とも
  全曲(14曲)を返し無変更であることを確認。`plchanges "<旧version>" "0:2"`
  (新機能)は修正前`ACK wrong number of arguments for "plchanges"`だったのが
  修正後`Pos: 0`/`Pos: 1`の2曲のみを正しく返すことを確認。範囲外
  `"9999:10005"`は空の`OK`(ACKにはならない、real MPDのClipRelaxed同様)。
  `plchangesposid "<旧version>"`(範囲無し)は全14件のcpos/Idを返し無変更。
  `plchangesposid "<旧version>" "1:2"`(新機能)は`cpos: 1`/`Id: 5`のみを
  正しく返すことを確認。回帰確認: 非数値VERSION(`plchanges "abc"`)は引き続き
  `ACK incorrect arguments`、不正な範囲文字列(`plchanges "<version>" "abc"`)
  も引き続き`ACK incorrect arguments`(protocol.RANGEのバリデーションが機能)。
  mopidy.log新規ERROR/Traceback0件。

- [x] `binarylimit {SIZE}`(mpdbinarylimitargerr-patch.py導入)が実MPDの持つ
  コマンド固有の上限チェックを一切持たない不具合。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。実MPD本体(gh rawでsrc/command/ClientCommands.cxxの
  `handle_binary_limit()`を確認)は`args.ParseUnsigned(0,
  client.GetOutputMaxSize() - 4096)`でSIZEをパースし、超過時に
  `ACK_ERROR_ARG(2)`の`Number too large`を送出する。`GetOutputMaxSize()`
  (src/event/FullyBufferedSocket.hxx)はサーバ設定`max_output_buffer_size`
  (デフォルト`CLIENT_MAX_OUTPUT_BUFFER_SIZE_DEFAULT`=8192*1024バイト、
  src/client/Config.cxx)そのもの。実際の上限はデフォルト設定下で
  8192*1024-4096=8,384,512であり、mopidy_mpd側が持つ`protocol.UINT`の
  汎用上限0xFFFFFFFF(4,294,967,295、mpduintmax-patch.py)よりずっと小さい
  コマンド固有の上限。mopidy_mpdのbinarylimit()は下限(64未満)のみ明示
  チェックしており上限側は無いため、8,384,513〜4,294,967,295の範囲の値が
  本来ACKされるべきところ黙ってOKになっていた。BACKLOG.md全体を
  "8384512"/"8388608"/"client_max_output_buffer_size"/"GetOutputMaxSize"で
  検索したが既出無し(既存のbinarylimit項目は下限・非数値引数の
  バリデーションのみを扱っている)。
  修正: `mpdbinarylimitmax-patch.py`。mopidy_mpdにはサーバ設定
  `client_max_output_buffer_size`相当が存在しないため実MPDのデフォルト値を
  ハードコードし、`_MPD_BINARYLIMIT_MAX = 8192 * 1024 - 4096`
  (=8,384,512)をモジュールレベル定数として追加、既存の"Value too small"と
  同じ流儀でlimit超過時に`exceptions.MpdArgError("Number too large")`を
  送出する。
  verified: オフライン検証(`/tmp`へ隔離コピーしパッチ適用、`ast.parse()`で
  構文確認、2回連続適用でも"already patched, skip"で冪等なことを確認)の
  上で、dev mopidyをビルド・起動(mopidy.log新規ERROR/Traceback0件、
  クリーン起動)。実機確認(TCP 6601): `binarylimit 8384512`→OK(境界値)、
  `binarylimit 8384513`/`binarylimit 100000000`/
  `binarylimit 4294967295`→修正前は全てOKだったのが修正後は全て
  `ACK [2@0] {binarylimit} Number too large`に変化。
  `binarylimit 4294967296`(汎用UINT上限超過)は前後で無変更
  (`ACK [2@0] {binarylimit} incorrect arguments`、protocol.UINT自体の
  パース時チェックのまま)。通常利用値`binarylimit 8192`/下限境界
  `binarylimit 64`(OK)/`binarylimit 63`(ACK Value too small、既存
  mpdbinarylimitargerr-patch.pyの挙動)は無変更であることを回帰確認。
  mopidy.log新規ERROR/Traceback0件。

- [x] `mount {PATH} {URI}`(`mopidy_mpd/protocol/mount.py`)が、busy/URI重複/
  URIスキーム未認識の3種のエラーチェックの優先順位を実MPDと逆転させてしまって
  いた不具合。TODO全項目消化済みのため自走エージェントが(general-purpose
  サブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawで`src/command/StorageCommands.cxx`の`handle_mount()`を
  確認)はPATH空/"/"混入→`Bad mount point`、`composite.IsMountPoint(local_uri)`
  (busy)→`Mount point busy`、`composite.IsMounted(remote_uri)`(URI重複)→
  `This storage is already mounted`、`CreateStorageURI(remote_uri)`(スキーム
  認識)→`Unrecognized storage URI`の順でチェックすることを確認(busy/
  already-mountedが先、URIスキーム認識は最後)。
  `mpdmount-patch.py`の元の実装はbusyチェックをURIスキームチェックより先に
  行っていたため実MPDと一致していたが、その後`mpdmounttoctou-patch.py`が
  busy/URI重複チェックを`mount_try_add()`1関数にまとめてアトミックにした際、
  URIスキームチェック("://"の有無)だけがロック外・busyチェックより**先**に
  呼ばれる順序に変わってしまっていた(同patch自身のコメントは「優先順位を
  保った」と主張していたが実際には保たれていなかった)。実害: 既に別スキームで
  使用中のmount pointに対しスキーム無しURIで再mountを試みると、実MPDなら
  `Mount point busy`が返るはずが`Unrecognized storage URI`が返ってしまう。
  修正: `mpdmountorder-patch.py`。`mount_try_add(path, uri, recognized)`に
  第3引数を追加し、単一ロックスコープ内でbusy→uri_used→unrecognizedの順に
  判定してから`_mounts`へ書き込むよう変更(TOCTOU安全性は維持したまま優先
  順位だけ実MPDに合わせた)。
  verified: mpdmountorder-patch.py。オフライン検証(`/tmp`へ隔離コピーし
  パッチ適用、`ast.parse()`で構文確認、2回連続適用でも"already applied,
  skip"で冪等なことを確認)の上で、dev mopidyをビルド・起動(mopidy.log
  新規ERROR/Traceback0件、クリーン起動)。実機確認(TCP 6601): 既に
  `mount "foo" "nfs://192.168.1.4/export/mp3"`済みの状態で同一PATH"foo"へ
  スキーム無しURI"no-scheme-value"を`mount`→修正前は`ACK Unrecognized
  storage URI`のはずが修正後`ACK [2@0] {mount} Mount point busy`(正しい
  優先順位)に変化したことを確認。別PATH"bar"へ既存URIを`mount`→
  `ACK This storage is already mounted`(uri_used、無変更)、`mount ""`/
  `mount "a/b"`→`Bad mount point`(無変更)、新規PATH+スキーム無しURI→
  `Unrecognized storage URI`(無変更、退行なし)、`unmount`/`listmounts`/
  `idle mount`(別接続でmount実行→`changed: mount`起床)/`status`/`tagtypes`
  の回帰なし、mopidy.log clean(0件)を確認。

- [x] `enableoutput`/`disableoutput`(`mopidy_mpd/protocol/audio_output.py`)が、
  要求された有効/無効状態が現在のmute状態と既に同じ(no-op)場合でも常に
  `context.core.mixer.set_mute()`を無条件に呼んでしまい、実際には何も変化して
  いないのに`changed: output`のidle通知が誤って発火する不具合。TODO/既知の
  残課題を全項目消化済みのため自走エージェントが(general-purposeサブエー
  ジェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawで`src/output/OutputCommand.cxx`
  `audio_output_enable_index()`/`audio_output_disable_index()`を確認)は
  `LockSetEnabled(true/false)`が実際に状態を変化させた場合のみtrueを返し
  `partition.EmitIdle(IDLE_OUTPUT)`を発火、状態不変(no-op)なら早期return
  してidleを発火しない。兄弟コマンド`toggleoutput`(`LockToggleEnabled()`)は
  常に状態を反転させるためno-opという概念自体が無く、対象外であることも確認
  済み。
  dev環境が使う`mopidy/audio/actor.py` `SoftwareMixer.set_mute()`は値が
  変わったか無関係に`trigger_mute_changed()`を無条件に呼ぶため、
  `mute_changed`コアイベント経由で`changed: output`が値が全く変化していない
  のに発火してしまっていた。全く同じ根本原因(`SoftwareMixer`の無条件
  `trigger_*_changed`)を`volume`(相対指定)については既に
  `mpdvolumenoopidle-patch.py`が修正済みだが、兄弟コマンドの
  `enableoutput`/`disableoutput`(mute方向)には未対応のまま残っていた。
  BACKLOG.md全体を"enableoutput"/"disableoutput"/"LockSetEnabled"/"no-op"で
  検索し、既存項目(mpdoutputtogglerace/mpdoutputpartition/
  mpdidlemixerpartition)はレース・パーティション所有・パーティション越し
  idle漏れのみを扱っており本件(同一パーティション内でのno-op時のidle抑制)
  は既出無しと確認した。
  修正: `mpdoutputtogglerace-patch.py`が既に追加した`_output_mixer_lock`
  スコープ内で、`set_mute()`呼び出し前に現在のmute状態を確認し、既に要求
  状態と一致するならno-opとして`success = True`とする(実MPDの
  `LockSetEnabled()`と同じ「実際に変化した場合のみ」ガード)。
  verified: mpdoutputnoopidle-patch.py。offline検証(`/tmp`へ隔離コピーし
  パッチ適用、`ast.parse()`で構文確認、2回連続適用でも"already applied,
  skip"で冪等なことを確認)の上で、dev mopidyをビルド・起動(mopidy.log
  新規ERROR/Traceback0件、クリーン起動)。実機確認(TCP 6601、2接続A/B):
  Aで`enableoutput 0`を送り`outputenabled: 1`のベースラインを確立後、Bが
  `idle output`で既存の保留イベントをdrain(点62のドレイン手法)してから
  再度`idle output`で新規購読、Aから同じ`enableoutput 0`(既に有効、真の
  no-op)を送信すると修正前はBが誤って`changed: output`で起床していたはず
  だが修正後はBは起床しない(timeout)ことを確認。対照として同じ購読状態
  からAが実際に状態を変える`disableoutput 0`を送信すると正しく`changed:
  output`でBが起床し`outputs`の`outputenabled`が0に変化することも確認、
  idle配送機構自体が生きていることの裏付けとした。回帰確認: `toggleoutput`
  (常に状態を反転)はB購読中にAが実行すると変更前後で無変更に`changed:
  output`が発火することを確認(no-op概念が無いため対象外どおり)。
  `status`/`tagtypes`/`outputs`の応答内容も無変更、mopidy.log新規
  ERROR/Traceback0件。

- [x] `mopidy_mpd/tokenize.py`の`split()`が1コマンド行あたりの引数トークン
  総数(コマンド名を除く)に一切上限を設けていない不具合。TODO全項目消化済み
  のため自走エージェントが(general-purposeサブエージェントへの調査委任を
  経て)新規発見。
  実MPD本体(gh rawでsrc/command/AllCommands.cxx `command_process()`を確認、
  自分でも生の`AllCommands.cxx`をcurlして`StaticVector<const char*,
  COMMAND_ARGV_MAX> argv`/`argv.full()`/`push_back()`の並びを直接読んで
  再検証)は、トークン抽出成功直後・`push_back()`直前に`argv.full()`を検査
  し、超過していれば(未知コマンド名であっても`command_checked_lookup()`
  より前段のため)即座に`ACK_ERROR_ARG` "Too many arguments"を返す。
  `COMMAND_ARGV_MAX = 2 + TAG_NUM_OF_ITEM_TYPES*2`(src/tag/Type.hxxの
  enum TagTypeを自分で数えて36種と確認)= 74。`src/client/Response.hxx`の
  `command`フィールドはデフォルト空文字列で、`SetCommand()`は
  `command_checked_lookup()`内でのみ呼ばれるため、この検査時点のACKは
  コマンド名の既知/未知を問わず常に`{}`。
  mopidy_mpd側は`tokenize.split()`がPARAM_REで抽出したトークンを
  `result`へ無条件appendし続けるだけで総数上限が無い。
  BACKLOG.md/nix/lib/mopidy-env.nixを"ARGV_MAX"/"Too many arguments"/
  "COMMAND_ARGV_MAX"で検索し既出無しを確認済み、`tokenize.py`を触る
  既存パッチ(mpdauthtabsplit/mpdcmdlisttabsplit/mpdcommandnamecase/
  mpdstrictnumparse/mpdtokenizecommandnone)もいずれもコマンド名の
  字句解析や数値パーサの別軸でありトークン総数は未対応と確認済み。
  修正: `tokenize.py`に定数`_MPD_COMMAND_ARGV_MAX = 74`を追加し、
  `split()`のwhileループでPARAM_REによるトークン抽出成功直後・
  `result.append`直前に`len(result) - 1 >= _MPD_COMMAND_ARGV_MAX`の
  検査を追加(実MPDの`argv.full()`と同じ検査タイミング)。raiseする
  `MpdArgError`は`command=""`を明示指定(`mpdtokenizecommandnone-
  patch.py`と同じ流儀。指定しないと`dispatcher.py`の`tokens[0]`による
  補完は`protocol.commands.call()`を囲むtry節内でのみ動作し
  `tokenize.split()`自体の例外には掛からないため、同ファイルの過去
  バグ"{None}"漏れを再発してしまう)。`mpdargvmax-patch.py`として実装、
  `nix/lib/mopidy-env.nix`に`mpdvpathaddcount-patch.py`直後(mpdPatched
  リスト末尾)で登録。
  verified: 実機(TCP 6601、生ソケット): `status`に引数トークンを
  73個/74個付けると修正前後とも既存の`ACK wrong number of arguments
  for "status"`(0引数コマンドの既存arity検証、無変更)、75個付けると
  修正前は同じくstatusハンドラまで到達し`wrong number of arguments`
  だったのが修正後は`ACK [2@0] {} Too many arguments`に変化(トークン
  化の時点で拒否されるようになったことを確認)。100個でも同様。
  クォート済みトークン(`"a0" "a1" ...`)でも74個OK/75個ACKの境界が同一
  であることを確認。存在しないコマンド名+75個の引数
  (`bogus a0 a1 ... `)は修正前`ACK unknown command "bogus"`だったのが
  修正後`ACK [2@0] {} Too many arguments`に変化(実MPDと同じく引数上限
  超過がコマンド名解決より優先されることを確認)、+10個(上限内)は
  修正前後とも無変更で`ACK unknown command "bogus"`のまま。回帰確認:
  実データでの`find "(Artist == \"YOASOBI\")"`(265行)、
  `findadd`(`status`の`playlistlength`が期待通り反映)、`ping`、
  `clear`、`tagtypes`はいずれも前後で無変更。mopidy.logに新規
  ERROR/Traceback無し、起動もクリーン。オフラインでも
  `tokenize.split()`を直接呼び73/74/75/100トークンで同じ境界
  (73,74→成功、75,100→`MpdArgError("Too many arguments")`,
  `command=""`)を確認済み。

- [x] mpdfindvirtualpath-patch.py が導入した仮想パス→実URIツリー解決
  (`_mpd_resolve_virtual_path_tracks`)は `find` にしか配線されておらず、
  同じ `find "(File starts_with '<仮想パス>')"` スタイルのクエリを
  `findadd`/`searchadd`/`searchaddpl`/`count`/`searchcount` で送ると
  引き続き0曲/0件になる不具合。TODO全項目消化済みのため自走エージェント
  が(general-purposeサブエージェントへの調査委任を経て)新規発見。
  BACKLOG.mdを`grep -n`で"findadd.*virtual""virtual.*findadd"
  "searchadd.*virtual""_mpd_resolve_virtual_path_tracks"等で検索し
  既出・却下記録が無いことを確認済み。`mpdfindvirtualpath-patch.py`
  自身が`find()`以外に一切触れていないことも確認済み。
  原因: `music_db.py`の`findadd()`/`searchadd()`/`searchaddpl()`は各々
  独立して`context.core.library.search(...)`を直接呼び出し、
  `count()`/`searchcount()`が共有する`_mpd_count_grouped()`のungrouped
  分岐も同様。いずれも`find()`が使うようになった
  `_mpd_resolve_virtual_path_tracks(context, negatives, positives)`
  (sole positiveが`uri`/`starts_with`系、negatives無しの場合のみ
  `context.browse(path, recursive=True, lookup=True)`で仮想パスを実URI
  ツリーへ解決)を一切呼ばないため、rmpcのDirectoriesペインが送る
  `find file starts_with`スタイルのクエリで「キューに追加」「プレイ
  リストへ保存」「曲数/再生時間を数える」を行うと常に0件になる。
  修正: `findadd`/`searchadd`/`searchaddpl`の各backend検索呼び出し
  直前、および`_mpd_count_grouped()`のungrouped分岐に、既存の
  `_mpd_resolve_virtual_path_tracks`を同じ形で追加配線(非該当時は
  `None`を返し既存コードパスへ無変更フォールバックするため退行
  リスク無し)。`mpdvpathaddcount-patch.py`として実装、
  `nix/lib/mopidy-env.nix`に`mpdfindvirtualpath-patch.py`直後で登録。
  verified: 実プレイリスト(`YouTube Music/Home/Anime songs/Brand New`、
  1曲)で`clear`→`findadd "(File starts_with '...')"`→`status`が
  修正前`playlistlength: 0`→修正後`playlistlength: 1`、`searchadd`
  (小文字フィールド)も同様、`searchaddpl`後の`listplaylistinfo`が
  修正前0曲→修正後1曲、`count`/`searchcount`が修正前`songs: 0`/
  `playtime: 0`→修正後`songs: 1`/`playtime: 212`に変化することを
  実機(TCP 6601、mopidy-ytmusic実アカウント)で確認。回帰確認:
  通常のタグ検索(`find`/`findadd`/`searchadd`/`count`/`searchcount`
  "(Artist == \"YOASOBI\")")は前後で無変更(5曲、findaddは既存通り
  artist/albumプレースホルダ非含有)、実URIのリテラル前方一致
  (`ytmusic:track:...`の切り詰めprefix)も前後で0件のまま無変更
  (既存の`find()`側フォールバックと同じ挙動、本修正の対象外)、
  mopidy.logに本修正由来の新規ERROR/Traceback無し(既知の
  Liked Songs未サインイン起因/深い仮想パス非決定性起因のエラーのみ、
  いずれも本修正と無関係な既存の環境依存ノイズ)、mopidy起動もクリーン。

- [x] rmpcの Directories ペインでディレクトリを選択して行う一括操作
  (「Save to playlist」「Create playlist」「Add to playlist」「Delete
  from playlist」等)が、mopidy-ytmusicバックエンドでは常に0曲扱いに
  なってしまう不具合。TODO/既知の残課題を全項目消化済みのため自走
  エージェントが(general-purposeサブエージェントへの調査委任を2段階
  経て)新規発見。BACKLOG.mdを`grep -n`で"list_songs_in_item"
  "directories.rs" "Tag::File.*StartsWith" "find file" "Save to
  playlist" "Create playlist"等で検索し既出・却下記録が無いことを確認
  済み。mierak/rmpcを実際に`git clone --depth 1`して確認:
  `rmpc/src/ui/panes/directories.rs`の`list_songs_in_item()`は選択項目が
  ディレクトリ(`playlist: false`)の場合 `client.find(&[Filter::
  new_with_kind(Tag::File, &full_path, FilterKind::StartsWith)])`、つまり
  `find "(File starts_with '<full_path>')"` を発行し、`full_path`は直前の
  `lsinfo`が返した`directory:`行の値をそのまま使う。実MPD(ローカル
  ファイル)では`directory:`の値と`file:`タグの値が同じファイルパス階層
  を共有するためこの前方一致は正しく機能するが、`mopidy_mpd/
  dispatcher.py`の`MpdContext.browse()`(291行目〜)が生成する`path`は
  `"/".join([base_path, ref.name...])`という**表示名から合成した仮想
  パス**(例: `"YouTube Music/Home/Charts/Trending 20 Japan"`)であり、
  mopidy_ytmusicの実`track.uri`(例: `"ytmusic:track:JofSrfFV4Kw"`)とは
  無関係。`music_db.py`の`file`/`filename`タグは`_LIST_MAPPING`/
  `_SEARCH_MAPPING`経由で"uri"フィールドへ写像され、フィルタ判定・
  backend検索とも`track.uri`そのものとの文字列比較になるため、仮想
  パスの前方一致は常に一致せず、`find`は常に0件のOKを返していた
  (`lsinfo`自体は同じパスで実トラックを正しく表示するため、対称的な
  ギャップ)。修正: `music_db.py`の`find()`に、sole positive条件が
  `uri`/`starts_with`(`_cs`/`_ci`含む)かつnegativesが無い場合に限る
  特別扱いを追加。`dispatcher.py`の`MpdContext.browse()`が既に実装
  済みの仮想パス→実URI解決(`_uri_map`キャッシュ、無ければ
  `library.browse()`によるpart-by-part再帰解決)を`context.browse(path,
  recursive=True, lookup=True)`として呼び出し(`listallinfo()`と全く
  同じfuture消費パターン)、配下の実トラックを直接収集して返す。解決に
  失敗した場合(値がそもそも仮想パスとして存在しない、実URIのリテラル
  前方一致等の別用途)は`None`を返し、従来の生文字列前方一致(複合条件
  クエリ含む全経路)へ無変更でフォールバックするため退行リスクが無い。
  `current_playlist.py`(`playlistfind`/`playlistsearch`)や
  `stored_playlists.py`(`searchplaylist`)はbackend検索を呼ばずロード
  済みtracklistをローカルの`_pf_matches()`のみで判定するため本件と無関係、
  対象外。`mpdfindvirtualpath-patch.py`。
  verified: dev mopidy (TCP 6601、mopidy-ytmusic実アカウント) を実際に
  起動しTCP生ソケットで確認。修正前: `lsinfo "YouTube Music/Home/
  Charts/Trending 20 Japan"`(実プレイリスト、20曲)に対し `find
  "(File starts_with 'YouTube Music/Home/Charts/Trending 20 Japan')"`
  → `OK`(0件)。修正後: 同じ`find`が同じ20曲(`file:`のURI集合が
  `lsinfo`と完全一致)を返すことを確認、`window "0:2"`修飾子併用でも
  正しく2曲に絞られることを確認。回帰確認: 存在しない仮想パス
  (`'NoSuchDir/Whatever'`)→`OK`(0件、クラッシュ無し)、複合条件
  クエリ(`"(Artist == 'YOASOBI') AND (File starts_with 'ytmusic:')"`)
  →フォールバック経路のまま従来通りbackend検索結果を返す(無変更)、
  実URIそのものをstarts_with値に使うレガシーな用法
  (`'ytmusic:track:JofSrfFV4Kw'`)→仮想パスとしての解決に失敗し
  従来の生文字列前方一致にフォールバックしその1曲を正しく返すことを
  確認(退行無し)、`find artist "YOASOBI"`(旧形式)・`status`は前後で
  無変更、mopidy.log新規ERROR/Traceback0件。なお、YouTube Musicの
  Home配下の一部セクション(例: "Quick picks"のような複数階層に渡る
  動的レコメンド)は`browse()`呼び出しごとに内容が再生成される既知の
  非決定的挙動(BACKLOG内の他のHome関連項目で既出の制約と同種)があり、
  そのような多階層ディレクトリを未キャッシュの新規接続から直接
  再帰解決しようとすると当該再帰の一部枝が偶発的に0件になり得るが、
  これは本パッチのロジック不備ではなくbackend側データの非決定性に
  起因するもの(実データ・実プレイリストである安定したディレクトリ
  では上記の通り完全一致することを確認済み)。

- [x] `mopidy_mpd/tokenize.py` の `WORD_RE` が、コマンド名の2文字目以降に
  大文字を一切許容しない (`[a-z][a-z0-9_]*`) ため、`"sTatus"`/`"pIng"` の
  ように先頭は小文字だが途中に大文字を含む行が、コマンド名として一切
  トークナイズされず `split()` が `MpdUnknownError("Invalid word
  character")` を投げてしまう不具合。TODO/既知の残課題を全項目消化済みの
  ため自走エージェントが(general-purposeサブエージェントへの調査委任を
  経て)新規発見。BACKLOG.md を `WORD_RE`/`tokenize.py`/`Invalid word
  character`/大文字 で grep して重複無しを確認(`mpdtokenizecommandnone-
  patch.py` は同じ2箇所の raise を対象にしているが、command引数省略に
  よる `command=None` 漏れというまったく別の不具合を修正したもので、
  `WORD_RE` 自体の文字クラスは未修正のまま残っていた)。
  `mopidy_mpd/session.py` の `on_line_received()` は行頭1文字のみを
  `line[0].islower() and line[0].isalpha()` でガードしており(実MPD本体の
  `IsLowerAlphaASCII(*line)` と一致、この部分は正しい)、2文字目以降は
  素通しで `dispatcher` 経由 `tokenize.split()` に渡る。
  実MPD確認: gh raw で `src/util/Tokenizer.cxx` を取得すると、
  `valid_word_first_char(ch) = IsAlphaASCII(ch)`、
  `valid_word_char(ch) = IsAlphaNumericASCII(ch) || ch == '_'`
  (`src/util/CharUtil.hxx` の `IsAlphaASCII`/`IsAlphaNumericASCII` は
  大文字・小文字どちらも真)であり、`Tokenizer::NextWord()`
  (`src/command/AllCommands.cxx` の `command_process()` が呼ぶ) は
  `"sTatus"` のトークナイズ自体には成功する。その後
  `command_checked_lookup()` の `command_lookup()`
  (大文字小文字を区別する `strcmp` ベースの検索) が一致せず、
  `r.FmtError(ACK_ERROR_UNKNOWN, "unknown command {:?}", cmd_name)` を
  `r.SetCommand()` より前に呼ぶため、`command` フィールドは既定の空文字列
  のまま `ACK [5@0] {} unknown command "sTatus"` を返す。
  修正: `WORD_RE` のコマンド名文字クラスの2文字目以降を `[a-zA-Z0-9_]` に
  拡張(1文字目は `[a-z]` のまま維持)。`mpdcommandnamecase-patch.py`。
  verified: TCP 127.0.0.1:6601 の生ソケットで確認。修正前
  `sTatus\n`/`pIng\n`/`tagTypes\n` → `ACK [5@0] {} Invalid word
  character`。修正後は `ACK [5@0] {} unknown command "sTatus"` 等
  (実MPDと同じ文言・`{}` 空フィールドも実MPDの `SetCommand()` 呼び出し
  順と一致)。回帰確認: 通常の小文字コマンド (`status`/`ping`/`tagtypes`/
  `find "(Artist == \"YOASOBI\")"`) は無変更で正常応答、行頭空白 (`"
  status\n"`)・全大文字開始 (`"STATUS\n"`) は既存の `session.py` ガード
  により従来通り接続切断、`st$tus\n` (WORD_RE非マッチ文字) は従来通り
  `ACK [5@0] {} Invalid word character` のまま無変更。事前にオフライン
  単体テスト(`/tmp` へ isolated copy した `tokenize.py` を直接 import)
  でも regex/split() の挙動を確認済み。mopidy起動クリーン、
  mopidy.log 新規 ERROR/Traceback 0件。

- [x] `mopidy_mpd/dispatcher.py` の `MpdDispatcher._authenticate_filter()` が、
  パスワード認証有効時 (`[mpd] password` 設定時) に未認証の接続が「存在しない
  コマンド名」を送った場合、実MPDなら本来返すべき `ACK_ERROR_UNKNOWN`
  ("unknown command") ではなく、常に `ACK_ERROR_PERMISSION` ("you don't have
  permission for ...") を誤って返してしまう不具合。TODO/既知の残課題を全項目
  消化済みのため自走エージェントが(general-purposeサブエージェントへの調査
  委任を経て)新規発見。同じ関数・同じブロックを対象にした
  `mpdauthtabsplit-patch.py`(コマンド名抽出がタブ区切りをすり抜ける不具合)
  は既出だったが、それとは別軸の「抽出したコマンド名がハンドラテーブルに
  無いときの分類」問題は未記載だった(BACKLOG.md を
  `_authenticate_filter`/`MpdPermissionError`/`unknown command`/
  `ACK_ERROR_UNKNOWN`/`command_checked_lookup`/`AllCommands.cxx` で grep して
  重複無しを確認)。
  現状コード: `command = protocol.commands.handlers.get(command_name)` が
  `None`(未知コマンド)を返す場合も `if command and not command.auth_required`
  が False になり、無条件で `else` 節の `MpdPermissionError` に落ちる —
  「未知コマンドかどうか」と「権限があるかどうか」を区別しない。
  実MPD確認: gh raw で `src/command/AllCommands.cxx` の
  `command_checked_lookup()` を直接取得すると、`command_lookup(cmd_name)` が
  `nullptr`(未知コマンド)なら即座に `ACK_ERROR_UNKNOWN`("unknown command")
  を返し、権限チェック(`command_check_request`、`ACK_ERROR_PERMISSION`)は
  その後にしか行われない。`src/protocol/Ack.hxx` でも
  `ACK_ERROR_PERMISSION=4`/`ACK_ERROR_UNKNOWN=5` は別コード。mopidy_mpd自身も
  認証後の未知コマンド判定には正規の `exceptions.MpdUnknownCommand`
  (`protocol/__init__.py`)を既に持っており、今回のギャップは「未認証時のみ」
  これを使わず `MpdPermissionError` に丸め込んでしまっている非対称。
  修正: mpdauthunknown-patch.py。「存在確認 → 権限確認」の順に分離
  (`command is None` なら `MpdUnknownCommand`、存在するが `auth_required`
  なら従来通り `MpdPermissionError`)。`nix/lib/mopidy-env.nix` に
  `mpdauthtabsplit-patch.py` の直後として登録(同じ関数を対象にした唯一の
  他パッチで、編集する行が別行のため衝突無し)。
  verified: `ast.parse`で構文確認、独立コピーへのパッチ適用で idempotent
  (2回目は skip) であることを確認。実機確認(TCP 6601):
  `~/ai/mopidy-dev/mopidy-dev.conf` の `[mpd]` に一時的に
  `password = authunknowntest` を追加して `build-run.sh` で実ビルド・実起動し、
  修正前後を比較。**パッチ前**: 未認証で未知コマンド `boguscmd123` を送ると
  `ACK [4@0] {boguscmd123} you don't have permission for "boguscmd123"`
  (バグ再現)。**パッチ後**: 同じ入力が
  `ACK [5@0] {} unknown command "boguscmd123"` に変化。回帰確認: 未認証の
  既存コマンド `status`(`auth_required=True`)は引き続き
  `ACK [4@0] {status} you don't have permission for "status"`、
  `ping`/`commands`(`auth_required=False`)は引き続き正常応答、
  `password "authunknowntest"` → `OK` 後は `boguscmd123` が(認証後の既存
  `MpdUnknownCommand` 経路と同じ)`ACK [5@0] {} unknown command
  "boguscmd123"` に、`status` も正常応答、誤ったパスワード
  (`password "wrongpass"`)は引き続き `ACK [3@0] {password} incorrect
  password`。テスト後 `mopidy-dev.conf` を元の(password未設定)状態に戻し
  再ビルド・再起動し、通常運用時(パスワード認証無効、常時 authenticated)の
  `status`/`boguscmd123` が引き続き正常応答(`boguscmd123` は
  `ACK [5@0] {} unknown command "boguscmd123"`)することを確認。
  mopidy起動時・全テスト中とも mopidy.log に ERROR/Traceback 0件を確認した。

- [x] `playlistlength {NAME}` (mpdplaylistlength-patch.py で実装済み) が返す
  `playtime` フィールドが `int(total_length / 1000)` で常に切り捨てになって
  いる不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  mpdplaylistlength-patch.py 自身の検証ログ(2977-2981行目付近)は
  「実MPDと同じ切り捨て、count/statsと同じ丸め規約」と結論づけていたが、
  これは実際には `src/playlist/Length.cxx` を確認せずに書かれた誤った
  結論だった。gh raw で実際に `src/playlist/Length.cxx`
  (`playlist_provider_length()`) を取得して確認すると、
  `playtime += get_duration(*song)` でミリ秒精度に積算した後
  `std::chrono::round<std::chrono::seconds>(playtime)` で最近接秒への丸め
  (四捨五入、tie-breakはround-half-to-even) を行っている。一方 `count`/
  `searchcount`/`stats` が使う `src/db/Count.cxx` は
  `std::chrono::duration_cast<std::chrono::seconds>(...)` で切り捨てており、
  実MPD内部でも playlistlength と count系とで丸め規約は非対称(兄弟コマンドの
  丸め規約が一致するという過去の思い込みが誤りだった一例)。BACKLOG.md 全体を
  "playtime"/"round"/"duration_cast" 等で検索したが本件は既出無し。
  修正: mpdplaylistlengthround-patch.py。`int(total_length / 1000)`
  (切り捨て) を `round(total_length / 1000)` (最近接丸め、Python組み込み
  round も tie-break が round-half-to-even で実MPDの std::chrono::round と
  同じ規約) に変更するのみ。count/stats側 (mpdcount-patch.py/
  mpdstats-patch.py) は実MPDのCount.cxx同様の切り捨てのままで正しいため無変更。
  verified: mpdplaylistlengthround-patch.py。`ast.parse`で構文確認、
  isolated `/tmp` コピーへパッチ適用しfileが `round(total_length / 1000)`
  に変わること・2回適用しても冪等(スキップ)であることを確認。オフライン検証:
  デプロイ済みの実ソースから `"playtime", ...` 式を実際に正規表現抽出し
  `eval()` で直接実行(再実装ではなく出荷コードそのものをテスト) —
  `total_length=468500`→`468`、`468501`→`469`、`469500`→`470`、
  `469501`→`470`(いずれも旧`int()`切り捨てと異なる結果になり、
  real MPDのround-half-to-even規約と一致)を確認。実機確認(TCP 6601、
  mopidy-ytmusic実アカウント): `playlistadd`で2曲(Time: 207秒/214秒、
  実測ms値 207000/214000)を追加した実プレイリストに対し
  `playlistlength`→`songs: 2`/`playtime: 421`(207+214と一致、mopidy_ytmusic
  backendは常にYouTube Music APIの秒単位長さを1000倍したミリ秒値を返す
  ため実データでは丸めと切り捨ての差が現れない既知の環境制約 — 上記
  オフライン検証で規約自体の正しさを担保)。存在しないプレイリスト名→
  `ACK No such playlist`、引数無し→`ACK wrong number of arguments`
  ともに無変更、`status`/`tagtypes`の回帰なし、mopidy.log新規ERROR/
  Tracebackはplaylistadd新規作成時の既知のytmusicapi HTTP 401
  (pre-existing、mpdplaylistlength-patch.py検証時にも確認済み)のみ。

- [x] lsinfo/listall/listallinfo/listfiles がルート以外のディレクトリを
  ブラウズしたとき、mopidy_ytmusic backend が `Ref.playlist(...)` として
  埋め込む「YouTube Music の各ホーム/Auto Playlistsセクション内のプレイリスト
  項目」を、実MPDでは `playlist: NAME` として返すべきところ常に
  `directory: NAME` として返してしまう不具合。
  mpdbrowseplaylist-patch.py で修正。dispatcher.py の browse() が
  非TRACK refのうち `ref.type == ref.PLAYLIST` の場合だけ falsy な区別可能
  マーカー(空タプル `()`。`bool(())` は False で既存の `not lookup_future`
  等の判定は無変更のまま `== ()` で判別可能)を yield するよう変更し、
  music_db.py の listall()/listallinfo()/listfiles()/lsinfo() 側でこの
  マーカーを見て `("playlist", path)` を出す分岐を追加。
  verified: `~/ai/mopidy-dev/build-run.sh` でビルド・起動(mopidy-ytmusic
  実アカウント、"YTMusic loaded 5 auto playlists sections"のログを確認)し、
  生ソケット(TCP 6601)で `lsinfo "YouTube Music/Auto Playlists/Summer 🏖"`
  を実行。修正前は全項目が `directory: ...` だったが、修正後は実データの
  埋め込みプレイリスト10件全てが `playlist: YouTube Music/Auto
  Playlists/Summer 🏖/Summer J-Pop (...)` のように正しく `playlist:` へ変化
  したことを確認。回帰確認: (1) 通常ディレクトリ `lsinfo "YouTube
  Music/Artists"` は前後で無変更(`directory:` のまま、空リストでもOK応答)。
  (2) 変化したプレイリストの内部へさらに `lsinfo` で再帰ブラウズすると
  従来通り `file: ytmusic:track:...` + タグ情報700行が返り、
  library.browse()での再帰列挙(recursive=Trueの既存動作)が壊れていない
  ことを確認。mopidy.log に新規ERROR/Traceback無し。listall/listallinfo
  はdev環境設定で無効化されているため直接確認は不可だったが、lsinfoと同一の
  browse()経路・同一パターンの分岐追加のためコードレビューで整合性を確認済み。

- [x] find/search/count/findadd/searchadd/searchaddpl/playlistfind/playlistsearch/
  searchplaylist が共有するフィルタ式パーサが、複合式全体を否定する
  `(!( LEAF1 AND LEAF2 ... ))`(ド・モルガンの法則 NOT(A AND B))を認識できず、
  否定が黙って消えて肯定条件 (`A AND B`) として扱われてしまう不具合。TODO/
  既知の残課題を全項目消化済みのため自走エージェントが(general-purpose
  サブエージェントへの調査委任を経て)新規発見した項目。mpdnegexpr-patch.py
  が実装した `_neg_wrap` 検出は、クオート値を含むリーフ自身の直前の `(` の、
  さらに直前1文字だけを見て `!` かどうか判定するため、`(!((A) AND (B)))`
  のように `!` とリーフの間に複合式自身の `(` が1つ余分に挟まる場合、各
  リーフの `_neg_wrap` は常に False のままになり否定が完全に無視される。
  BACKLOG.md 全体を `_neg_wrap`/`!(` で検索したが、mpdnegexpr-patch.py 自身の
  既存テストは各リーフが個別に `!` を持つ形 (`((A) AND (!(B)))`) のみで、
  複合式全体を1個の `!` でラップする形は未検証・未修正と確認した。
  verified: mpdnegcompound-patch.py。実機確認(TCP 6601、mopidy-ytmusic実
  アカウント、YOASOBI「怪物」で確認)で、修正前は
  `find "((Artist == \"YOASOBI\") AND (!((Title contains \"怪物\") AND
  (Artist == \"YOASOBI\"))))"` が、否定なしの
  `find "((Artist == \"YOASOBI\") AND ((Title contains \"怪物\") AND
  (Artist == \"YOASOBI\")))"` と全く同じ1件(「怪物」のみ)を返してしまう
  ことを確認(本来は NOT(both) が真になる残り21件が返るべき)。修正:
  NOT(A AND B) は「A と B が両方真になったら除外」と等価であり OR を一切
  追加せずに表現できることを利用し、`_query_from_mpd_filter_expression` の
  メインループ前に `!(` の出現位置を走査、対応する閉じ括弧までの中身を
  「同じ関数への再帰呼び出し」(`require_positive=False`) でパースし、中身が
  単一リーフ(positives 1件)なら既存の `_neg_wrap` ロジックにそのまま委ね
  (ゼロ変更、回帰リスクを避ける)、複数リーフ(AND、positives 2件以上)なら
  その範囲を空白でマスクした上で `kind="and_group"` の negative として
  まとめて登録する。中身の再帰パースが negatives を返す場合(`!=`/`!~`や
  入れ子の `!(...)` が混在し NOT(A AND NOT B) 相当のより複雑な論理になる
  ケース)は誤った結果を静かに返すより安全側に倒し `ACK incorrect
  arguments` にする(スコープ外、既知の境界として明示)。新ヘルパ
  `_mpd_group_all_match`(music_db.py)/`_pf_group_all_match`
  (current_playlist.py、searchplaylistも共有)を新設し、`_mpd_track_
  matches_positives`が持つgenre/track_no/date等のbackendベストエフォート
  信頼バイパス(単独条件時continue)を適用せず常に実値で判定するようにした
  (バイパスを適用すると否定グループの文脈では常にTrue=常に除外になり
  不正確なため)。current_playlist.py側は実際のキュー優先度(priority
  引数)を使う点がmusic_db.py側(DB検索文脈のため常に0扱い)と非対称
  (mpdprio-patch.py以来の既知の非対称)。実機確認: `find`で上記の修正後
  21件(「怪物」を含む1件が正しく除外される)を確認、`playlistfind`/
  `playlistsearch`でも実キュー(YOASOBI検索結果5曲: 怪物/勇者/アイドル/
  群青/夜に駆ける)に対し同型のクエリで「怪物」のみが正しく除外され残り
  4曲が返ることを確認。単一リーフの否定(`!(Title == "怪物")`、既存
  mpdnegexpr-patch.py機能)は修正前後で結果不変(回帰なし)。入れ子否定
  (`!((Title != "怪物") AND (Artist == "YOASOBI"))`)は設計通り`ACK
  incorrect arguments`になることを確認(スコープ境界、サイレントな誤りを
  避けるための意図的な安全側動作)。回帰確認: 通常の複合AND(否定なし)、
  `base`/`window`/`sort`修飾子、`count group artist group album`
  (mpdcountsinglegroup-patch.py既存のACK)、`list album group artist`、
  `prio`、`tagtypes`、`status`はいずれも修正前後で結果不変。mopidy.log に
  新規ERROR/Traceback 0件、mopidy が正常に起動し続けることを確認。既知の
  境界: 複合否定式のみが単独で存在し他に一切条件が無い場合
  (`find "(!((A) AND (B)))"` 単体)は `require_positive` チェックが
  negatives の有無を見ないため `ACK incorrect arguments` になるが、これは
  単一リーフの否定単体も修正前から同じ理由でACKになる既存の(本パッチ範囲
  外の)境界であり新たな回帰ではない。

- [x] (誤検出・対応不要と判明) `searchplaylist()`が`_pf_matches()`呼び出しで
  `strip_diacritics`を渡していないのは不具合ではなく実MPD仕様通りと判明。
  verified: 前回記録時点では「`playlistsearch`と同様に`stringnormalization
  enable strip_diacritics`を適用すべき」という前提だったが、実MPD本体ソース
  (MusicPlayerDaemon/MPD, WebFetchで直接取得)を確認した結果、この前提が誤りと
  判明した。`src/command/PlaylistCommands.cxx`の`handle_searchplaylist()`は
  `filter.Parse(args, true)`(第3引数`strip_diacritics`省略、
  `src/song/Filter.hxx`で全`Parse`オーバーロードが`strip_diacritics=false`を
  デフォルト値として宣言)のみで`StringNormalizationEnabled`を一切参照しない。
  対して`src/command/QueueCommands.cxx`の`handle_playlistsearch()`
  (`playlistsearch`コマンド、current_playlist.pyの`_pf_search`に相当)は
  `auto strip_diacritics = client.StringNormalizationEnabled(SN_STRIP_DIACRITICS);`
  で明示的に取得し`Parse`へ渡している——`searchplaylist`(ストアドプレイリスト検索)と
  `playlistsearch`(現在再生キュー検索)は実MPDでも意図的に非対称。さらに
  mpd.readthedocs.ioのprotocolドキュメントも`stringnormalization`の説明を
  「searchコマンド使用時」限定と明記し`searchplaylist`には触れていない。
  `searchplaylist()`のdocstring「case insensitively, like with search」は
  `fold_case=true`(大文字小文字を区別しない)という一致挙動のみを指しており、
  diacritics除去は含意しない。よって現状のmopidy_mpd実装(strip_diacritics未配線)は
  既に実MPD準拠であり、コード変更は行わない
  (mpdsearchplaylist-patch.py冒頭コメントの「StringNormalizationEnabledは
  PlaylistCommands.cxxでは参照されない」という既存の調査結果とも整合)。

### mopidy-mpd プロトコル (認証不要でテストしやすい・優先)
- [x] `seekcur {TIME}` (相対 `+`/`-` 修飾込み) に非数値の TIME (`seekcur "abc"` 等) を
  渡すと `mopidy_mpd/protocol/playback.py` の `seekcur()` 内で手動パースしている
  `protocol.FLOAT(time)`/`protocol.UFLOAT(time)` が素の `ValueError` を送出し、
  捕捉されずに MPD セッションが切断されてしまう不具合 (サーバ本体は生存、
  当該コネクションのみ切断)。他の類似コマンド (`seek`/`seekid` は
  `@protocol.commands.add(..., seconds=protocol.UFLOAT)` のようにデコレータの
  引数バリデータとして宣言しているため、フレームワーク側の `validate()`
  (`mopidy_mpd/protocol/__init__.py`) が `ValueError` を捕捉し
  `ACK incorrect arguments` に変換する) と違い、`seekcur` は `time` の型宣言が
  無く関数本体で手動パースしているためこの保護を受けられない。
  mpdseekcurstop-patch.py (`seekcur` の停止中ガード) の実機検証中に副産物として
  発見 (自走エージェントによる新規発見)。
  verified: mpdseekcurargerr-patch.py。`+`/`-` 相対か絶対かを関数冒頭で判定し
  `protocol.FLOAT`/`UFLOAT` によるパースを一本化した上で try/except し、
  `ValueError` を `seek`/`seekid` と同じ `exceptions.MpdArgError("incorrect
  arguments")` に変換 (停止中ガード `_MpdSeekCurPlayerSyncError` は実MPDの
  「引数検証がハンドラ本体より先」という慣行に合わせパースの後・
  `core.playback.seek()` 呼び出しの前で判定、パース自体はstateに依存しないため
  順序を入れ替えても停止中ガードの効果は不変)。パッチ適用後の生成ソースは
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`に mpdseekcurstop-patch.py の直後に登録しビルド成功、
  生成ソースに新実装が反映されていることを確認した上で dev mopidy(6601,
  ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  (1)停止中`seekcur "abc"`/`seekcur "+abc"`→ともに
  `ACK [2@0] {seekcur} incorrect arguments`となりセッション切断されず、続く
  `status`も正常応答 (旧実装ならここで素の`ValueError`によりコネクションが
  切断されていた)。(2)停止中`seekcur "5"`(有効な数値)→従来通り
  `ACK [55@0] {seekcur} Not playing`(パース成功後に停止中ガードへ到達する順序を
  確認)。(3)`seek "0" "abc"`(既存の decorator バリデータ経由)が引き続き
  `ACK [2@0] {seek} incorrect arguments`となる回帰なしを確認。
  (4)実再生中の回帰確認: `findadd "(any contains \"yoasobi\")"`→`play "0"`→
  `seekcur "10"`(絶対)→`OK`かつ`status`の`elapsed`が10.000に反映、
  `seekcur "+2"`(相対)→`OK`かつ`elapsed`が12.052に反映、続けて
  `seekcur "abc"`→`ACK [2@0] {seekcur} incorrect arguments`となり
  `state: play`/`elapsed`は直前の値のまま無変更・コネクションは生存
  (`stop`まで正常継続)。mopidy.logにTraceback/ERROR新規発生なしを確認。
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
- [x] `mopidy_mpd/network.py` の `LineProtocol.encode()` が `UnicodeError` (対になっていない
  UTF-16サロゲート単体文字、例 `"\ud83d"` を含む文字列を `str.encode("utf-8")` しようと
  すると発生する `UnicodeEncodeError`。このサブクラス) を捕捉した際、`self.stop()`
  (pykka.ThreadingActor自身への非同期停止要求で、この関数の実行自体は中断させない) を
  呼ぶだけで関数は暗黙に `None` を返す設計になっている。ところが呼び出し元の
  `send_lines()` はこの戻り値をNoneチェックせず `self.connection.queue_send(
  self.encode(data))` とそのまま渡しており、`Connection.queue_send(None)` は
  `self.send_buffer + data` で `bytes + NoneType` の素の `TypeError` を送出する。
  これは `mopidy_mpd/dispatcher.py` の `except exceptions.MpdAckError` の外側
  (network層、`decode()`/`encode()`と対称関係にあるはずの送信経路) で発生するため
  未捕捉のまま pykka actor の失敗パス (`on_failure()`) まで伝播し、本来意図されていた
  「警告ログを出して静かに切断」(`decode()`側は`on_receive()`が既に
  `if line is not None: self.on_line_received(line)` で対称にNoneガード済み) が
  意図せぬクラッシュ経由の切断にすり替わってしまう。加えて `Connection.queue_send()`
  自体は `self.send_lock.acquire(True)` の後 try/finally 無しで
  `self.send_buffer = self.send(...)` しているため、この `TypeError` 発生時
  `send_lock.release()` に到達せず Lock が held のまま残る。TODO/既知の残課題を
  全項目消化済みのため自走エージェントが(サブエージェントに調査を委任した上で)
  mopidy_mpd のコード品質を再調査して新規発見した項目。踏む条件は、search/find/
  playlistinfo/currentsong/lsinfo等どのレスポンスであれ、フィールド値(mopidy_ytmusic
  のスクレイピング結果由来のタイトル/アーティスト名等、外部データにサニタイズ無しで
  依存)に対になっていないサロゲート単体文字が1文字でも混入していること。
  verified: mpdencodeguard-patch.py。(1) `send_lines()` で `encode()` の戻り値を
  変数`encoded`に受け、`None`なら`queue_send()`を呼ばずに何もしない(`self.stop()`は
  `encode()`内で既に呼ばれ済みのため二重に切断処理する必要は無い)。(2) `queue_send()`
  自体にも`data is None`の早期リターンガードを追加(将来Noneを渡す呼び出しが増えても
  安全)、`send_lock.release()`をtry/finallyで保護しLock解放を保証
  (mpdstickersqlerr-patch.py等の「ロックは必ず解放する」流儀)。パッチ適用後の
  生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)
  であることも確認。`nix/lib/mopidy-env.nix`にmpdaddidrawuriguard-patch.pyの直後に
  登録しビルド成功、生成ソースに新実装が反映されていることを確認。
  **修正前後の差分の実証**: ビルド前後2つのenv(pre-fix/post-fix)それぞれの
  `mopidy_mpd/network.py`を直接importし、対になっていないサロゲート単体文字を含む
  文字列に対して`LineProtocol.encode()`→`Connection.queue_send()`を直接呼び出す
  比較スクリプトを実行 — pre-fixは`queue_send(encode()の戻り値)`が
  `TypeError: can't concat NoneType to bytes`を送出しかつ`send_lock`がheldのまま
  残ることを確認、post-fixは例外を送出せず`send_lock`も解放されていることを確認。
  **実ソケット・実pykka actorでのエンドツーエンド実証**: 同じ2つのenvそれぞれの
  実際の`mopidy_mpd.network.Connection`/`LineProtocol`を、GLibメインループを実際に
  起動した状態で実TCPソケット越しに動作させるecho用テストハーネスを構築し、
  正常な行(`"hello"`)がそのままechoされることを確認した上で、サーバ側の
  `on_line_received()`へ対になっていないサロゲート単体文字を含む文字列を直接
  投入 — pre-fixは`actor call raised: True TypeError("can't concat NoneType to
  bytes")`、post-fixは`actor call raised: False None`となり、いずれも
  `self.stop()`により意図通りconnectionは最終的に停止する(`connection.stopping`=True、
  actor is_alive=False)ものの、post-fixはこれが意図されたクリーンな停止経路のみを
  通ることを実証。dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  `tagtypes`/`status`/`stats`/`search artist "YOASOBI"`/`list album`/`count any "a"`/
  `listplaylists`が全て正常応答し、直後の`status`も正常応答(コネクション生存)で
  回帰なし、mopidy.logにTraceback/ERROR 0件、クリーンな起動(回帰なし)を確認した。

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
- [x] Liked Songs: ytmusicapi 1.12.1 が get_liked_songs で失敗する件を、別エンドポイント/パースで回避
  verified: ytliked-patch.py。実データで再現・ログのトレースバックで根本原因を特定 —
  get_liked_songs() (=get_playlist("LM")) 自体は成功しているが、Liked Songs プレイリスト内に
  ポッドキャストのエピソード等の非音楽アイテムが含まれていると ytmusicapi の
  parse_playlist_items (ytmusicapi/parsers/playlists.py、"Non music videos, for example:
  podcast episodes" 分岐) が artist_index を解決できず `"artists"` キーは存在するが値が
  None のまま返る。mopidy_ytmusic.library.playlistToTracks() 側は `if "artists" in track:`
  とキー存在しか見ておらず、値が None のまま `for a in track["artists"]:` に突入し
  `TypeError: 'NoneType' object is not iterable` でクラッシュ、`lsinfo` が丸ごと空応答になる
  不具合を確認 (修正前ログで実証済み)。修正: キー存在チェックを `track.get("artists")` の
  真偽値チェックに変更し、値が None/空でも同関数内の既存フォールバック経路
  (elif "byline" / else: artists=None、他の分岐で既に使われている安全な経路) に自然に
  流れるようにした。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `lsinfo "YouTube Music/Liked Songs"` → 約90曲全曲が例外なく返り、Artist情報が無い
  アイテム(東京事変のアップロード曲、ポッドキャスト由来と見られる非音楽アイテム含む)も
  Title のみで正常に列挙されクラッシュしない、mopidy.log に Traceback 0件を確認
  (修正前は同じ操作で TypeError の Traceback が出ていた)。旧来の `search any`/`list album`/
  `tagtypes`/`lsinfo "YouTube Music/Recently Played"` の回帰なし・Traceback 0 を確認
  (history 取得も同じ playlistToTracks を共有するため同種の非音楽アイテムに対して
  同様に頑健になっている)。
- [x] Recently Played (history): get_history 失敗を回避して Recently Played を出す
  verified: パッチ不要 — 調査の結果、`ytmusic:history` は現行の mopidy_ytmusic (nixpkgs
  mopidy-ytmusic 0.3.9 + 既存パッチ) で既に正常動作していると確認。ytmusicapi 側の
  `get_history()` (mixins/library.py) は履歴ページの各セクションが `musicShelfRenderer` を
  持たない場合に `musicNotifierShelfRenderer` のメッセージで `YTMusicServerError` を送出する
  実装だが、`_send_request("browse", {"browseId": "FEmusic_history"})` を直接叩いて生応答を
  検証したところ実アカウントの履歴は3セクション(47/41/111件)とも全て `musicShelfRenderer`
  を持ち例外は発生しない。またこの backlog 項目は Liked Songs の
  `TypeError: 'NoneType' object is not iterable` (artists=None で playlistToTracks が
  クラッシュ) と同種の懸念で先回りして追加されていたが、history も同じ
  `playlistToTracks()` を共有するため既存の ytliked-patch (`track.get("artists")` 化) で
  既に同様に頑健化済みと判明。dev mopidy (6601, ytmusic 実アカウント、mopidy-dev.conf に
  `enable_history = true` を追加して起動) を実際に起動し MPD で確認 —
  `lsinfo "YouTube Music/Recently Played"` → 199件 (47+41+111と一致) 全曲が例外なく
  `file:`/Time/Artist/Title 等を伴って返り `OK` で正常終了、mopidy.log に ERROR/Traceback
  0件。一部アイテムで `Artist: 2.6M views` のような誤ったアーティスト表記が見えるが、これは
  history 固有の不具合ではなく既存の別 backlog 項目「検索結果のアーティスト表記が
  "Song" 等になる件の是正」と同根の ytmusicapi パース品質の問題で対象外。旧来の
  `search any`/`tagtypes`/`status` の回帰なし・Traceback 0 を確認。
- [x] 検索結果のアーティスト表記が "Song" 等になる件の是正 (parseSearch の filter=None 品質)
  verified: ytartist-patch.py。原因調査のため一時的にparseSearchの生resultをログ出力して
  実データ(米津/YOASOBI検索)で再現・特定 — ytmusicapi の
  `parse_song_runs(runs, skip_type_spec=True)` は "Song • ..." 等の resultType 表記を
  スキップする際「表記の直後(index 2)が本物のアーティスト run である」ことを要求するが、
  無リンクの曲で subtitle が "Song • 3:23" のように duration が resultType 表記の直後へ
  すぐ続くケース(実データで確認: "UNDEAD"/"セブンティーン"等の単曲、"THE BOOK for,"の
  アルバム)ではこの条件が成立せず、表記そのもの(`{"name": "Song", "id": None}` /
  `{"name": "Album", "id": None}`)が唯一のアーティストとして誤って返る。mopidy_ytmusic の
  parseSearch はこれをそのまま Artist 化していたため、rmpc の検索結果で
  `Artist: Song` / `AlbumArtist: Song` / `Artist: Album` のような誤表記になっていた。
  対策: song/album 両分岐の `for a in result["artists"]:` で、id が None かつ名前が
  既知の resultType 表記 (song/video/album/single/ep/episode/podcast/station/playlist/
  profile、小文字比較) と一致する要素を除外 (残った本物のアーティストは従来通り反映、
  全滅した場合はアーティスト無しとして空 — 誤った名前を出すよりは正しい)。
  パッチ済み env の dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  修正前は `search any "yoasobi"` で "THE BOOK for," アルバムに `Artist: Song` /
  `AlbumArtist: Song`、単曲 "UNDEAD"/"セブンティーン" に `Artist: Song` が付いていたのが、
  修正後は該当行が正しく消え(Artist行なしでその他のTitle/Time等は維持)、実アーティストが
  取れているもの(YOASOBI等)は従来通り正しく表示されることを確認。`search any "米津"` でも
  同様に誤った Artist 行が消え、Kenshi Yonezu の正当な行は維持。`search artist "YOASOBI"`
  (アーティスト自体の検索・関連アルバム一覧、YOASOBI/Ayase/Lilas 等)、`tagtypes`、
  `count any "yoasobi"`、`list album` の回帰なし・Traceback 0 を確認。
- [x] `ytmusic:home` を深いページまで (get_home の continuation) 取得
  verified: home-patch.py (既存パッチを改良)。ytmusicapi 1.12.1 の `get_home(limit=N)` の実装を
  ソース確認 (`get_continuations`) — continuation は「初回ページの取得件数が既に limit 以上」
  だと `limit - len(home)` が非正になり、while 条件 `len(items) < limit` が最初から偽になるため
  1回も継続取得が起きずに終わる仕組みと判明。従来の home-patch.py は `get_home(limit=5)` を
  呼んでいたが、実アカウントの初回ページは6セクションあり limit(5)を初回だけで超えるため
  continuation が一切発火せず、常に最初のネイティブページしか見えていなかった (「深いページ」が
  存在するのに取得されない不具合)。修正: limit を 100 に上げ、初回ページ超過後も
  `limit - len(home)` が十分大きな正の値になるようにして continuation ループを実際に走らせるように
  した (limit=None ではなく暴走防止のため実用上十分大きい有限値に留めた)。dev mopidy(6601,
  ytmusic 実アカウント) を実際に起動し MPD で確認 — 修正前 `lsinfo "YouTube Music/Home"` は
  6件 (Listen again/Music videos for you/Shows for you/Forgotten favorites/Quick picks/
  Trending songs for you) だったのが、修正後は12件 (上記6件に加え Your shows/Mixed for you/
  Fresh finds, old favorites/お気に入り音楽/Vocaloid/From the community が新規出現、
  continuation で取得した深いページ由来)。新規に出現したセクションも
  `lsinfo "YouTube Music/Home/Mixed for you"` (楽曲一覧)・
  `lsinfo "YouTube Music/Home/Fresh finds, old favorites"` (プレイリスト一覧)・
  `lsinfo "YouTube Music/Home/お気に入り音楽"` (Mix系プレイリスト一覧) 等いずれも
  例外なく正しい種別 (Ref.track/Ref.playlist) でブラウズ可能なことを確認。旧来の
  `search any "yoasobi"`/`list album`/`tagtypes`/`status` の回帰なし・Traceback 0 を確認。
- [x] アルバム/プレイリストのブラウズ時にトラックのアート(get_images)を確実に載せる
  verified: ytimages-patch.py。原因調査の結果、albumToTracks() は末尾で addThumbnails(bId, album)
  を呼び album の thumbnails を各トラックの videoId にも複製して self.IMAGES に積んでいるため
  アルバム経由のトラックは既に get_images() でヒットしていたが、playlistToTracks()
  (ytmusic:playlist:* のブラウズ、Liked Songs、Recently Played、Similar to last played が共有)
  は ytmusicapi の各トラック dict に既に含まれている "thumbnails" (parse_playlist_item が
  per-track で積んでいる) を一切見ておらず self.IMAGES に何も登録しないため、get_images() は
  track.album が無いと空、album があっても毎回 get_album() を追加で叩く非効率な経路にしか
  ならないと判明。オフライン単体テストで実証: 合成トラック(album=None、thumbnails=2件)を
  修正前/修正後の両 library.py に対し playlistToTracks() へ直接投入し比較 —
  修正前は self.IMAGES にキー登録されず(get_images相当が空になる不具合を再現)、修正後は
  ["https://.../large.jpg"(500x500), ".../small.jpg"(60x60)] の順(addThumbnailsと同じ大きい順)
  で正しく登録されることを確認。対策: playlistToTracks で各トラックを初めて登録する際に
  track["thumbnails"] を追加API呼び出し無しで self.IMAGES[videoId] へキャッシュ。
  パッチ済み env の dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `lsinfo "YouTube Music/Liked Songs"` の全95曲(album無しの曲を含む)に対し
  `albumart URI 0` を実行し 95/95 で実JPEGデータ取得(修正前は album 無しの曲で空になっていた
  不具合をオフラインテストで実証済み)、`lsinfo "YouTube Music/Recently Played"` の先頭15曲も
  15/15 albumart 取得、album付きトラック(`readpicture`/`albumart` 双方)・`search any "yoasobi"`
  の検索結果1件目、いずれも正常にJPEGバイト列を返す。旧来の `list album`(get_distinct 経由の
  albumToTracksパス)・`lsinfo "YouTube Music/Home"`(12件、深いページ含む継続取得)・`status`
  の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。

- [x] `subscribe`/`unsubscribe`/`channels`/`readmessages`/`sendmessage` (client-to-client messaging):
  mopidy-mpd 3.3.0 の `mopidy_mpd/protocol/channels.py` は5コマンド全て `raise MpdNotImplemented`
  のスタブ。rmpc本体 (mierak/rmpc) を実際にcloneして調査したところ、CLIサブコマンド
  `rmpc sendmessage <channel> <text>` (rmpc/src/config/cli.rs `Command::SendMessage`、
  rmpc/src/core/command.rs で `client.send_message()` を実際に呼び出す) が存在し、
  `sticker`/`mount`/`listmounts` 等と同じ「rmpc CLIサブコマンドとして実在するがバックエンドが
  未実装」パターンに該当する新規ギャップとして発見・追加。TODO 全項目消化済みのため
  自走エージェントが新規発見。
  verified: mpdchannels-patch.py。実 MPD (MusicPlayerDaemon/MPD の
  src/command/MessageCommands.cxx / src/client/Subscribe.cxx / src/client/Message.cxx) を
  実際にcloneしてソース確認し、チャンネル名検証 (`^[A-Za-z0-9:._-]+$`、unsubscribeは
  検証せず存在確認のみ)・エラーコード (ACK_ERROR_ARG/EXIST/NO_EXIST)・idle
  `subscription`/`message` イベント発火条件を確定。translator.py に session id
  (`id(context.session)`) をキーにした購読チャンネル集合/未読メッセージの揮発性ストアを
  追加し、idle通知は actor.py の `send_idle` と同じ `mopidy.listener.send(session.MpdSession,
  subsystem)` (pykka `.tell()` 経由でスレッドセーフ) を再利用。session.py に `on_stop` を
  追加し接続切断時に購読/メッセージを破棄 (実MPDの `Client::UnsubscribeAll` 相当)。
  status.py の `SUBSYSTEMS` に `message`/`subscription` を追加し bare `idle` でも拾うように
  した。dev mopidy(6601, ytmusic実アカウント) を実際に起動し、2本のTCP接続(A/B)で
  MPDプロトコルを直接叩いて確認 — `channels`(空)→OK、A `subscribe "foo"`→OK、B
  `channels`→`channel: foo`、A再度`subscribe "foo"`→`ACK already subscribed to this
  channel`、`subscribe "bad name!"`→`ACK invalid channel name`、B
  `sendmessage "foo" "hello world"`→OK、A `readmessages`→`channel: foo`/
  `message: hello world`、再度`readmessages`→空(消費済み)、購読者0人の channel への
  `sendmessage`→`ACK nobody is subscribed to this channel`、A `unsubscribe "foo"`→OK、
  再度`unsubscribe`→`ACK not subscribed to this channel`、`channels`→再び空。idle実測:
  A `idle message`後にBが`sendmessage`→Aが`changed: message`で起床し`readmessages`で
  正しく取得、bare `idle`(引数無し)でもBの`subscribe`で`changed: subscription`起床を確認。
  切断クリーンアップ実測: Aを切断後`channels`が正しく空に戻ることを確認(on_stopでの
  破棄が機能)。旧来の `search any`(sort+window併用)/`list album`/`count any`/`crossfade`/
  `status`/`sticker get`(既存の no such sticker 応答)の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
  既知の制約(下記項目で解消済み): 実MPDは`message`idleイベントを「新規に受信した購読者のみ」に
  個別配送するが、この実装はidle通知を全接続セッションへブロードキャストしていた
  (readmessagesは各自の未読分のみ返すため機能的には正しいが、無関係なセッションが稀に
  余分に起こされうる)。
- [x] `message` idleイベントが実MPD仕様(受信した購読者のみへ個別配送)に反し、無関係な
  全接続セッションへブロードキャストされていた件の是正 (上記 `sticker set`/`delete` の
  idle未発火バグ修正・`prio`のTOCTOUレース修正と同種の、TODO全項目消化後にレビューで
  自走エージェントが再発見した既知の制約の解消)。
  verified: mpdchannels-patch.py を改良。実 MPD (src/client/Message.cxx) の仕様確認は
  当該項目の初版実装時に既に完了済み (「新規に受信した購読者のメッセージキューが空から
  非空になった、その購読者のみ」に個別配送) だったが、初版はその仕様を実装しきれず
  `mopidy.listener.send(session.MpdSession, "message")` で全セッションへブロードキャスト
  していた。mopidy_mpd の `MpdSession` は pykka.ThreadingActor のサブクラスで、コマンド
  実行中の `context.session` は当該アクター自身のインスタンス (同一スレッド内での実行)
  であるため `context.session.actor_ref` を同期的に取得可能と判明。これを利用し、
  `subscribe` 時に session_id に紐づけて actor_ref を translator.py の揮発性ストア
  (`_channel_actor_refs`) に保存、`sendmessage` は `channel_push_message()` が返す
  「実際にメッセージを受け取ったセッションの actor_ref 一覧」だけに対して
  `pykka.messages.ProxyCall` を直接 `.tell()` する `_mpdchannels_notify_targeted()` で
  個別通知するよう変更 (`subscription` イベントは実MPD (`idle_add(IDLE_SUBSCRIPTION)`)
  同様に全セッションへのブロードキャストが正しい仕様のため無変更)。パッチ済み env の
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、4本のTCP接続 (A/B/C/D) で
  MPDプロトコルを直接叩いて確認 — Aが`subscribe "foo"`、Bが`subscribe "bar"`、Cは無購読の
  状態で全員が bare `idle` 待機中、Dが`sendmessage "foo" "hello A"` → 実際の受信者Aのみが
  `changed: message`で起床し、無関係なB(別チャンネル購読)・C(無購読)は3秒待っても
  起床しないことを確認 (修正前は3者とも起床していたはずの状態からの改善)。複数購読者への
  正配送も確認: A/B双方が同一チャンネル`multi`を購読した状態でCから送信 → 両者とも
  正しく`changed: message`で起床。`readmessages`での取得内容・`subscribe`の不正名/二重購読
  エラー・`channels`一覧・`unsubscribe`の未購読エラー・`sendmessage`の購読者0人エラー
  (旧来の全エラー系統)は無変更で回帰なし。切断クリーンアップ実測: 購読済み接続を切断後、
  別接続からの`channels`が空に戻り`sendmessage`が正しく`ACK nobody is subscribed`に戻る
  ことを確認 (actor_ref も含め session.py の on_stop 経由 channel_cleanup で破棄される)。
  旧来の`tagtypes`/`status`/`listmounts`/`listpartitions`/`outputs`/`getvol`/`crossfade`/
  `decoders`/`commands`/`urlhandlers`の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mount`/`unmount`/`listmounts` (mounts and neighbors section): mopidy-mpd 3.3.0 の
  `mopidy_mpd/protocol/mount.py` は4コマンド全て `raise MpdNotImplemented` のスタブ。
  mpdchannels-patch.py 自身のコメントで「sticker/mount/listmounts 等と同じ『rmpc CLI
  サブコマンドとして実在するがバックエンドが未実装』パターン」と名指しされていた
  ギャップで、実際に rmpc 本体 (mierak/rmpc) を clone して確認したところ
  `rmpc mount <name> <path>` / `rmpc unmount <name>` / `rmpc listmounts` の3つの
  CLIサブコマンド (rmpc/src/config/cli.rs Command::Mount/Unmount/ListMounts、
  rmpc/src/core/command.rs で client.mount()/unmount()/list_mounts() を実際に呼ぶ) が
  存在すると確認。TODO 全項目消化済みのため自走エージェントが新規発見・追加した項目
  (`listneighbors` は rmpc 側に送信箇所が無いため対象外・未着手のまま)。
  verified: mpdmount-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/StorageCommands.cxx handle_mount/handle_unmount/handle_listmounts) を
  実際にcloneしてソース確認し仕様を確定 — PATHが空/"/"を含む→`ACK Bad mount point`、
  PATHが既にマウント済み(チェックはURIチェックより先)→`ACK Mount point busy`、
  URIが既に別PATHにマウント済み→`ACK This storage is already mounted`、成功時は
  idle "mount" イベント発火。translator.pyにprio/crossfadeと同じ流儀でモジュール
  レベルの揮発性ストア(path->uri)を追加 (channelsの購読と異なりセッション単位では
  なく実MPD同様サーバー全体で共有、cleanup不要)。status.pyのSUBSYSTEMSに"mount"を
  追加。パッチ済み env の dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で
  確認 — `listmounts`(空)→OK、`mount "foo" "nfs://192.168.1.4/export/mp3"`→OK、
  `listmounts`→`mount: foo`/`storage: nfs://...`、同じPATHへ再`mount`→
  `ACK Mount point busy`(URIチェックより先にPATHチェックが効くことを確認)、別PATHで
  同一URIを`mount`→`ACK This storage is already mounted`、`mount "" "..."`(空PATH)/
  `mount "a/b" "..."`(スラッシュ入りPATH)→`ACK Bad mount point`、
  `mount "baz" "bogus"`(スキーム無しURI)→`ACK Unrecognized storage URI`、
  `unmount "foo"`→OK・`listmounts`→再び空、再度`unmount "foo"`→
  `ACK Not a mount point`、`unmount ""`→`ACK Bad mount point`。idle実測: 別接続で
  `idle mount`後に`mount`実行→`changed: mount`で起床、bare `idle`(引数無し)でも
  `unmount`で`changed: mount`起床を確認。旧来の `tagtypes`/`status`/`search any`/
  `list album`/`count any`/`crossfade`/`sticker get`/`channels` の回帰なし・
  mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: mopidy core 自体は実 MPD の CompositeStorage のような nfs://・smb:// 等
  任意ネットワークストレージを実行時にマウントする機構を持たず、mopidy core はパッチ
  対象外のため、mount で登録したURIが実際にブラウズ可能なディレクトリとして現れる
  ことはない (crossfadeが実際の再生に影響しないのと同種の限界。プロトコル層の往復・
  エラー応答・idle通知の互換性のみを提供)。
- [x] `partition`/`listpartitions`/`newpartition`/`delpartition`/`moveoutput` (partition
  commands section): mopidy-mpd 3.3.0 は5コマンドとも mount.py のようなスタブすら
  存在せず未登録 (`ACK unknown command`)。mpdmount-patch.py 自身のコメントで名指しされて
  いた「rmpc CLIサブコマンド/グローバルアクションとして実在するがバックエンドが未実装」
  パターンの延長で、実際に rmpc 本体 (mierak/rmpc) を clone して確認したところ、
  rmpc-mpd/src/mpd_client.rs の send_switch_to_partition/send_new_partition/
  send_list_partitions/send_delete_partition/send_move_output が rmpc/src/ui/mod.rs の
  `GlobalAction::Partition` (パーティション切替・新規作成メニュー、キーバインド可能) と
  rmpc/src/ui/modals/outputs.rs (出力を別パーティションへ移すメニュー) から実際に呼ばれ、
  `status` の `partition` フィールドも rmpc-mpd/src/commands/status.rs で常時パースされ
  メニュー表示判定に使われている実害ある新規ギャップと判明。TODO 全項目消化済みのため
  自走エージェントが調査して新規発見・追加した項目。
  verified: mpdpartition-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/PartitionCommands.cxx, src/protocol/IdleFlags.cxx) を実際にcloneして
  ソース確認し仕様を確定 (partitionは名前検証なし・存在チェックのみ、newpartition/
  delpartitionは英数字+`-`/`_`のみ許可、idleサブシステム名は"partition"、moveoutputの
  idleは"partition"でなく"output"、等)。mount/crossfade (mpdmount-patch.py/
  mpdcrossfade-patch.py) と同じ流儀で、パーティション一覧・出力の所属パーティションを
  translator.py の揮発性ストアに保持 (mopidy core は複数パーティション独立再生や複数出力を
  持たずパッチ対象外のため、プロトコル層の状態保持のみ)。パーティション割当は channels.py の
  購読と同じくセッション単位 (id(context.session)) で保持し、切断時に session.py の
  on_stop (mpdchannels-patch.py が追加済み) へ partition_cleanup を追加。status.py の
  SUBSYSTEMSに"partition"を追加、`status`応答に`partition`フィールドを追加。パッチ済み
  env の dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、2本のTCP接続で MPD
  プロトコルを直接叩いて確認 — `listpartitions`(初期)→`partition: default`のみ、
  `newpartition "bad name!"`→`ACK bad name`、`newpartition zone1`→OK、再度→
  `ACK name already exists`、`delpartition default`→`ACK cannot delete the default
  partition`、`delpartition bogus`(不存在)→`ACK no such partition`、`partition bogus`
  (切替、不存在)→`ACK partition does not exist`、A `partition zone1`→OK・`status`→
  `partition: zone1`、AがzoneA1に居る状態でB `delpartition zone1`→`ACK partition still
  has clients`、Aが`partition default`で離脱後→`delpartition zone1`成功・
  `listpartitions`から消滅。`moveoutput bogus`(不存在出力)→`ACK No such output`、
  `moveoutput Mute`(既に現パーティション所属、no-op)→OK。出力のみ残すケース:
  zoneYへ`moveoutput Mute`後クライアントだけ`partition default`で離脱→
  `delpartition zoneY`→`ACK partition still has outputs`(クライアント起因の先勝ち
  チェックと分離して確認)、出力も戻してから削除→成功。idle実測: 別接続で
  `idle partition`後に`newpartition`→`changed: partition`で起床、`idle output`後に
  `moveoutput`→`changed: output`で起床(partitionでなくoutputである点も確認)。切断
  クリーンアップ実測: zoneWへ`partition`で切替後、TCP接続をshutdown+closeし4秒待って
  別接続から`delpartition zoneW`→クライアント参照が消えて正常に成功(session.pyの
  on_stopが機能)。旧来の`tagtypes`/`status`(single/consume oneshot含む)/
  `search any sort`/`getvol`/`playlistid`/`crossfade`/`outputs`/`channels`/
  `listmounts`/`sticker get`の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: mopidy core は audio_output.py の単一仮想出力("Mute", outputid 0)しか
  持たないため、moveoutputで所属パーティションを変えても実際の音声出力に実効果は無い
  (mountで登録したURIが実際にブラウズ可能にならないのと同種の限界。プロトコル層の
  往復・エラー応答・idle通知・status.partitionの互換性のみを提供)。
- [x] `decoders`: mopidy-mpd 3.3.0 は `return  # TODO` で常に何も返さない (OKのみ)。TODO 全項目
  消化済みのため自走エージェントが rmpc 本体 (mierak/rmpc) を実際に clone して調査したところ、
  キーバインド 'op' (`GlobalAction::ShowDecoders`) で開く "Decoder plugins" モーダル
  (rmpc/src/ui/modals/decoders.rs) が `client.decoders()` の結果 (plugin/mime_types/suffixes
  の3列テーブル) をそのまま描画する実装で、クラッシュはしないが常に空のモーダルになる実害ある
  新規ギャップと判明。
  verified: mpddecoders-patch.py。実装方針の検討で mopidy の実再生パイプライン (GStreamer
  playbin) が本当に使える decoder plugin を live 問い合わせできないか調査 —
  `nix-store -q --requisites` で mopidy パッケージの closure に gst-plugins-base/good/bad/ugly
  + gst-libav が実在すると確認した一方、パッチ済み env の実プロセスで
  `Gst.Registry.get().get_feature_list(Gst.ElementFactory)` を直接叩いたところコア組込み要素
  24個のみでコーデック別プラグインは0件 (GST_PLUGIN_PATH相当がこの構成の実行時に配線されて
  おらず自動では埋まらないため) と判明し、ライブ introspection では実装前と同じく空になる
  ことを確認。そのため mount/partition/outputs plugin と同じ「プロトコル層の応答を仕様に
  合わせるだけで実体は静的」方針とし、上記 closure に実在するプラグイン (flac/vorbis/opus/
  wavparse/wavpack/isomp4/matroska/libav) を静的に列挙する実装にした (libav は mp3/aac/wma/ac3
  等ffmpeg経由の多数コーデックの代表としてまとめて1エントリ)。パッチ済み env の
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 — `decoders` →
  上記8プラグイン×suffix/mime_typeを実MPD仕様の順序 (plugin行の直後にsuffix/mime_type行が
  続くグループ形式、rmpc の `FromMpd for Decoders` パーサ実装と同じ "plugin" キーで新グループ
  開始する解釈に一致) で列挙、同一セッション内で2回連続 `decoders` を叩いても同一応答
  (副作用なし)。旧来の `search any sort+window併用`/`list album group`/`count any`/
  `sticker get`(no such sticker応答)/`listmounts`/`listpartitions`/`channels`/`outputs`
  (plugin列維持)/`getvol`/`commands`(decodersが一覧に追加されている)/`tagtypes`/
  `notcommands`/`urlhandlers` の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: 実際にこの環境で GStreamer のプラグインレジストリが実行時に codec プラグインを
  検出できているかは別問題で未検証・未解決 (今回の調査で判明した副次的な観測。decoders
  コマンド自体は「プロトコル応答が仕様通りの形になっているか」のみを保証するもので、実際の
  デコード可否を保証するものではない。mount/crossfade 等と同種の限界であり本item のスコープ外)。
- [x] `status` の `lastloadedplaylist` (MPD 0.24+、直近に `load` したストアドプレイリスト名):
  mopidy-mpd 3.3.0 の status.py は一切このフィールドを返さない。実 MPD
  (MusicPlayerDaemon/MPD src/command/PlayerCommands.cxx / src/playlist/PlaylistQueue.cxx /
  src/queue/Queue.cxx) を実際にcloneしてソース確認したところ、`load NAME` 成功時に
  queue へ名前を記録し `clear` でのみリセットされる (個々の add/delete では消えない)、
  `status` は毎回無条件に1行返す仕様と判明。rmpc 本体 (mierak/rmpc) を実際にcloneして
  調査したところ rmpc-mpd/src/commands/status.rs が実際にパースし、
  rmpc/src/core/event_loop.rs の `reflect_changes_to_playlist` 機能 (config で有効化すると
  ロード中のストアドプレイリストへの編集を自動 save する) がこの値の前後比較で動作条件を
  判定しており、未対応のままだとこの機能が一切発火しない実害あるギャップと判明。TODO
  全項目消化済みのため自走エージェントが調査して新規発見・追加した項目。
  verified: mpdlastloadedplaylist-patch.py。crossfade/prio (mpdcrossfade-patch.py/
  mpdprio-patch.py) と同じ流儀で translator.py にモジュールレベルの揮発性ストアを追加し、
  `load` 成功時に設定・`clear` でリセット・`status` で無条件に反映する実装。dev
  mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で実データを使って確認 — 初期状態
  `status` → `lastloadedplaylist: `(空)、実トラックをキューに積み `save "LLPTest"` で
  ストアドプレイリスト作成 (save 自体は lastloadedplaylist を変更しないことを確認)、
  `load "LLPTest"` → OK・以後 `status` → `lastloadedplaylist: LLPTest`、その状態で
  `add` (キュー追加) しても `lastloadedplaylist` は維持されたまま (個々の add では消えない
  実MPD仕様通り)、`clear` → `status` → `lastloadedplaylist: `(空に復帰)、存在しない
  プレイリストの `load "NoSuchPlaylist12345"` → `ACK No such playlist`・status は
  無変更 (空のまま) を確認。旧来の `tagtypes`/`list album`/`search any sort`/
  `count any`/`crossfade`/`getvol`/`listplaylists`/`rm` の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認 (`save` 実行時に mopidy_ytmusic 側の create_playlist が
  このテストアカウントの書き込み権限不足で HTTP 401 を出すログが1件あるが、これは
  mopidy core の PlaylistsController.create() が複数バックエンドを順に試す既存の
  仕組みに由来する `save` コマンド自体の pre-existing な挙動であり、本パッチが触れていない
  save の経路かつ最終的に m3u バックエンド側で正常に作成されているため今回のリグレッション
  ではない)。

- [x] `sticker find` の拡張構文 (比較演算子 `=`/`<`/`>`/`eq`/`lt`/`gt`/`contains`/`starts_with`、
  および `sort`/`window` 修飾) 未対応: mpdsticker-patch.py の `sticker()` は
  `action, field, uri, name=None, value=None` の固定引数で、基本形
  `sticker find TYPE URI NAME` しか受け付けない。TODO 全項目消化済みのため自走エージェントが
  rmpc 本体 (mierak/rmpc) を実際に clone して調査したところ、`rmpc-mpd/src/mpd_client.rs`
  の `send_find_stickers` が `StickerFindOptions{filter, sort, window}` から
  `sticker find song URI NAME [OP VALUE] [sort TYPE] [window START:END]` を組み立てて送信し、
  実際に (1) `rmpc/src/ui/panes/search/mod.rs` の検索ペインの評価(rating: eq/gt/lt int比較)・
  お気に入り(liked: eq int比較)フィルタ、(2) `rmpc/src/ui/panes/recently_played.rs` の
  「最近再生」ペイン (sort value_int/value + window でページング) の両方で実際に使われている
  実害ある新規ギャップと判明 (固定引数のため余分なトークンを送ると
  `ACK wrong number of arguments` になり、これらの機能が丸ごと失敗する)。musicpd.org
  protocol docs と実 MPD (MusicPlayerDaemon/MPD src/command/StickerCommands.cxx
  handle_sticker) を実際にcloneしてソース確認し仕様を確定 (文字列比較 `=`/`<`/`>`、整数比較
  `eq`/`lt`/`gt`、`contains`/`starts_with`、sort は `uri`/`value`/`value_int` のみ、window は
  他コマンドと同じ `START:END`)。
  verified: mpdstickerfind-patch.py。mopidy_mpd の `Commands.add()` が「`*args` は固定引数と
  併用不可」のため、`sticker(context, action, field, uri, name=None, value=None)` を
  `find`/`playlistfind` と同じ `def sticker(context, *args)` に書き換え、action ごとに
  手動で引数を切り出す方式に変更 (list/get/set/delete は挙動不変、find のみ拡張)。window は
  mpdwindow-patch が music_db.py に用意した `_mpd_parse_window` を import して再利用。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても
  冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し
  MPD で確認 — `sticker set song "test:N" rating "5"` 等でテストデータ投入した上で:
  `sticker find song "" rating`(演算子無し、旧来どおり)→全件、`sticker find song "" rating
  gt "2"`→rating>2のみ、`sticker find song "" like eq "2"`→整数一致、`sticker find song ""
  rating lt "3"`→整数未満、`sticker find song "" rating sort -value_int`→降順、`sticker find
  song "" rating sort value_int window "0:2"`→ソート後に2件スライス、`gt "0" sort -value_int
  window "0:2"`(演算子+sort+window併用)→正しく絞り込み・ソート・ページング、`sticker find
  song "" note contains "hello"`/`starts_with "good"`/`= "hello world"`(文字列演算子)→
  それぞれ正しく部分一致・前方一致・完全一致。エラー系: `badop`(未知演算子)→`ACK Unknown
  sticker operator: badop`、`sort bogus`(未知sortタイプ)→`ACK Unknown sort type: bogus`、
  `window "a:b"`(不正window)→`ACK Invalid window: a:b`、`gt`のみ(値欠落)→`ACK incorrect
  arguments`、`sticker find song ""`(NAME欠落)→`ACK incorrect arguments`。旧来の `sticker
  get`/`list`/`delete`(基本形)は無変更で回帰なし、`sticker list song URI extra`(余分な
  トークン)は以前は黙って無視されていたのが `ACK wrong number of arguments` になる変更が
  入ったが、これは実 MPD (StickerCommands.cxx `args.size() == 3` 厳密一致) によりむしろ
  正しい挙動であることをソースで確認済み。実データ(YOASOBI検索結果)で `tagtypes`/`list
  album`/`list Album group AlbumArtist`/`search any "yoasobi"`/`search any "yoasobi" sort
  -Date window "0:2"`/`count any`/`status`/`crossfade`/`getvol`/`listplaylists`/`channels`
  の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] Recently Played (last-played タイムスタンプ): 上記 `sticker find` の sort/window が
  実際に機能するには、曲再生ごとに last-played 系のスティッカーを自動更新する仕組みが
  mopidy 側に必要かどうかの調査 (rmpc 本体は最終的にどのスティッカー名を読むか
  `rmpc/src/ui/panes/recently_played.rs` の `sticker: String` 設定元を確認すること)。
  mopidy_mpd がスティッカーを自動更新する機構を持たないなら対象外 (rmpc 側でCLI経由や
  ユーザ操作で書き込む前提の可能性もあるため要調査、`sticker find` 拡張の実装後に着手)。
  verified: パッチ不要・調査の結果、対象外(mopidy_mpd 側の実装は一切不要)と確定。
  rmpc 本体 (mierak/rmpc) を実際に clone してソース確認したところ、
  `rmpc/src/ui/panes/recently_played.rs` の `StickerPane` は `sticker`/`sort`/`limit` を
  すべて `rmpc/src/config/tabs.rs` の `PaneTypeFile::Sticker { sticker: String, ... }` から
  ユーザ設定として受け取る汎用ペインで、rmpc 自身は "recently played" 用の固定スティッカー名を
  一切ハードコードしていない。かつ `rmpc-mpd/src/mpd_client.rs`/`client.rs` 全体を grep しても
  `sticker set` を送信する箇所は存在せず (`send_sticker`(get)のみで write 系は皆無)、rmpc/rmpc-mpd
  本体はスティッカーの書き込みを一切行わない=読み取り専用と判明。決め手は rmpc 本体
  CHANGELOG.md の該当項目本文 (v0.9系, "Added `Sticker` browser pane...") — 「このスティッカーは
  外部で追跡される必要がある。例えば rmpcd-lastplayed プラグイン
  (https://github.com/rmpc-org/rmpcd-lastplayed) 経由で」と明記されており、公式に
  「サーバー側(mopidy_mpd)ではなく外部クライアントが書き込む」設計であることが確定した。
  実際に rmpc-org/rmpcd-lastplayed 本体 (rmpcd の Lua プラグイン) の `lastplayed.lua` を
  clone してソース確認 — `song_change`/`state_change`/`shutdown` フックで経過再生時間を追跡し、
  曲が変わるかシャットダウンする瞬間に標準の `sticker set song {uri} lastPlayed {unix時刻}`
  (mpd.set_song_sticker) を送るだけの、mopidy 側に一切変更を要求しない完全に独立した
  常駐 MPD クライアント (rmpcd、rmpc 本体とは別プロセス) であることを確認。つまり実 MPD 自体も
  スティッカーを自動更新する機構を持たず(スティッカーは汎用KVストアで書き込みは常にクライアント
  側の責務)、mopidy_mpd がこれに倣うのは正しい設計であり、必要な受け皿 (`sticker set`/`sticker
  find ... sort value_int/-value_int ... window ...`) は既存の mpdsticker-patch.py /
  mpdstickerfind-patch.py で全て実装・検証済みであることを再確認した。
  念のため rmpcd-lastplayed が実際に送る操作列を dev mopidy(6601, ytmusic 実アカウント) で
  再現し MPD で確認 — 実データ(YOASOBI検索結果3曲)に `sticker set song URI lastPlayed
  "<unixtime>"` を時刻をずらして3件投入 → `sticker find song "" lastPlayed sort -value_int
  window "0:2"` → 最新2件が新しい順(降順)で正しく返る(rmpc の
  `StickerSort::ValueIntDesc`+`window`と同じ組み合わせ)、`sticker get song URI lastPlayed` →
  該当値を取得、`sticker list song URI` → 反映確認、後片付けの `sticker delete` → OK。
  `tagtypes`/`status` の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。

- [x] `add {URI} [POSITION]`: mopidy-mpd 3.3.0 の `add` は `uri` のみの固定引数で
  POSITION を一切受け付けない (実 MPD 0.23+ の `add {URI} [POSITION]`、絶対/相対
  `+N`/`-N` は未対応)。TODO 全項目消化済みのため自走エージェントが mopidy_mpd の
  `raise MpdNotImplemented` スタブ (mixrampdb/mixrampdelay/replay_gain_mode/
  listfiles/rangeid/addtagid/cleartagid/clearerror) と mount.py の listneighbors を
  調査したが、rmpc 本体 (mierak/rmpc) を実際に clone してソース確認したところ
  いずれも rmpc 側から一切送信されない (rmpc-mpd のクライアントtraitに定義は
  あるが呼び出し元が皆無、または元々 rmpc に機能自体が存在しない) 死んだギャップと
  判明。代わりに rmpc-mpd/src/mpd_client.rs send_add を確認したところ、既存の
  addid の POSITION 対応 (mpdaddid-patch.py) と対になる `add URI POSITION` を
  実際に送信していると判明。実害を特定: rmpc/src/config/keys/actions.rs の
  `Position::AfterCurrentSong => QueuePosition::RelativeAdd(0)` /
  `Position::BeforeCurrentSong => QueuePosition::RelativeSub(0)` がキーバインド
  可能な「現在の曲の次に追加/前に追加」アクションとして実在し、`client.add(uri,
  position)` 経由で `add URI "+0"`/`add URI "-0"` を送る。また `rmpc add` CLI
  サブコマンドやダウンロードファイルのキュー追加 (rmpc/src/core/command.rs,
  rmpc/src/ui/modals/downloads.rs) でも同じ POSITION 付き `add` を送信する。
  mopidy-mpd の固定引数実装では余分なトークンが `ACK wrong number of arguments`
  になり、これらの機能が丸ごと失敗する実害あるギャップと確認した上で追加した項目。
  verified: mpdaddpos-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/QueueCommands.cxx handle_add / src/command/PositionArg.cxx
  ParseInsertPosition) を実際にcloneしてソース確認し仕様を確定 — 位置解決ロジックは
  addid の相対位置 (+N/-N、現在曲基準) と同一だが、`add` はディレクトリ等で複数曲を
  再帰的に追加しうるため、実 MPD は「常に末尾へ追加してから、要求位置が末尾より
  手前ならその追加された範囲だけをまとめて move する」実装 (MoveRange) になっている
  ことを確認。mopidy core の `tracklist.move(start, end, to_position)` が同じ
  「範囲を切り出してから to_position に挿入」セマンティクスを持つため、それを使って
  同アルゴリズムを移植 (URI一括ではなく既存の scheme直接追加/browse再帰追加の分岐は
  無変更のまま、末尾に追加後、POSITION指定時のみ move)。POSITION 未指定時は解析
  スキップで従来通り末尾追加のみ (無変更)。パッチ適用後の生成ソースは一時コピーに
  当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。dev
  mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で実データ(YOASOBI検索結果の
  track URI)を使って確認 — 絶対位置 `add URI "1"`(3曲キューの中間へ挿入)→
  該当位置に正しく挿入され後続曲がシフト、キューが空(現在曲なし)で相対指定
  `add URI "+0"`/`add URI "-0"` → `ACK [55@0] {add} No current song`、3曲キュー+
  `play "1"`(pos1を実際に再生開始、`status`のstate:play/song:1で確認)の状態で
  `add URI "+0"`→現在曲の直後(pos2)に挿入され後続がシフト、`add URI "-0"`→現在曲の
  直前に挿入され現在曲が1つ後ろにシフト(`status`のsong:が1→2に変化、songidは
  不変=同じ曲が再生継続していることを確認)、境界値超過 `+999`/`-999`→
  `ACK [2@0] {add} Number too large`、絶対位置の範囲外 `add URI "999"`→
  `ACK [2@0] {add} Bad song index`、非数値 `add URI "abc"`→
  `ACK [2@0] {add} incorrect arguments`。POSITION省略時の従来動作(URIがアルバム等で
  browse経由で複数曲を再帰追加、末尾へ通常追加)も無変更で回帰なし。旧来の
  `addid`(POSITION付き含む)・`tagtypes`・`list album`・`search any sort+window併用`・
  `count any`・`crossfade`・`getvol`・`listplaylists`・`sticker get`・`channels`の
  回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: `mixrampdb`/`mixrampdelay`/`replay_gain_mode`/`listfiles`/`rangeid`/
  `addtagid`/`cleartagid`/`clearerror`/`listneighbors`(mount.py)は、rmpc 本体
  (rmpc-mpd/src/mpd_client.rs, rmpc/src/config/keys/actions.rs, rmpc/src/core/
  command.rs 全体を実際に grep して呼び出し元皆無と確認)から一切送信されないため
  対象外・未着手のまま (listneighbors と同じ「クライアントtraitに定義はあるが
  死んでいる」パターン)。
- [x] MPD protocol の greeting (`OK MPD {VERSION}`) が mopidy-mpd 3.3.0 のまま常に
  固定文字列 "0.19.0" (mopidy_mpd/protocol/__init__.py の VERSION 定数、session.py が
  そのまま送信)。TODO 全項目消化済みのため自走エージェントが rmpc 本体
  (rmpc-mpd/src/mpd_client.rs, rmpc/src/ui/mod.rs, rmpc/src/core/command.rs) を実際に
  clone して調査したところ、`client.version()` (greetingから実際にパースした値) で
  複数の機能をバージョンゲートしていると判明: `send_get_volume`(getvol) は
  `version < 0.23.0` で送らずクライアント側エラー、`send_consume` の Oneshot 指定は
  `version < 0.24.0` で同様、`ToggleSingle`/`ToggleConsume` (rmpc/src/ui/mod.rs,
  rmpc/src/core/command.rs) は `version < 0.21.0`/`< 0.24.0` だと oneshot を含まない
  on/off の2値サイクルにフォールバックし oneshot へは一切遷移しない。つまり
  mpdgetvol-patch.py (getvol, MPD 0.23+) と mpdoneshot-patch.py (single/consume
  oneshot, MPD 0.21+/0.24+) はサーバー側では実装・プロトコル単体テストでは検証済みなのに、
  VERSION が "0.19.0" に固定されている限り実際の rmpc クライアントからは一生呼ばれず
  死んだ実装のままになる、という実害ある新規ギャップ。
  verified: mpdversion-patch.py。VERSION を実装済み機能に見合う "0.24.0" へ引き上げ
  (0.25.0 未満を維持: stringnormalization は未実装のため 0.25 は名乗らない。rmpc の
  `supported_commands.contains("stringnormalization")` チェックにより実害は無いが、
  検索画面の diacritics トグルが実体の無い機能を見せるのを避けるため)。ただし version
  だけ上げると副作用が1つ生じると判明: rmpc/src/core/event_loop.rs の
  reflect_changes_to_playlist 機能 (lastloadedplaylist と対になる既存の opt-in 機能) が
  version>=0.24.0 になると `save_queue_as_playlist(name, Some(SaveMode::Replace))`
  (= `save NAME "replace"`) を実際に送るが、mopidy-mpd の `save` は
  `save(context, name)` の固定1引数のままで MODE を受け付けず `ACK wrong number of
  arguments` になり機能が壊れる (version bump 単体では新規リグレッション)。そのため
  同パッチで `save {NAME} [MODE]` (MPD 0.24+, MusicPlayerDaemon/MPD
  src/command/PlaylistCommands.cxx handle_save / src/PlaylistSave.cxx
  spl_save_queue を実際にcloneしてソース確認した仕様: create=既存なら失敗、
  append/replace=不存在なら失敗) にも対応、MODE省略時は旧来の mopidy 挙動
  (無ければ作成・あれば上書き) を無変更維持し過去 backlog で検証済みの `save`
  単体動作の回帰を回避。パッチ済み env の dev mopidy(6601, ytmusic 実アカウント) を
  実際に起動し MPD で確認 — greeting `OK MPD 0.24.0` (旧 0.19.0 から変化)、実データ
  (YOASOBI検索結果2曲)をキューに積み `save "SVTest1"`(mode省略)→OK・
  `listplaylistinfo`でフル情報、再度 `save "SVTest1"`(mode省略、既存)→OK上書き
  (回帰なし)、`save "SVTest1" "create"`(既存)→`ACK Playlist already exists`、
  `rm`後 `save "SVTest2" "append"`/`"replace"`(不存在)→`ACK No such playlist`、
  `save "SVTest2" "create"`(不存在)→OK作成、`playlistadd`で1曲追加後
  `save "SVTest2" "append"`→末尾に現在のキュー2曲を追記(3→5曲)、
  `save "SVTest2" "replace"`→現在のキュー2曲で丸ごと上書き(5→2曲)、
  `save "SVTest2" "bogus"`→`ACK Unrecognized save mode, expected one of 'create',
  'append', 'replace'`。旧来の `tagtypes`/`list album`/`search any sort+window併用`/
  `count any`/`crossfade`/`status`/`getvol`/`listplaylists`/`sticker get` の回帰なし・
  mopidy.log の Traceback は `save` 実行時の mopidy_ytmusic 側 create_playlist が
  このテストアカウントの書き込み権限不足で HTTP 401 を出す1件のみで、これは
  mpdlastloadedplaylist-patch.py の検証時にも確認済みの pre-existing な `save`
  自体の挙動 (本パッチが触れていない経路) であり新規リグレッションではない。
  既知の制約: `listplaylistinfo {NAME} [RANGE]` (MPD 0.24+ の範囲指定) も
  `version < 0.24.0` でゲートされているが、rmpc 本体の呼び出し箇所
  (rmpc/src/ui/modals/menu/mod.rs, rmpc/src/ui/panes/directories.rs,
  rmpc/src/ui/panes/playlists.rs 全て) は実際に grep して確認したところ常に
  `range=None` で呼んでおり死んだ経路のため未対応のまま (version bump による実害なし)。
- [x] `update`/`rescan` が常に `updating_db: 0` を返すだけの固定スタブで、`status` の
  `updating_db`/idle の `database`/`update` イベントを一切発火しない件。TODO 全項目
  消化済みのため自走エージェントが rmpc 本体 (mierak/rmpc) を実際に clone して調査
  したところ、rmpc/src/ui/mod.rs の `GlobalAction::Update`/`GlobalAction::Rescan`
  (キーバインド可能なグローバルアクション) と `rmpc update`/`rmpc rescan` CLI
  サブコマンド (rmpc/src/core/command.rs) が実際に `client.update(None)`/
  `client.rescan(None)` を送信し、rmpc-mpd/src/commands/idle.rs の
  `IdleEvent::Database`/`IdleEvent::Update` ハンドラ (rmpc/src/core/event_loop.rs)
  が受信時に status を再取得して `UiEvent::Database` を発火、
  directories.rs/playlists.rs/tag_browser.rs/queue.rs/search/mod.rs 等の各ペインが
  表示中データを再クエリすることを確認。つまり idle 通知が一切発火しない現状では
  「データベース更新」操作をしても rmpc の画面が一切再描画されない実害あるギャップ
  と判明・追加した項目。
  verified: mpdupdate-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/OtherCommands.cxx handle_update, src/db/update/Service.cxx) を実際に
  cloneしてソース確認し仕様を確定 (ジョブIDは1から単調増加してupdating_dbとして返る、
  ジョブ開始・終了でidle updateを発火、実際にDBが変化した場合のみidle databaseを発火)。
  mount.py (mpdmount-patch.py) と同じ流儀で、mopidy core の
  `context.core.library.refresh(uri)` を実際に呼び出し (mopidy_ytmusicはrefresh()を
  オーバーライドしていないためbase実装のno-opだが、mopidy core自体はパッチ対象外の
  ためこれは妥当)、ジョブIDをtranslator.pyの単調増加カウンタとして発行、
  `mopidy.listener.send(session.MpdSession, subsystem)` で全セッションへ
  `update`→`database` の順にidle通知をブロードキャスト (refresh()が同期的に完了し
  ジョブの開始/終了が実質同時なため、実際に変化したか検出はできず毎回両方発火する
  簡略化 — mount/crossfadeと同種の割り切り)。uriがmopidyのURI形式
  (scheme:...) でない場合 `mopidy.exceptions.ValidationError` を捕捉し無視して
  正常応答 (実MPDも存在しないパスのupdateをACKエラーにはしないため方向性は一致)。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても
  冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に
  起動し MPD で確認 — `update`(uri無し)→`updating_db: 1`、`rescan`→
  `updating_db: 2`(以後の呼び出しも単調増加)、`update "ytmusic:track:bogus"`
  (スキーム有り・存在しないURI)→クラッシュせず`updating_db: N`で正常応答、
  `update "some/plain/path"`(スキーム無し素パス)→ValidationErrorを捕捉しクラッシュ
  せず正常応答。idle実測: 別接続で`idle database update`後に`update`実行→
  `changed: update`で即時起床、直後に再度`idle`→`changed: database`で起床
  (2つのlistener.send呼び出しが2件の別メッセージとして届くため1回のidle応答には
  乗らないが、次のidle呼び出しで確実に届くことを確認 — mpdchannels-patch.pyの
  ブロードキャスト方式と同種の許容できる細かい挙動差)。bare `idle`(引数無し)でも
  `rescan`→`changed: update`→再度idleで`changed: database`と同様に確認。`status`は
  `updating_db`フィールドを一切含まない(refresh()が同期的に即完了しジョブが常時
  「実行中でない」ため実MPD同様に省略されるのは仕様通り)ことも確認。旧来の
  `tagtypes`/`search any "yoasobi"`(実データ)/`list album`/`getvol`/`crossfade`/
  `listplaylists`/`channels`/`listmounts`/`status`の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
- [x] `delete [{POS}|{START:END}]` (現行キューからの単曲/範囲削除) が
  `context.core.tracklist.remove(...)` の戻り値 (pykka Future) を一度も `.get()`
  せず投げっぱなしのまま関数を抜けている件。TODO 全項目消化済みのため自走エージェントが
  rmpc 本体 (mierak/rmpc) と mopidy_mpd ソースを実際に読んで新規発見・追加した項目。
  同じファイル内の隣の `deleteid()` は `context.core.tracklist.remove(...).get()`
  と正しく同期しているのに `delete()` のループ内だけ非対称に `.get()` が抜けており、
  mopidy_mpd はハンドラが返った時点でクライアントへ `OK` を返すため、実際に core actor
  側でキューからの除去が反映されるより前に `OK` が届きうる不具合と確認。rmpc は
  `rmpc/src/ui/panes/queue.rs` の単曲削除(`d`キー相当)・visual-select複数曲削除の
  どちらも `client.delete_from_queue(...)` (`rmpc-mpd/src/mpd_client.rs`
  `send_delete_from_queue`) 経由で `delete {POS}`/`delete {START:END}` を送るため、
  キューペインで最も日常的に使う削除操作がこの経路を通ると確認した上で着手。
  verified: mpddeleterace-patch.py。move/shuffle/swap (mpdmoveswaprace-patch.py)・
  findadd/searchadd (mpdfindaddrace-patch.py)・prio (前述) と同じ「pykka Future の
  `.get()` 未呼び出し」バグクラス。`mopidy.core.tracklist.remove()` の実装
  (mopidy/core/tracklist.py) を確認し、該当tlidが見つからなくても例外を投げず空リストを
  返すだけと確定 (move/shuffleと違いAssertionErrorの変換は不要、単に`.get()`を足すだけで
  同期化できる)。パッチ適用後の生成ソースは一時コピーに `chmod u+w` して `ast.parse` で
  構文確認、2回適用しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し、YOASOBI検索結果15曲をキューに積んで MPD で確認 —
  `delete "0"`(単曲)→Id1除去、直後の`playlistinfo`で即座に14曲へ反映、
  `delete "0:2"`(範囲)→2曲除去し12曲、`delete "5:"`(開放端)→5曲のみ残存、
  `delete "999"`(範囲外)→`ACK Bad song index`、`deleteid`/`move`/`swap`の既存動作も
  回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `toggleoutput` (audio_output.py) が `context.core.mixer.set_mute(not mute_status)`
  の戻り値 (pykka Future) を `.get()` せずそのまま `success` として `if not success:`
  の真偽判定に使っている件。TODO 全項目消化済みのため自走エージェントが
  mopidy_mpd/protocol/audio_output.py を実際に読んで新規発見・追加した項目
  (mpdoutputpartition-patch.py が周辺の分岐条件を書き換えた際もこの行自体には
  一度も手を入れておらず、mopidy-mpd 3.3.0 アップストリーム由来のバグとそのまま
  同居していた)。同じファイル内の `enableoutput`/`disableoutput` はどちらも
  `context.core.mixer.set_mute(True/False).get()` と正しく `.get()` している
  のに `toggleoutput` だけ非対称。
  verified: mpdtogglemuterace-patch.py。まず pykka の `Future` に `__bool__`
  オーバーライドが無く `bool(future)` が中身に関わらず常に `True` になることを
  実際に確認 (`pykka.ThreadingFuture().set(False)` → `bool(f)` は `True`、
  `f.get()` は `False`) — つまり修正前は `set_mute()` が実際に失敗しても
  `if not success:` が絶対に真にならず `MpdSystemError("problems toggling
  output")` が到達不能なデッドコードだったと確定。加えて delete()/prio()/
  move()/swap() 等と同じ「`.get()` 未呼び出しによりOK応答が実際の状態反映より
  先に届きうる」非同期の問題も併発。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)である
  ことも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `outputs`(初期)→`outputenabled: 0`、`toggleoutput 0`→`OK`、直後の`outputs`→
  `outputenabled: 1`に反映、再度`toggleoutput 0`→`OK`、`outputs`→
  `outputenabled: 0`に戻る、`toggleoutput 1`(存在しないID)→`ACK No such audio
  output`。`enableoutput`/`disableoutput`の既存動作(この2つは元々`.get()`済み
  で無修正)も回帰なし、`status`/`tagtypes`/`listplaylists`/`getvol`/
  `search any "yoasobi"`(実データ)含め mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mount`/`unmount`/`listmounts` (mpdmount-patch.py) が translator.py に追加した
  揮発性ストア `_mounts` (path -> uri) が、MpdUriMapper/channels.py/partition.py の
  各ストアと全く同じ理由でロック無しに全クライアント接続間 (各々別スレッドの
  MpdSessionアクター) で共有されている件。TODO 全項目消化済みのため自走エージェントが
  既存の `*race-patch.py` 群 (mpdurimaprace/mpdchannelrace/mpdpartitionrace/
  mpdqueuestorerace) と同じ「モジュールレベルのdict/listがロック無しで共有される」
  パターンが他に残っていないか全パッチを再調査して新規発見・追加した項目。
  `_mounts` は mount.py のコメント通り session 単位ではなくサーバー全体で共有される
  実MPD仕様のストアで、`mount_uri_used(uri)` (`uri in _mounts.values()`) と
  `mount_list()` (`sorted(_mounts.items())`) がその場でdictを走査する一方、
  `mount_add(path, uri)` (`_mounts[path] = uri`) が新規キー追加でdictをリサイズしうる。
  verified: mpdmountrace-patch.py。まずユニットレベルの決定的再現テストで修正前後の
  挙動を確認 — 5000件のdictを手動ループで走査中(1件ごとの走査に人為的なsleepを挟み
  走査時間の窓を広げる)に別スレッドが新規キーを追加すると、ロック無しの旧実装では
  確実に `RuntimeError: dictionary changed size during iteration` が発生する一方、
  `threading.RLock` で走査・書き込み双方を直列化した新実装では同一シナリオで例外が
  発生せず、書き込みがロック解放後まで正しく直列化されることを確認。パッチ適用後の
  生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等
  (スキップ)であることも確認。`nix/lib/mopidy-env.nix` に mpdqueuestorerace-patch.py
  の直後に登録しビルド成功、生成ソースに `_mount_lock` が反映されていることを確認した
  上で dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `listmounts`(初期)→空でOK、`mount "foo" "nfs://192.168.1.4/export/mp3"`→OK、
  `listmounts`→`mount: foo`/`storage: nfs://...`、同名 `mount` 再実行→
  `ACK [2@0] {mount} Mount point busy`、同URIを別名で `mount`→
  `ACK [2@0] {mount} This storage is already mounted`、`unmount "foo"`→OK、
  再度`unmount "foo"`→`ACK [2@0] {unmount} Not a mount point`、いずれも既存の
  エラー応答が回帰なく維持されていることを確認。実ソケットでの8並列mounter
  (mount→unmount連打)×8並列lister(listmounts連打)×300ラウンドのストレステストも
  実施 (mopidy.logにTraceback/RuntimeError/ERROR 0件、サーバーはストレス後も
  `status`に正常応答— なお少数のクライアント側socket timeoutが発生したが、
  パッチ適用前の同一ストレステストでも同数程度発生し、mopidy.logにも同様に
  Traceback/RuntimeError 0件だったため、これは環境要因 (このマシン上での大量同時
  接続時のスレッドスケジューリング遅延) によるテストハーネス側のノイズであり
  今回の修正が原因ではないと確認済み。信頼できる修正効果の証明は上記のユニット
  レベル決定的再現テストによる)。`status`/`tagtypes`/`listplaylists`/
  `search any "yoasobi"`(実データ)含め既存コマンドの回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
- [x] `playlistinfo [SONGPOS | START:END]` に不正な引数 (非数値 `playlistinfo "abc"`、
  `-1` 以外の負数、`START >= END` の逆順レンジ `playlistinfo "5:2"`、開始のみ空の
  `playlistinfo ":5"` 等) を渡すと `mopidy_mpd/protocol/current_playlist.py` の
  `playlistinfo()` 内で手動パースしている `protocol.RANGE(parameter)` が素の
  `ValueError` を送出し、捕捉されずに MPD セッションが切断されてしまう不具合
  (サーバ本体は生存、当該コネクションのみ切断)。これは BACKLOG 最初の項目である
  `seekcur` の不具合 (mpdseekcurargerr-patch.py で修正済み) と全く同じパターン:
  `delete`/`move`/`shuffle`/`listplaylist`/`listplaylistinfo`/`load`/
  `playlistdelete`/`playlistmove` は全て `@protocol.commands.add(...,
  songrange=protocol.RANGE)` のようにデコレータの引数バリデータとして宣言している
  ため `Commands.add.<locals>.validate()` (`mopidy_mpd/protocol/__init__.py`) の
  `except ValueError: raise exceptions.MpdArgError(...)` に保護されるが、
  `playlistinfo` は `parameter` が省略可能 (`None`/`"-1"` で全件表示) なため
  デコレータの型宣言ではこの分岐を表現できず、関数本体で手動パースしており保護を
  受けられない。同じファイル内の `prio()` (関数本体で `*args` の各トークンを
  `protocol.RANGE(token)` で手動パースしている点は同型) は既に
  `try: songrange = protocol.RANGE(token) / except ValueError: raise
  exceptions.MpdArgError("incorrect arguments")` で保護済みであり、
  `playlistinfo()` だけがこの保護漏れであることを既存パッチ全件との突き合わせで
  確認した。TODO 全項目消化済みのため自走エージェントが Explore サブエージェントに
  他の未対応箇所の調査を委任し新規発見・追加した項目 (`protocol.RANGE()` を
  スタンドアロン実行し `"abc"`/`"-3"`/`"5:2"`/`":5"`/`""` いずれも `ValueError` を
  送出すること、`dispatcher.py` の `_call_handler_filter`/
  `_catch_mpd_ack_errors_filter` が `pykka.ActorDeadError`/`exceptions.MpdAckError`
  のみを捕捉し素の `ValueError` を拾う経路がどこにも無いことをソース読解で確認済み)。
  verified: mpdplaylistinfoargerr-patch.py。`prio()` と同じ流儀で
  `protocol.RANGE(parameter)` の呼び出しを try/except で囲み、`ValueError` を
  `exceptions.MpdArgError("incorrect arguments")` に変換。パッチ適用後の生成
  ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等
  (スキップ)であることも確認。`nix/lib/mopidy-env.nix` に
  mpdalbumartrace-patch.py の直後に登録しビルド成功、生成ソースに新実装が
  反映されていることを確認した上で dev mopidy(6601, ytmusic 実アカウント) を
  実際に起動し MPD で実機確認 — `playlistinfo "abc"`/`playlistinfo "-3"`/
  `playlistinfo "5:2"`/`playlistinfo ":5"` (非数値・`-1`以外の負数・逆順レンジ・
  開始のみ空) いずれも `ACK [2@0] {playlistinfo} incorrect arguments` となり
  セッション切断されず、続く `status` も正常応答 (旧実装ならここで素の
  `ValueError` によりコネクションが切断されていた)。実データ(YOASOBI検索結果
  2曲をfindaddでキューに追加)で従来動作の回帰なしも確認 — 引数無し
  `playlistinfo`/`playlistinfo "-1"` (共に全件、Added/Pos/Id含め正常表示)、
  単一インデックス `playlistinfo "0"`(1件)、有効なレンジ `playlistinfo "0:2"`
  (2件)、範囲外 `playlistinfo "999"` → 従来通り `ACK [2@0] {playlistinfo} Bad
  song index`(この分岐は別ロジックで変更なし)。旧来の `tagtypes`/`status`/
  `search any "yoasobi"` の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic/library.py` の `uploadAlbumToTracks()` (YouTube Music の
  「Uploads」= 自分でアップロードした楽曲をアルバム単位でブラウズする際に呼ばれる)
  が `track_no` を無条件で `None` にしており、`mopidy_mpd/translator.py` の
  `track_to_mpd_format()` は `track.track_no is not None` のときのみ `Track` タグを
  出力するため、find/search/lsinfo/playlistinfo/currentsong いずれの応答でも
  Uploads 経由のアルバムだけ `Track` 行が常に欠落する不具合。TODO 全項目消化済みの
  ため自走エージェントが再調査して発見した項目。構造的に同一の処理を行う姉妹関数
  `albumToTracks()` (通常のライブラリ登録アルバム用) は
  `for index, song in enumerate(album["tracks"], start=1):` で `track_no=index` を
  正しく設定しており、`get_library_upload_album()` (ytmusicapi) も `get_album()` と
  同じ `parse_uploaded_items()` 経由でアルバムページの表示順そのままのリストを返す
  ため「リスト順=トラック順」の前提は同一、`uploadAlbumToTracks()` だけ実装が
  漏れていたと判明。
  verified: ytuploadalbumtrackno-patch.py。ytuploaddurationfix-patch.py 適用後の
  ソースを前提に、`uploadAlbumToTracks()` のループを albumToTracks() と同じ
  `for index, track in enumerate(album["tracks"], start=1):` に変更し
  `track_no=None` → `track_no=index` に修正。パッチ適用後の生成ソースは一時コピーに
  当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix` に ytbitrate-patch.py の直後に登録しビルド成功、生成
  ソースに新実装が反映されていることを確認。dev アカウントには実際の Uploads
  データが無い (`lsinfo "YouTube Music/Uploads"` → `ACK Not found`) ため、
  `YTMusicLibraryProvider` を直接インスタンス化し合成データ (videoId/title/
  duration付きの3曲を持つアルバム) を `uploadAlbumToTracks()` に渡すオフライン検証
  (`ytunavailabletrack-patch.py` 等の前例と同じ手法) を実施 — 修正前は
  `track_no` が全曲 `None` で `translator.track_to_mpd_format()` が `Track` タグを
  一切出力しなかったのに対し、修正後は `[1, 2, 3]` と正しく連番化され、
  `track_to_mpd_format()` の出力にも `('Track', '1/3')`/`('Track', '2/3')/`
  `('Track', '3/3')` が実際に含まれることを確認。dev mopidy(6601, ytmusic 実
  アカウント) を実際に起動し MPD で回帰確認 — `status`(xfade/state等の既存
  フィールド正常)、`tagtypes`(Track含む既存タグ一覧に変化なし)、
  `search any "YOASOBI"`(既存トラック/アルバムの応答形式に変化なし)、
  `list album` の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] ストリーム解決を pytube→yt-dlp へ委譲 (ytdlp-patch) — verified: 再生 state=playing
- [x] any 検索が album=None で 0 件になる不具合 (search-patch) — verified: yoasobi 等ヒット
- [x] 新 MPD フィルタ式 `(Tag contains "x")` の解釈 (mpdsearch-patch) — verified: 米津37件
- [x] albumart/readpicture 実装 + offset==total 修正 (mpd-patch) — verified: JPEG全転送
- [x] binarylimit 受け (mpd-patch) — verified: rmpc 接続可
- [x] ytmusic:home (get_home) ブラウズ (home-patch) — verified: セクション→playlist
- [x] listenbrainz 空 release_name の 400 修正 (lb-patch) — verified: 400消滅
- [x] find/search/count/findadd/searchadd/searchaddpl/playlistfind/playlistsearch/
  searchplaylist が共有するフィルタ式パーサ (`_query_from_mpd_filter_expression`/
  `_query_from_mpd_search_parameters`, music_db.py) と旧式 TAG/VALUE ペア構文が、
  VALUE が真に空文字列 (`(TAG == "")` / `find TAG ""`) の節を一律
  `if not value.strip(): continue` で黙って読み捨ててしまう不具合。TODO 全項目
  消化済みのため自走エージェントが (general-purpose サブエージェントへの調査
  委任を経て) 新規発見。実MPD本体 (gh raw で src/song/TagSongFilter.cxx
  TagSongFilter::Match() を確認) は空文字列 VALUE を特別扱いせず通常通り
  パースし、タグが不在 (`!visited_types[type]`) かつ `filter.empty()` の場合
  `return !filter.IsNegated()` という明示的なフォールバック分岐を持つ ——
  `(TAG == "")` はタグ不在/空のトラックにマッチする正当なクエリ、
  `(TAG != "")` は逆にタグが実在するトラックにのみマッチする。mopidy_mpd は
  該当節自体を黙って消し去るため、単独では `ACK incorrect arguments`
  (positives が空になり mpdnegonlyfilter-patch.py のガードにかかる)、他条件
  との AND 併用時 (`(Composer == "") AND (Artist == "YOASOBI")`) はさらに悪く
  条件が消えたまま黙って絞り込み漏れの結果を返していた。
  mpdfilterexprtagerr-patch.py 自身のコメントが「値が空文字列のケースは本項目
  のスコープ外」と明示的に据え置いていた未対応項目と BACKLOG.md 全体検索で
  確認済み。
  verified: mpdfilteremptyvalue-patch.py。パーサは空白のみの値 (従来通り
  無条件 drop、無変更) と真に空文字列の値を区別し、後者は backend の query
  へは送らず (base/prio/audioformat 等の既存疑似タグと同じ扱い) kind 付き
  positives/negatives へ積む。ローカル判定 (`_mpd_track_matches_positives`/
  `_mpd_track_excluded`、current_playlist.py の独立複製 `_pf_matches`) は該当
  フィールドの値が1つも無い (タグ不在) 場合、needle が空文字列なら real MPD
  の `filter.empty() -> !IsNegated()` に倣い positives 側はマッチ・negatives
  側は不一致 (除外) とする。needle が非空の場合の既存挙動は無変更。オフライン
  単体テストで `_mpd_track_matches_positives`/`_mpd_track_excluded`/
  `_pf_matches` を values有/無 × needle空/非空の全4象限 (composer フィールドは
  `len(positives)==1` の backend 信頼バイパスが先に発火し検証にならないため
  album フィールドで直接検証) で確認、パーサ側も sole-empty-positive/
  combined-AND/negation-only/whitespace-only-unchanged/legacy-pair構文を単体
  テストで確認済み。dev mopidy (TCP 6601、mopidy-ytmusic 実アカウント) で実機
  確認 — mopidy_ytmusic の Track は composer を常に空で返すため、`find
  "(Composer != \"\") AND (Artist == \"YOASOBI\")"` が修正前は Composer 節が
  消え YOASOBI の全22件 (アルバムプレースホルダ含む) がヒットしていたが、
  修正後は「Composer が実在する」条件を全曲が満たせず0件になることを確認。
  `find "(Composer == \"\")"` (単独の空positive) は ACK にならず OK
  (backend への問い合わせ対象を持たないため0件、prio/audioformat 単独疑似
  タグと同じ既存の受容済み制約) を確認、`find "(Composer != \"\")"` (単独の
  空negation) は従来通り `ACK incorrect arguments` (positive 条件皆無、
  mpdnegonlyfilter-patch.py のガード) であることも確認。queue 経由
  (searchadd artist "YOASOBI" で15曲投入) の `playlistfind` でも同型を確認 —
  `(Composer != "")` → 0件、`(Composer == "")` → 全15件、対照実験として
  `(Album == "")` (全曲が実際に Album を持つ) → 0件、`(Album != "")` → 全15件、
  `(Artist == "YOASOBI")` (通常のフィルタ、無関係) → 5件 (回帰なし)。
  空白のみの値 (`(Album == "  ")`) は修正前後で挙動不変 (無条件 drop により
  条件が残らず `ACK incorrect arguments`) であることも確認。回帰確認:
  `findadd ... window "0:2"`/`search any "yoasobi" sort -Date`/`count
  "(Genre == \"Pop\")"`/`list album group artist`/`find "(Bogus == \"x\")"`
  (未知タグは従来通り ACK Unknown filter type)/`find "(Artist ==
  \"YOASOBI\") sort Title"` (22件、フィルタ+sort併用) はいずれも修正前後で
  応答不変。mopidy.log に新規 ERROR/Traceback 0件、起動もクリーンであることを
  確認。
- [x] フィルタ式/旧式検索構文の「空白のみの VALUE」節が黙って読み捨てられる不具合:
  mpdfilteremptyvalue-patch.py が真に空文字列 (`(TAG == "")`) の節は修正したが、
  同パッチ自身のコメントで「空白のみの値 (`(TAG == "  ")`) は従来通り無条件drop、
  スコープ外」と明示的に据え置いていた残課題。TODO 全項目消化済みのため自走
  エージェントが (general-purpose サブエージェントへの調査委任を経て) 新規発見。
  verified: mpdfilterwhitespacevalue-patch.py。実MPD本体 (gh raw で
  src/song/Filter.cxx ExpectQuoted()、src/song/StringFilter.hxx を確認) はクォート
  文字列トークナイザがクォート内容を一切trim/stripしないため、空白のみの VALUE
  は `StringFilter::empty()` (`value.empty()`、純粋な長さ0チェック) が偽になる
  通常の非空文字列条件であり、`TagSongFilter::Match()` の「タグ不在+filter.empty()」
  フォールバックには入らない。mopidy_mpd はこの節自体を黙って消し去るため、単独
  では `ACK incorrect arguments`、他条件と AND 併用時
  (`(Composer == "  ") AND (Artist == "YOASOBI")`) は条件が消えたまま黙って
  絞り込み漏れの結果を返していた (mpdfilteremptyvalue-patch.py が真に空文字列に
  ついて修正したのと同じ実害パターン)。**実装上の罠**: 最初の実装は空白のみの
  値を通常値と同じ経路で `query` dict (backendへのtext search) に流したところ、
  mopidy core 自体の `validation.py check_query()` (`_check_query_value`:
  `not arg.strip()` で ValidationError) が例外を送出し find/search/count が丸ごと
  クラッシュ(接続が無応答に)することを実機で確認、`mopidy.log` に
  `ValidationError: Expected "composer" to be list of strings, not '  '` の
  Traceback を確認した上で設計を修正。真に空文字列と同じ理由 (backendへは送れない)
  で空白のみの値もローカル判定 (`_mpdbasefilter_positives`) 専用に回す方針に変更、
  ローカル側 (`_mpd_track_matches_positives`/`_mpd_track_excluded`) は無変更のまま
  既存の `needle == ""` 分岐が実行時に真に空文字列/空白のみを自動的に区別する
  (空白のみは通常の非空値比較経路、real MPD の `filter.empty() == false` と一致)。
  実機確認 (TCP 6601、mopidy-ytmusic 実アカウント): mopidy_ytmusic の Track は
  composer を常に空で返すため、`find "(Composer == \"  \")"` が修正前
  `ACK incorrect arguments`、修正後 `OK` (0件、クラッシュなし) に変化、
  `(Composer == "  ") AND (Artist == "YOASOBI")` が修正前 YOASOBI 全曲ヒット (誤)、
  修正後 0件 (正) に変化、`(Composer != "  ") AND (Artist == "YOASOBI")` は
  タグ不在+非空negation→不一致(除外しない)により 265行 (全曲) 正しくヒット、
  旧式構文 `find Composer "  "` も同型、`count "(Composer == \"  \")"` →
  `songs: 0` (クラッシュなし)、`playlistfind` (queue に searchadd artist
  "YOASOBI" で投入) でも同型を確認。回帰確認: `find "(Composer == \"\")"`
  (真に空文字列)、`find "(Album == \"  \")"`/`find "(Genre == \"\")"`
  (通常フィールド)、`find "(Artist == \"YOASOBI\")"`/`search any "YOASOBI"`/
  `count "(Artist == \"YOASOBI\")"`/`tagtypes`/`status`/
  `playlistfind artist "YOASOBI"` はいずれも無変更。mopidy.log に新規
  ERROR/Traceback 0件、mopidy が正常に起動し続けることを確認。
- [x] `sticker`系コマンド(get/set/delete/list/find/inc/dec)と`stickertypes`/
  `stickernamestypes`がTYPE引数として"song"/"playlist"の2種のみ受け付け、実MPD
  0.24+が対応するタグ種別ドメイン(artist/album/albumartist/title/genre/composer/
  performer/conductor/work/ensemble/location/label/MUSICBRAINZ_*等17種)を送ると
  常に`ACK Unknown sticker domain`になる不具合。TODO全項目消化済みのため
  自走エージェントがgeneral-purposeサブエージェントへの調査委任を経て新規発見。
  verified: mpdstickertagdomain-patch.py。実MPD本体(gh rawで
  src/sticker/AllowedTags.cxx/src/sticker/TagSticker.cxx/
  src/command/StickerCommands.cxxを実際に取得して確認) は`tag_name_parse_i()`
  (大文字小文字区別無し)でタグ名を解決し17タグの許可ビットマスクに含まれていれば
  TagHandlerとしてディスパッチ、`ValidateUri()`は`TagExists()`(=完全一致フィルタが
  DB内に1件でもヒットするか)でURI引数(=タグ値)の実在を検証し無ければ
  `std::invalid_argument`(ACK_ERROR_ARG(2)、playlistドメインと同じコード、
  ACK_ERROR_NO_EXIST(50)ではない)を送出すると判明。mpdstickerplaylist-patch.py
  導入時のコメントは「mopidy_ytmusicはfilter式マッチ/タグ値単位の実データ構造を
  持たないためタグ種別ドメインは対象外」としていたが、既存のfind/searchフィルタ式
  パーサ(music_db.py `_LIST_MAPPING`/`_LIST_NAME_MAPPING`、mpdtagnames-patch.py/
  mpdtagnames2-patch.py由来)が既にartist/album等17タグ全てをtagとして認識し
  backendへの`library.search(query={field:[value]})`委譲で実際に値の存在確認が
  可能であり、当時のスコープ外判断は誤りだったと判明(BACKLOG.md全体を
  `sticker`/`タグ種別`/`filter拒否`で検索し、この非対称が既出の対象外判断のまま
  再対応されていなかったことを確認)。実データの無い"phantom"タグ
  (`_PHANTOM_TAG_FIELDS`: conductor/work/ensemble/location/label/
  musicbrainz_releasetrackid/musicbrainz_workid/musicbrainz_albumartistid)は
  実データを捏造せず常に「存在しない」として扱う(points 8/16と同じ方針)。
  修正: `_mpd_sticker_check_type()`を`_mpd_sticker_resolve_domain()`へ置き換え、
  song/playlistは既存通り厳密一致、それ以外は`_LIST_MAPPING`経由の大文字小文字
  非依存タグ名解決+canonical名への正規化(`_LIST_NAME_MAPPING`)を追加。
  `_mpd_sticker_validate_uri()`にタグドメイン分岐(`context.core.library.search(
  query={field:[uri]}, exact=True)`の結果有無で存在確認)を追加、stickertypes/
  stickernamestypesも17タグを反映するよう修正。dev mopidy(6601, ytmusic実
  アカウント)を実際に起動しMPDで実データ確認 —
  `sticker set artist "YOASOBI" rating "5"`→OK、`sticker get artist "YOASOBI"
  rating`→`rating=5`、大文字小文字違い(`sticker get Artist "YOASOBI" rating`)
  でも同じ値を取得(canonical名への正規化を確認)、`sticker list artist
  "YOASOBI"`→同値、`sticker inc artist "YOASOBI" rating "2"`→`rating=7`に
  加算、`sticker find artist "" rating`→`Artist: YOASOBI`+`sticker: rating=7`、
  `sticker delete artist "YOASOBI" rating`→OK、直後の`sticker get`→
  `ACK [50@0] no such sticker`(実在チェック自体は無関係、既存のno-such-sticker
  経路)。実在しないアーティスト名`sticker set artist "NoSuchArtistXYZ999"
  rating "5"`→`ACK [2@0] no such Artist: NoSuchArtistXYZ999`(ACK_ERROR_ARG、
  50ではない)。phantomタグ`sticker set conductor "AnythingAtAll" rating "1"`→
  常に`ACK [2@0] no such Conductor: ...`(データが無い以上、実在すると偽装しない
  ことを確認)。`stickertypes`→`stickertype: song`/`playlist`に加え17タグの
  canonical名(Artist/Album/AlbumArtist/Title/Genre/Composer/Performer/
  Conductor/Work/Ensemble/Location/Label/MUSICBRAINZ_ARTISTID/
  MUSICBRAINZ_ALBUMID/MUSICBRAINZ_ALBUMARTISTID/MUSICBRAINZ_RELEASETRACKID/
  MUSICBRAINZ_WORKID)を列挙。`sticker set album "怪物" plays "3"`+
  `stickernamestypes Album`/`stickernamestypes album`(大文字小文字どちらも)→
  `type: Album`で正しく絞り込み。回帰確認: 未知ドメイン`sticker get bogusdomain
  "x" name`→引き続き`ACK [2@0] Unknown sticker domain: bogusdomain`、song
  ドメイン(実uriへのset/get/delete)・playlistドメイン(実在しないプレイリスト名
  への set→引き続き`ACK [2@0] no such playlist`)は無変更、`tagtypes`/`status`/
  `count "(Artist == \"YOASOBI\")"`の回帰なし。mopidy.log に新規ERROR/Traceback
  0件、mopidy が正常に起動し続けることを確認。

## 既知の軽微な残課題(レビュー由来・優先度低)
- [x] `prio`/`prioid` の TOCTOU レース: get_length()とget_tl_tracks()が別呼び出し＋index参照で、同時2クライアントが間にtracklistを縮めるとIndexError→接続切断。tracklist.slice()に置換して解消(delete()/move()と同流儀)。rmpcはprioを送らず実害は極小。
  verified: mpdprio-patch.py の `prio()` 実装を修正。旧実装は `get_length()` で長さを
  取得した後、別呼び出しの `get_tl_tracks()` で取得したスナップショットへ位置インデックス
  (`tl_tracks[position]`) するという2段構成で、間に他クライアントが `delete` 等で
  tracklist を縮めると `IndexError` が発生し MPD セッションが切断されるバグがあった
  (`prioid` は tlid を直接指定するのみで別呼び出し後の位置参照が無いため元々レース無し、
  修正不要と判明)。修正: `delete()`/`move_range()` と同じ流儀で、範囲ごとに
  `context.core.tracklist.slice(start, end).get()` を1回のcore呼び出しで叩き、返ってきた
  `(tlid, track)` を直接使う (別呼び出しでの位置インデックス参照を排除)。範囲外/逆転レンジは
  slice結果が空になり `ACK Bad song index` (delete()と同じ挙動)。dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し、YOASOBI検索結果5曲をキューに積んで MPD で確認 —
  `prio 50 "0:2"`→Id1/Id2 に `Prio: 50`、`prio 30 "3:"`(open-ended)→Id4/Id5 に `Prio: 30`、
  `prio 20 "0:3" "1:4"`(重複レンジ、set で重複排除)→Id1-4 に正しく反映、
  `prioid 0 1 2`(0でリセット)→Id1/Id2 から Prio 消滅、`prio 10 "100:200"`(範囲外)→
  `ACK Bad song index`、`prio 10 "5:3"`(逆転レンジ)→`ACK incorrect arguments`
  (protocol.RANGE側の既存検証、無変更)、`prio 999 "0"`→`ACK Invalid priority`、
  `prio 10`(引数不足)→`ACK wrong number of arguments`、`prio abc "0"`(非数値)→
  `ACK incorrect arguments`、`prioid 77 99999`(存在しないid)→`ACK No such song`、
  `moveid`/`swapid` の既存動作も回帰なし。**TOCTOUレース自体の再現確認**: 4スレッドで
  `prio 42 "0:20"` を連打しつつ、別4スレッドで同時に `clear`→`findadd`→`delete` による
  tracklist縮小を8秒間並行実行するストレステストを実施 — 修正後は接続断・例外0件、
  mopidy.log に ERROR/Traceback 0件 (このレース条件を再現する構成で検証)。旧来の
  `tagtypes`/`count any`/`list album`/`status`/`search any` の回帰なし・Traceback 0 を確認。
- [x] `playlistfind`/`playlistsearch` (現行キュー内検索): `playlistfind` は `tag=="filename"` の
  1ケースのみ実装、`playlistsearch` は完全な `raise MpdNotImplemented` のスタブのままだった
  (musicpd.org 仕様の現行形 `{FILTER} [sort {TYPE}] [window {START:END}]` 未対応、複数マッチも
  非対応)。TODO 全項目消化済みのため自走エージェントが調査して新規発見・追加した項目。
  verified: mpdplaylistfind-patch.py。mopidy_mpd/protocol/current_playlist.py に対する新規
  パッチ。mpdsearch/mpdsort/mpdwindow-patch が music_db.py に用意したフィルタ式パーサ/
  `_SEARCH_MAPPING`/`_mpd_extract_sort_params`/`_mpd_sort_value` を current_playlist.py から
  import して再利用し、バックエンドの library.search ではなく現在のキュー
  (`tracklist.get_tl_tracks()`) のTrackの実値を直接参照して走査するよう実装 (専用の値取得
  ヘルパー `_pf_field_values` を新設)。仕様は WebFetch で mpd.readthedocs.io/protocol.html を
  確認し、`playlistfind`=大文字小文字を区別する厳密一致、`playlistsearch`=区別しない部分一致、
  と確定。パッチ済み env の dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、実データ
  (YOASOBI「怪物」「アイドル」/Ayase「飛天」/Lilas「恋風」の4曲)をキューに積んで MPD で確認 —
  `playlistfind artist "YOASOBI"` → 2曲(Pos/Id付きフル情報)、`playlistfind artist "yoasobi"`
  (小文字)→ 厳密一致のため0件(OKのみ)、`playlistsearch artist "yoasobi"` → 大小無視で同じ2曲、
  `playlistsearch title "飛"`(部分一致)→ Ayase「飛天」、フィルタ式
  `playlistfind "(Artist == \"Ayase\")"` → 1曲、複数タグ・値ペアの AND
  `playlistfind album "アイドル" artist "YOASOBI"` → 交差する1曲のみ、`any "Lilas"` →
  Artistフィールド経由でヒット、`sort Title`/`sort -Title` → 順序が反転、`window "0:1"` →
  先頭1件のみ、旧来の `playlistfind filename "URI"`(絶対一致)も回帰なし。エラー系: 引数無し
  `playlistfind` → `ACK wrong number of arguments`、フィルタ無しで修飾子のみ
  `playlistsearch sort Title` → 同エラー、未知タグ `playlistfind Bogus "x"` →
  `ACK incorrect arguments`、不正 `window "a:b"` → `ACK Invalid window: a:b`、未知
  `sort Bogus` → `ACK Unknown sort type: Bogus`。空キューでの検索 → エラーにならずOKのみ
  (0件)。旧来の `search any`/`count any`/`list album`/`prio`/`playlistid`/`sticker` の回帰なし・
  mopidy.log に Traceback/ERROR 0件を確認。
- [x] `crossfade {SECONDS}` が `raise MpdNotImplemented` のスタブで、`status` の `xfade`
  フィールドも常に固定値 0 のままだった。TODO 全項目消化済みのため自走エージェントが
  rmpc-mpd 本体 (mierak/rmpc, rmpc-mpd/src/mpd_client.rs `send_crossfade`) を gh search code
  で調査し、`CrossfadeUp`/`CrossfadeDown` グローバルアクション (rmpc/src/ui/mod.rs) が実際に
  `crossfade` コマンドを送信し、ステータスバーの Crossfade 表示 (rmpc/src/ui/panes/mod.rs
  `StatusProperty::Crossfade`) が `status` の xfade を読むことを確認した上で新規発見・追加した
  項目。
  verified: mpdcrossfade-patch.py。prio/prioid (mpdprio-patch.py) と同じ流儀で、crossfade秒数を
  translator.py にモジュールレベルの揮発性ストア (`_crossfade_seconds`/`set_crossfade`/
  `get_crossfade`) として保持し、`crossfade` コマンドで更新、`status` の `_status_xfade` で
  反映するよう実装 (mopidy core 自体は GStreamer レベルのクロスフェード機能を持たずこの値が
  実際の再生に影響することはないが、mopidy core はパッチ対象外のため妥当な範囲)。dev
  mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 — 初期状態 `status` → `xfade: 0`、
  `crossfade 15` → OK、以後 `status` → `xfade: 15`、`crossfade 0`(リセット) → `status` →
  `xfade: 0`、非数値 `crossfade abc` → `ACK incorrect arguments`(既存の引数検証のまま回帰なし)。
  旧来の `tagtypes`/`list album`/`search any`/`count any`/`status` の他フィールドの回帰なし・
  mopidy.log に Traceback/ERROR 0件を確認。
- [x] `single`/`consume` の `oneshot` (MPD 0.21+/0.24+) 未対応: mopidy-mpd 3.3.0 は両コマンドとも
  `state=protocol.BOOL` (0/1のみ) で登録されているため `single oneshot`/`consume oneshot` を送ると
  `ACK incorrect arguments` になる。TODO 全項目消化済みのため自走エージェントが調査して新規発見・
  追加した項目。rmpc 本体 (mierak/rmpc) を実際に clone しソース確認したところ、
  rmpc-mpd/src/mpd_client.rs send_single/send_consume が実際に `OnOffOneshot::cycle()`
  (rmpc/src/ui/mod.rs の SingleGlobal/ConsumeGlobal 等のキーバインドアクション) で
  off→on→oneshot→off の3値を送信し、ステータスバー表示 (rmpc/src/ui/panes/mod.rs
  StatusProperty::Single/Consume) が `status` の single/consume を `"0"/"1"/"oneshot"` として
  パース (rmpc-mpd/src/commands/status.rs OnOffOneshot::from_str) することを確認した上で追加。
  verified: mpdoneshot-patch.py。(1) protocol/__init__.py に ONOFFONESHOT 変換関数を追加し
  single/consume の引数型を差し替え。(2) 実際の on/off は既存の mopidy core
  tracklist.set_single/set_consume (crossfade/prioと違いスタブではなく実在の機能) へ
  `state != "0"` としてそのまま反映しつつ、表示用の3値は translator.py の揮発性ストアに保存し
  status で返す。(3) 実 MPD 仕様通り oneshot は対象の1曲の再生が終わったら自動で off に戻るため、
  mopidy_mpd/actor.py の既存 CoreListener (MpdFrontend) が受け取る `track_playback_ended`
  イベントで oneshot なら off へ戻すハンドラを追加 (mopidy core 自体はパッチ対象外だが、
  mopidy_mpd 拡張側からの CoreListener 購読は対象内)。パッチ適用後の生成ソースは一時コピーに
  当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `single "oneshot"`→OK・`status`→`single: oneshot`、`consume "oneshot"`→OK・`status`→
  `consume: oneshot`(揮発性ストアが同一プロセス内の別接続からも一貫して見えることも確認)。
  実データ(YOASOBI 2曲)をキューに積み `play "0"` で再生開始、`single oneshot`/`consume oneshot`
  を設定した状態で `next` を送信 → mopidy core の `track_playback_ended` が実際に発火し
  (`_on_stream_changed`、自然再生終了と同じ内部イベント経路)、後続の `status` で
  `single: 0`/`consume: 0` に自動復帰、かつ consume 効果で再生済みの1曲目がキューから
  実際に削除される (`playlistlength` が2→1に減少) ことを確認。エラー系: `single "2"`/
  `single "bogus"`/`consume "2"` → `ACK incorrect arguments`(引数検証)、旧来の `single "1"`/
  `single "0"`/`consume "1"`/`consume "0"` (0/1のみの旧来動作) も status 反映含め回帰なし。
  旧来の `tagtypes`/`search any`(sort+window併用)/`list album`/`count any`/`crossfade`/
  `getvol`/`listplaylists` の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `load {NAME} [START:END] [POSITION]`: mopidy-mpd 3.3.0 の `load` は `[START:END]` レンジ
  までしか受け付けず、実 MPD 0.23+ の POSITION (add/addid と同じ絶対/相対 `+N`/`-N`) 未対応。
  TODO 全項目消化済みのため自走エージェントが rmpc 本体 (mierak/rmpc) を実際に clone して調査
  したところ、rmpc-mpd/src/mpd_client.rs send_load_playlist が常に RANGE (`0:`) に加えて任意の
  POSITION を送信する実装で、rmpc/src/ui/panes/directories.rs の enqueue() がディレクトリ
  ブラウザでストアドプレイリスト項目を選択した際に Enqueue::Playlist を生成し、
  CommonAction::AddOptions (キーバインド可能な「現在の曲の次に追加」「前に追加」等
  rmpc/src/config/keys/actions.rs の Position::AfterCurrentSong/BeforeCurrentSong を含む位置
  指定つき追加アクション) 経由で実際に `load NAME 0: +0` のような POSITION 付き `load` を
  送信すると判明。mopidy-mpd の固定引数実装では余分なトークンが `ACK wrong number of
  arguments` になり、ディレクトリブラウザからストアドプレイリストを位置指定付きでキューに
  追加する機能が丸ごと失敗する実害あるギャップと確認した上で追加した項目。
  verified: mpdloadpos-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/PlaylistCommands.cxx handle_load) を WebFetch でソース確認し仕様を確定:
  位置解決は add と同じ ParseInsertPosition (現在曲基準の相対 +N/-N、絶対はロード前のキュー長
  でクランプ) だが、load はプレイリストの複数曲を一括で追加しうるため、実 MPD は「常に末尾へ
  追加してから、要求位置が末尾より手前ならその追加された範囲だけをまとめて move する」実装
  (MoveRange) になっている。mpdaddpos-patch.py の add と同じアルゴリズム (mopidy core の
  tracklist.move(start, end, to_position) を利用) を stored_playlists.py の load へ移植。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し実データ
  (YOASOBI検索結果のtrack URI 2曲) で `save "LoadPosTest1" "create"` してストアドプレイリスト
  作成した上で MPD プロトコルを直接叩いて確認 — 3曲キュー+`play 1`(pos1を実際に再生開始、
  `status`のstate:play/song:1/songidで確認)の状態で `load "LoadPosTest1" "0:" "+0"`→現在曲
  (songid不変)の直後(pos2-3)に2曲挿入されplaylistlength 3→5、`load "LoadPosTest1" "0:" "-0"`→
  現在曲の直前(pos1-2)に挿入され現在曲がpos1→pos3にシフト(songidは不変=同じ曲が再生継続)、
  絶対位置 `load "LoadPosTest1" "0:" "1"`→該当位置に正しく挿入、境界値超過
  `+999`/`-999`→`ACK [2@0] {load} Number too large`、絶対位置の範囲外
  `load "LoadPosTest1" "0:" "999"`→`ACK [2@0] {load} Bad song index`、非数値
  `load "LoadPosTest1" "0:" "abc"`→`ACK [2@0] {load} incorrect arguments`、キューが空
  (現在曲なし)で相対指定 `load "LoadPosTest1" "0:" "+0"`→`ACK [55@0] {load} No current song`、
  存在しないプレイリスト名+POSITION `load "NoSuchPlaylistXYZ123" "0:" "0"`→
  `ACK [50@0] {load} No such playlist`(POSITION不正より先にプレイリスト存在チェックが効く)、
  POSITION省略時の従来動作(末尾へ追加のみ)も無変更で回帰なし、`load`成功後
  `status`の`lastloadedplaylist`も正しく追従(mpdlastloadedplaylist-patchとの相互作用も
  問題なし)。旧来の `tagtypes`/`list album`/`search any sort+window併用`/`count any`/
  `crossfade`/`getvol`/`listplaylists`/`sticker get`/`playlistfind filename`の回帰なし。
  mopidy.log に Traceback 3件のみ(`save`実行時の mopidy_ytmusic 側 create_playlist が
  このテストアカウントの書き込み権限不足で HTTP 401 を出す既知の pre-existing な挙動 —
  mpdlastloadedplaylist-patch.py/mpdversion-patch.py の検証時にも確認済みの `save`
  自体の挙動であり、POSITION指定なしの `load` のみを行う対照実験でも同一のTracebackが
  出ることを確認し、本パッチによる新規リグレッションではないと確定)。
- [x] `sticker set`/`sticker delete` が idle "sticker" イベントを一切発火しない件。実 MPD
  (MusicPlayerDaemon/MPD src/command/StickerCommands.cxx handle_sticker_song /
  src/protocol/IdleFlags.cxx IDLE_STICKER) を実際に clone してソース確認したところ、実MPDは
  sticker set/delete 成功時に必ず idle "sticker" を発火する仕様と判明。一方 mopidy_mpd 3.3.0
  (+ mpdsticker-patch.py) は書き込み成功時に一切通知を送らず、status.py の SUBSYSTEMS にも
  "sticker" 自体が未登録のため、bare `idle` は元より明示的な `idle sticker` を送っても
  以後二度と `changed: sticker` が来ない。TODO 全項目消化済みのため自走エージェントが
  rmpc 本体 (mierak/rmpc) を実際に clone して調査したところ、rmpc-mpd/src/commands/idle.rs
  の IdleEvent::Sticker と rmpc/src/core/event_loop.rs の handle_idle_event が受信時に
  ctx.stickers_supported が真なら表示中の全曲の sticker (rating/like 等、rmpc/src/ctx.rs の
  RATING_STICKER/LIKE_STICKER) を再フェッチし UiEvent::Sticker で画面反映する実装であること、
  かつ主イベントループが `client.enter_idle(None)` (bare idle、SUBSYSTEMS既定集合を購読) を
  使うことを確認した上で、あるクライアント/別接続がrating・likeを更新しても他のrmpc接続の
  一覧表示がidle経由では永久に再フェッチされない実害あるギャップと確認し新規発見・追加した項目。
  verified: mpdstickeridle-patch.py。mpdmount-patch.py/mpdchannels-patch.py と同じ機構
  (`mopidy.listener.send(session.MpdSession, "sticker")`、pykka の `.tell()` 経由で
  スレッドセーフに全セッションへブロードキャスト) を再利用し、sticker set/delete が
  例外を投げず成功した場合のみ通知するよう stickers.py に `_mpdsticker_notify()` を追加、
  status.py の SUBSYSTEMS に "sticker" を追加 (playlist と stored_playlist の間に
  アルファベット順で挿入)。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で
  構文確認、2回適用しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し、2本のTCP接続(A/B)で MPD プロトコルを直接叩いて確認 —
  A `idle sticker`(明示)後にB `sticker set song "..." "rating" "5"` →
  A が `changed: sticker` で即時起床、A 再度 `idle`(bare、引数無し)後にB
  `sticker delete song "..." "rating"` → 同様に `changed: sticker` で起床(SUBSYSTEMS
  追加によりbare idleでも拾えることを確認)。旧来の `sticker set`/`get`/`list`/`find`
  (演算子/sort/window付き含む)・`sticker find ... badop`(`ACK Unknown sticker
  operator`)・`sticker get`(存在しない、`ACK no such sticker`)は無変更で回帰なし、
  `tagtypes`/`list album`/`search any "yoasobi"`(実データ)/`count any`/`status`/
  `listmounts`/`listpartitions`/`channels` の回帰なし・mopidy.log に Traceback/ERROR
  0件を確認。
- [x] `stringnormalization` (MPD 0.25+, diacritics除去): mpdversion-patch.py が
  「stringnormalization は未実装のため 0.25 は名乗らない」と明記して VERSION を
  0.24.0 に意図的に留めていた既知の残課題。TODO 全項目消化済みのため自走エージェントが
  rmpc 本体 (mierak/rmpc) を実際に clone して調査したところ、rmpc-mpd/src/client.rs の
  `search()` が `supported_commands.contains("stringnormalization")` かつ
  ignore_diacritics 有効時に `stringnormalization enable/disable strip_diacritics` を
  コマンドリストで送る実装であること、rmpc/src/ui/panes/search/mod.rs の検索ペインが
  `strip_diacritics_supported: ctx.mpd_version >= Version::new(0, 25, 0)` の場合のみ
  「Ignore diacritics」トグルを表示すること (現状 VERSION 0.24.0 のため丸ごと非表示)
  を確認し、実装可能と判断して着手した項目。
  verified: mpdstringnorm-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/ClientCommands.cxx handle_string_normalization,
  src/client/StringNormalization.{hxx,cxx}, src/lib/icu/Canonicalize.cxx) を実際に
  clone してソース確認し仕様を確定 (対応FEATUREは strip_diacritics の1種のみ、
  アルゴリズムは "NFD; 結合文字(Mark)除去; NFC"、状態は接続ごとで切断で破棄、
  未知サブコマンド→`ACK Unknown sub command`、enable/disable引数無し→
  `ACK Not enough arguments`、未知FEATURE→`ACK Unknown string normalization`、
  all/clear/available に余分な引数→`ACK Too many arguments`)。`context.session.tagtypes`
  と同じ流儀で `context.session.string_normalization` (set) をセッション属性として追加、
  connection.py に `stringnormalization` コマンドを新設。実 MPD 調査の結果、
  strip_diacritics が実際に効くのは search/searchadd/searchaddpl/searchcount/
  playlistsearch のみ (find/playlistfindには効かない仕様) と判明したが、mopidy_mpd の
  `search`/`find`/`count`/`list` は全て `context.core.library.search()` 経由で
  バックエンド(mopidy-ytmusicなら実際のリモートYouTube Music検索API)へ丸投げしており
  ローカル文字列比較を一切行わないため、対象コードが存在せず適用不能と判明 (mount/
  crossfadeと同種の割り切り、状態保持・プロトコル往復のみ)。唯一ローカルに文字列比較を
  行う `playlistsearch` (mpdplaylistfind-patch.py の `_pf_matches`/`_pf_search`) には
  実際に diacritics 除去 (NFD分解→`unicodedata.combining()`で結合文字除去→NFC再合成、
  実MPDのICU transliteratorと同一アルゴリズム) を追加。合わせて mpdversion-patch.py の
  VERSION を 0.24.0→0.25.0 へ引き上げ (rmpc-mpd/src/mpd_client.rs 全体・rmpc/src/ui/mod.rs・
  rmpc/src/core/command.rs を実際に grep し 0.25.0 でこれ以外に新規バージョンゲートされる
  機能が無いことも確認済み)。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で
  構文確認、2回適用しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し MPD で確認 — greeting `OK MPD 0.25.0`(旧0.24.0から変化)、
  `stringnormalization`(初期・引数無し)→空でOK、`stringnormalization available`→
  `stringnormalization: strip_diacritics`、`stringnormalization enable strip_diacritics`→
  OK・以後`stringnormalization`(引数無し)→`stringnormalization: strip_diacritics`、
  `stringnormalization disable strip_diacritics`→OK・以後空、`stringnormalization all`→
  有効化、`stringnormalization clear`→無効化、`stringnormalization enable bogus`→
  `ACK Unknown string normalization`、`stringnormalization enable`(引数無し)→
  `ACK Not enough arguments`、`stringnormalization all extra`(余分な引数)→
  `ACK Too many arguments`、`stringnormalization bogus`(未知サブコマンド)→
  `ACK Unknown sub command`。実データ(`search any "Celine Dion Resume"`でヒットした
  Artist「Céline Dion」の曲 `ytmusic:track:X_hxmjJSYOU` を`add`でキューに積み)
  `playlistsearch artist "celine"`(diacritics無効時、既定)→0件、
  `stringnormalization enable strip_diacritics`後に同じ`playlistsearch artist "celine"`
  →1件ヒット(「Céline Dion」を正しくマッチ)、`playlistfind artist "celine"`(strict、
  diacritics有効時でも)→0件のまま(実MPD仕様通りplaylistfindには効かない)、
  アクセント付きのまま検索する`playlistsearch artist "Céline"`はdiacritics設定に関わらず
  常にヒットすることを確認。状態が接続ごとであること(別TCP接続Bでは`stringnormalization`
  が独立して空のまま・`playlistsearch artist "celine"`も0件)も2本のTCP接続で実測。
  旧来の`playlistfind filename`(FILTER式/sort/window)/`search any "yoasobi" sort -Date
  window "0:2"`/`tagtypes`/`list album`/`count any "yoasobi"`/`status`/`getvol`/
  `crossfade 5`/`listplaylists`の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: 実MPDの`search`/`searchadd`/`searchaddpl`/`searchcount`にもstrip_diacritics
  が効くが、mopidy_mpdのこれらは全てバックエンドのリモート検索APIへ丸投げのためローカル
  文字列比較の対象コードが存在せず適用対象外 (mount/crossfadeと同種の限界、上記参照)。
- [x] フィルタ式の `!=`/`!~` (not-equal/not-regex) 演算子: mpdsearch-patch.py の
  `_query_from_mpd_filter_expression` が「否定/OR は best-effort でスキップ」と明記した上で
  `!=`/`!~` を単純に読み捨てており、`find`/`search`/`findadd`/`searchadd`/`searchaddpl`/
  `count`/`playlistfind`/`playlistsearch` 全てで同じ挙動だった。TODO 全項目消化済みのため
  自走エージェントが調査して新規発見・追加した項目。rmpc 本体 (mierak/rmpc) を実際に clone
  してソース確認したところ、rmpc-mpd/src/filter.rs の `FilterKind` に Exact/StartsWith/
  Contains/Regex/NotExact/NotRegex/CustomQuery があり、rmpc/src/ui/panes/search/inputs.rs の
  検索ペイン `SearchMode` の NotExact/NotRegex がそのまま対応する実在の検索モードであること、
  加えて rmpc/src/config/search.rs の `custom_query`(既定false、ユーザがconfigで有効化する
  オプトイン機能)を有効にすると rmpc/src/ui/panes/search/mod.rs の `search()` がユーザ入力の
  フィルタ式文字列を(他の条件とAND結合したものを含め)ほぼそのまま `find`/`search` に渡す
  ことを確認した上で、dev mopidy(6601, ytmusic実アカウント) に実際に
  `find "(Artist == \"YOASOBI\") AND (Genre != \"Rock\")"` を送って `Genre != "Rock"` 条件が
  完全に無視され `Artist == "YOASOBI"` 単独と同じ全曲(177行)が返るサイレントな不正確さを
  実機で再現確認した上で着手。
  verified: mpdnegfilter-patch.py。実 MPD 仕様は WebFetch で mpd.readthedocs.io/protocol.html
  の Filters 節を確認し確定 (find/playlistfind=大文字小文字区別、search/searchadd/
  searchaddpl/count/playlistsearch=区別しない。`!=`はタグの全値のいずれとも一致しないことが
  条件を満たす条件=いずれか1つでも一致したら除外)。`_query_from_mpd_filter_expression`を
  `!=`/`!~`を読み捨てず`(field, is_regex, value)`のリストとして集約し、返すquery dictに
  隠しキー`__mpd_negatives__`として載せる方式に変更、`_mpd_pop_negatives()`で必ずバックエンド
  丸投げ前にpopしてから使う。positiveな条件と違い、find/search/findadd/searchadd/
  searchaddpl/count(非group)は`context.core.library.search()`で取得済みのTrackオブジェクトに
  対しローカルな文字列/正規表現比較で後段フィルタするだけで完結するため、mount/crossfade/
  stringnormalization-on-searchのような「バックエンドに丸投げのため対応不能」という制約が
  本質的に存在しない(取得後のローカルデータへの後処理のため)。playlistfind/playlistsearch
  (mpdplaylistfind-patch.py)は同じ関数を再利用しキュー内をローカル走査するため、`_pf_matches`
  に否定条件チェックを追加するだけで対応(`__mpd_negatives__`キーが素通しされると
  `_pf_matches`のfield/needlesループがタプルのリストを文字列needle列として誤扱いし常に
  0件になる回帰が起きるところだったため、`_pf_search`側で明示的にpopする形で回避)。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等
  (スキップ)であることも確認。dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで
  確認 — `find "(Artist == \"YOASOBI\") AND (Title != \"アイドル\")"`→22件中「アイドル」の
  1件のみ除外され21件(177行→169行)、`search "(artist == \"yoasobi\") AND (title !=
  \"アイドル\")"`(小文字・大小無視)→同様に除外、`AND (Title != \"アイドル\") AND (Title !=
  \"群青\")`(否定条件2つ)→両方除外、`Title !~ \"^ア.*\"`(正規表現否定)→「アイドル」のみ
  除外し「アドレナ」(Albumフィールドで別物)は無関係のため残存、`count`→5→4件に減少、
  `findadd`→実際にキューに4曲追加されplaylistinfoで「アイドル」抜けを確認、`searchadd`/
  `searchaddpl`→同様に正しく除外、`playlistfind`/`playlistsearch`(キュー内、既存4曲から
  「怪物」除外)→3曲のみヒット。case-sensitivity実測: `find "(Artist == \"YOASOBI\") AND
  (Artist != \"yoasobi\")"`(find=大文字小文字区別、小文字needleは大文字valueと不一致)→
  何も除外されず177行のまま、`search "(artist == \"yoasobi\") AND (artist !=
  \"yoasobi\")"`(search=区別しない)→一致してartist=YOASOBIの曲が実際に除外され件数減少、
  の違いを確認。不正な正規表現`Title !~ \"(unclosed\"`→クラッシュせず該当条件を無視して
  177行のまま返る(re.compile例外を捕捉)ことも確認。既知の制約(mount/crossfadeと同種の
  割り切り): フィルタが`!=`/`!~`のみ(positiveな条件が皆無)の場合は従来通り`ACK incorrect
  arguments`のまま(実機で`find "(Artist != \"YOASOBI\")"`等が変化なくACKになることを確認)
  — mopidy-ytmusicはリモート検索APIのみで「全曲取得」手段がなく(get_distinctはタグの
  distinct値であって曲一覧ではない)原理的に代替不能なため。rmpcの検索ペインは検索モードを
  全入力欄に一括適用する設計のため、単一欄のみ入力してNotExact/NotRegexを選ぶとこのケースに
  該当し引き続き動作しない(複数欄併用や`custom_query`で他条件も含めれば動く)。
  `list`/グループ化`count group ...`は`get_distinct()`経由のためTrack単位の後段フィルタと
  相性が悪く対象外のまま(`!=`/`!~`混入時はqueryからpopするだけで従来通り無視、クラッシュは
  しないことを確認)。旧来の`tagtypes`/`list album group AlbumArtist`/`search any "yoasobi"
  sort -Date window "0:2"`/`status`/`crossfade 5`/`listmounts`/`listpartitions`/`channels`/
  `getvol`/`single "oneshot"`/`consume`/`update`/`stringnormalization enable
  strip_diacritics`+`playlistsearch`(diacritics)の回帰なし・mopidy.log に Traceback/ERROR
  0件(save "create" 時の既知の mopidy_ytmusic HTTP 401、本パッチ検証と無関係な
  pre-existing挙動、を除く)を確認。
- [x] queue の `Added` (MPD 0.24+、各曲がキューへ追加された時刻、ISO 8601): mopidy-mpd 3.3.0 の
  translator.track_to_mpd_format は Pos/Id/Prio は出力するが Added を一切出力しない。TODO
  全項目消化済みのため自走エージェントが調査して新規発見・追加した項目。rmpc 本体
  (mierak/rmpc) を実際に clone してソース確認したところ、rmpc-mpd/src/commands/
  current_song.rs の `Song` 構造体が "added" キーを専用フィールド
  `added: Option<DateTime<Utc>>` として解釈しており (コメントに "Option because it is
  present from mpd 0.24 onwards" と明記)、CHANGELOG.md v0.11.0 の "Added `Added()` ...
  song properties" で `SongProperty::Added()` として rmpc/src/ui/song_ext.rs
  (song_table_format のカラム表示) / rmpc/src/ui/dir_or_song.rs (キューの `Sort`/
  `SortByColumn` キーバインドでのソート) に実際に使われていることを確認した。musicpd.org
  protocol の "Other Metadata" 節も ISO 8601 形式で明記していることを WebFetch で確認。
  未対応のままだと rmpc でキューを Added 列で表示・ソートしても常に空欄のままになる実害
  あるギャップと確認した上で追加した項目。
  verified: mpdadded-patch.py。mopidy core の Track モデル自体は「キューに追加された時刻」
  という概念を持たない (last_modified はファイルの更新時刻でありキュー追加時刻とは無関係)
  ため、prio/crossfade/lastloadedplaylist と同じ揮発性ストア方式で translator.py に
  tlid -> ISO8601文字列を保持する2段構えの実装: (1) キューへ実際に曲を追加する各コマンド
  (current_playlist.py の add/addid、music_db.py の findadd/searchadd、
  stored_playlists.py の load) で `context.core.tracklist.add(...)` が同期的に返す新規
  TlTrack のtlidを使ってその場で即座にタイムスタンプを記録 (`translator.stamp_added`)。
  (2) mopidy core が発火する CoreListener の `tracklist_changed` イベント (delete/clear/
  move等キュー変更全般で発火) を actor.py の MpdFrontend.on_event で拾い、その時点の実際の
  tlid集合との差分を取ってキューから消えたtlidを揮発性ストアから破棄する (掃除のみ、非同期
  でも実害なし)。**(1)を追加した理由の実機検証**: 当初は(2)のCoreListenerイベントのみで
  実装したところ、`addid`直後に同じ接続で即座に`playlistinfo`を送ると、MpdFrontendアクター
  (Core本体とは別アクター、非同期メッセージ配送) がイベントをまだ処理し終えておらず
  `Added`が反映されていないレースを実機で再現・特定 (Traceback等クラッシュは起きないが
  値がサイレントに欠落する不具合)。(1)の同期stamp方式に切り替えて解消したことを確認。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等
  (スキップ)であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し実データ
  (YOASOBI検索結果のtrack URI) で MPD プロトコルを直接叩いて確認 — `addid URI`直後に同じ
  接続で`playlistinfo`→`Added: <ISO8601>`が即座に反映(レース無し)、2曲目`addid`→2曲目は
  1曲目と異なる(後の)タイムスタンプ、`delete 0`(1曲目削除)→残り1曲のAddedのみ表示、
  `clear`→Added行なしで空、`findadd "(any contains \"yoasobi\")"`(複数曲一括追加)→
  全曲に同時刻のAddedが反映、`playlistid`でも同様にAdded反映、ストアドプレイリストを
  `save "create"`で作成後`clear`→`load NAME "0:" "0"`(POSITION付きload)→ロードされた
  全曲に即座にAddedが反映(`playlistinfo`/`playlistid`両方で確認)。旧来の`tagtypes`/
  `status`/`search any sort+window併用`/`list album`/`list Album group AlbumArtist`/
  `count any`/`crossfade`/`getvol`/`listplaylists`/`listmounts`/`listpartitions`/
  `channels`/`sticker get`(no such sticker応答)/`stringnormalization`/`playlistfind
  filename`/`single`/`consume`/`update`の回帰なし・mopidy.log に Traceback/ERROR 0件
  (save "create" 時の既知の mopidy_ytmusic HTTP 401、本パッチ検証と無関係な pre-existing
  挙動、を除く)を確認。
- [x] `outputs` に `plugin` フィールドが無い: mopidy-mpd 3.3.0 の audio_output.py の
  `outputs()` は outputid/outputname/outputenabled の3フィールドしか返さない。TODO
  全項目消化済みのため自走エージェントが調査して新規発見・追加した項目。musicpd.org
  protocol (audio output devices 節) を WebFetch で確認したところ、`outputs` は
  outputid/outputname/plugin/outputenabled/attribute の順で `plugin` を常時返す仕様
  (例: `plugin: alsa`) と判明。実際に rmpc 本体 (mierak/rmpc) を clone してソース確認
  したところ、rmpc-mpd/src/commands/outputs.rs の `Output` 構造体が `plugin: String`
  を専用フィールドとしてパースし、rmpc/src/ui/modals/outputs.rs のアウトプット一覧
  モーダルが実際に "Plugin" 列として描画している (`Cell::new(output.plugin.as_str())`)
  ことを確認。plugin キーが応答に無くても FromMpd 側は未知キーとして黙って無視する
  ためクラッシュはしないが、常に空欄の列になり実 MPD 互換の情報が欠落する実害を確認した。
  verified: mpdoutputplugin-patch.py。mopidy core (mixer.py) は GStreamer レベルの
  出力プラグイン概念を持たず、audio_output.py が返す "Mute" は実出力ではなく
  core.mixer の mute 状態を模した仮想出力 (outputname も "Mute" 固定のハードコード)
  のため、plugin も同様に固定文字列 "mopidy" を返す実装 (crossfade/mount 等と同じく
  「プロトコル層の応答を仕様に合わせるだけで実体を持たない」既知の限界)。生成後ソースは
  一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも
  確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `outputs` → `outputid: 0` / `outputname: Mute` / `plugin: mopidy` / `outputenabled: 0`
  (実MPD準拠の順序)、`disableoutput 0`→OK・以後`outputs`→`outputenabled: 0`のまま
  plugin行も維持、`enableoutput 0`→OK・`outputenabled: 1`、`toggleoutput 0`→トグルされ
  plugin行は常に維持されることを確認。旧来の `search any sort+window併用`/`list album`/
  `count any`/`sticker get`(no such sticker応答)/`listmounts`/`listpartitions`/
  `channels`/`status`/`tagtypes` の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] mopidy_ytmusic の `YTMusicPlaylistsProvider.save()` (playlist.py) に実データを破壊しうる
  バグを発見: `newIds` の計算が `set([parse_uri(p.uri)[0] for p in playlist.tracks])` に
  なっており、`parse_uri(uri)` は library.py が生成する実際のトラックURI形式
  ("ytmusic:track:{videoId}", 3コロン区切り) から videoId 文字列そのものを返す
  にも関わらず、その戻り値へさらに `[0]` で添字アクセスしているため videoId の
  「先頭1文字」だけが newIds に入ってしまう不具合。一方 `oldIds` は
  `t["videoId"]` を正しくフルで使っているため、`common = oldIds & newIds` が
  実質的に常に空集合になり、`remove = oldIds ^ common` が実質「プレイリスト内の
  既存曲全て」になる。つまり `playlistadd`/`playlistdelete`/`playlistmove`/`rename`
  等、mopidy_mpd の stored_playlists.py が `core.playlists.save()` を経由する
  あらゆる MPD コマンドが、実 YouTube Music 上の既存プレイリストを保存するたびに
  現在の全曲を `remove_playlist_items()` で実際に削除してしまう (add側は1文字の
  偽videoIdなので `add_playlist_items` が失敗するだけで実害はないが、remove側は
  本物の既存videoIdの集合そのものなので実際に消える)。従来の「プレイリスト編集系」
  backlog 項目の検証は「破壊的操作はスコープ外」として検証用スタブ backend
  でのみ確認しており、実 YouTube Music アカウントへの `save()` 実行を避けていた
  ためこのバグは見逃されていた。自走エージェントが新たな「曲順を反映する
  reorder」機能を実装・検証する過程でオフライン単体テストにより偶然発見した。
  合わせて、`save()` は既存/新規トラック列を videoId の「集合」の差分としてしか
  見ておらず曲順の変化を一切 YouTube Music 側へ反映しないため、上記バグを修正した
  後も `playlistmove` は「OK は返るが実際の並び順は変化しない」ままになる欠落も
  確認したため、この2つをまとめて修正した。
  verified: ytplaylistreorder-patch.py。(1) `parse_uri(p.uri)[0]` の `[0]` を除去し
  フル videoId を使うよう修正。(2) ytmusicapi.edit_playlist(moveItem=(setVideoId,
  successor_setVideoId)) で「setVideoId のアイテムを successor の直前へ移動」できる
  ことを ytmusicapi 本体 (sigma67/ytmusicapi) を実際に clone して
  tests/mixins/test_playlists.py test_edit_playlist で実証済みの仕様として確認した
  上で、目的順序の末尾ペアから先頭へ向かって「1つ前の曲を次の曲の直前へ移動」を
  繰り返すことで任意の初期順序から目的順序を復元するアルゴリズムを実装
  (n-1回のmoveItemで完成、末尾から処理するためすでに確定させた並びを崩さない)。
  新規追加された曲の setVideoId は `add_playlist_items()` のレスポンス
  (playlistEditResults) から取得し、取得できない曲があれば並べ替えは諦めて
  従来通り (add/remove のみ、クラッシュしない) に留める。冗長な API 呼び出しを
  避けるため、remove適用後+add追記(末尾) で推定される現在の並びを手元で追跡し、
  既に目的の隣接関係になっている箇所は `moveItem` を送らずスキップする。
  検証は、実 YouTube Music アカウントでの `save()` 呼び出しがこのテスト環境では
  `create_playlist` がアカウントの書き込み権限不足で HTTP 401 になり
  (mpdlastloadedplaylist-patch.py/mpdversion-patch.py 検証時にも確認済みの
  既知の pre-existing な制約で、実際には mopidy core の PlaylistsController が
  m3u バックエンドへフォールバックして作成される) 実 ytmusic プレイリストに
  対する end-to-end 確認ができないため、setVideoId 付きの偽 YTMusic API を
  実装したオフライン単体テストで検証: 純粋な並べ替え (D,B,A,C)、6曲の完全逆順、
  新規曲を追加しつつ並べ替え (NEW,A,B)、削除しつつ並べ替え (B削除後C,A)、
  部分的な並べ替え (5曲中1回の move で完成) で最終順序が全て正しく反映されること、
  順序が変わらない場合や既に隣接済みの箇所では `moveItem` が呼ばれないこと
  (冗長呼び出しの抑制)、setVideoId が解決できない曲があればクラッシュせず
  並べ替えのみスキップされること、rename と reorder の併用、単曲プレイリストで
  クラッシュしないこと、を全て確認 (16項目)。**truncationバグの再現確認**: 修正前
  相当のロジックで videoId "existingA"/"existingB" が入った既存プレイリストに
  新規曲 "NEWTRACK" を追加保存すると、修正前は既存曲が誤って remove 対象になって
  いたはずのところ、修正後は既存曲が一切 remove されず新規曲のみ正しくフルの
  videoId で add されることをオフラインテストで実証。パッチ適用後の生成ソースは
  一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)である
  ことも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で
  確認 — 上記の通り `create_playlist` の既知の401制約によりm3uへフォールバックで
  `save "create"`→`listplaylistinfo`が正常応答すること、`rm`で後片付けできること、
  クリーン起動・回帰なしを確認。旧来の `count any`/`list album group AlbumArtist`/
  `search any sort+window併用`/`crossfade`/`getvol`/`listmounts`/`listpartitions`/
  `channels`/`sticker get`(no such sticker応答)/`tagtypes`/`status` の回帰なし・
  mopidy.log に Traceback は上記の既知の401 (create_playlist、本パッチ非対象の
  pre-existing挙動) 1件のみで新規リグレッションなしを確認。
  既知の制約: 同一 videoId が複数箇所にあるプレイリストは videoId->setVideoId が
  1対1にならないため、従来の集合差分ロジック自体の既知の限界に倣い並べ替えも
  対象外のまま (該当曲のsetVideoIdが曖昧になり得るため安全側でスキップされる)。
  このテストアカウントの書き込み権限制約により、実 YouTube Music プレイリストに
  対する reorder の end-to-end 実証は本item のスコープでは不可能なまま
  (オフライン単体テストによる論理検証のみ、mpdlastloadedplaylist-patch.py 等の
  save() 系検証と同種の限界)。
- [x] `mixrampdb`/`mixrampdelay` が `raise MpdNotImplemented` のスタブで常に ACK エラーになる件:
  mopidy-mpd 3.3.0 の playback.py はこの2コマンドを未実装のまま残しており、標準 MPD クライアント/
  汎用ツールが送ると実 MPD なら OK になるところ ACK エラーで拒否される。加えて `mixrampdelay` の
  引数型が `protocol.UINT` (`\d+` のみ許可) になっており、実 MPD 仕様 (musicpd.org, WebFetch で確認)
  が許可する小数秒や無効化用の特殊値 `"nan"` を渡すと ValueError で弾かれる欠陥も確認。TODO 全項目
  消化済みのため自走エージェントが調査して新規発見・追加した項目。rmpc本体 (mierak/rmpc) を
  gh api で確認したところ rmpc-mpd/src/commands/status.rs の `Status` 構造体は status 応答の
  `mixrampdb`/`mixrampdelay` フィールドを既にパース対象にしているが、rmpc 自身がこの2コマンドを
  送信する UI 導線 (keybinding action 等) は持たない (`send_mixrampdb`/`send_mixrampdelay` が
  mpd_client.rs に存在しない、actions.rs にも "Mixramp" 系アクション無し) ことを確認済み。実害は
  「rmpc固有」ではなく crossfade/decoders/outputs plugin と同種の「標準 MPD プロトコル準拠」の不備。
  実 MPD (MusicPlayerDaemon/MPD の src/command/PlayerCommands.cxx を gh api で確認) の `status` は
  `mixrampdb` を常時、`mixrampdelay` は値が0より大きい時のみ返す仕様と判明。
  verified: mpdmixramp-patch.py。crossfade (mpdcrossfade-patch.py) と同じ流儀で translator.py に
  揮発性ストア (`_mixrampdb` 初期値0.0、`_mixrampdelay` 初期値nan=実MPDの無効化デフォルトに合わせる)
  を追加し、`mixrampdb`/`mixrampdelay` コマンドで更新、`status` へ反映 (`mixrampdb`は常時、
  `mixrampdelay`は>0の時のみ)。`mixrampdelay`の引数型は `protocol.UINT`→`protocol.FLOAT` へ修正し
  小数秒・`nan`を受理できるようにした。生成後ソースは一時コピー (nixストアからの読み取り専用コピーに
  `chmod u+w` して書き込み可にした上で) に当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)
  であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 — `status`で
  `mixrampdb: 0.0`(初期値、常時表示)・`mixrampdelay`フィールド無し(初期値nan)、`mixrampdb -17`→OK・
  以後`status`で`mixrampdb: -17.0`、`mixrampdelay 5.5`→OK・以後`status`で`mixrampdelay: 5.5`が追加、
  `mixrampdelay nan`→OK・以後`status`で`mixrampdelay`フィールドが消える(nan>0はFalseなので非表示、
  実MPD仕様通り)、`mixrampdb 0`/`mixrampdelay 0`→OK・`status`で`mixrampdb: 0.0`・`mixrampdelay`
  フィールド無し(0>0はFalse)を確認。旧来の`crossfade`/`single oneshot`/`consume oneshot`/`getvol`/
  `listmounts`/`listpartitions`/`channels`/`sticker get`(no such sticker応答)/`count any`/
  `list album group AlbumArtist`/`tagtypes`の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: crossfade と同じく mopidy core 自体は GStreamer レベルの MixRamp/クロスフェード機能を
  持たないため、この値が実際の再生へ影響することはない (プロトコル応答・status フィールド反映のみ)。
- [x] `findadd`/`searchadd` の `[sort TYPE] [window START:END] [position POS]` 修飾子 (MPD 0.24+)
  未対応: mopidy-mpd 3.3.0 の両コマンドは `{TYPE} {WHAT} [...]` の生の args をそのまま
  `_query_from_mpd_search_parameters` に渡すだけで、フィルタ式形式
  (`findadd "(Artist == \"X\")"`) の場合は同関数が args[0] しか見ないため、末尾に付いた
  `sort ...`/`window ...`/`position ...` トークンが ACK エラーにすらならず黙って無視される
  (クラッシュはしないが要求を静かに無視し、常に末尾へ無条件追加してしまう不具合)。TODO 全項目
  消化済みのため自走エージェントが rmpc 本体 (mierak/rmpc) を実際に clone して調査したところ、
  rmpc-mpd/src/mpd_client.rs の `send_find_add` が `findadd "(FILTER)" position POS` を
  実際に送信しており (searchadd は trait に定義はあるが呼び出し元皆無で未使用、searchaddpl は
  rmpc に送信箇所自体が無い = 既存の addid/add/load POSITION 系項目と同じ「クライアントtraitに
  定義はあるが一部は死んでいる」パターンと確認)、rmpc/src/shared/mpd_client_ext.rs の
  `enqueue_multiple` から `Enqueue::Find { filter }` 経由で呼ばれ、実際に
  rmpc/src/ui/panes/search/mod.rs の検索結果ペインで「現在の曲の次に追加」「前に追加」等の
  位置指定つき追加アクション (rmpc/src/config/keys/actions.rs
  Position::AfterCurrentSong/BeforeCurrentSong) を検索結果に対して実行すると
  `findadd "(...)" position "+0"` が送られると確認した。dev mopidy(6601, ytmusic実アカウント)
  で実際に `findadd "(any contains \"米津\")" position "+0"` を送って再現したところ ACK
  エラーにはならず OK が返るが、期待通りの位置(現在曲の直後)ではなく常に末尾に追加される
  サイレントな不具合を実機で確認した上で着手。
  verified: mpdfindaddpos-patch.py。musicpd.org protocol (WebFetch で確認):
  `findadd {FILTER} [sort {TYPE}] [window {START:END}] [position POS]` / `searchadd` も同形式、
  position は addid と同じ絶対/相対 (+N/-N, 現在曲基準) 指定。mpdsort-patch.py/
  mpdwindow-patch.py が既に music_db.py に用意した `_mpd_extract_sort_params`/
  `_mpd_sort_tracks`/`_mpd_parse_window` をそのまま再利用し (同一ファイル内のため
  cross-file import不要)、position だけ mpdaddpos-patch.py/mpdloadpos-patch.py と同じ
  MoveRange アルゴリズム (mopidy core の tracklist.move(start, end, to_position) で「末尾に
  追加してから範囲ごと move」) を移植。findadd の大文字小文字区別 (exact=True)・searchadd の
  非区別という既存の差異は無変更で維持。searchaddpl は rmpc から一切送信されないため対象外
  (position 未対応のまま)。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認 (nix ストアからの読み取り専用コピーは
  `chmod`/`cp -R`/`tar` では権限が正しく引き継がれない環境だったため、Python の
  `shutil.copytree` 後に全ファイルへ明示的に `os.chmod` して書き込み可にした上で検証)。加えて
  `_mpd_extract_addpos_params`/`_mpd_parse_addpos_position` の単体テストをオフラインで実施
  (sort+window+positionの組み合わせ抽出、フィルタ式+position、"any"タグの値がたまたま
  "position"になるケースで誤爆しないこと、非数値positionでMpdArgError、を確認)。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し実データで MPD プロトコルを直接叩いて
  確認 — 3曲キュー+`play "1"`(pos1を実際に再生開始、`status`のstate:play/song:1/songidで確認)の
  状態で `findadd "(any contains \"米津\")" position "+0"`→新規3曲が現在曲の直後(pos2-4)に
  挿入され元の3曲目が末尾にシフト、再生中の曲(songid)・再生位置は無変更(中断なし)、
  `position "-0"`→現在曲の直前に挿入され現在曲のPosが+3シフト(songidは不変=同じ曲が再生継続、
  elapsedも継続して増加)、絶対位置 `position "0"`→キュー先頭に正しく挿入、
  `sort Title window "0:2" position "0"`(sort+window+position併用)→ソート後に2件へ
  スライスしてから正しく挿入、`searchadd "(...)" position "+0"`(case-insensitive経路)も
  同様に正しく動作。エラー系: 絶対位置の範囲外 `position "999"`→
  `ACK [2@0] {findadd} Bad song index`、非数値 `position "abc"`→
  `ACK [2@0] {findadd} incorrect arguments`、未知 `sort Bogus`→
  `ACK [2@0] {findadd} Unknown sort type: Bogus`、不正 `window "a:b"`→
  `ACK [2@0] {findadd} Invalid window: a:b`、キューが空(現在曲なし)で相対指定
  `position "+0"`→`ACK [55@0] {findadd} No current song`。POSITION省略時の従来動作
  (`findadd any "yoasobi"`、末尾へ無条件追加)も無変更で回帰なし、0件ヒット時
  (`findadd any "zzzznonexistentqueryxyz"`)もクラッシュせずOK・空キューのまま。旧来の
  `tagtypes`/`list album`/`search any "yoasobi" sort -Date window "0:2"`/`count any`/
  `sticker get`(no such sticker応答)/`crossfade 5`/`getvol`/`listplaylists`/`channels`/
  `listmounts`の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `playlistdelete`/`playlistmove` (ストアドプレイリスト編集系) の SONGPOS/FROM が
  `START:END` レンジ指定を受け付けない: mopidy-mpd 3.3.0 は `playlistdelete`
  (`songpos=protocol.UINT`)・`playlistmove` (`from_pos=protocol.UINT`) とも単一の非負
  整数のみで、実 MPD 0.23.3+/0.24+ のレンジ指定 (`START:END`) 未対応。TODO 全項目
  消化済みのため自走エージェントが調査して新規発見・追加した項目。musicpd.org
  protocol (WebFetch で確認) によれば `playlistdelete {NAME} {SONGPOS}` の SONGPOS は
  MPD 0.23.3 からレンジ指定可、`playlistmove {NAME} [{FROM}|{START:END}] {TO}` の
  FROM 側レンジ指定は MPD 0.24 から可能。rmpc 本体 (mierak/rmpc) を実際に clone して
  ソース確認したところ、`rmpc/src/ui/panes/playlists.rs` の `move_selected()` が
  プレイリストペインで複数曲をマーク(visual-select)した状態で上下移動キーバインドを
  実行すると、選択中の連続レンジを `client.move_in_playlist(&playlist, &range,
  new_idx)` 経由で `playlistmove NAME "START:END" TO` として実際に送信すると確認
  (`rmpc-mpd/src/mpd_client.rs` send_move_in_playlist のデフォルト実装)。固定 UINT
  実装では余分なコロンを含むトークンが `ACK incorrect arguments` になり、プレイリスト
  ペインでの複数選択移動が丸ごと失敗する実害あるギャップと確認した上で着手
  (`playlistdelete` は rmpc からレンジ送信される実際の呼び出し箇所は未確認だが、同じ
  `stored_playlists.py` の同種コマンドとして仕様準拠のため合わせて対応)。
  verified: mpdplaylistrange-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/PlaylistCommands.cxx handle_playlistdelete/handle_playlistmove,
  src/PlaylistFile.{hxx,cxx} PlaylistFileEditor::RemoveRange/MoveIndex,
  src/protocol/RangeArg.hxx) を実際に gh api で確認し仕様を確定 —
  `playlistdelete` は RemoveRange (CheckClip: start > 曲数なら `Bad song index`、
  end は曲数へ自動クリップ、開放端 `START:` も可) 相当、`playlistmove` は MoveIndex
  (「レンジを切り出してから、切り出し後の配列に対する位置TOへ挿入」、
  `from.start == to` なら実 MPD のコメント通りプレイリスト存在確認すらせず無条件で
  無変更OK、開放端レンジは明示的に `ACK Open-ended range not supported` で拒否)相当。
  既存の `protocol.RANGE`(mopidy_mpd/protocol/__init__.py、current_playlist.py の
  delete/move_range が既に使っている型)をそのまま再利用し、`songpos=protocol.UINT`→
  `songrange=protocol.RANGE`、`from_pos=protocol.UINT`→`from_range=protocol.RANGE`
  に差し替え、pop/insert の単純ロジックをスライス削除・カット&インサートに書き換え。
  まずオフラインのPythonロジック単体テスト(nixストア外の純粋関数として同アルゴリズムを
  再実装)で全パターン(レンジ削除・単一削除・開放端削除・境界値ちょうど`len`の単一指定
  →無変更でOK・start>lenで`Bad song index`、レンジ移動を先頭/末尾/範囲外/start==to
  no-op/開放端拒否の全パターン)を検証してから実環境に適用。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` して書き込み可にした上で `ast.parse` で構文確認、2回適用
  しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic 実アカウント) を
  実際に起動し実データ(検索で見つけた6曲のtrack URI)で `playlistadd` によりストアド
  プレイリストを作りMPDプロトコルを直接叩いて確認 — 6曲(A-F)に対し
  `playlistdelete NAME "1:3"`→B,C削除でA,D,E,F、続けて`playlistdelete NAME "2:"`
  (開放端)→E,F削除でA,D、境界値ちょうど曲数と同じ単一指定`playlistdelete NAME "2"`
  (曲数2に対し)→無変更でOK(実MPDのCheckClip仕様通り、ACKにならない)、
  `playlistdelete NAME "5:6"`(start>曲数)→`ACK Bad song index`。6曲に対し
  `playlistmove NAME "1:3" "0"`→B,C,A,D,E,F(先頭へ)、別の6曲に対し
  `playlistmove NAME "1:3" "3"`→A,D,E,B,C,F(切り出し後配列の位置3へ、実MPDの
  MoveIndexと同じセマンティクスを確認)、`playlistmove NAME "1:3" "5"`
  (切り出し後配列の許容範囲超過)→`ACK Bad song index`、`playlistmove NAME "1:3" "1"`
  (start==to、no-op)→無変更でOK、存在しないプレイリスト名でも`start==to`なら
  `ACK No such playlist`にならず無条件OK(実MPDの「存在確認すらしない」仕様を実機で
  再現確認)、`playlistmove NAME "1:" "0"`(開放端)→`ACK Open-ended range not
  supported`。旧来の単一インデックス指定(非レンジ)の`playlistdelete NAME "0"`/
  `playlistmove NAME "0" "2"`/範囲外`playlistdelete NAME "999"`→`ACK Bad song index`
  も無変更で回帰なしを確認。旧来の`tagtypes`/`status`/`count any "yoasobi"`の回帰なし・
  mopidy.log の Traceback は`save`(内部でplaylistadd等が使う`context.core.playlists.save`)
  実行時の既知の mopidy_ytmusic HTTP 401 (このテストアカウントの書き込み権限不足、
  mpdlastloadedplaylist-patch.py等の検証時にも確認済みの pre-existing な挙動) のみで
  新規リグレッションではないことを確認。
- [!] `listall` が mopidy_mpd の既定 `command_blacklist`(ext.conf: `listall,listallinfo`)
  により `ACK "listall" has been disabled in the server` で常に拒否される件: TODO 全項目
  消化済みのため自走エージェントが rmpc 本体 (mierak/rmpc) を実際に clone して調査した
  ところ、rmpc/src/ui/modals/add_random_modal.rs の AddRandomModal (グローバルアクション
  `AddRandom`、既定キーバインド `R`、モーダルの初期選択は `AddRandom::Song`) で何も
  変更せず Enter するだけの最も素朴な操作が、rmpc-mpd/src/client.rs `add_random_songs`
  経由で `listall` を送ることを確認 (`AddRandom::Artist/Album/AlbumArtist/Genre` は
  `list`+`findadd` 経由でこの制約を受けない)。dev mopidy(6601) で実際に `listall` を送り
  ブラックリスト拒否を実機確認した上で着手。
  blocked: mpdlistall-patch.py として ext.conf の command_blacklist から `listall` のみ
  除外 (listallinfo は維持) するパッチを実装・ast相当の文字列置換検証・冪等性確認まで
  完了させ、dev mopidy(6601, ytmusic 実アカウント) に実際に適用してビルド・起動まで
  成功したが、実機検証で重大な問題を発見したため revert し未コミットのまま破棄した。
  `listall`(引数無し、ルートから)を送ると mopidy_mpd の `context.browse()` が
  `context.core.library.browse(uri)` を深さ優先で再帰的に呼び続ける実装であり、
  mopidy-ytmusic backend の browse() はルート直下にユーザーのライブラリだけでなく
  Home/Explore 等の YouTube Music 全体のカタログ的セクションも含むため、再帰が
  事実上非有界(あるいは少なくとも非常に巨大)になることを実機で確認した。加えて
  その巡回の途中で ytmusicapi 側の未知のレスポンス形状 (`musicResponsiveListItemRenderer`
  等) に対するパーサのバグ (`KeyError: "Unable to find 'musicTwoRowItemRenderer' ..."`,
  navigation.py) に複数回ヒットし mopidy.log に大量の Traceback が出続けることも確認した。
  最も深刻な点: `listall` 実行中は同時に張った**別の**TCP接続から送った`status`
  (通常は即座に返る軽量コマンド)が10秒以上応答なしでタイムアウトすることを実機で確認 —
  mopidy の core actor (pykka) がこの1本の再帰 browse に専有され、他の全クライアントの
  MPD セッションがブロックされる deadlock 同然の状態になる。つまり「モーダルを開いて
  Enter するだけ」という最も素朴な rmpc 操作が mopidy サーバー全体を(接続している他の
  rmpc/クライアント含め)無応答にしてしまう、blacklist 解除前より深刻な実害を生む
  ことが判明した。これは mopidy_mpd 自身の docstring 警告 ("Do not use this command...
  will break with large databases") がまさに想定していた実害そのもので、特にリモートAPI
  丸投げ・非有界カタログを持つ mopidy-ytmusic backend では通常のローカルファイル
  ライブラリ以上に致命的となることが分かった。本項目のスコープ (configs/media/mopidy/
  と nix/lib/mopidy-env.nix のみ、mopidy core 自体はパッチ対象外) では、
  「browse の再帰に深さ/件数上限を設ける」「非同期化してcore actorを専有しないようにする」
  といった根本対策は mopidy_mpd/mopidy core 本体側の変更が必要でありパッチスクリプトの
  範囲を超えるため、安全な対応策が見つからず一旦 revert した。今後再挑戦する場合の
  方向性メモ: (a) `listall` 自体は解禁せず、mopidy-ytmusic 側の browse() が返す root
  Ref 一覧から「ユーザーのライブラリ由来」のノードだけに限定した独自の軽量代替コマンドを
  検討する、(b) `context.browse()` 相当のロジックを深さ制限・件数上限つきでラップする
  独自実装に差し替える、(c) rmpc 側は `AddRandom::Artist/Album/AlbumArtist/Genre` が
  既に正常動作するため、実害は「Song」タグ選択時のみに限定されている点を踏まえ、
  影響範囲は限定的と判断し優先度を下げる、のいずれか。
- [x] フィルタ式の肯定演算子 (`==` exact / `contains` / `starts_with` / `=~` regex) が区別されない件:
  mpdnegfilter-patch.py は `!=`/`!~` (否定) を実装したが、肯定側の演算子は
  `_query_from_mpd_filter_expression` が演算子そのものを読み捨てており、
  `(Artist == "X")` も `(Artist contains "X")` も `(Artist starts_with "X")` も
  `(Artist =~ "X")` も区別なく同じ `query["artist"] = ["X"]` として backend の
  library.search() に丸投げされ、結果は backend 依存の緩いマッチのまま返っていた。
  TODO 全項目消化済みのため自走エージェントが調査して新規発見・追加した項目。
  rmpc 本体 (mierak/rmpc) を実際に clone してソース確認したところ、
  rmpc/src/ui/panes/search/inputs.rs の `SearchMode` (検索ペインでキーバインドにより
  Exact/StartsWith/Contains/Regex/NotExact/NotRegex をユーザが明示的に切り替えられる
  実在の機能、既定は config の `FilterKindFile`、`cycle()`で巡回) が
  `FilterKind::Exact/StartsWith/Contains/Regex` (rmpc-mpd/src/filter.rs) として
  `find`/`search` に送信されると確認した上で着手 (`SearchMode::cycle`で誰でも到達できる
  UI操作であり、実害は「否定演算子と同様、ユーザ操作がサーバー側で無視される」)。
  verified: mpdfilterkind-patch.py。実 MPD 仕様は WebFetch で mpd.readthedocs.io/protocol.html
  の Filters 節を確認し確定 (`==`/`!=`=タグ値の完全一致・複数値タグは1つでも一致すればOK、
  `contains`=部分文字列、`starts_with`=前方一致、`=~`/`!~`=正規表現、find/playlistfindは
  大文字小文字区別・search/searchadd/searchaddpl/count/playlistsearchは区別しない)。
  mpdnegfilter-patch.py の negatives と全く同じ機構を肯定側にも追加: 否定でない演算子も
  `(field, kind, value)` を `positives` リストへ集約し `query["__mpd_positives__"]` に載せ
  (backendへの検索クエリ自体は従来通り `query[field]` へも積むため無変更=回帰なし)、
  `find`/`findadd`/`search`/`searchadd`/`searchaddpl`/`count`(非group) は取得済みの実
  Track データに対し演算子種別ごとの正しいローカル比較を後段フィルタとして適用
  (`_mpd_negative_field_values`をフィールド値抽出の汎用ヘルパとしてそのまま再利用)。
  `list`/グループ化`count group`はget_distinct経由のためTrack単位フィルタと相性が悪く
  pop-and-discardで対象外 (negativesと同じ既存の割り切り)。playlistfind/playlistsearch
  (mpdplaylistfind-patch.py) も同じ機構を再利用し `_pf_matches` に演算子種別チェックを
  追加。**実装中に発見・修正したバグ**: `_pf_matches`には元々「query dict の全フィールドを
  strict(exact list membership)/非strict(部分一致)で一律判定する」ベースループが既に
  存在し (mpdplaylistfind-patch.pyの既存実装)、これは演算子種別を持たない従来のTAG VALUE
  構文には正しいが、新たに追加した演算子種別ループと同じフィールドに対して二重に(かつ
  ベースループの一律ルールが優先されて)判定されると、例えば `playlistfind`
  (strict=True既定) で `(Title starts_with "怪")` を送った場合、ベースループが
  `"怪" in ["怪物"]`(完全一致)を要求し前方一致であるべき候補を誤って弾いてしまう不具合が
  offline単体テストで発覚。対策: positivesに演算子種別情報を持つフィールドはベース
  ループをスキップし (`_pf_positive_fields`集合でfield単位に除外)、演算子種別ループのみで
  判定するよう修正 (オフライン単体テストでこの不具合を実際に再現し、修正後にt1/t3の
  期待通りの合否を確認済み)。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で
  構文確認、2回適用しても冪等(スキップ)であることも確認。加えてスタブ化した
  mopidy_mpd/mopidy モジュールに対してオフラインで `_query_from_mpd_filter_expression`/
  `_mpd_filter_positives`/`_pf_matches` を直接呼び出す単体テスト (exact/contains/
  starts_with/regex 各演算子、大文字小文字区別・不問、否定との併用、不正な正規表現で
  クラッシュしないこと、legacy TAG VALUE構文が無変更であること、playlistfind/
  playlistsearchでのstrict/非strictと演算子種別の組み合わせ全パターン)を実施し全て合格。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動しMPDで実データ(YOASOBI)を使って確認 —
  `find "(Artist == \"YOASOBI\")"` → Artist値が厳密に"YOASOBI"の21件(実トラック5件+
  albumがqueryに無いため合成される既存仕様の"Title: Album: X"疑似トラック16件、
  count()は疑似トラックを含まず実トラックのみ数えるため`count "(Artist ==
  \"YOASOBI\")"`→songs:5と正しく一致することも確認)、`find "(Artist starts_with
  \"YOASOBI\")"`→前方一致で同じ21件、`find "(Artist starts_with \"ASOBI\")"`
  (前方一致でないので0件のはず)→0件で正しく空、`search "(Artist =~ \"^YOASOBI$\")"`→
  正規表現完全一致、`search "(Artist =~ \"(unclosed\")"`(不正な正規表現)→クラッシュせず
  該当条件を無視してACKにならず正常応答、`findadd "(Artist == \"YOASOBI\")"`→キューに
  実トラック5件のみ追加(疑似トラックはfindadd自体が元々`_get_tracks()`のみで対象外の
  ため無関係、positivesフィルタも正しく適用)、その後`playlistfind "(Title starts_with
  \"怪\")"`(strict既定+starts_with、上記で発見・修正したTOCTOU的バグの再現ケース)→
  「怪物」のみ正しくヒット、`playlistsearch "(Title == \"怪\")"`(非strict既定+exact、
  部分文字列"怪"は完全一致しないので0件のはず)→0件で正しく空、`playlistsearch
  "(Title contains \"怪\")"`→「怪物」がヒット。旧来の`search any "yoasobi"`/`sort+window
  併用`/`list album group AlbumArtist`/`count any`/`count group artist`/`tagtypes`/
  `getvol`/`crossfade`/`listmounts`/`listpartitions`/`channels`/`status`/`outputs`/
  `decoders`/`mixrampdb`/`single oneshot`/`consume`/`stringnormalization`/
  `listplaylists`/`playlistfind filename`(絶対一致)/`sticker get`(no such sticker応答)/
  `find "(Artist != \"YOASOBI\")"`(positiveな条件皆無、既存の`ACK incorrect
  arguments`のまま)の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約 (mount/crossfade・mpdnegfilter-patch.pyと同種の割り切り):
  `starts_with`/`contains`/`=~`のneedleが曖昧な部分文字列(例: "YOASO")だと、
  backend(mopidy-ytmusicのリモート検索API)がそもそも検索候補を返さないことがある
  (ローカルpost-filter自体は取得済み候補に対して常に正しく動作するが、候補取得自体は
  backendのフルテキスト検索品質に依存するため完全な再現率は保証できない)。
  `list`/グループ化`count group ...`は対象外のまま(`__mpd_positives__`混入時はpopする
  だけで従来通り無視、クラッシュはしない)。伝統的な`TYPE VALUE`構文(フィルタ式でない
  `find artist "X"`等)は演算子情報を持たないため対象外・無変更。
- [x] `replay_gain_mode`/`replay_gain_status` が `raise MpdNotImplemented` のスタブで常に
  ACK エラー・固定応答になる件: mopidy-mpd 3.3.0 の playback.py はこの2コマンドを未実装の
  ままにしていた。TODO 全項目消化済みのため自走エージェントが調査して新規発見・追加した
  項目。rmpc 本体 (mierak/rmpc) を実際に clone して grep したが、rmpc-mpd/src/mpd_client.rs
  全体・rmpc/src/ui/ 全体を探しても replay_gain 関連の送信箇所は皆無 (rmpc はこの機能を
  持たない) と判明。ただしこれは mixrampdb/mixrampdelay (mpdmixramp-patch.py)・decoders
  (mpddecoders-patch.py)・outputs の plugin フィールド (mpdoutputplugin-patch.py) と同種の
  「rmpc固有ではなく標準 MPD プロトコル準拠の不備」に該当すると判断: mpc・ncmpcpp 等の
  汎用 MPD クライアントが標準的に使う基本コマンドが常に ACK エラーになる現状は、
  mixrampdb 同様「実際の再生へ効果はなくともプロトコル層の往復自体は仕様通りにすべき」
  ギャップと確認した上で着手。
  verified: mpdreplaygain-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/PlayerCommands.cxx handle_replay_gain_mode/handle_replay_gain_status,
  src/ReplayGainMode.cxx FromString/ToString) を WebFetch で実際にソース確認し仕様を確定
  (有効な MODE は `off`/`track`/`album`/`auto` の4種のみ、未知の値は
  `std::invalid_argument`("Unrecognized replay gain mode")でACKエラー、
  `replay_gain_mode`成功時は`partition.EmitIdle(IDLE_OPTIONS)`を実際に呼び
  repeat/single等と同じ`options` idleイベントを発火する仕様)。crossfade/mixrampdb
  (mpdcrossfade-patch.py/mpdmixramp-patch.py)と同じ流儀でtranslator.pyに揮発性ストア
  (初期値"off")を追加し、mount/update (mpdmount-patch.py/mpdupdate-patch.py)と同じ
  `mopidy.listener.send(session.MpdSession, "options")`機構でidle `options`通知を
  全セッションへブロードキャストする実装にした(crossfade/mixrampdbより実MPD仕様に
  近い)。mopidy core自体はReplayGainの概念を持たないため、実際の音量補正が掛かることは
  ない(crossfade/mixrampdbと同種の割り切り)。パッチ適用後の生成ソースは一時コピーに
  当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで確認 —
  初期状態`replay_gain_status`→`replay_gain_mode: off`、
  `replay_gain_mode "track"`→OK・以後`replay_gain_status`→`replay_gain_mode: track`、
  `"album"`/`"auto"`/`"off"`も同様に正しく反映、`replay_gain_mode "bogus"`→
  `ACK [2@0] {replay_gain_mode} Unrecognized replay gain mode`(値は変化せず維持)、
  引数無し`replay_gain_mode`→`ACK ... wrong number of arguments`(既存の引数検証)。
  idle実測: 別接続(2本のTCP接続A/B)でA `idle options`後にB
  `replay_gain_mode "track"`→Aが`changed: options`で即時起床することを確認。旧来の
  `crossfade`/`status`/`tagtypes`/`search any "yoasobi"`(実データ)/`count any`/
  `list album`/`getvol`/`listmounts`/`listpartitions`/`channels`/`mixrampdb`/
  `single "oneshot"`/`consume "oneshot"`の回帰なし・mopidy.log に Traceback/ERROR
  0件を確認。
- [x] `clearerror` が `raise MpdNotImplemented` のスタブで常に ACK エラーになる件:
  mopidy-mpd 3.3.0 の status.py はこのコマンドを未実装のままにしていた。TODO 全項目
  消化済みのため自走エージェントが残りの `MpdNotImplemented` スタブ (listfiles/rangeid/
  addtagid/cleartagid/clearerror/listneighbors) を洗い出し、rmpc 本体 (mierak/rmpc) を
  実際に clone して grep したところ `clearerror` を送信する箇所は皆無 (listneighbors 等と
  同じく rmpc はこの機能を持たない) と判明。ただしこれは mixrampdb/mixrampdelay
  (mpdmixramp-patch.py)・replay_gain_mode/replay_gain_status (mpdreplaygain-patch.py)・
  decoders (mpddecoders-patch.py) と同種の「rmpc固有ではなく標準 MPD プロトコル準拠の
  不備」に該当すると判断: 実 MPD (MusicPlayerDaemon/MPD src/command/PlayerCommands.cxx
  handle_clearerror) を gh api で実際にソース確認したところ、引数なしで無条件に
  `LockClearError()` を呼んで常に OK を返すだけの副作用薄いコマンドと判明 (mpc・ncmpcpp
  等の汎用 MPD クライアントが標準的に使う基本コマンドであり、これが常に ACK エラーに
  なる現状は crossfade/mixrampdb 同様のギャップ)。
  verified: mpdclearerror-patch.py。mopidy core (mopidy/core/listener.py の
  CoreListener) には再生エラーの状態を保持・通知する仕組みが一切無い (track_playback_error
  相当のイベントが存在しない) ことを確認した上で、mopidy_mpd の `status` が元々 `error`
  フィールドを一度も出力しない (エラー無し=フィールド省略は実 MPD 仕様上も正当) 現状を
  踏まえ、「クリアすべきエラー状態がそもそも常に空」と結論。crossfade/mixrampdb のような
  揮発性ストアは不要で、単に無条件 OK (関数末尾で暗黙の None を返す、noidle 等と同じ
  パターン) に差し替えるだけで実 MPD 仕様と完全に一致すると判断し実装した。パッチ適用後の
  生成ソースは一時コピーに `chmod u+w` して書き込み可にした上で `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。パッチ済み env をビルドし dev
  mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 — `clearerror`(引数無し)→
  `OK`(修正前は`ACK [0@0] {clearerror} Not implemented`)、`clearerror extraarg`
  (余分な引数)→`ACK [2@0] {clearerror} wrong number of arguments`(既存の0引数検証が
  そのまま機能)、`status`は従来通り`error`フィールドを含まないまま(無変更)。旧来の
  `search any "yoasobi" sort -Date window "0:2"`/`list album`/`count any "yoasobi"`/
  `crossfade 5`/`getvol`/`listmounts`/`listpartitions`/`channels`/`sticker get`(no such
  sticker応答)/`tagtypes`/`status`の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: `listfiles`/`rangeid`/`addtagid`/`cleartagid`/`listneighbors`は
  mpdmixramp-patch.py/mpdaddpos-patch.pyの既知の制約欄で確認済みの通り rmpc 本体から
  一切送信されないため引き続き対象外・未着手のまま。

- [x] `mopidy_ytmusic.library.uploadArtistToTracks()`/`uploadAlbumToTracks()` (YouTube Music の
  「Uploads」= ユーザー自身がアップロードした曲、`browse()`/`lookup()` が URI 末尾 `:upload` で
  実際に呼ぶ生きた経路。この一覧自体は `get_library_artists`/`get_library_albums` 呼び出し時に
  upload 分もマージして返しており常時有効) に、artists/album/year 等の付随メタデータが欠けた
  アップロード曲で未ガードの添字アクセスによりクラッシュする不具合を発見。TODO 全項目消化済みの
  ため自走エージェントが rmpc 側の未実装コマンド調査 (mpd_client.rs の全 `send_*`/trait メソッドを
  rmpc/rmpc-mpd 全体で洗い出し済みの既存コマンド一覧と突き合わせ) を行ったが新規ギャップが
  見つからなかったため、mopidy_ytmusic 側のコード品質を調査 (ytliked-patch.py/
  ytplaylistreorder-patch.py が過去に同種のバグを発見した実績があるため) して発見した項目。
  アップロード曲はユーザーが手元のファイルをそのままアップロードしたものであり、Liked Songs に
  混ざるポッドキャスト等の非音楽アイテム以上に artists/album タグが欠落しやすい (ID3 タグ未設定の
  音源、シングルファイルは album を持たない、アーティスト名不明のアップロードも珍しくない)。
  呼び出し元の browse()/lookup() は try/except Exception で囲んでいるため MPD セッション自体は
  落ちないが、例外発生時は該当アーティスト/アルバムのブラウズ結果が丸ごと空になる
  (ytliked-patch.py が修正した Liked Songs バグと同じ実害のクラス)。
  verified: ytuploadfix-patch.py。`uploadArtistToTracks()`: `for a in track["artists"]:`
  (キー欠落/値Noneで例外) と `track["album"]["id"]` (album欠落曲で例外、`playlistToTracks` は
  既に `"album" in track and track["album"] is not None` でガード済みだがこちらは未対応) の
  2箇所を修正。`uploadAlbumToTracks()`: `album["artists"][0]["id"]` (artistsが空リスト/欠落で
  IndexError/KeyError) と、アルバム自身の `Album(date=...)` だけでなく各トラックの
  `Track(date=...)` でも参照されていた `album["year"]` (欠落でKeyError、2箇所とも同じ値を指すよう
  `album_date` 変数へ一本化) を修正。パッチ適用後の生成ソースは一時コピーに `chmod u+w` して
  書き込み可にした上で `ast.parse` で構文確認済み。**修正前の再現確認**: 同じオフライン単体
  テスト (13ケース: 正常系/artistsキー欠落・None・空リスト/albumキー欠落・None/year・
  trackCount欠落/artists要素にidが無い、等) を未パッチの `library.py` に対して実行し、
  `for a in track["artists"]:` で `KeyError: 'artists'` が実際に発生することを確認した上で、
  パッチ適用後は同テストが全13ケースとも例外なく正しい `Track`/`Album` オブジェクト
  (欠落時は artists=空・album=None・date="0000" にフォールバック) を返すことを確認
  (`YTMusicLibraryProvider` を直接 import し、ダミーの `backend` オブジェクトで
  `uploadArtistToTracks`/`uploadAlbumToTracks` を単体呼び出し)。dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し MPD で確認 — 現時点のこのアカウントはフォロー中の
  アーティスト/保存済みアルバムが0件のため `lsinfo "YouTube Music/Artists"`/`"...Albums"` が
  空で実データによる `:upload` 経路のend-to-end確認はできなかった (ytimages-patch.py/
  ytplaylistreorder-patch.py 検証時と同種のテストアカウント制約) が、`lsinfo "YouTube Music/
  Home"`(8件)/`search any "yoasobi"`(実データ3件)/`tagtypes`(18種)/`status` が全て正常応答し、
  mopidy.log に Traceback/ERROR が起動から一連の操作を通じて0件であることを確認 (本パッチが
  触れた関数はこのアカウントの現在の状態では未到達のため、影響範囲内での回帰なしの確認に留まる)。

- [x] 曲メタデータに `duration` (MPD 0.20+、`Time` の後継、小数秒) が一度も出力されない件:
  mopidy-mpd 3.3.0 の translator.py `track_to_mpd_format()` (playlistinfo/playlistid/
  find/search/count/listplaylistinfo/currentsong/playlistfind/playlistsearch 全ての
  トラック整形が共有する唯一の関数) は `Time` (整数秒、非推奨のlegacyフィールド) のみを
  出力し、後継の `duration` (小数秒) を出していない。TODO 全項目消化済みのため自走エージェントが
  rmpc 本体 (mierak/rmpc) を実際に clone してソース確認したところ、rmpc-mpd/src/from_mpd.rs の
  `next()` はキーを必ず `to_lowercase()` してから渡すため `Time: N` は小文字化されて
  `current_song.rs` の `FromMpd for Song` に届くが、そこでは `"time" => {} // deprecated or
  ignored` と明記されて完全に無視され、`self.duration` (Song構造体のフィールド) をセットするのは
  `"duration"` キーの1系統のみと判明。つまり mopidy_mpd が送る全ての曲情報は rmpc からは常に
  `Song.duration == None` に見える。実害を実際に grep で確認: rmpc/src/ui/song_ext.rs
  `SongProperty::Duration`(キューテーブル/検索結果テーブルの "Duration" カラム描画元)・
  rmpc/src/ctx.rs `cached_queue_time_total`(キュー全体の合計時間)・
  rmpc/src/ui/modals/info_list_modal.rs `total_duration`(アーティスト/アルバム詳細モーダルの
  合計時間)・rmpc/src/ui/panes/mod.rs(Now Playing欄の合計時間集計)が軒並み常にNoneの
  `s.duration` に依存しており空欄/0表示になる、加えて rmpc/src/shared/lrc/index.rs
  (歌詞.lrc同期機能)の `target_duration` フォールバックにも使われ歌詞位置合わせの精度にも
  影響する、という実害ある新規ギャップと確認した上で着手。実 MPD
  (MusicPlayerDaemon/MPD src/SongPrint.cxx song_print_info、gh clone で実際にソース確認)は
  `Time: {}\nduration: {:1.3f}\n` を常にセットで出力しており、musicpd.org protocol docs
  (WebFetch で確認)も「`duration`が小数秒を含む現行フィールド、`Time`は互換性のためだけに
  残された非推奨の整数版」と明記しており、mopidy_mpd がこの後継フィールドを一度も送っていない
  こと自体が標準 MPD プロトコル準拠の欠落と判明。
  verified: mpdduration-patch.py。translator.py の `track_to_mpd_format()` の
  `("Time", track.length and (track.length // 1000) or 0)` の直後に
  `("duration", round((track.length or 0) / 1000, 3))` を追加(既存の `Time` の
  「track.length が無ければ0」という既存の best-effort な流儀にそのまま揃え、実 MPD のように
  丸ごと省略はしない=Timeと常に対で出るようにして中途半端な非対称を避けた)。
  `track_to_mpd_format` は music_db.py(find/search/count)・current_playlist.py
  (playlistinfo/playlistid)・stored_playlists.py(listplaylistinfo、内部で
  `playlist_to_mpd_format`経由)・status.py(currentsong)・mpdplaylistfind-patch.py
  (playlistfind/playlistsearch)全てが共有する唯一の整形関数のため、この1箇所の修正で
  全コマンドに一括反映される。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で
  構文確認、2回適用しても冪等(スキップ)であることも確認(pristine相当に`duration`行を
  一旦除去して再適用するテストで新規挿入経路も確認済み)。dev mopidy(6601, ytmusic
  実アカウント)を実際に起動し実データ(YOASOBI「夜に駆ける」Time262/「オリオン」Time207)を
  `addid`でキューに積んでMPDで確認 — `playlistinfo`→各曲に`Time: 262`直後に
  `duration: 262.0`、`Time: 207`直後に`duration: 207.0`が正しく追加、`save "create"`で
  ストアドプレイリスト化した後の`listplaylistinfo`でも同様に反映、`search any "yoasobi"`の
  実データ(アルバム合成疑似トラック含む)でも`Time: 0`/`duration: 0.0`のペアが一貫、
  `count any`(songs/playtimeは既存のまま無変更)・`tagtypes`(duration は Time 同様
  タグではなく別枠のためtagtypes一覧に影響なし、無変更)の回帰なしを確認。旧来の
  `list album`/`crossfade 5`/`getvol`/`listmounts`/`listpartitions`/`channels`/
  `sticker get`(no such sticker応答)/`mixrampdb`/`replay_gain_status`の回帰なし・
  mopidy.log に Traceback は`save "create"`実行時の既知の mopidy_ytmusic HTTP 401
  (このテストアカウントの書き込み権限不足、mpdlastloadedplaylist-patch.py等の検証時にも
  確認済みのpre-existingな挙動、本パッチが触れていない`save`自体の経路)1件のみで
  新規リグレッションではないことを確認。
- [x] `playlistadd {NAME} {URI} [POSITION]` (MPD 0.23.3+): mopidy-mpd 3.3.0 の `playlistadd` は
  `name`/`track_uri` の固定2引数のみで、実 MPD 0.23.3+ が追加した第3引数 POSITION
  (ストアドプレイリスト内の挿入位置、絶対インデックスのみ・add/addid/load の相対 +N/-N とは
  異なる) を一切受け付けない。TODO 全項目消化済みのため自走エージェントが rmpc 本体
  (mierak/rmpc, 既存の /private/tmp/rmpc-check clone を再利用) の rmpc-mpd/src/mpd_client.rs
  全 `send_*` を洗い出したところ、`send_add_to_playlist(playlist_name, uri, target_position:
  Option<usize>)` が POSITION 付きで `playlistadd NAME URI POSITION` を送るコード経路を実装
  済みと判明。呼び出し元 (rmpc/src/ui/panes/queue.rs, rmpc/src/shared/mpd_client_ext.rs) は
  現状全て `None` 固定で送信しており rmpc 固有の実害の確証は得られなかったが、mixrampdb/
  decoders/outputs plugin/replay_gain/clearerror と同じ「rmpc固有ではなく標準 MPD プロトコル
  準拠の不備」に該当すると判断: 実 MPD (MusicPlayerDaemon/MPD src/command/PlaylistCommands.cxx
  handle_playlistadd/handle_playlistadd_position) を gh api で実際にソース確認し、POSITION 付き
  3引数フォームが MPD 0.23.3 の正式仕様であることを確認した上で追加した項目。
  verified: mpdplaylistaddpos-patch.py。実 MPD ソース確認で仕様確定 — POSITION は絶対
  インデックスのみ(add/addid/loadと異なり相対+N/-N書式は無い、`args.ParseUnsigned(2)`)、
  `position > 対象プレイリストの現在の曲数`(存在しなければ0)なら`ACK_ERROR_ARG`("Bad
  position")、`position == 曲数`(末尾)は許可。mopidy_mpd の playlistadd は URIをlibrary.lookup()
  で0..N件のTrackへ展開し末尾に足すだけの実装のため、add/addid/loadのような「末尾に追加後
  move」の二段構えは不要で、追加するTrack集合を指定位置へ直接スライス挿入するだけで済む
  (ストアドプレイリストに`tracklist.move()`相当の概念はないため)。パッチ適用後の生成ソースは
  一時コピーに`chmod u+w`して書き込み可にした上で`ast.parse`で構文確認、2回適用しても冪等
  (スキップ)であることも確認。dev mopidy(6601, ytmusic実アカウント)を実際に起動し実データ
  (検索で集めた6曲のtrack URI A-F)でMPDプロトコルを直接叩いて確認 —
  `playlistadd NAME A`(POSITION省略、新規作成)→OK・`listplaylist`→A、
  `playlistadd NAME B`(POSITION省略、既存への追加、従来動作)→OK・A,B、
  `playlistadd NAME C "0"`(先頭へ挿入)→C,A,B、`playlistadd NAME D "1"`(中間へ挿入)→
  C,D,A,B、`playlistadd NAME E "4"`(現在の曲数と同じ位置=末尾、境界値)→C,D,A,B,E、
  `playlistadd NAME F "999"`(曲数超過)→`ACK Bad position`・キューは無変更のまま5曲、
  空の新規プレイリストへ`playlistadd NAME2 A "0"`(曲数0に対し境界値ちょうど)→OK作成、
  空の新規プレイリストへ`playlistadd NAME3 A "1"`(曲数0superior)→`ACK Bad position`・
  プレイリスト自体が作成されないことを`listplaylists`で確認、非数値`"abc"`/負数`"-1"`→
  `ACK incorrect arguments`(既存のUINT型検証がそのまま機能)。旧来の POSITION 省略時の
  動作(新規作成・既存への追加どちらも)は無変更で回帰なし、旧来の `list album`/`search any
  sort+window併用`/`listplaylists`/`sticker get`(no such sticker応答)/`crossfade`/`getvol`/
  `status`/`tagtypes`/`count any`の回帰なしを確認。mopidy.log の Traceback は
  `playlistadd`が内部で使う`core.playlists.save`/`create`実行時の既知の mopidy_ytmusic
  HTTP 401 (このテストアカウントの書き込み権限不足、mpdlastloadedplaylist-patch.py等の
  検証時にも確認済みのpre-existingな挙動、本パッチが触れていない`save`/`create`自体の経路。
  実際にはmopidy coreのPlaylistsControllerがm3uバックエンドへフォールバックして正常に
  作成されるため機能的な回帰ではない)3件のみで新規リグレッションではないことを確認。
- [x] `mopidy_ytmusic.library.albumToTracks()` (通常の—アップロードでない—アルバムを
  ブラウズ/検索結果から展開する主経路。browse()/lookup()/search() の計4箇所から呼ばれ、
  Uploads (`:upload`) 経由より遥かに高頻度で通る) に、未ガードの添字アクセスによる
  TypeError/KeyError クラッシュを発見。TODO 全項目消化済みのため自走エージェントが
  rmpc 側の未実装コマンド調査で新規ギャップが見つからなかったため、ytuploadfix-patch.py
  が同種のバグを Uploads 経路 (uploadArtistToTracks/uploadAlbumToTracks) で発見・修正した
  実績があることを踏まえ、主経路である albumToTracks 自体のコード品質を調査して発見した
  項目。ytmusicapi 1.12.1 (mixins/browsing.py get_album → parsers/albums.py
  parse_album_header_2024) を実際にソース確認し、以下2点が実データで起こりうることを
  確認: (1) `album["artists"]`: strapline (アーティスト名表示欄) が無いアルバム
  (一部のシングル等) では `parse_album_header_2024` が明示的に `album["artists"] = None`
  をセットする実装 (`album_info["artists"] = parse_artists_runs(strapline_runs) if
  strapline_runs else None`) と判明。旧実装は `if "artists" in album:`
  (キー存在のみ確認、値がNoneでも真) の後 `artist = album["artists"]` (Noneのまま) →
  `artist["id"]` で `TypeError: 'NoneType' object is not subscriptable`。
  (2) `album["trackCount"]`: `secondSubtitle.runs` が1件以下 (トラック数表示欄が無く
  再生時間のみのアルバムページ) の場合、`trackCount` キー自体を一切セットしない実装と
  判明。旧実装は `str(album["trackCount"]).isnumeric()` で直接添字アクセスしており、
  キー欠落時に `KeyError: 'trackCount'`。呼び出し元の browse()/lookup()/search() は
  try/except Exception で囲んでいるため MPD セッション自体は落ちないが、例外発生時は
  該当アルバムのブラウズ/検索結果への反映が丸ごと欠落する (ytliked-patch.py/
  ytuploadfix-patch.py と同じ実害のクラス) ことを確認した上で着手。
  verified: ytalbumfix-patch.py。`album.get("artists")` へ変更しNone/欠落/空リストいずれも
  安全にスキップ (加えて `artist.get("id")` チェックも追加し、ytmusicapiの
  `parse_artists_runs` が `id=None` の要素を返しうる — `nav(..., NAVIGATION_BROWSE_ID,
  True)` が browseId 欠落時に None を返す仕様を実際にソース確認済み — ケースで
  `ARTISTS[None]` という壊れたURIの偽エントリが作られる副次的な問題も併せて解消)、
  `album.get("trackCount")` へ変更しキー欠落時は`isnumeric()`がFalseになり
  `int(album["trackCount"])`評価自体を回避 (Python三項演算子の短絡評価)。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても
  冪等(スキップ)であることも確認 (ytuploadfix-patch.py の `uploadAlbumToTracks` に既に
  類似の `album_artists = album.get("artists")` という行が存在するため、初期実装の
  idempotency marker がそれと衝突して誤って「既にパッチ済み」判定してしまう不具合を
  実際に発見・より具体的な marker 文字列に修正して解消)。**修正前後のオフライン単体
  テスト**: `YTMusicLibraryProvider` を直接 import し (`object.__new__` で `__init__` を
  経由せず TRACKS/ALBUMS/ARTISTS/IMAGES のみ手動セットしたダミーインスタンス)、
  `albumToTracks` を直接呼び出す5ケース (artists=None単体、trackCount欠落単体、両方欠落、
  正常系の回帰、artist id=None) で検証 — 修正前 (未パッチ) の `library.py` に対して
  実行すると、artists=Noneで実際に`TypeError: 'NoneType' object is not subscriptable`、
  trackCount欠落/両方欠落で実際に`KeyError: 'trackCount'`が発生することを確認した上で、
  修正後は同じ5ケース全てが例外なく正しい `Track`/`Album` オブジェクトを返すこと
  (artists=None/trackCount欠落→`artists=[]`/`num_tracks=None`にフォールバック、
  正常系→従来通り`name`/`num_tracks`/`artists`が正しく反映、id=None→`ARTISTS`に登録
  されず空の`artists`のまま=偽エントリ抑制)を確認。dev mopidy(6601, ytmusic 実アカウント)
  を実際に起動し実データで MPD プロトコルを直接叩いて確認 —
  `add "ytmusic:album:MPREb_a5PIYyducZQ"`(YOASOBI「THE BOOK for,」、実際に
  albumToTracks の主経路を通す)→OK・`playlistinfo`で12曲全てTrack/Artist/AlbumArtist/
  Date/X-AlbumUri等がフルに反映されクラッシュしないことを確認。旧来の`tagtypes`/
  `count any "yoasobi"`/`list album group AlbumArtist`/`search any "yoasobi" sort -Date
  window "0:2"`/`crossfade 5`/`getvol`/`listplaylists`/`sticker get`/`listmounts`/
  `listpartitions`/`channels`の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `ytmusic:history` (Recently Played) / `ytmusic:watch` (Similar to last played) が
  `get_history()` の `YTMusicServerError` で丸ごと失敗し常に空になる件: TODO 全項目
  消化済みのため自走エージェントが dev mopidy(6601, ytmusic 実アカウント) を実際に起動し
  `lsinfo "YouTube Music/Recently Played"`/`lsinfo "YouTube Music/Similar to last played"`
  を含む広範なブラウズ/検索経路を実際に MPD で叩いて mopidy.log を監査したところ、
  以下の実クラッシュを新規発見・再現した:
  ```
  ytmusicapi.exceptions.YTMusicServerError: None
    File ".../ytmusicapi/mixins/library.py", line 313, in get_history
      raise YTMusicServerError(error)
  ```
  この項目は BACKLOG の既存項目「Recently Played (history)」で先に調査済みで、
  その時点では実アカウントの履歴3セクションが全て `musicShelfRenderer` だったため
  「再現しない」と判定されていたが、時間経過に伴うアカウント/セッション状態の変化で
  今回実機で新たに再現した (`_send_request` で生レスポンスをダンプして特定した原因は
  `itemSectionRenderer`(「Sign in to view your history」という案内メッセージ)の混入で、
  ytmusicapi の `get_history()` は履歴の各セクションが必ず `musicShelfRenderer` を持つ
  前提で実装されており、1つでも別種のセクションがあると即 `YTMusicServerError` を
  送出して全体を失敗させる壊れやすい実装と判明)。
  verified: ythistory-patch.py。ytmusicapi 自体は nix/lib/mopidy-env.nix の postPatch
  対象外 (mopidy-ytmusic/mopidy-mpd/mopidy-listenbrainz のみ) のためソース修正できず、
  mopidy_ytmusic.library.py 側に `get_history()` 相当の処理 (`_send_request` で
  `FEmusic_history` を叩き、`musicShelfRenderer` を持たないセクションは例外にせず
  読み飛ばす) を独自実装 (`getHistory()`) し、"ytmusic:history"/"ytmusic:watch" の
  2箇所の呼び出しをこちらに差し替え。あわせて "ytmusic:watch" 側の
  `hist[0]["videoId"]` が空リストに対し未ガードだった箇所も同じ機会に
  `hist[0]["videoId"] if hist else None` へ修正 (get_history() が常に例外を投げていた
  従来は素通りしていた到達不能コードだったが、今回の修正で到達しうるようになるため)。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても
  冪等(スキップ)であることも確認。**オフライン単体テスト**: `YTMusicLibraryProvider`
  を直接 import し (`object.__new__` で `__init__` を経由せず手動セットしたダミー
  インスタンス)、`_send_request` をモックした3ケース (正常セクションのみ/
  `itemSectionRenderer` 混在/全セクションが非`musicShelfRenderer`) で `getHistory()`
  を直接呼び出し検証 — いずれも例外を投げず、正常セクションのみ正しく件数を返す
  (混在ケースは1件、全滅ケースは0件で正常応答) ことを確認。パッチ済み env の
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 — 修正前は
  `lsinfo "YouTube Music/Recently Played"`/`lsinfo "YouTube Music/Similar to last
  played"` の両方で mopidy.log に `YTMusicServerError`(前者)/`IndexError`(後者、
  `get_history()`が例外を投げなくなった結果 hist=[] で到達した別クラッシュ)の
  トレースバックが出ていたのが、修正後はいずれも例外なく `OK` で正常応答するように
  なったことを確認 (このアカウントは検証時点でセッション認証状態が「Sign in to view
  your history」を返す状態だったため実件数は0件のままだが、これはブラウザ認証
  (`~/ai/mopidy-dev/browser.json`、本item のスコープ外・触れていない)由来の
  既知の環境要因であり、本パッチはクラッシュの解消のみを保証するもの — オフライン
  単体テストで正常セクションが実在すれば正しく件数が返ることは別途確認済み)。旧来の
  `tagtypes`/`search any "yoasobi" sort -Date window "0:2"`/`list album`/`count any`/
  `getvol`/`crossfade`/`listmounts`/`listpartitions`/`channels`/`sticker get`/
  `listplaylists`/`decoders`/`lsinfo "YouTube Music/Home"`/`lsinfo "YouTube Music/Mood
  and Genre Playlists"` の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。

- [x] `mopidy_ytmusic.library.py` の `playlistToTracks()`/`uploadArtistToTracks()`/
  `parseSearch()` (song/album 両分岐、計4箇所) が、id=None の非リンクアーティストクレジット
  (例: "Various Artists" 等、クリック可能な channel を持たないアーティスト表記) を
  `self.ARTISTS` へ `None` キーでキャッシュしてしまい、同一セッション内で以後 id=None の
  別アーティスト(名前は全く異なる)を持つ全トラックが誤って最初にキャッシュされた
  Artist オブジェクト(=最初のトラックのアーティスト名)を共有してしまう不具合を発見。
  TODO 全項目消化済みのため自走エージェントが rmpc 側の未実装コマンド調査 (rmpc-mpd/
  src/mpd_client.rs 全 send_* を実際に洗い出し、既存の全パッチが既にカバー済みで
  新規ギャップなしと確認) に続き、ytartist-patch.py/ytliked-patch.py/ytuploadfix-patch.py/
  ytalbumfix-patch.py が同種のバグを発見してきた実績を踏まえ mopidy_ytmusic のコード品質を
  再調査して発見した項目。ytmusicapi の `parse_artists_runs()`
  (ytmusicapi/parsers/artists.py) は各アーティスト run に navigationEndpoint (browseId)
  が無い場合 `{"name": <表示名>, "id": None}` を返す実装であり、これは
  `parse_song_artists()`→`parse_playlist_item()` (ytmusicapi/parsers/playlists.py)
  経由で実際のプレイリストアイテムに実データで起こりうる(コンピレーション曲の
  "Various Artists" クレジット等)。既存の ytartist-patch.py は id=None のうち名前が
  resultType 誤表記("Song"/"Album"等)と一致するものだけを除外する対応で、正当な名前を
  持つ id=None のケースは4箇所とも未対応のまま残っていた。`lsinfo`/`search`/`add` 等、
  プレイリスト・検索結果をブラウズする通常経路全てで到達しうる、クラッシュはしないが
  静かにデータが汚染される実害あるバグ。
  verified: ytartistcache-patch.py。4箇所全てで `a.get("id")` が falsy の場合は
  `self.ARTISTS` へキャッシュせず都度その場限りの(uri無し) Artist を作るよう修正
  (albumToTracks の既存の `artist.get("id")` ガードと同じ流儀)。パッチ適用後の生成
  ソースは一時コピーに `chmod u+w` して書き込み可にした上で `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。**修正前後のオフライン単体テスト**:
  `YTMusicLibraryProvider` を直接 import し (`object.__new__` で `__init__` を経由せず
  TRACKS/ALBUMS/ARTISTS/IMAGES のみ手動セットしたダミーインスタンス)、id=None だが
  異なる名前を持つ2アーティストを含む合成データで `playlistToTracks()`/
  `uploadArtistToTracks()` を直接呼び出し比較 — 修正前(未パッチ)の `library.py` に
  対して実行すると、2曲目のアーティスト名が実際に1曲目の名前("Various Artists"等)に
  誤って上書きされる不具合を再現・確認した上で、修正後は同じ入力に対し各トラックが
  それぞれ正しい自分自身のアーティスト名を保持することを確認 (両関数とも合格)。
  パッチ済み env の dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で
  確認 — `tagtypes`/`search any "yoasobi"`(実データ、Artist行が正しく個別反映)/
  `status`/`lsinfo "YouTube Music/Home"`(10セクション)/`lsinfo "YouTube Music/Home/
  All time biggest hits/Idol Golds"`(50曲、playlistToTracks の主経路を実データで通し
  各曲が個別の正しいArtist名で表示されることを確認)の回帰なし・mopidy.log を監査し、
  本パッチが触れた4箇所 (`library.py:788,865,1102,1161`) はいずれのTracebackにも
  一切登場しないことを確認 (ログに出た唯一のエラーはこのテストアカウントの既知の
  認証状態に起因する `get_liked_songs`("Sign in to view your liked tracks") と
  Mood/Genre プレイリストの `musicTwoRowItemRenderer` 未対応形状 — いずれも本パッチの
  対象関数とは無関係な既知の pre-existing 事象で新規リグレッションではない)。

- [x] `mopidy_ytmusic.library.py` の `playlistToTracks()`/`albumToTracks()`/`parseSearch()`
  (song分岐) が曲の長さ (length, ms) を独自に "MM:SS" 決め打ちでパースしており、
  1時間を超える動画 ("H:MM:SS" 表記) で時間成分を無視し大幅に短い長さを返す不具合を
  発見。TODO 全項目消化済みのため自走エージェントが rmpc 側の未実装コマンド調査
  (新規ギャップなしと確認済み) に続き、ytartistcache-patch.py までの一連のパッチが
  同種のバグを発見してきた実績を踏まえ mopidy_ytmusic のコード品質を再調査して発見した
  項目。YouTube Music では DJ ミックス/作業用BGM/睡眠導入音等の長尺コンテンツが
  Liked Songs・プレイリスト・アルバム・検索結果いずれにも実データで混在しうる。
  verified: ytduration-patch.py。ytmusicapi 1.12.1 (parsers/_utils.py parse_duration、
  parsers/songs.py parse_song_runs) を実際にソース確認したところ、ytmusicapi 自身は
  duration文字列と対で "duration_seconds" (H:MM:SSを正しく解釈した秒数、
  mixins/browsing.py get_album のdocstring例で `"duration_seconds": 4657`
  (=1時間17分37秒) が実例として明記) を既に計算済みで track dict に含めていると判明
  (playlistToTracks/parseSearchが受け取るtrackはいずれも内部でparse_song_runs/
  parse_playlist_itemsを経由するため一貫して存在)。ところが mopidy_ytmusic 側はこれを
  一切使わず、3箇所で独自に `文字列.split(":")` した結果の[0]/[1]要素だけを「分:秒」
  として決め打ちで使っており、"H:MM:SS"では時間成分を無視していた。加えて
  albumToTracks/parseSearchはコロン無しの単一要素duration文字列(例: "45")の場合
  split結果が1要素になりValueErrorが発生しないため、直後の`length[1]`で未捕捉の
  IndexErrorが発生しクラッシュしうる不具合も併せて発見(呼び出し元のtry/except Exception
  でセッションは落ちないが該当結果が丸ごと欠落)。対策: ytmusicapiが既に計算済みの
  "duration_seconds"を優先し(H:MM:SSを正しく反映)、無い場合のみ任意の桁数のコロン
  区切り文字列を汎用的に(ytmusicapiのparse_durationと同じ乗算累積方式で)解釈する
  `_yt_track_length_ms()`ヘルパーをモジュールレベルに追加して3箇所を置き換え。パッチ
  適用後の生成ソースは一時コピーに`chmod u+w`して書き込み可にした上で`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。**オフライン単体テスト**:
  mopidy/ytmusicapiをスタブ化した上で`_yt_track_length_ms()`を直接呼び出す9ケース
  (duration_seconds優先(1h17m37s例)/H:MM:SSフォールバック(1:02:03→3723秒)/MM:SS通常
  ケース/lengthキー(watch playlist由来)/コロン無し単一要素(旧実装ならIndexError)/
  キー無し/空文字/非数値/duration_secondsがNoneでdurationへフォールバック)全て合格。
  パッチ済み env の dev mopidy(6601, ytmusic 実アカウント) を実際に起動し実データで
  MPD プロトコルを直接叩いて確認 — `search any "lofi mix 3 hours"` →
  実際に3時間超のロングミックス動画がヒットし `Time: 11017` / `duration: 11017.0`
  (=3時間3分37秒、タイトル「3 Hours of Chill Lofi Music for DEEP Sleep or Study
  Session」と整合、旧実装なら183秒相当の誤った値になっていたはずの箇所が正しく反映)、
  YOASOBI「THE BOOK for,」アルバムを`add`(albumToTracksの主経路)→`playlistinfo`で
  12曲全て正しいTime/duration(207/188/183/202/211/233/186/188/208/335秒等)を確認、
  クラッシュなし。旧来の`search any "yoasobi"`(実データ3件)/`tagtypes`/`status`/
  `lsinfo "YouTube Music/Liked Songs"`の回帰なし・mopidy.log の Traceback は
  このテストアカウントの既知の認証状態("Sign in to view your liked tracks"、
  ytliked-patch.py等の検証時にも確認済みのpre-existingな挙動、本パッチが触れていない
  browse()の別経路)1件のみで新規リグレッションではないことを確認。

- [x] `mopidy_ytmusic.library.py` の `uploadArtistToTracks()`/`uploadAlbumToTracks()`/
  `parseSearch()` (artist 分岐、`artistq["songs"]["results"]` ループ) の計3箇所が、曲の長さを
  一切パースせず `length=None` を決め打ちで `Track` に渡しており、Uploads (自分のアップロード曲)
  のアーティスト/アルバムブラウズ、および検索でヒットしたアーティストのトップソング一覧の
  いずれも Time/duration が常に 0 になる不具合を発見。TODO 全項目消化済みのため自走エージェントが
  BACKLOG.md に未消化項目が無いことを確認した上で mopidy_ytmusic のコード品質を再調査して発見した
  項目。直前の ytduration-patch.py が `playlistToTracks()`/`albumToTracks()`/`parseSearch()`
  (song 分岐) の3箇所を H:MM:SS 対応の `_yt_track_length_ms()` ヘルパーに置き換え済みだったが、
  この3箇所は対象に入っておらず旧来のまま `length=None` だった。ytmusicapi 1.12.1 のソースを
  実際に確認したところ、この3箇所が受け取る track/song dict はいずれも実際に
  "duration"/"duration_seconds" を含みうると判明: `uploadArtistToTracks()`/
  `uploadAlbumToTracks()` は `get_library_upload_artist()`/`get_library_upload_album()` が
  内部で `parsers/uploads.py` の `parse_uploaded_items()` を経由し各曲に "duration"/
  "duration_seconds" を含む (`mixins/uploads.py` の `get_library_upload_album()` docstring
  例でも `"duration": "4:15", "duration_seconds": 255` が実例として明記)。`parseSearch()` の
  `artistq["songs"]["results"]` は `mixins/browsing.py` の `get_artist()` が
  `artist["songs"]["results"] = parse_playlist_items(musicShelf["contents"])`
  (`parsers/playlists.py`) で構築しており、`playlistToTracks()` が受け取るのと同じ
  `parse_playlist_items()` 経由のため duration が shelf に含まれていれば同様に反映されうる。
  いずれも既に取得済みのデータを一切使わず捨てて `length=None` にする理由が無いにもかかわらず
  静かに Time/duration が失われるバグ。
  verified: ytuploaddurationfix-patch.py。既存の `_yt_track_length_ms()` ヘルパー
  (ytduration-patch.py で追加済み、H:MM:SS/duration_seconds優先/コロン無し文字列いずれも
  安全に処理) をこの3箇所でも呼び出し `length=None` を置き換え。mopidy-env.nix で
  ytduration-patch.py の直後に登録し、ヘルパーが未定義の場合は assert で早期に失敗するよう
  ガード。パッチ適用後の生成ソースは一時コピーに `chmod u+w` して書き込み可にした上で
  `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。**オフライン単体
  テスト**: `YTMusicLibraryProvider` を直接 import し (`object.__new__` で `__init__` を
  経由せず TRACKS/ALBUMS/ARTISTS/IMAGES のみ手動セットしたダミーインスタンス)、
  `uploadArtistToTracks()` (H:MM:SS+duration_seconds の合成データ→3723000ms、
  duration情報無しの曲→0ms のフォールバック確認)、`uploadAlbumToTracks()`
  (MM:SS+duration_seconds の合成データ→255000ms)、`parseSearch()` の artist 分岐
  (`get_artist()` をスタブ化し songs.results に duration 付きの合成データ→225000ms) の
  3ケース全てで期待通りの length (ms) を確認。パッチ済み env の dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し MPD で確認 — `search artist "yoasobi"`(実データ、複数アルバム/
  トラックがヒット、Traceback無くクラッシュなし)、`search any "yoasobi"`(旧来のsong分岐、
  Time: 262/207等が正しく反映され続けており本パッチによる回帰が無いことを確認)、`tagtypes`/
  `status`/`lsinfo "YouTube Music/Home"`(9セクション)/`lsinfo "YouTube Music/Liked Songs"`の
  回帰なしを確認。このテストアカウントは library Artists/Albums が空でアップロード曲も無いため
  `uploadArtistToTracks()`/`uploadAlbumToTracks()` 自体を実データ経由で通す経路が無く、
  この2関数についてはオフライン単体テストのみでの検証となった点、および
  `parseSearch()` artist 分岐で実際にヒットした曲は shelf 自体に duration 列が無く
  Time:0 のままだった(ytmusicapi 側のデータ欠如であり本パッチの不具合ではないことを
  `parsers/playlists.py` のduration列検出ロジックを確認した上で判断)点は限界として明記。
  mopidy.log の Traceback はこのテストアカウントの既知の認証状態(`get_liked_songs`の
  "Sign in to view your liked tracks"、本パッチが触れていない`browse()`の別経路、
  ytliked-patch.py等の検証時にも確認済みのpre-existingな挙動)1件のみで新規リグレッションでは
  ないことを確認。

- [x] `mopidy_ytmusic.library.py` の `parseSearch()` (resultType=="album"/"artist" 両分岐、
  計4箇所) が `search album`/`search artist` の応答に含まれるアルバム/シングルの "year"
  キーへ未ガードの添字アクセスをしており、ytmusicapi が "year" を一度もセットしない
  ケースで KeyError クラッシュする不具合を発見。TODO 全項目消化済みのため自走エージェントが
  rmpc 本体 (mierak/rmpc, 既存の /tmp/rmpc-check clone を再利用) の rmpc-mpd/src/mpd_client.rs
  全 `send_*` を洗い出したが新規プロトコルギャップは見つからなかったため、
  ytartistcache-patch.py/ytduration-patch.py/ytuploaddurationfix-patch.py が同種のバグを
  発見してきた実績を踏まえ mopidy_ytmusic のコード品質を再調査して発見した項目。
  ytmusicapi 1.12.1 (parsers/browsing.py) を実際にソース確認したところ、search
  album/artist 応答内のアルバム・シングルはいずれも共通の `_parse_album_single_subtitle()`
  を経由しており、subtitle が数値そのものでなく (例: "Album"/"EP" 等の種別文字列) かつ
  SUBTITLE2 が存在しないか数値でない場合、"year" キーは一度もセットされないと判明 (常に
  保証されたキーではない)。実害箇所は2種: (1) resultType=="album" 分岐の
  `date = result["year"]` はローカルな try/except に捕捉され search 全体は落ちないが、
  "year" 欠落のアルバム単体が `search album "X"` の結果から静かに消える。(2)
  resultType=="artist" 分岐 (`date=album["year"]` x2 経路 + `date=single["year"]`) は
  アーティスト1件分の処理全体を包む唯一の try/except の中にあり、どれか1つでも "year" が
  欠けると例外がアルバム/シングル/曲の残り処理全てを巻き込んで中断させ、
  `search artist "NAME"` がアーティスト自体は返しつつアルバム/シングル/曲をまるごと0件に
  してしまう (albumToTracks が既に同種の日付欠落を "0000" フォールバックで解決済みなのと
  同じ根本原因の別経路)。
  verified: ytartistalbumyear-patch.py。4箇所全てで `.get("year", "0000")` フォールバックへ
  修正 (albumToTracks/uploadAlbumToTracks 等で既に使われている "0000" 決め打ちの慣例に
  合わせた)。パッチ適用後の生成ソースは一時コピーに `chmod u+w` して書き込み可にした上で
  `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。**修正前後の
  オフライン単体テスト**: `YTMusicLibraryProvider` を直接 import し (`object.__new__` で
  `__init__` を経由せず TRACKS/ALBUMS/ARTISTS/IMAGES のみ手動セットしたダミーインスタンス)、
  `backend.api.get_artist` をモックした合成データ (year欠落のalbum/single混在、正常な
  album/songも含む) で `parseSearch()` を直接呼び出し比較 — 修正前(未パッチ)の
  `library.py` に対して実行すると、resultType=="album" (year欠落単体) で
  `KeyError: 'year'` が実際に発生しアルバムが0件に、resultType=="artist"
  (year欠落albumが2件中2番目) では例外がその場で artist 処理全体を中断させ
  albums=1件(1番目のみ)/tracks=0件(singlesもsongsも未処理のまま失われる) ことを
  実際に再現・確認した上で、修正後は同じ入力に対しalbums=1件(year欠落単体ケース)、
  artists=1/albums=3(album2件+single1件)/tracks=1件(songsも正しく処理)と全データが
  欠落なく処理されることを確認。パッチ済み env の dev mopidy(6601, ytmusic 実アカウント)
  を実際に起動し MPD で実データ確認 — `search artist "yoasobi"` → YOASOBI/Ayase/Lilas の
  3アーティスト + 38アルバム + 15曲が例外なく一括で返り(Date行も全アルバムに正しく反映)、
  mopidy.log に Traceback/ERROR 0件を確認 (このアカウントのヒットしたアルバムは全て
  year取得済みだったため実データでは "0000" フォールバック自体は未経由だが、
  オフライン単体テストで欠落時の完全な保護は別途確認済み)。旧来の
  `search any "yoasobi" sort -Date window "0:2"`/`list album`/`list Album group
  AlbumArtist`/`count any "yoasobi"`/`tagtypes`/`status`/`listplaylists`/`getvol`/
  `listmounts`/`listpartitions`/`channels`/`sticker get`(no such sticker応答)の回帰なし・
  mopidy.log に Traceback/ERROR 0件を確認。

- [x] `mopidy_ytmusic.library.py` の `artistToTracks()` (browse `ytmusic:artist:<id>` /
  `lookup()` の非アップロード経路が使う唯一の変換関数、`add`/`addid` 等でアーティストURIを
  直接指定した場合の解決先でもある) が、`artist["songs"]["browseId"]` が None だと
  無条件に None を返し、その artist の曲を丸ごと欠落させる不具合を発見。TODO 全項目消化済み
  のため自走エージェントが mopidy_mpd/mopidy_ytmusic の残りソースを再調査して発見した項目。
  ytmusicapi (mixins/browsing.py `get_artist()`) を実際にソース確認したところ:
  `artist["songs"] = {"browseId": None}` で初期化され、曲一覧に「もっと見る」の展開リンクが
  あるアーティストのみ `browseId` が設定される。曲数が少なく展開リンクが無いアーティスト
  (小規模/インディーズ系で頻出) では `browseId` が None のままで、`artistToTracks()` は
  `"songs" in artist and "browseId" in artist["songs"] and ... is not None` の3条件目で
  弾かれ即 None を返していたが、`artist["songs"]["results"]` には
  `parse_playlist_items()` 済み(`playlistToTracks()` が期待するのと同じ videoId/title/
  artists/album/duration_seconds 形式)の曲リストが実際には入っており、みすみす捨てていた。
  対策: `browseId` が無い場合は `songs["results"]` を `{"tracks": [...]}` として
  `playlistToTracks()` にそのまま渡すフォールバックを追加 (`getHistory()` が同じ
  `{"tracks": [...]}` 形式で `playlistToTracks()` を呼ぶのと同じ流儀)。`songs` 自体が無い/
  `results` も無い ("API sometimes does not return songs" の場合) は従来通り None のまま。
  verified: ytartistnoexpand-patch.py。**オフライン単体テスト**: `YTMusicLibraryProvider` を
  `object.__new__` で直接生成し、ytmusicapi docstring 記載の実データ形状(`browseId: None` +
  `results` に1曲)を模した合成データで `artistToTracks()` を直接比較 — 修正前(未パッチ)の
  `library.py` では None が返り曲が消えることを実際に再現、修正後は1曲を正しく返すことを
  確認 (境界ケース: songsキー自体が無い/resultsが空、はどちらも従来通りNoneのまま・
  クラッシュ無しであることも確認)。パッチ済み env の dev mopidy(6601, ytmusic 実アカウント)
  を `-v` (debug) で実際に起動し MPD で実データ確認 — `search artist "indie"` で見つけた
  実在の10アーティストを `core.library.browse` (HTTP JSON-RPC、dispatcherが内部で呼ぶのと
  同一のcore関数) で一括ブラウズしたところ、"Mela Indie"/"Indie K" の2アーティストで実際に
  `browseId=None` (mopidy.log に "found N tracks for X (no expand browseId)" の新規追加
  デバッグログが出力) を実データで踏み、それぞれ5曲を欠落なく返すことを確認。さらに生の
  MPD プロトコルで `clear` → `add "ytmusic:artist:UC744zbDbyf8cC1r9jCnsTEg"`
  (Mela Indie) → `playlistinfo` を実行し、5曲全てが実際にキューへ追加されること
  (修正前は0曲でACK "directory or file not found" になっていたはずの経路) を実機確認。
  旧来の browseId 経由アーティスト("Re:Covered Indie" 等、25〜98曲)のブラウズ結果件数に
  回帰が無いこと、`tagtypes`/`status` の応答に回帰が無いことも確認。本項目の変更が原因の
  新規 Traceback は0件 (起動〜検証全体で5件のTracebackを観測したが、いずれも
  `search any "indie"` 由来の `parseSearch` の `result["artists"]` 未ガード添字アクセス
  (KeyError)・`search artist "indie"` 由来の `get_artist_albums` 内 `nav()` の
  `musicCarouselShelfRenderer` 未ガード添字アクセス (KeyError)・本項目で初めて実データ到達した
  「アーティストが正真正銘0曲」ケースで `browse()` L439 `[Ref.track(...) for t in tracks]` が
  `tracks=None` を未ガードでイテレートする (TypeError) の3種で、いずれも本パッチの変更対象
  関数の外側・かつ本パッチ適用前から存在する既知の別不具合であり本パッチによる新規リグレッション
  ではないことをスタックトレースの行番号で確認済み。次点候補として BACKLOG に未着手のまま残す。

- [x] 上記 `artistToTracks()` 修正の実機検証で新規発見した、本パッチ範囲外の既存3件の不具合:
  (1) `parseSearch()` の song 分岐 `for a in result["artists"]:` が `result` に `"artists"`
  キー自体が無いケース (`search any "..."` で resultType=="song" だが artists 情報を持たない
  結果、実データで再現済み: "indie" の any 検索で "Alternative Radio" 相当のアルバム的
  song 結果がヒットして発生) で `KeyError: 'artists'` (mopidy_ytmusic/library.py 付近
  1169行目、ytartist-patch/ytartistcache-patch適用後の行番号)。個別の try/except で
  search 全体は落ちないが、その1件が静かに消える。(2) `parseSearch()` の artist 分岐が
  `get_artist_albums()` 呼び出し経由で `ytmusicapi/navigation.py` の `nav()` が
  `musicCarouselShelfRenderer` キー不在で `KeyError` (実データ "Indie Soull" で再現)、
  こちらも artist 単位の try/except で握り潰され、その1アーティストのアルバム/曲が
  静かに0件になる。(3) `library.py` の `browse()` `ytmusic:artist:<id>` 分岐 (アップロード
  以外) L439 `return [Ref.track(uri=t.uri, name=t.name) for t in tracks]` が、
  `artistToTracks()` が正真正銘0曲のアーティスト (実データ "The Indie Hippies"/
  "Indie Lust" で再現、`artist["songs"]` に `browseId`/`results` どちらも無い) で None を
  返すケースを未ガードでイテレートし `TypeError` (これも外側の try/except で握り潰され
  ユーザー影響はブラウズ結果が空になるのみ・クラッシュはしないが、ログにERROR+Traceback
  が毎回出る)。3件とも try/except に守られており実害はログ汚染+結果の静かな欠落に留まる
  (クラッシュ・接続断は無い)が、いずれも実データで再現性のある本物の不具合。
  verified: ytparsegaps-patch.py。実機検証で(1)の実際のクラッシュ地点は記述当時の行番号
  ("song 分岐"付近)ではなく、その後の追加パッチでズレた現在のソースでは album 分岐
  (`if result["browseId"] not in self.ALBUMS:` 直後)であることを dev mopidy(6601,
  ytmusic 実アカウント)で `search any "indie"` を実行し実際に確認 (mopidy.log に
  `YTMusic failed parsing album Alternative Radio` + `KeyError: 'artists'` の Traceback、
  該当アルバムが唯一のヒットだったため search 結果が丸ごと空になることも実証)。
  song/album 分岐とも同一パターン (`for a in result["artists"]:`、ytartist-patch.py/
  ytartistcache-patch.py も同じ2箇所同時パターンで既に修正実績あり) のため両方を
  `result.get("artists") or []` へ一括修正。(2) は `get_artist_albums()` 呼び出しだけを
  個別 try/except で保護し、失敗時は albums=[] として singles/songs 処理を継続する対策。
  (3) は `tracks or []` にフォールバック。
  パッチ適用後、dev mopidy(6601, ytmusic 実アカウント)を実際に起動し MPD/HTTP-JSONRPC で
  再検証 — `search any "indie"` → "Alternative Radio" アルバムが例外なく結果に含まれる
  ことを確認 (mopidy.log Traceback 0件)。`search artist "indie"` → 実データで
  再度 "Indie Soull" が `get_artist_albums()` の同じ KeyError を踏むことを確認しつつ
  (WARNING ログ `YTMusic failed getting albums for artist Indie Soull via
  get_artist_albums` のみでERROR/Tracebackなし)、その後の singles 由来のアルバム
  (Moment II/Moment I/Second Chances 等10件、AlbumArtist: Indie Soull) が結果に含まれ
  続けることを確認 (修正前は albums 失敗で singles/songs 処理ごと中断していたはずの経路)。
  (3) は同じ `search artist "indie"` の実データ20アーティストを `core.library.browse`
  (HTTP JSON-RPC) で全件ブラウズし、0曲アーティスト (実データ
  "ytmusic:artist:UCyuJvmFcKtxb5_CEJ8jMeUg"、-v(debug)ログで `artist["songs"]` が
  browseId/results 無しの1キーのみと確認) が空リストで例外なく返り ERROR/Traceback が
  出ないことを確認 (修正前なら `TypeError` で `logger.exception` の Traceback が出ていた
  経路)。旧来の `search any "yoasobi" sort -Date window "0:2"`/`list Album group
  AlbumArtist`/`count any "yoasobi"`/`tagtypes`/`status`/`listplaylists` の回帰なし。
  検証全体を通し mopidy.log に ERROR/Traceback 0件を確認。
- [x] `status` 応答に `duration` (MPD 0.20+、現在再生中の曲の長さ、小数秒) が一度も出力
  されない件: mopidy-mpd 3.3.0 の status.py `status()` は state が playing/paused の
  ときに `time`(非推奨)/`elapsed`/`bitrate` の3行のみ追加し、後継フィールド `duration`
  を一切出力しない (mpdduration-patch.py が既に対応済みの `track_to_mpd_format()` 側の
  曲メタデータ `duration` タグとは別物 — 今回のものは `status` 応答自体が持つ「現在
  再生中の曲の長さ」フィールド)。TODO 全項目消化済みのため自走エージェントが rmpc 本体
  (mierak/rmpc) を実際に clone してソース確認したところ、rmpc-mpd/src/commands/status.rs
  の `Status.duration` (status応答の `duration` キー専用パースフィールド、デフォルト
  `Duration::ZERO`) が実際に rmpc/src/ui/panes/progress_bar.rs の2箇所で使われている
  実害ある新規ギャップと判明: (1) プログレスバーの表示比率
  `value = elapsed.as_secs_f32() / duration.as_secs_f32()` の分母 — `duration ==
  Duration::ZERO` だと常に `value = 0.0` に固定され、実際にどれだけ再生が進んでいても
  プログレスバーが常に空のまま描画される、(2) 同ファイルのマウスクリックによる
  シーク処理 `second_to_seek_to = duration.mul_f32(クリックX位置比率)` — duration が
  常にZEROのため計算結果が常に0になり、プログレスバー上のどこをクリックしても曲の
  先頭(0秒)へシークされてしまう。実 MPD (MusicPlayerDaemon/MPD
  src/command/PlayerCommands.cxx を実際に clone してソース確認) は `time`/`elapsed`/
  `bitrate` と同じ `player_status.state != PlayerState::STOP` (playing/paused) の
  条件下で、かつ曲の長さが既知 (`total_time` が negative でない) の場合のみ
  `duration: {:1.3f}\n` を追加出力する仕様と確認した上で着手。
  verified: mpdstatusduration-patch.py。既存の `_status_time_total(futures)`
  (曲の長さをミリ秒で返す、無ければ0) とは区別し、実 MPD の「長さ不明なら行自体を
  省略する」仕様に合わせて0とNoneを区別する専用の `_status_duration(futures)` を
  新設し、time/elapsed/bitrateと同じif ブロック内でNoneでないときだけ結果へ追加する
  実装にした。生成後ソースは一時コピーに `chmod u+w` して書き込み可にした上で
  `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動しMPDで実データ
  (YOASOBI「夜に駆ける」Time:262) を使って確認 — 初期状態(stopped、空キュー)の
  `status` → `duration`行なし(旧来通り)、`add`+`play 0`で実際に再生開始後の
  `status` → `time: 0:262`/`elapsed: 0.000`/`bitrate: 0`と共に`duration: 262.0`が
  新規追加、`pause 1`後の`status`でも`duration: 262.0`を維持、`stop`後の`status`
  → `time`/`elapsed`/`bitrate`と共に`duration`行も消える(実MPD仕様通り)ことを確認。
  旧来の`tagtypes`/`list album`/`count any "yoasobi"`/`crossfade 5`/`getvol`/
  `sticker get`(no such sticker応答)の回帰なし・mopidy.log に Traceback/ERROR 0件
  を確認。
- [x] `stats` (musicpd.org protocol 標準の統計コマンド) が artists/albums/songs/uptime/
  db_playtime/db_update/playtime の全フィールドで常に固定値 0 (`# TODO`) を返す件:
  mopidy-mpd 3.3.0 の status.py はこのコマンドを実装しないままにしていた。TODO 全項目
  消化済みのため自走エージェントが残存する `# TODO`/`MpdNotImplemented` を洗い出して発見した
  項目。rmpc 本体 (mierak/rmpc, 既存の /private/tmp/rmpc-check clone を再利用) の
  rmpc-mpd/src/mpd_client.rs 全 `send_*` および rmpc/rmpc-mpd 全体を grep したが `stats` を
  送信する経路は皆無 (rmpc はこの機能を使わない) と判明したため、clearerror/replay_gain/
  mixrampdb/decoders と同種の「rmpc固有ではなく標準 MPD プロトコル準拠の不備」に該当すると
  判断: mpc/ncmpcpp 等の汎用 MPD クライアントが標準的に使う基本コマンドが常時ゼロ固定を返す
  現状はプロトコル層として不正確なギャップと確認した上で着手。
  verified: mpdstats-patch.py。実装方針の検討で「songs(DB内曲数)/db_playtime(DB内全曲の
  合計長)」を実値にするには mopidy-ytmusic backend のライブラリ全体を曲単位で走査する必要が
  あると分かったが、これは本 BACKLOG の `listall` blocked 項目 (mopidy-ytmusic の browse() が
  Home/Explore等の非有界カタログを含むため深さ優先の再帰が事実上非有界になり、mopidy core
  actor を専有して他クライアントの`status`応答すら10秒以上ブロックするデッドロック同然の実害を
  実機で確認済み)と全く同じ危険を抱えると判断し、この2フィールドは安全策として未実装のまま
  0 を返す設計にした (決め打ちで誤魔化さず、コメントで理由を明記)。一方 artists/albums は
  `list`/`count group` が既に安全に使っている `context.core.library.get_distinct()` を
  再利用して実値化、uptime/db_update/playtime は crossfade/mixrampdb と同じ流儀で
  translator.py にモジュールレベルの揮発性ストアを追加し実装: uptime はプロセス起動時刻からの
  経過秒、db_update は既存の `next_update_job_id()` (mpdupdate-patch.py が update/rescan成功時
  に呼ぶ) を拡張してUNIX時刻を記録、playtime は mopidy core の `track_playback_ended` イベント
  (mpdoneshot-patch.py が既に actor.py の MpdFrontend.on_event で購読済み) が渡す
  `time_position` (ms、再生終了/切り替わり時点までの到達位置、mopidy/core/playback.py
  `_trigger_track_playback_ended` を実際にソース確認済み) を積算する近似値として実装
  (シークで巻き戻した場合は壁時計時間より少なく積算されうるが、実 MPD 自体もデコーダの
  再生位置進行を基準にしているため方向性は一致、mixrampdb/decoders と同種の割り切り)。
  パッチ適用後の生成ソースは一時コピーに `chmod u+w` して書き込み可にした上で `ast.parse` で
  3ファイル(status.py/translator.py/actor.py)とも構文確認、2回適用しても冪等(スキップ)で
  あることも確認。オフライン単体テストで `translator.add_playtime()`/`get_playtime()`/
  `get_uptime()`/`next_update_job_id()`→`get_db_update_time()` を直接呼び出し、加算の
  累積・None/0の無視・時刻反映を確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し
  MPD で確認 — 初期`stats`→`uptime`のみ経過秒で非0、他は0、`update`実行後の`stats`→
  `db_update`が実UNIX時刻に反映(実行前は0)、実データ(YOASOBI「夜に駆ける」)を`addid`+`play`
  で再生開始後`seekcur 100`(このdev環境はfakesink+低速ストリームで実デコードがほぼ進まず、
  seekが実質的にEOS相当の`track_playback_ended`を誘発)→`stop`後の`stats`→`playtime: 261`
  (time_position≈261sが正しく積算)を確認、この一連の操作全体で`mopidy.log`にTraceback/ERROR
  0件。`list artist`/`list album`が実際に空(このアカウントの現在のライブラリ状態)のこの状態で
  `stats`の`artists`/`albums`も同じく0で一致することを確認 (get_distinctへの丸投げが
  正しく機能している証跡)。旧来の`tagtypes`/`list album`/`list artist`/`search any "yoasobi"`/
  `count any "yoasobi"`/`crossfade 5`/`getvol`/`listmounts`/`listpartitions`/`channels`/
  `sticker get`(no such sticker応答)/`decoders`/`replay_gain_status`/`single "oneshot"`/
  `consume "oneshot"`/`status`の回帰なし・Traceback 0件を確認。
  既知の制約: songs/db_playtime は上記の理由で常に0のまま (mount/crossfade/listall等と同種の
  安全優先の割り切り、rmpc自体もstatsを送信しないため実害は無い)。playtime はシーク巻き戻しを
  含む場合に実際の壁時計再生時間より少なく積算されうる近似値 (実MPD自体もデコーダ位置基準の
  近似であり方向性は一致)。
- [x] `listneighbors` が `raise MpdNotImplemented` (error_code=0 "Not implemented") のスタブの
  ままで、実 MPD のエラーコード/メッセージと異なっていた件: TODO 全項目消化済みのため
  自走エージェントが mopidy_mpd 残りの `MpdNotImplemented` スタブ (listfiles/rangeid/
  addtagid/cleartagid/clearerror/listneighbors, mpdclearerror-patch.py のコメントで
  洗い出し済み) から次の1件として選定。rmpc 本体 (mierak/rmpc) を実際に clone して grep
  したが `listneighbors` を送信する箇所は皆無 (idle "neighbor" イベントも
  rmpc/src/core/event_loop.rs で `log::warn!("Received unhandled event")` するだけで
  listneighbors を送り返す導線は無い) と判明。clearerror/mixrampdb/decoders と同種の
  「rmpc固有ではなく標準 MPD プロトコル準拠の不備」に該当すると判断した上で着手。
  verified: mpdlistneighbors-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/NeighborCommands.cxx handle_listneighbors) を実際にソース取得
  (`curl raw.githubusercontent.com`) して確認: `client.GetInstance().neighbors`
  (smb/upnp等の neighbor プラグインが1つ以上有効な場合のみ生成される NeighborGlue) が
  null なら `r.Error(ACK_ERROR_UNKNOWN, "No neighbor plugin configured")` を返し、
  プラグインはあるが0件発見の場合のみ OK+空リストになる、と2ケースが明確に区別される仕様
  と確定。mopidy_mpd/mopidy core には neighbor プラグインの仕組み自体が一切存在しない
  (grep で該当実装コード皆無) ため常に前者 (プラグイン自体が無い) のケースに一致すると
  判断し、既存の `MpdNotImplemented` を `exceptions.MpdUnknownError("No neighbor plugin
  configured")` (ACK_ERROR_UNKNOWN=5) に差し替え、dispatcher.py が自動付与する
  command フィールドをそのまま利用する実装にした (crossfade/mixrampdb のような揮発性
  ストアは不要、無条件で実MPD仕様のエラーを返すだけ)。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` して書き込み可にした上で `ast.parse` で構文確認、2回適用
  しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に
  起動し MPD で確認 — `listneighbors` → `ACK [5@0] {listneighbors} No neighbor plugin
  configured` (旧来の `ACK [0@0] {listneighbors} Not implemented` から実MPD仕様の
  コード5+メッセージへ是正)。旧来の `tagtypes`/`listmounts`/`listpartitions`/`channels`/
  `decoders`/`replay_gain_status`/`crossfade 5`/`mixrampdb -10`/`getvol`/`list album`/
  `status`/`stats` の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `addtagid`/`cleartagid` (musicpd.org protocol, current playlist section) が
  `raise MpdNotImplemented` のスタブのままだった件: TODO 全項目消化済みのため自走
  エージェントが mopidy_mpd 残りの `MpdNotImplemented` スタブ (listfiles/rangeid/
  addtagid/cleartagid、mpdclearerror-patch.py/mpdlistneighbors-patch.py のコメントで
  洗い出し済み) から選定。rmpc 本体 (mierak/rmpc) を実際に clone して grep したが
  addtagid/cleartagid を送信する箇所は皆無 (rmpc はこの機能を持たない) と判明。ただし
  listneighbors (mpdlistneighbors-patch.py) と同じく「rmpc固有ではなく標準 MPD
  プロトコル準拠の不備」に該当すると判断: mpc・ncmpcpp 等の汎用 MPD クライアントが
  標準的に使うコマンドが常に ACK エラーになる現状はギャップと確認した上で着手。加えて
  現行の `cleartagid(context, tlid, tag)` は TAG を固定必須引数にしており、仕様上省略可能な
  `cleartagid ID` (TAG省略、全タグ削除) が "Not implemented" 以前に "wrong number of
  arguments" にもなる二重の不備もあわせて確認。
  verified: mpdaddtagid-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/TagCommands.cxx handle_addtagid/handle_cleartagid,
  src/queue/PlaylistTag.cxx AddSongIdTag/ClearSongIdTag) を実際に取得してソース確認し
  仕様を確定 — TAG は大文字小文字不問で解決し未知の値は `ACK Unknown tag type: {name}`
  (music_db.py の `count group Bogus` 等と同一の文言・エラーコード)、addtagid は
  TAG検証→曲の存在確認 (無ければ `ACK No such song`)→ローカルファイルでないか確認
  (ローカルなら `ACK_ERROR_PERMISSION` "Cannot edit tags of local file") の順、
  cleartagid も同じ順序 (TAG省略時は全タグ削除)。musicpd.org docs (WebFetch で確認) の
  「変更は volatile: サーバーから受信したタグで上書きされうる、曲がキューから消えたら
  データも消える」を踏まえ、mopidy core が持たない「キュー内の1曲だけへの追加タグ」
  概念を prio/Added と同じ流儀で translator.py に tlid -> {tag_type: [value, ...]} の
  揮発性ストアとして実装し、track_to_mpd_format() の出力に追加行として重畳表示
  (`tagtypes` によるフィルタもタグ種別名で自動的に効く)。mopidy のトラックは全て
  scheme 付き URI (ytmusic:/m3u: 等、このデプロイでは file: バックエンドは無効) の
  ため「ローカルファイル」判定に実際に到達する経路は無いが、仕様に忠実に
  `urllib.parse.urlparse(uri).scheme` が空 or "file" の場合のみ拒否する実装にした
  (mount/crossfade等と同種の割り切り)。actor.py の tracklist_changed イベント
  (mpdadded-patch.py が既に購読済みの同じフック) で、キューから消えた tlid の
  タグオーバーレイを掃除。パッチ適用後の生成ソースは一時コピーに `chmod u+w` して
  書き込み可にした上で3ファイル (current_playlist.py/translator.py/actor.py) とも
  `ast.parse` で構文確認、2回適用しても冪等 (スキップ) であることも確認 (この確認は
  nix ビルドが mopidy-env.nix 登録後に自動実行した postPatch で実際に非冪等エラーなく
  通ったことでも二重に確認済み)。**オフライン単体テスト**: パッチ済み env の Python から
  `mopidy_mpd.protocol.current_playlist._mpd_require_remote_track()` を合成 Track
  (uri="file:///...", "song.mp3", "", None, "ytmusic:track:abc",
  "http://example.com/x.mp3") に対し直接呼び出し、file:/スキームなし/空/None のみ
  `error_code=4 "Cannot edit tags of local file"` で拒否され、ytmusic:/http: は許可
  されることを確認 (このデプロイでは file: バックエンドが無効なため実データでは
  到達できない分岐だが、ロジック自体はオフラインで検証)。パッチ済み env の
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し実データ (YOASOBI「オリオン」
  Id1/「夜に駆ける」Id2) をキューに積んで MPD で確認 — `addtagid 1 "Comment" "hello
  world"`→OK・`playlistid 1`→`Comment: hello world`が反映、`addtagid 1 "genre"
  "Lo-fi"`(小文字タグ名)→正しく`Genre: Lo-fi`として反映 (大文字小文字不問の解決を確認)、
  同じタグ種別に2回目の`addtagid 1 "Comment" "second value"`→`Comment:`行が2行
  (multi-value、実タグの複数値表示と同じ形) に、`cleartagid 1 "comment"`(小文字、
  該当タグのみ)→Comment行のみ消えGenre行は維持、`addtagid 2 "Artist" "Extra
  Artist"`→既存の実Artist行に追加でもう1行`Artist:`が重畳表示、`cleartagid 2`
  (TAG省略、全タグ削除)→追加分のみ消え元の実データは無変更。エラー系: `addtagid 1
  "BogusTag" "x"`→`ACK Unknown tag type: BogusTag`、`addtagid 999 "Comment" "x"`
  (存在しないId)→`ACK No such song`、`cleartagid 999`→同様に`No such song`、
  `cleartagid 1 "BogusTag"`→`Unknown tag type`。**掃除の実機確認**: Id1にタグを追加
  した状態で`delete 0`→同じ曲を`addid`で再追加すると新しいId(3)にタグが一切
  漏れ継承されない(揮発性ストアがtracklist_changedで正しく掃除されたことを確認)。
  **tagtypesとの相互作用**: `addtagid 3 "Genre" "TestGenre"`→`tagtypes disable
  Genre`→`playlistid 3`でGenre行が消える、`tagtypes all`→復元、を確認 (`_has_value()`
  がタグ種別名で判定する既存の仕組みがオーバーレイタグにも自動的に効くことを実証)。
  旧来の`search any "yoasobi" sort -Date window "0:2"`/`count any`/`sticker get`
  (no such sticker応答)/`listmounts`/`listpartitions`/`channels`/`decoders`/
  `mixrampdb -10`/`replay_gain_status`/`stats`/`listneighbors`/`tagtypes`/`status`/
  `list album`/`crossfade 5`/`getvol`の回帰なし・mopidy.log に Traceback/ERROR 0件を
  確認。既知の制約: cleartagid はこの実装のオーバーレイ(addtagidで足した分)のみを
  消去し、Track本体の実メタデータ(実MPDならサーバーから受信したタグ)には触れない
  (mopidy core がキュー内の1曲だけの実タグを書き換える機構を持たないための割り切り、
  mount/crossfade と同種)。`listfiles`/`rangeid` は引き続き rmpc から一切送信されない
  ため対象外・未着手のまま (mpdmixramp-patch.py/mpdaddpos-patch.pyの既知の制約欄で
  洗い出し済み)。
- [x] `status` 応答に `audio` (MPD標準、samplerate:bits:channels、実際にデコード中の
  フォーマット) フィールドが一度も出力されない件: mopidy-mpd 3.3.0 の status.py は
  duration 等と違いこのフィールドを一切扱っていない (docstring に仕様の説明はあるが
  実装が無い)。TODO 全項目消化済みのため自走エージェントが、既に着手済みだが未コミット
  だった配置済みパッチ2本 (mpdaudioformat-patch.py/ytaudioformat-patch.py、リポジトリに
  untracked で残っていたもの) の内容を検証・完成させて引き継いだ。rmpc 本体
  (mierak/rmpc) を実際に clone して調査したところ、rmpc-mpd/src/commands/status.rs の
  `Status.audio` (status応答の"audio"キー専用パースフィールド) が
  `Status::samplerate()`/`bits()`/`channels()` として実際に使われ、
  rmpc/src/config/theme/properties.rs の `StatusProperty::SampleRate()`/`Bits()`/
  `Channels()` (テーマでステータスバーに配置可能なプロパティ) が描画に使う実装と確認。
  既定テーマでは未使用だが、audio が常に欠落している限りユーザーがテーマで配置しても
  永久に空欄になる実害あるギャップ。
  verified: mpdaudioformat-patch.py (mopidy_mpd)。crossfade/mixrampdb と同じ流儀で
  translator.py にモジュールレベルの揮発性ストア (`set_audio_format`/`get_audio_format`)
  を追加し、status.py の duration ブロックの直後に「play/pause 中のみ・値がある時だけ」
  audio を追加出力 (実 MPD 準拠、旧来の duration と同じ条件分岐を再利用)。書き込み側は
  ytaudioformat-patch.py (mopidy_ytmusic) が playback.py の `_get_track()` 末尾
  (yt-dlp でストリームURLを解決した直後、`return url` の直前) で info dict の
  `asr`(サンプルレート)/`audio_channels` (requested_formats経由のフォールバックあり) を
  取り出し `"{asr}:16:{channels}"` の形式で書き込む。bits はyt-dlpのformat情報からは
  得られないため GStreamer の一般的な PCM デコード出力 (16-bit) を仮定した固定値
  (decoders パッチの静的一覧と同種の割り切り、既知の制約として明記済み)。書き込み側は
  mopidy_ytmusic 拡張が無効な環境でも壊れないよう import ごと try/except で保護。
  パッチ適用後の生成ソース (translator.py/status.py/playback.py) は `ast.parse` で構文
  確認、nix ビルドが2回目の postPatch でも非冪等エラーなく通ることを確認 (MARKER 文字列
  による重複適用ガードが機能)。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し
  MPD で実データ確認 — YOASOBI「夜に駆ける」を `add`/`play` すると
  `status`→`audio: 48000:16:2` (実際に yt-dlp が解決した48kHz/2chが反映)、`pause 1`後も
  `audio` が維持されること、`stop`/`clear` 後 (未再生時) は audio 行が出力されない
  こと (実MPD準拠、旧来の time/elapsed/bitrate/duration と同じ「再生中のみ」条件)を
  確認。別トラック (オリオン) でも同様に反映されることを確認。旧来の
  `tagtypes`/`listmounts`/`listpartitions`/`channels`/`decoders`/`crossfade 5`/
  `mixrampdb -10`/`getvol`/`list album`/`stats`/`search any` の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。既知の制約: bits は固定値 "16" で実際のパイプラインの
  ビット深度を反映しない (mpdaudioformat-patch.py 冒頭コメントに明記)。
- [x] 曲メタデータ (`currentsong`/`playlistinfo`/`find`/`search`/`listallinfo` 等) に
  `Format` (samplerate:bits:channels、実MPDでは「その曲ファイルの音声フォーマット」を
  表すタグ) が一度も出力されない件: TODO全項目消化済みのため自走エージェントが
  musicpd.org protocol docs (Song Metadata Format節) を確認したところ、`Format` は
  `status` の `audio` (再生中デコーダの実際の出力、mpdaudioformat-patch.py で対応済み) とは
  別物で、`find`/`search`/`playlistinfo`/`currentsong`/`listallinfo`/`lsinfo` の各曲行に
  載る仕様と判明。rmpc 本体 (mierak/rmpc) を実際に clone して調査したところ、
  rmpc-mpd/src/commands/current_song.rs の `Song::samplerate()`/`bits()`/`channels()` が
  `self.metadata.get("format")` (曲の"Format"タグ) をパースする実装で、
  rmpc/src/ui/song_ext.rs の `SongProperty::SampleRate()`/`Bits()`/`Channels()`
  (テーマの song_format で曲一覧やヘッダーに配置できるプロパティ、
  rmpc/src/config/theme/properties.rs で定義・TOMLから設定可) が実際にこの値を描画に
  使う実装と確認。status の audio (ステータスバー用) とは別の、曲そのものの
  プロパティとして曲一覧に列表示できる機能であり、Format が常に欠落している限り
  ユーザーがテーマでこれらの SongProperty を配置しても永久に空欄のままになる実害
  あるギャップと判断し着手。
  verified: mpdsongformat-patch.py (mopidy_mpd) + ytsongformat-patch.py
  (mopidy_ytmusic)。mpdaudioformat-patch.py が追加した translator.py の `_audio_format`
  揮発性ストアを拡張し、直近に解決した曲の uri も一緒に記録 (`set_audio_format(value,
  uri=None)`、`get_song_audio_format(uri)` で一致時のみ値を返す)。track_to_mpd_format
  がその曲の uri が一致する時だけ `Format` を出力する。書き込み側は
  ytsongformat-patch.py が ytaudioformat-patch.py の `_get_track(self, bId)` 内の
  `set_audio_format(...)` 呼び出しに `uri="ytmusic:track:%s" % bId`
  (translate_uriの`bId = uri.split(":")[2]`の逆算、既存実装を読んで一意に復元できると
  確認済み) を追加するのみ。生成後ソース (translator.py/playback.py) は `ast.parse` で
  構文確認、パッチスクリプトの再実行が「already patched, skip」で安全に冪等である
  ことを確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動しMPDで実データ確認 —
  YOASOBI「夜に駆ける」を`add`/`play`すると`currentsong`/`playlistinfo`に
  `Format: 48000:16:2` (status の audio と同じ値) が出力され、`search any "yoasobi"`
  の同じ曲の行にも反映されることを確認。オリオンへ`clear`/`add`/`play`で切り替えると
  Format が新曲(48000:16:2)へ追従し、`search any "yoasobi"`で以前再生したYOASOBIの
  行からは Format が消え(直近解決uriのみ保持する設計通り)、Orionの行にのみ Format が
  出ることを確認。`stop`後も`currentsong`のFormatは維持(実MPD同様、Formatは再生状態に
  依らずDB由来の曲プロパティ)、`clear`後(曲が無い)は該当行自体が出ないことを確認。
  旧来の`tagtypes`/`stats`/`pause`/`status`(audioフィールド)/`list album`/`search any`の
  回帰なし・mopidy.log に Traceback/ERROR 0件を確認。既知の制約:
  mpdaudioformat-patch.py と同じくbitsは固定値"16"。また「直近に解決した1曲」のみを
  記憶する揮発性ストアのため、複数曲のFormatを同時に把握しているわけではない
  (実MPDはDBスキャン済み全曲のFormatを常時把握するが、本パッチはストリーミング
  バックエンドの性質上、再生時に解決された曲のみ分かる)。
- [x] `rangeid` (musicpd.org protocol, current playlist section、曲の部分再生区間指定) が
  `raise MpdNotImplemented` のスタブのままだった件: TODO 全項目消化済みのため自走
  エージェントが mopidy_mpd 残りの `MpdNotImplemented` スタブ (listfiles/rangeid、
  mpdclearerror-patch.py/mpdaddtagid-patch.py のコメントで洗い出し済み) から選定。
  rmpc 本体 (mierak/rmpc) を実際に clone して grep したが `rangeid` を送信する箇所は
  皆無 (rmpc はこの機能を持たない) と判明。ただし clearerror/decoders/stats/
  listneighbors と同種の「rmpc固有ではなく標準 MPD プロトコル準拠の不備」に該当すると
  判断: mpc・ncmpcpp 等の汎用 MPD クライアントが標準的に使う基本コマンドが常に ACK
  エラーになる現状はギャップと確認した上で着手。
  verified: mpdrangeid-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/QueueCommands.cxx handle_rangeid/parse_time_range,
  src/queue/PlaylistEdit.cxx SetSongIdRange, src/SongPrint.cxx PrintRange) を
  実際に取得してソース確認し仕様を確定 — 引数は "{ID} {START:END}"(秒、小数可、
  両辺省略可)、コロン無し/非数値/負値/(endが0でないのに)end<=start は全て
  `ACK_ERROR_ARG "Bad range"`、ID不在は`ACK_ERROR_NO_EXIST "No such song"`、
  対象曲の長さが既知ならstart>durationは`ACK_ERROR_ARG "Invalid start offset"`、
  end>=durationは無制限(end=0)へ自動クランプ(エラーにしない)、対象曲が現在
  再生中/一時停止中の曲そのものなら`ACK_ERROR_PERMISSION "Cannot edit the current
  song"`(ただしこのチェックはPlaylistControl.cxx Stop()がposition位置を-1へ戻さない
  ため実際には`playing`フラグでガードされておりstop後は編集可能、という実装の
  細部までソースで確認)。mopidy core は実MPDのような「キュー内1曲だけ部分再生」
  機構を持たないため(パッチ対象外)、mount/crossfade/prioと同種の「プロトコル層の
  状態保持・応答・playlistid/playlistinfoのRange反映のみ提供し実際の再生区間には
  影響しない」実装にした。prio/Added/addtagidと同じ流儀でtranslator.pyに
  tlid->(start_ms, end_ms)の揮発性ストアを追加し、actor.pyのtracklist_changed
  イベントでキューから消えたtlidを掃除。生成後ソース(current_playlist.py/
  translator.py/actor.py)は一時コピーに`chmod u+w`して書き込み可にした上で
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  パッチ済み env の dev mopidy(6601, ytmusic 実アカウント)を実際に起動し実データ
  (YOASOBI「THE BOOK for,」アルバム12曲+単曲「オリオン」「夜に駆ける」)をキューに
  積んで MPD で確認 — 未再生曲へ`rangeid ID "10:20"`→OK・`playlistid ID`に
  `Range: 10.000-20.000`が反映、`rangeid ID "30:"`(open-ended)→
  `Range: 30.000-`(無制限)、`rangeid ID ":"`(両方省略、コロンのみ)→レンジ解除・
  Range行が消える、コロン無し`"5"`/非数値`"a:b"`/逆転`"20:10"`/負値`"-5:10"`→
  いずれも`ACK [2@0] {rangeid} Bad range`、存在しないID`9999`→
  `ACK [50@0] {rangeid} No such song`、`Time: 207`の曲へ`"300:305"`(start>duration)
  →`ACK [2@0] {rangeid} Invalid start offset`、`"10:9999"`(end>=duration)→OK・
  無制限へ自動クランプされ`Range: 10.000-`。**現在曲チェックの実機確認**:
  `playid`でstatus実測(`state: play`/`songid`一致)を確認した上で対象曲へ
  `rangeid`→`ACK [4@0] {rangeid} Cannot edit the current song`、再生中でも
  別のIdへの`rangeid`→OK、`pause 1`後も再生中扱いで同様に拒否、`stop`後は
  直前に再生していた曲でも`rangeid`が成功することを実機で確認(実MPDの
  `if (playing)`ガードの挙動と一致)。**掃除の実機確認**: Idにレンジ設定後
  `deleteid`→同じ曲を`addid`で再追加すると新しいIdにレンジが一切漏れ継承
  されないことを確認(揮発性ストアがtracklist_changedで正しく掃除された)。
  旧来の`tagtypes`/`status`/`stats`/`listmounts`/`listpartitions`/`channels`/
  `decoders`/`getvol`/`crossfade 5`/`mixrampdb -10`/`search any "yoasobi" sort
  -Date window "0:2"`/`list album`/`count any "yoasobi"`/`sticker get`(no such
  sticker応答)の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: mount/crossfade/prio等と同種、mopidy coreがキュー内1曲だけの
  部分再生機構を持たないため実際の再生区間には影響しない(プロトコル応答・
  playlistid/playlistinfoのRange反映のみ)。`listfiles`は引き続きrmpcから
  一切送信されないため対象外・未着手のまま。
- [x] `listfiles` (musicpd.org protocol, music database section) が
  `raise MpdNotImplemented` のスタブのままだった件: TODO/既知の軽微な残課題を
  全項目消化済みのため自走エージェントが mopidy_mpd 残りの `MpdNotImplemented`
  スタブを再洗い出しして選定 (rangeidと並んで名指しされていたうち、rangeidは
  既に対応済みでlistfilesのみ残っていた)。rmpc本体(mierak/rmpc)を実際にclone
  してgrepしたが`listfiles`を送信する箇所は皆無(rmpcはこの機能を持たない)と
  判明。ただしclearerror/decoders/stats/listneighbors/rangeidと同種の「rmpc
  固有ではなく標準MPDプロトコル準拠の不備」に該当すると判断: mpc・ncmpcpp等の
  汎用MPDクライアントが標準的に使う基本コマンド(MPDが認識しないファイルも
  含む生ファイル一覧)が常にACKエラーになる現状はギャップと確認した上で着手。
  verified: mpdlistfiles-patch.py。実MPD(MusicPlayerDaemon/MPD
  src/command/OtherCommands.cxx handle_listfiles, FileCommands.cxx
  handle_listfiles_local, StorageCommands.cxx handle_listfiles_storage,
  DatabaseCommands.cxx handle_listfiles_db)を実際に取得してソース確認 —
  実体は3経路(ローカルFS/storageプラグイン/DBフォールバック)に分岐するが、
  出力形式は共通で通常ファイルは`file: NAME`+`size: N`(タグ情報は含まない、
  lsinfoが返すArtist/Album等は仕様外)、ディレクトリは`directory: NAME`、
  どちらも任意で`Last-Modified`が続く(size/Last-Modifiedとも"may be
  followed by"の任意属性)。mopidyのbackendは実ファイルのようなサイズ/mtime
  を持たないため(mount/decoders/stats等と同種の割り切り)、file行はuriのみ・
  size/Last-Modifiedは付与しない実装にした。lsinfoが既に使っている
  `context.browse(uri, recursive=False, lookup=False)`を再利用し
  (lookup=Falseでトラックの余分なlibrary.lookup()を回避、不正URIでの
  `MpdNoExistError`等の既存エラー処理もそのまま流用)、track参照は
  `file: {ref.uri}`、非trackの参照(ディレクトリ)は`directory: {path}`として
  列挙(lsinfo固有の「ルートではplaylistsも返す」非推奨挙動は踏襲しない)。
  生成後ソース(music_db.py)は一時コピーに`chmod u+w`して書き込み可にした上で
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  パッチ済みenvのdev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで
  実データ確認 — `listfiles`(ルート)→`directory: YouTube Music`、
  `listfiles ""`/`listfiles "/"`(lsinfoと同じ挙動)も同一、実データを含む
  `listfiles "YouTube Music/Home/Popular playlists/Summer Party"`(89件)→
  全曲が`file: ytmusic:track:VIDEOID`のみ(タグなし)で列挙され、同じ
  ディレクトリへの`lsinfo`(544行、Artist/Title等フル情報)と対比してタグが
  正しく省略されていることを確認、不正パス`listfiles "Bogus/Nonexistent/Path"`
  →`ACK [50@0] {listfiles} Not found`(lsinfoの既存browse()エラー処理を
  継承)。旧来の`tagtypes`/`status`/`list album`/`count any "yoasobi"`/
  `listmounts`/`decoders`/`lsinfo`(タグ付きの旧来動作)の回帰なし・
  mopidy.log に本パッチ由来のTraceback/ERROR 0件を確認(検証中に観測した
  唯一のERROR/Traceback×2件はこのテストアカウントが現在サインアウト状態で
  Liked Songs取得が"Sign in to listen to your liked tracks"で失敗する
  既知の別問題であり、listfiles/lsinfoとは無関係のパスで発生・本パッチの
  変更対象外)。
  既知の制約: mopidyのbackendは実ファイルのサイズ/更新日時を持たないため
  size/Last-Modified属性は常に省略(mount/decoders等と同種の割り切り)。
  rmpc自体はlistfilesを送信しないため実害はmpc/ncmpcpp等汎用クライアントの
  互換性向上に留まる。
- [x] `sticker inc`/`sticker dec` と `stickernames`/`stickertypes`/`stickernamestypes`
  (MPD 0.24+、musicpd.org protocol sticker section) が丸ごと欠落していた件:
  TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが mopidy_mpd 側の
  未対応コマンドを再洗い出しして選定(`MpdNotImplemented`スタブは全消化済みだった
  ため、mpd.readthedocs.io の protocol リファレンスを実際に fetch して既存実装
  (mpdsticker-patch.py 由来の list/find/get/set/delete のみ)との差分を確認)。
  verified: mpdstickernames-patch.py。実MPD(MusicPlayerDaemon/MPD
  src/command/StickerCommands.cxx handle_sticker_names/handle_sticker_types/
  handle_sticker_names_types)を実際に取得してソース確認 — sticker inc/decは
  実DBは`INSERT ... ON CONFLICT DO UPDATE SET value = value +/- ?`という単一SQLで
  新規作成と加減算を両立、stickernamesは`name: `、stickertypesは`stickertype: `、
  stickernamestypesは`name: `/`type: `のペアで返す仕様と判明。本実装は
  `_mpd_sticker_check_type`が"song"以外を一律拒否する既存スコープ通りsongタイプ
  のみ実装のため、stickertypesは実MPDのfilter/playlist/song+タグ名ではなく
  `stickertype: song`のみ返す割り切り(mpdstats-patch.py のsongs/db_playtime
  未実装と同種、実装と矛盾する過大申告を避けた)。パッチ済みenvのdev
  mopidy(6601, ytmusic)を実際に起動しMPDで実データ確認 —
  `sticker set song URI rating 3`→`sticker inc song URI rating 2`→
  `sticker get`で`rating=5`、既存値への`sticker dec ... 4`で`rating=1`、
  未設定stickerへの`sticker inc song URI2 playcount 3`(新規作成)→
  `sticker get`で`playcount=3`と一致、`stickernames`で登録済み名を`name: `で
  列挙、`stickertypes`で`stickertype: song`、`stickernamestypes`/
  `stickernamestypes song`で`name:`/`type: song`ペア列挙、
  `stickernamestypes playlist`→`ACK Unknown sticker domain: playlist`、
  不正VALUE`sticker inc song URI rating notanumber`→
  `ACK invalid sticker value`、引数不足`sticker inc song URI 2`→
  `ACK wrong number of arguments`を確認。idle通知: 別接続で`idle sticker`購読中に
  `sticker dec`実行→即座に`changed: sticker`受信(mpdstickeridle-patch.py の
  通知機構がinc/decでも動作)を確認。旧来の`tagtypes`/`status`/`commands`
  (新規3コマンドが一覧に追加され、list_command=Falseの既存`sticker`は元々
  `commands`一覧に出ない仕様のまま)の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
  既知の制約: type=songのみ対応(playlist/filterスティッカーは既存実装と同様
  未対応)。rmpc本体は`sticker inc`/`dec`/`stickernames`等を送信しないため
  実害はmpc/ncmpcpp等汎用クライアントおよびrating/playcount系スティッカーを
  直接操作したいスクリプトの互換性向上に留まる。
- [x] `mopidy_ytmusic/backend.py` の `scrobble_track()` が唯一 try/except による保護を
  持たず、YouTube側のplayer応答形状次第でバックエンドアクター全体を停止させうる件:
  TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが mopidy_ytmusic の
  コード品質を再調査 (ytduration-patch.py 等これまでの一連の発見的パッチと同じ流儀)
  して発見した項目。
  verified: ytscrobble-patch.py。同ファイル内の他の外部API呼び出しメソッド
  (`_get_youtube_player()`/`_get_auto_playlists()`)は例外なく`try/except Exception:
  logger.exception(...)`で保護されているのに対し、`scrobble_track()`だけが唯一無保護で
  `player_response["playbackTracking"]["videostatsPlaybackUrl"]["baseUrl"]`という
  多段dictアクセスを行っていることをソース確認。`scrobble_track()`は
  `scrobble_fe.py`の`track_playback_ended`から`mopidy.listener.send(
  YTMusicScrobbleListener, "scrobble_track", bId=bId)`経由で曲再生完了ごとに呼ばれるが、
  実体は`YTMusicBackend`自身(pykka.ThreadingActor、ライブラリ/再生/プレイリスト提供を
  兼ねる唯一のバックエンドアクター)のメソッドとして実行される。scrobbleは再生完了後に
  独立して発行される2回目のAPI呼び出しのため、対象動画が再生後に地域制限/削除/
  メンバー限定化等でplayabilityStatusがERROR/LOGIN_REQUIRED/UNPLAYABLEになり得ることは
  現実的で、その場合player_responseに"playbackTracking"キーが存在せずKeyErrorが発生する。
  インストール済みpykka(1.86.0系)の`Actor.on_failure`docstring("immediately before the
  thread exits")を実際に確認し、tell()経由のメッセージ処理中の未捕捉例外はアクター停止に
  つながる仕様と確定。つまり有効化(enable_scrobbling)時に曲を最後まで聴くたびに起こりうる、
  mopidyプロセス再起動までYouTube Music機能全体が使用不能になる実害の大きいクラッシュと
  判明。対策: 他の外部API呼び出しメソッドと同じ流儀で本体全体をtry/except Exceptionで
  包み、失敗時はlogger.exceptionでログするだけに留めてアクターを止めないよう修正。
  パッチ適用後の生成ソースは一時コピーに`chmod u+w`して書き込み可にした上で`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。パッチ済みenvのdev
  mopidy(6601, ytmusic実アカウント)を実際にビルド・起動しクリーンな起動
  (Traceback/ERROR 0件、YTMusic Auto Playlists正常ロード)を確認した上で、
  ビルド済みenvから実パッチ済みモジュール`mopidy_ytmusic.backend`を実際にimportし、
  `player`APIが`playbackTracking`キーを含まない応答(地域制限/削除等を模した実際に
  起こりうる形状)を返すよう`_send_request`をモックした`self`で`scrobble_track()`を
  直接呼び出して実機検証 — 修正前と同じ`KeyError: 'playbackTracking'`が内部で実際に
  発生することをトレースバックで確認した上で、それが`logger.exception`でログされるのみで
  呼び出し元へは一切伝播しない(`scrobble_track()`が正常にreturnする)ことを確認。
  GI_TYPELIB_PATH/GST_PLUGIN_SYSTEM_PATH_1_0は実行中のdev mopidyプロセス自身の環境変数
  (`ps eww`で取得)を再現して用いたため、mopidy本体が実際に使うものと同一のgi/gst
  バインディング経由でのimportであることを確認済み。旧来の`status`/`tagtypes`/
  `search any "yoasobi"`(実データ3件ヒット)の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
  既知の制約: `player`API呼び出し自体が失敗する他のケース(ネットワークエラー等)や
  今回モックしていない別の応答形状異常も同じtry/exceptで一括して救済されるが、
  個別のエラー種別に応じた再試行等は行わない(他の外部API呼び出しメソッドと同種の
  「失敗したら諦めてログするだけ」という割り切り)。
- [x] `playlistlength {NAME}` (musicpd.org protocol, stored playlists section、MPD 0.24+
  で追加。ストアドプレイリストの曲数/総再生時間だけを軽量に返す) がコマンド自体
  丸ごと欠落し常に `ACK Unknown command` になる件: TODO/既知の軽微な残課題を全項目
  消化済みのため自走エージェントが mopidy_mpd の再洗い出しでは新規発見が尽きたため
  mpd.readthedocs.io の protocol リファレンスを実際に fetch し、実装済みコマンド
  一覧(`@protocol.commands.add(...)` を全 grep)と全文照合して差分を選定
  (searchcount/outputset/getfingerprint/playlistlength/searchplaylist/protocol の
  6件が未実装と判明)。rmpc 本体(mierak/rmpc)を実際に clone して grep したところ
  いずれも rmpc 自身は送信しない(rmpc は `status` 応答の `playlistlength` フィールドは
  解釈するが同名のこのコマンド自体は使わない)と確認した上で、mpdlistfiles-patch.py/
  mpdstickernames-patch.py 等と同種の「rmpc固有ではなく標準MPDプロトコル準拠の不備
  (mpc/ncmpcpp等の互換性)」として選定。他5件はそれぞれ本パッチ範囲での実装が
  困難(getfingerprintはlibchromaprint必須でmopidyのリモートバックエンドに経路が
  無い、outputsetはmopidyのaudio output抽象にruntime attributeの概念が無い、
  protocolはサブコマンドでコマンド可視性自体を動的に変える大掛かりな機能で
  dispatcherの権限モデルに触れる、searchcount/searchplaylistは既存の肯定/否定
  フィルタ演算子機構(mpdfilterkind-patch.py等)との整合を要し1回のパッチとしては
  範囲が広い)と判断し見送り、既存の `_get_playlist` ヘルパ(listplaylist/
  listplaylistinfoが使用)だけで完結し外部依存が無い playlistlength を選定した。
  verified: mpdplaylistlength-patch.py。パッチ済みenvのdev mopidy(6601, ytmusic
  実アカウント)を実際にビルド・起動しMPDで実データ確認 —
  実装当初は `_get_playlist` が返す軽量Track(length未設定)をそのまま合計した結果
  `songs: 2`/`playtime: 0` と曲数のみ正しく再生時間が常に0になる不具合を実機で発見、
  listplaylistinfo と同じ `context.core.library.lookup()` によるフルTrack差し替えに
  修正して再検証 — `playlistadd`で2曲(262秒/207秒)追加した実プレイリストに対し
  `playlistlength`→`songs: 2`/`playtime: 468`(実MPDと同じ切り捨て、count/statsと
  同じ丸め規約)、3曲目(重複曲)追加後は`songs: 3`/`playtime: 729`と単調増加を確認、
  存在しないプレイリスト名→`ACK No such playlist`(listplaylist/listplaylistinfoと
  同じエラー文言)、引数無し`playlistlength`→`ACK wrong number of arguments`を確認。
  旧来の`status`/`tagtypes`/`count any "yoasobi"`/`listplaylist`(存在しない名前での
  ACK)の回帰なし、mopidy.log のERROR/Tracebackは`playlistadd`が新規プレイリスト作成時に
  内部で使う`context.core.playlists.save`由来の既知のytmusicapi HTTP 401(このテスト
  アカウントの書き込み権限不足、mpdplaylistrange-patch.py等の検証時にも確認済みの
  pre-existingな挙動)のみで新規リグレッションではないことを確認。
- [x] `searchcount {FILTER} [group {GROUPTYPE}]` (musicpd.org protocol, music database
  section、`count` と全く同じ意味論だが `find`/`search` の関係同様に大文字小文字を
  区別しない) がコマンド自体丸ごと欠落し常に `ACK unknown command` になる件:
  mpdplaylistlength-patch.py の調査時に mpd.readthedocs.io の protocol リファレンスと
  照合して見つかった未実装6件 (searchcount/outputset/getfingerprint/playlistlength/
  searchplaylist/protocol) のうち、当時は「既存の肯定/否定フィルタ演算子機構
  (mpdfilterkind-patch.py等) との整合を要し1回のパッチとしては範囲が広い」として
  searchplaylist と共に見送られていた項目。今回自走エージェントが再調査したところ、
  mpdcount-patch.py 由来の `_mpd_count_grouped` が mpdnegfilter-patch.py/
  mpdfilterkind-patch.py 適用後は既に `negatives`/`positives` を引数として受け取る
  形に拡張済みで、`count` (`library.search(..., exact=True)`) と `search`
  (`library.search(query)`、exact省略=False) の唯一の違いが `exact` フラグである
  ことをソース確認したため、`_mpd_count_grouped` に `exact=True` 引数を追加 (count は
  無変更のデフォルト値で動作) し、`searchcount` からは `exact=False` で呼ぶだけで
  group再帰・negatives/positivesフィルタを丸ごと再利用でき、当初の懸念ほど範囲は
  広くないと判明したため単独パッチとして実装した。
  verified: mpdsearchcount-patch.py。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して書き込み可にした上で `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。実データ (dev mopidy 6601, ytmusic実アカウント) は
  ライブラリ内に大文字小文字違いの同一タグ値が存在しないため case-insensitive の
  違いを実証できないと判断し、mpdsort-patch.py/mpdwindow-patch.py 等と同じ流儀で
  検証用スタブ backend (pykka.ThreadingActor + mopidy.backend.Backend、
  7トラック・genre "Rock"×2/"Jazz"×3/"Pop"×1/大文字違いの"ROCK"×1を含む、
  search()がexactフラグに応じて大文字小文字区別/不問を切り替える実装、
  get_distinct()実装、entry_points.txtで/tmpにdist-info生成、別ポート6602)を
  実際に起動しMPDで確認 — `count genre "rock"`(小文字で検索、実データは"Rock"/
  "ROCK"のみ)→`songs: 0`(大文字小文字区別のため不一致)、`searchcount genre "rock"`
  →`songs: 3`(Rock×2+ROCK×1、大文字小文字を区別しないことを実証)、
  `count genre "Rock"`→`songs: 2`(完全一致のRockのみ)、`searchcount genre "Rock"`
  →`songs: 3`(大文字小文字不問でROCKも含む)、フィルタ式演算子併用
  `searchcount "(Genre == \"rock\")"`→`songs: 3`(mpdfilterkind-patch由来の
  positives機構が大文字小文字不問で正しく機能)、`count "(Genre == \"rock\")"`
  →`songs: 0`(同フィルタでもcountは区別、対比確認)、`searchcount
  "(Genre contains \"oc\")"`/`searchcount "(Artist starts_with \"artist\")"`も
  期待通りの件数、`searchcount group genre`→Jazz/Pop/ROCK/Rockの4グループで
  正しく列挙、`searchcount group Bogus`→`ACK Unknown tag type: Bogus`
  (`_mpd_extract_group_params`を無改変で共有)、引数不足`searchcount artist`
  (値省略)→`ACK incorrect arguments`、フィルタ・group共に無い`searchcount`/
  `count`→`songs: 0`(空queryはmopidy core の `library.search()` が
  `if not query: return []` で即空応答を返す既存の仕様通り、`count`と同じ挙動で
  新規リグレッションではない)を確認。旧来の`count group genre`(Rock:2/ROCK:1と
  正しく区別、回帰なし)/`list genre`/`find genre "Rock"`/`search genre "rock"`の
  回帰なしも確認。dev mopidy(6601, ytmusic実アカウント)でも実データで
  `searchcount any "yoasobi"`→`songs: 2`/`playtime: 469`(`count any "yoasobi"`と
  同値、実データに大文字小文字違いの重複が無いため差が出ないのは想定通り)、
  `searchcount any "yoasobi" group album`(ytmusicのget_distinctがalbum未実装のため
  空でOK応答、`count ... group album`と同じ既知の別項目の制約)、`tagtypes`含め
  Traceback/ERROR 0件を確認。
  既知の制約: `_mpd_count_grouped`のgroup再帰は各group値を`get_distinct()`で
  列挙後`subquery[gfield]=[str(gvalue)]`として`library.search(..., exact=exact)`
  で絞り込む設計(count/list group と共有)のため、`exact=True`の`count group`
  では大文字小文字が完全一致でしか揃わずgroup値ごとに正しく分離されるが、
  `exact=False`の`searchcount group`では同一タグの大文字小文字違いの値
  (上記スタブの"Rock"/"ROCK"等、通常の実ライブラリでは稀なデータ品質問題)が
  互いを取り込み合い、双方のgroup行が本来より多い件数(この場合は両方とも
  Rock+ROCKの合計3)を示す既知のクロスコンタミネーションがある
  (`searchcount`単体・`group`無しでの使用、または大文字小文字が統一された
  通常のタグデータでは発生しない)。この設計は既存の`count`/`list`のgroup実装を
  そのまま再利用したものでありパッチ範囲の再設計は見送った。rmpc本体
  (mierak/rmpc)は`searchcount`自体を送信しないため実害はmpc/ncmpcpp等
  汎用クライアントおよびタグの大文字小文字が不統一な稀なライブラリに限られる。
- [x] `searchplaylist {NAME} {FILTER} [window {START:END}]` (musicpd.org protocol, stored
  playlists section、MPD 0.24+。NEWS: "new commands ... 'searchplaylist' ...") がコマンド
  自体丸ごと欠落し常に `ACK unknown command` になる件: mpdplaylistlength-patch.py の調査時に
  mpd.readthedocs.io の protocol リファレンスと照合して見つかった未実装6件
  (searchcount/outputset/getfingerprint/playlistlength/searchplaylist/protocol) のうち、
  当時は「既存の肯定/否定フィルタ演算子機構 (mpdfilterkind-patch.py等) との整合を要し
  1回のパッチとしては範囲が広い」として searchcount と共に見送られていた項目。
  mpdsearchcount-patch.py が同じ懸念だった `count` の case-insensitive 版を、既存の
  `_mpd_count_grouped` の再利用だけで単独パッチとして実装できると判明させた前例に倣い
  再調査したところ、current_playlist.py (mpdplaylistfind-patch.py/mpdnegfilter-patch.py/
  mpdfilterkind-patch.py が段階的に拡張してきた) の `_pf_matches` がクエリ/否定/肯定演算子
  全対応のローカル Track マッチャとして既に完成しており、これを import して再利用するだけで
  当初の懸念ほど範囲は広くないと判明したため単独パッチとして実装した。
  verified: mpdsearchplaylist-patch.py。実 MPD (MusicPlayerDaemon/MPD
  src/command/PlaylistCommands.cxx handle_searchplaylist, src/playlist/Print.cxx
  playlist_provider_search_print, src/command/AllCommands.cxx) を実際に取得してソース確認し
  仕様を確定 — FILTER は find/search と同じ構文で大文字小文字を区別しない
  (fold_case=true)、sort 修飾は存在せず window のみ、StringNormalizationEnabled は一切
  参照しない (playlistsearch と異なり diacritics 除去の対象外、DatabaseCommands.cxx/
  QueueCommands.cxx のみが参照することを gh search code で確認済み)、`Pos: N` は元の
  プレイリスト内インデックス (window はマッチ結果に対するスライスとして働く、位置カウンタ
  自体はマッチの有無に関わらず全曲を順に数える)。実装は listplaylistinfo/playlistlength と
  同じ `_get_playlist` + `context.core.library.lookup()` でプレイリスト全曲を実 Track に
  解決し、current_playlist.py の `_pf_matches` (strict=False) をそのまま適用、
  `_query_from_mpd_search_parameters`/`_mpd_pop_negatives`/`_mpd_pop_positives`/
  `_mpd_parse_window` も music_db.py から再利用。新規ロジックは「window のみを末尾から
  剥がす」抽出関数 (`_mpd_extract_window_only`、sort非対応のため`_mpd_extract_sort_params`
  とは別に用意) のみ。`protocol.commands.add` が `*args` と固定引数の混在を許さない制約
  (playlistfind/playlistsearchと同じ) のため `searchplaylist(context, *params)` とし、
  NAME も params から手動抽出。track_to_mpd_format は plain Track (tlid=None) には Pos を
  付与しないため、`("Pos", position)` を結果へ手動追記。パッチ適用後の生成ソースは一時
  コピーに当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し実データ(YOASOBI「THE BOOK for,」の
  4曲+Artist情報を持たない曲1件、`playlistadd`で計5曲のストアドプレイリスト "SPTest1" を
  作成、順にPos 0-4)で MPD プロトコルを直接叩いて確認 —
  `searchplaylist "SPTest1" artist "yoasobi"`(小文字、大文字小文字不問)→Pos 0/1/2/4の
  4曲(Artist情報の無い曲=Pos3のみ正しく除外)、`... window "1:3"`→マッチ結果に対する
  スライスでPos1/2のみ、フィルタ式 `"(Title contains \"ADRENA\")"`→Pos1、
  `"(Artist == \"yoasobi\")"`(小文字でも==が大文字小文字不問)→4曲、
  `"(Title starts_with \"UNDE\")"`/`"(Title =~ \"^UND\")"`→Pos2、
  `"(Artist == \"YOASOBI\") AND (Title != \"UNDEAD\")"`(肯定+否定併用)→Pos0/1/4
  (UNDEADのみ正しく除外)。エラー系: 存在しないプレイリスト名→`ACK No such playlist`、
  FILTER省略(`searchplaylist "SPTest1"`)/引数無し(`searchplaylist`)→
  `ACK wrong number of arguments`、windowのみでFILTER無し→同エラー、不正window
  `"a:b"`→`ACK Invalid window: a:b`、未知タグ`Bogus "x"`→`ACK incorrect arguments`、
  否定条件のみ(positiveな条件皆無)`"(Artist != \"yoasobi\")"`→`ACK incorrect arguments`
  (`_query_from_mpd_filter_expression`自体の既存ガード、playlistfind/playlistsearchと
  同じ制約を自然に継承)。`playlistlength "SPTest1"`→`songs: 5`/`playtime: 956`
  (207+188+183+176+202、正しい値と一致)。旧来の`tagtypes`/`status`/`listplaylistinfo`/
  `playlistfind artist`/`playlistsearch artist`/`count any "yoasobi"`/`list album`/
  `listplaylists`の回帰なし・mopidy.log の Traceback は`playlistadd`が新規プレイリスト
  作成時に内部で使う`context.core.playlists.save`由来の既知のytmusicapi HTTP 401
  (このテストアカウントの書き込み権限不足、mpdplaylistlength-patch.py等の検証時にも
  確認済みのpre-existingな挙動)1件のみで新規リグレッションではないことを確認。
  既知の制約: playlistfind/playlistsearchと同じ既存の仕様上、フィルタが`!=`/`!~`のみ
  (positiveな条件皆無)の場合は`ACK incorrect arguments`のまま(この制約は
  `_query_from_mpd_filter_expression`共有関数自体に起因し、searchplaylistは既にローカルに
  全曲データを持っているため技術的には解除可能だが、playlistfind/playlistsearchとの
  一貫性を優先しそのまま踏襲した)。rmpc本体は`searchplaylist`自体を送信しないため実害は
  mpc/ncmpcpp等汎用クライアントの互換性向上に留まる。
- [x] `idle [SUBSYSTEMS...]` がクライアントから受け取ったサブシステム名を一切検証しない件:
  mopidy_mpd/protocol/status.py の `idle()` 実装には `# TODO: test against valid subsystems`
  というソース自身のコメントが残されたままで、存在しないサブシステム名(typo含む)を
  渡しても黙って `context.subscriptions` に追加するだけだった。TODO 全項目消化済みのため
  自走エージェントが mopidy_mpd 本体に残存する他の `# TODO` コメント (music_db.py/
  status.py/dispatcher.py/stored_playlists.py等)を洗い出す中で発見し、実 MPD
  (MusicPlayerDaemon/MPD src/command/OtherCommands.cxx handle_idle,
  src/protocol/IdleFlags.cxx idle_parse_name/idle_names) を実際に取得してソース確認した
  ところ、実 MPD は引数を1つずつ大文字小文字を区別せず既知の14種
  (database/stored_playlist/playlist/player/mixer/output/options/sticker/update/
  subscription/message/neighbor/mount/partition)と照合し、1つでも不一致なら
  `ACK_ERROR_ARG`(コード2)で`Unrecognized idle event: {name}`を返し idle モードには
  一切入らない実装と確定。さらに mopidy_mpd の `SUBSYSTEMS` 定数がこの14種のうち
  `neighbor` のみ欠落 (13種) していることも判明。無効な名前が黙って登録されると
  当該イベントは永遠に発火しないため、`idle` がその接続を無応答のまま永久にブロックする
  (ACK にもならない)実害があると確認した上で着手。
  verified: mpdidle-patch.py。status.py の `SUBSYSTEMS` に `neighbor` を追加し、`idle()`
  冒頭で全引数を実MPDと同様に大文字小文字を区別せず検証(1つでも不正なら
  `context.subscriptions`を一切変更せず`exceptions.MpdArgError`で即エラー)、
  正当な場合は小文字化して従来通り登録するよう変更。パッチ適用後の生成ソースは
  一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD プロトコルを直接叩いて確認 —
  `idle bogus`→即座に`ACK [2@0] {idle} Unrecognized idle event: bogus`(idle モードに
  入らずブロックしない)、`idle player bogus`(有効+無効混在)→同様に即エラーで
  `context.subscriptions`は変更されない(直後に別接続で`idle player`を送っても
  即座には応答が返らずタイムアウトすることで、先行した失敗idleが状態を汚染していない
  ことを確認)、`idle Player`(大文字小文字混在)→有効として受理されタイムアウトまで
  ブロック(`noidle`→OK)、`idle neighbor`(新規追加した名前)→有効として受理されブロック、
  `idle`(引数無し、全サブシステム購読)・`idle player mixer`(複数の有効な引数)は
  従来通りブロック・`noidle`→OK、実イベント発火の回帰確認として`idle mixer`でブロック中に
  別接続から`setvol 42`を送信→実際に`changed: mixer`で即座にwakeupすることを確認
  (検証の副作用で終わらず、正当なidleの実動作自体に影響が無いことも担保)。旧来の
  `status`/`tagtypes`の他フィールドの回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: rmpc本体(mierak/rmpc)は常に有効なサブシステム名のみ送信するため
  (mpdlistneighbors-patch.py検証時にgrep済み)実害は無いが、`mpc`/`ncmpcpp`等の汎用MPD
  クライアントがtypoしたサブシステム名を送った場合の無応答ハングを防ぐ、標準MPD
  プロトコル準拠の不備修正。
- [x] `mopidy_ytmusic.library.get_distinct("album", query)` が `query` 引数を一切見ず常に
  ライブラリの全アルバムを返す件: `list Album group AlbumArtist` (mpdlist-patch.py) は
  各 AlbumArtist ごとに `subquery={"albumartist": [artist]}` を積んで
  `get_distinct("album", subquery)` を再帰的に呼ぶが、ytdistinct-patch.py が有効化した
  album 分岐はこの `query` を無視するため、実際には**全 AlbumArtist の子に「ライブラリの
  全アルバム」が丸ごと重複表示**されてしまう(rmpc の Album Artists タブが実質使い物に
  ならない)。`count group album`(mpdcount-patch.py が同じ get_distinct 呼び出しを共有)
  も同様に誤ったグルーピングになる。TODO 全項目消化済みのため自走エージェントが
  `mopidy/backend.py`(`get_distinct` の docstring が `query` を「結果を絞り込むためのクエリ」
  と明記)・`mopidy_mpd/protocol/music_db.py`(`_mpd_list_grouped`/`_mpd_count_grouped` の
  subquery 構築)・ytmusicapi の `get_library_albums()` 実装(各アルバムが
  `artists: [{name, id}]`/`year` を保持)を実際にソース確認した上で発見・着手。
  verified: ytdistinctfilter-patch.py。ytdistinct-patch.py が生成する album 分岐に対する
  追加パッチとして新規実装(nix/lib/mopidy-env.nix に ytdistinct-patch.py の直後で登録)。
  `query` から `artist`/`albumartist`(大文字小文字無視)と `date` を取り出し、
  `get_library_albums()` の各エントリの `artists`(名前の集合)/`year` と実際に突き合わせて
  一致しないものを除外するよう修正(ジャンル等 ytmusic ライブラリのアルバム情報に無い
  フィールドでの絞り込みは、データが無いため従来通り無条件通過のまま=既知の制約)。
  パッチ適用後のソースは一時コピーに当てて `ast.parse` で構文確認、2回適用で
  anchor 消費済みとして意図通り assert で落ちる(他の単純置換パッチと同じ流儀、
  二重適用は起きない nix ビルド前提)ことを確認。ビルド後の実 env から直接
  `mopidy_ytmusic.library.YTMusicLibraryProvider.get_distinct` を import し、
  `backend.api.get_library_albums` をモック(4アルバム、Artist One/Two 各2枚、うち1枚は
  両アーティスト共作、year違いあり)して単体検証 —
  query無し→旧来通り全4アルバム、`{"albumartist": ["Artist One"]}`→3枚(共作アルバム含む)、
  `{"artist": ["artist two"]}`(小文字表記)→大文字小文字無視で2枚、`{"date": ["2019"]}`→
  該当年の2枚、`{"albumartist": ["Artist One"], "date": ["2019"]}`(AND)→共作の1枚のみ、
  `{"albumartist": ["Nonexistent"]}`→0枚、`{"genre": ["Rock"]}`(データ無しフィールド)→
  絞り込まず全4枚(既知の制約通り)。`list Album group AlbumArtist` の実際の呼び出し列を
  シミュレート(get_distinct("albumartist")→Artist One/Two、各々に対し
  get_distinct("album", {"albumartist": [...]})→各アーティスト固有のアルバムのみ、
  もはや全カタログの重複表示にならないことを確認)。dev mopidy(6601, ytmusic 実アカウント)
  を実際に起動しクリーン起動・Traceback/ERROR 0件を確認した上で `status`/`tagtypes`/
  `search any "yoasobi"`/`count any "yoasobi"`/`count any "yoasobi" group album`/
  `list album group albumartist`/`listplaylists` を実際に送り旧来コマンドの回帰なしを確認
  (このテストアカウントはライブラリに保存済みアルバム/アーティストが1件も無いため
  `list album`/`list artist` 自体が元々空応答になる環境で、実データでの
  fixed-vs-broken の直接比較はできなかった。そのため上記の単体検証で
  `get_distinct` のパッチ後コードそのものを直接呼び出し、修正の効果を厳密に確認した)。
- [x] `move`/`moveid` の TO が相対指定 (`+N`/`-N`、現在曲基準) を一切受け付けない件:
  mopidy_mpd 3.3.0 は両コマンドとも `to=protocol.UINT` (絶対位置のみ) でパースしており、
  `+`/`-` 始まりの値は `ValueError` → `ACK incorrect arguments` になり機能が丸ごと失敗する
  (`moveid` のdocstring自身は既に「If TO is negative, it is relative to the current song」
  と書いているのに実装が追従していなかった)。TODO 全項目消化済みのため自走エージェントが
  mopidy_mpd/protocol/current_playlist.py を洗い出す中で発見し、実 MPD
  (MusicPlayerDaemon/MPD src/command/PositionArg.cxx ParseMoveDestination,
  src/command/QueueCommands.cxx handle_move/handle_moveid) をソース確認して仕様を確定した
  上で着手 (`add`/`addid`/`load`/`findadd`/`searchadd` の POSITION と同じ +N/-N 書式だが、
  move は FROM の範囲を一旦キューから外した空間へ挿入するため現在曲位置の補正が必要な点、
  および移動対象の範囲自体に現在曲が含まれる場合は基準が定まらずエラーとする点が異なる)。
  verified: mpdmoveto-patch.py。current_playlist.py に `_mpd_move_to`(値パーサ)・
  `_mpd_resolve_move_to`(範囲除去後のインデックス空間への解決、add/addid と同じ
  `_MpdPlayerSyncError`/`MpdArgError`パターンを流用)を追加し、`move`/`moveid` 双方の
  `to` コンバータを `protocol.UINT` からこれに置換。パッチ適用後のソースは一時コピーに
  当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、YOASOBI/米津/ヨルシカ検索結果
  7曲をキューに積み `play 3` で現在曲を設定した上で MPD プロトコルを直接叩いて確認 —
  `moveid <pos1のid> +0`(現在曲より前の曲を現在曲の直後へ)→現在曲がFROM除去で1つ
  繰り上がった上でその直後に正しく挿入されることをplaylistinfoで確認、
  `moveid <pos5のid> -0`(現在曲より後の曲を現在曲の直前へ)→現在曲の直前に正しく挿入、
  `moveid <現在曲自身のid> +0`/`-0`→`ACK [2@0] {moveid} Cannot move current song relative
  to itself`(実MPDと同じエラー文言)、`move 0:2 +0`(範囲版、現在曲を含まない2曲を
  現在曲の直後へ)→正しい順序で挿入、`move 0 100`(絶対位置で範囲外)→
  `ACK [2@0] {move} Bad song index`(旧実装は無検証でcore側のAssertionErrorが漏れる
  経路だったため副次的にも改善)、`moveid <id> +999`(相対offsetが大きすぎ)→
  `ACK [2@0] {moveid} Number too large`、`move 0:1 +0`(現在曲を含む範囲を相対移動)→
  `ACK [2@0] {move} Cannot move current song relative to itself`、`moveid <id> +abc`
  (非数値)→`ACK incorrect arguments`、`move 0 6`(絶対位置、相対でない従来経路)→
  従来通り正常動作(回帰なし)。旧来の`status`/`tagtypes`/`count any`/
  `search any ... sort -Date`/`playlistfind`の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
- [x] `outputs`/`enableoutput`/`disableoutput`/`toggleoutput` (audio_output.py) が
  mpdpartition-patch.py の追加した出力所属パーティション (`translator.
  _output_partition`) を一切参照せず、どのパーティションから呼んでも常に同じ応答
  (plugin: "mopidy"、実際のmute状態) を返す件: TODO 全項目消化済みのため自走
  エージェントが rmpc 本体 (mierak/rmpc) を実際に clone して調査したところ、
  rmpc/src/shared/mpd_client_ext.rs の `list_partitioned_outputs()` が「default
  パーティションの `outputs` 応答で `plugin == "dummy"` の出力は他パーティション所属
  (`PartitionedOutputKind::OtherPartition`)、それ以外は自パーティション所属
  (`CurrentPartition`)」という実MPD仕様の契約 (関数内コメント: "MPD lists all
  outputs only on the default partition ... We also have to list outputs on the
  current partition to find out which output is actually enabled on the current
  partition") を前提にしており、rmpc/src/ui/modals/outputs.rs の Outputs モーダル
  (グローバルアクション `GlobalAction::ShowOutputs`、実キーバインド可能) がこの
  分類で `OtherPartition` 行のみ `move_output`、`CurrentPartition` 行のみ
  `toggle_output` を送るよう出し分けている実害のあるギャップと判明 (`newpartition`→
  `moveoutput` で "Mute" を別パーティションへ移した後、元のパーティションから
  Outputs モーダルを開いても常に plugin: "mopidy" (非dummy) のままのため
  CurrentPartition と誤分類され、モーダルの「別パーティションへ移動する」操作が
  機能しない)。mpdpartition-patch.py 自体の検証 (本ファイル既存項目) は
  `partition`/`newpartition`/`delpartition`/`moveoutput`/`listpartitions`/idle/
  `status.partition` は網羅していたが、`outputs` を非defaultパーティションから
  実行した際の dummy/所有権表現までは検証していなかった。
  verified: mpdoutputpartition-patch.py。audio_output.py に
  `_mpdoutputpartition_owned(context)` ヘルパ (`translator.output_partition_get
  ("Mute") == translator.partition_get(id(context.session))`) を追加し、
  `outputs()` は所属パーティション不一致時に `plugin: "dummy"` / `outputenabled: 0`
  を返すよう変更、`enableoutput`/`disableoutput`/`toggleoutput` の `outputid == 0`
  分岐にも同じ所属チェックを追加し不一致なら実MPD同様 `ACK No such audio output`
  とする(mpdpartition-patch.py が既に持つ揮発性ストアを参照するのみで新規状態は
  持たない)。パッチ適用後のソースは一時コピーに当てて `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し、2本のTCP接続(A=default固定, B)でMPDプロトコルを
  直接叩いて確認 —
  ベースライン(パーティション未使用時)の `outputs`→従来通り`plugin: mopidy`
  (回帰なし)、`newpartition p2`→OK、B `partition p2`→OK、B `outputs`(Muteはまだ
  default所属)→`plugin: dummy`/`outputenabled: 0`、B `enableoutput 0`(未所属)→
  `ACK [50@0] {enableoutput} No such audio output`、B `moveoutput Mute`→OK、
  B `outputs`(所属後)→`plugin: mopidy`、A `outputs`(移動後のdefault、Muteはもう
  default所属でない)→`plugin: dummy`/`outputenabled: 0`、A `enableoutput 0`
  (もう非所属)→同じくACKエラー、B `enableoutput 0`(所属している)→OK、
  B `outputs`→`outputenabled: 1`に反映、A `moveoutput Mute`(defaultへ戻す)→OK、
  A `outputs`→`plugin: mopidy`/`outputenabled: 1`(mute状態自体はcore.mixerの
  実状態のままパーティション跨ぎで保持され続けることも確認)、B切断後
  `delpartition p2`→OK(切断前は`partition still has clients`で実MPD同様に拒否される
  ことも確認)。旧来の`toggleoutput 0`/`disableoutput 0`/`outputs`(所属パーティション
  内、従来の単一パーティション運用)・`tagtypes`の回帰なしも確認。mopidy.log に
  ERROR/WARNING/Traceback 0件を確認。
- [x] `listplaylist`/`listplaylistinfo` (ストアドプレイリスト参照系) が NAME のみの固定引数で、
  実 MPD が MPD 0.24+ で対応する `[START:END]` レンジ指定を一切受け付けない
  (余分なトークンを渡すと `ACK incorrect arguments`)。TODO 全項目消化済みのため
  自走エージェントが調査して新規発見・追加した項目。musicpd.org protocol と実 MPD
  (MusicPlayerDaemon/MPD を実際に clone して src/command/PlaylistCommands.cxx
  handle_listplaylist/handle_listplaylistinfo、src/playlist/Print.cxx を確認) で
  仕様を確定: 両コマンドとも MPD 0.24+ でレンジ対応、範囲がプレイリスト長を超えても
  `playlistdelete`/`playlistmove` と異なりエラーにはならず、Python の list slice と
  全く同じ「はみ出しは黙って切り詰め」の挙動。rmpc 本体 (mierak/rmpc) を実際に
  clone してソース確認したところ、`rmpc-mpd/src/mpd_client.rs` の
  `send_list_playlist_info` は `Option<SingleOrRange>` の range 引数を実際に持ち、
  `self.version() < 0.24.0` を検査した上でレンジ付きコマンドを送信するコードパスが
  存在する (現行の rmpc UI 呼び出し箇所は全て `None` 固定で未使用だが、mopidy 側は
  greeting で VERSION=0.25.0 を名乗っている以上この version gate は通過してしまう —
  バージョン表示と実装の不整合という点で mpdoneshot-patch.py 等の既存項目と同種の
  ギャップ)。
  verified: mpdplaylistinforange-patch.py。`listplaylist`/`listplaylistinfo` に
  `songrange=protocol.RANGE` (デフォルト `slice(0, None)`) を追加し、
  `playlist.tracks[songrange]` で単純にスライスするのみ (エラー化しない)。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用
  しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic 実アカウント)
  を実際に起動し、実データ(YOASOBI/Ado/米津玄師 検索結果8曲)を `findadd` で
  キューに積み `save "rangetest"` で保存の上 MPD で確認 — レンジ無し
  `listplaylist`/`listplaylistinfo`(8曲、旧来通り)、`"2:5"`→3曲目(index2-4)、
  `"6:"`(open-ended)→末尾2曲、`"0:100"`(プレイリスト長超過)→全8曲へ黙って
  クリップ(エラーにならない)、`"100:200"`(完全範囲外)→0件・OKのみ(エラーに
  ならない)、単一インデックス `"3"`→該当1曲のみ、`listplaylistinfo "rangetest"
  "1:3"`→2曲目・3曲目のフル情報(Pos/Idは元々ストアドプレイリストには付与
  されない仕様通り引き続き無し)。エラー系: `"a:b"`(非数値)/`"5:2"`(逆転レンジ)→
  `ACK incorrect arguments`、存在しないプレイリスト`"nosuchplaylist" "0:1"`→
  `ACK No such playlist`、負数`"-1:2"`→`ACK incorrect arguments`。旧来の
  `playlistdelete`/`rm`/`listplaylists`/`tagtypes`/`list album`/`search any`/
  `getvol`/`crossfade`/`status`/`listmounts`/`channels`/`stats` の回帰なしも確認。
  mopidy.log には無関係な既存事象(このYTMusicアカウントの`save`がリモート
  YTMusicプレイリスト作成もあわせて試行し401 Unauthorizedで失敗する
  `mopidy_ytmusic/playlist.py create()`起因のエラー、本パッチ範囲外・m3u側の
  save自体はOKを返しており実害なし)以外の Traceback/ERROR 0件を確認。
- [x] `protocol` (MPD 0.24+, connection settings section) が一切登録されておらず
  `ACK unknown command` になる件: TODO 全項目消化済みのため自走エージェントが実 MPD の
  完全なコマンド一覧 (mpd.readthedocs.io/protocol.html) と mopidy_mpd の登録済みコマンド
  一覧を突き合わせて新規発見・追加した項目 (`getfingerprint`(要libchromaprint、実音声解析が
  必要なため対象外)/`outputset`(対象となる実属性が無いため対象外)と合わせて3件見つかった
  未登録コマンドのうち唯一実装可能だったもの)。rmpc 本体 (mierak/rmpc) を実際に clone して
  `rmpc-mpd/src/`・`rmpc/src/` を grep したが `protocol` コマンドの送信箇所は無く、rmpc固有の
  実害ではなく decoders/mixrampdb/outputs-plugin と同種の「標準 MPD プロトコル準拠」の不備と
  確認した上で着手。
  verified: mpdprotocol-patch.py。実 MPD (MusicPlayerDaemon/MPD を実際に gh api で確認:
  src/command/ClientCommands.cxx handle_protocol、src/client/ProtocolFeature.{hxx,cxx}) を
  確認し仕様を確定 (対応FEATUREは`hide_playlists_in_root`の1種類のみ、状態は接続ごとで
  切断で破棄、応答キーは`stringnormalization`ではなく`feature`、未知sub commandや
  Not/Too many argumentsのエラー文言はmpdstringnorm-patch.pyと同型)。
  `context.session.string_normalization`と全く同じ流儀で`context.session.protocol_features`
  をセッション属性として追加、connection.pyに`protocol`コマンドを新設。効果の実装対象として
  music_db.pyの`lsinfo`がルート(`uri in (None, "", "/")`)で無条件に
  `protocol.stored_playlists.listplaylists(context)`を追記している箇所
  (docstring "This behavior is deprecated; use listplaylists instead." が実MPDの
  `hide_playlists_in_root`の説明"disables the listing of stored playlists for the lsinfo"と
  一致)を特定し、機能が有効な間はこの追記をスキップするようゲート。`listplaylists`コマンド
  自体は実MPD同様この機能の影響を受けないため無変更で維持。パッチ適用後の生成ソースは
  一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `protocol`(初期・引数無し)→空でOK、`protocol available`→`feature:
  hide_playlists_in_root`、`protocol all`→OK・以後`protocol`→`feature:
  hide_playlists_in_root`、`protocol clear`→OK・以後空、`protocol enable
  hide_playlists_in_root`→OK・反映、`protocol disable hide_playlists_in_root`→OK・以後空、
  `protocol enable bogus_feature`→`ACK Unknown protocol feature`、`protocol enable`
  (引数無し)→`ACK Not enough arguments`、`protocol bogus_sub`→`ACK Unknown sub command`、
  `protocol all`/`available`/`clear`に余分な引数→`ACK Too many arguments`。実データ
  (YOASOBI検索結果を`findadd`でキューに積み`save "protocoltest" "create"`でストアド
  プレイリスト作成)で効果を実測 — 機能無効時(既定)の`lsinfo`→`directory: YouTube
  Music`に続けて`playlist: protocoltest`(旧来動作)、`protocol enable
  hide_playlists_in_root`後の`lsinfo`→`directory: YouTube Music`のみでplaylist行が
  消える、`protocol disable`で元に戻すと再度`playlist: protocoltest`が復活、
  `listplaylists`コマンド自体は機能の有効/無効に関わらず常に`playlist: protocoltest`を
  返す(実MPD仕様通り無影響)ことを確認。状態が接続ごとであること(別TCP接続Aで`protocol
  enable hide_playlists_in_root`後、接続Bの`protocol`は空のまま独立)も2本のTCP接続で実測。
  旧来の`tagtypes`/`status`/`stringnormalization`/`listmounts`/`channels`/`list album`の
  回帰なし・mopidy.log に Traceback/ERROR 0件(既知の`save`時401、本パッチ非対象の
  pre-existing挙動、を除く)を確認。
  既知の制約: `getfingerprint {URI}` (Chromaprint音声フィンガープリント) は実MPDが
  libchromaprintでビルドされた場合のみ有効な機能で、実際の音声データをデコードして解析する
  必要があるが mopidy-ytmusic はリモートストリームURIを扱うのみでローカルな音声解析の
  仕組みを持たないため対象外のまま。`outputset {ID} {NAME} {VALUE}`はプラグイン固有の
  実行時属性を設定するコマンドだが、mopidy_mpdの出力は実体を持たない仮想出力("Mute"、
  mpdoutputplugin-patch.py参照)で設定可能な属性が存在しない(実MPDも対象属性が無い場合
  `ACK you can't set anything for that output type`相当のエラーになる)ため対象外のまま。
- [x] `mopidy_ytmusic/backend.py` の `parse_auto_playlists()` (browse `ytmusic:auto` =
  「Auto Playlists」フォルダ、既定で `auto_playlist_refresh=60`分ごとに自動更新される、
  `ytmusic:home` とは別の旧来機構) がセクション/アイテムを1件も個別ガードせず処理しており、
  1件でも構造が想定外だと更新全体が丸ごと失敗し古いキャッシュのまま固まる不具合を発見・修正:
  TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが実MPDコマンド一覧との
  再照合(getfingerprint/outputsetのみ・対象外)・rmpc本体 (mierak/rmpc) の
  `mpd_client.rs`/`rmpc-mpd/src`再照合(新規ギャップ無し)に続けて、mopidy_ytmusicの
  未監査コード(過去の監査は主にlibrary.pyのparseSearch/artistToTracks/albumToTracks系に
  集中しており、backend.pyの`parse_auto_playlists`はホーム画面刷新(home-patch.py、
  `ytmusic:home`)より前からある別経路のため見落とされていた)を洗い出して発見した項目。
  (1) `stitle = nav(car, CAROUSEL_TITLE + ["text"]).strip()` (nav()のoptional指定なし)は
  タイトル欠落カルーセルで `KeyError` を送出し、呼び出し元 `_get_auto_playlists()` の
  唯一のtry/exceptでしか捕まらないため以後の全セクションの処理を道連れに中断させ
  `self.library.ytbrowse` が一切更新されない。(2) `ititle = nav(item,
  ["musicTwoRowItemRenderer"] + TITLE_TEXT).strip()` も同様にタイトル欠落アイテムで
  `KeyError` を送出し全体を中断させる。(3) `MUSIC_PAGE_TYPE_ALBUM` 分岐の `ctype` は
  `nav(..., True)` で `None` を許容しているにもかかわらず直後で
  `ititle + " (" + ctype + ")"` と無条件に文字列結合しており、サブタイトルの1行目
  (Album/Single等の種別ラベル) を持たないアルバムで `TypeError` を送出し、これも全体を
  中断させる。(4) playlist分岐の `for st in
  item["musicTwoRowItemRenderer"]["subtitle"]["runs"]: ititle += st["text"]` は "runs"
  欠落やテキストを持たないrunで `KeyError` を送出する。
  対策: `ytautoplaylistfix-patch.py`。セクション単位・アイテム単位でそれぞれ
  try/exceptを追加し1件の不具合が他のセクション/アイテムを道連れにしないようにした
  (home-patch.pyのisinstanceガード、ytparsegaps-patch.pyのper-itemフォールバックと
  同じ「1件落ちても全体は継続する」流儀)。stitle/ititleは`nav(..., True)`化しNoneなら
  そのセクション/アイテムだけをスキップ、ctypeは`or ""`でNoneフォールバックし
  文字列結合のTypeErrorを解消した。
  verified: 実装対象の `parse_auto_playlists()` 関数本体のみをmopidy本体を一切
  importせず(GStreamer依存を避けるため)抜き出して単体exec評価する合成データテストで
  再現・修正の両方を確認 — タイトル欠落セクション1件を含む5セクション(正常/タイトル
  欠落/アイテムタイトル欠落/ctype欠落アルバム/正常)の合成データを与えたところ、
  パッチ前は1件目の正常セクションを処理し終えた後2件目のタイトル欠落セクションで
  `KeyError: 'title'` を送出し5セクション全てが失われる(戻り値0件)ことを確認、
  パッチ後は同じ入力で4/5セクションが復元され(真にタイトルを持たないセクションのみ
  スキップ)、アイテムタイトル欠落アイテムはそのアイテムだけがスキップされ
  (セクション自体は空リストで生存)、ctype欠落アルバムは`TypeError`を送出せず
  `"Some Album ()"`として復元されることを確認。さらに `nix/lib/mopidy-env.nix` に
  登録の上 `~/ai/mopidy-dev/build-run.sh` でenvを再ビルドしdev mopidy(6601、ytmusic
  実アカウント)を実際に起動 — mopidy.log に `YTMusic loaded 5 auto playlists
  sections` (実アカウントのAuto Playlists、5セクション全件成功) 、Traceback/ERROR
  0件を確認。MPDで実際に `lsinfo "YouTube Music/Auto Playlists"` → 5セクション
  (Hits throughout the decades/Starting the day/Trending community
  playlists/New releases/Charts) 列挙、`lsinfo "YouTube
  Music/Auto Playlists/New releases"` → 実アルバム/シングル/EPが
  `Artist - Title (Album)`/`(Single)`/`(EP)` 形式で正しく列挙されることを確認
  (ctype欠落フォールバックのコードパス自体は合成データテストでのみ再現、実アカウントの
  現在のホームデータには該当ケースが無かったため実機では未観測)。`lsinfo`/`status`の
  回帰なしも確認。
- [x] mpdfilterkind-patch.py が実装したフィルタ式の肯定演算子後段フィルタ
  (`_mpd_track_matches_positives`, music_db.py) が `(any contains "X")` 等
  field="any" のケースで常に0件を返す重大な回帰を発見・修正: TODO/既知の軽微な
  残課題を全項目消化済みのため自走エージェントが dev mopidy(6601, ytmusic
  実アカウント) で実際に MPD コマンドを叩いて発見した項目。
  `search any "BTS"` (旧来構文、post-filter 無し) は実データ (例:
  "NORMAL (Korean Ver.) (Explicit Ver.)"というTitleのみでArtistタグが空のTrack)
  を正しく返すのに対し、`search "(any contains \"BTS\")"` (フィルタ式、
  mpdfilterkind-patch.py 適用後) は全く同じ実データに対し常に0件になることを
  確認した。原因: mopidy-ytmusic backend の library.search() は field="any" の
  とき YouTube Music の関連度検索 (`filter=None`、リテラルなタグ一致ではなく
  緩い関連度マッチ) に丸投げしており、返ってくる Track の露出タグ (parseSearch()
  の一部経路で artists が空になることがある) が検索語を文字列として含まない
  場合が普通にある。`_mpd_track_matches_positives` は field="any" についても
  他の具体的タグ (Artist/Title等) と全く同じ「全タグ値の文字列一致」判定を適用
  するため、backend が正しく返した関連候補を後段フィルタが機械的に弾いていた。
  `(Artist contains "X")` 等の具体的タグでは backend 自体がタグ一致する候補
  だけを返す (`filter="artists"` 等) ため同じ問題は起きず、mpdfilterkind-patch.py
  自身の実機検証 (YOASOBI、Artist/Title固有フィールドのみ) では any 未検証
  だったため見落とされていた。rmpc本体の `Tag::Any` (rmpc-mpd/src/filter.rs、
  検索ペインの既定フィールド) は誰でも到達する最も基本的な検索操作であり、
  実害は「検索ペインでデフォルトのまま何か検索すると常に0件になる」。
  verified: mpdanyfilter-patch.py。field="any" の positives 条件だけは後段
  フィルタを適用せず常に合格させる (backend の関連度マッチを信頼、
  `search any "X"` と同じ挙動へ復帰) よう `_mpd_track_matches_positives` を
  修正。パッチ適用後のソースは一時コピーに当てて `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix` に
  mpdfilterkind-patch.py の直後として登録の上 `~/ai/mopidy-dev/build-run.sh` で
  env を再ビルドしdev mopidy(6601、ytmusic実アカウント)を実際に起動 — 修正後
  `search "(any contains \"BTS\")"` / `find "(any contains \"BTS\")"` /
  `search "(any contains \"夜\")"` / `search "(any == \"BTS\")"` が正しく実
  トラックを返すことを確認、`count "(any contains \"BTS\")"` → songs:2
  (findadd→playlistinfo→play 0→statusで実際に再生しstate=play/audio:
  48000:16:2まで確認、end-to-endで動作)。回帰確認: `find "(Artist ==
  \"YOASOBI\")"`（具体的タグのexact、22件中アルバム疑似トラック含め従来通り）、
  `find "(Artist starts_with \"YOASOBI\")"`（22件）、`find "(Artist
  starts_with \"ASOBI\")"`（前方一致でないので0件のはず→0件で正しく空）、
  `find "(Artist != \"YOASOBI\")"`（positiveな条件皆無、既存の`ACK incorrect
  arguments`のまま）、`search any "yoasobi"`（旧来構文）、`list Album group
  AlbumArtist`、`sticker get`（no such sticker応答）、`tagtypes`、`status`の
  回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `sticker` コマンドが実装済み (mpdsticker-patch.py 以下一連のパッチで
  get/set/delete/list/find + inc/dec + idle通知まで完備) にもかかわらず、
  `commands` (reflection) の応答に一切現れず、rmpc からは常に「サーバは
  sticker 非対応」と誤認識される不具合を発見・修正: TODO/既知の軽微な残課題を
  全項目消化済みのため自走エージェントが実際に dev mopidy へ `commands` を
  送って全コマンドの一覧を洗い出す中で発見した。原因: `mopidy_mpd/protocol/
  stickers.py` の `sticker` ハンドラ登録は元々 `raise exceptions.
  MpdNotImplemented` のスタブだった名残で `@protocol.commands.add("sticker",
  list_command=False)` のまま(未実装コマンドを reflection から隠す実 MPD 風の
  規約、`config`/`kill`/`command_list_begin`等と同種)登録されており、
  mpdsticker-patch.py がハンドラ本体を全機能実装に置き換えた際にこの
  `list_command=False` だけ変更されずに残っていた。`list_command` は
  reflection.py の `commands()` がその名前を返すかどうかのフラグで、
  `False` だと実装済みでも一覧に出てこない。rmpc本体
  (rmpc/src/ctx.rs `Ctx::try_new`) はまさにこの `commands` 応答に
  `"sticker"` が含まれるかだけで `StickersSupport::Supported`/`Unsupported`
  を判定し、`Unsupported` と判定すると以後一切 sticker コマンドを送らない
  ため、曲への評価(レーティング、rmpc/src/ui/mod.rs の `RATING_STICKER`)
  機能が実装済みにもかかわらず rmpc 側から永久に使われないという実害がある。
  対策: `mpdstickerreflect-patch.py`。`list_command=False` を外し(デフォルトの
  `True` に戻し)、実装状態通り `commands` に `sticker` を含めるようにした。
  verified: パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文
  確認、2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`
  の mpdPatched リスト末尾に登録の上 `~/ai/mopidy-dev/build-run.sh` で env を
  再ビルドしdev mopidy(6601、ytmusic実アカウント)を実際に起動 — 修正前は
  `commands` の応答に `sticker` が0件だったのに対し、修正後は
  `command: sticker` が1件含まれることを確認。`sticker set song
  "ytmusic:track:..." rating "5"` → OK、`sticker get`/`sticker list`/
  `sticker find` がいずれも `rating=5` を正しく返す、`sticker delete` 後に
  `sticker get` → `ACK no such sticker` と、実データでset/get/list/find/
  delete の一連が正常動作することも確認。回帰確認: `search any "yoasobi"`、
  `list Album group AlbumArtist`、`listplaylists`、`tagtypes`、`status`の
  回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic.library.py` の `parseSearch()` の artist 分岐が、YTMusic の
  "Top result" カード (よく知られたアーティスト名と厳密一致する検索でリスト先頭に
  付与される特別な結果) を処理する際、二次的な `KeyError` でエラーメッセージ自体が
  失敗し本当の原因を隠したまま結果を失う不具合を発見・修正: TODO/既知の軽微な残課題を
  全項目消化済みのため自走エージェントが mopidy.log を監視する中で
  `YTMusic: skipping unparseable search result ('artist')` という警告 (ytparsegaps-patch.py
  が追加した parseSearch() 最外周の per-item try/except による最終フォールバック) を
  発見し、ytmusicapi のソース (`parsers/search.py` の `parse_top_result()`) を確認して
  原因を特定した。通常の "Artists" カテゴリの検索結果は `artist` (単数、アーティスト名
  文字列) と `browseId` キーを持つが、"Top result" カードが `resultType=="artist"` の
  場合は `parse_top_result()` が `browseId` を一切設定せず、`artist` の代わりに
  `parse_song_runs()` が返す `artists` (複数形、dict のリスト) キーを持つ全く異なる
  形の dict を返す。parseSearch() の artist 分岐は両キーが常に存在する前提で
  `field == "artist" and ... result["artist"] ...` (exact match 判定) と
  `self.backend.api.get_artist(result["browseId"])` にアクセスしており、後者は
  外側の try で保護されているものの、その except 節自身が
  `logger.exception(..., result["artist"])` で同じ `KeyError` をもう一度送出して
  しまう (albums 取得失敗時の `logger.warning(..., result["artist"])` も同様) ため、
  本当の原因 (browseId 欠落) ではなく二次的な `KeyError` がログに残り診断を妨げたまま
  ytparsegaps-patch.py の最外周 per-item except まで伝播していた。機能上はその1件が
  静かにスキップされるだけで search 全体やプロセスは落ちないが、Top result カードとして
  返ってきたアーティスト (検索語ともっとも確からしく一致する候補) が常に失われる実害が
  ある。
  verified: yttopresultartist-patch.py。artist 分岐の先頭で `browseId` 欠落を検知し
  早期に `continue` でスキップするよう変更、あわせて例外ハンドラ2箇所の
  `result["artist"]` を `result.get("artist", result.get("browseId", "?"))` に変更した。
  パッチ適用後のソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても
  冪等(スキップ)であることも確認。ytmusicapi/mopidy への依存を最小化した合成データ
  テスト (`YTMusicLibraryProvider.parseSearch()` を実際にインスタンス化し、
  `browseId` 無し・`artists`(複数)キーのみを持つ Top result カード相当の synthetic
  dict を含む2件の検索結果を与える) で再現・修正の両方を確認 — パッチ前の
  `library.py` (旧 store path) では同じ入力に対し `YTMusic: skipping unparseable
  search result ('artist')` の警告 (二次的な KeyError によるマスキング) が出た上で
  Top result カードの1件を失うのに対し、パッチ後は同じ入力で警告なしに静かに
  Top result カードをスキップし、通常カテゴリの正常な entry (browseId/artist 両キー
  あり) から `Artist(name="BTS")` を正しく1件復元することを確認した。さらに
  `nix/lib/mopidy-env.nix` に登録の上 `~/ai/mopidy-dev/build-run.sh` で env を
  再ビルドしdev mopidy(6601、ytmusic実アカウント)を実際に起動 — mopidy がクリーンに
  起動 (Traceback/ERROR 0件) することを確認した上で `find artist "BTS"` を実際に
  MPD で叩き、実データ (Mental Medicine/ARIRANG 等の実アルバム/曲) を正しく返す
  ことを確認 (mopidy.log にも `skipping unparseable search result` は出ず、
  想定通り既存の `get_artist_albums` フォールバック警告のみ)。回帰確認:
  `search any "yoasobi"`、`list Album group AlbumArtist`、`tagtypes`、`status`、
  `commands`(sticker含む全一覧)の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic.library.py` の `browse()` `ytmusic:mood:<params>:<browseId>`
  (Mood and Genre Playlists の各カテゴリページ、例:「Feel good」「Enkakayokyoku」) が
  セクション内のタイルを無条件に「musicTwoRowItemRenderer = プレイリスト/アルバムタイル
  (browseEndpoint持ち)」と決め打ちして browseId を nav() で取り出す不具合を発見・修正:
  TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが前回セッションの
  未コミット作業 (configs/media/mopidy/ytmoodgenre-patch.py、nix未登録・未検証のまま
  残っていたファイル) を引き継ぎ、実機 (dev mopidy 6601, ytmusic 実アカウント) で
  `lsinfo "YouTube Music/Mood and Genre Playlists/<カテゴリ>"` を全37カテゴリ実際に
  叩いて特定した。一部カテゴリ (例: Enkakayokyoku=演歌・懐メロ) は
  musicTwoRowItemRenderer タイルがプレイリストではなく「単曲のミュージックビデオ」を
  指しており、`navigationEndpoint: {watchEndpoint: {videoId: ...}}` のみを持ち
  `navigationEndpoint: {browseEndpoint: {browseId: ...}}` が存在しない(実データ例:
  videoId=DHbIIBmqHsw「ジンギスカン」、videoId=PC_oQmjcxLo「木綿のハンカチーフ」)。
  前段の実装は NAVIGATION_BROWSE_ID を無条件 nav() で取得しKeyErrorを送出し、
  1アイテム分の処理が for ループ全体を包む唯一の try/except の中にあるため、この
  1件のKeyErrorでそのカテゴリページの全セクション・全アイテムが道連れになり空リストに
  なっていた(ytparsegaps-patch等と同種の「1件の異常が全体を道連れにする」パターン)。
  別途 musicResponsiveListItemRenderer (個々の楽曲のlist item) を混在させるカテゴリも
  あり、これも既存の ythistory-patch/ytliked-patch と同じ流儀で対応が必要だった。
  verified: ytmoodgenre-patch.py。musicTwoRowItemRenderer タイルは browseId があれば
  従来通り Ref.playlist、無く videoId (NAVIGATION_VIDEO_ID) があれば単曲として
  Ref.track、musicResponsiveListItemRenderer は parse_playlist_items() で Ref.track、
  どれにも該当しない/パース失敗時は1件だけ warning ログで読み飛ばし残りを継続する
  よう修正。パッチ適用後のソースは一時コピーに当てて `ast.parse` で構文確認、2回適用
  しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix` の
  ytmusicPatched リスト末尾に登録の上 `~/ai/mopidy-dev/build-run.sh` で env を
  再ビルドしdev mopidy(6601、ytmusic実アカウント)を実際に起動 —
  修正前は問題のカテゴリで該当アイテムが `keys=['musicTwoRowItemRenderer']` の
  警告と共に欠落する動作を(調査用の一時的なDEBUGDUMPログ付きビルドで)実データ込みで
  確認した上で、修正後は同じカテゴリで該当2曲 (Dschinghis Khan / 木綿のハンカチーフ)
  が `file:`/Artist/Title 付きで正しく返り、他のプレイリストタイルとも混在した状態で
  クラッシュせず `OK` で完了することを確認。全37カテゴリ (African〜Workout) を実際に
  `lsinfo` で叩き、mopidy.log に `unparseable mood`・`Traceback`・`ERROR` が
  1件も出ないことも確認。回帰確認: `search any "yoasobi"`、
  `list Album group AlbumArtist`、`tagtypes`、`status`、`listplaylists`、
  `commands`(sticker含む)の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic.library.py` の `playlistToTracks()`/`uploadArtistToTracks()`/
  `albumToTracks()`/`uploadAlbumToTracks()` (プレイリスト・アルバム・アップロード楽曲を
  Track へ変換する4つの中核関数) が1曲もガードせず処理しており、削除/非公開/地域制限
  された「再生不能曲」を安全に扱えない不具合を発見・修正: TODO/既知の軽微な残課題を
  全項目消化済みのため自走エージェントが、既存の監査が主にbrowse()のセクション/
  アイテム単位ガード(ytautoplaylistfix-patch.py/ytmoodgenre-patch.py)や検索経路
  (parseSearch系)に集中しており、実際に曲データをTrackへ変換する4関数自体の中身は
  1曲単位でガードされていないことに気づいて調査した項目。ytmusicapi
  (`parsers/playlists.py` parse_playlist_items()) は削除/非公開/地域制限で再生不能に
  なった楽曲を `"videoId": None`(`isAvailable: False`)として返す。4関数はいずれも
  `track["videoId"] not in self.TRACKS` を無条件キャッシュキーに使うため実害が2つある:
  (1) 再生不能曲がそのまま `uri="ytmusic:track:None"` という無効なURIのTrackとして
  結果に混入する。(2) より深刻なのは `self.TRACKS` が `YTMusicLibraryProvider`
  インスタンスの寿命全体(mopidyプロセスの生存期間)で共有されるキャッシュであること:
  最初に遭遇した再生不能曲のタイトル・アーティストが `self.TRACKS[None]` に一度
  キャッシュされると、その後まったく別のプレイリスト/アルバムに含まれる別の
  (タイトルの異なる)再生不能曲であっても `None not in self.TRACKS` が False になり、
  最初の1件のタイトルに化けたまま表示され続ける(データ破損)。さらに(3)
  "title" 等の想定キーを欠く1曲がある場合、その関数呼び出し全体が `KeyError` で
  失敗し、呼び出し元のtry/except(browse()側)経由でプレイリスト/アルバム全体が
  0曲になる(ytautoplaylistfix-patch.py/ytmoodgenre-patch.pyと同じ「1件の異常が
  全体を道連れにする」パターン)。
  verified: ytunavailabletrack-patch.py。4関数とも先頭で `videoId` が無い(再生不能)
  曲は `self.TRACKS` を汚染する前にスキップし、あわせて1曲単位の try/except で
  残りの曲の処理を継続するよう修正(ytautoplaylistfix-patch.pyと同じ「1件落ちても
  全体は継続する」流儀)。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse`
  で構文確認、2回適用しても冪等(スキップ)であることも確認。合成データによる
  再現・修正の両方の単体テスト(`YTMusicLibraryProvider` を実際にインスタンス化し、
  mopidy/ytmusicapiへの依存を最小化した状態で各関数を直接呼び出し)を実施 —
  パッチ前の`library.py`(旧 store path)では: `playlistToTracks()` に
  タイトルの異なる2件の再生不能曲(videoId=None)を含む5曲を与えると5曲すべてが
  返り、うち2件の`uri='ytmusic:track:None'`エントリが両方とも**1件目**の
  タイトル("Unavailable Track A")のまま返る(2件目の実際のタイトルが失われる
  データ破損を再現)ことを確認。また`albumToTracks()`でも同様に`videoId=None`の曲が
  `uri='ytmusic:track:None'`のTrackとして混入することを確認。さらに`title`キーを
  欠く1曲を含む`playlistToTracks()`呼び出しが`KeyError: 'title'`で全体クラッシュ
  することも確認。パッチ後は同じ入力に対し: `playlistToTracks()`が再生不能曲2件を
  正しくスキップし残り3件の実曲のみ(正しいタイトルで)を返す、`albumToTracks()`が
  再生不能曲をスキップしつつ残り2曲の`track_no`(1と3、元の並び順)を正しく維持する、
  title欠落曲を含む`playlistToTracks()`がクラッシュせず残り2曲を返す、
  `uploadArtistToTracks()`/`uploadAlbumToTracks()`も同様に再生不能曲をスキップして
  残りの実曲のみ返すことを確認。`nix/lib/mopidy-env.nix`のytmusicPatchedリスト末尾に
  登録の上 `~/ai/mopidy-dev/build-run.sh` でenvを再ビルドしdev mopidy(6601、ytmusic
  実アカウント)を実際に起動 — クリーンに起動(Traceback/ERROR 0件)することを確認した
  上でMPDで実際に`search any "yoasobi"`(18行)、実アカウントの実データ(200曲規模の
  Auto Playlists内プレイリスト複数、12曲規模のアルバム含む)を`lsinfo`で実際に
  ブラウズし正しく曲が返ることを確認(このアカウントの現在のカタログには
  たまたまvideoId=None曲が含まれていなかったため実機ではガード自体の発火は
  未観測、合成データテストで再現・修正を確認済み)。回帰確認: `search any "yoasobi"`、
  `list Album group AlbumArtist`、`tagtypes`、`status`、`listplaylists`、
  `commands`(sticker含む)の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic/playlist.py` の `YTMusicPlaylistsProvider.save()`/`_reorder_playlist()`
  (ytplaylistreorder-patch.py 適用後の版) が、同一 videoId がプレイリスト内に複数回
  出現するケース (実 MPD の m3u ストアドプレイリストは同一 URI の重複を普通に許容する)
  を正しく扱えない不具合を発見・修正: TODO/既知の軽微な残課題を全項目消化済みのため
  自走エージェントが、既存の監査が主にライブラリ側の変換関数 (playlistToTracks 等) や
  browse() 経路に集中しており、プレイリスト**書き込み**経路 (save()) 自体の重複曲
  ハンドリングは未調査だったことに気づいて調査した項目。実害は2つ: (1) `oldIds`/
  `newIds`/`common`/`remove`/`add` がいずれも `set()` (多重度なし) で計算されるため、
  `playlistadd` で同じ URI をもう一度追加する等して目的の並びに同じ videoId が
  2回現れても `newIds = set(newOrder)` の時点で1回に潰れ、2件目ぶんの
  `add_playlist_items()` が呼ばれず曲が黙って欠落する (逆に既存側の重複を減らしたい
  場合も余分なコピーが `remove` に入らず残り続ける)。(2) より深刻なのは、そのケースが
  発生しなくても `_reorder_playlist()` に渡る目的順序に同じ videoId が複数あると
  `setVideoIdByVideoId` (videoId→setVideoId の単純dict) が区別できず、既存の
  `any(svid is None ...)` ガードをすり抜けてしまい、`working.remove(a)` (a=b=同じ
  videoId) 直後の `working.index(b)` が未捕捉の `ValueError` を送出して `save()`
  全体がクラッシュする (ytplaylistreorder-patch.py 自身のコメントは「同一videoIdが
  複数箇所にあるプレイリストは並べ替えも対象外のまま」と意図を明記していたが、
  実装 [None チェックのみ] がその意図を満たせていなかった)。mopidy core 側はこの
  例外を飲み込んで `playlistadd` を `ACK [11@0] {playlistadd} Not able to add ...`
  として返すため、クライアントには「何も保存されなかった」ように見えるが、実際には
  クラッシュ直前に無意味な `edit_playlist(moveItem=...)` 呼び出しがYouTube Music側に
  対して実行されてしまっている不整合も生じる。
  verified: ytplaylistdup-patch.py。`oldIds`/`newIds` を `collections.Counter`
  (多重集合) に変更し実際の個数差分ぶんだけ remove/add するよう修正、削除対象は
  `pls["tracks"]` を先頭から見て必要数だけ選ぶことで特定の1件だけを正しく除去できる
  ようにした。`_reorder_playlist()` には目的順序 (newOrder) に重複 videoId があれば
  (setVideoId で一意に対象を特定できないため) 並べ替えを丸ごとスキップするガードを
  追加 (add/remove 自体は既に実行済みなので曲の過不足は正しく反映される)。パッチ適用後の
  生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)
  であることも確認。`mopidy_ytmusic.playlist.YTMusicPlaylistsProvider` を実際に
  インスタンス化し `backend.api` (ytmusicapi クライアント相当) をモックした単体テストを
  パッチ前後の両方のソースで実施 — パッチ前: 既存1曲のプレイリストへ同じ videoId を
  含む目的順序 `[V1, V1]` で `save()` を呼ぶと `ValueError: 'V1' is not in list` で
  実際にクラッシュすることを確認 (不具合の再現)。パッチ後は同じ入力に対し:
  クラッシュせず `add_playlist_items('PLID', ['V1'])` が正しく呼ばれ2件目が追加される、
  既存2件(同一videoId)→目的1件のケースで `remove_playlist_items` が過不足なく1件だけ
  除去される、目的順序に重複videoIdがある3曲(V2,V1,V1)のケースで `edit_playlist(
  moveItem=...)` が一切呼ばれず(reorderが安全にスキップされる)クラッシュもしない、
  重複なしの通常ケース(既存A,B→目的C,B,A)は従来通り add + 複数回の `moveItem`
  呼び出しで正しく並べ替えられる(回帰なし)ことを確認。`nix/lib/mopidy-env.nix`の
  ytmusicPatchedリスト末尾に登録の上 `~/ai/mopidy-dev/build-run.sh` でenvを再ビルドし
  dev mopidy(6601、ytmusic実アカウント)を実際に起動 — クリーンに起動
  (Traceback/ERROR 0件)することを確認した上で、ビルド済みenv内の実ファイルに
  `Counter`/重複ガードのコードが実際に反映されていることをソース確認。MPDで実際に
  `status`/`search any "yoasobi"`/`listplaylists`/`tagtypes`/`list Album group
  AlbumArtist` を叩き回帰なし・mopidy.log に Traceback/ERROR 0件を確認(実アカウントの
  プレイリストへの書き込みは「実アカウントを変更する破壊的操作はスコープ外」の既存方針
  [プレイリスト編集系項目 verified 参照] に従い実施せず、モック単体テストで再現・修正の
  両方を確認する方式を採用)。
- [x] `add {URI} POSITION` / `load {NAME} RANGE POSITION` (mpdaddpos-patch.py/mpdloadpos-patch.py)
  の位置解決に、`prio`/`prioid` (mpdprio-patch.py で修正済み) と同種の TOCTOU レースが
  残っていた件: 「まず末尾へ追加してから `[追加前の長さ, 追加後の長さ)` という長さの
  差分レンジを move する」実装が、`get_length()` → `add()` → `get_length()` → `move()`
  という4回の別々の非同期 core 呼び出しに分解されており、この間に別クライアントが
  `add`/`delete` 等でキューの長さを変えると、差分レンジがもはや「自分が追加した曲」と
  一致せず無関係な曲を巻き込んで move してしまいキュー順序が静かに破損する不具合。
  TODO 全項目消化済みのため自走エージェントが調査して新規発見・追加した項目。rmpc 本体
  (mierak/rmpc) を実際に clone してソース確認したところ、rmpc/src/config/keys/actions.rs
  の `Position::AfterCurrentSong`/`BeforeCurrentSong` (キーバインド可能な「現在の曲の次/前に
  追加」) が `QueuePosition::RelativeAdd(0)`/`RelativeSub(0)` を生成し、
  rmpc-mpd/src/mpd_client.rs の send_add (559-562行) が `add URI +0`/`-0`、
  send_load_playlist (738-742行) が `load NAME 0: +0` を実際に送信する(日常的に使う
  操作)と確認した上で着手。
  verified: mpdaddloadrace-patch.py。同じファイル内の `addid` (mpdaddid-patch.py) は
  元からこのレースが無いことに着目: `context.core.tracklist.add(uris=[uri],
  at_position=at_position)` を1回呼ぶだけで、mopidy core の tracklist.add() 自体が
  at_position 引数で複数曲の直接挿入をサポートしている (mopidy/core/tracklist.py
  Tracklist.add、ループ内で `at_position` をインクリメントしながら `insert` するため
  複数曲でも順序が保たれる) と確認。`add`/`load` を「末尾追加+move」ではなく addid と
  同じ「解決済みの position を `at_position` としてそのまま `tracklist.add()` へ渡す」
  流儀に統一するよう current_playlist.py の `add()` と stored_playlists.py の `load()`
  を修正 (最終的な曲順は従来の「末尾追加+range move」と数学的に同一だが、1回の
  atomic な core 呼び出しに収まるためレース自体が構造的に発生しなくなる)。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても
  冪等(スキップ)であることも確認。パッチ済み env の dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し MPD で実データ(YOASOBI楽曲)で確認 — 絶対位置
  `add URI "1"`(3曲キューの中間へ挿入)→正しく挿入され後続曲がシフト、3曲キュー+
  `play "1"`(pos1を実際に再生開始、`status`のstate:play/song:1/songidで確認)の状態で
  `add URI "+0"`→現在曲の直後に挿入、`add URI "-0"`→現在曲の直前に挿入され現在曲の
  position が1つ後ろにシフト(songidは不変=同じ曲が再生継続していることを実際に確認)、
  境界値超過 `+999`→`ACK Number too large`、絶対位置の範囲外 `999`→
  `ACK Bad song index`、非数値 `abc`→`ACK incorrect arguments`(全て既存の引数検証の
  まま回帰なし)。`load NAME "0:" "+0"`(現在曲再生中に2曲ロード)→現在曲の直後に
  正しく挿入されsongid不変・`status`のlastloadedplaylistも追従。**TOCTOUレース自体の
  検証**: 4スレッドで `add URI "+0"` を連打しつつ、別4スレッドで同時に
  `add`(位置指定なし・末尾追加)+`delete "0"` によるキュー長の変動を8秒間並行実行する
  ストレステストを実施 — 修正後は接続断・ACK異常0件、最終的な `playlistinfo` の
  Pos が 0..142 の連番で重複・欠落なし(143曲、キュー整合性を実際に確認)、
  mopidy.log に Traceback/ERROR 0件(このレース条件を再現する構成で検証)。旧来の
  `tagtypes`/`status`/`count any`/`search any sort+window併用`/`list album`/
  `addid`(POSITION付き含む)/`playlistinfo`の回帰なしも確認。
- [x] `move`/`shuffle`/`swap` (raw position/range指定、tlid経由の`moveid`/`swapid`は対象外)
  が範囲外の POS/START:END を渡されても、実際には何もせず `OK` を返してしまう不具合。
  TODO 全項目消化済みのため自走エージェントが調査して新規発見・追加した項目。原因:
  これらのハンドラは `context.core.tracklist.move(...)`/`shuffle(...)` の戻り値
  (pykka Future) に一度も `.get()` を呼んでおらず (mopidy-mpd 本家からしてこの書き方)、
  mopidy core 側の `move()`/`shuffle()` が範囲外 start/end/to_position に対し投げる
  裸の `AssertionError` が `.get()` されないため誰にも再送出されずに握り潰され、
  `mopidy_mpd/dispatcher.py` の `_catch_mpd_ack_errors_filter` (`MpdAckError` のみ捕捉)
  にも引っかからず mopidy.log にすら記録されないと判明。実際に dev mopidy(6601,
  ytmusic 実アカウント) の2曲キューに対し `move "99" "0"` / `swap "0" "99"` /
  `shuffle "0:99"` を送って先に不具合を再現確認 — 全て `OK` が返るが `playlistinfo`
  のPos/Id/曲順は一切変化せず、mopidy.log にも AssertionError 等の記録が一切
  無いことを確認した上で着手。
  verified: mpdmoveswaprace-patch.py。current_playlist.py の `move_range`/`moveid`/
  `shuffle`/`swap` の該当 `context.core.tracklist.move/shuffle(...)` 呼び出しに
  `.get()` を追加して実行を同期化し、`AssertionError` を実 MPD 同様の
  `ACK ... Bad song index` (`delete()` と同じ文言) へ変換。`swap` は追加で2回の
  `move()` 前に `get_length()` で範囲チェックし (`songpos1 == songpos2` は実害の
  無い自分自身へのswapとしてno-op扱い)、`moveid`/`swapid` も同じ `.get()`+変換を
  適用 (tlid経由で位置は常に実在するため通常は無害だが、将来のレース耐性のため
  同じ流儀に統一)。`command` は明示指定せず `dispatcher._call_handler` の
  `exc.command is None` 時の自動補完 (実際にクライアントが送ったコマンド名を採用)
  に委ねる。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。パッチ済み env の dev
  mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で実データ(YOASOBI楽曲)
  2曲キューで確認 — `move "99" "0"`(範囲外の単一位置)→
  `ACK [2@0] {move} Bad song index`・`playlistinfo`の曲順/Pos/Id変化なし、
  `move "5:10" "0"`(範囲外の明示レンジ)→同エラー・回帰なし、
  `move "0" "1"`(有効な範囲)→`OK`・実際に順序が入れ替わることを確認、
  `swap "0" "99"`(範囲外)→`ACK [2@0] {swap} Bad song index`・変化なし、
  `swap "0" "0"`(自分自身)→`OK`・無害なno-op、`swap "0" "1"`(有効)→`OK`・
  実際に入れ替わる、`shuffle "0:99"`(範囲外)→`ACK [2@0] {shuffle} Bad song index`・
  変化なし、`shuffle "0:2"`(有効)→`OK`。既存動作の回帰なし確認: `play "1"`で
  現在曲をセットした状態で`move "1" "+0"`(現在曲を自分自身基準で移動)→従来通り
  `ACK [2@0] {move} Cannot move current song relative to itself`、実在しないid
  `moveid "999" "0"`→従来通り`ACK [50@0] {moveid} No such song`、実在するidでの
  `moveid`/`swapid`→従来通り`OK`で正しく移動/交換。`tagtypes`/`search
  any sort+window併用`/`list album`/`count any`/`listplaylists`/`status`/`stats`
  の回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `findadd`/`searchadd` (mpdfindaddpos-patch.py) の POSITION 解決に、直前の
  `add`/`load` (mpdaddloadrace-patch.py で修正済み) と全く同種の TOCTOU レースに加え、
  それ以上に悪い「`tracklist.move()` の戻り値(pykka Future)に一度も `.get()` を
  呼んでいない」不備が残っていた件。TODO 全項目消化済みのため自走エージェントが
  調査して新規発見・追加した項目。原因: mpdfindaddpos-patch.py の実装は「まず末尾へ
  追加してから `[追加前の長さ, 追加後の長さ)` の差分レンジを move する」という、
  add/load が既に置き換えた旧アルゴリズムのままだった (`get_length()` → `add()` →
  `get_length()` → `move()` の4回の別々の非同期 core 呼び出しに分解されており、
  別クライアントが間にキュー長を変えると無関係な曲を巻き込んで move する)。さらに
  add/load の旧実装は少なくとも `move(...).get()` を呼んでいたのに対し、findadd/
  searchadd は `context.core.tracklist.move(old_size, new_size, position)` の
  戻り値を一度も `.get()` していないと判明 (mpdmoveswaprace-patch.py が
  `move`/`shuffle`/`swap` で修正したのと同じ「`AssertionError` が
  `_catch_mpd_ack_errors_filter` にも引っかからず握り潰される」不具合が、範囲外
  position 指定という滅多に起きない条件だけでなく通常のレース条件でも発生しうる
  状態だった)。rmpc 本体 (mierak/rmpc) を実際に clone してソース確認したところ、
  rmpc/src/shared/mpd_client_ext.rs の `enqueue_multiple` が
  `Position::AfterCurrentSong`/`BeforeCurrentSong` から
  `QueuePosition::RelativeAdd(0)`/`RelativeSub(0)` を生成し、検索結果ペインでの
  「現在の曲の次/前に追加」操作 (日常的に使う操作) で `send_find_add` 経由
  `findadd "(FILTER)" position "+0"` を実際に送信すると確認した上で着手
  (mpdfindaddpos-patch.py 自身のコメントで既に確認済みの到達経路と同一)。
  verified: mpdfindaddrace-patch.py。mpdaddloadrace-patch.py と全く同じ方針で、
  `_mpd_resolve_addpos_position` による位置解決を `tracklist.add()` 呼び出しの前に
  移動し、末尾追加+move の2段階ではなく `context.core.tracklist.add(uris=[...],
  at_position=position).get()` の1回の atomic 呼び出しに統一 (findadd/searchadd
  両方の同一ブロックを1回の置換で修正)。mopidy core の `Tracklist.add()` 実装を
  実際にソース確認し、`uris=[]`(検索結果0件)で `at_position` が非Noneでも
  `for track in tracks:` ループが空回りするだけで例外にならず安全なことも確認済み。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても
  冪等(スキップ)であることも確認。パッチ済み env の dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し MPD で実データ(YOASOBI検索結果)で確認 —
  2曲キュー+`play "1"`(pos1を実際に再生開始、`status`のstate:play/song:1/songidで確認)
  の状態で `findadd "(any contains \"YOASOBI\")" position "+0"` → 検索ヒット曲が
  現在曲の直後に正しく挿入され後続曲がシフト(従来の位置無視バグが解消)、
  `searchadd "(any contains \"yoasobi\")" position "-0"` → 現在曲の直前に挿入され
  現在曲の position が1つ後ろにシフト(songid不変=同じ曲が再生継続していることを確認)、
  絶対位置 `findadd "(any contains \"yoasobi\")" position "1"` → 該当位置に正しく挿入、
  境界値超過 `position "+999"` → `ACK Number too large`、キューが空(現在曲なし)での
  相対指定 `position "+0"` → `ACK No current song`、`sort`/`window` 修飾との併用
  (`findadd "(any contains \"yoasobi\")" sort -Date window "0:2" position "0"`) も
  正しく絞り込み・ソート・ページング後に指定位置へ挿入、検索結果0件のフィルタに
  `position "+0"` を付けても例外にならず何も追加されずOK。**TOCTOUレース自体の
  検証**: 4スレッドで `findadd "(any contains \"yoasobi\")" position "+0"` を連打
  しつつ、別4スレッドで同時に `add`(末尾追加)+`delete "0"` によるキュー長変動を
  8秒間並行実行するストレステストを実施 — 修正後は接続断・ACK異常0件、mopidy.log に
  Traceback/ERROR 0件 (このレース条件を再現する構成で検証)。旧来の `tagtypes`/
  `status`/`count any`/`search any sort+window併用`/`list album`/`addid`(POSITION
  付き含む)/`add`/`load`(POSITION付き含む)/`playlistinfo` の回帰なしも確認。
- [x] `moveid`/`swapid` (current_playlist.py、tlid経由の move/swap 系統) に残っていた
  TOCTOUレース。mpdmoveswaprace-patch.py は raw position/range 系統
  (move/shuffle/swap) の「範囲外指定がサイレントにOKを返す」不具合を修正した際、
  その docstring コメントで「moveid/swapidはtlid経由で常に実在する位置しか渡らない
  ため元々無害」と結論していたが、これは同時実行下では誤りだった。TODO 全項目
  消化済みのため自走エージェントが、直近の一連の TOCTOU 修正 (prio/add・load/
  findadd・searchadd/delete) と同種のパターンが他にも残っていないか
  `context.core.tracklist.*` の全呼び出しを洗い出す形で調査し新規発見・追加した
  項目。原因: moveid/swapid は tlid→position の解決を
  `tl_tracks = context.core.tracklist.filter({"tlid": [tlid]}).get()` →
  `position = context.core.tracklist.index(tl_tracks[0]).get()` という2段階の
  別々の core 呼び出しで行っていた。mopidy/core/tracklist.py の `index(tl_track)`
  を実際にソース確認したところ、渡された TlTrack が現在の tracklist に存在しなければ
  `ValueError` を握り潰して `None` を返す実装 (`_tl_tracks.index(tl_track)` の
  `except ValueError: pass` の後 `return None`) と判明。つまり呼び出し1と呼び出し2
  の間に別クライアントが `deleteid`/`delete`/`clear` 等で当該 tlid をキューから
  除去すると `position` が `None` になり、moveid は直後の `position + 1` で
  `TypeError: unsupported operand type(s) for +: 'NoneType' and 'int'`、swapid は
  `swap(context, position1, position2)` 内の `songpos1 >= length` 評価で
  `TypeError: '>=' not supported between instances of 'NoneType' and 'int'` を
  発生させる。この例外は `exceptions.MpdAckError` ではないため
  `dispatcher._catch_mpd_ack_errors_filter` に捕捉されず、pykka の
  `MpdSession` アクターの `_actor_loop_running` まで伝播して
  `_handle_failure`(`logger.error("Unhandled exception in ...")`)が呼ばれ
  アクター(=MPDセッション)が停止しクライアントの接続が切断される (prio の
  `IndexError`・findadd/searchadd や add/load の位置解決レースと同種の実害)。
  mpdprio-patch.py 自身のコメントで既に確認済みの通り、rmpc (mierak/rmpc) は
  prio/prioid を一切送信しない一方 moveid/swapid は実際に送信するため到達可能。
  verified: mpdmoveidrace-patch.py。`filter()`→`index(tl_track)` の2段階を、
  mopidy core が用意する `tracklist.index(tlid=...)` (tlid直接指定、1回の
  core呼び出しで完結しfilter不要) へ置き換え、戻り値が `None` の場合を明示
  チェックして `ACK No such song` へ変換 (delete()/prio() 等と同じ「範囲外は
  ACKで返す」流儀)。1回の core 呼び出しに集約するため、呼び出し1-2間の TOCTOU
  ウィンドウ自体が消滅する (move()/swap() 本体呼び出しとの間の残余レースは
  mpdmoveswaprace-patch.py の AssertionError→ACK Bad song index 変換が既に
  吸収済みのため対象外)。パッチ適用後の生成ソースは一時コピーに `chmod u+w`
  して書き込み可にした上で `ast.parse` で構文確認、2回適用しても冪等(スキップ)
  であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で
  確認 — 通常系: 8曲キューで `moveid` (絶対/末尾越え位置とも正しく移動)・
  `swapid` (2曲の入れ替えが正しく反映)、存在しない tlid `moveid "9999" "0"` /
  `swapid "9999" "3"` / `swapid "4" "9999"` → いずれも修正前ならクラッシュしていた
  ところ `ACK [50@0] {moveid/swapid} No such song` に正しく変換されることを確認。
  **TOCTOUレース自体の再現・修正確認**: 未パッチ版 (nix/lib/mopidy-env.nix から
  本パッチを一時的に除外して再ビルド) に対し、複数スレッドで同一 tlid への
  `moveid`/`swapid` を連打しつつ別スレッドで同じ tlid を `deleteid`→`findadd`
  再追加を繰り返すストレステストを実施したところ、mopidy.log に実際に
  `TypeError: unsupported operand type(s) for +: 'NoneType' and 'int'`
  (current_playlist.py:490, moveid) と
  `TypeError: '>=' not supported between instances of 'NoneType' and 'int'`
  (current_playlist.py:859, swapid) の Traceback が出力され、`Unhandled exception
  in MpdSession` としてアクターが停止しクライアント接続が実際に切断されることを
  確認 (パッチ前の実際の不具合として再現確認)。本パッチを再適用したビルドで同一の
  ストレステスト (moveid系: mover 6スレッド+deleter 6スレッド20秒、swapid系: swapper
  6スレッド+deleter 6スレッド20秒) を再実行したところ、接続断0件・異常ACK0件・
  mopidy.log の Traceback/ERROR 0件を確認 (moveid合計164回・swapid合計138回の
  操作を消化)。旧来の `tagtypes`/`status`/`list album`/`count any`/`search any
  sort+window併用`/`crossfade`/`getvol`/`move`/`swap`(raw position系統)の回帰なし・
  mopidy.log に Traceback/ERROR 0件を確認。
- [x] `searchaddpl {NAME} {TYPE} {WHAT} [...]` (music_db.py) が保存結果を反映する
  `context.core.playlists.save(playlist)` の戻り値 (pykka の Future) を一度も
  `.get()` せず投げっぱなしのまま関数を抜けている不具合。TODO 全項目消化済みのため
  自走エージェントが、直近の一連の `.get()` 抜け修正 (delete/toggleoutput/moveid/
  swapid 等) と同種のパターンが他にも残っていないか `context.core.*` の全呼び出しを
  ast (`ast.walk` で `context.*(...)` の裸のExpr文を抽出) で機械的に洗い出す形で
  調査し新規発見・追加した項目。同じファイル/隣接ファイル (stored_playlists.py) の
  `context.core.playlists.save(...)` 呼び出しは他に10箇所あり、そのどれもが
  `.get()` した上で戻り値が `None` (保存失敗、mopidy core `playlists.save()` の
  docstring通りURIスキームに対応するバックエンドが無い/バックエンド側で書き込みに
  失敗した場合の挙動) なら `exceptions.MpdFailedToSavePlaylist` を送出しているのに、
  `searchaddpl` だけが唯一 `.get()` すらせず保存の成否を一切確認しないまま `OK` を
  返す非対称な実装だったと判明。実害: 保存が実際に失敗しても (書き込み権限不足等)
  クライアントには `OK` が返り、検索結果が実は1件も保存されていないことに気づけない。
  verified: mpdsearchaddplsave-patch.py。stored_playlists.py の`playlistclear`/
  `playlistdelete`等と同じ流儀で`.get()`して結果を変数に受け、`None`なら
  `exceptions.MpdFailedToSavePlaylist(urllib.parse.urlparse(playlist.uri).scheme)`
  を送出するよう変更 (music_db.pyに`import urllib`を追加)。パッチ適用後の生成
  ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)
  であることも確認。パッチ済みenvのdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで実データ(YOASOBI楽曲)で確認 — **不具合自体の再現**: パッチ未適用の
  ビルド(nix/lib/mopidy-env.nixから本パッチを一時的に除外して再ビルド)で、既存の
  ストアドプレイリスト`SearchAddPlTest1`(m3uバックエンド、ローカルディスク保存)の
  保存先ディレクトリを`chmod 555`(書き込み不可)にした状態で`searchaddpl
  "SearchAddPlTest1" any "YOASOBI"`を送信→`OK`が返るが`listplaylist
  "SearchAddPlTest1"`の内容は一切変化せず(保存が実際には全く行われていない)、
  mopidy.logには`mopidy.m3u.playlists ERROR Error saving playlist ...: Permission
  denied`が記録されているにも関わらずMPDクライアント側には一切通知されないことを
  実際に確認(パッチ前の実際の不具合として再現確認)。本パッチを再適用したビルドで
  同一の条件(ディレクトリ書き込み不可)で再実行したところ、`searchaddpl
  "SearchAddPlTest1" any "YOASOBI"`→`ACK [0@0] {searchaddpl} Backend with scheme
  "m3u" failed to save playlist`に正しく変換され、`listplaylist`の内容も不変
  (誤って保存済みと誤認しない)ことを確認。ディレクトリを書き込み可能に戻した状態
  (通常系)では、新規プレイリスト`searchaddpl "SearchAddPlTest2" any "YOASOBI"`→
  `OK`・`listplaylist "SearchAddPlTest2"`で実際に2曲(YOASOBI検索結果)が正しく
  保存されていることも確認 (`.get()`追加による同期化が正常系の動作・レスポンス
  タイミングを変えないことも確認)。旧来の`tagtypes`/`status`/`search
  any`/`list album`/`count any`/`listplaylists`の回帰なし・mopidy.logに
  Traceback 0件・意図した検証用ERROR(上記Permission denied、本テストで意図的に
  発生させたもの)以外のERROR 0件を確認。
- [x] `clear`(current_playlist.py)、`consume`/`random`/`repeat`/`single`/`stop`
  (playback.py) が `context.core.*(...)` の戻り値 (pykka の Future) を一度も
  `.get()` せず投げっぱなしのまま関数を抜けている不具合。TODO 全項目消化済みの
  ため自走エージェントが、直近の一連の `.get()` 抜け修正 (delete/toggleoutput/
  moveid/swapid/searchaddpl 等) と同種のパターンが他にも残っていないか
  `context.core.*` の全呼び出しを ast (`ast.walk` で `context.core.*(...)` の
  裸の Expr 文を抽出) で機械的に洗い出す形で調査し新規発見・追加した項目。
  current_playlist.py 内の他の全ての `context.core.tracklist.*` 呼び出し
  (add/remove/move/index/get_length 等、計20箇所以上) はどれも `.get()` して
  いるのに `clear()` だけが唯一投げっぱなし。playback.py も同様に
  next/pause/resume/play/seek/mixer.get_volume/set_volume 等は全て `.get()`
  しているのに `consume`/`random`/`repeat`/`single`/`stop` の5箇所だけが
  投げっぱなしという非対称な実装だったと判明 (mopidy-mpd 3.3.0 アップストリーム
  由来、周辺パッチ (mpdoneshot-patch.py 等) はこの行自体には手を入れていない)。
  実害: mopidy_mpd はハンドラが返った時点でクライアントへ `OK` を返すため、
  実際に core actor 側で consume/random/repeat/single/再生停止/キュークリアが
  反映されるより前に `OK` が届きうる (delete()/toggleoutput() 等で既に修正した
  「.get() 未呼び出しによるOK応答と実状態反映の非同期」と同じバグクラス)。rmpc
  はこれらのモード切替キー (既定バインドの Consume/Random/Repeat/Single トグル
  やクリア操作) の直後に `status`/`playlistinfo` を再取得して表示を更新するため、
  タイミング次第で古い状態を表示しうる。
  verified: mpdstatesync-patch.py。いずれも `.get()` を追加して同期化するだけの
  修正 (mopidy core の clear()/set_consume()/set_random()/set_repeat()/
  set_single()/playback.stop() は STATE が事前にプロトコル層で BOOL/
  ONOFFONESHOT として検証済みのため validation.check_boolean() が実際に例外を
  投げることはなく、追加の例外処理は不要と判断)。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` して書き込み可にした上で `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。パッチ済み env の dev
  mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD で確認 —
  `consume 1`/`random 1`/`repeat 1`/`single 1` それぞれ直後の `status` で
  即座に反映を確認、`single "oneshot"`/`consume "oneshot"`
  (ONOFFONESHOT、mpdoneshot-patch.py との相互作用) も回帰なく `status` へ
  正しく反映。実データ(YOASOBI「Orion」「夜に駆ける」2曲)を `findadd` で
  キューに積み `play "0"` で再生開始した状態から、`stop` 送信直後の同一接続での
  `status` が `state: stop` を即座に返すこと、`clear` 送信直後の同一接続での
  `playlistinfo` が空 (`playlistlength` 反映) を即座に返すことを確認 (旧実装なら
  投げっぱなしのため理論上ここで古い状態が返り得た経路)。旧来の
  `tagtypes`/`status`/`search any`/`list album`/`count any`/`crossfade`の
  回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `count`/`searchcount group TAG` と `playlistfind`/`playlistsearch` が、フィルタ式が
  `!=`/`!~` (negatives) のみで肯定条件を1つも含まない場合、実際には計算可能にも関わらず
  一律 `ACK incorrect arguments` を返していた不具合。TODO 全項目消化済みのため自走
  エージェントが、mpdnegfilter-patch.py 自身の既知の制約コメント (「フィルタが
  `!=`/`!~` のみだと backend が全曲取得できないため代替不能」) を手掛かりに、この制約が
  本当に全ての経路で成り立つか再検証する過程で新規発見・追加した項目。実際には
  `count`/`searchcount group ...` は `_mpd_count_grouped()` が `get_distinct()` で
  タグ値を列挙し、値ごとに `subquery[gfield]=[value]` という肯定条件を追加してから
  再帰する構造のため、最終的に backend.search() へ渡る query は常に非空になり
  「全曲取得不能」制約はそもそも発生しない。`playlistfind`/`playlistsearch`
  (`_pf_search`) に至っては `context.core.tracklist.get_tl_tracks()` でキュー全体を
  無条件取得してからローカル比較するだけの実装で、backend への丸投げ自体が存在せず
  制約が原理的に無関係。にも関わらず両者とも共有関数 `_query_from_mpd_filter_expression`
  の `if not query: raise` に一律で引っかかっていた。dev mopidy(6601, ytmusic
  実アカウント) に実際に `playlistfind "(Title != \"XYZDOESNOTEXIST\")"` を送って
  2曲キューの状態で再現確認したところ `ACK [2@0] {playlistfind} incorrect arguments`
  となり、本来「該当しない曲を除いた残り全曲」を返せるはずの操作が丸ごと失敗することを
  実機で確認した。
  verified: mpdnegonlyfilter-patch.py。`_query_from_mpd_search_parameters`/
  `_query_from_mpd_filter_expression` に `require_positive=True` (既定値、
  find/search/findadd/searchadd/searchaddpl は無指定のまま=従来通り厳格) を追加し、
  `count`/`searchcount` は `group` 指定時 (`_group_fields` 非空) のみ
  `require_positive=False` を渡すよう変更、`_pf_search` (playlistfind/playlistsearch)
  は常に `require_positive=False` を渡し、二重に存在した同種のガードも
  negatives/positives いずれも空の場合のみエラーにするよう修正。パッチ適用後の生成
  ソースは一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し
  MPD で確認 — `playlistfind "(Title != \"XYZDOESNOTEXIST\")"` → 該当しないため全曲
  (2曲)、`playlistfind "(Title != \"夜に駆ける\")"` → 「夜に駆ける」のみ正しく除外され
  「Orion」1曲、`playlistsearch "(title != \"夜に駆ける\")"` (大小無視) も同様、
  `sort`/`window` 併用も正しく機能、既存の `playlistfind "(Title == \"夜に駆ける\")"`
  (肯定演算子) や `playlistfind ""` (空引数、従来通り `ACK incorrect arguments`) は
  無変更で回帰なし。`count`/`searchcount group ...` は、このテストアカウントの
  ytmusic get_distinct が personal library 認証 (browser.json のセッション) に依存し
  今回の検証セッションでは認証切れのため実データでは検証できなかった (`list album`
  等も同様に空になることを確認済みで、本パッチ非対象の環境要因)。そのため
  get_distinct/search を実装した検証用スタブ backend (pkg_resources entry_points で
  /tmp に dist-info 生成、別ポート6602、artist/genre違いの4トラック) で確認 —
  `count "(Genre != \"Rock\")" group artist` → Rock を含む曲を除外した上で正しく
  ArtistA:1曲/ArtistB:1曲 (修正前は同条件で `ACK incorrect arguments`)、
  `count "(Genre == \"Rock\")" group artist` (肯定演算子、従来通り) も無変更で正しい
  カウント、`searchcount "(genre != \"rock\")" group artist` (大小無視) も同様、多段
  group (`group artist group album`) + negative filter の組み合わせも正しくネスト、
  `count group artist` (フィルタ無し) は無変更で回帰なし。既存の重要な仕様は意図的に
  維持: `count "(Genre != \"Rock\")"` (group無し)・`find "(Genre != \"Rock\")"` は
  引き続き `ACK incorrect arguments` のまま (mopidy-ytmusic はリモート検索APIのみで
  「全曲取得」手段が無く原理的に代替不能なため、mpdnegfilter-patch.py の既知の制約は
  この2経路については変更していない)。dev mopidy(6601, ytmusic 実アカウント) でも
  実データ (YOASOBI 2曲) で `tagtypes`/`status`/`search any sort+window併用`/
  `list album group AlbumArtist`/`count any`/`playlistfind filename`/
  `sticker get`(no such sticker応答)/`listplaylists`/`crossfade`/`getvol` の回帰なし・
  mopidy.log に Traceback/ERROR 0件を確認。
  既知の制約: この検証セッションでは dev mopidy の ytmusic アカウント認証
  (browser.json のセッション) が切れており、`YouTube Music/Liked Songs`/`Artists`/
  `Albums`/`Subscriptions` 等の個人ライブラリ依存機能が軒並み空を返す状態だった
  (get_liked_songs が「Sign in to listen to your liked tracks」という未ログイン応答を
  受け取り KeyError を握り潰して空になっていることをログで確認、`search`
  等の公開カタログAPIのみは正常に機能)。本項目のスコープ (configs/media/mopidy/と
  nix/lib/mopidy-env.nix のみ、secrets/browser.jsonには触れない) では対応不可のため
  次回以降の人間の対応が必要 (browser.json の再認証)。
- [x] `mopidy_mpd/actor.py` の `_revert_oneshot` (mpdoneshot-patch.py が追加した、
  single/consume の oneshot モードを対象曲の再生終了後に自動でoffへ戻す処理) が
  `self.core.tracklist.set_single(False)` / `self.core.tracklist.set_consume(False)`
  の戻り値 (pykka の Future) を一度も `.get()` せず投げっぱなしのまま関数を抜けている
  不具合。TODO 全項目消化済みのため自走エージェントが、既存の `.get()` 抜け修正
  (delete/toggleoutput/moveid/swapid/searchaddpl/clear/consume/random/repeat/single/
  stop 等) と同じ「`context.core.*`/`self.core.*` の裸の Expr 文呼び出し」パターンを
  ast (`ast.walk`) で `mopidy_mpd/protocol/*.py` だけでなく `mopidy_mpd/actor.py`・
  `mopidy_ytmusic/*.py` も含めて機械的に再走査し新規発見・追加した項目
  (mpdstatesync-patch.py 自身のコメントが「周辺パッチ (mpdoneshot-patch.py 等) は
  この行自体には手を入れていない」と明記していた通り、actor.py はこれまでの
  `.get()` 監査の対象外だった)。同じメソッド内の直前の行
  `translator.set_single_state("0")`/`translator.set_consume_state("0")` は
  プロセス内の揮発性ストアへの同期的な代入で即座に反映されるため (status の
  single/consume フィールドは常にこのストアから返す)、`status` 応答自体に見た目の
  遅れは生じないが、実際の自動再生判断へ使われる mopidy core 本体の
  `Tracklist._single`/`_consume` (get_eot_tlid()/_mark_played() が参照する実体) 側は
  非同期メッセージが core actor のメールボックスで処理されるまで反映されず、他の
  `context.core.tracklist.set_*()` 呼び出しが全て `.get()` して同期化しているのと
  非対称だった。
  verified: mpdoneshotrace-patch.py。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも
  確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、`findadd` で
  YOASOBI 2曲をキューへ積んだ上で MPD プロトコルで実際に確認 —
  `single "oneshot"` → `play "0"` → `seekcur` で曲終端付近まで進めて自然終了
  (`track_playback_ended`) を実際に発火させ、`_revert_oneshot()` が例外なく実行され
  `status` が `single: 0`/`state: stop` に正しく反映されることを確認。
  `consume "oneshot"` でも同様に自然終了を発火させ、`_revert_oneshot()` 実行後に
  `consume: 0` へ復帰した上で、consume本来の動作(該当曲がキューから削除され
  `playlistlength` が2→1に減少、かつ次曲(Orion)へ自動的に再生が進む)が
  正しく機能することを確認。旧来の `status`/`outputs`/`listplaylists`/
  `count any`/`list album group AlbumArtist`/`getvol`/`crossfade`/`channels`/
  `sticker get`(no such sticker応答) の回帰なし、mopidy.log に Traceback/ERROR
  0件を確認 (テスト中に発生した1件の `GStreamer error: Forbidden` はYouTube側の
  ストリームURLへの短時間の連続アクセスによるものであり、本パッチや
  `track_playback_ended` 経路とは無関係な別要因と切り分け済み)。
- [x] `list` (mpdlist-patch.py が実装した group 修飾込み) が末尾の `window {START:END}`
  修飾 (musicpd.org 仕様: `list {TYPE} {FILTER} [group {GROUPTYPE}] [window {START:END}]`)
  に一切対応しておらず、`window` トークンがそのままフィルタ式のタグ名として扱われ
  `ACK Unknown filter type` を返していた不具合。TODO 全項目消化済みのため自走
  エージェントが実 MPD 本体 (MusicPlayerDaemon/MPD を実際に clone し
  src/command/DatabaseCommands.cxx の `handle_list`/`ParseDatabaseSelection` を直接確認)
  と rmpc 本体 (mierak/rmpc を実際に clone) を突き合わせて調査し新規発見・追加した項目。
  rmpc-mpd/src/mpd_client.rs `send_list_tag_grouped` は現状 window を送らないが、
  rmpc/src/ui/panes/tag_browser.rs (カスタムタグ階層ブラウザペイン、`group_by` が
  複数指定された場合に `list_tag_grouped(primary_tag, &group_tags, ...)` で任意個数の
  `group` を送る汎用実装) は musicpd.org 仕様に忠実なクライアント実装であり、将来
  ページングに window を使う/他クライアントが使う可能性のある正当な呼び出しが
  現状は丸ごと失敗するギャップとして修正した。実 MPD ソース確認で判明した仕様:
  window は `group` 修飾群よりさらに後ろ(コマンド末尾)に置く必要があり、
  `PrintUniqueTags` の実装上、window は最外周の階層 (group 指定時はその一番外側の
  group、無指定時は TYPE 自体) にのみ適用され、内側の階層は常に全件表示される。
  verified: mpdlistwindow-patch.py。mpdwindow-patch.py が search/find 用に追加済みの
  `_mpd_parse_window(value)` (window値文字列→sliceの変換、書式検証込み) を再利用し、
  `list_()` で group 抽出の前に末尾の `window START:END` を剥がして
  `_mpd_list_grouped(..., window)` へ渡すよう変更、`_mpd_list_grouped` は
  window が指定されていれば最外周のイテレーション対象 (group 指定時は最外周の
  group値列、無指定時はリーフの値列) のみに `values[window]` のスライスを適用し、
  再帰先には渡さない (内側は常に全件) よう修正。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。ytmusic backend の `get_distinct` が個人ライブラリ
  (このテストセッションでは album 系タグを一切返さない、公開検索カタログのみ機能する
  状態) に依存し実データでの検証ができないため、mpdlist/mpdsort/mpdwindow-patch.py
  自身の検証と同じ流儀で、`get_distinct` を実装した検証用スタブ backend
  (pkg_resources entry_points で /tmp に dist-info 生成、別ポート6602、
  AlbumArtist 3件×Album 計10件の固定データ) を用意して実際に起動し MPD で確認 —
  `list Album`(無指定、10件)、`list Album window "0:3"`→先頭3件、
  `list Album window "3:6"`→中間3件、`list Album window "8:"`→末尾2件(open-ended)、
  `list Album group AlbumArtist`(無windowの通常表示、AA1/AA2/AA3全件)、
  `list Album group AlbumArtist window "0:2"`→AA1・AA2の2アーティスト分のみだが
  各アーティストの Album はそれぞれ全件(4件/2件)を正しく表示 (内側は非windowed)、
  `list Album group AlbumArtist window "2:3"`→AA3のみ(Album4件全件)、
  フィルタ式併用 `list Album "(Album contains \"Album0\")" window "0:2"`→2件、
  旧来の3引数互換形式 `list album "AA1" window "0:2"`→2件、いずれも正しく動作。
  エラー系: `list Album window "bogus"`→`ACK Invalid window: bogus`、
  `list Album window "5:2"`(逆転レンジ)→`ACK Invalid window: 5:2`、実 MPD 仕様通り
  window は group より後ろに置く必要があるため `list Album window "0:3" group
  AlbumArtist`(誤った順序)→`ACK Unknown filter type`(window非対応時と同じ挙動を
  維持、実 MPD も同じ位置で同様に失敗することをソースで確認済み)。dev
  mopidy(6601, ytmusic 実アカウント) でも実際に起動し、`search any "yoasobi"
  sort -Date`/`list Album`(空)/`list Album window "0:1"`(空、エラーにならず
  OKのみ)/`count any`/`status`/`tagtypes` の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
- [x] `searchaddpl {NAME} {TYPE} {WHAT} [...]` が `sort {TYPE}`/`window {START:END}`/
  `position {POS}` 修飾子を一切解釈せず、検索結果を無条件・無ソートで常に末尾へ
  追加するのみだった不具合。findadd/searchadd (mpdfindaddpos-patch.py) は既に
  この3修飾子に対応済みだが、同じ grammar を共有するはずの `searchaddpl` だけが
  legacy な固定 TAG/VALUE ペア列のみを受け付ける実装のまま取り残されていた
  非対称なギャップ。TODO 全項目消化済みのため自走エージェントが実 MPD の
  プロトコル仕様書 (mpd.readthedocs.io/en/latest/protocol.html および
  MusicPlayerDaemon/MPD の doc/protocol.rst) を WebFetch で確認し、
  `find`/`search`/`findadd`/`searchadd`/`searchaddpl` の5コマンドが共通の
  `{FILTER} [sort {TYPE}] [window {START:END}]` を持ち、うち
  `findadd`/`searchadd`/`searchaddpl` の3つはさらに `[position {POS}]` も
  持つと確定した上で新規発見・追加した項目。実害: sort/window/position 付きの
  正当な MPD 0.24+ 呼び出しが `searchaddpl` に対してだけ余分なトークン扱いで
  `ACK incorrect arguments` になり丸ごと失敗する。
  verified: mpdsearchaddplpos-patch.py。実 MPD 本体 (MusicPlayerDaemon/MPD
  src/command/DatabaseCommands.cxx handle_searchaddpl,
  src/db/DatabasePlaylist.cxx SearchInsertIntoPlaylist) を WebFetch で実際に
  ソース確認し仕様を確定: POSITION は `playlistadd`(mpdplaylistaddpos-patch.py)
  と同じく絶対インデックスのみ(add/addid/load/findadd/searchadd の相対 +N/-N
  とは異なる)、対象プレイリストの現在の曲数を超えると `ACK_ERROR_ARG`
  ("Bad position"、playlistadd と同一メッセージ)、sort/window は追加しようと
  している新規トラック集合に対して「まずソート→次にwindowで絞り込み」の順で
  適用してから POSITION の位置へ挿入する。実装は末尾の `position POS` を先に
  剥がし、残りへ findadd/searchadd と共用の `_mpd_extract_sort_params` で
  `sort`/`window` を適用してから FILTER を解釈するよう変更(実 MPD の
  ParseQueuePosition→ParseDatabaseSelection の剥がす順序と一致)。パッチ適用後の
  生成ソースは一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用
  しても冪等(スキップ)であることも確認。パッチ済み env の dev mopidy(6601,
  ytmusic 実アカウント) を実際に起動し実データ(YOASOBI「夜に駆ける」
  「オリオン - Orion」2曲、アーティスト検索で15曲)で MPD プロトコルを直接
  叩いて確認 — 修飾子無し(従来通り末尾追加)の回帰なし、`sort Title`→昇順
  ([オリオン, 夜に駆ける])/`sort -Title`→降順が正しく反転、`sort Title window
  "0:1"`→ソート後に先頭1件のみ、`sort Title position "0"`→ソート済み2曲が
  既存プレイリストの先頭に正しく挿入され末尾の既存2曲はそのまま
  ([新規2曲(ソート順), 既存2曲])、`sort Title window "0:1" position "0"`→
  window絞り込み後の1曲だけが先頭に挿入、`position "2"`(中間位置)→該当
  インデックスに正しく挿入、レガシー2引数形式 `searchaddpl NAME artist
  "YOASOBI"`(15曲、修飾子無し)も無変更で回帰なし。エラー系: 現在の曲数(2)を
  超える `position "999"`→`ACK [2@0] {searchaddpl} Bad position`、非数値
  `position "abc"`→`ACK incorrect arguments`、相対書式 `position "+0"`
  (findadd/searchaddとは異なりsearchaddplは絶対のみ)→`ACK incorrect
  arguments`(仕様通り拒否)、新規(存在しない)プレイリストへの
  `position "0"`→正しく作成・挿入、同じ新規プレイリストへの `position "1"`
  (曲数0を超過)→`ACK Bad position`。旧来の `tagtypes`/`status`/`list
  Album`/`count any`/`search any sort+window併用`/`crossfade`/`getvol`/
  `listplaylists` の回帰なし・mopidy.log に Traceback/ERROR
  0件(意図的に投げた不正URI `playlistadd` テストによる1件のKeyError
  Tracebackを除く、本パッチの経路とは無関係と確認済み)を確認。
- [x] `mopidy_ytmusic.library.py` の `parseSearch()` (resultType=="artist" 分岐、
  artistq["songs"]["results"] 経由で曲を積む箇所) が、曲に紐づく album
  (song["album"]) を新規 Album として登録する際、この日付フォールバックだけ
  `date="1999"` という無関係な決め打ち値を使っている不具合。TODO 全項目消化済み
  のため自走エージェントが mopidy_ytmusic のコード品質を再調査して発見した項目。
  ファイル内の他13箇所の日付フォールバックは全て "0000" (unknown センチネル) で
  統一されているのにここだけ異質で、ytmusicapi 1.12.1 (parsers/songs.py
  parse_song_album()) をソース確認したところ `{"name": ..., "id": ...}` のみで
  "year" キーはこの経路では構造的に一度も生成されないため、KeyError にはならず
  (ytartistalbumyear-patch.py が既に修正した album["year"]/single["year"] 決め打ち
  アクセスの KeyError クラッシュとは別種のバグ)静かに偽の年 1999 が全曲に付与され
  続ける。実害: `search artist "NAME"` のトップ曲一覧経由で得た曲は実際のリリース年
  に関わらず常に Date: 1999 を返し、`sort Date` や rmpc のアルバム年表示を汚染する。
  verified: ytartistsongyear-patch.py。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも
  確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し実データで MPD を直接
  叩いて確認 — `search artist "YOASOBI"` のトップ曲一覧経由の曲 (アイドル/夜に駆ける/
  群青/怪物/勇者 等、videoId 経由で新規登録される曲) が全て `Date: 1999` から
  `Date: 0000` に変化 (実際の年は取得不能なため他箇所と同じ unknown センチネル)、
  同レスポンス内のアルバム自体の `Date:` (album["year"]/single["year"] 経由、
  ytartistalbumyear-patch.py の担当範囲) は無変更で実年 (2021-2026 等) を維持し
  回帰なし。旧来の `status`/`count any "yoasobi"`(songs:2/playtime:469)/
  `search any "yoasobi" sort -Date window "0:2"` の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
- [x] `lsinfo {URI}` に曲そのものの生URI (例: `ytmusic:track:xxx`) を渡すと常に
  `ACK [50@0] {lsinfo} Not found` になる不具合。TODO 全項目消化済みのため自走エージェントが
  rmpc 本体 (mierak/rmpc) を実際に clone して調査し発見した項目。rmpc/src/ui/panes/search/mod.rs
  の検索ペイン search() (236-304行目) が、テキストフィルタ無しで Rating/Liked フィルタのみを
  指定した場合 (mpdstickerfind-patch.py 対応済みの `sticker find song "" rating ...`/
  `like ...` 拡張構文を使う、rmpc UIから普通に到達できる操作) に入る分岐で、ヒットした各曲の
  `sticker find` 結果の `file` (= rmpc-mpd/src/shared/mpd_client_ext.rs set_sticker_multiple の
  `Enqueue::File{path}` = song.file、バックエンドの生URIそのもの、299行目 `send_lsinfo`) を
  `send_start_cmd_list()` のコマンドリスト内で URI毎に `lsinfo` してタグ情報を再取得している
  ことを確認した上で着手。原因: mopidy_mpd/dispatcher.py の `MpdSession.browse()` は URI引数を
  「バックエンドの生URI」ではなく「表示名で構成された仮想パス文字列」として扱い、`_uri_map`
  (過去のディレクトリ走査でのみ登録される表示名→URIキャッシュ) 経由でしか解決できない設計の
  ため、"/" を含まない生URI (ytmusic:track:xxx 等) は必ず `_uri_map`・表示名一覧のどちらにも
  一致せず `raise exceptions.MpdNoExistError("Not found")` に落ちる。実 MPD の仕様は WebFetch で
  MusicPlayerDaemon/MPD の src/command/DatabaseCommands.cxx handle_lsinfo2 と
  src/db/DatabasePrint.cxx db_selection_print (db.Visit()がVisitSongにマッチすればPrintSongFull()
  でその曲1件のタグを返す) を確認し、「曲ファイルのURIを渡された lsinfo はその曲のタグ情報を
  返す」のが正しい仕様と確定 (mount/crossfade等の「バックエンドがリモートAPI丸投げのため対応
  不能」という既存の制約とは異なり、mopidy_mpd 自身の設計上の非互換であり修正可能と判断)。
  verified: mpdlsinfouri-patch.py。readcomments (mpdreadcomments-patch.py) と同じ流儀で、
  browse() が MpdNoExistError を投げた場合のフォールバックとして
  `context.core.library.lookup(uris=[uri]).get()` で生URIとして直接解決を試み、解決できれば
  その曲のタグ情報を返し、解決できなければ元の Not found をそのまま再送出するよう修正。
  パッチ適用後の生成ソースは一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用
  しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し
  実データで MPD を直接叩いて確認 — `search any "yoasobi"` で得た実在の曲URI
  (`ytmusic:track:by4SYYWlhEs`=夜に駆ける、`ytmusic:track:fCh0qfxElm8`=オリオン) への
  `lsinfo "URI"` が Not found ではなく正しくその曲のタグ情報 (Title/Time/Date等) を返すことを
  確認。rmpc が実際に使う `command_list_begin`/`command_list_end` 経由での複数URI一括 lsinfo
  (rmpcのRating/Liked検索と同じ呼び出しパターン) も両曲とも正しく返ることを確認。回帰確認:
  存在しない生URI形式 (`ytmusic:track:doesnotexist12345`) への `lsinfo` は従来通り
  `ACK [50@0] {lsinfo} Not found` を維持 (フォールバックのlibrary.lookup()がERROR log付きの
  KeyErrorをバックエンド内部で起こすが、これは既存の `readcomments` に全く同じ偽URIを渡しても
  同一のERROR/Tracebackが発生する mopidy_ytmusic.getTrack() 側の既存挙動であり
  readcomments-patch.py と対称の pre-existing 挙動と確認済み・本パッチが新規に持ち込んだ
  ものではない)、`lsinfo` 無指定 (ルート)・`lsinfo "YouTube Music"` (仮想パス経由の
  ディレクトリ列挙) は無変更で回帰なし。旧来の `tagtypes`/`listplaylists`/
  `crossfade 5`+`status`(xfade反映)/`count any "yoasobi"`(songs:2/playtime:469) の回帰なしを
  確認。
- [x] `mopidy_mpd/uri_mapper.py` の `MpdUriMapper.refresh_playlists_mapping()` が削除/リネームされた
  旧プレイリストの名前<->URIキャッシュを永久に残す不具合。TODO 全項目消化済みのため自走エージェントが
  mopidy_mpd のコード品質を再調査して発見した項目。同ファイルの `rename()` 実装自身が末尾に
  `# TODO: should we purge the mapping in an else?` と自認している通り、上流未対応のまま残っていた
  ギャップ。原因: `_uri_from_name`/`_playlist_name_from_uri` は `insert()` で追加専用に書き込まれる
  だけで、`refresh_playlists_mapping()` はバックエンドの現在の `as_list()` を都度読んでは既存
  エントリに`insert()`するだけであり、以前存在したが今は無いプレイリストのエントリを一切
  pop/del しない。再現手順: 名前「Test」のプレイリストを作成し `listplaylists` で一度でも
  参照させる (uri=U1 がキャッシュされる)。それを `rm` で削除し、同じ名前「Test」で新規に
  プレイリストを作る (`save`/`playlistadd` 経由。mopidy_ytmusic 等バックエンドは削除ごとに
  新しい id を振るため uri=U2 で全く別物)。次の `listplaylists`/`_create_unique_name("Test", U2)`
  は「"Test" という名前は既に(古い)U1 に紐付いている」と誤判定し、実際には同名プレイリストが
  1つしか存在しないのに `playlist: Test [2]` という不要なサフィックス付き名前を返す。さらに、
  `rm`/`load`/`playlistadd`/`rename` が使う `lookup_playlist_uri_from_name("Test")` は
  キャッシュヒットする限り常に実在しない古い U1 を返し続けるため、クライアントが「Test」という
  名前で操作しようとした対象が食い違う (実装済みの `rename()` は「新URIで作成→旧URI削除」という
  実装のため、rename 経路は毎回このケースを引き起こす)。
  verified: mpdplaylistcache-patch.py。`refresh_playlists_mapping()` を、まず現在の `as_list()`
  に存在しない旧エントリ (stale) を `_playlist_name_from_uri`/`_uri_from_name` から pop してから、
  現在のプレイリスト群を `insert()` する2段構成に変更 (stale 除去を先に行うことで、名前の再利用時に
  `_create_unique_name` が正しく元の名前へ戻れるようにする)。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。さらに
  `MpdUriMapper` を直接 import したユニットテストで、(a) 削除→別URIで同名再作成→
  `playlist_name_from_uri`/`playlist_uri_from_name` が新URIに正しく解決され旧エントリが残らない
  こと、(b) 修正前ロジックのみを切り出した再現コードで同シナリオが実際に `"Test [2]"` を生む
  (=不具合の実在) ことを確認、(c) 本当に同時に存在する同名2プレイリスト (バックエンドの
  `as_list()` が同じ名前を持つ別URIの Ref を2件返すケース) は今回の変更後も従来通り
  `"Same"`/`"Same [2]"` に正しく disambiguate されること (stale 判定は「現在の as_list() に
  無い uri」のみを対象とするため誤爆しない) を確認。実機検証: pkg_resources.entry_points(mopidy.ext)
  で /tmp に登録した検証用スタブ backend (PlaylistsProvider をメモリ実装、create() 毎に新規uriを
  発番、別ポート6602) でパッチ済み env の mopidy を実際に起動し MPD を直接叩いて確認 —
  `save "Test"`→`listplaylists`(`Test`)→`rm "Test"`→`save "Test"`(新URI)→`listplaylists`
  (`Test`、`Test [2]`ではない) を3サイクル連続で確認、`rename "Alpha" "Beta"`→`listplaylists`
  (`Beta`のみ)→`rm "Beta"`→`save "Alpha"`(新URI)→`listplaylists`(`Alpha`、サフィックス無し)、
  `playlistadd`/`listplaylistinfo`/`load`+`status`(lastloadedplaylist反映) の回帰なしも確認。
  dev mopidy(6601, ytmusic 実アカウント) でもクリーン起動・`status`/`tagtypes`/`listplaylists`/
  `count any "yoasobi"`(songs:2/playtime:466) の回帰なし・mopidy.log に Traceback 0件を確認。
- [x] `mopidy_ytmusic/backend.py` の `_get_auto_playlists()` (「Auto Playlists」ホーム相当、
  `library.ytbrowse` を更新し `ytmusic:auto`/`ytmusic:auto:<hash>` の browse で使われる) にある
  「空セクションを削除する」ループがオフバイワンで先頭セクション(index 0)を決して削除しない
  不具合。TODO 全項目消化済みのため自走エージェントが mopidy_ytmusic のコード品質を再調査して
  発見した項目。該当コード:
  ```
  for i in range(len(browse) - 1, 0, -1):
      if len(browse[i]["items"]) == 0:
          browse.pop(i)
  ```
  `range(len(browse) - 1, 0, -1)` は stop=0 が exclusive のため i=0 に到達せず、`browse[0]` が
  どれだけ空でも pop されない。`ytautoplaylistfix-patch.py` 適用後の `parse_auto_playlists()` は
  タイトル欠落セクションは弾く(browseへ追加しない)ものの、「セクション自体は追加されたが
  中の全アイテムが個別ガードでスキップされ `items=[]` のまま残る」ケース (例: カルーセルの
  全アイテムが未知のレンダラーで brId/ititle を解決できない) は正常系として想定しており、
  その除去をこの「空セクション削除」ループに委ねている。そのケースが最初のセクションで
  発生すると、rmpc 側で `ytmusic:auto` を開いたときに中身の無い空フォルダがクラッシュ無しで
  一覧に残り続ける。
  verified: ytautoemptysection-patch.py。`range(len(browse) - 1, 0, -1)` を
  `range(len(browse) - 1, -1, -1)` に変更し i=0 まで含める。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)である
  ことも確認。実機検証: パッチ済み env の `mopidy_ytmusic.backend` を `GI_TYPELIB_PATH`/
  `DYLD_LIBRARY_PATH` (gstreamer/gst-plugins-base の girepository-1.0) を明示して直接 import し、
  実際の `YTMusicBackend._get_auto_playlists()` を1件目のセクションが空(全アイテムが
  `musicTwoRowItemRenderer` を持たず未解決)・2件目が正常(1曲のプレイリスト)という合成
  `browse` レスポンスで呼び出して確認 — 修正前ロジックのみを切り出した再現コード
  (`range(..., 0, -1)`)では `ytbrowse` に `[("Empty Section", 0), ("Quick picks", 1)]` と
  空セクションが残ることを確認 (=不具合の実在)、修正後の実コードでは `[("Quick picks", 1)]`
  のみとなり空セクションが正しく削除されることを確認。dev mopidy(6601, ytmusic 実アカウント)
  を実際に起動し `lsinfo "YouTube Music"` → `Auto Playlists` フォルダ存在、
  `lsinfo "YouTube Music/Auto Playlists"` → `Rewind, replay`/`Hits throughout the decades`/
  `Trending community playlists`/`New releases`/`Charts` の5セクション正常列挙 (実データでは
  空セクションが無かったため空リストからの削除自体は再現できないが、クラッシュ無しの通常経路に
  回帰が無いことを確認)、旧来の`status`/`tagtypes`/`count any "yoasobi"`の回帰なしを確認。
  mopidy.log の Traceback は本検証中に意図的に送った不正な生URI (`lsinfo "ytmusic:auto"`、
  仮想パスではなく生URIをそのまま渡したことでフォールバックの `library.lookup()`→
  `getTrack()` が `KeyError: 'videoDetails'` を起こす、mpdlsinfouri-patch.py/
  readcomments-patch.py の検証時にも確認済みの pre-existing な挙動) の1件のみで、本パッチが
  新規に持ち込んだリグレッションではないことを確認。
- [x] `mopidy_mpd/uri_mapper.py` の `MpdUriMapper` は、mpdplaylistcache-patch.py で
  プレイリスト名前空間 (`_playlist_name_from_uri`) の stale エントリ purge は既に修正済みだが、
  browse (ディレクトリ閲覧) 名前空間 (`insert(..., playlist=False)` で書き込まれる
  `_browse_name_from_uri`/`_uri_from_name`) には対応する purge が一切無い不具合。TODO 全項目
  消化済みのため自走エージェントが mopidy_mpd のコード品質を再調査して発見した項目。原因:
  `dispatcher.py` の `MpdContext.browse()` は、あるディレクトリ(base_path)を列挙するたびに
  その子要素を無条件に `_uri_map.insert()` し続けるだけで、以前そのディレクトリに存在したが
  今回のリストには無い子要素のキャッシュエントリを一切削除しない。mopidy_ytmusic の
  `ytmusic:home`(YouTube Musicのホーム、日替わりでセクション内容・browseIdが変わる)のような
  動的なディレクトリをブラウズし続けると、`_uri_from_name`/`_browse_name_from_uri` が際限なく
  肥大化するだけでなく、`_create_unique_name()` が「名前は既存だが URI が違う」場合に無条件で
  衝突とみなし `"Name [2]"` サフィックスを付けるため、古い stale エントリ(既にそのディレクトリ
  から消えたURI)が残ったまま同名だが別URIの項目が同じディレクトリに再出現すると、本来
  衝突していないのに不要な `[2]` サフィックスが付き続ける(プレイリスト側で
  mpdplaylistcache-patch.py が修正したのと全く同じ設計ミスが browse 側にも存在する形)。
  verified: mpdbrowsecache-patch.py。`uri_mapper.py` に `refresh_browse_children(base_path,
  current_uris)` を追加(現在の子要素の URI 集合を受け取り、base_path の直接の子として
  過去にキャッシュされたが現在のリストに無い stale エントリを `_uri_from_name`/
  `_browse_name_from_uri` から purge する。prefix境界は「`base_path + "/"` で始まり、
  それ以降に `/` を含まない」ことで直接の子のみに限定し、別ディレクトリの兄弟エントリを
  誤って巻き込まない)。`dispatcher.py` の `browse()` を、ディレクトリの子を列挙する際に
  まず `future.get()` を1回だけ materialize してリスト化し、`refresh_browse_children()` を
  呼んでから `insert()` するよう修正。パッチ適用後の生成ソースは一時コピーに `chmod u+w` して
  `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。まず `MpdUriMapper` を
  直接 import したユニットテストで、(a) 修正前ロジックのみを切り出した再現コードで
  「同じディレクトリに同名だが別URIの項目が後日現れる」シナリオが実際に `"Name [2]"` を生む
  (=不具合の実在)ことを確認、(b) `refresh_browse_children()` 経由で purge した後は同シナリオで
  サフィックス無しの `"Name"` のままになることを確認、(c) 別ディレクトリの同名エントリ
  (prefix境界外)や、本当に同一ディレクトリ内に同時に存在する同名2エントリ(purgeされるべきで
  ない現存エントリ)は従来通り正しく `"Same"`/`"Same [2]"` に disambiguate されることを確認。
  実機検証: pkg_resources.entry_points(mopidy.ext)で /tmp に登録した検証用スタブ backend
  (LibraryProvider.browse()がルート直下の"Home"ディレクトリのuriを呼び出しごとにv1→v2→v2と
  変化させる、別ポート6602)でパッチ済み env の mopidy を実際に起動し MPD を直接叩いて確認 —
  `lsinfo "Stub"` を3回連続実行し、毎回 `directory: Stub/Home` (サフィックス無し)を維持する
  ことを確認。同じスタブ・同じシナリオを本パッチ適用前の env (別ポート6603)で実行すると
  1回目は `directory: Stub/Home`、2回目以降は `directory: Stub/Home [2]` という不要な
  サフィックスが付くことを確認(=不具合の実在と、本パッチによる解消の両方を実機で対比確認)。
  dev mopidy(6601, ytmusic 実アカウント)でもクリーン起動・`tagtypes`/`status`/`lsinfo ""`/
  `lsinfo "YouTube Music"`/`count any "yoasobi"`(songs:2/playtime:469)の回帰なしを確認。
  さらに `lsinfo "YouTube Music/Home"` を連続2回実行し、実データで日替わりのセクション構成
  (1回目: Rewind,replay/Trending community playlists/Summer 🏖/New releases/Charts/Quick picks、
  2回目: Hits throughout the decades/Trending community playlists/All time biggest hits/
  New releases/Charts/Quick picks、のようにセクションが入れ替わる)でも `[2]` サフィックスが
  一切付かずクラッシュも無いことを確認。mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic.library.py` の `self.TRACKS` (videoId -> Track のプロセス内キャッシュ) が、
  一度でも `getTrack()` (生の `ytmusic:track:<id>` URI を `lookup()` するフォールバック経路、
  mpdlsinfouri-patch.py の `lsinfo <生URI>` が実際に叩く) 由来の簡易版 (album=None、artistに
  URIなし) で書き込まれると、`playlistToTracks()`/`parseSearch()` (song分岐・artist経由songs
  分岐) がその後同じ曲に何度遭遇しても `if videoId in self.TRACKS: <再利用>` で中身の質を
  問わず無条件に再利用し続け、二度と豊富なメタデータ (Album/AlbumArtist/ブラウズ可能な
  Artist URI) で上書きされない不具合。TODO 全項目消化済みのため自走エージェントが
  mopidy_ytmusic のコード品質を再調査して発見した項目。姉妹関数の
  `uploadArtistToTracks()`/`uploadAlbumToTracks()`/`albumToTracks()` は同種のガードが
  ytuploadfix-patch.py/ytalbumfix-patch.py で既に無条件上書きに修正済みだったが、
  `playlistToTracks()`/`parseSearch()` だけ取り残されていた対称性の欠落と判明。実害:
  rmpc の Rating/Liked 検索は sticker (sqlite永続化、mopidy再起動をまたいで残る) に保存した
  曲URIへ `lsinfo` を command-list で一括送信するため、mopidy再起動直後の最初の一撃が
  `getTrack()` 経由で簡易版キャッシュを永久に焼き付け、以後その曲が本来のプレイリスト一覧や
  検索結果に豊富なデータで現れても Album タグ等が mopidy プロセスの残り寿命ずっと欠落し、
  rmpc の Album/Artist によるグルーピング・ナビゲーションが壊れる。
  verified: ytstalecache-patch.py。`playlistToTracks()` のガード、`parseSearch()` のsong分岐の
  外側ガード(`if videoId in self.TRACKS: 再利用`)+内側の冗長な二重ガード、同関数のartist経由
  songs分岐(`"songs" in artistq`)の外側ガード、計4箇所を撤去 (comment-outの流儀は
  `uploadAlbumToTracks()` 等の既存パッチと同じ)、常に最新の情報で `self.TRACKS` を
  再構築するよう統一 (album解決の既存ロジック自体、例えば song分岐で「アルバムが既に
  ALBUMSキャッシュに存在する場合はalbum変数に代入されない」という別の予備的な癖は今回の
  スコープ外としてそのまま温存)。パッチ適用後の生成ソースは一時コピーに `chmod u+w` して
  `ast.parse` で構文確認、2回適用しても (アンカー不一致で) 例外になり冪等にスキップされない
  (=他パッチと同じ一回限りのビルド時パッチ) ことを確認。まず namedtuple ベースの簡易
  スタブで新旧ロジックを切り出したユニットテストを実施し、(a) 修正前ロジックでは
  `getTrack()`相当の簡易キャッシュ (album=None) を先に入れた状態で `parseSearch()`
  相当の処理を実行しても album=None のまま (=不具合の実在)、(b) 修正後ロジックでは
  同シナリオで album が実データに正しく更新されることを確認。実機検証: dev mopidy
  (6601, ytmusic 実アカウント) を実際に起動し MPD を直接叩いて確認 — チャート系プレイリスト
  `YouTube Music/Auto Playlists/Charts/Trending 20 Japan (Chart • YouTube Music)` から
  実在の曲 `ytmusic:track:UZ4an60Zmvc` (Mrs. GREEN APPLE「Brand New」) のvideoIdを把握した
  上で mopidy を再起動しキャッシュを空にし、①まず `lsinfo "ytmusic:track:UZ4an60Zmvc"`
  (生URI) を送信 → `getTrack()` 経由の簡易版が返り Album/AlbumArtist/X-AlbumUri が
  一切無いことを確認 (=簡易キャッシュが実際に焼き付いたことの確認)、②続けて同じ
  プレイリストを `lsinfo` でブラウズ (`playlistToTracks()` 経由) → 同じ曲が
  `Album: Brand New`/`AlbumArtist: Mrs. GREEN APPLE`/`X-AlbumUri: ytmusic:album:...`
  付きの豊富なデータで返ることを確認 (=簡易キャッシュを乗り越えて正しく上書きされたことの
  実機確認)、③さらに同じ生URIへ再度 `lsinfo` → 今度はキャッシュ経由で豊富なデータが
  そのまま返ることも確認、④`search artist "Mrs. GREEN APPLE"` (artist経由songs分岐を
  実際に経由) でも同曲を含む多数の曲が `Album`/`AlbumArtist`/`X-AlbumUri` 付きで正しく
  返り、この分岐もクラッシュ無く動作することを確認。旧来の `tagtypes`/`status`/
  `count any "yoasobi"`(songs:2/playtime:469) の回帰なし、mopidy.log に Traceback/ERROR
  0件を確認。
- [x] `mopidy_mpd/protocol/stored_playlists.py` の `rename {NAME} {NEW_NAME}` が
  `context.core.playlists.create(new_name, uri_scheme).get()` の戻り値を None チェックせず
  いきなり `.replace()` している不具合。TODO 全項目消化済みのため自走エージェントが
  mopidy_mpd のコード品質を再調査して発見した項目。原因: `mopidy_ytmusic.playlist.
  YTMusicPlaylistsProvider.create()` は `self.backend.api.create_playlist(name, "")` が
  例外を投げた場合 (ネットワーク瞬断・YouTube Music側のレート制限/クォータ・重複タイトル・
  不正な文字・認証切れ等) `logger.exception()` した上で None を返す設計であり、同じファイル内の
  姉妹関数 `_create_playlist()` (playlistadd が使う) は `if new_playlist is None: ... continue`
  で正しくガードしているのに対し、`rename()` だけ create() の戻り値を無条件に `.replace()`
  している非対称な実装だったと判明。実害: create() が None を返すと
  `AttributeError: 'NoneType' object has no attribute 'replace'` という素の Exception が
  送出される。これは `exceptions.MpdAckError` のサブクラスではないため
  `mopidy_mpd/dispatcher.py` の `_catch_mpd_ack_errors_filter` に捕捉されず、
  `mopidy_mpd/session.py` の `on_line_received` にも try/except が無いため pykka アクターの
  `on_receive` の外まで伝播し `network.LineProtocol.on_failure`
  (`self.connection.stop("Actor failed.")`) に到達する。結果、クライアントには ACK エラーが
  一切返らずTCP接続そのものが問答無用で切断される (rmpc から見れば `rename` を送っただけで
  サーバーとの接続が落ちる)。
  verified: mpdrenamefix-patch.py。`_create_playlist()`/`playlistadd`/`playlistclear` 等と
  同じ流儀で、create() 直後に `if new_playlist is None: raise
  exceptions.MpdFailedToSavePlaylist(uri_scheme)` を追加 (以後の `.replace()`/`save()` には
  到達させない)。パッチ適用後の生成ソースは一時コピーに `chmod u+w` して `ast.parse` で構文
  確認、2回適用しても冪等(スキップ)であることも確認。まず `mopidy_mpd.protocol.
  stored_playlists.rename()` を `context.core.playlists.create()` が None を返すよう
  MagicMock でスタブしたユニットテストで直接呼び出し、(a) 修正前(パッチ未適用)の
  site-packages に対する同テストでは実際に `AttributeError: 'NoneType' object has no
  attribute 'replace'` が飛ぶこと (=不具合の実在)、(b) 修正後は `AttributeError` ではなく
  `exceptions.MpdFailedToSavePlaylist` (`exceptions.MpdAckError` のサブクラスであり
  dispatcher が正しく捕捉してACKへ変換できることも `isinstance` で確認) が送出されることを、
  同一のパッチ済み/未パッチの2つの site-packages を切り替えて対比確認。実機検証:
  dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD を直接叩いて確認 —
  `save "RenameFixTest1"` → `listplaylists`(`RenameFixTest1`) → `rename "RenameFixTest1"
  "RenameFixTest2"` → OK・`listplaylists`(`RenameFixTest2`のみ、旧名は消滅) →
  直後の `status` で接続が生きていることを確認 (=成功パスの回帰なし)、`rm
  "RenameFixTest2"` で後始末。旧来の `tagtypes`/`search any "yoasobi"`/`listplaylists`の
  回帰なし・mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mopidy_mpd/protocol/command_list.py` の `command_list_end()` が、ネストされた
  `command_list_begin`/`command_list_ok_begin` をキュー内の1コマンドとしてそのまま
  `context.dispatcher.handle_request()` 経由で再実行し、セッションが以後一切応答を
  返さなくなる (静かにハングして固着する) 不具合。TODO 全項目消化済みのため自走エージェントが
  `command_list.py`/`dispatcher.py` を再調査して発見した項目。実MPD (src/client/Process.cxx
  の `ProcessCommandList`、`AllCommands.cxx`) は `command_list_begin` を一般コマンドテーブルに
  登録しておらず、list実行中にネストして紛れ込んでも「unknown command」ACKで即座に打ち切られ
  状態破壊は起きないが、mopidy_mpd は `protocol.commands.add("command_list_begin", ...)` で
  通常コマンドと同じディスパッチテーブルに登録しているため非対称になっていたと判明。原因:
  `dispatcher.py` の `_command_list_filter` は list受信中 (`command_list_receiving=True`) の
  間、受け取ったリクエスト文字列を実行せずそのまま `self.command_list` へキューするだけ
  (ハンドラは呼ばれない) だが、`command_list_end()` はループ開始前に一度
  `command_list_receiving=False` に戻した後、キューされた各コマンド文字列
  (ネストされた `command_list_begin` の文字列も含む) を `handle_request()` で
  フルの再ディスパッチにかける。この再ディスパッチ時点では既に `command_list_receiving`
  は False に戻っているため、ネストされた `command_list_begin` の本物のハンドラが実際に
  実行されて `command_list_receiving=True`/`command_list=[]` へ**ループの途中で**書き戻して
  しまい、直後の残りのキュー内コマンド (例: `ping`) が `_command_list_filter` に
  「まだ受信中」と誤認されて実行されずキューへ再投入される。`command_list_end()` は
  ループ後に `command_list_receiving` を再確認・リセットしないため、この状態はループ終了後も
  残り続ける。実害: クライアントには `command_list_end` に対しエラー無く `OK` が一つ
  返るだけで、list内の後続コマンドは一切実行されず、かつ以後そのTCP接続上でどんなコマンドを
  送っても `session.py` の `if not response: return` によって一切応答が返らなくなる
  (クライアントが偶然もう一度 `command_list_end` を送らない限り復旧しない静かな
  ハング固着)。
  verified: mpdcmdlistnest-patch.py。実MPDと同じ挙動 (list実行中の
  `command_list_begin`/`command_list_ok_begin` は「unknown command」ACKで即座に list処理を
  打ち切る) を、`command_list_end()` のリプレイループ内でトークンを見て
  `handle_request()` へ渡す前に弾くことで再現 (ハンドラ自体を呼ばないため
  `command_list_receiving` の書き戻りが起こり得ない構造に修正)。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)である
  ことも確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し MPD を直接叩いて確認 —
  修正前ロジックの再現確認込みで、`command_list_begin` / `command_list_begin` / `ping` /
  `command_list_end` → `ACK [5@0] {} unknown command "command_list_begin"`
  (list即座に打ち切り)、直後の同一接続への `status` → 正常応答 (ハングせず生存)、
  `command_list_begin` / `command_list_ok_begin` / `ping` / `command_list_end`
  (もう一方の入れ子パターン) → 同様に `ACK [5@0] {} unknown command
  "command_list_ok_begin"`、直後の `ping` → `OK` (ハングせず生存)。旧来の非ネスト
  `command_list_begin ... command_list_end` (`ping`+`status`) → 正常に `status` 応答+`OK`、
  `command_list_ok_begin ... command_list_end` (`ping`×2) → `list_OK`×2+`OK`
  (list_OK付与の回帰なし)、list内の実在しないコマンドでの従来のエラー処理
  (`command_list_begin`/`ping`/`bogus_command_xyz`/`ping`/`command_list_end`) →
  `ACK [5@1] {} unknown command "bogus_command_xyz"` (正しいindexで打ち切り、回帰なし)、
  旧来の `tagtypes`/`status` の回帰なし。mopidy.log に Traceback/ERROR 0件を確認。
- [x] `prio`/`prioid` の tlid->優先度ストア `_queue_priorities` (translator.py) だけ、
  同種の揮発性ストア `_queue_added`(mpdadded-patch.py)・`_queue_extra_tags`/`_queue_ranges`
  (mpdaddtagid-patch.py/mpdrangeid-patch.py) と違い、actor.py の `tracklist_changed`
  イベントで掃除されず、`delete`/`clear`等でキューから除去された曲のPrioが tlid ごと
  永久に居座り続ける(プロセス内でtlidは再利用されないため誤表示の実害は無いが)メモリ
  リークだった。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが
  translator.py/actor.py の揮発性ストア群を横断調査して新規発見・追加した項目。
  verified: mpdprioleak-patch.py。`_queue_added`/`_queue_extra_tags`/`_queue_ranges` と対称に
  translator.py へ `sync_priorities(current_tlids)` を追加し、actor.py の
  `_sync_added_timestamps`/`_sync_extra_tags`/`_sync_ranges` と並べて `_sync_priorities()` を
  新設、`on_event` の `tracklist_changed` 分岐に追加。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  ビルド済み env の実モジュールを importlib で単独ロードし `sync_priorities([3])`
  (tlid 1,2削除・3生存)を直接呼び出して `_queue_priorities` が `{1:50,2:80,3:20}` から
  `{3:20}` へ正しく縮小すること、`sync_priorities([])`(全削除)で `{}` になることを確認
  (actor.py は `mopidy.core`→GStreamer依存で単独importが不可のため、配線自体は実ソース
  `grep`で `_sync_added_timestamps`/`_sync_extra_tags`/`_sync_ranges`と完全に同じ形で
  `_sync_priorities`が追加されていることを確認)。実機検証: dev mopidy(6601, ytmusic
  実アカウント) を実際に起動しMPDで確認 — `searchadd any "YOASOBI"`→2曲キュー投入、
  `prio 50 "0:2"`→`playlistinfo`で両曲に`Prio: 50`反映、`delete "0:2"`→空キュー(旧来動作の
  回帰なし)。`prioid ID 0`(明示リセット、既存のset_priority直接パスの回帰なし)も確認。
  旧来の`tagtypes`/`status`/`count any`/`list album`の回帰なし・mopidy.log に
  Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic.library.py` の `parseSearch()` のうち、実際のリリース年 (`year`) を
  持つ3箇所 (`resultType=="album"`分岐、`resultType=="artist"`分岐の
  `get_artist_albums()`/`artistq["albums"]["results"]` 経由のalbums、同分岐のsingles) が、
  いずれも `if X["browseId"] not in self.ALBUMS:` というガードの内側でのみ `self.ALBUMS`
  を構築しており、同じ browseId のアルバムが先に他経路 (`resultType=="song"`分岐、
  `playlistToTracks()`、`uploadArtistToTracks()`。いずれも `date="0000"` 固定の
  プレースホルダしか作れない) で `self.ALBUMS` に登録済みだと、実在する year を一切
  反映せず古いプレースホルダを永久に使い続ける不具合。TODO/既知の軽微な残課題を全項目
  消化済みのため自走エージェントが調査して新規発見・追加した項目。
  原因: ytstalecache-patch.py が `self.TRACKS` について「一度でも簡易版で書き込まれると
  二度と豊富なデータで上書きされない」不具合を修正し、ytalbumfix-patch.py/
  ytuploadfix-patch.py が `albumToTracks()`/`uploadAlbumToTracks()` の `self.ALBUMS`
  ガードを既に無条件上書きに修正済みだったが、`parseSearch()` 内の上記3箇所の
  `self.ALBUMS` ガードだけ対称性が欠けたまま残っていた (`resultType=="song"`分岐・
  artist経由songs分岐の `self.ALBUMS` ガードは `date="0000"` しか作れず実データを
  持たないため、上書き済みでも意味がなく対象外と判断)。実害: mopidy再起動直後に
  「同じアルバムの曲」を含む search/find が先に `resultType=="song"` 側でヒットすると、
  そのアルバムは `date="0000"` のまま `self.ALBUMS` に焼き付く。続けて
  `find album "NAME"`/`search album "NAME"` (`resultType=="album"`分岐) や
  `find artist "ARTIST"` 由来のアーティストブラウズ (`get_artist_albums()`/singles) で
  同じ browseId が実際の year を伴って返ってきても反映されず、以後 mopidy プロセスの
  寿命が尽きるまで `Date: 0000` を返し続け、rmpc のアルバム年表示・`sort Date` を汚染する。
  verified: ytalbumstale-patch.py。3箇所の `if X not in self.ALBUMS:` を
  `if True:  # ...(既存分のdateが古い場合でも実データで上書きする)` へ変更し、常に最新の
  year で `self.ALBUMS` を再構築 (comment-outでガードの意図を残しつつ無条件上書きにする、
  ytalbumfix-patch.py等と同じ方針)。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  パッチ登録前(旧ビルド, nix store保持済み)と登録後の2つの `library.py` を用意し、
  `YTMusicLibraryProvider.parseSearch()` を `self.backend`/`self.ARTISTS`/`self.ALBUMS`/
  `self.TRACKS`/`self.IMAGES` をダミーにした最小 harness から直接呼び出す before/after
  比較で不具合の実在と修正を確認 — (1) `resultType=="album"`分岐: song分岐で
  `ALBUMS['ALBUM1'].date` が `'0000'` プレースホルダになった後、`year="2019"` を持つ
  album分岐ヒットを流すと、旧版は `'0000'` のまま(バグ再現)、新版は `'2019'` に更新
  (修正確認)。(2) `resultType=="artist"`分岐の albums["results"]/singles["results"]:
  同様に song分岐で `ALBUM2`/`SINGLE1` を `'0000'` で焼き付けた後、`get_artist()` を
  スタブして `year="2021"`/`year="2022"` を返す artist分岐ヒットを流すと、旧版は両方
  `'0000'` のまま、新版は `'2021'`/`'2022'` に正しく更新。実機検証: dev mopidy(6601,
  ytmusic 実アカウント) を実際に起動し `search any "YOASOBI"` で実データの
  `Album: THE BOOK for, / Date: 2026`(album分岐、実年が即座に正しく反映)を確認、
  旧来の `tagtypes`/`status`/`list album` の回帰なしを確認、mopidy.log に
  mopidy_ytmusic関連のTraceback/ERROR 0件を確認 (SIGTERM終了時の
  `mopidy_mpd/network.py` 由来の既存無関係なsocket shutdown ERRORのみ、本パッチの
  スコープ外)。
- [x] `mopidy_ytmusic.library.py` の `lookup()` (add/findadd/playlistadd 等、
  `core.library.lookup()` 経由で呼ばれる唯一の変換経路) が、アップロード済みアーティスト
  (`ytmusic:artist:<id>:upload`) に対してだけ誤った変換関数 `artistToTracks()` (dict前提)
  を呼び、`get_library_upload_artist()` の戻り値 (list) を渡すため必ず
  `AttributeError: 'list' object has no attribute 'get'` になり握り潰され、以後
  `lookup()` 末尾のフォールバックがアーティストのbrowseIdをトラックIDとして
  `getTrack()` に渡してさらに壊れる不具合。TODO/既知の軽微な残課題を全項目消化済みのため
  自走エージェントが調査して新規発見・追加した項目。
  原因: 同じ URI を `browse()` (446-448行目) で辿ると `uploadArtistToTracks(res)` を
  正しく呼んでいるのに、`lookup()` (540行目) だけ `artistToTracks(res)` を呼んでおり非対称。
  `uploadArtistToTracks(artist)` は `for track in artist:` と list 前提、
  `artistToTracks(artist)` は `artist.get("songs")` と dict (`get_artist()`の戻り値) 前提で、
  データ形状が根本的に異なる。実害: YouTube Music の「アップロード済み楽曲」ライブラリを
  持つアカウントで、browse では曲一覧が見えているアップロードアーティストを
  add/findadd/playlistadd すると、エラー表示もされず常に0曲になる(静かな機能不全)。
  verified: ytuploadartistlookup-patch.py。`lookup()`のアップロードアーティスト分岐を
  `browse()`と対称に`uploadArtistToTracks(res)`へ変更。パッチ適用後の生成ソースは
  一時コピーに`chmod u+w`して`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  パッチ登録前(旧ビルド, nix store保持済み)と登録後の2つの`library.py`を用意し、
  `YTMusicLibraryProvider.lookup()`を`self.backend`/`self.ARTISTS`/`self.ALBUMS`/`self.TRACKS`/
  `self.IMAGES`をダミーにした最小harnessから、`get_library_upload_artist()`が実際の戻り値形状
  (videoId/title/artists/album等を持つ生トラック辞書のlist、2件)を返すスタブ付きで
  `ytmusic:artist:UCxxxxxxxx:upload`をlookupする before/after 比較で不具合の実在と修正を確認 —
  旧版は`AttributeError: 'list' object has no attribute 'get'`(artistToTracks内)が発生し、
  さらにフォールバックが`FakeApi.get_song`不在で`AttributeError`を再送出してlookup()全体が
  例外で終了(バグ再現)、新版は`uploadArtistToTracks(res)`が正しく機能し
  `Track(name='Song One', ...)`/`Track(name='Song Two', ...)`の2曲を正常に返す(修正確認)。
  実機検証: dev mopidy(6601, ytmusic実アカウント)を実際に起動し`status`/`tagtypes`/`lsinfo`/
  `lsinfo "YouTube Music"`/`search any "yoasobi"`/`list album`/`stats`の回帰なしを確認、
  mopidy.logにlookup()/artistToTracks()/uploadArtistToTracks()関連のTraceback/ERROR 0件を確認
  (該当アカウントに認証済みLiked Songsアクセス権が無いことに起因する既存の無関係な
  `get_liked_songs()`/`nav()` KeyErrorのみ、本パッチのスコープ外・自分のテスト操作由来)。
- [x] `mopidy_ytmusic.library.py` の `parseSearch()` の `resultType=="song"` 分岐が、album を
  `self.ALBUMS` キャッシュへ「新規登録した時だけ」album 変数へ代入し、既に登録済み
  (キャッシュヒット)の場合は `album=None` のまま `Track` を組み立ててしまう不具合。
  ytstalecache-patch.py (self.TRACKS の陳腐化キャッシュ修正) 対応時に本 BACKLOG へ
  「今回のスコープ外としてそのまま温存」と明記されていた既知の予備的な癖で、TODO/既知の
  残課題を全項目消化済みのため自走エージェントが改めて調査し着手した。
  原因: `album = self.ALBUMS[result["album"]["id"]]` が `if result["album"]["id"] not in
  self.ALBUMS:` の内側にネストしており、新規登録時にしか実行されない。同じ関数の
  `playlistToTracks()` や、同分岐内のartist経由songsループ (`"songs" in artistq` の分岐) は
  `album = self.ALBUMS[...]` を if の外側に置いており対称になっているのに、song分岐だけが
  非対称だった。実害: search/find の結果に同一アルバムの曲が複数含まれる場合(あるいは
  同じクエリ結果に album カード自体も含まれ先に self.ALBUMS へ登録される場合)、最初の
  1曲だけ Album/AlbumArtist/X-AlbumUri が付き、2曲目以降は mopidy プロセスの残り寿命
  ずっと album=None になり、rmpc の Album によるグルーピング・ナビゲーションが壊れる。
  verified: ytsongalbumcache-patch.py。`album = self.ALBUMS[...]` を内側のifから外側へ
  デデントし、キャッシュヒット時も常に代入されるよう修正 (playlistToTracks()と同じ流儀に
  統一)。パッチ適用後の生成ソースは一時コピーに`chmod u+w`して`ast.parse`で構文確認、
  2回適用しても(アンカー不一致で)例外になり冪等にスキップされないことを確認。namedtuple
  ベースの最小harnessで新旧ロジックのbefore/after比較を実施 — 同一アルバムIDを共有する
  2曲を順に処理させたところ、旧ロジックは1曲目のみalbum取得・2曲目はalbum=None(不具合の
  実在を確認)、新ロジックは両曲ともalbum取得(修正確認)。実機検証: dev mopidy(6601,
  ytmusic実アカウント)を実際に起動し MPD で確認 — `search Title "Brand New"` で
  アルバム`Deja Entendu`(MPREb_4vHE1Z163Pg)を共有する3曲、`search Title "Lilac"` で
  アルバム`IU 5th Album 'LILAC'`(MPREb_iG5q5DIdhdA)を共有する2曲が、いずれも全曲
  `Album:`/`AlbumArtist:`/`X-AlbumUri:` 付きで正しく返ることを確認(パッチ前なら2曲目以降は
  欠落していたはずの箇所)。`status`/`tagtypes`/`list album`/`count any "yoasobi"`
  (songs:2/playtime:469) の回帰なし、mopidy.log に parseSearch()/library.py関連の
  Traceback/ERROR 0件を確認(残る4件のTracebackは自分のテストスクリプトが`close`直後に
  ソケットを切断したことによる mopidy_mpd 自体の無関係な `ActorDeadError` のみ)。
- [x] `mopidy_mpd.uri_mapper.MpdUriMapper.playlist_name_from_uri()` が、キャッシュミス後の
  `refresh_playlists_mapping()` でも見つからない場合に素の dict インデックス
  `self._playlist_name_from_uri[uri]` で `KeyError` を投げる不具合。TODO/既知の残課題を
  全項目消化済みのため自走エージェントが改めて mopidy_mpd のコード品質を再調査して発見した。
  姉妹関数 `playlist_uri_from_name()` は同じ「キャッシュミス→refresh→再検索」パターンで
  `.get(name)` を使い安全に None を返すのに対し非対称だった。実害の引き金:
  `mopidy_ytmusic.playlist.YTMusicPlaylistsProvider.as_list()` は
  `get_library_playlists()`(実ネットワーク呼び出し)が例外を投げると空リストへ
  フォールバックする設計。`protocol/stored_playlists.py` の `listplaylists()` は
  1) `core.playlists.as_list().get()` で一覧取得 → 2) 各 uri を
  `lookup_playlist_name_from_uri()` で解決、という2段構成で、名前キャッシュが
  空(起動直後等)だと 2) の内部で `refresh_playlists_mapping()` が as_list() を
  「もう一度」呼び直す。1回目は成功したのに2回目だけ瞬断/レート制限等で失敗すると
  空リストへのフォールバックにより既存キャッシュが丸ごと stale 扱いで破棄され、
  1回目のスナップショットに実在した uri がキャッシュに無いまま `[uri]` に到達し
  `KeyError`。`exceptions.MpdAckError` のサブクラスではないため
  `_catch_mpd_ack_errors_filter` に捕捉されず、素の例外が pykka アクターの外まで
  伝播して接続が問答無用で切断される(rmpc から見れば `listplaylists` を送っただけで
  サーバーとの接続が落ちる)。
  verified: mpdplaylistnamerace-patch.py。`playlist_name_from_uri()` を
  `playlist_uri_from_name()` と対称に `.get(uri)` へ変更、唯一の呼び出し元
  `listplaylists()` は None を受け取ったエントリだけ `continue` でスキップするよう修正。
  パッチ適用後の生成ソースは一時コピーに `chmod u+w` して `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることを確認。まず namedtuple ベースの最小harnessで
  「1回目の as_list() は実データ、2回目(refresh内)は瞬断を模した空リスト」を返す
  FlakyCore を用意し before/after 比較 — 旧版は `KeyError: 'ytmusic:playlist:P1'`
  (不具合の実在を確認)、新版は `None` を安全に返す(修正確認)。さらに実際の MPD
  プロトコルでも確認: pkg_resources entry_points で `/tmp` に dist-info 付きの
  テスト用スタブ拡張(1回目の `as_list()` は2件のプレイリストを返し2回目以降は
  空にフォールバックする `FlakyPlaylistsProvider`)を作成し、別ポート(6602)で
  patched/pre-patch 両方の mopidy を起動して `listplaylists` を実送信 — pre-patch は
  実際に接続が `<EOF>` で切断され mopidy.log に本不具合と同じ
  `KeyError: 'teststub:playlist:P1'` の Traceback を確認(不具合の実在を実プロトコルで
  再現)、patched 版は `OK`(空応答、接続維持)を確認(修正確認)。dev mopidy
  (6601, ytmusic実アカウント)でも `listplaylists`/`status`/`stats`/`lsinfo`/
  `search any "yoasobi"` の回帰なし、mopidy.log に Traceback 0件を確認。
- [x] `mopidy_ytmusic/playback.py` の `update_cipher()` が唯一 try/except による保護を
  持たず、バックグラウンドの `youtube_player_refresh` タイマースレッド (デフォルト15分
  間隔) を永久停止させうる不具合: TODO/既知の軽微な残課題を全項目消化済みのため
  自走エージェントが mopidy_ytmusic のコード品質を再調査 (ytscrobble-patch.py 等
  これまでの一連の発見的パッチと同じ流儀) して発見した項目。
  verified: ytcipherfail-patch.py。`backend.py` の `on_start()` は
  `RepeatingTimer(self._refresh_youtube_player, ...)` という素の `threading.Thread`
  サブクラスを起動するが、`repeating_timer.py` の `RepeatingTimer.run()` は
  `self._method()` の呼び出しを一切 try/except で保護していない。
  `_refresh_youtube_player()` 自身も無保護で、`self._get_youtube_player()`
  (music.youtube.com への1回目のHTTP GET、こちらは try/except Exception:
  logger.exception(...) で保護済み) の戻り値URLが変化していれば
  `self.playback.update_cipher(playerurl=url)` を呼ぶ。`update_cipher()` は
  このURLへの2回目のHTTP GET (`requests.get("https://music.youtube.com" + playerurl)`)
  を無保護で行っており、同ファイル内の他の外部API呼び出しメソッド
  (`_get_youtube_player()`/`_get_auto_playlists()`/`scrobble_track()`、いずれも
  保護済み)と非対称だった。タイムアウト/DNS失敗/接続断/5xx等でこのGETが例外を
  投げると、例外は `update_cipher()` → `_refresh_youtube_player()` →
  `RepeatingTimer.run()` と無捕捉のまま伝播し `run()` 自体が終了、スレッドが
  その場で死ぬ。`cancel()`を呼ぶ主体もいないため以後 `signatureTimestamp`/
  `Youtube_Player_URL` は自己復旧なしに二度と更新されない (mopidy.log への
  一度きりのTracebackのみで通知も無い)。長時間稼働するmacmini常駐サーバでは
  15分間隔のうち一度でもネットワーク瞬断が起きれば十分再現し、以後
  `scrobble_track()` が送る `signatureTimestamp` が陳腐化したまま静かに劣化し
  続ける実害がある。対策: 他の外部API呼び出しメソッドと同じ流儀でHTTP GET以降を
  try/except Exceptionで包み、失敗時は logger.exception でログするだけに留めて
  スレッドを止めないよう修正。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w`して`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることを
  確認。まずbefore/after比較の最小harnessで実証: `requests.get`を常に例外を送出する
  スタブへ差し替えた `mopidy_ytmusic.playback` を実際にimportし
  `update_cipher()` を直接呼び出したところ、パッチ前は
  `Timeout('simulated network failure')` が無捕捉のまま呼び出し元まで伝播すること
  (=RepeatingTimerスレッドが死ぬ再現条件の実在)を確認、パッチ後は同じ例外が
  `logger.exception`でログされるのみで正常に戻り値`None`を返しスレッドが
  生存し続けることを確認。パッチ済みenvのdev mopidy(6601, ytmusic実アカウント)を
  実際にビルド・起動しクリーンな起動(Traceback/ERROR 0件、YTMusic Auto
  Playlists正常ロード)を確認した上で、実際のMPDプロトコルで
  `status`/`search any "yoasobi"`/`tagtypes`を実送信し正常応答・回帰なし・
  mopidy.log に Traceback/ERROR 0件(累計)を確認。
- [x] `mopidy_ytmusic.library.py` の `lookup()` のうち、URIが album/artist/playlist の
  いずれのprefixにも一致しない単曲URI (`ytmusic:track:<id>`) を解決する末尾の分岐
  `return [self.getTrack(bId)]` だけが try/except による保護を持たず、`getTrack()` が
  例外を投げるとそのまま呼び出し元へ伝播する不具合。TODO/既知の軽微な残課題を全項目
  消化済みのため自走エージェントが mopidy_ytmusic のコード品質を再調査
  (ytcipherfail-patch.py 等これまでの一連の発見的パッチと同じ流儀) して発見した項目。
  `lookup()` の album/artist(アップロード含む)/playlist の4分岐はいずれも
  try/except で保護されている一方この分岐だけ非対称で、`browse()` 側の同じ
  `getTrack()` 呼び出し (`ytmusic:track:` prefix分岐) はちゃんと保護済みだった。
  verified: ytlookuptrackfail-patch.py。`getTrack()` 内部の
  `self.backend.api.get_song(bId)` (ytmusicapi mixins/browsing.py) は "player"
  innertube エンドポイントをそのまま叩くだけで playabilityStatus を検証しないため、
  動画が削除/非公開/地域制限で再生不能だとレスポンスに `videoDetails` キー自体が
  無く `tv = track["videoDetails"]` が素の `KeyError` を投げる。mopidy core の
  `CoreLibrary.lookup()` は `_backend_error_handling` で最終的に例外を捕捉するため
  接続断や恒久停止はしないが、「backend caused an exception」という汎用メッセージで
  生のTracebackが出るだけになり、どの `bId` が失敗したのか分からずデバッグが困難に
  なる実害を確認した上で追加した項目。対策は `browse()` 側の同じ呼び出しと対称に
  try/except で包み、他の分岐と同じ書式で `logger.exception('YTMusic failed to get
  track "%s"', bId)` して空リストへフォールバック。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。パッチ済み env の dev mopidy(6601, ytmusic
  実アカウント) を実際にビルド・起動し MPD で確認 — 正常系: 未キャッシュの実在動画ID
  `add "ytmusic:track:dQw4w9WgXcQ"` → OK・`playlistinfo` にArtist/Title/Time
  含むフル情報で反映 (getTrack()のキャッシュ未ヒット成功パスの回帰なし)。異常系:
  存在しない動画ID `add "ytmusic:track:AAAAAAAAAAA"` → 実際に
  `KeyError: 'videoDetails'` を再現させた上で、mopidy.log に
  `YTMusic failed to get track "AAAAAAAAAAA"` と`bId`付きの具体的なTracebackが
  記録されつつ、MPD応答は接続断せず通常の `ACK [50@0] {add} directory or file not
  found` (他の解決不能URIと同じ経路) に収まり、直後の `playlistinfo`/`status` も
  正常応答 (接続生存・キュー未変化) を確認。旧来の `tagtypes`/`list album`/
  `search any "yoasobi" window "0:1"`/`status`/`listplaylists` の回帰なし・
  意図的に踏んだ1件を除き Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic` の設定 `verify_track_url` (ext.conf既定 `yes`、`__init__.py`で
  `config.Boolean(optional=True)`宣言、`backend.py`の`__init__`で`self.verify_track_url`
  へ読み込み済み) が実際には`playback.py`のどこからも参照されておらず完全な死に設定に
  なっていた不具合。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが
  mopidy_ytmusicのコード品質を再調査(ytcipherfail-patch.py等これまでの一連の発見的
  パッチと同じ流儀)して発見した項目。gh api経由でアップストリーム
  (github.com/OzymandiasTheGreat/mopidy-ytmusic)の素の`_get_track()`を実際に取得し
  確認したところ、pytubeベースの原実装には
  `if self.backend.verify_track_url and requests.head(url).status_code == 403: ...`
  という「実際にURLが403で弾かれていないか確認してから返す」ガードが存在していたが、
  ytdlp-patch.pyがpytube由来のcipher解読破損を回避するため`_get_track()`をyt-dlp委譲へ
  全面書き換えした際にこのガード節ごと丸ごと削除され、以後`verify_track_url`の値が
  どう変わっても一切の副作用が無いまま今日に至っていたと確定。yt-dlpが解決する
  googlevideo.comの直リンクはIP不一致・レート制限・期限切れ等で稀に実際に403を返す
  個体が混じり(`extract_info(download=False)`時点ではダウンロードされないため
  yt-dlp自身の検証は効かない)、`verify_track_url`を有効にしていても何も確認されず
  そのままGStreamerに渡り再生が静かに失敗する実害があった。
  verified: ytverifytrackurl-patch.py。yt-dlp解決フローに合わせ、URL解決成功後
  (asr/audio_channels記録の直前)に`self.backend.verify_track_url`が真ならHEADリクエストで
  実際に403を返さないか確認し、403ならログを残しNoneを返して`translate_uri()`に
  「解決失敗」として扱わせる(アップストリームの意図と対称、yt-dlpは独自にcipherを
  解読するため`_youtube_player_refresh_timer.now()`によるpytube cipher自己修復呼び出しは
  現構成には適用できず移植しない)。HEAD自体が例外を投げた場合(タイムアウト・DNS失敗等)
  はdebugログのみで握りつぶし通常どおり再生を試みる(誤検知で再生機会を奪わない)。
  パッチ適用後の生成ソースは一時コピーに`chmod u+w`して`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic実アカウント)を
  実際にビルド・起動しMPDで確認 — `search any "yoasobi"`でヒットした実トラックを
  `add`/`play`したところ、1曲目(by4SYYWlhEs)はyt-dlp解決URLが実際に403 Forbiddenを
  返す個体であることが本パッチにより実際に検出され、mopidy.logに
  `YTMusic yt-dlp resolved URL for by4SYYWlhEs returned 403 Forbidden, treating as
  unplayable`+`Track is not playable`が記録され再生は`state: stop`のまま安全に失敗
  (本不具合が実際に実害を生む条件そのものを実データで再現・修正確認)。別トラック
  (fCh0qfxElm8)はHEAD検証を通過し`state: play`・`audio: 48000:16:2`で正常再生開始
  (verify_track_url有効時も正当なURLの再生を妨げないことを確認)。旧来の`tagtypes`/
  `listplaylists`/`count any "yoasobi"`/`status`の回帰なし、意図的に踏んだ1件を除き
  mopidy.log にTraceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic.library.py` の `search()` の `query["uri"]` 分岐 (MPD の `find`/`search`
  の `file`/`filename` タグ、`mopidy_mpd/protocol/music_db.py` の TAG_MAP で
  `"file"`/`"filename"` -> `"uri"` にマップされ、`mopidy.core.Library.search()` の
  docstring 上も `uri`/`track_name`/`album`/... と並ぶ正式フィールド) が `ytmusic:album:`
  の URI しか扱わず、`ytmusic:artist:`/`ytmusic:playlist:`/単曲 `ytmusic:track:` の
  有効な既知 URI を渡しても無条件に `None` (「このバックエンドは非対応」の意味、
  `mopidy.core.Library.search()` はNoneを返したバックエンドの結果を単に無視するだけ)
  を返しヒット0件になっていた不具合。TODO/既知の軽微な残課題を全項目消化済みのため
  自走エージェントが mopidy_ytmusic のコード品質を再調査 (ytverifytrackurl-patch.py等
  これまでの一連の発見的パッチと同じ流儀) して発見した項目。`lookup()` は既に
  album(通常/upload)/artist(通常/upload)/playlist/単曲URIの全パターンを
  try/except保護つきで解決済みであるにもかかわらず、`search()`のuri分岐だけ
  そのロジックを再実装せず album 限定の劣化コピーになっていたことが原因。
  verified: ytsearchuri-patch.py。uri分岐を`self.lookup(uri)`への委譲に置き換え
  (ytmusicスキーム以外のURIは従来通り`None`を返し他バックエンド管轄と明示)、
  重複コードを消しつつ対応範囲をlookup()と同等まで拡大。パッチ適用後の生成ソースは
  一時コピーに`chmod u+w`して`ast.parse`で構文確認、2回適用しても冪等(スキップ)
  であることも確認。dev mopidy(6601, ytmusic実アカウント)を実際にビルド・起動し
  MPDで実機確認 — `search any "yoasobi"`/`search artist "yoasobi"`で実トラック
  (ytmusic:track:by4SYYWlhEs)・実アーティスト(ytmusic:artist:UCI6B8NkZKqlFWoiC_xE-hzA
  = YOASOBI)・実アルバム(ytmusic:album:MPREb_a5PIYyducZQ)のURIを取得、HTTP
  JSON-RPC(6681)の`core.library.browse`で実プレイリストURI
  (ytmusic:playlist:VLRDCLAK5uy_lMzHW51iFg1Kx0d_2EHpzbOgCrwtu8cgI, Auto Playlists
  経由)も取得した上で、`find file "ytmusic:track:by4SYYWlhEs"`→修正前は0件のところ
  該当1曲がフルタグで返る、`find file "ytmusic:artist:UCI6B8NkZKqlFWoiC_xE-hzA"`→
  修正前は0件のところYOASOBIの実トラック群が返る、`find filename
  "ytmusic:playlist:VLRDCLAK5uy_lMzHW51iFg1Kx0d_2EHpzbOgCrwtu8cgI"`→修正前は0件の
  ところプレイリスト実トラック群(Michael Jackson - Beat It 等)が返る、を確認。
  `find file "ytmusic:album:MPREb_a5PIYyducZQ"`(既存対応分)は修正前後で同じ
  アルバム全曲が返り回帰なしを確認。エッジケース: 他バックエンド宛と想定される
  `find file "file:///nonexistent.mp3"`(ytmusicスキームでないURI)→従来通り
  空でOK(クラッシュなし)、存在しない`find file "ytmusic:bogus:xyz"`→lookup()内部の
  既存のtry/except保護によりgetTrack()失敗がログ1件(意図的に踏んだ想定通りの
  ケース)に留まり空でOK応答・接続維持を確認。旧来の`tagtypes`/`list album`/
  `count any "yoasobi"`/`listplaylists`/`search any "yoasobi" sort -Date window
  "0:2"`の回帰なし、意図的に踏んだ1件を除きmopidy.log にTraceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic/scrobble_fe.py` の `YTMusicScrobbleFE.track_playback_ended()` が
  duration不明(0)の曲に対してscrobble閾値判定を実質無効化してしまう不具合。TODO/既知の
  軽微な残課題を全項目消化済みのため自走エージェントが mopidy_ytmusic のコード品質を
  再調査 (ytverifytrackurl-patch.py/ytsearchuri-patch.py 等これまでの一連の発見的パッチと
  同じ流儀) して発見した項目。原文は `duration = track.length and track.length // 1000
  or 0` の後 `if time_position < duration // 2 and time_position < 120: return`
  (scrobbleしない)という判定で、意図は「50%以上 or 120秒以上再生した場合のみscrobble」
  だが、duration不明(track.length が None/0)のとき `duration // 2` が0になり
  `time_position < 0` が0以上の整数に対し常に偽になるため `and` 全体が常に偽になり
  return に到達せず、再生時間に関わらず常にscrobbleされてしまう。duration不明は
  library.py の曲パース経路 (parseSearch/playlistToTracks/artistToTracks 等が
  duration_seconds/duration/length 全欠落時に length=0 のTrackを生成) で実データとして
  起こりうる。実害: enable_scrobbling有効時、rmpc等で曲を数秒プレビュー再生してすぐ
  スキップしても、duration不明の曲だけ無条件で「最後まで聴いた」としてYouTube Music
  側の再生履歴・レコメンドへ記録されてしまう。
  verified: ytscrobblethreshold-patch.py。duration不明時は120秒閾値のみへフォールバック
  する判定 (`if duration: long_enough = time_position >= duration//2 or
  time_position >= 120 else: long_enough = time_position >= 120`) に置換。
  パッチ適用後の生成ソースは一時コピーに`chmod u+w`して`ast.parse`で構文確認、2回適用
  しても冪等(スキップ)であることも確認。GStreamer依存で単体import不可能な
  `mopidy`/`pykka`をスタブ差し替えし、`track_playback_ended()`のロジックそのものを
  実際に呼び出して検証 — 修正前ロジックでは「duration不明・2秒再生」で即scrobble
  される(バグ再現)ことを対照確認した上で、修正後ロジックで同ケースがscrobbleされない
  (`duration不明・0秒再生`も同様)こと、`duration不明・121秒再生`
  (120秒閾値到達)はscrobbleされること、`duration200秒・60秒再生`(50%未満/120s未満)は
  scrobbleされないこと、`duration200秒・120秒再生`(50%以上)はscrobbleされることを
  全て確認。dev mopidy(6601, ytmusic実アカウント)を実際にビルド・起動し、
  `YTMusicScrobbleFE`フロントエンドの正常起動・`tagtypes`/`status`/`count any "a"`の
  回帰なし・mopidy.log にTraceback/ERROR 0件を確認。
- [x] `mopidy_mpd/protocol/current_playlist.py` の `delete [{POS}|{START:END}]` が、
  実MPDなら「範囲は不正ではないが結果的に空」の境界ケース (`start == キュー長`) でも
  一律 `ACK Bad song index` を返してしまう不具合。TODO/既知の軽微な残課題を全項目
  消化済みのため自走エージェントがmopidy_mpdのコード品質を再調査(mpddeleterace-patch.py
  等これまでの一連の発見的パッチと同じ流儀)して発見した項目。実MPD本体
  (MusicPlayerDaemon/MPD `src/queue/PlaylistEdit.cxx` の `DeleteRange` +
  `src/protocol/RangeArg.hxx` の `CheckClip`/`IsEmpty`) をgh api経由で実際に取得し
  確認したところ、`CheckClip(count)` は `start > count` の場合のみ false
  (`ACK BadRange`) を返し、`start == count` はendを`count`へクリップした上でtrueを
  返す。続けて`range.IsEmpty()`(`start >= end`)が真なら例外を投げず単に`return`する
  (=OKのみで実際には無変更、実害の無い黙示no-op)と確定した。対してこの実装の
  `delete()`は`context.core.tracklist.slice(start, end)`(Pythonのリストスライス)の
  結果が空リストになるケースを「`start > 長さ`(真に範囲外)」「`start == 長さ`
  (境界上の空範囲)」の区別なく一律`ACK Bad song index`にしてしまっており、例えば
  3曲キュー(有効位置0-2)に対し`delete "3"`や`delete "3:"`を送ると、実MPDは
  `OK`(無変更)を返すのにこの実装は`ACK`を返す実害あるプロトコル差異と確認した上で
  追加した項目。
  verified: mpddeleteboundary-patch.py。`mpddeleterace-patch.py`が用意した
  `.get()`同期化済みの`delete()`本体に対する新規パッチとして、`tl_tracks`が空だった
  場合`start > 実際の長さ`のときのみ`ACK Bad song index`を投げ、それ以外
  (`start == 長さ`の境界上の空範囲)は無変更で正常終了させるよう修正 (実MPDの
  CheckClip/IsEmptyと同じ判定に合わせた)。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w`して`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic実アカウント)を実際にビルド・起動しMPDで実機確認 —
  実アルバム(YOASOBI「THE BOOK for,」12曲)を`add`しキューへ展開後`delete "3:"`で
  3曲に整形し、`delete "3"`(start==キュー長3)→修正前は`ACK Bad song index`のところ
  修正後は`OK`のみ・`playlistinfo`で3曲とも無変更を確認、`delete "3:"`(open-ended、
  同じ境界)→同様に`OK`のみ・無変更を確認。回帰確認: `delete "4"`(start>長さ、
  真に範囲外)→従来通り`ACK Bad song index`、`delete "999:1000"`→同様に
  `ACK Bad song index`、通常の`delete "0"`(有効な単曲位置)→`OK`かつ実際に1曲削除
  (`playlistinfo`が3→2曲)、`delete "0:2"`(有効な範囲)→`OK`かつ残り全削除
  (`playlistinfo`が0曲)を確認。旧来の`tagtypes`/`status`の回帰なし、mopidy.log に
  Traceback/ERROR 0件を確認。
- [x] `find`/`findadd`/`count` (`searchcount`/`search`/`searchadd`/`searchaddpl` を除く) が、
  フィルタ式 (`(Tag contains "x")`/`(Tag starts_with "x")`/`(Tag =~ "x")`) の明示的な
  演算子を無視し、backend への丸投げクエリを常に `exact=True` で送ってしまうため、
  mopidy_ytmusic のように `exact=True` 時に自前で casefold 完全一致まで絞り込む backend
  では contains/starts_with/regex を指定した正当な部分一致検索が無条件で0件になる
  不具合。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが
  mpdfilterkind-patch.py 等これまでの一連の発見的パッチと同じ流儀でコード品質を
  再調査して発見した項目。実MPD仕様 (mpd.readthedocs.io/en/latest/protocol.html) を
  WebFetchで確認したところ、`find` の "case sensitive" は search との大小文字区別の
  違いを説明しているだけで、フィルタ式の明示的な演算子はそのまま尊重される (`find`
  だから常に完全一致に強制される、という仕様ではない) と確定した。
  mpdfilterkind-patch.py が実装した `(field, kind, value)` の `positives` リストと、
  それを個々の track 属性に対して直接判定する `_mpd_filter_positives`/
  `_mpd_track_matches_positives` は演算子種別ごとの判定を post-filter として既に
  正しく実装済みだったが、`find()`/`findadd()`/`count()`(経由の`_mpd_count_grouped`
  既定値) はこの positives の有無に関わらず一律 `context.core.library.search(query=query,
  exact=True)` を呼んでおり、mopidy_ytmusic/library.py の `search()` はこの `exact=True`
  を受けると `parseSearch(res, field, query[field])` を呼んで
  `q.casefold() == result["title"/"artist"].casefold() for q in queries` という
  完全一致のみを通す事前フィルタを自前でかけ、post-filterに候補が届く前に部分文字列を
  弾いてしまうことを確認した。`search`/`searchadd`/`searchaddpl`/`searchcount` は
  `exact=False` を渡すためこの問題が起きず、`find` 系だけの非対称なバグと確認した。
  rmpc本体 (mierak/rmpc) を実際に clone してソース確認したところ、
  rmpc/src/ui/panes/search/inputs.rs の `FilterKind` の既定値は `Contains` であり、
  rmpc/src/ui/panes/search/mod.rs は「Case sensitive」トグルがONの状態では `find` を、
  OFFの状態では `search` を送信する。つまり検索ペインで大文字小文字区別トグルをONに
  したまま (既定のContainsモードで) 部分文字列検索する、という誰でも到達する普通の
  操作がこの不具合を踏むと確認した上で着手。
  verified: mpdfindexactfilter-patch.py。`positives` (フィルタ式由来の演算子付き
  肯定条件) が1件でもあれば backend への `exact` を常に False にし、演算子種別
  (==/contains/starts_with/=~) ごとの厳密な判定は既存の post-filter に完全に委ねる
  よう `_mpd_backend_search_exact()` を追加し find/findadd/count の3箇所に適用。
  positives が無い旧来形式 (`find TAG VALUE`) は従来通り exact=True を維持し既存動作を
  変えない。パッチ適用後の生成ソースは一時コピーに`chmod u+w`して`ast.parse`で構文
  確認、2回適用しても冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic実
  アカウント)を実際にビルド・起動しMPDで実機確認 —
  修正前(パッチ未適用の旧env)で`find "(Artist starts_with \"YOA\")"`/
  `find "(Artist contains \"OASOBI\")"`が実際に0件になることを再現した上で、
  修正後の同env再起動後は`find "(Artist starts_with \"YOA\")"`→YOASOBI関連22件
  (アルバム+単曲)がフルタグで返り、`find "(Artist contains \"OASOBI\")"`→
  "OASOBI.NET"を含む実アーティストの候補が正しく返ることを確認。大文字小文字の
  区別 (find は case-sensitive) も`find "(Artist contains \"oasobi\")"`(小文字)→
  0件 (post-filterのcase_sensitive=Trueが機能) で確認。`findadd`も同条件で同じ
  5トラックをキューへ正しく追加 (`playlistinfo`で確認)。`count "(Artist starts_with
  \"YOA\")"`→`songs: 24`(修正前相当の0件から復旧)、`count "(Artist == \"YOASOBI\")"`
  →`songs: 5`。回帰確認: 旧来形式`find artist "YOASOBI"`(演算子省略、暗黙exact)→
  24件で修正前後同一、`find "(Artist == \"YOASOBI\")"`(明示的==)→22件で正しく
  完全一致のみ、`find "(Artist == \"YOA\")"`(非該当の完全一致)→0件、
  `search "(artist starts_with \"YOA\")"`(元々`exact=False`のsearch系)→回帰なし、
  `count "(Artist != \"YOASOBI\")" group artist`(mpdnegonlyfilter-patch.py の
  否定のみ+group経路)→回帰なし、`tagtypes`/`status`の回帰なし、mopidy.log に
  Traceback/ERROR 0件を確認。
- [x] `mopidy_mpd/protocol/current_playlist.py` の raw position 版 `swap {SONG1} {SONG2}`
  (mpdmoveswaprace-patch.py が「範囲外指定でサイレントにOKを返す」不具合は修正済みだが、
  その内部アルゴリズム自体に残っていた別のTOCTOUレース)。TODO/既知の軽微な残課題を
  全項目消化済みのため自走エージェントがmopidy_mpdのコード品質を再調査して発見した項目。
  `swap` は songpos1 < songpos2 として `move(songpos1, songpos1+1, songpos2).get()`
  (move1) → `move(songpos2-1, songpos2, songpos1).get()` (move2) という2回の別々の
  core呼び出しで構成されており、move2 は「move1の後にsongpos2-1という座標に今いる曲」を
  一切確認せず無条件にsongpos1へ戻す実装だった。mopidy/core/tracklist.py の `move()` は
  起点/終点とも純粋なposition指定で動作し曲の同一性は一切見ない(gh api実装確認済み)ため、
  move1の.get()が返ってからmove2が実行されるまでの間に別クライアントがdelete/move等で
  songpos2-1の座標の中身を変えると、move2は無関係な曲を songpos1 へ動かしてしまい、
  ACKは一切出ず`OK`が返るためクライアントはキュー破損に気づけない。rmpc本体
  (mierak/rmpc)をgh apiで確認したところ、`queue_header.rs`の`sort_by_column()`
  (キュー列ヘッダをクリックしてソートする一般的操作)が`calculate_swaps()`で求めた
  複数の(i,j)ペアをcommand_list経由で複数回の生`swap {i} {j}`として一括送信するため、
  この操作中に別クライアントが同時にキューを操作しているとソート結果が静かに破損しうる
  と確認した上で着手。mpdmoveidrace-patch.py はコメントで「move()/swap()本体の呼び出しと
  の間のレースはmpdmoveswaprace-patch.pyが既にAssertionError→ACK Bad song indexで
  吸収済みのためスコープ外」としていたが、これは範囲外に押し出されるケースにしか
  当てはまらず、範囲内に留まる(=例外が起きない)上記のサイレント破損ケースを見落として
  いたと判明した。
  verified: mpdswapstalepos-patch.py。当初はmove2の起点をtlid経由(move1後に都度
  再解決)する案を実装したが、実機の2コネクション継続競合ストレステスト(swapを連打する
  コネクションAに対し、Aの範囲内側だがA自身のsongpos1/songpos2には触れない`move`を
  連打するコネクションBを1秒間ぶつける、を15試行)で検証したところ修正前15試行中14/15
  破損・tlid案適用後も15/15破損と有意な改善が見られず、tlid案は「move2の対象曲の
  取り違え」という1症状のみを塞ぐものでmove1自体の起点や再解決呼び出し自体の間に残る
  別の窓は塞げていないと判明したため、mopidy/core/tracklist.pyのversion(状態変化の
  たびに単調増加、巻き戻り無し。この同じファイルの`plchanges`/`plchangesposid`が既に
  同じ仕組みを使用)による楽観的排他制御に切り替えた: 操作前versionを記録し、move1後に
  version+1と一致するか、move2後にversion+2と一致するかを検証、不一致(=2回のmove間に
  自分以外の変更が割り込んだ)ならACK Bad song indexで打ち切る。パッチ適用後の生成
  ソースは一時コピーに`chmod u+w`して`ast.parse`で構文確認、2回適用しても冪等
  (スキップ)であることも確認。さらにmopidy core本体の実move()/get_version()実装を
  忠実に再現したPythonロジックレベルの検証で、move1とmove2の間に無関係な同時変更が
  割り込む決定的シナリオを再現したところ、旧実装はACK無しで無関係な曲を巻き込み
  サイレントに破損する一方、新実装は同シナリオを正しくACK Bad song indexとして検知
  すること、レース無しの通常swap(1,4)/swap(4,1)/swap(0,5)/swap(2,2)/swap(0,1)は
  新旧で完全に同一の結果になること(回帰無し)、範囲外(0,99)/(99,0)は共にACK Bad song
  indexになることを確認。dev mopidy(6601, ytmusic実アカウント)を実際にビルド・起動し
  MPDで実機確認 — 単一接続でのswap/swapidの機能テスト(実際にキューへ積んだYOASOBI
  「THE BOOK for,」全曲に対しswap 1 4→期待通りの単純交換、swapidでも同様、swap 0 99→
  ACK Bad song index、swap 2 2→OK)、move/tagtypes/status/count等の回帰なしを確認。
  さらに本項目のためだけに旧(パッチ未適用)envを同dev環境の別ポート(6602)で並行起動し、
  同一の2コネクション競合ストレステスト(コネクションAが`swap 1 4`、コネクションBが
  `swap 2 3`を1秒間ひたすら連打)を新旧env双方に実際にぶつけて比較 — 旧env(6602)は
  5032回の生swap呼び出し全てが`ACK`0件・全て`OK`を返しながらキュー順序が実際に破損
  する(=クライアントに一切気づかれない完全なサイレント破損)ことを実機再現、新env
  (6601)は同条件下で2037/2788回(約42%)が`ACK Bad song index`として正しく検知され、
  残るOK分については曲の紛失/重複が一切無い(multisetが常に一致)ことを確認。両env
  ともmopidy.log にTraceback/ERROR 0件。なお2回のmoveの間(あるいはversion確認と
  move実行の間)に残るごく短い窓は原理上残存し、飽和した敵対的トラフィック下では
  それすら踏まれうる(上記ストレステストで実際に確認済み)が、これは「2回の別々の
  core呼び出しに分解される」というmopidy-mpdの設計自体に起因しmopidy core自体を
  変更しない限り完全には閉じられないため、prio/moveid/swapid等の既存パッチが同種の
  残存リスクを許容範囲として明記しているのと同じ扱いとする(本パッチのスコープ内
  では「別の曲を巻き込みサイレントにOKを返す」という最悪の症状を解消し、割り込みを
  検知した場合は既存のmpdmoveswaprace-patch.pyと同水準のACK Bad song indexに変換する
  ところまでとした)。
- [x] `mopidy_mpd/protocol/current_playlist.py` の `move`/`moveid` の TO 相対指定
  (`+N`/`-N`、現在曲基準。mpdmoveto-patch.pyが追加)を解決する`_mpd_resolve_move_to()`
  に残っていたTOCTOUレース。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェント
  がmopidy_mpdのコード品質を再調査して発見した項目。`_mpd_resolve_move_to()`は
  `get_length().get()`と(相対TOの場合)`index().get()`という2回の別々のcore呼び出しで
  「現在曲のposition」を読み取り絶対`to_position`を確定するが、呼び出し元の
  `move_range()`/`moveid()`はこの`to_position`をさらに別のcore呼び出しである
  `move(start, end, to_position).get()`に渡して実行する。「現在曲位置を読む」→
  「moveを実行する」の間に他クライアントのdelete/move/swap等が割り込める窓があり、
  mopidy/core/tracklist.pyのmove()は範囲チェックのみで無条件に実行され「動かした曲が
  本当に意図した曲か」「to_positionが本当に現在曲の直後/直前のままか」は一切検証しない
  (mpdswapstalepos-patch.pyが確認済みの性質と同一)。mpdmoveto-patch.py(初出)は相対TOの
  パース・数式ロジックのみ、mpdmoveswaprace-patch.pyは範囲外POS/START:ENDのACK変換のみ、
  mpdmoveidrace-patch.pyはFROM側(tlid->position)の2段階解決レースのみを対象としており、
  いずれもこの`_mpd_resolve_move_to`内部の競合には触れていないことをBACKLOG.md全文検索で
  確認した。
  verified: mpdmovetorace-patch.py。まず実機の2コネクション継続競合ストレステスト
  (`swap 3 6`を連打するコネクションBに対し、Bの範囲外側の`move 9 +0`を連打する
  コネクションAを2秒間ぶつける)で新実装が実際にACK Bad song indexを返す(546 OK /
  254 ACK)ことと、キュー整合性(10曲のtlid多重集合が常に一致、消失/重複なし)が
  保たれることを確認した。ただし黒箱の実ネットワークタイミング検証だけでは
  「+0=現在曲の直後」という意味的な約束が実際に破られる瞬間を確実に再現できな
  かった(YTMusicの短時間トラックでcurrent自体が入れ替わり得るなど、実環境のノイズが
  大きく再現性が不安定だったため)。そこでmpdswapstalepos-patch.pyの検証手法と同様、
  mopidy/core/tracklist.pyの実move()/index()/get_version()実装をgh api相当で確認した
  上で忠実に再現したPythonロジックレベルの決定論的検証を追加実施: キュー10曲・現在曲
  position5(怪物)の状態で`move 8 +0`を送り、resolve完了後・move実行前に別クライアントの
  `delete 0`を注入する決定的シナリオを再現したところ、旧実装はACK無しでOKを返しながら
  意図した曲(position8だった曲)を現在曲(実際は今position3)から4つも離れた位置(position8)
  へ動かし「+0=現在曲の直後」という約束を明確に破っていることを確認した。新実装は同
  シナリオで正しくACK Bad song indexを返し、無関係な曲を巻き込む前に検知することを確認。
  さらにレース無しの通常呼び出し5パターン(絶対move、相対-0、相対+2、window型、現在曲
  自身への相対move)は新旧で完全に同一の結果(エラー種別・最終キュー状態とも)になること
  (回帰無し)も同ロジックレベルの検証で確認した。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w`して`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic実アカウント)を実際にビルド・起動しMPDで実機確認 —
  絶対move(`move 4 0`)、相対`+0`/`-0`、範囲外相対(`move 4 +99`→`ACK Number too large`)、
  現在曲自身への相対moveid(`ACK Cannot move current song relative to itself`)、
  存在しないtlidへのmoveid(`ACK No such song`)、swap/tagtypes/status等の回帰なしを確認。
  mopidy.log にTraceback/ERROR 0件(既知のpre-existing 401を除く)を確認。
- [x] `mopidy_mpd/protocol/current_playlist.py` の `swapid` (tlid経由のswap) が
  `tlid1->position1`/`tlid2->position2` の解決を2回の別々の `tracklist.index(tlid=...)`
  呼び出しで行っており、その間に他クライアントがキューを操作(move/swap等)しても検知
  できないTOCTOUレースが残っていた。TODO全項目消化済みのため自走エージェントが
  mpdmoveidrace-patch.py(この2段階呼び出し自体は既にfilter()+index()からindex(tlid=...)へ
  集約済み)のコメント「move()/swap()本体との間のレースはmpdmoveswaprace-patch.pyが
  範囲外AssertionError→ACKで吸収済みのためスコープ外」が、position解決自体がその場で
  古くなり範囲内に留まったまま曲の対応関係だけずれるケース(=無関係な曲をサイレントに
  入れ替えてOKを返す、prio/move/moveidの各TOCTOUレースと同根)を見落としていたと判明し
  新規発見・追加した項目。
  verified: mpdswapidrace-patch.py。mpdswapstalepos-patch.py/mpdmovetorace-patch.pyと同じ
  tracklist.versionによる楽観的排他制御を、呼び出し1(tlid1)と呼び出し2(tlid2)の間に割り込みが
  無かったことの検証に適用(変化していればswap()本体を呼ぶ前にACK Bad song indexで打ち切る)。
  パッチ適用後の生成ソースは一時コピーに`chmod u+w`して`ast.parse`で構文確認。dev
  mopidy(6601, ytmusic実アカウント)を実際にビルド・起動しMPDで実機確認 — 通常の
  `swapid`(2曲の入れ替えが正しくPos/Idに反映)、存在しないtlid(`ACK No such song`)、
  同一tlid指定(無変更でOK)の回帰なしをまず確認。**レース自体の再現確認**: 8曲キューに
  実データ(YOASOBI/Ayase/Lilas)を積み、3スレッドでランダムなtlidペアへの`swapid`を、
  別3スレッドでランダムな位置への`move`を8秒間飽和的に並行実行するストレステストを
  実施 — 2773回のswapid呼び出し中1982回(約71%)で割り込みを検知し`ACK Bad song
  index`を返し(=旧実装ならここで無関係な曲を巻き込みサイレントにOKを返していたはずの
  頻発する競合窓を実際に検知・遮断できていることを高頻度で確認)、残り791回は正常に
  `OK`で完了。ストレス後もキューの曲数・tlid集合は完全一致(曲の消失・重複無し)、
  mopidy.logにTraceback/ERROR 0件、接続断も無し。旧来の`moveid`/`status`/`tagtypes`/
  `search any`の回帰なしも確認。
- [x] `mopidy_mpd/protocol/playback.py` の `play [SONGPOS]` が、`SONGPOS` に `-1`
  以外の負数 (`-2`/`-8`/`-100`等)を渡された場合に `ACK Bad song index` を返さず、
  キュー末尾付近の無関係な曲をサイレントに再生してしまう不具合。TODO/既知の
  残課題を全項目消化済みのため自走エージェントが mopidy_mpd のコード品質を
  再調査して発見した項目。`play()` は `songpos == -1` だけを `_play_minus_one()`
  へ特別扱いし、それ以外は素通しして
  `context.core.tracklist.slice(songpos, songpos + 1).get()[0]` に渡すが、
  `mopidy/core/tracklist.py` の `slice()` は素の Python リストスライス
  (`self._tl_tracks[start:end]`) であり、Python のスライスは負数の start/end を
  「末尾からの相対位置」として解釈し `IndexError` を投げない
  (`[0,1,2,3,4][-2:-1]` は空にならず `[3]` を返す)。結果、5曲キューに
  `play "-2"` を送ると、本来ACKすべき無効な位置指定のはずが位置3(末尾から2番目)
  の無関係な曲をそのまま再生してしまう。一方、範囲外に大きく振れた負数
  (`play "-100"`) はスライス結果が空リストになり既存の `except IndexError` で
  正しく `ACK Bad song index` になっており、中間の負数域だけが可観測にサイレント
  破損する非対称な挙動だった。他の類似POS系コマンド (`swap`/`delete`等) は
  `protocol.UINT` で負数自体を受理しない設計だが、`play` の `songpos` だけ `-1`
  の特別扱いのため符号付き `protocol.INT` を使っており、この非対称がガードの
  抜け穴になっていた。
  verified: mpdplayneg-patch.py。まず一時コピー(`chmod u+w`)に適用し
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることを確認。
  `nix/lib/mopidy-env.nix`に登録しdev mopidy(6601, ytmusic実アカウント)を
  実際にビルド・起動しMPDで実機確認 — 実際にfindaddで8曲(YOASOBI/米津/Ado等)を
  キューへ積んだ上で、`play "-2"`/`play "-8"`(=-キュー長)/`play "-100"`
  (境界外の遠い負数、旧実装でも既にACKだった回帰確認)/`play "99"`(範囲外の正数、
  回帰確認)が全て`ACK [2@0] {play} Bad song index`になること、`play "0"`/
  `play "3"`(通常の有効範囲、`status`のsong/songidが該当位置の実トラックに
  一致)が正常に`OK`を返すこと、`play "-1"`(既存の特別扱い、停止中に現在曲へ
  再生開始)が引き続き`OK`を返すことを確認。`status`/`tagtypes`等の回帰なし、
  mopidy.logにTraceback/ERROR 0件を確認。
- [x] `mopidy_mpd/protocol/playback.py` の `seekcur {TIME}` が、停止中
  (`state == PlaybackState.STOPPED`) でも無条件で `context.core.playback.seek()`
  を呼んでしまい、`mopidy/core/playback.py` の `seek()` 内部の「STOPPEDなら
  暗黙に `self.play()` する」実装を誘発してサイレントに停止中→再生中へ遷移
  してしまう不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  mopidy_mpdのコード品質を再調査して発見した項目 (実MPD本体
  `MusicPlayerDaemon/MPD` の `src/queue/PlaylistControl.cxx`
  `playlist::SeekCurrent` をgh api経由でソース確認し、`if (!playing) throw
  PlaylistError::NotPlaying();` を最初に無条件で行うことを確認した上で追加)。
  `seek`/`seekid` はSONGPOS/IDを明示するため対象が現在曲と異なれば内部で
  `play()`を呼んで切り替える仕様上の相違があり(意図通り、無変更)、`seekcur`
  だけが「現在曲基準」という性質上、再生中でないと成立しない操作になっている。
  判定条件は`get_current_tl_track() is None`ではなく`get_state() ==
  PlaybackState.STOPPED`にする必要があると判明: `mopidy/core/playback.py`の
  `stop()`は`_current_tl_track`を一切クリアしないため、一度でも再生してから
  `stop`した後は`get_current_tl_track()`が非Noneのまま残り続け
  (前者の判定では停止中でも素通ししてしまう)、一方`state`は`stop()`で確実に
  `PlaybackState.STOPPED`になるため実MPDの`playing`真偽値を過不足なく再現できる。
  verified: mpdseekcurstop-patch.py。既存の`current_playlist.py`/`music_db.py`/
  `stored_playlists.py`が「現在曲が必要な操作」で確立済みの`_MpdPlayerSyncError`
  (`error_code = ACK_ERROR_PLAYER_SYNC`)と同じパターンを`playback.py`にも
  `_MpdSeekCurPlayerSyncError`として導入。実MPDのソース(`src/protocol/Ack.hxx`
  `ACK_ERROR_PLAYER_SYNC = 55`、`src/PlaylistError.hxx`
  `NotPlaying()`のメッセージ"Not playing"、`src/command/CommandError.cxx`の
  `ToAck()`で`NOT_PLAYING`→`ACK_ERROR_PLAYER_SYNC`への写像)をgh api経由で
  実際に確認した上でACKコード・メッセージ文言を実MPDに合わせた。パッチ適用後の
  生成ソースは`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix`に登録しdev mopidy(6601, ytmusic実アカウント)を
  実際にビルド・起動しMPDで実機確認 — (1)起動直後で一度も再生していない状態
  (`get_current_tl_track()`もNone)でfindaddし`seekcur "5"`→
  `ACK [55@0] {seekcur} Not playing`、`status`は`state: stop`のまま無変更。
  (2)`play "0"`後に`stop`(mopidyの仕様上`song`/`songid`はstatusに残存し続ける
  ことを実機で確認した上でのケース)→`seekcur "3"`→同じく
  `ACK [55@0] {seekcur} Not playing`となり`state: stop`のまま無変更
  (旧実装ならここでサイレントに直前の現在曲が再生開始してしまっていた)。
  (3)再生中の回帰確認: `play "0"`→`seekcur "10"`(絶対)→`OK`かつ`status`の
  `elapsed`が10.000に反映、`seekcur "+2"`(相対)→`OK`かつ`elapsed`が12.000に
  反映。(4)一時停止中の回帰確認: `pause "1"`→`seekcur "4"`→`OK`かつ`elapsed`が
  4.000に反映(実MPDもPAUSE状態はplaying扱いのため一致)。(5)`seek`/`seekid`の
  既存動作の回帰確認: 停止中でも明示的なSONGPOS/tlid指定なら`seek "0" "5"`/
  `seekid "1" "5"`は引き続き`OK`(仕様通り無変更)。旧来の`tagtypes`/`list album`/
  `count any "yoasobi"`の回帰なし。mopidy.logにTraceback 0件、ERRORは既知の
  pre-existingなyt-dlpストリーム403(このテスト環境で時折発生する一時的な
  解決失敗、他パッチ検証時にも確認済みの挙動)のみで新規リグレッションでは
  ないことを確認。なお検証中に副産物として`seekcur`に非数値TIME
  (`seekcur "abc"`)を渡すとセッションが切断される別の不具合(本パッチとは
  無関係、`protocol.FLOAT`/`UFLOAT`の手動パースが素の`ValueError`を投げる
  ことが原因)を発見したため、TODOセクション先頭に新規未着手項目として追記した
  (1回の実行では1項目のみ扱う方針のため今回は着手せず次回に回した)。
- [x] `mopidy_mpd/protocol/status.py` の `currentsong`、`current_playlist.py` の
  `playlistid {SONGID}` と `plchanges {VERSION}` (version一致=メタデータ更新のみの分岐)
  に共通して残っていた TOCTOU レース。TODO/既知の残課題を全項目消化済みのため
  自走エージェントが mopidy_mpd のコード品質を再調査して発見した項目
  (prio/moveid/swapid の TOCTOU レース群と同根だが、書き込み系コマンドの修正時には
  スコープ外だった読み取り系コマンドに同型の欠陥が残っていた)。3箇所とも
  「対象の tl_track (群) を取得する core 呼び出し」と「その位置を求める
  `tracklist.index(...)` の core 呼び出し」が別々の pykka actor 往復に分かれており
  (`currentsong`/`plchanges`: `get_current_tl_track()` → `index(tl_track)`、
  `playlistid {SONGID}`: `filter({"tlid": [tlid]})` → `index(tl_tracks[0])`)、
  `mopidy/core/tracklist.py` の `index(tl_track)` は対象曲がもはやキューに存在しなければ
  `ValueError` を握り潰して `None` を返す実装 (gh api で実装確認済み)。呼び出し1と
  呼び出し2の間隙で別クライアントが `delete`/`clear` 等により対象曲をキューから
  外すと `position=None` になり、`mopidy_mpd/translator.py` の `track_to_mpd_format()`
  が `if position is not None and tlid is not None:` の内側でしか `Pos`/`Id`/`Range`/
  `Prio`/`Added` を出力しないため、例外もACKも無くこれらのフィールドが応答から
  サイレントに丸ごと欠落する。rmpc (mierak/rmpc) は `get_status_and_current_song()`
  で `status`+`currentsong` を command_list で毎回セットで送り(player idle wakeup時=
  最頻出経路)、返ってきた `Song.id` を `event_loop.rs` の `is_new_song =
  new_song_id.is_some() && new_song_id != current_song_id` で「曲が変わったか」の
  判定に使う。`playlistid`/`plchanges` も同種のクライアントの曲同定に使われるため、
  Idの欠落によりこの判定がサイレントに誤る実害がある。
  verified: mpdcurrentsongrace-patch.py。`currentsong`/`playlistid`/`plchanges` は
  読み取り専用コマンドで ACK による失敗の余地が無いため (musicpd.org 仕様上こういう
  ケースでのエラー応答は定義されていない)、mpdswapstalepos-patch.py 等が書き込み系
  コマンドで確立した `tracklist.version` による楽観的排他制御を「割り込みを検知したら
  取り直す (bounded retry、上限5回)」形で `currentsong`/`plchanges` に転用: 呼び出し
  前後で version が不変なら割り込みが無かったことを意味し、得られた position は正しい
  (割り込みがあれば取り直し、収束しない極端なケースでも最後に得た値をそのまま返すため
  現状の「常にサイレントに欠落」より確実に改善し悪化はしない)。`playlistid {SONGID}`
  はより単純に `get_tl_tracks()` 1回のスナップショットに対しローカルで位置を求める
  ことで2回の core 呼び出し自体を1回へ一本化しレースそのものを解消した
  (`playlistinfo`/`plchangesposid` が既に同じ「1回のスナップショット+ローカル
  enumerate」の流儀を使っており、これに揃えた)。パッチ適用後の生成ソースは
  一時コピーに `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix` に登録し dev mopidy(6601, ytmusic実アカウント)を実際に
  ビルド・起動しMPDで実機確認 — (1)回帰確認: `findadd`で5曲キューに積み`play "0"`後、
  `currentsong`/`playlistid "<songid>"`/`plchanges "0"`がいずれも`Pos`/`Id`含む
  フルの曲情報を返すこと、`playlistid "999"`(存在しないid)が引き続き`ACK [50@0]
  {playlistid} No such song`を返すこと(回帰なし)を確認。(2)**レース自体の再現・
  非再現確認**: 5曲キューを積み`play "0"`後、`status`をポーリングして`state: play`
  かつ`audio`フィールド出現(実際に音声デコード開始=current_tl_trackが安定)を確認
  してから、2スレッドで`currentsong`を、2スレッドで`playlistid "<現在のsongid>"`を
  連打しつつ、別3スレッドで「現在再生中の曲には触れない末尾の曲」を`delete`+
  `findadd`で継続的に入れ替える(=tracklist.versionを頻繁に増加させ他クライアント
  割り込みの機会を最大化する)ストレステストを6秒間実施 — 113回の`currentsong`/
  `playlistid`呼び出し中、`Id`欠落0件、並行して`status`を0.1秒間隔でポーリングし
  現在の`songid`が終始不変であること(=レースの温床となる「現在曲自体が途中で変わって
  しまう」という別要因が混入していないこと)も0件のずれで確認。mopidy.logにこの
  ストレス区間でのTraceback/ERROR 0件。旧来の`status`/`tagtypes`の回帰なしも確認。
  なお検証の試行錯誤中、意図的に「現在再生中の曲そのもの」を繰り返し`delete`する
  (本パッチのスコープ外の別シナリオ)と、YouTube側のストリームURL期限切れ(403、
  ytmusic backend側の既知の一時的挙動)による自動曲送りと重なって
  `mopidy/core/playback.py`の`_on_about_to_finish`(core本体、mopidy_mpd外)で
  `AttributeError: 'NoneType' object has no attribute 'track'`が発生する事象を偶発的に
  観測したが、これは mopidy core 自体の別の pre-existing な欠陥であり (configs/media/
  mopidy/ と nix/lib/mopidy-env.nix のみというスコープ上 core 自体は対象外)、本パッチの
  対象範囲(mopidy_mpd の currentsong/playlistid/plchanges)とは無関係なため今回は
  着手せず記録のみ残す。
- [x] `mopidy_mpd/protocol/music_db.py` の `searchaddpl {NAME} {FILTER} [...]` (対象
  プレイリストが未存在で新規作成する経路) と `mopidy_mpd/protocol/stored_playlists.py`
  の `playlistclear {NAME}` (同じく未存在なら新規作成する経路) が、どちらも
  `context.core.playlists.create(name).get()` の戻り値を None チェックせずいきなり
  `.replace()` している不具合。TODO 全項目消化済みのため自走エージェントが
  mopidy_mpd のコード品質を再調査して発見した項目 (general-purpose agent による
  ソース精読調査で発見)。`mopidy.core.playlists.create()` の docstring 通り、対応する
  バックエンドが無い/生成に失敗した場合は None を返しうる (`mopidy_ytmusic.playlist.
  YTMusicPlaylistsProvider.create()` は `api.create_playlist()` が例外(ネットワーク
  瞬断・レート制限・認証切れ等)を投げると `logger.exception()` した上で None を返す
  設計であり実際に踏みうる)。全く同じ create()-None 未チェックのバグクラスは
  `stored_playlists.py` の `rename()` に対して既に mpdrenamefix-patch.py で修正済み
  だが、そのパッチのコメントが `_create_playlist()`/`playlistadd`/`playlistclear` は
  正しくガードされていると誤って記載していた(実際には `playlistclear` は未ガード
  のままだった)のと、`searchaddpl` は当時のスコープ外だったため、2箇所とも対象外の
  まま残っていた。実害: `playlist.replace(...)` が素の
  `AttributeError: 'NoneType' object has no attribute 'replace'` を送出し、これは
  `exceptions.MpdAckError` のサブクラスではないため `dispatcher.py` の
  `_catch_mpd_ack_errors_filter` に捕捉されず、`session.py` にも try/except が無い
  ため pykka アクターの外まで伝播し `network.LineProtocol.on_failure`
  (`self.connection.stop("Actor failed.")`) に到達、ACK エラーが一切返らずTCP接続
  そのものが問答無用で切断される(rmpc から見ればコマンドを送っただけでサーバーとの
  接続が落ちる)。
  verified: mpdplaylistcreateguard-patch.py。`rename()`/`_create_playlist()` と同じ
  流儀で、create() 直後に None チェックを追加し、None なら
  `exceptions.MpdFailedToSavePlaylist(default_scheme)`
  (`context.dispatcher.config["mpd"]["default_playlist_scheme"]`、`_create_playlist()`
  のフォールバック経路と同じ scheme 取得方法。対象URIが無いため既存playlistの
  uriから逆算できないため)を送出するよう修正。パッチ適用後の生成ソースは一時
  コピーに `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  さらに `context.core.playlists.create()` が None を返すケースを FakeContext/
  FakeFuture でモック注入し、`music_db.searchaddpl()`/`stored_playlists.
  playlistclear()` の双方が修正後は素の `AttributeError` ではなく
  `exceptions.MpdFailedToSavePlaylist` を送出することを実際にビルド後の
  site-packages を import して確認 (GI_TYPELIB_PATH/DYLD_LIBRARY_PATH に
  gstreamer/gst-plugins-base の typelib を指定し `mopidy.core` の import chain を
  解決)。`nix/lib/mopidy-env.nix` に登録しビルド成功、生成ソースに新実装が反映
  されていることを確認した上で dev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで実機確認 — (1) 未存在プレイリスト名への `playlistclear
  "AutoAgentTestNew1"` → `OK`、`listplaylists` に新規作成されたプレイリストが
  反映(この実環境では ytmusic の create() 自体は成功するため create()-None分岐
  には到達しないが、既存の作成→保存の経路に回帰が無いことを確認)。(2) 未存在
  プレイリスト名への `searchaddpl "AutoAgentTestNew2" artist "yoasobi"` → `OK`、
  `listplaylistinfo` で検索結果の曲が実際に保存されていることを確認。(3) 後片付け
  で `rm` 済みの2件とも成功、`listplaylists` が空に戻ることを確認。(4) `tagtypes`/
  `status` の回帰なし、mopidy.log に Traceback/ERROR 0件(既知の pre-existing な
  yt-dlp 403 除く)。
- [x] `mopidy_mpd/protocol/status.py` の `status` コマンド本体 (`currentsong` とは別関数)
  に、mpdcurrentsongrace-patch.py が `currentsong`/`playlistid`/`plchanges` に対して
  修正したのと全く同型の TOCTOU レースが残っていた不具合。TODO 全項目消化済みのため
  自走エージェントが general-purpose agent によるソース精読調査で発見。`status()` は
  「`tl_track = core.playback.get_current_tl_track()` → `tracklist.index(tl_track.get())`」
  「`next_tlid = core.tracklist.get_next_tlid()` → `tracklist.index(tlid=next_tlid.get())`」
  という2組で、それぞれ「曲/tlidを取得するcore呼び出し」と「その位置を求める
  `tracklist.index()` のcore呼び出し」が別々のpykka actor往復に分かれており、間隙で
  別クライアントが `delete`/`clear` 等により対象曲をキューから外すと `index()` が
  `ValueError` を握り潰し `None` を返す (currentsong修正時に確認済みの実装と同一)。
  `currentsong` 等と違い `status()` の `song`/`nextsong` は
  `translator.track_to_mpd_format()` の `position is not None` ガードを経由せず、
  `_status_songpos()`/`_status_nextsongpos()` が `futures["tracklist.index"].get()`/
  `futures["tracklist.next_index"].get()` を無条件にそのまま返し、`dispatcher.py` の
  `_format_lines()` が `f"{key}: {value}"` で無検証に文字列化するため、ACKもクラッシュも
  無く `song: None`/`nextsong: None` という musicpd.org 仕様 (both are integers) に反する
  応答がそのまま返る実害がある (`songid`/`nextsongid` は `current_tl_track.tlid`/
  `next_tlid` から直接得るためこのレースの影響を受けない)。rmpc は player idle wakeup
  のたびに `status`+`currentsong` を command_list で送るため、この応答不正がクライアント
  側のパース/曲同定ロジックへ伝播しうる。
  verified: mpdstatusrace-patch.py。mpdcurrentsongrace-patch.py が確立した
  「呼び出し前後で `tracklist.version` が不変なことを確認し、割り込みがあれば
  取り直す (bounded retry)」を転用。`status()` は元々 futures辞書+`pykka.get_all()`で
  多数のcore呼び出しをまとめて解決する構造のため、tl_track/position/next_tlid/
  next_indexの4値だけ先にレース対策込みで解決し、`pykka.ThreadingFuture().set()`で
  「既に解決済みのfuture」として同じfutures辞書の枠組みに乗せる(既存の
  `_status_songpos()`等の呼び出し側は無変更)。パッチ適用後の生成ソースは一時コピーに
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`にmpdcurrentsongrace-patch.py/mpdplaylistcreateguard-patch.py
  の後段(status.pyへの前提適用順序のため)に登録しビルド成功、生成ソースに新実装が
  反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで実機確認 — (1)回帰確認: `findadd`で5曲キューに積み`play "0"`後、
  `status`が`song: 0`/`songid: 1`/`nextsong: 1`/`nextsongid: 2`等いずれも正しい整数を
  返すこと、最終曲再生中は`nextsong`/`nextsongid`が仕様通り省略されること、`stop`後は
  `song`/`songid`のみ残り`nextsong`系が省略されること、`tagtypes`の回帰なし、いずれも
  確認。(2)レース自体の再現・非再現確認: 5曲キューを積み`play "0"`後、4スレッドで
  `status`を、別3スレッドで「現在再生中のpos 0には触れない末尾の曲」を`delete`+
  `findadd`で継続的に入れ替える(=tracklist.versionを頻繁に増加させ他クライアント
  割り込みの機会を最大化する)ストレステストを10秒間実施 — 25回の`status`呼び出し
  (churner側30回の入れ替え)中、`song: None`/`nextsong: None`の出現0件、mopidy.logに
  このストレス区間でのTraceback/ERROR 0件(既知の無関係なgst-plugin-scanner
  `pygobject initialization failed`のみ)を確認。
- [x] `mopidy_mpd/uri_mapper.py` の `MpdUriMapper` インスタンスが `actor.py` で1個だけ
  生成され、`network.py` の `Server` が同一の `protocol_kwargs` dict を全クライアント
  接続に使い回すため、全 `MpdSession` (各接続=別々の `pykka.ThreadingActor`、実OS
  スレッド) が同一の `_uri_from_name`/`_browse_name_from_uri`/`_playlist_name_from_uri`
  dict を一切のロック無しで直接読み書きしていた不具合。TODO 全項目消化済みのため
  自走エージェントが mopidy_mpd のコード品質を再調査して発見した。
  mpdplaylistcache-patch.py/mpdbrowsecache-patch.py/mpdplaylistnamerace-patch.py は
  この3 dict の「stale purge漏れ」「素dictインデックスのKeyError化」といった
  ロジック不具合は既に修正していたが、いずれも単一スレッド逐次実行を前提にしており
  複数クライアント同時接続時のスレッド安全性は未検討だった。
  実害: `refresh_browse_children()` の `for path, uri in self._uri_from_name.items()`
  というその場走査、`refresh_playlists_mapping()` の
  `set(self._playlist_name_from_uri)` というキー集合スナップショット構築は、走査中に
  別スレッドが `insert()` (browse中の子要素登録、または `refresh_playlists_mapping()`
  自身の更新ループ) で同じ dict へ挿入/削除すると CPython の
  `RuntimeError: dictionary changed size during iteration` を送出する。これは
  `exceptions.MpdAckError` のサブクラスではないため `dispatcher.py` の
  `_catch_mpd_ack_errors_filter` に捕捉されず、pykka アクターの外まで伝播し
  `network.LineProtocol.on_failure` (`self.connection.stop("Actor failed.")`) に
  到達、ACK エラーが一切返らずその接続の TCP セッションが問答無用で切断される。
  トリガ条件は「2本以上の MPD 接続が同時に張られている」だけで良く (rmpc複数起動や
  rmpc+他クライアント併用等)、一方が `lsinfo`/`listfiles` 等でブラウズ中、もう一方が
  `listplaylists`/`rm`/`rename`/`save` 等でプレイリスト名前空間を更新する、という
  ごくありふれた並行操作で発現する。
  verified: mpdurimaprace-patch.py。`MpdUriMapper.__init__` に `threading.RLock()`
  を追加し、`insert()` 全体、`refresh_browse_children()` の走査+purge、
  `refresh_playlists_mapping()` の stale purge+insert ループを `with self._lock:`
  で保護 (`refresh_playlists_mapping()` から `insert()` を呼ぶため再入可能な RLock を
  使用)。`listall` blocked 事案の教訓を踏まえ、`self.core.playlists.as_list().get()`
  (バックエンドへの実ネットワーク呼び出しを伴う pykka future の `.get()`) はロックの
  外で実行し、ロック区間は純粋なローカル dict 操作のみに最小化して他クライアント
  接続の待ち時間を増やさないようにした。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも
  確認。まず実際にビルド済み env の (パッチ未適用) `uri_mapper.py` を import した
  独立harnessで、4スレッドで `refresh_browse_children()` を、別4スレッドで
  `insert()` を3秒間同時実行 — 毎回確実に `RuntimeError('dictionary changed size
  during iteration')` を実際に再現 (不具合の実在を確認)。同様に `refresh_playlists_
  mapping()` (FakeCore経由) x4スレッド + `insert()` x4スレッド + `refresh_browse_
  children()` x4スレッドの5秒間同時実行でも同じ `RuntimeError` を再現。
  `nix/lib/mopidy-env.nix` に登録しビルド成功、パッチ適用後の生成ソースへ import
  すると上記2種のストレステストとも例外0件になることを確認 (修正確認)。さらに
  `nix/lib/mopidy-env.nix` 登録・ビルド後、dev mopidy (6601, ytmusic実アカウント) を
  実際に起動しMPDプロトコルで実機確認 — 4本の接続で `lsinfo "YouTube Music"`/
  `lsinfo ""` を、別4本で `listplaylists` を、別2本で `status` を10秒間連打する
  実ソケットストレステスト (計10本の同時TCP接続) を実施し、205回のコマンド応答が
  全て正常完了・接続断0件、mopidy.log に `RuntimeError`/`Actor failed`/`dictionary
  changed size` 0件を確認 (既知の無関係な ytmusic:home 由来 `KeyError:
  'videoDetails'` トレースバックが4件出たのみで新規リグレッションではない)。
  加えて `tagtypes`/`status`/`listplaylists`/`lsinfo` の単発呼び出しが従来通り
  正常応答することも確認し、ロック導入による回帰が無いことを確認した。
- [x] `mopidy_mpd/protocol/playback.py` の `crossfade`/`mixrampdb`/`mixrampdelay`
  (mpdcrossfade-patch.py/mpdmixramp-patch.py で実装済み) が idle "options" イベントを
  一切発火しない不具合。TODO 全項目消化済みのため自走エージェントが general-purpose
  agent によるソース精読調査で発見。実 MPD (src/command/PlayerCommands.cxx
  handle_crossfade/handle_mixrampdb/handle_mixrampdelay) はいずれも成功時に
  `partition.EmitIdle(IDLE_OPTIONS)` を呼び、`status.py` のdocstring自体も idle の
  `options` サブシステムを "options like repeat, random, crossfade, replay gain" と
  明記している。ところが `crossfade()`/`mixrampdb()`/`mixrampdelay()` は mopidy core
  (`context.core.tracklist` 等) を一切経由せず `translator.py` のモジュールレベル
  揮発性ストアを直接書き換えるだけのため (mopidy core 自体は crossfade/mixramp の
  概念を持たない)、`actor.py` の `MpdFrontend.on_event` が拾う core 由来の
  `options_changed` イベントに乗れず、`idle options` で待機中の他クライアントへは
  一切通知が届かなかった。同じ揮発性ストア方式の `replay_gain_mode`
  (mpdreplaygain-patch.py) だけは `_mpdreplaygain_notify()` で明示的に idle 通知する
  よう既に対応済みで、そのコミット自体が「crossfade/mixrampdbより実MPD仕様に近い」と
  記していたにも関わらず crossfade/mixrampdb/mixrampdelay 側は取り残されていた。
  実害: rmpc (rmpc-mpd/src/mpd_client.rs send_crossfade、rmpc/src/ui/ の
  CrossfadeUp/CrossfadeDown グローバルアクション) はcrossfadeコマンドを実際に送信し
  ステータスバーへ反映する導線を持つ。別クライアント(または同一クライアントの別接続)が
  crossfade/mixrampdb/mixrampdelayを変更しても、`idle options` で待機中のrmpc等は
  起こされず、次に別の理由(repeat切替等)でoptionsイベントが発火するまで表示が
  古いまま固定される、というサイレントな不整合が生じていた。クラッシュやセッション
  切断は起きないが実MPD仕様違反かつUI表示に実害がある。
  verified: mpdcrossfadeidle-patch.py。mount (mpdmount-patch.py の
  `_mpdmount_notify`)・replay_gain_mode (mpdreplaygain-patch.py の
  `_mpdreplaygain_notify`) と同じ流儀で、本パッチ専用の `_mpdcrossfadeidle_notify()`
  を playback.py に追加し (他パッチ実装済みの notify 関数へ相乗りせず自パッチ内で
  完結させ適用順序への依存を避けた)、crossfade/mixrampdb/mixrampdelay 3関数の末尾に
  呼び出しを追加。パッチ適用後の生成ソースは一時コピーに `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix` に登録し
  ビルド成功、生成ソースに新実装が反映されていることを確認した上でdev mopidy(6601,
  ytmusic実アカウント)を実際に起動しMPDで実機確認 — 2本のTCP接続を張り、一方で
  `idle options` を待機させ、他方から `crossfade 5`/`mixrampdb -10.5`/
  `mixrampdelay 2.5` をそれぞれ送信 — いずれも `OK` 応答かつ待機側に即座に
  `changed: options` が届くことを確認 (旧実装ではこの3コマンドいずれも idle 側は
  タイムアウトまで無反応だった)。加えて `status` にそれぞれ `xfade: 5`/
  `mixrampdb: -10.5`/`mixrampdelay: 2.5` が正しく反映されることも確認。回帰確認:
  `repeat 1` が従来通り `idle options` を発火すること (core経由の既存経路に変更が
  無いこと)、`tagtypes` の単発応答に異常が無いことを確認。mopidy.log に
  Traceback/ERROR 0件 (このテスト区間) を確認した。
- [x] `mopidy_mpd/translator.py` の `channels.py` (client-to-client messaging) 用揮発性
  ストア (`_channel_subscriptions`/`_channel_actor_refs`/`_channel_messages`、
  mpdchannels-patch.py が追加) が `mpdurimaprace-patch.py` で修正した `MpdUriMapper`
  と全く同じ理由でスレッド安全性を欠いていた不具合。TODO 全項目消化済みのため
  自走エージェントが general-purpose agent によるソース精読調査で発見。これら3つの
  module-level dict は全クライアント接続 (各々別スレッドの `MpdSession` pykka
  アクター) から一切のロック無しで共有 read/write されており、`channel_list()`/
  `channel_push_message()` は dict の内容をその場で走査するループを持つ一方、
  `channel_cleanup()` は接続切断のたび (channels未使用のクライアントも含め
  session.py の on_stop から無条件に) 該当キーを pop する。CPython の dict は
  走査中に要素数が変化すると `RuntimeError: dictionary changed size during
  iteration` を送出する仕様のため、あるクライアントが `channels`/`sendmessage`
  実行中に**別の**クライアントが切断すると走査側で `RuntimeError` が飛ぶ。
  `RuntimeError` は `exceptions.MpdAckError` のサブクラスではないため
  `dispatcher.py` の `_catch_mpd_ack_errors_filter` に捕捉されず、`session.py`にも
  保護が無いため pykka アクターの外まで伝播し `network.LineProtocol.on_failure`
  に到達、ACK エラーが一切返らずその接続の TCP セッションが問答無用で切断される。
  verified: mpdchannelrace-patch.py。mpdurimaprace-patch.py と全く同じ流儀で
  translator.py にモジュールレベルの `threading.RLock()` (`_channel_lock`) を追加し、
  `channel_subscribe`/`channel_unsubscribe`/`channel_list`/`channel_push_message`/
  `channel_read_messages`/`channel_cleanup` の本体を `with _channel_lock:` で
  直列化 (いずれもローカルの dict 操作のみでバックエンドへのネットワーク呼び出しを
  含まないため listall事案のような長時間ブロックの懸念は無い)。パッチ適用後の
  生成ソースは一時コピーに `ast.parse` で構文確認、2回適用しても冪等(スキップ)で
  あることを確認。`nix/lib/mopidy-env.nix` に登録しビルド成功。実機検証はまず
  ネットワーク越しの並行接続/切断ストレステストではタイミングウィンドウが狭すぎて
  再現率が低いと判明したため、修正前後の実 store path から `mopidy_mpd.translator`
  を直接 import し、4000件の購読を事前投入した上で読み取りスレッド4本
  (`channel_list()`/`channel_push_message()`連打) と cleanup連打スレッド4本を
  5秒間並行実行するユニットレベルの決定的再現テストを実施 — 修正前
  (`mpdchannelrace-patch.py`適用前の store path) では4スレッド全てで確実に
  `RuntimeError: dictionary changed size during iteration` を再現、修正後
  (同パッチ適用後の store path) では3回の繰り返し試行いずれも例外0件で完走する
  ことを確認した。加えて dev mopidy(6601, ytmusic実アカウント) を実際に起動し
  2本のTCP接続で `subscribe`/`channels`/`sendmessage`/`readmessages`/
  `unsubscribe`、および未購読チャンネルへの `sendmessage` が
  `ACK [50@0] {sendmessage} nobody is subscribed to this channel` となることを
  実機確認 (機能面の回帰なし)。`status`/`tagtypes` の単発応答、および10本の
  同時TCP接続 (購読+切断連打6本、channels/sendmessage連打4本) による8秒間の
  実ソケットストレステストも実施し、mopidy.log に
  `RuntimeError`/`Traceback`/`Actor failed` 0件、サーバが正常に生存し続ける
  ことを確認した。
- [x] `mopidy_mpd/translator.py` の `partition.py` (partition/listpartitions/
  newpartition/delpartition/moveoutput) 用揮発性ストア `_partitions`/
  `_session_partition`/`_output_partition` (mpdpartition-patch.py が追加) が
  `mpdurimaprace-patch.py`/`mpdchannelrace-patch.py` で修正した `MpdUriMapper`/
  channels.py ストアと全く同じ理由でスレッド安全性を欠いていた不具合。TODO/
  既知の残課題を全項目消化済みのため自走エージェントが (general-purpose agentへの
  委譲調査を含め) 再調査して発見。実害は2種類: (1) `partition_client_count()`/
  `partition_output_count()` が `_session_partition.values()`/
  `_output_partition.values()` をその場で走査する一方、`session.py`の`on_stop`から
  接続切断のたび (partition未使用のクライアントも含め無条件に、channel_cleanupと
  全く同じ呼び出しパターンで) `partition_cleanup()`が`_session_partition.pop()`する
  ため、あるクライアントの`delpartition`実行中に**別の**クライアントが切断すると
  CPythonのdictが`RuntimeError: dictionary changed size during iteration`を送出し、
  `MpdAckError`のサブクラスではないため`dispatcher.py`に捕捉されずセッションが
  問答無用で切断される。(2) `delpartition`ハンドラは`partition.py`側で
  `partition_exists(name)`確認後に`partition_delete(name)`(=`_partitions.remove(name)`)
  を呼ぶ2段構成のTOCTOUのため、同名`delpartition`を2接続が同時実行すると片方の
  `remove()`が`ValueError: list.remove(x): x not in list`を送出しこれもセッション
  切断に至る。
  verified: mpdpartitionrace-patch.py。mpdurimaprace-patch.py/mpdchannelrace-patch.py
  と同じ流儀でtranslator.pyにモジュールレベルの`threading.RLock()`
  (`_partition_lock`)を追加し、partition_list/partition_exists/partition_get/
  partition_switch/partition_create/partition_delete/partition_client_count/
  partition_output_count/partition_cleanup/output_partition_get/
  output_partition_moveの本体を`with _partition_lock:`で直列化。実害2は
  `partition_delete()`自体を`if name in _partitions: _partitions.remove(name)`
  という削除済みなら無害にno-opする実装に変更(mount_remove等の既存の「無ければ
  何もしない」流儀に合わせた)。パッチ適用後の生成ソースは一時コピーにast.parseで
  構文確認、2回適用しても冪等(スキップ)であることを確認。`nix/lib/mopidy-env.nix`
  にmpdchannelrace-patch.pyの直後に登録しビルド成功、生成ソースに新実装が反映
  されていることを確認した。**ユニットレベルの決定的再現テスト**: 修正前
  (`mpdpartitionrace-patch.py`適用前のtranslator.pyを直接import)、
  `partition_switch`/`partition_cleanup`各4スレッド連打+`partition_client_count`/
  `partition_output_count`読み取り4スレッドを5秒間並行実行 —
  `RuntimeError: dictionary changed size during iteration`を確実に2回再現。
  修正後(同パッチ適用後)は同条件で0件、加えて`partition_create`+4スレッド同時
  `partition_delete`を2000回繰り返す実害2の再現テストも修正後は
  `ValueError`0件で完走することを確認。dev mopidy(6601, ytmusic実アカウント)を
  実際に起動しMPDで実機確認 — `listpartitions`(初期`default`のみ)→
  `newpartition "testpart"`→`listpartitions`(2件)→`partition "testpart"`→
  `status`(`partition: testpart`反映)→`partition "default"`→
  `delpartition "testpart"`→`listpartitions`(defaultのみに戻る)、
  存在しない`delpartition "nosuch"`→`ACK [50@0] {delpartition} no such partition`、
  不正名`newpartition "bad name"`→`ACK [2@0] {newpartition} bad name`、
  `delpartition "default"`→`ACK [5@0] {delpartition} cannot delete the default
  partition`、いずれも既存仕様通りで回帰なし。**実ソケットでのレース実機確認**:
  300個のpartitionを事前作成し、`delpartition`連打3接続+`connect→status→
  disconnect`連打6接続+`status`連打3接続を8秒間並行実行 (約2750回の接続/切断)、
  mopidy.logに`RuntimeError`/`ValueError`/`Traceback`/`ERROR` 0件、サーバが
  クラッシュせず生存し続けることを確認 (発生した3件のクライアント側
  `socket.timeout`はテストスクリプトの過負荷な接続試行によるものでサーバ側の
  切断ではないことを`status`/`delpartition`スレッドのエラー0件で確認済み)。
  ストレステスト後も`status`/`tagtypes`/`listpartitions`/
  `count "(any contains 'yoasobi')"`(2件ヒット)が正常応答することを確認した。
- [x] translator.pyのprio/Added/addtagid/rangeid用4揮発性ストア
  (`_queue_priorities`/`_queue_added`/`_queue_extra_tags`/`_queue_ranges`) が
  mpdurimaprace-patch.py/mpdchannelrace-patch.py/mpdpartitionrace-patch.py が
  修正した uri_mapper.py/channels.py/partition.py の揮発性ストアと全く同種の
  不備を抱えたまま残っていた: 全クライアント接続 (各々別スレッドの
  MpdSession アクター) が prio/addtagid/rangeid/add 等のコマンド経由で直接
  読み書きする一方、actor.py の MpdFrontend (Core本体とは別アクター、
  別スレッド) が core の tracklist_changed イベント (add/delete/move/clear
  等キュー変更全般で発火) を受けるたびに `sync_priorities`/`sync_added`/
  `sync_extra_tags`/`sync_ranges` を呼び「dict をその場で走査するリスト
  内包表記」でstale tlidを掃除するため、ロック無しでは走査中に別スレッドが
  同じ dict へ挿入すると `RuntimeError: dictionary changed size during
  iteration` が飛びセッションが問答無用で切断される。加えて
  `get_song_tags(tlid)` が内部dictをコピーせずそのまま返し、呼び出し元の
  `track_to_mpd_format()` (playlistinfo/playlistid/find/search/count/
  currentsong等ほぼ全コマンドが経由する共有関数) がロック解放後にこの生の
  dict を `.items()` で走査するため同様のRuntimeErrorになりうる不備も発見。
  TODO 全項目消化済みのため自走エージェントが既存の揮発性ストア群
  (translator.py) を横断調査して発見・追加した項目。
  verified: mpdqueuestorerace-patch.py。mpdurimaprace-patch.py/
  mpdchannelrace-patch.py/mpdpartitionrace-patch.py と同じ流儀で
  `threading.RLock()` を1個 (`_queue_lock`、4ストア共通) 導入し、4ストアの
  読み書き関数全てを `with _queue_lock:` で直列化 (`sync_added()`が同じ
  ロック保持中に`stamp_added()`を呼ぶためRLockの再入可能性を利用)。
  `get_song_tags()` は `{k: list(v) for k, v in ...}` の浅いコピーを返す
  よう変更しロック解放後の走査を安全化。パッチ適用後の生成ソースは一時
  コピー (nixストアからの読み取り専用コピーに`shutil.copytree`後全ファイル
  `os.chmod`して書き込み可にした上で) に当てて`ast.parse`で構文確認、2回
  適用しても冪等(スキップ)であることも確認。**オフライン決定的再現テスト**:
  修正前のtranslator.pyを直接importし、writer(stamp_added/set_priority/
  add_song_tag/set_range連打)6スレッド+syncer(sync_added/sync_priorities/
  sync_extra_tags/sync_ranges連打)4スレッド+reader(get_song_tags().items()/
  get_range/get_priority/get_added連打)4スレッドを6秒間並行実行 —
  修正前は`RuntimeError: dictionary changed size during iteration`を23件
  確実に再現、修正後(同パッチ適用後)は同条件で0件を確認。dev
  mopidy(6601, ytmusic実アカウント)を実際に起動し実データ(YOASOBI2曲)で
  MPDプロトコルを直接叩いて確認 — `prio "0:1"`/`addtagid`(複数値)/
  `rangeid`/`cleartagid`が単一接続での通常動作として従来通り正しく反映
  (`playlistid`のPrio/Range/Comment(複数行)/Added全て期待通り)、削除後の
  存在しないtlidへの`addtagid`/`rangeid`は`ACK No such song`のまま回帰なし
  であることを確認した上で、**実ソケットでの並行実機確認**: writer(prio/
  addtagid/rangeid連打)4接続+churn(findadd→playlistinfo→delete連打、
  tracklist_changedを継続的に発火させる)3接続+status連打3接続を10秒間
  並行実行 (合計10本のTCP接続) — エラー0件・意図しない切断0件、
  mopidy.logにTraceback/ERROR 0件を確認 (churnスレッドのplaylistinfo応答に
  RuntimeError文字列が漏れていないことも明示的に検査)。旧来の`status`/
  `tagtypes`/`findadd`/`playlistinfo`/`playlistid`/`delete`の回帰なしを
  確認。
- [x] `mopidy_ytmusic/backend.py` の `on_start()` が起動する2本の `RepeatingTimer`
  (`_auto_playlist_refresh_timer`/`_youtube_player_refresh_timer`、素の`threading.Thread`
  サブクラス、repeating_timer.py) が `YTMusicBackend`(`pykka.ThreadingActor`) 自身の
  受信ループ (actorの単一ワーカースレッド) を経由せず `self._refresh_auto_playlists`/
  `self._refresh_youtube_player` を直接タイマー自身のスレッドで実行しており、rmpc からの
  browse/search/lookup 等 (core が ActorProxy 経由で呼ぶため必ずactorの単一スレッドで
  直列実行される) と並行して `self.api` (ytmusicapiの共有 `YTMusic` インスタンス) へ
  アクセスすると、`self.api.headers` プロパティが `@cached_property` の
  `self.api.base_headers` (プロセス生存中同一の `requests.structures.CaseInsensitiveDict`)
  を in-place で書き換える一方、`requests.PreparedRequest.prepare_headers()`
  (`self.api._send_request()`/`_send_get_request()` が headers=self.api.headers を
  コピーせずそのまま渡す) がこの共有オブジェクトを `for header in headers.items():` で
  直接走査するため、走査中に別スレッドが新規キーを追加すると
  `RuntimeError: OrderedDict mutated during iteration` が発生しうる不具合。TODO/既知の
  軽微な残課題を全項目消化済みのため自走エージェントが、ytcipherfail-patch.py が発見した
  「RepeatingTimerが無保護」問題の隣接領域としてバックエンドのスレッドモデル自体を
  再調査して新規発見・追加した項目。
  verified: ytapiactorrace-patch.py。まず `requests.structures.CaseInsensitiveDict` を
  実際に使い、新規キーを追加し続けるwriterスレッド(3本)と`for k in d: ...`で走査する
  readerスレッド(3本、1件ごとの走査に人為的なsleepを挟み走査時間の窓を広げる、
  mpdmountrace-patch.py等の既存レース検証と同じ手法)を2秒間並行実行するオフライン
  決定的再現テストで、"OrderedDict mutated during iteration"が571件確実に発生することを
  確認 (この時点では合成的なdictでの再現であり、mopidy_ytmusicのコードは未変更)。加えて
  `requests.models.PreparedRequest.prepare_headers`の実ソースを確認し、`self.api.headers`
  がコピーされず共有のまま`for header in headers.items():`で走査される実際の呼び出し
  経路であることも確認した。
  修正: on_start()が`RepeatingTimer`に渡すcallableを、private メソッド
  (`self._refresh_auto_playlists`/`self._refresh_youtube_player`)の直接参照から、
  `self.actor_ref.proxy()`経由のアンダースコア無し公開ラッパーメソッド
  (`refresh_auto_playlists_from_timer`/`refresh_youtube_player_from_timer`、新設。
  ロジック自体は無変更で既存private メソッドへ委譲するだけ)に変更。pykkaの
  ActorProxy越しのメソッド呼び出しは常にactor自身の受信ループへメッセージとして
  送られる(pykka公式ドキュメントの「actorが自分自身に将来の作業をスケジュールする」
  用法と同じ)ため、これにより2本のタイマースレッドが行っていたself.apiアクセスも
  全てactorの単一ワーカースレッドへ直列化され、core駆動のアクセスと二度と競合しなく
  なる。pykkaのActorProxyは`_`で始まる属性を意図的に公開しない
  (pykka/_introspection.py introspect_attrsがattr_path[-1].startswith("_")を除外)ため、
  既存のprivateメソッド名をそのままproxy越しに呼ぶことはできず新設が必要と判断した。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`にytcipherfail-patch.pyの
  直後に登録しビルド成功、生成ソースにproxy経由の新実装が反映されていることを確認した
  上で、dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで確認 —
  起動直後の自動リフレッシュ(`YTMusic loaded N auto playlists sections`/
  `YTMusic Player URL refreshed`ログ)が想定通り発生し、そのログ行のスレッドタグが
  従来の生スレッド名ではなく`YTMusicBackend-3`(actor自身のワーカースレッド名)に
  なっていることを確認し、実際にactorスレッドへ直列化されたことを構造的に確認した。
  さらに`auto_playlist_refresh=1`/`youtube_player_refresh=1`(分、テスト用に一時変更、
  検証後に元の設定へ復元済み)へ変更した状態で、8並列クライアントが`search any`/
  `list album`/`status`/`tagtypes`を連打する負荷試験を135秒間(60秒間隔のリフレッシュを
  2回以上跨ぐ)実施 — クライアント側エラー0件、mopidy.logにTraceback/ERROR/
  RuntimeError/mutated during iteration 0件、3回のリフレッシュログが全て
  `YTMusicBackend-3`から実行されたことを確認した。`status`/`tagtypes`/`list album`/
  `search any`(実データ、YOASOBI/Lilas)の回帰なしも確認。
- [x] `update`/`rescan` (music_db.py) が発行するジョブID採番 `translator._update_job_id`
  が、mpdqueuestorerace-patch.py/mpdmountrace-patch.py/mpdchannelrace-patch.py/
  mpdpartitionrace-patch.pyが修正した他の揮発性ストアと同種の「全クライアント接続
  (各々別スレッドのMpdSessionアクター) 間でロック無しに共有」不備を抱えたまま
  残っていた。ただし他の4件と違いこちらはdictの走査中変更によるRuntimeErrorでは
  なく、`next_update_job_id()`の`_update_job_id += 1`が「読み出し・加算・書き戻し」の
  複合操作 (単一のアトミックなbytecodeではない) であるため、2接続以上が同時に
  `update`/`rescan`を送るとGILのスレッド切替が読み出しと書き戻しの間に割り込み、
  加算が失われるロストアップデートが起きる不具合。クラッシュ・セッション切断は
  起きないが、`update`/`rescan`の応答`updating_db: JOBID`が実MPD仕様の要求する
  「呼び出しごとに一意で単調増加」でなくなり、ジョブIDで完了を追跡するクライアントを
  誤らせうる。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが、
  translator.pyの他の揮発性ストア群と同じ観点で横断調査し新規発見・追加した項目。
  verified: mpdupdatejobrace-patch.py。まず`_update_job_id += 1`と同じロジックを
  素のPythonで再現し、`sys.setswitchinterval`を極小値にして8スレッド×2000回
  (計16000回)並行呼び出しするオフライン決定的再現テストで、214件のduplicate job id
  (カウンタ自体も本来の16000ではなく15812までしか進まない=加算のロスト) が確実に
  発生することを確認 (この時点ではロック無しの合成テストであり、実際のtranslator.py
  は未変更)。修正: mpdqueuestorerace-patch.py等と同じ流儀で専用の`threading.RLock()`
  (`_update_lock`)を導入し、`next_update_job_id()`/`get_db_update_time()`を
  `with _update_lock:`で直列化。パッチ適用後の生成ソースは一時コピーに当てて
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`にmpdmountrace-patch.pyの直後に登録しビルド成功、生成
  ソースに`_update_lock`を用いた新実装が反映されていることを確認した上で、
  dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで確認 — 単発の
  `update`→`updating_db: 1`、`update`→`updating_db: 2`、`rescan`→
  `updating_db: 3`と単調増加することをまず確認。**レース再現確認**: 12並列
  クライアントが`update`/`rescan`を交互に計60回ずつ(合計720回)連打する負荷試験を
  実施 — 修正後は720件全てのjob idが一意(duplicate 0件)、クライアント側エラー0件、
  mopidy.logにTraceback/ERROR 0件を確認 (このレース条件を再現する構成で検証)。
  旧来の`tagtypes`/`status`(xfade等の他フィールド含む)/`search any`(実データ、
  YOASOBI)/`crossfade 5`→`status`反映の回帰なしも確認。
- [x] フィルタ式全体を丸ごと否定する `(!(EXPRESSION))` (musicpd.org/mpd.readthedocs.io
  仕様上 `!=` と等価と明記) が、`_query_from_mpd_filter_expression`
  (mpdsearch/mpdnegfilter/mpdfilterkind-patch.py適用後) の「直前のクオート文字から
  `rfind`で`(`を探して`TAG OP`を切り出す」実装により外側の`!`を一度もスキャンせず、
  通常の肯定条件として誤解釈されてしまう不具合。エラーにはならず`OK`で結果が
  サイレントに反転する (例: 「Xを含まない曲」のつもりが「Xのみ」になる)。
  find/search/findadd/searchadd/searchaddpl/count/playlistfind/playlistsearch/
  searchplaylistが全て同じ`_query_from_mpd_filter_expression`または
  current_playlist.pyの`_pf_matches`を経由するため同じ影響を受ける。TODO/既知の
  軽微な残課題を全項目消化済みのため自走エージェントがソースを横断調査し新規発見・
  追加した項目 (WebFetchでmpd.readthedocs.io/protocol.htmlのFilters節の
  `(!EXPRESSION)`構文を確認済み)。
  verified: mpdnegexpr-patch.py。`op_open`(`(`の位置)の直前(空白許容)に`!`があるかを
  `_neg_wrap`として検出し、演算子トークン自体が`!=`/`!~`かどうか
  (`_op_is_neg_token`)とのXORで最終的な否定有無を決定 (`!(field != "x")`という
  二重否定も理屈通り肯定条件へ潰れる)。これに伴いnegativesの内部形式を
  `(field, is_regex, value)`から、positivesと同じ`(field, kind, value)`
  (exact/contains/starts_with/regex)へ統一し、`_mpd_track_excluded`
  (music_db.py)と`_pf_matches`のnegativesループ(current_playlist.py、
  stored_playlists.pyのsearchplaylistもこれを再利用)を4種判定に揃えた
  (旧来`!=`/`!~`はexact/regexの2種類しか後段フィルタで区別できず、
  `!(tag contains "x")`のような一般否定を表現できなかったための統一)。まず
  `_query_from_mpd_filter_expression`単体をスタブ環境でオフライン抽出・実行し、
  `(!(artist == "ABBA"))`→`__mpd_negatives__:[('artist','exact','ABBA')]`、
  `(!(artist contains "ABBA"))`→kind='contains'、`(!(artist =~ "ABBA"))`→
  kind='regex'、二重否定`(!(artist != "ABBA"))`→肯定`__mpd_positives__`へ、
  という期待通りの分類を確認。パッチ適用後の生成ソース(music_db.py/
  current_playlist.py)は一時コピーに当てて`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`にmpdupdatejobrace-patch.py
  の直後に登録しビルド成功、生成ソースに`_neg_wrap`/`for field, kind, needle in
  negatives`を用いた新実装が反映されていることを確認した上で、dev mopidy(6601,
  ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  (1) `find "(Artist == \"YOASOBI\")"` → 44件 (正)。
  (2) `find "((Artist == \"YOASOBI\") AND (!(Artist == \"YOASOBI\")))"`
  (自己矛盾: YOASOBIかつYOASOBIでない) → 修正前なら`!`が無視され(1)と同じ44件に
  なるところ、修正後は正しく**0件**。
  (3) `find "((Artist == \"YOASOBI\") AND (!(Artist == \"NonExistentXYZ999\")))"`
  (存在しないアーティストの否定、何も除外されないはず) → 期待通り(1)と同じ44件。
  (4) `search "((artist contains \"YOASOBI\") AND (!(artist contains
  \"YOASOBI\")))"` → 0件、`search "(...) AND (!(artist contains
  \"NoSuchArtistXYZ\"))"` → 46件 (containsのwrapped否定も同様に正しく機能)。
  (5) 既存の明示的`!=`トークン (`find "((Artist == \"YOASOBI\") AND (Artist !=
  \"YOASOBI\"))"` → 0件) に回帰が無いことを確認。
  (6) `playlistfind`(current_playlist.py、キュー内走査の`_pf_matches`経由) でも
  同型の自己矛盾テスト: `searchadd`でYOASOBI 10曲をキューに追加した上で
  `playlistfind "(Artist == \"YOASOBI\")"`→10件、自己矛盾AND→**0件**、
  存在しないアーティストの否定AND→10件のまま、と同じ結果を確認し
  current_playlist.py側の修正も実機検証できた。
  (7) 全テストを通してmopidy.logにTraceback/ERROR 0件、`status`が引き続き正常
  応答することを確認 (回帰なし)。
- [x] `stringnormalization enable strip_diacritics` (MPD 0.25+、mpdstringnorm-patch.py)
  が、`search`/`searchadd`/`searchaddpl`/`searchcount`のうちフィルタ式
  (`(TAG OP "VALUE")`、mpdnegfilter-patch.py/mpdfilterkind-patch.pyが実装したkind付き
  否定/肯定条件、rmpcの検索UIが実際に送信する形式)を使った検索には一切効かない不具合。
  mpdstringnorm-patch.py自身のコメントは当時「search/find/count/listは全て
  context.core.library.search()へのバックエンド丸投げで、ローカルな文字列比較を一切
  行わないためdiacriticsストリップを適用する対象コードが存在しない(mount/crossfadeと
  同種の割り切り)」と明記していたが、その後のmpdnegfilter-patch.py/mpdfilterkind-patch.py
  が「バックエンドから取得済みのTrackに対するローカル後段フィルタ」
  (`_mpd_filter_negatives`/`_mpd_filter_positives`、music_db.py)を追加しており、
  mpdnegfilter-patch.pyのBACKLOG記述自身も「find/search/findadd/searchadd/searchaddpl/
  countはローカルデータへの後処理のため、mount/crossfade/stringnormalization-on-searchの
  ような『バックエンド丸投げのため対応不能』という制約が本質的に存在しない」と明記して
  いた。つまりstrip_diacriticsを配線する余地がすでに存在していたにも関わらず、
  mpdstringnorm-patch.py側の「対応不能」判断が更新されないまま放置されていた不具合
  (TODO全項目消化済みのため自走エージェントが横断調査し新規発見・追加した項目。
  current_playlist.pyの`_pf_matches`(playlistfind/playlistsearch用)は既に
  `context.session.string_normalization`を見て`_pf_strip_diacritics`を適用済みだが、
  music_db.pyには同等ロジックが皆無(patch前はgrepで`strip_diacritics`が0件ヒット)
  だったことを確認した上で着手)。
  verified: mpdsearchdiacritics-patch.py。current_playlist.pyの`_pf_strip_diacritics`
  (NFD分解→結合文字(Mark)除去→NFC、実MPDのICU "NFD; [:M:] Remove; NFC"
  transliteratorと同じアルゴリズム)と同一の`_mpd_strip_diacritics`をmusic_db.pyにも
  追加し、`_mpd_track_excluded`/`_mpd_track_matches_positives`/`_mpd_filter_negatives`/
  `_mpd_filter_positives`/`_mpd_count_grouped`に`strip_diacritics`引数(既定False)を
  追加、`search`/`searchadd`/`searchaddpl`/`searchcount`の呼び出し元で
  `context.session.string_normalization`から算出して配線(実MPD仕様通り`count`/`find`/
  `findadd`は対象外のため変更なし)。パッチ適用後の生成ソースは一時コピーに当てて
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`にmpdnegexpr-patch.pyの直後に登録しビルド成功、生成ソースに
  `_mpd_strip_diacritics`を用いた新実装が反映されていることを確認した上で、
  dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  (1) 実際にYTMusic上に存在するアクセント付き公式アーティスト"Beyoncé"(非アクセントの
  "beyonce"では通常のダミーアーティスト群としか一致しない環境)を用い、legacy形式
  `search artist "beyonce"`(バックエンド丸投げのみ)ではバックエンドのリモート検索が
  既に非アクセント一致で"Beyoncé"を返すことをまず確認。
  (2) フィルタ式`search "(artist contains \"beyonce\")"`(strip_diacritics無効時)では
  バックエンドが返した"Beyoncé"がローカル後段フィルタ(`"beyonce" in "beyoncé".lower()`
  が偽)でサイレントに除外され結果に含まれない(0件)ことを修正前の実際の欠陥として確認。
  (3) `stringnormalization enable strip_diacritics`後に同じ`search`を送ると
  "Artist: Beyoncé"を含む32件がヒットし修正が機能することを確認、
  `stringnormalization disable strip_diacritics`後は再び除外される(件数が戻る)ことも確認。
  (4) `searchcount "(artist contains \"beyonce\")"`が無効時13件→有効時18件→再度無効化で
  13件に戻ることを確認。
  (5) `searchadd`でも同様に有効時のみ"Beyoncé"(Halo等の実トラック)がキューに追加される
  ことを`playlistinfo`で確認。
  (6) 実MPD仕様通りstrip_diacriticsの対象外である`count "(artist contains
  \"beyonce\")"`(常に13件のまま、stringnormalization enable後も不変)、および
  `find "(Artist == \"YOASOBI\") AND (!(Artist == \"YOASOBI\"))"`
  (mpdnegexprの自己矛盾テスト、0件)、`find "(Artist == \"YOASOBI\")"`(baseline)、
  `tagtypes`/`status`が引き続き正常応答することを確認(回帰なし)。
  (7) テスト中に発生した`mopidy_ytmusic`のERROR("YTMusic failed parsing artist ...",
  ytmusicapi navigation.pyのKeyError: 'content')は`parseSearch()`が検索結果アーティストの
  詳細(get_artist_albums等)を追加取得しようとして失敗する既存の(try/exceptで捕捉済み・
  セッション継続)警告であり、本パッチのローカルフィルタ処理(バックエンドから結果を
  受け取った後の処理)より前段の既存コードパスで発生するため無関係、かつ`search`自体は
  引き続き正常に`OK`応答することを確認した(新規リグレッションではない)。
- [x] mpd-patch.pyが実装したalbumart/readpicture用の画像キャッシュ`_MPDART_CACHE`
  (uri -> ダウンロード済み画像バイト列)が、mpdurimaprace-patch.py/
  mpdchannelrace-patch.py/mpdpartitionrace-patch.py/mpdmountrace-patch.py/
  mpdqueuestorerace-patch.py/mpdupdatejobrace-patch.py が修正した他の揮発性ストアと
  全く同じ理由(全クライアント接続、各々別スレッドのMpdSessionアクターがロック無しで
  共有dictへ同時アクセス)でスレッド安全性を欠いていた不具合。TODO/既知の残課題を
  全項目消化済みのため自走エージェントが横断調査(rmpc本体のalbumart/readpicture呼び出し
  経路を確認した上で、mpd-patch.pyが実装したキャッシュ周りを再監査)して新規発見・
  追加した項目(パッチ本体は前回セッションの自走エージェントが未コミットのまま
  `configs/media/mopidy/mpdalbumartrace-patch.py`として作成済みだったものを、
  今回のセッションで検証・登録・コミットまで完了させた)。
  実害(KeyErrorによるセッション切断): `_mpdart_bytes()`は`if uri in _MPDART_CACHE:
  return _MPDART_CACHE[uri]`という「存在確認」と「取得」が別々の2文(アトミックでない)
  になっており、この間に別クライアントのリクエストがちょうど65件目のキャッシュを
  追加して`if len(_MPDART_CACHE) > 64: _MPDART_CACHE.clear()`を実行すると、前者の
  `uri in _MPDART_CACHE`がTrueと判定した直後にdictが丸ごと空になり、後続の
  `_MPDART_CACHE[uri]`がKeyErrorを送出する。`KeyError`は`exceptions.MpdAckError`の
  サブクラスではないため`dispatcher.py`の`_catch_mpd_ack_errors_filter`に捕捉されず、
  `session.py`にも保護が無いためpykkaアクターの外まで伝播し、そのalbumart/readpicture
  を実行した接続がACKエラー無しに問答無用で切断される(mpdurimaprace-patch.py等一連の
  race修正と同型の実害)。rmpcはブラウズ画面でアルバムアート格子を表示する際、多数の
  albumart/readpictureリクエストを短時間に並行して送るため、キャッシュが64件を
  超えた直後にヒットしたばかりのURIへアクセスが集中する状況は現実的に起こりうる。
  verified: mpdalbumartrace-patch.py。モジュールレベルの`threading.Lock()`
  (`_mpdart_lock`)を導入し、`_mpdart_bytes()`内の`_MPDART_CACHE`への読み書き
  (存在確認+取得、サイズ上限チェック+clear+新規登録)をそれぞれ`with _mpdart_lock:`
  で直列化。ネットワークダウンロード(urlopen、数百ms〜数秒かかりうる)は意図的に
  ロック区間の外に置き、他クライアントのキャッシュヒットをダウンロード完了まで
  ブロックさせないようにした(mpdqueuestorerace-patch.py等と同じトレードオフの判断を
  踏襲)。パッチ適用後の生成ソースは`ast.parse`で構文確認、2回適用しても冪等
  (スキップ)であることを確認。`nix/lib/mopidy-env.nix`にmpdsearchdiacritics-patch.pyの
  直後に登録しビルド成功、生成ソースに`_mpdart_lock`を用いた新実装が反映されている
  ことを確認した上で、dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機
  確認 —
  (1) `search any "yoasobi"`で取得した実トラック/アルバムURIに対し`albumart`を実行し、
  アルバム(`ytmusic:album:...`)では実際にJPEGバイト列(`\xff\xd8\xff\xe0...JFIF`)が
  正しく返り、mopidy.logにTraceback/ERRORが出ないこと(基本機能の回帰なし)を確認。
  (2) 2種類のURIへ交互に振り分けた20並行TCP接続で同時に`albumart`を送るストレス
  テストを実施(ytmusicapi実ネットワーク呼び出しのため個々の応答は低速だったが)、
  mopidy.logにTraceback/ERROR/KeyError 0件・サーバプロセス生存・処理完了後の
  `status`/`tagtypes`が引き続き即座に正常応答することを確認(回帰なし、パニックによる
  セッション無条件切断が発生していないことを確認)。
  (3) 実機ネットワーク経由では狙ったタイミングでのレース再現が確率的なため、
  ビルド後の実モジュール(`mopidy_mpd.protocol.connection`)を直接importし、
  64スレッド×20回反復×200種のURIで`_MPDART_CACHE`の64件境界を継続的に跨がせる
  決定的ストレステストを実施しエラー0件を確認。
  (4) 検証の妥当性を担保するため、パッチ前の旧ロジック(ロック無しの
  `if uri in cache: return cache[uri]`)を`threading.Event`で人為的に「存在確認直後に
  別スレッドがclear()を割り込ませる」よう決定的に再現し、実際に`KeyError`が
  発生することを確認(修正が実在するバグに対応していることを確認)。同じ強制割り込みの
  仕組みで、パッチ適用後の実モジュールでは`_mpdart_lock`が臨界区間を実効的に排他制御し
  (ロック保持中は同一ロックの別スレッドからの`acquire(timeout=...)`が失敗する)ことを
  直接確認。
- [x] `command_list_end`(command_list.py)のリプレイループが、`idle`/`noidle`を list 内の
  1コマンドとして本物のハンドラで再実行してしまう不具合。musicpd.org protocol
  (command list section) は "Only synchronous commands can be used in a command list.
  idle and noidle are not allowed." と明記しているが、mopidy_mpdはmpdcmdlistnest-patch.py
  で command_list_begin/command_list_ok_begin のネスト再実行こそ塞いだものの、
  idle/noidle は未ガードのままだった。TODO 全項目消化済みのため自走エージェントが
  command_list.py/dispatcher.py/status.pyを横断監査し新規発見・追加した項目。
  実害(以後のOK応答喪失+次コマンドでの無条件切断): `command_list_begin`/`idle`/
  `command_list_end`を送ると、リプレイループが`context.dispatcher.handle_request("idle",
  current_command_list_index=0)`を入れ子で呼ぶ。status.pyの`idle()`はSUBSYSTEMS未指定
  なので`context.subscriptions`へ全サブシステムを登録して`None`を返し、
  `_idle_filter`はハンドラ実行後`if self._is_currently_idle(): return []`により
  応答を握り潰す。ループを抜けた後、外側の`command_list_end`自身の
  `handle_request`呼び出しも同じ`_is_currently_idle()`(subscriptions populate済み)
  でTrueになるため、`command_list_end`に対する"OK"応答までもが黙って握り潰され、
  クライアントは一切の応答を受け取れない。さらに接続は「idle中」のまま固着し、
  クライアントが次に何を送っても(例:`status`)`_idle_filter`の
  `session.close()`によりACKエラーすら返さずTCP接続を問答無用で切断する。
  verified: mpdcmdlistidle-patch.py。mpdcmdlistnest-patch.pyがcommand_list_begin/
  command_list_ok_beginに行ったのと同じ手法(ハンドラ本体を呼ばずリプレイループ内で
  直接ACKを返す)をidle/noidleにも適用。実MPD(src/client/Process.cxx)がlist内の
  idle/noidleをACK_ERROR_NOT_LIST(1)で拒否するのに倣い同じエラーコードで即座に
  list処理を打ち切るよう、command_list_end()の分岐に`elif command_name in ("idle",
  "noidle")`を追加(ハンドラを一切呼ばないためcontext.subscriptions/
  self.command_list_indexの汚染も起こり得ない)。パッチ適用後の生成ソースは
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることを確認。
  `nix/lib/mopidy-env.nix`にmpdcmdlistnest-patch.pyの直後に登録しビルド成功、
  生成ソースに`ACK_ERROR_NOT_LIST`を用いた新実装が反映されていることを確認した上で
  dev mopidy(6601)を実際に起動しMPDで実機確認 —
  (1) `command_list_begin`/`idle`/`command_list_end`を送信 →
  `ACK [1@0] {idle} not allowed in a command list`が即座に返り(旧実装なら無応答の
  まま固着していた)、続けて送った`status`も正常応答(セッションが生きていることを
  確認、旧実装ならここでACK無しに問答無用切断されていた)。
  (2) `command_list_begin`/`noidle`/`command_list_end`でも同様に
  `ACK [1@0] {noidle} not allowed in a command list`となり、後続`status`も正常応答。
  (3) `command_list_begin`/`ping`/`status`/`command_list_end`(idle/noidleを含まない
  通常のcommand list)が引き続き正常に"OK"で終わる回帰なしを確認。
  (4) list外での通常の`idle`→`noidle`(即時解除)が引き続き"OK"を返し、続く`status`も
  正常応答する回帰なしを確認。mopidy.logにTraceback/ERROR 0件。
- [x] `mopidy_ytmusic.library.py`の`parseSearch()`のうち`resultType=="artist"`分岐が
  `get_artist(browseId)["songs"]["results"]`からTrackを作る唯一のループだけ、
  同じ関数内の`song`分岐(`if result["videoId"] is None: continue`、以前から存在)や
  `playlistToTracks`/`uploadArtistToTracks`/`albumToTracks`/`uploadAlbumToTracks`
  (ytunavailabletrack-patch.py)と違いvideoId欠落曲のガードを一切持たず、削除/非公開/
  地域制限曲(ytmusicapiが`videoId: None`で返す、ytunavailabletrack-patch.pyが確認済みの
  実データ仕様)を無条件で`self.TRACKS`キャッシュへ書き込んでしまう不具合。
  TODO全項目消化済みのため自走エージェントがExploreサブエージェントに調査を委任し
  新規発見・追加した項目(既存137パッチのうちこのループにvideoIdガードを追加した
  ものは無いことを確認した上で着手)。
  実害: (1) `self.TRACKS[None]`がLibraryProviderインスタンス寿命全体で共有される
  キャッシュへ書き込まれ、以後別のアーティストの別の再生不能曲でも同じキャッシュ
  エントリ(最初に遭遇した曲のタイトル・アーティストのまま)を共有してしまう
  (ytunavailabletrack-patch.pyが他4関数で確認したのと同型のデータ破損)。
  (2) 再生不能な`ytmusic:track:None`がそのまま`search artist`/`search albumartist`
  等の結果に混入し、選択すると再生に失敗する。
  verified: ytartistsongsvideoid-patch.py。ytunavailabletrack-patch.pyと同じ流儀で
  ループ先頭に`if not song.get("videoId"): continue`を追加しキャッシュ汚染を防止、
  さらに1曲単位のtry/exceptで残りの曲の処理を継続するようにした。パッチ適用後の
  生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等
  (スキップ)であることを確認。`nix/lib/mopidy-env.nix`にはlibrary.pyへ触れる
  ytmusic側パッチ列の最後(ytscrobblethreshold-patch.pyの直後)に登録しビルド成功。
  まず**オフライン単体テスト**でバグを実際に再現・修正を検証: `videoId: None`と
  `videoId: "VALID123"`の2曲を返す偽の`get_artist()`をスタブしparseSearch()を
  直接呼び出したところ、**パッチ前**の生成ソースでは`self.TRACKS`に
  `None`(NoneType)と`'None'`(文字列、末尾の`parse_uri()`再キャッシュ経由)の
  両方のキーが汚染混入し、`ytmusic:track:None`という無効なURIのTrackが
  `SearchResult.tracks`にそのまま混入することを確認。**パッチ後**は同じ入力で
  `self.TRACKS`に`'VALID123'`のみが残り(`None`/`'None'`は不在)、有効な曲のみが
  結果に含まれることを確認(バグの再現とその解消の両方を実証)。
  続けてdev mopidy(6601, ytmusic実アカウント)を実際に起動し`search artist
  "YOASOBI"`をMPDで実行、返ってきた全`ytmusic:track:*` URI(15件)に`None`を
  含む不正な値が無いことを確認、mopidy.logにTraceback/ERROR 0件で起動・検索とも
  クリーンな回帰なしを確認(このテストアカウントの実データには偶然
  videoId=None曲が含まれていなかったため、実害の再現自体はオフライン単体テストで
  行い、実機では起動・検索の無回帰確認に絞った)。
- [x] `mopidy_listenbrainz.listenbrainz.Listenbrainz.list_playlists_created_for_user()`だけが
  `check_response_status(response)`(非200で自作例外`_RequestError`を送出)を
  try/exceptで囲んでおらず、同ファイル内の`validate_token()`/`submit_listen()`/
  `_collect_playlist_data()`が全て`try: ... except _RequestError: ...`で握りつぶして
  いるのと非対称になっている不具合。TODO全項目消化済みのため自走エージェントがExplore
  サブエージェントに調査を委任し新規発見・追加した項目(`lb-patch.py`は`submit_listen()`の
  空`release_name`のみが対象で本件とは無関係であることを確認した上で着手)。
  実害: ListenBrainz APIが一時的に非200(401/429/5xx等)を返すと`_RequestError`が
  呼び出し元`frontend.py`の`ListenbrainzFrontend`まで素通りする。(1)
  `on_start()`内の初回`import_playlists()`呼び出し中に発生すると、pykkaの
  `ThreadingActor.on_start()`内の未捕捉例外としてactor自体がクラッシュし、
  ListenBrainz連携(scrobble含む)全体がプロセス生涯にわたり無効化される。
  (2) 週次再インポートの`threading.Timer`経由の呼び出し中に発生すると、
  `import_playlists()`が例外で中断し末尾の`self._schedule_playlists_import()`に
  到達しないため、次回の週次インポートが二度とスケジュールされなくなる
  (Timerスレッドが黙って死ぬだけでログにも次回予定が残らない)。
  verified: lbplaylistguard-patch.py。`validate_token()`と同じ流儀で
  `try: check_response_status(response) except _RequestError: return []`を追加。
  パッチ適用後の生成ソースは一時コピーに`chmod +w`した上で`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることを確認。`nix/lib/mopidy-env.nix`の
  `listenbrainzPatched`に`lb-patch.py`の直後として登録しビルド成功、生成ソースに
  新実装が反映されていることを確認。ListenBrainzはdev環境では認証情報(secrets)が
  無く`enabled = false`のため実アカウントでの実機起動確認はできないが、代わりに
  **オフライン単体テスト**でバグの再現とその解消の両方を実証: `session.get()`が
  常にHTTP 429を返す偽の`session`を持つ`Listenbrainz`相当のオブジェクトを構築し
  `list_playlists_created_for_user()`を直接呼び出したところ、**パッチ前**
  (lb-patch.py適用済み/lbplaylistguard-patch.py未適用のenv)の生成ソースでは
  `mopidy_listenbrainz.listenbrainz._RequestError`がそのまま送出されることを確認、
  **パッチ後**は同じ入力で例外を送出せず`[]`を返すことを確認。続けてパッチ済み
  envでdev mopidy(6601)を実際に起動し、MPDで`ping`/`status`が正常応答し
  mopidy.logにTraceback/ERROR 0件(`listenbrainz`は設定通り`Disabled extensions`に
  含まれるのみ)であることを確認、ビルド・起動の無回帰を確認した。
- [x] `current_playlist.py`の`add()`が、POSITION(`+N`/`-N`相対指定込み)の解決を
  `context.browse(uri, lookup=False)`(URIスキーム無しのディレクトリ/mopidy-ytmusicの
  プレイリスト等。YouTube Music APIへの同期的なネットワーク呼び出しを伴い数百ms〜
  数秒かかりうる)より**前**に行っていたため、mpdaddloadrace-patch.pyが「末尾追加+move」
  の2段階呼び出しを`at_position`単発呼び出しに統一してTOCTOUレースを解消した後も、
  browse分岐だけ別種のTOCTOUレースが残っていた不具合。TODO全項目消化済みのため
  自走エージェントがExploreサブエージェントに調査を委任し新規発見・追加した項目
  (findadd/searchadd(mpdfindaddrace-patch.py)やload(mpdaddloadrace-patch.py)は
  いずれも時間のかかるデータ取得を先に終えてからposition解決+`tracklist.add()`を
  直前でまとめて行う順序になっており、add()のbrowse分岐だけこの順序から外れていた
  ことを確認した上で着手)。
  実害: `_mpd_resolve_add_position()`は`context.core.tracklist.index()`(現在再生中の
  曲のtracklist上の位置)と`get_length()`(キュー長)に依存するが、これらをbrowse
  **前**に固定してしまうため、browse中に別クライアント(または同一クライアントの
  別接続)がキューを操作すると、実際に`tracklist.add(at_position=position)`が呼ばれる
  時点ではpositionがbrowse開始前の古い状態のまま反映され、ユーザーが「今の曲の次に
  追加」のつもりで送った`add URI "+0"`が意図と無関係な位置に静かに挿入されキュー
  順序が破損する。dev mopidy(6601, ytmusic実アカウント)で実際に再現確認:
  4曲(pos0-3、pos1を再生中)のキューに対し`add "(未ブラウズの91曲のYTMusicプレイリスト)"
  "+0"`を送り応答を待たずに別接続から即座に`next`(pos1→pos2への遷移)を送ったところ、
  追加された91曲は「browse開始前のカレント曲(pos1)の直後」であるpos2に挿入され、
  `next`によって新カレント曲になっていたはずの曲(元pos2)がpos93まで押し出される
  (狙った「新カレント曲の直後」ではなく「新カレント曲の直前」に91曲が挿入される形で
  キュー順序が破損する)ことを確認した上で着手。
  verified: mpdaddbrowserace-patch.py。addid(元からこの種のレースが無い)と同じ
  「position解決の直後に即`tracklist.add()`へ渡す」流儀に揃え、position解決を
  scheme付き分岐・browse分岐それぞれの`tracklist.add()`呼び出し直前(=そのブランチの
  時間のかかる処理が全て完了した後)まで遅延させレース窓を最小化。パッチ適用後の
  生成ソースは一時コピーに`chmod +w`した上で`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることを確認。`nix/lib/mopidy-env.nix`にmpdaddloadrace-patch.pyの
  直後に登録しビルド成功、生成ソースに新実装(position解決が各分岐の`tracklist.add()`
  直前に移動)が反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)
  を実際に起動しMPDで確認。次に`next()`によるカレント曲遷移がGStreamerの再生確認を
  伴い非同期に確定する(コマンド応答が返った後も`status`の`song:`反映にラグがある)
  ため、この非同期ラグと本パッチのbrowse-vs-position-resolutionの窓を厳密に分離した
  単発の再現確認は困難と判断し、代わりにmpdaddloadrace-patch.py自身の検証で採用された
  のと同じ「並行ストレステスト+不変条件確認」の方式で事後検証: 3スレッドで
  `add "(YTMusicの複数アルバム)" [+0|-0|(位置指定無し)]`(browse経由)を、別3スレッドで
  `addid`+`delete "0"`(キュー長変動)を8秒間並行実行 — 接続断・SEND/RECVエラー・
  想定外応答0件、最終`playlistinfo`のPosが0..89の連番で重複・欠落なし(90曲、
  キュー整合性を実際に確認)、この並行実行区間(09:25:06-09:25:19)のmopidy.logに
  Traceback/ERROR 0件を確認(直前の別テストで意図せず巨大なYouTube Musicジャンル
  カテゴリ`listall`相当の再帰browseを踏んでしまい`mopidy.exceptions.TracklistFull`
  という別の未捕捉例外でセッションが1本切断される事象を観測したが、これは
  `context.browse()`の再帰件数無制限という既存の別問題[前述の`listall`blocked項目と
  同根]であり本パッチのposition解決タイミングとは無関係、かつ本ストレステスト区間
  より前のタイムスタンプで発生した無関係な残留処理であることをログのタイムスタンプで
  確認済み)。既存動作の回帰なし確認: 2曲キュー+`play "0"`の状態でbrowse経由の
  絶対位置`add URI "1"`(中間挿入)→正しく挿入され後続曲がシフト、browse経由の
  `add URI "+0"`→実際のカレント曲の直後に正しく挿入、スキーム付きURIの
  `addid URI "+0"`→同様に正しく挿入、境界外の絶対位置`add URI "9999"`→
  従来通り`ACK Bad song index`、存在しないディレクトリ`add "Nonexistent Dir"`→
  従来通り`ACK directory or file not found`、いずれも回帰なしを確認。
- [x] `mopidy_listenbrainz.frontend.ListenbrainzFrontend._collect_playlist_tracks()`内で
  ローカルライブラリ検索で見つからなかった曲を補完するために呼ぶ
  `musicbrainzngs.get_recording_by_id()` (MusicBrainz本家APIへのネットワーク呼び出し)
  だけが無防備で、`_RequestError`(ListenBrainz本家API)を対象にlbplaylistguard-patch.pyが
  ガードした`import_playlists()`と同じ呼び出し経路にある別の外部API呼び出しである
  MusicBrainz本家APIのエラー(`musicbrainzngs.WebServiceError`、NetworkError/
  ResponseError/AuthenticationErrorの親クラス)は素通りしたままだった不具合。
  TODO全項目消化済みのため自走エージェントがmopidy_listenbrainzの全ソース
  (`frontend.py`/`listenbrainz.py`/`playlists.py`/`backend.py`)を直接読んで新規発見・
  追加した項目(lbplaylistguard-patch.pyは`listenbrainz.py`内の`_RequestError`のみを
  対象としており、`frontend.py`内のこの呼び出しとは無関係であることを確認した上で着手)。
  実害: lbplaylistguard-patch.pyと同根 — (1) `on_start()`内の初回`import_playlists()`
  呼び出し中にMusicBrainz APIが一時的にエラー(レート制限/5xx/ネットワーク断等)を返すと、
  pykkaの`ThreadingActor.on_start()`内の未捕捉例外としてactor自体がクラッシュし、
  ListenBrainz連携(scrobble含む)全体がプロセス生涯にわたり無効化される。(2) 週次
  再インポートの`threading.Timer`経由の呼び出し中に発生すると、`import_playlists()`が
  例外で中断し末尾の`self._schedule_playlists_import()`に到達しないため、次回の週次
  インポートが二度とスケジュールされなくなる(Timerスレッドが黙って死ぬだけでログにも
  次回予定が残らない)。
  verified: lbmbidguard-patch.py。`get_recording_by_id()`呼び出しをtry/except
  `musicbrainzngs.WebServiceError`で囲み、失敗時は`mb_recording_query = None`として
  扱う(既存コードの「MusicBrainzに情報が無かった」場合と同じ判定分岐を通るため、
  その曲だけ`found_tracks`が空のままスキップされ、呼び出し元は正常終了まで到達する)。
  パッチ適用後の生成ソースは一時コピーに`chmod +w`した上で`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることを確認。**オフライン単体テスト**でバグの
  再現とその解消の両方を実証: `mopidy.core`/`mopidy.models`/`mopidy.ext`/
  `mopidy.config`/`mopidy.httpclient`をスタブ化して`gi`/GStreamer依存を回避した上で
  `mopidy_listenbrainz`パッケージ全体(`__init__.py`含む、フォルダごとコピーし
  regular packageとして解決されることを確認)をロードし、`musicbrainzngs.get_recording_by_id`
  を常に`NetworkError`を送出する偽関数へ差し替えて`_collect_playlist_tracks()`を
  直接呼び出したところ、**パッチ前**の生成ソースでは`musicbrainzngs.WebServiceError`
  (`NetworkError`)がそのまま送出されることを確認、**パッチ後**は同じ入力で例外を
  送出せず`tracks = []`を返すことを確認。`nix/lib/mopidy-env.nix`の
  `listenbrainzPatched`にlbplaylistguard-patch.pyの直後として登録しビルド成功、
  生成ソースに新実装(try/except節)が反映されていることを確認した上でdev
  mopidy(6601)を実際に起動、MPDで`ping`/`status`が正常応答しmopidy.logに
  Traceback/ERROR 0件(`listenbrainz`は設定通り`Disabled extensions`に含まれるのみ)
  であることを確認し、ビルド・起動の無回帰を確認した。
- [x] `mopidy_listenbrainz.listenbrainz.Listenbrainz`の`validate_token()`/`submit_listen()`/
  `list_playlists_created_for_user()`/`_collect_playlist_data()`が、いずれも
  `check_response_status(response)`(非200応答を自作例外`_RequestError`に変換)は
  try/exceptで保護済み(lb-patch.py/lbplaylistguard-patch.py適用後)だが、その手前の
  `self.session.get()`/`self.session.post()`自体はtryの外側で無防備なままだった不具合。
  TODO全項目消化済みのため自走エージェントがExploreサブエージェントに調査を委任し
  新規発見・追加した項目(既存のlb-patch.py/lbplaylistguard-patch.py/lbmbidguard-patch.py
  のいずれも`check_response_status()`のtry/exceptのみを対象にしており、
  `session.get()`/`post()`自体を対象にしたパッチが存在しないことをgrepで確認した上で
  着手)。
  実害: lbplaylistguard-patch.py/lbmbidguard-patch.pyと同根 — ListenBrainz APIが
  一時的に非200を返す場合は`_RequestError`として握りつぶされ既に安全だが、
  DNS失敗/接続拒否/タイムアウト等のネットワーク層エラーは
  `requests.exceptions.RequestException`(ConnectionError/Timeout等)として
  `check_response_status()`呼び出しより前でraiseされるため誰にも捕捉されず素通りする。
  (1)`validate_token()`は`Listenbrainz.__init__()`から同期的に呼ばれ、それは
  `ListenbrainzFrontend.on_start()`から呼ばれるため、pykkaの
  `ThreadingActor.on_start()`内の未捕捉例外として起動直後にactor自体がクラッシュし
  Scrobble含むListenBrainz連携全体がプロセス生涯にわたり無効化される。
  (2)`list_playlists_created_for_user()`/`_collect_playlist_data()`は
  `import_playlists()`経由(on_start初回または週次再インポートのthreading.Timer経由)の
  呼び出し中に起きると同様にactorクラッシュ/週次再インポート永久停止を招く。
  (3)`submit_listen()`(再生の都度呼ばれるscrobble本体)で起きると、ネットワーク瞬断の
  たびに呼び出し元まで例外が伝播しうる。
  verified: lbnetguard-patch.py。各関数について既存の
  `try: check_response_status(response) except _RequestError: <既存の戻り値>`を、
  `self.session.get()`/`post()`呼び出しも同じtryに含め、exceptを
  `except (requests.exceptions.RequestException, _RequestError):`に拡張(戻り値は
  各関数の既存の`_RequestError`処理と同一のものを流用するため正常系の後続処理には
  無影響)。`list_playlists_created_for_user()`/`_collect_playlist_data()`は
  `self.session.get(...)`のurlに使う`path`変数のf文字列が同一のためアンカーが
  衝突しうるが、直前の`path = LIST_PLAYLIST_CREATED_FOR_ENDPOINT.format(...)`/
  `path = PLAYLIST_ENDPOINT.format(...)`行を含めた全体一致で一意性を確保。
  パッチ適用後の生成ソースは一時コピーに`chmod +w`した上で`ast.parse`で構文確認、
  2回適用しても冪等(4関数とも`already guarded`でスキップ)であることを確認。
  **オフライン単体テスト**でバグの再現とその解消の両方を実証:
  `self.session`を常に`requests.exceptions.ConnectionError`を送出する偽の
  `FakeSession`に差し替えた`Listenbrainz`インスタンス(`object.__new__`で`__init__`を
  バイパスし`token`/`url`/`session`/`user_name`を直接セット)に対し4関数すべてを
  直接呼び出したところ、**パッチ前**(lbnetguard-patch.py未適用のenv)の生成ソースでは
  4関数すべてで`requests.exceptions.ConnectionError`がそのまま送出されることを確認、
  **パッチ後**は同じ入力で4関数とも例外を送出せず、各関数の既存の`_RequestError`
  処理と同じ戻り値(`validate_token`→`False`、`submit_listen`→`None`、
  `list_playlists_created_for_user`→`[]`、`_collect_playlist_data`→`None`)を
  返すことを確認した。`nix/lib/mopidy-env.nix`の`listenbrainzPatched`に
  lbmbidguard-patch.pyの直後として登録しビルド成功、生成ソースに新実装
  (`self.session.get/post()`を含む`try`ブロックと拡張された`except`節)が
  反映されていることを確認した上でdev mopidy(6601)を実際に起動し、MPDで
  `status`/`close`が正常応答しmopidy.logにTraceback/ERROR 0件(`listenbrainz`は
  設定通り`Disabled extensions`に含まれるのみ)であることを確認し、ビルド・起動の
  無回帰を確認した。
- [x] `mopidy_listenbrainz.listenbrainz.Listenbrainz.__init__()`が、`validate_token()`の
  戻り値`False`を「トークンが本当に無効(200応答のvalid:false)」と「一時的な
  ネットワーク層エラー(lbnetguard-patch.py適用後、`session.get()`自体の
  `RequestException`や非200応答の`_RequestError`も同じくFalseとして返る)」の
  両方で区別せず、いずれも同じ`raise RuntimeError(f"Token {token} is not valid")`へ
  変換してしまう不具合。TODO全項目消化済みのため自走エージェントがExploreサブ
  エージェントに新規発見を委任し着手(lbnetguard-patch.pyはあくまで
  `validate_token()`等4関数の`session.get()`/`post()`自体を対象にしており、
  `__init__()`の`raise RuntimeError`行自体はいずれの`lb*-patch.py`からも
  触れられていないことをgrepで確認)。
  実害: lbplaylistguard-patch.py/lbmbidguard-patch.py/lbnetguard-patch.pyが
  繰り返し解消してきたのと同じ「actor起動時クラッシュ」症状が、
  `validate_token()`自体をガードしたことで一段深いこの箇所に移動しただけで
  残っていた。mopidy起動時(`ListenbrainzFrontend.on_start()`から
  `Listenbrainz(...)`を同期構築する経路)にListenBrainz APIへ一時的に到達できない
  状態(起動直後のDNS不安定・API側の瞬断・レート制限/5xx等)だと、
  `validate_token()`は例外を送出せず静かにFalseを返すが、`__init__()`はこれを
  「トークン無効」と誤解して新たにRuntimeErrorを送出し、pykkaの
  `ThreadingActor`の`on_start()`未捕捉例外としてactor自体が停止、ListenBrainz
  連携(scrobble含む)がプロセス生涯にわたり無効化される。
  verified: lbtokennetguard-patch.py。`validate_token()`の戻り値をbool型から
  `Optional[bool]`へ拡張し、例外(`RequestException`/`_RequestError`)発生時は
  「無効と判定できた」Falseではなく「判定不能」を表すNoneを返すよう変更。
  `__init__()`側はNoneのときはRuntimeErrorを送出せずwarningログのみで起動を
  継続し(`submit_listen()`等は各呼び出し単位で既にRequestExceptionを自己防御済み
  のため接続回復後は自然に成功するようになる)、Falseのとき(本当に無効、200応答
  でvalid:falseが返った場合)のみ従来通りRuntimeErrorでfail-fastする(回帰なし)。
  パッチ適用後の生成ソースは一時コピーに`chmod +w`した上で`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることを確認。**オフライン単体テスト**で
  バグの再現とその解消の両方、および回帰なしを実証: `mopidy_listenbrainz`
  パッケージをフォルダごとコピーしEnvのpython3.13(requests/musicbrainzngs等の
  依存込み)で`object.__new__`により`__init__`をバイパスした`Listenbrainz`
  インスタンスに対し、`session.get()`/`post()`が常に`ConnectionError`を送出する
  `FakeSession`を注入して`validate_token()`→`__init__`相当のロジックを直接実行
  したところ、**パッチ前**の生成ソースでは`RuntimeError("Token ... is not
  valid")`が送出されることを確認(バグ再現)、**パッチ後**は同じ入力で
  `token_valid is None`となりRuntimeErrorを送出しないことを確認(修正確認)。
  さらに200応答で`{"valid": False}`を返す`FakeSession`(本当に無効なトークン)を
  別途注入したところ、パッチ後も従来通り`RuntimeError`が送出されることを確認し
  (fail-fast動作に回帰なし)。`nix/lib/mopidy-env.nix`の`listenbrainzPatched`に
  lbnetguard-patch.pyの直後として登録しビルド成功、生成ソースに新実装
  (`token_valid = self.validate_token()`/`Optional[bool]`)が反映されていることを
  確認した上でdev mopidy(6601)を実際に起動し、MPDで`status`/`tagtypes`/`ping`/
  `close`が正常応答しmopidy.logにTraceback/ERROR 0件(`listenbrainz`は設定通り
  `Disabled extensions`に含まれるのみのため本パッチ自体の実挙動はオフライン
  単体テストで検証、dev mopidy起動では全体のビルド・起動無回帰のみ確認)である
  ことを確認した。
- [x] `mopidy_ytmusic.library.py`の`playlistToTracks()`/`uploadArtistToTracks()`/
  `parseSearch()`(song分岐、およびartist経由songs分岐)が共通して
  `if X["album"]["id"] not in self.ALBUMS: self.ALBUMS[X["album"]["id"]] = Album(...)`
  という同一パターンを使っており、ytmusicapiの`parse_song_album()`が album のテキスト
  runに`navigationEndpoint`(browseId)が無い場合に返す`{"name": <表示名>, "id": None}`
  (プレイリスト/Liked Songs/History内のリンク不可なアルバム表記を持つ曲、シングル等で
  実際に起こりうる)を無検証で`self.ALBUMS`のキャッシュキーに使ってしまう不具合。
  TODO全項目消化済みのため自走エージェントがgeneral-purposeサブエージェントに新規発見を
  委任し着手(ytartistcache-patch.pyが兄弟キャッシュ`self.ARTISTS`について既に発見・
  修正した「id=Noneを素のままキャッシュキーに使う」のと全く同じバグクラスが、
  `self.ALBUMS`側には一切対応されないまま4箇所とも残っていたことをnix/lib/mopidy-env.nix
  の既存150+パッチ一覧とのクロスリファレンスで確認)。
  実害: `self.ALBUMS`はプロセス寿命全体でキーごとにグローバルにキャッシュされる辞書の
  ため、id=Noneのアルバムに最初に遭遇したトラックの名前で`self.ALBUMS[None]`が一度だけ
  作られ、以後id=Noneの別アルバム(実際には全く別の名前)を持つ全ての曲が誤って同じ
  `Album`オブジェクト(最初の曲のアルバム名のまま)を共有してしまう。クラッシュはしない
  が、rmpcのAlbum/AlbumUri表示・グルーピングが無関係な別トラックのアルバム名で汚染
  される。プレイリスト・Liked Songs・History・検索結果をブラウズする通常経路全てで
  到達しうる。
  verified: ytalbumidcache-patch.py。4箇所全てで`X["album"].get("id")`がfalsyの場合は
  `self.ALBUMS`へキャッシュせず都度その場限りの(uri無し)`Album`を作るよう修正
  (ytartistcache-patch.pyの`self.ARTISTS`対策と同じ流儀)。パッチ適用後の生成ソースは
  一時コピーに`chmod u+w`して書き込み可にした上で`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。**修正前後のオフライン単体テスト**:
  `YTMusicLibraryProvider`を直接import し(`object.__new__`で`__init__`を経由せず
  TRACKS/ALBUMS/ARTISTS/IMAGESのみ手動セットしたダミーインスタンス)、id=Noneだが
  異なる名前を持つ2アルバムを含む合成データで4箇所全て(`playlistToTracks()`/
  `uploadArtistToTracks()`/`parseSearch()`song分岐/`parseSearch()`artist経由songs分岐、
  最後の1つは`self.backend.api.get_artist`を`SimpleNamespace`でモック)を個別に直接
  呼び出し比較 — 修正前(未パッチ)の`library.py`に対して実行するといずれも2曲目の
  アルバム名が実際に1曲目の名前に誤って上書きされる不具合を再現・確認した上で、修正後は
  同じ入力に対し各トラックがそれぞれ正しい自分自身のアルバム名を保持することを確認
  (4箇所とも合格)。回帰確認: 同じidを持つ2曲(id="album123")では従来通り同一の
  `Album`オブジェクトを共有しキャッシュが正しく効くことも別途確認 (`n1.album is
  n2.album`が`True`のまま)。`nix/lib/mopidy-env.nix`の`ytmusicPatched`に
  ytartistsongsvideoid-patch.pyの直後として登録しビルド成功、生成ソース4箇所
  (`library.py:857,941,1216,1375`)に新実装(`if not track["album"].get("id"):`等)が
  反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで確認 — `tagtypes`/`status`/`search any "YOASOBI"`(実データ、Album/
  Title/Dateが個別に正しく反映)/`lsinfo "YouTube Music/Home"`(5セクション)/
  `lsinfo "YouTube Music/Home/Quick picks"`(12曲、`playlistToTracks()`の主経路を
  実データで通し各曲が個別のArtist/Titleで表示されることを確認)の回帰なし・
  mopidy.logを監査しTraceback/ERROR 0件(既知のpre-existing事象である
  `get_liked_songs`("Sign in to view your liked tracks")を除く)を確認した。
- [x] `mopidy_listenbrainz.listenbrainz.py`の`validate_token()`/`list_playlists_created_for_user()`/
  `_collect_playlist_data()`が、`self.session.get()`自体のネットワーク層エラー(lbnetguard-patch.py)
  と非200応答(`_RequestError`)は`try`/`except`で保護済みだが、直後の
  `parsed_response = response.json()`は`try`ブロックの**外側**で無防備なままだった不具合。
  TODO全項目消化済みのため自走エージェントがgeneral-purposeサブエージェントに新規発見を
  委任し着手(既存のlb*-patch.py 5本いずれもcheck_response_status()/session.get()/post()
  自体のみを対象にしており、その後段のresponse.json()呼び出しを対象にしたパッチが
  存在しないことをgrepで確認した上で着手)。
  実害: ListenBrainz APIまたは経路上のプロキシ/CDN/ロードバランサがステータス200
  (=check_response_status()を素通りする)で本文が空/非JSON(HTMLメンテナンスページ、
  Cloudflareチャレンジページ、通信打ち切りによる不完全な応答等)を返すと、`response.json()`は
  `requests.exceptions.JSONDecodeError`を送出する。このクラスは`RequestException`の
  サブクラスではあるが(nix env の python で`JSONDecodeError.__mro__`を実行し
  `InvalidJSONError -> RequestException`の継承を確認済み)、発生箇所がtryブロックの
  外側のため既存の`except (requests.exceptions.RequestException, _RequestError):`には
  一切掛からず素通りする。(1) `validate_token()`は`Listenbrainz.__init__()`から呼ばれ、
  それは`ListenbrainzFrontend.on_start()`から同期的に呼ばれるため、pykkaの
  `ThreadingActor.on_start()`内の未捕捉例外としてactor自体が起動直後にクラッシュし
  ListenBrainz連携がプロセス生涯にわたり無効化される(lbtokennetguard-patch.pyが
  「戻り値の誤判定」経路について解消したのと同じ最終症状を、malformed JSONボディという
  別トリガーから再び引き起こす)。(2) `list_playlists_created_for_user()`/
  `_collect_playlist_data()`は`on_start()`内の初回`import_playlists()`、または週次
  再インポートの生の`threading.Timer`コールバック経由で呼ばれるため、同様にactor
  クラッシュ、または(Timer経由の場合)例外発生地点が`import_playlists()`末尾の
  `self._schedule_playlists_import()`呼び出しより前にあるため次回の週次タイマーが
  二度と再スケジュールされない永久停止を招く(lbplaylistguard-patch.py/
  lbnetguard-patch.pyが解消したのと同じ症状を同じく別トリガーから再現する)。
  verified: lbjsonguard-patch.py。3箇所全てで`try`ブロック内の`check_response_status(response)`
  直後へ`parsed_response = response.json()`を移し、既存の
  `except (requests.exceptions.RequestException, _RequestError):`(`JSONDecodeError`は
  `RequestException`のサブクラスのためそのまま捕捉される)に委ねるよう修正
  (`submit_listen()`は`response.json()`を呼ばないため対象外)。パッチ適用後の生成
  ソースは一時コピーに`chmod u+w`した上で`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることを確認。**修正前後のオフライン単体テスト**でバグの再現と
  その解消の両方、および回帰なしを実証: `mopidy_listenbrainz`パッケージをフォルダごと
  コピーし別プロセスのEnvのpython3.13で`object.__new__`により`__init__`をバイパスした
  `Listenbrainz`インスタンスに対し、`session.get()`が常に`status_code=200`だが
  `.json()`呼び出しで`requests.exceptions.JSONDecodeError`を送出する`FakeResponse`を
  返す`FakeSession`を注入して3関数を直接呼び出したところ、**パッチ前**の生成ソースでは
  3関数全てで`JSONDecodeError`が未捕捉のまま呼び出し元へ伝播することを確認(バグ再現)、
  **パッチ後**は同じ入力で3関数とも例外を送出せず既存の失敗時戻り値
  (`validate_token()`→`None`、`list_playlists_created_for_user()`→`[]`、
  `_collect_playlist_data()`→`None`)を返すことを確認(修正確認)。回帰確認: 正常な
  JSONを返す`FakeSession`では`validate_token()`が従来通り`True`/`user_name`を正しく
  返すこと、およびステータス429(`.json()`を呼ばれたら`AssertionError`を送出するよう
  細工した`FakeResponse`)では`check_response_status()`が`_RequestError`を送出し
  `response.json()`へ到達する前に`except`節で処理されること(=既存の非200経路は
  無変更)を確認した。`nix/lib/mopidy-env.nix`の`listenbrainzPatched`に
  lbtokennetguard-patch.pyの直後として登録しビルド成功、生成ソース3箇所
  (`listenbrainz.py:122,200,265`)に新実装(`check_response_status(response)`直後の
  `parsed_response = response.json()`)が反映されていることを確認した上でdev
  mopidy(6601)を実際に起動しMPDで`status`/`tagtypes`/`ping`/`close`が正常応答し
  mopidy.logにTraceback/ERROR 0件(`listenbrainz`は設定通り`Disabled extensions`に
  含まれるのみのため本パッチ自体の実挙動はオフライン単体テストで検証、dev mopidy起動
  では全体のビルド・起動無回帰のみ確認)であることを確認した。
- [x] `mopidy_mpd/protocol/current_playlist.py`の`prio {PRIORITY} {START:END...}`が、
  `start == キュー長`という境界上の空レンジトークンを実MPDでは無変更でOKとすべきところ、
  一律`ACK Bad song index`にしてしまう不具合。TODO全項目消化済みのため自走エージェントが
  general-purposeサブエージェントに新規発見を委任し着手。兄弟コマンドの
  `delete [{POS}|{START:END}]`は既にこの境界ケースを是正済み(mpddeleteboundary-patch.py、
  実MPD`CheckClip`/`IsEmpty`セマンティクスに合わせ`start > 長さ`のみエラーとし
  `start == 長さ`は無変更でOK)なのに、同じ`current_playlist.py`内の`prio()`だけ
  この区別が実装されておらず`context.core.tracklist.slice(start, end)`が空になる
  ケースを全て無条件で`ACK Bad song index`としていた非対称性がバグの本体。
  実害: rmpcが優先度操作を日常的に送るコマンドではないため実害は極小だが、2クライアントが
  同じキュー末尾領域を同時に操作する競合(片方が`delete`等でキューを縮め、もう片方の
  `prio {P} "N:"`のNがちょうど新しい長さと一致する)で実際に起こりうる、実MPDとの
  可観測なプロトコル差異(delete()と同じ理屈)。
  verified: mpdprioboundary-patch.py。実MPD (MusicPlayerDaemon/MPD
  `src/command/QueueCommands.cxx handle_prio` → `src/queue/PlaylistEdit.cxx
  playlist::SetPriorityRange`) をgh api経由で実際に確認し、`range.CheckClip(GetLength())`
  (`start > count`のみfalse=ACK BadRange)→`range.IsEmpty()`(`start >= end`なら
  例外を投げず`return`のみ)という2段判定であることを特定した上で着手。`prio()`は
  複数のSTART:ENDトークンを列挙できるため、`delete()`(単一レンジで即`return`)と違い
  境界上の空レンジは「そのトークンだけ無視して次のトークンへ進む」(`continue`)よう
  実装(修正: `tl_tracks`が空の場合、`start > 実際の長さ`のときのみ`ACK Bad song index`、
  それ以外はそのトークンをスキップして継続)。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w`した上で`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix`の`mpdPatched`リスト末尾(mpdplaylistinfoargerr-patch.py
  の直後)に登録しビルド成功、生成ソースに新実装が反映されていることを確認した上で
  dev mopidy(6601, ytmusic実アカウント)を実際に起動し、YOASOBI/Ayase/Lilas検索結果
  15曲(`searchadd artist "YOASOBI"`)をキューに積んでMPDで実機確認 —
  `prio 50 "15:"`(open-ended、start==長さ15)→旧実装なら`ACK Bad song index`だったのが
  `OK`(無変更)、`prio 50 "15:20"`(closed、同じ境界)→同じく`OK`(無変更)、
  `prio 50 "16:"`/`prio 50 "20:25"`(真に範囲外`start>長さ`)→従来通り
  `ACK [2@0] {prio} Bad song index`(この場合は引き続きエラーであるべきことを確認)、
  `prio 80 "15:" "2:3"`(境界no-opトークンと有効トークンを同一コマンドに混在)→`OK`で
  `2:3`側のみ`playlistinfo "2:3"`で`Prio: 80`と正しく反映(`continue`による
  トークン単位のスキップが複数トークン処理の残りを壊さないことを確認)。回帰確認:
  `prio 60 "0:2"`(通常の有効レンジ)→`playlistinfo "0:2"`で両曲に`Prio: 60`、
  `prioid 0 1`(既存の`prioid`)→回帰なし、`prio abc "0:1"`(非数値優先度)→
  `ACK incorrect arguments`、`prio 10`(引数不足)→
  `ACK wrong number of arguments for "prio"`。mopidy.logにTraceback/ERROR 0件を確認。
- [x] `mopidy_mpd/protocol/stored_playlists.py`の`playlistadd {NAME} {URI} [POSITION]`が、
  `URI`がバックエンドで実在の曲へ解決できない場合(削除済み/存在しないID等)でも例外を出さず
  黙って`OK`を返してしまう不具合。TODO全項目消化済みのため自走エージェントが
  general-purposeサブエージェントに新規発見を委任し着手。
  実害: `context.core.library.lookup(uris=[track_uri]).get()`はmopidy.core.library
  .LibraryController.lookup()が問い合わせたURIをキーに空リストで事前初期化したdictを
  返す実装のため、解決失敗時も例外は飛ばず`new_tracks == []`になるだけで後続処理が
  そのまま進んでしまっていた。(1) 既存プレイリストへの追加時は`combined_tracks ==
  old_tracks`(無変化)のまま`core.playlists.save()`が成功し`OK`が返り、rmpcは
  「追加成功」と表示するが実際には何も追加されない。(2) 新規プレイリスト作成時は
  `_create_playlist(context, name, combined_tracks=[])`が呼ばれ、0曲の空プレイリストが
  実際に作成された上で`OK`が返り、`listplaylists`にゴミの空プレイリストが残り続ける。
  仕様確認: 実MPD(MusicPlayerDaemon/MPD)をgh api経由で実際にソース確認したところ、
  `handle_playlistadd`(src/command/PlaylistCommands.cxx)は`SongLoader::LoadSong()`
  (src/SongLoader.cxx)経由でURIを解決しており、データベースに存在しない場合は
  `LoadFromDatabase()`が`PlaylistError(PlaylistResult::NO_SUCH_SONG, ...)`を送出、
  ファイルが存在しない場合も`LoadFile()`が`PlaylistError::NoSuchSong()`を送出する
  (常に"No such song"でエラーとして拒否し、黙って無視/空プレイリスト作成にはならない)
  ことを確認。同じmopidy_mpdコードベース内でも`music_db.py`の`readcomments()`や
  `current_playlist.py`の`addid`等多数のコマンドが「lookup結果が空なら
  `MpdNoExistError("No such song")`」という統一方針を取っており、`playlistadd`だけが
  この検証を欠いていた非対称性がバグの本体。
  verified: mpdplaylistaddexist-patch.py。`new_tracks`展開直後、`combined_tracks`
  組み立て前(既存のPOSITION範囲チェックより後、副作用が生じる`_create_playlist`/
  `save`呼び出しより前)に`if not new_tracks: raise exceptions.MpdNoExistError("No such
  song")`を追加。mpdplaylistaddpos-patch.py(POSITION対応)適用後の`playlistadd`実装が
  対象のため、`nix/lib/mopidy-env.nix`の同パッチ直後に登録。パッチ適用後の生成ソースは
  一時コピーに`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  ビルド成功・生成ソースに新実装が反映されていることを確認した上でdev
  mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  `playlistadd "GhostList" "ytmusic:track:doesnotexist12345"`(新規名・無効URI)→
  `ACK [50@0] {playlistadd} No such song`、直後の`listplaylists`→空(ゴーストの
  空プレイリストが作成されていないことを確認)。実データ(YOASOBI「怪物」
  `ytmusic:track:qivRUhepWVA`)で`playlistadd "AgentRealList" "..."`(新規名・有効URI)→
  `OK`、`listplaylistinfo "AgentRealList"`で正しく1曲反映(回帰なし)。既存プレイリストへ
  無効URI追加`playlistadd "AgentRealList" "ytmusic:track:doesnotexist12345"`→
  `ACK [50@0] {playlistadd} No such song`、直後の`listplaylistinfo`で中身が無変化のまま
  (誤った`OK`にならず、既存曲も保持されていることを確認)。既存プレイリストへ有効URI+
  `POSITION`指定`playlistadd "AgentRealList" "ytmusic:track:dGZqpVCJP3k" "0"`→`OK`、
  `listplaylistinfo`で指定位置に正しく挿入。無効URI+有効範囲内POSITION
  `playlistadd "AgentRealList" "ytmusic:track:doesnotexist12345" "0"`→
  `ACK [50@0] {playlistadd} No such song`(POSITION自体は妥当でも曲の存在チェックが
  優先されることを確認)。無効URI+範囲外POSITION
  `playlistadd "AgentRealList" "ytmusic:track:doesnotexist12345" "999"`→
  `ACK [2@0] {playlistadd} Bad position`(既存のPOSITION範囲チェックが本パッチの追加した
  存在チェックより先に評価される順序を維持しており回帰なしであることを確認)。
  `rm "AgentRealList"`で後片付け後`listplaylists`→空。旧来の`tagtypes`/`status`の
  回帰なしを確認。mopidy.logには本パッチ経路とは無関係な既知のpre-existing事象
  (`mopidy_ytmusic.library.getTrack()`が未知/無効IDで送出する`KeyError:
  'videoDetails'`をlookup()内部で捕捉しログのみ出す挙動、およびこのテストアカウントの
  書き込み権限不足による`playlist creation failed...HTTP 401`、いずれもmpdprioboundary
  等の過去エントリで確認済みの事象で新規リグレッションではない)を除きTraceback/ERROR
  なしを確認した。
- [x] `mopidy_listenbrainz/frontend.py`の`ListenbrainzFrontend.track_playback_started()`/
  `track_playback_ended()`が、`", ".join(sorted([a.name for a in track.artists]))`で
  トラックのアーティスト名を無条件に文字列扱いしている不具合。TODO全項目消化済みのため
  自走エージェントが新規発見・着手(前回セッションが調査・パッチ実装まで進めた後
  未コミットのまま中断していた作業を引き継ぎ、nix登録・実機検証・BACKLOG記載・コミットを
  完了させた)。
  実害: `mopidy.models.fields.Field.__set__`(実ソース確認済み: `if value is not None:
  value = self.validate(value)`)はNoneを渡された場合バリデーション自体をバイパスするため、
  `Artist(name=None, ...)`は完全に正当な`mopidy.models.Artist`インスタンスであり、`name`
  フィールドは仕様上optional(非nullを保証しない)。`mopidy_ytmusic/library.py`は複数箇所
  (`playlistToTracks()`の`Artist(name=a["name"], sortname=a["name"], musicbrainz_id="")`等、
  YouTube Music APIのartist dictを`.get("name", "")`のような既定値なしに素通しする箇所)が
  あり、同ファイル内の既存パッチ群(ytartistcache-patch.py/yttopresultartist-patch.py/
  ytmoodgenre-patch.py等)が繰り返し扱ってきた「YouTube Music APIのartistメタデータが
  id/name欠落を伴う」という既知の傾向と整合するため、`Artist(name=None)`を含むTrackが
  実際の再生対象になり得る。`track_playback_started`/`track_playback_ended`は
  `mopidy.core.CoreListener`イベントとして`mopidy.listener.send()`経由でpykkaの
  "tell"(reply_to無し)メッセージとして配送されるため、この中で`sorted([a.name for a in
  track.artists])`が(複数アーティストでNoneと文字列が混在すれば`TypeError: '<' not
  supported between instances of 'NoneType' and 'str'`、単一アーティストでNoneのみなら
  直後の`", ".join(...)`で`TypeError: sequence item 0: expected str instance, NoneType
  found`という形で)TypeErrorを送出すると、pykka `_actor_loop_running()`(実ソース確認済み、
  pykka/_actor.py)の`except Exception:`分岐で`reply_to is None`のため
  `self._handle_failure()`が呼ばれ`ActorRegistry.unregister()` +
  `self.actor_stopped.set()`でactorが永久停止する。`ListenbrainzFrontend.on_start()`は
  プロセス起動時に1度しか呼ばれないため、以後の`submit_listen()`(scrobble)も週次
  プレイリスト再インポートも含めListenBrainz連携全体がプロセス生涯にわたり無効化される。
  lbnetguard-patch.py/lbtokennetguard-patch.py/lbjsonguard-patch.py等は同種の
  「actorクラッシュ」パターンをネットワーク/JSON応答まわりで修正済みだったが、この曲
  メタデータ整形経路(ネットワークI/Oを伴わない)は無防備のまま残っていた。
  verified: lbartistnameguard-patch.py。同じコードベース内の
  `mopidy_mpd/protocol/current_playlist.py`の`_pf_field_values()`
  (`[a.name for a in track.artists if a.name]`、空/None名を除外)と同じ防御を、
  `track_playback_started()`/`track_playback_ended()`両方のアーティスト名整形にも適用
  (`sorted([a.name for a in track.artists])` →
  `sorted(a.name for a in track.artists if a.name)`)。パッチ適用後の生成ソースは
  一時コピーに`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  **修正前後のオフライン単体テスト**でバグの再現とその解消の両方、および回帰なしを実証:
  `mopidy_listenbrainz`パッケージをパッチ前後それぞれフォルダごとコピーし、別プロセスの
  Envのpython3.13で`mopidy.core`/`pykka`/`musicbrainzngs`を軽量スタブに差し替えて
  (GStreamer実バインディング読み込みを回避しつつ`mopidy.models.Track`/`Artist`は実物を
  使用)`object.__new__`で`__init__`をバイパスした`ListenbrainzFrontend`インスタンスに対し、
  `Artist(name=None)`を含む`Track`で`track_playback_started()`/`track_playback_ended()`を
  直接呼び出したところ、**パッチ前**の生成ソースでは両メソッドとも`TypeError`
  (`'<' not supported between instances of 'str' and 'NoneType'`)が未捕捉のまま呼び出し元へ
  伝播することを確認(バグ再現)、**パッチ後**は同じ入力で例外を送出せず`submit_listen()`が
  正しい引数(Noneのartistを除外した文字列)で呼ばれることを確認(修正確認)。回帰確認:
  全アーティストが有効な名前を持つ複数アーティストのTrack(`Artist(name="Zebra")`/
  `Artist(name="Alpha")`)では従来通りソート済みの`"Alpha, Zebra"`が`submit_listen()`へ
  渡されることを確認(正常系は無変更)。`nix/lib/mopidy-env.nix`の`listenbrainzPatched`に
  lbjsonguard-patch.pyの直後として登録しビルド成功、生成ソース2箇所
  (`frontend.py`の`track_playback_started()`/`track_playback_ended()`)に新実装が反映
  されていることを確認した上でdev mopidy(6601)を実際に起動しMPDで
  `status`/`tagtypes`/`ping`/`close`が正常応答し回帰なし、mopidy.logにTraceback/ERROR
  0件を確認した(`listenbrainz`は設定通り`Disabled extensions`に含まれるのみのため
  本パッチ自体の実挙動はオフライン単体テストで検証、dev mopidy起動では全体のビルド・
  起動無回帰のみ確認)。
- [x] `albumart`/`readpicture` (mpd-patch.py が追加) が `command_list` 内で実行されると、
  レスポンスの並び順(プロトコルのフレーミング)が壊れてしまう不具合。TODO 全項目消化済み
  のため自走エージェントが command_list.py/connection.py を再監査して発見した項目。
  実 MPD (musicpd.org, command list section) は「レスポンスは全コマンド分をまとめて返す
  (does not execute any commands until the list has ended)」「Only synchronous commands
  can be used in a command list」とのみ明記するが、mopidy_mpd の command_list_end()
  (mopidy_mpd/protocol/command_list.py) の実装は各コマンドのテキスト応答行を
  `command_list_response` という Python list に一旦蓄積し、リスト全体の処理が終わった
  後にまとめてソケットへ書き出す。ところが `_mpdart_send()` (connection.py の
  albumart/readpicture 実装、mpd-patch.py が追加) は
  `context.session.connection.queue_send(...)` でバイナリチャンクをその場で直接
  ソケットへ書き込むため、この蓄積の仕組みを完全にバイパスしてしまう。関連する既存
  パッチ mpdalbumartrace-patch.py は `_MPDART_CACHE` の TOCTOU/KeyError (並行接続間の
  ロック) を修正したのみで本件とは無関係、mpdcmdlistidle-patch.py/mpdcmdlistnest-patch.py
  も idle/noidle・ネストされた command_list_begin の再実行防止であり、
  albumart/readpicture の queue_send() 直接書き込みには触れていなかった。
  verified: mpdalbumartcmdlist-patch.py。修正前に dev mopidy(6601, ytmusic 実アカウント)
  を実際に起動し生ソケットで実機再現 —
  `command_list_begin` / `status` / `albumart "ytmusic:track:<実在id>" 0` /
  `command_list_end` を送ると、届いたバイト列は
  `size:`/`binary:`ヘッダ+生JPEGバイト(実行順2番目のalbumart)が**先頭**に届き、
  その**後**に`status`のテキスト行(実行順1番目、蓄積されていたぶん)が続き、最後に
  `OK`が1つだけ、という実行順と矛盾した並びになることを確認(修正前バグ再現、
  宣言バイト数だけ読んでから次コマンドの応答をパースするクライアントは確実に
  デシンクする)。修正: mpdcmdlistidle-patch.py が idle/noidle に対して行ったのと
  全く同じ手法(ハンドラ本体を一切呼ばずリプレイループ内で直接 ACK を返す)を
  `albumart`/`readpicture` にも適用し、command_list 内での実行自体を実MPDと同じ
  `ACK_ERROR_NOT_LIST`で即座に拒否(connection.py側の変更は不要)。パッチ適用後の
  生成ソースは一時コピーに`ast.parse`で構文確認、2回適用しても冪等(スキップ)である
  ことも確認。`nix/lib/mopidy-env.nix`にmpdcmdlistidle-patch.pyの直後として登録し
  ビルド成功、生成ソースのcommand_list.pyに新実装が反映されていることを確認した上で
  dev mopidy(6601, ytmusic実アカウント)を実際に起動し実データ(実在track URI)で
  再検証 — 修正後は同じ`command_list_begin`/`status`/`albumart ...`/`command_list_end`
  で`status`の全フィールドが正しい順序で届いた直後に
  `ACK [1@1] {albumart} not allowed in a command list`となりバイナリ混入なし、
  直後の同一接続での`status`も正常応答(接続が生きたままであることを確認)、
  同様に`readpicture`を挟んだcommand_listも`ACK [1@1] {readpicture} not allowed in
  a command list`。回帰確認: command_list外の単独`albumart`/`readpicture`は従来通り
  正しくバイナリ(size/binaryヘッダ+実データ+末尾OK)を返す、command_list内の
  `idle`/`noidle`は既存パッチ通り`ACK [1@1] {idle} not allowed in a command list`
  のまま無変更、albumart/readpictureを含まない通常のcommand_list
  (`ping`+`tagtypes`)は従来通り正常応答。mopidy.logにTraceback/ERROR 0件を確認した。
- [x] `mopidy_listenbrainz/frontend.py`の`ListenbrainzFrontend._collect_playlist_tracks()`が
  ローカルライブラリで見つからない曲をMusicBrainz本家APIから補完しようとするたび、
  実質確実にKeyErrorでactorをクラッシュさせる不具合。TODO全項目消化済みのため
  自走エージェントが新規発見・着手 (lbmbidguard-patch.py等の既存LB系パッチ群を再監査中に
  発見)。
  実害: `musicbrainzngs.get_recording_by_id(track_mbid, includes=["artists"])`の
  `includes=["artists"]`は、musicbrainzngs 0.7.1の`VALID_INCLUDES["recording"]`
  (実ソース確認済み: `musicbrainzngs/musicbrainz.py`)が"artists"と"artist-credits"を
  別々の要素として列挙する通り、recordingの**artist-relation**(作曲者/演奏者等の関係
  グラフ)を追加する include であり、直後にアクセスする`mb_recording["artist-credit-phrase"]`
  を得るのに必要な include ("artist-credits"、末尾sで複数形が異なる) とは別物。
  `mbxml.py`の`parse_recording()`(実ソース確認済み)は`if "artist-credit" in result:`の
  場合のみ`"artist-credit-phrase"`を合成するため、`includes=["artists"]`では
  レスポンスにこのキーが実質常に欠落する。MusicBrainz公式APIドキュメントもrecording
  lookupではartist-creditはデフォルトで含まれず`inc=artist-credits`の明示指定が
  必要であることを明記 (WebFetchで確認)。lbmbidguard-patch.pyが`get_recording_by_id()`
  自体をtry/except `musicbrainzngs.WebServiceError`でガード済みで200応答が返る
  正常系では、直後の`mb_recording["recording"]`/`mb_recording["artist-credit-phrase"]`/
  `mb_recording["title"]`という素インデックスアクセス3箇所のうち
  `artist-credit-phrase`が無条件でKeyErrorを送出する。この例外は`import_playlists()`
  まで未捕捉のまま伝播し、lbmbidguard-patch.py/lbplaylistguard-patch.py等が既に
  修正した他の欠陥と全く同じ実害 (`on_start()`経由ならactorが起動直後にクラッシュし
  ListenBrainz連携全体がプロセス生涯にわたり無効化、週次再インポートのTimer経由なら
  `import_playlists()`が中断し末尾の`self._schedule_playlists_import()`に到達せず
  次回の再インポートが二度とスケジュールされなくなる) を招く。ローカルライブラリ検索で
  見つからない曲を1件でもMusicBrainz補完しようとするたび (found_tracksが空の
  track_mbidごと) に必ず踏む経路のため、lbmbidguard-patch.pyが守ったネットワーク層
  エラーより高頻度 (実質確実) に発生する。
  verified: lbmbidartistcredit-patch.py。`includes`を正しい`"artist-credits"`へ修正し、
  加えて`mb_recording_query["recording"]`/`mb_recording["artist-credit-phrase"]`/
  `mb_recording["title"]`の素インデックスアクセスを`.get()`ベースへ変更、
  artist_name/track_nameのいずれかが得られない場合はフォールバック検索自体を
  スキップするよう防御 (万一MusicBrainz側のレスポンス形状が想定と異なってもKeyErrorで
  再度クラッシュしないようlbjsonguard-patch.py等と同じ思想で防御的に実装)。
  パッチ適用後の生成ソースは一時コピーに`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。**修正前後のオフライン単体テスト**でバグの再現と
  その解消の両方、および回帰なしを実証: `mopidy_listenbrainz`パッケージをパッチ前後
  それぞれフォルダごとコピーし、別プロセスのEnvのpython3.13で`mopidy.core`だけを
  軽量スタブに差し替え(`musicbrainzngs`/`mopidy.models`/`mopidy.config`/`mopidy.ext`/
  `pykka`は実物のまま使用してGStreamer実バインディング読み込みのみ回避)、
  `object.__new__`で`__init__`をバイパスした`ListenbrainzFrontend`インスタンスに
  対し、`musicbrainzngs.get_recording_by_id`を実際のMusicBrainz応答形状
  (includes=["artists"]相当ではartist-credit-phrase欠落、includes=["artist-credits"]
  相当では付与)を模したスタブに差し替えて`_collect_playlist_tracks()`を直接呼び出した
  ところ、**パッチ前**の生成ソースでは`get_recording_by_id(includes=['artists'])`が
  呼ばれた上で`KeyError: 'artist-credit-phrase'`が未捕捉のまま伝播することを確認
  (バグ再現)、**パッチ後**は`get_recording_by_id(includes=['artist-credits'])`が
  呼ばれ例外を送出せず、`library.search()`が正しい`artist_name`/`track_name`
  (`"Some Artist"`/`"Some Title"`)で呼ばれた上でtracks=[]へ正常に帰結することを確認
  (修正確認)。`nix/lib/mopidy-env.nix`の`listenbrainzPatched`にlbmbidguard-patch.pyの
  直後として登録しビルド成功、生成ソースの`frontend.py`に
  `includes=["artist-credits"]`が反映されていることを確認した上でdev mopidy(6601)を
  実際に起動しMPDで`status`/`tagtypes`/`ping`/`close`が正常応答し回帰なし
  (`listenbrainz`は設定通り`Disabled extensions`に含まれるのみのため本パッチ自体の
  実挙動はオフライン単体テストで検証、dev mopidy起動では全体のビルド・起動無回帰のみ
  確認)、mopidy.logにTraceback/ERROR 0件を確認した。
- [x] `mopidy_ytmusic/library.py`の`albumToTracks()`(アルバムをbrowse/lookup経由で
  展開する主経路。ytalbumfix-patch.pyが既にクラッシュ系の不具合を修正済みだが、別の
  「静かなデータ破損」不具合が残っていた)。TODO/既知の残課題を全項目消化済みのため
  自走エージェントが横断調査(同ファイルの`playlistToTracks()`のper-track artist組み立て
  ロジックと比較)して新規発見・着手。
  実害: 旧実装は各曲のアーティストを以下の分岐で決めていた:
  ```
  if ("artists" not in song or song["artists"] == artistname
      or song["artists"] is None):
      songartists = artists
  else:
      songartists = [Artist(name=artistname)]
  ```
  ytmusicapi 1.12.1 (mixins/browsing.py `get_album()`、実ソース確認済み) は
  `album["tracks"][i]["artists"] = album["tracks"][i]["artists"] or album["artists"]`
  により各トラックの`"artists"`キーを常にdictのlistとして設定するため、
  `"artists" not in song`は常にFalse、`song["artists"] is None`も常にFalse、
  `song["artists"] == artistname`はlistとstrの型不一致で恒常的にFalseとなり、
  3条件は事実上全て成立せず**必ずelse分岐に落ちる**。結果として:
  (1) 曲固有の実アーティスト情報(feat.曲の追加アーティストや、オムニバス盤で
  曲ごとに演奏者が異なるケース)が握り潰され、常にアルバムの代表アーティスト名
  (`artistname`)に一律で誤表示される。(2) `Artist(name=artistname)`はuri無しで
  毎回新規生成されるため、本来`self.ARTISTS[artist['id']]`経由でuri付き
  (`ytmusic:artist:<id>`)アーティストが得られるはずが、常にuri無しに化ける
  (アーティストページへのブラウズ導線喪失)。クラッシュではなく毎回発火する
  静的なメタデータ破損で、同ファイルの`playlistToTracks()`(正しく
  `song["artists"]`を`self.ARTISTS`キャッシュ付きで組み立てている)との
  非対称性からも実装漏れと判断できる。
  verified: ytalbumtrackartist-patch.py。`playlistToTracks()`と同じ流儀
  (`a["id"]`があれば`self.ARTISTS`へuri付きでキャッシュ、無ければ
  `Artist(name=a["name"])`を都度生成)で`song["artists"]`から`songartists`を
  正しく組み立て、曲側にアーティスト情報が無い場合のみアルバムの`artists`へ
  フォールバックするよう修正。パッチ適用後の生成ソースは一時コピーに当てて
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`の`ytmusicPatched`にytalbumidcache-patch.pyの直後として
  登録しビルド成功、生成ソースの`albumToTracks()`に新実装が反映されていることを
  確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に起動し実データで
  再現・修正の両方を確認 —
  修正前に相当する挙動の確認として、まず通常の単一アーティストアルバム
  (Akon「Konvicted」、feat.曲「Smack That (feat. Eminem)」「I Wanna Love You
  (feat. Snoop Dogg)」等を含む)を`add`し`playlistinfo`で全12曲の`Artist`タグが
  一貫して`Akon`(アルバムの代表アーティスト名と一致、feat.曲でも同じ)である
  ことを確認(この場合は旧実装のバグでも表示上は同じ名前になるため区別不可)。
  次に本バグが可視化されるコンピレーション盤
  (`ytmusic:album:MPREb_0y7rgjfqP5X`「Various Artists - Awesome Mix Vol. 1 &
  Vol. 2」、Guardians of the Galaxyのサントラで曲ごとに演奏者が異なる)を`add`し
  `playlistinfo`を確認したところ、修正後は16曲それぞれ実際の演奏者名
  (`Crazee Noize`/`Graham Blvd`/`The New Merseysiders`/`R.D. Shannon`/
  `Detroit Soul Sensation`/`The Magic Time Travelers`等)が曲ごとに正しく
  出力されることを確認(旧実装であれば`song["artists"]`が常にelse分岐に落ちる
  ため全16曲が一律`Various Artists`になっていたはずの箇所)。回帰確認:
  `status`/`tagtypes`/`ping`が正常応答、mopidy.log起動時の既存の自動プレイリスト
  更新エラー(本パッチと無関係、既知のセクション欠落起因)以外にTraceback/ERROR
  無し。
- [x] `mopidy_mpd/protocol/music_db.py`の`_query_from_mpd_filter_expression()`
  (フィルタ式パーサ、`find`/`findadd`/`search`/`searchadd`/`searchaddpl`/
  `count`/`searchcount`、および`current_playlist.py`の`_pf_search()`経由で
  `playlistfind`/`playlistsearch`/`searchplaylist`も共有する唯一の実装箇所)。
  TODO全項目消化済みのため自走エージェントが横断調査(mpdfilterkind-patch.py/
  mpdnegfilter-patch.pyが追加した正規表現演算子`=~`/`!~`を実データで実際に
  叩いて検証)して新規発見・追加した項目。
  実害: 実MPD仕様(MusicPlayerDaemon/MPDを実際にclone してソース確認)は
  `src/song/Filter.cxx`のフィルタ式パーサが`(TAG =~ "VALUE")`を読んだ時点で
  `UniqueRegex::Compile()`(「Throws Pcre::Error on error.」と明記)を即座に
  呼び出しており、コンパイル失敗は例外としてコマンド全体を中断させ`ACK`を
  返す(データベース照会は一切行わない)。対して現状のmopidy_mpd
  (mpdnegfilter-patch.py/mpdfilterkind-patch.py適用後)は、パース時点では
  演算子とタグ名だけを見て`(field, "regex", value)`をpositives/negativesへ
  積むのみで、実際に`re.compile(value)`を試すのはずっと後段の取得済み
  Trackに対するローカルフィルタ(`_mpd_track_matches_positives()`/
  `_mpd_track_excluded()`/`_pf_matches()`)であり、しかもそこでは
  `except re.error: continue`で静かに握り潰し、そのフィルタ条件自体が
  「常に真」であるかのように扱われる。さらに`query.setdefault(field,
  []).append(value)`により生の不正な正規表現文字列がそのまま後段フィルタとは
  無関係にbackendのlibrary.search()(ytmusicなら実際のYouTube Music検索API)
  へ渡ってしまう。rmpc本体(mierak/rmpc, rmpc-mpd/src/filter.rs
  `FilterKind::Regex`/`NotRegex`)は検索ペインでユーザが明示的にRegex/
  NotRegexモードへ切り替え生の正規表現文字列を送信できる実在の機能のため、
  typo等で不正な正規表現を入力したユーザに実際に到達しうる。
  verified: mpdregexvalidate-patch.py。`_query_from_mpd_filter_expression()`が
  演算子種別`_kind`を`"regex"`と判定した直後(positives/negatives および
  backend用query dictへ積む前)に`re.compile(value)`を試し、`re.error`なら
  実MPDと同じくコマンド全体を即座に`exceptions.MpdArgError`で中断するよう
  修正。パッチ適用後の生成ソースは一時コピーに`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  `mpdPatched`にmpdprioboundary-patch.pyの直後として登録しビルド成功、
  dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  (1)修正前に相当する挙動の再現確認: パッチ適用前の生成ソースへ実際に
  `find "(Artist =~ '(')"`(閉じ括弧の無い不正な正規表現)を送ったところ、
  実MPDなら即座にACKになるはずがOKで応答し、"(" というキーワードでの実検索が
  ネットワーク越しに実行され`Bracket`/`P-Square`等 "(" と何ら関係の無い
  アーティストの楽曲・アルバムが多数(15984バイト超)ヒットして返ってしまう
  ことを確認(バグ再現)。(2)修正後は同じコマンドが
  `ACK [2@0] {find} Could not compile regular expression: missing ),
  unterminated subpattern at position 0`に変化し、backendへの検索が実行され
  なくなったことを確認。同様に`search`/`count`/`findadd`/`searchadd`/
  `searchaddpl`/`playlistfind`/`playlistsearch`/`searchplaylist`の全てで
  同じACKになること、`!~`(否定側)の不正な正規表現、`AND`で連結した複合式の
  一部だけが不正な場合、`command_list`内(`status`→不正`find`→`ping`の順)で
  該当コマンドの位置番号`[2@1]`で正しく中断し後続`ping`が実行されないことを
  確認(実MPDのcommand_list仕様通り)。(3)有効な正規表現
  (`find "(Artist =~ 'Bracket')"`)は引き続き正常にOK+実データ
  (`ytmusic:album:...`等15984バイト相当)を返すことを確認、回帰なし。
  (4)既存の`!=`/`==`/`group`等の回帰確認: `find "(Artist != 'Bracket')"`は
  従来通り(本パッチ無関係の既存挙動)`ACK incorrect arguments`、
  `list album group AlbumArtist`/`sticker find song "" x`/`status`/
  `tagtypes`/`ping`/`search any "yoasobi"`が正常応答、mopidy.logに
  Traceback/ERROR新規発生なしを確認した。

- [x] `binarylimit {SIZE}` (mpd-patch.py が rmpc の albumart/readpicture 対応のため
  追加したコネクション設定コマンド) に非数値・空文字・負数の SIZE
  (`binarylimit "abc"`/`binarylimit ""`/`binarylimit -5` 等) を渡すと、
  `int(limit)` が送出する素の `ValueError` を直後の
  `except (TypeError, ValueError): pass` が無条件に握り潰してしまい、
  `context.session.binary_limit` を更新しないまま関数が正常終了する不具合。
  dispatcher の `_add_ok_filter` は例外(ACK)が飛ばなければ無条件に "OK" を
  付加するため、不正な引数を渡したのにクライアントには `ACK` ではなく `OK`
  が返っていた(実MPD仕様からの逸脱、他コマンドを切断させる系統とは逆に
  「本来ACKにすべきものを黙って正常応答してしまう」派生パターン)。
  さらに `64` 未満の有効な正の数値 (`binarylimit 10` 等) も、実MPD
  (MusicPlayerDaemon/MPD `src/command/ClientCommands.cxx` の
  `handle_binary_limit()`、実際にソース確認: `args.ParseUnsigned()` でパース後
  `if (value < 64) { r.Error(ACK_ERROR_ARG, "Value too small"); ... }`) と
  異なり、`max(64, int(limit))` でエラーにせず黙って64へクランプしOKを
  返してしまっていた。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  横断調査 (mpd-patch.py が実装した connection.py の全コマンドの引数
  バリデーションを実MPDソースと突き合わせて再監査) して新規発見・追加した項目。
  verified: mpdbinarylimitargerr-patch.py。`seekcur`/`playlistinfo` 等と同じ
  流儀 (mpdseekcurargerr-patch.py/mpdplaylistinfoargerr-patch.py) で、
  `@protocol.commands.add("binarylimit", limit=protocol.UINT)` へデコレータの
  型バリデータとして宣言し直し (フレームワーク側 `validate()` が `ValueError`
  を自動的に `exceptions.MpdArgError("incorrect arguments")` へ変換)、
  `limit < 64` は実MPDと同じ文言で `exceptions.MpdArgError("Value too
  small")` を明示的に送出するよう修正 (クランプではなくACK拒否)。パッチ適用後の
  生成ソースは一時コピーに `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。`nix/lib/mopidy-env.nix` の `mpdPatched` に
  `mpdregexvalidate-patch.py` の直後として登録しビルド成功、生成ソースに
  新実装が反映されていることを確認した上で dev mopidy(6601, ytmusic実
  アカウント)を実際に起動し同一コネクションでMPDプロトコルを実機確認 —
  (1)`binarylimit abc`/`binarylimit ""`/`binarylimit -5` の全てが
  `ACK [2@0] {binarylimit} incorrect arguments` に変化し(修正前ならここで
  `OK` が返っていた)、かつ同一ソケットのまま後続コマンドを送れる=セッションが
  切断されていないことを確認。(2)`binarylimit 10`(64未満の有効な数値)は
  `ACK [2@0] {binarylimit} Value too small` となり(修正前は黙って64へ
  クランプしOK)、クランプでなく明示的な拒否に変わったことを確認。
  (3)`binarylimit 8192`(有効な数値)は引き続き `OK` を返し、直後の `status`
  (partition/volume/state等正常表示)/`ping`/`lsinfo "/"`(YouTube Musicの
  ディレクトリ一覧)が正常応答する回帰なしを確認。mopidy.logにTraceback/ERROR
  新規発生なしを確認した。
- [x] `seek {SONGPOS} {TIME}`/`seekid {SONGID} {TIME}`/`seekcur {TIME}` に非有限値
  (`"nan"`/`"inf"`/`"-inf"`。Pythonの`float()`はこれらの文字列を有効な浮動小数点数
  として受理してしまう) を再生中に渡すと、MPDセッションが問答無用で切断されて
  しまう不具合。TODO全項目消化済みのため自走エージェントが、
  mpdseekcurargerr-patch.py(非数値TIMEの素のValueError切断を修正済み)の実機再検証
  中に「では有限だが特殊な浮動小数点値(nan/inf)はどうなるか」を追加で試す過程で
  新規発見。
  根本原因: `mopidy_mpd/protocol/__init__.py`の`protocol.FLOAT`/`protocol.UFLOAT`
  (`seek`/`seekid`はデコレータの引数バリデータとして、`seekcur`は
  mpdseekcurargerr-patch.py適用後に関数冒頭のtry/exceptで手動呼び出し)が
  `float(value)`をそのまま返すだけでnan/infを弾かず(UFLOATの`if value < 0`も
  nan/infはPython比較規則上Falseになるため素通り)、パース成功後にハンドラ本体が
  行う`int(seconds * 1000)`/`int(value * 1000)`が無防備で、nanは素の`ValueError`、
  inf/-infは素の`OverflowError`を送出する。`seek`/`seekid`のデコレータバリデータ
  (`Commands.add.<locals>.validate()`)は引数変換フェーズの`ValueError`しか捕捉せず
  この`int()`はハンドラ本体実行時(検証フェーズの外)のため無防備、`seekcur`の
  mpdseekcurargerr-patch.py由来のtry/exceptも`protocol.FLOAT`/`UFLOAT`呼び出し自体
  しか囲っておらずその戻り値を使う後段の`int()`は対象外だった。dev mopidy(6601、
  ytmusic実アカウント)でYOASOBI2曲をfindadd+play後、再生中に`seekcur "inf"`を
  送信したところ応答無しのままソケットがリセットされ切断、mopidy.logに
  `OverflowError: cannot convert float infinity to integer`
  (`playback.py`, line 426, `position = int(value * 1000)`)のTracebackを実機で
  確認。新規接続で`seekcur "nan"`も同様に切断(`ValueError: cannot convert float
  NaN to integer`)、別の新規接続で`seek "0" "nan"`(既存のデコレータバリデータ
  経由の経路)も同様に切断することを確認し、根本原因が`protocol.UFLOAT`自体の
  不足でありseekcur固有の問題ではないことを実機で裏付けた。
  verified: mpdfloatnonfinite-patch.py。3コマンドを個別に直すのではなく共有元の
  `protocol.FLOAT`/`protocol.UFLOAT`自体に`math.isfinite()`チェックを追加し
  非有限値を`ValueError`として弾くよう修正 (これにより`seek`/`seekid`は既存の
  デコレータバリデータの`except ValueError`が、`seekcur`は既存の
  mpdseekcurargerr-patch.pyのtry/exceptが、いずれも変更無しでそのまま`ACK
  incorrect arguments`に変換してくれる)。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w`して`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix`のmpdPatchedにmpdbinarylimitargerr-patch.pyの
  直後として登録しビルド成功、生成ソースに新実装が反映されていることを確認した
  上でdev mopidy(6601、ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  YOASOBI2曲をfindadd+play後の再生中に`seekcur "nan"`/`seekcur "inf"`/
  `seekcur "-inf"`/`seekcur "+nan"`/`seek "0" "nan"`/`seek "0" "inf"`/
  `seekid "1" "inf"`の全てが`ACK [2@0] {コマンド名} incorrect arguments`に変わり
  (修正前ならここでソケットが切断されていた)、直後の同一接続での`ping`が`OK`を
  返しセッションが生存していることを確認。回帰確認: 修正後も`seekcur "5"`
  (絶対)/`seekcur "+2"`(相対)/`seek "0" "3"`が引き続き`OK`を返し`status`の
  `elapsed`に正しく反映、`seekcur "abc"`(既存の非数値ガード、mpdseekcurargerr
  由来)も引き続き`ACK incorrect arguments`のまま無変更。副次的に
  `mixrampdelay "nan"`/`mixrampdb "inf"`(同じprotocol.FLOATを使うが元々int()
  変換が無くクラッシュはしなかった経路)も`ACK incorrect arguments`に変わり
  (修正前は黙って受理しstatusにnan/inf文字列を出力しうる状態だった)、実MPD準拠の
  拒否になったことを確認。旧来の`crossfade "5"`/`status`/`tagtypes`/
  `list Album group AlbumArtist`/`search any sort+window`/`sticker get`の回帰
  なし・mopidy.logにTraceback/ERROR新規発生なしを確認した。
- [x] `mopidy_ytmusic.library.py`の`browse()`の`ytmusic:artist:<id>:upload`
  (アップロード済みアーティスト)分岐が、`uploadArtistToTracks(res)`で曲一覧を
  正しく変換し終えた直後のデバッグログで`res[0]["artist"][0]["name"]`という
  存在しないキー("artist"、単数)にアクセスしKeyErrorを送出する不具合。
  ytmusicapi(`ytmusicapi/mixins/uploads.py`の`get_library_upload_artist()`
  docstring記載の実例そのまま)が返す生トラック辞書のアーティストフィールドは
  `"artists"`(複数・list)であり`"artist"`ではない。これは同じ関数内の
  `uploadArtistToTracks()`自身の実装(`for a in track.get("artists") or []:`)
  からも明らか。`tracks = self.uploadArtistToTracks(res)`の時点で変換は
  既に成功しているにも関わらず、その直後のログ出力行のタイポでKeyErrorが起き、
  直後の`except Exception: logger.exception(...)`に握り潰されてreturn文まで
  到達できない。結果としてbrowse()はこの分岐の末尾(returnなし→browse()全体が
  最終的に空リストへフォールスルー)になり、アップロード曲を持つアカウントで
  rmpcの「YouTube Music」→Uploadsのアーティスト別ブラウズが常に空フォルダに
  見える(曲は一歩手前まで正しく変換されていたのに無関係なログ出力のタイポで
  握り潰される「静かな」不具合)。TODO全項目消化済みのため自走エージェントが
  Explore サブエージェントに他の未対応箇所の調査を委任し新規発見・追加した
  項目 (`ytuploadartistlookup-patch.py`が同じアップロードアーティストの
  `lookup()`分岐の別バグ(誤った変換関数呼び出し)を既に修正済みだが、
  `browse()`側のこのデバッグログのタイポは未修正のまま残っていたことを
  既存パッチ全件とのgrep突き合わせで確認)。
  verified: ytuploadartistbrowselog-patch.py。キー名を`"artists"`(複数)に
  修正し、`res`が空/`res[0]`に`"artists"`が無い/artistsが空リストの場合にも
  IndexError/KeyErrorを起こさないよう`bId`へのフォールバックを追加。パッチ
  適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`に
  ytuploadartistlookup-patch.pyの直後に登録しビルド成功、生成ソースに新実装が
  反映されていることを確認した上で dev mopidy(6601, ytmusic実アカウント)を
  実際に起動しMPDで実機確認。ただし当該実アカウントはアップロード済み楽曲
  ライブラリを持たない(`lsinfo "YouTube Music/Artists"`が空)ため、この分岐を
  実データで直接MPD経由に叩くことはできなかった。そこで、ビルド済み
  env(`$ENV/bin/python3`)で実際にインストールされている
  `mopidy_ytmusic.library.YTMusicLibraryProvider.browse()`
  (dev mopidyが実行しているのと同一の生成ソース)を直接importし、
  `self.backend.api.get_library_upload_artist`を
  ytmusicapi公式docstringのExample Listそのまま(フィールド名を一切改変せず)
  返すスタブに差し替えて`browse("ytmusic:artist:<id>:upload")`を実行する
  検証を実施: (1)パッチ前(pristine env)では実際に
  `KeyError: 'artist'`のTracebackがログされた上で`browse()`が`[]`を返す
  (バグの再現を確認)。(2)パッチ後(ビルド済みenv)では例外なく
  `[Ref(name='Hold Me (Original Mix)', type='track',
  uri='ytmusic:track:Dtffhy8WJgw')]`を正しく返すことを確認。加えて、
  この変更が影響しない既存機能の回帰なしをdev mopidyへの実MPD接続で確認 —
  `tagtypes`/`status`/`search any "yoasobi"`(2曲+アルバム1件正常応答)/
  `lsinfo "YouTube Music"`(9セクション正常表示)/
  `lsinfo "YouTube Music/Artists"`(空だが正常応答、ACK無し)。mopidy.logに
  今回変更した`browse()`アップロードアーティスト分岐由来のTraceback/ERRORが
  無いことを確認(ログ中に別の既存事象("YTMusic failed to get track "None""、
  本パッチのbrowse()アップロードアーティスト分岐とは無関係な既存の
  `getTrack(None)`呼び出し由来)が1件あったが、今回のパッチ適用前後で
  変化なく本パッチの回帰ではないことをコード上確認(該当箇所は
  `library.py`の`lookup()`内`getTrack()`呼び出しで、`browse()`の
  アップロードアーティスト分岐とは無関係)。
- [x] `mopidy_ytmusic.backend.py`の`YTMusicBackend.__init__()`で、`self.api`(ytmusicapi
  クライアント)の初期化は`if self.auth and not self.oauth: ... elif self.oauth: ...`と
  `self.oauth`を正しく分岐条件に含めているのに対し、直後の`self.playlists`代入
  `if self.auth: self.playlists = YTMusicPlaylistsProvider(backend=self)`は
  `self.auth`のみで判定し`self.oauth`を見ていない不具合。`self.auth`/`self.oauth`は
  `config["ytmusic"]["auth_json"]`/`["oauth_json"]`(`__init__.py`の
  `get_config_schema()`で両方とも対等なoptional Path)がそれぞれ設定されているかで
  独立に立つフラグのため、`oauth_json`のみを設定し`auth_json`を空にする構成
  (`self.auth=False, self.oauth=True`)では`self.api`はOAuth認証で正しく生成される
  にもかかわらず`self.playlists`は一度も代入されず、`mopidy.backend.Backend`の
  クラス属性デフォルト`playlists: Optional[PlaylistsProvider] = None`のままになる。
  結果`has_playlists()`(`self.playlists is not None`)が`False`を返しmopidy coreが
  このバックエンドをplaylistsプロバイダ集合から除外するため、MPDの
  `listplaylists`/`load`/`playlistadd`/`rm`/`rename`
  (`mopidy_mpd/protocol/stored_playlists.py`)がYouTube Musicのプレイリストを
  完全に無視する「静かな」機能欠落になる(エラーは出ない、ログもクリーン)。
  ログインCookie(`auth_json`)は期限切れ運用が必要なため、より安定した
  `oauth_json`のみへ運用を切り替えた瞬間にプレイリスト機能一式が理由不明のまま
  消える。TODO全項目消化済みのため自走エージェントがExploreサブエージェントに
  未対応箇所の調査を委任し新規発見・追加した項目(全157個の既存パッチを
  `self.playlists`/`self.oauth`/`self.auth`でgrepし、`backend.py`を対象とする
  既存パッチ(ytapiactorrace/ytautoplaylistfix/ytautoemptysection/ytcipherfail/
  ytscrobble/ytverifytrackurl)のいずれもこの箇所へ触れていないことを確認)。
  verified: ytoauthplaylistguard-patch.py。`self.api`初期化と同じ条件
  `self.auth or self.oauth`へ統一する1行修正。パッチ適用後の生成ソースは一時
  コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix`のytmusicPatchedにytalbumtrackartist-patch.pyの
  直後として登録しビルド成功。実機検証: (1) dev mopidy(6601、ytmusic実アカウント、
  `auth_json`のみ設定・`oauth_json`は空という実際のdev構成)を実際に起動し
  MPDで確認 — クリーン起動(mopidy.logにTraceback/ERROR 0件)、`tagtypes`/
  `status`/`search any "YOASOBI"`(album 1件正常応答)/`listplaylists`(ACK無し
  でOK応答)の回帰なしを確認(このdev構成は元々`self.auth=True`のため本バグの
  影響を受けない経路であることも合わせて確認)。(2)
  本バグは`auth_json`を空にし`oauth_json`のみを設定した構成でのみ顕在化するが、
  実際にそのような有効なOAuth資格情報を用意する(Google側の認可が必要)ことは
  secrets/sopsに触れない制約上できないため、ビルド済みenv自身の
  `mopidy_ytmusic.backend`モジュール(dev mopidyが実行しているのと同一の生成
  ソース)を実際にimportし、`YTMusic`/`YTMusicPlaybackProvider`/
  `YTMusicLibraryProvider`/`YTMusicPlaylistsProvider`をダミーに差し替えた上で
  `config={"auth_json": None, "oauth_json": "/tmp/fake-oauth.json", ...}`
  (auth_jsonが空・oauth_jsonのみ設定という実際のバグ条件そのもの)を渡し
  `YTMusicBackend.__init__()`を直接実行する検証を実施(pykka.ThreadingActor.__init__
  はactor基盤セットアップ(スレッド起動等、このテストの対象外)のみをスキップし、
  `__init__()`本体のロジックはmodifyなしで実行)。GI_TYPELIB_PATH等の必要な
  環境変数は実際に起動中のdev mopidyプロセスの環境から`ps -E`で取得し同一の値を
  使用。(a) パッチ前(pristine env)では`self.auth=False, self.oauth=True`にも
  かかわらず`hasattr(self, "playlists")`が`False`のままとなり(バグを実機で再現)、
  (b) パッチ後(ビルド済みenv)では同じ条件で`self.playlists`が正しく
  `YTMusicPlaylistsProvider`インスタンスとなり`has_playlists()`相当が`True`に
  なることを確認した。
- [x] `mopidy_ytmusic.library.py`の`YTMusicLibraryProvider.search()`が`query["genre"]`
  (MPDの`find`/`search`/`count`タグ、`mopidy_mpd/protocol/music_db.py`の
  `_LIST_MAPPING`/`_SEARCH_MAPPING`で`"genre"`->`"genre"`と正式にマップされ、
  `find genre "X"`/`search genre "X"`/`count genre "X"`が素通りでこのフィールド名
  のままバックエンドの`library.search()`へ渡る)を扱う`if`/`elif`分岐を一切持たず、
  `"any"`/`"track_name"`/`"albumartist"or"artist"`/`"album"`/`"uri"`のどれにも
  一致しないため常に最終`else`(デバッグログ出力のみ)へ落ち、エラーにも一切ならない
  まま`return None`(0件)を返してしまう不具合。TODO全項目消化済みのため自走エージェント
  がExploreサブエージェントに未対応箇所の調査を委任し新規発見・追加した項目
  (`ytsearchuri-patch.py`と同じ`search()`分岐欠落パターンの横展開)。rmpc本体
  (mierak/rmpc)を実際にcloneしてソース確認したところ、`rmpc-mpd/src/filter.rs`の
  `Tag` enumに`Genre`がAny/Artist/AlbumArtist/Album/Title/Fileと並ぶ組み込み
  バリアントとして定義されており、検索ペインのタグ選択でGenreを選んでクエリを打つと
  実際に`find genre "..."`相当のMPDコマンドが送信されることを確認した。YouTube Music
  に真のジャンル絞り込み検索APIは無いため実MPD相当の厳密フィルタは実装不能だが、
  常に無条件で0件を返す現状より、`"any"`分岐と同じベストエフォートのテキスト検索
  (`filter=None`)にフォールバックする方が明らかに有用と判断し着手。
  verified: ytsearchgenre-patch.py。`"any"`分岐と同じ実装
  (`self.backend.api.search(" ".join(query["genre"]), filter=None)` ->
  `self.parseSearch(res)`、例外はtry/exceptでログのみに変換し従来同様0件フォール
  バック)を最終`else`の手前(`"uri"`分岐の直前)に追加。パッチ適用後の生成ソースは
  一時コピー(`mopidy_ytmusic/library.py`という相対パスを再現)に当てて`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  ytmusicPatchedに`ytsearchuri-patch.py`の直後として登録しビルド成功、生成ソースに
  新実装が反映されていることを確認した上でdev mopidy(6601、ytmusic実アカウント)を
  実際に起動しMPDで実機確認 — 修正前は`find genre "X"`/`search genre "X"`が常に
  `OK`(0件)、`count genre "X"`が`songs: 0`固定だったのに対し、修正後は
  `search genre "J-Pop"`→実際のアルバム1件(`ytmusic:album:VLRDATgx`「J-Pop Radio」)、
  `find genre "YOASOBI"`→アルバム1件+トラック2件(「夜に駆ける」「オリオン - Orion」)
  と実データがヒットするようになったことを確認 (`search any "Rock"`が0件なのは
  ytmusicapiの検索結果自体がこの語で空を返す既存の別事象であり、本パッチによる
  新規リグレッションではないことをコード上確認済み)。旧来の`tagtypes`(Genre含む
  既存タグ一覧に変化なし)/`status`/`search any "YOASOBI"`(アルバム1件+トラック2件、
  従来通り)/`count any "YOASOBI"`(songs: 2)/`list album`の回帰なし・mopidy.logに
  Traceback/ERROR 0件を確認。
- [x] `mopidy_mpd/protocol/audio_output.py`の`toggleoutput()`が、
  `context.core.mixer.get_mute()`(読み取り)と`context.core.mixer.set_mute(not
  mute_status)`(書き込み)という2回の**別々の** pykka actor呼び出しを、その間を
  保護する仕組み無しに実行しているTOCTOUレース(lost update)。TODO全項目消化済み
  のため自走エージェントがrmpc本体(mierak/rmpc)とmopidy_mpdのソースを実際に
  読んで新規発見・追加した項目 (mpdtogglemuterace-patch.pyが同じ関数の
  「set_mute()の.get()未呼び出し」という別種の不具合を既に修正済みだが、この
  read-modify-write自体の非原子性には手を入れていなかった)。rmpcの Outputs
  モーダル (`rmpc/src/ui/modals/outputs.rs::toggle_selected_output()` →
  `rmpc-mpd/src/mpd_client.rs`の`send_toggle_output`経由で`toggleoutput {ID}`を
  送信)からのtoggle操作はごくありふれた単純操作で、同一mopidyサーバへ複数
  クライアント接続(2台目のrmpc、他のMPDクライアント等)が張られるのも通常運用の
  範囲内。2本の接続がほぼ同時に`toggleoutput 0`を送ると、両方が同じ古い
  `mute_status`を読んだ後に両方が同じ`not mute_status`を書き込んでしまい、
  本来2回のトグルは元の状態に戻るはずが1回分の変化しか反映されない。
  verified: mpdoutputtogglerace-patch.py。mpdurimaprace-patch.py/
  mpdchannelrace-patch.py等と同じ流儀で、audio_output.pyにモジュールレベルの
  `threading.Lock()`を追加し、disableoutput/enableoutputの`set_mute()`呼び出しと
  toggleoutputの`get_mute()`→`set_mute()`複合操作を`with`ブロックで直列化(いずれも
  SoftwareMixerへの軽量なin-process actor呼び出しのみでバックエンドへの長時間
  ネットワーク呼び出しを含まないため、mpdurimaprace-patch.pyが警戒した
  「listall事案のような長時間ブロック」の懸念は無い)。パッチ適用後の生成ソースは
  一時コピーに当ててast.parseで構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix`にmpdtogglemuterace-patch.pyの直後として登録し
  ビルド成功、生成ソースに新実装(`_output_mixer_lock`)が反映されていることを
  確認した上でdev mopidy(6601、ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  (1)単一接続での`disableoutput 0`/`enableoutput 0`/`toggleoutput 0`
  (往復)/`outputs`の応答が従来通り(回帰なし)、存在しないID`toggleoutput 1`は
  引き続き`ACK [50@0] {toggleoutput} No such audio output`。(2)並行性ストレス試験:
  10本の別々のTCP接続から各25回、計250回の`toggleoutput 0`を20本×5ラウンド
  同時実行するPythonスクリプトを実際に走らせ、各ラウンド後の`outputenabled`が
  トグル回数の偶奇から数学的に期待される値と5/5ラウンドとも完全一致し
  (ACKエラーも0件)、mute状態がサイレントに食い違う事象が発生しないことを確認
  (max_connections=20の既定値内に収まるよう接続を使い回す構成に調整)。
  `status`/`tagtypes`の回帰なし・mopidy.logにTraceback 0件を確認。
- [x] `mopidy_ytmusic/library.py` の `lookup()` (add/findadd/playlistadd 等、
  `core.library.lookup()` 経由で呼ばれる唯一の変換経路) が、アップロード済みアルバム
  (`ytmusic:album:<id>:upload`) に対してだけ誤った変換関数 `albumToTracks()`
  (非アップロード専用、`get_album()` の戻り値用) を呼ぶ不具合。TODO 全項目消化済みのため
  自走エージェントが `mopidy_ytmusic/library.py` を通読して新規発見・追加した項目
  (`ytuploadartistlookup-patch.py` が全く同じバグクラスをアーティスト分岐について
  既に修正済みだったが、その直前にある album 分岐の同型バグが見落とされたまま
  残っていた)。同じ URI を `browse()` (478-479行目) で辿ると
  `get_library_upload_album(bId)` の戻り値を `uploadAlbumToTracks(res, bId)` に渡して
  正しい `:upload` 付き Album/Artist URI で曲一覧を組み立てるのに、`lookup()` だけ
  `albumToTracks(res, bId)` を呼んでいたため、`self.ALBUMS[bId]` が `:upload` 無しの
  実際には解決不能な URI で上書きされ (browse() が先に正しい値を登録していても
  lookup() 実行後にサイレントに壊れる)、アルバムアートワーク取得等の後続処理が
  静かに失敗する実害があった。
  verified: ytuploadalbumlookup-patch.py。`lookup()` のアップロードアルバム分岐を
  `browse()` と対称に `uploadAlbumToTracks(res, bId)` へ変更。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)で
  あることも確認。`nix/lib/mopidy-env.nix` に `ytoauthplaylistguard-patch.py` の直後として
  登録しビルド成功。パッチ登録前(旧ビルド, nix store保持済み)と登録後の2つの
  `library.py` を用意し、`YTMusicLibraryProvider.lookup()` を `self.backend`/
  `self.ARTISTS`/`self.ALBUMS`/`self.TRACKS`/`self.IMAGES` をダミーにした最小harnessから、
  `get_library_upload_album()` が実際の戻り値形状 (title/trackCount/year/artists/tracks を
  持つ辞書、videoId付きトラック2件) を返すスタブ付きで `ytmusic:album:<id>:upload` を
  lookupする before/after 比較で不具合の実在と修正を確認 — 旧版は
  `album.uri='ytmusic:album:<id>'` (`:upload` 欠落、実際には解決不能な壊れたURI)、
  新版は `album.uri='ytmusic:album:<id>:upload'` / `album.artists[0].uri` も同様に
  `:upload` 付きとなり `browse()` の結果と一致することを確認。実機検証: dev
  mopidy(6601, ytmusic実アカウント。当該アカウントにアップロード済み楽曲が無いため
  実データでの再現はできないが、以下の回帰確認で代替) を実際に起動し MPD で確認 —
  `status`/`tagtypes`/`search any "yoasobi"`(アルバム1件+トラック2件)/`stats`/
  `clear`→`findadd "(any contains \"yoasobi\")"`→`playlistinfo`(2曲とも正常追加、
  Pos/Id/Added含め従来通り)の回帰なしを確認、mopidy.log に本パッチが触れた
  `lookup()`/`albumToTracks()`/`uploadAlbumToTracks()` 関連の新規 Traceback/ERROR
  0件を確認 (検証序盤に自分で送った存在しない `lsinfo "ytmusic:uploads"` という
  誤ったテストクエリが `mpdlsinfouri-patch.py` のフォールバック経由で `lookup()` の
  無関係な最終フォールバック分岐 `getTrack(None)` を踏み `KeyError: 'videoDetails'` を
  1件ログに残したが、本パッチのスコープ外・自分のテスト操作由来であり本パッチの
  変更行とは無関係なことをコード上確認済み)。
- [x] `add`/`addid`/`findadd`/`searchadd`/`load` のPOSITION相対指定 (`+N`/`-N`、
  現在曲基準) を解決する5箇所 (`current_playlist.py`の`_mpd_resolve_add_position`
  =add、addid内インライン処理、`music_db.py`の`_mpd_resolve_addpos_position`
  =findadd/searchadd、`stored_playlists.py`の`_mpd_resolve_load_position`=load) が
  共通して持つTOCTOUレース。いずれも`context.core.tracklist.get_length().get()`
  (キュー長) と(相対指定時)`context.core.tracklist.index().get()`(現在曲位置)を
  **別々の**core呼び出しで読み取ってから、さらに別のcore呼び出しである
  `context.core.tracklist.add(uris=..., at_position=解決済み位置).get()`で実際に
  挿入する。`mopidy/core/tracklist.py`のadd()は`self._tl_tracks.insert(at_position,
  tl_track)`という素のlist.insert()で範囲外indexを例外無く黙ってクランプするため、
  「位置を読む」→「挿入する」の間に他クライアントのdelete/move/next(自動進行含む)
  等が割り込んでも一切エラーが出ず、OK応答のまま無関係な位置へサイレントに
  挿入されてしまう(mpdmovetorace-patch.pyがmove/moveidのTO解決について確認済みの
  性質と同型)。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが
  mopidy_mpdのコード品質を再調査して発見した項目。
  rmpc本体(mierak/rmpc)は既存パッチ(mpdaddpos-patch.py/mpdfindaddpos-patch.py/
  mpdloadpos-patch.py)がrmpc-mpd/src/mpd_client.rsのsend_add/send_find_add/
  send_load_playlistを実際にソース確認済みの通り、「現在の曲の次/前に追加」
  キーバインド(rmpc/src/config/keys/actions.rs Position::AfterCurrentSong/
  BeforeCurrentSong)で日常的にPOSITION付きコマンドを送信するため、2台目のrmpc
  接続や自動再生の曲送りが同時に走ると「次に追加」したはずの曲が無関係な位置に
  挿入されキュー順序がサイレントに破損する実害がある。findadd/searchaddは
  POSITION解決の手前に`context.core.library.search()`というネットワーク呼び出し
  (mopidy_ytmusicなら実際のYouTube Music検索API、数百ms〜数秒)を挟むため
  レース窓が他コマンドより広い。mpdaddloadrace-patch.pyは「末尾追加+moveの2段階」
  というTOCTOUをat_position直接指定へ変更し解消したが「addidは1回のcore呼び出しで
  完結するのでレース無し」と結論しており、位置解決自体と最終add()実行の間に
  残るこの窓には触れていなかった。BACKLOG.md全文検索でも
  `_mpd_resolve_add_position`/`_mpd_resolve_addpos_position`/
  `_mpd_resolve_load_position`は各初出の1箇所にしか登場せず、後続のどの是正項目にも
  再訪されていないことを確認した。
  verified: mpdaddposrace-patch.py。mpdmovetorace-patch.pyと同じ楽観的排他制御
  パターンを適用: POSITION解決の開始直前に
  `version = context.core.tracklist.get_version().get()`を記録し、
  `tracklist.add()`実行後、実際に1曲以上追加できていた場合のみ(0件追加=そもそも
  versionが増えないケースを誤検知しないよう`new_tl_tracks`/`tl_tracks`が非空で
  あることをガードに使用)versionがbaseline+1と一致するか確認、不一致ならACK
  Bad song indexへ変換(move/moveidと同様「操作は既に実行された状態でACKを返す」
  既知の許容パターン)。POSITION省略時(絶対追加のみ)は解決処理自体が無く単一
  core呼び出しで完結するためレースが無く対象外のまま。3ファイル5関数に横展開する
  共有ヘルパー`_mpd_check_position_race`を各ファイルへ導入。パッチ適用後の生成
  ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)
  であることも確認。`nix/lib/mopidy-env.nix`にmpdfloatnonfinite-patch.pyの直後
  として登録しビルド成功、生成ソースに新実装(`_mpd_check_position_race`)が
  反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで実機確認 — 単一接続での`add "URI" "+0"`(現在曲直後)/
  `addid "URI" "-0"`(現在曲直前)/`findadd "(...)" position "+0"`/
  `searchadd "(...)" position "0"`(絶対位置)が全て従来通り正しい位置に挿入される
  ことを確認(回帰なし)。**TOCTOUレース自体の再現確認**: 6曲キュー+`play "0"`
  (実際にストリーム解決・再生開始、state:play確認)の状態で、別4接続から計60回の
  `add "URI" "+0"`を並行実行しつつ、別1接続で`swap 0 5`(現在曲tlidの位置を0/5間で
  往復させ「現在曲位置」を絶えず変化させる)を60回連打するストレステストを実施 —
  60回中32回が`ACK [2@0] {add} Bad song index`となり本パッチのversionチェックが
  実際にレースを検知・遮断したことを確認(旧実装ならこの32回も含め全件が
  無警告でOKを返し無関係な位置へサイレントに挿入されていたはず)。ストレス試験後も
  接続断・例外0件、mopidy.logにERROR/Traceback 0件。旧来の`tagtypes`/`status`/
  `search any "yoasobi"`/`count any "yoasobi"`/`list album`/`addid`(POSITION省略、
  従来の末尾追加)/`stats`の回帰なしを確認。
- [x] `mopidy_mpd/protocol/playback.py`の`volume()`(相対音量変更コマンド
  `volume {CHANGE}`)が`context.core.mixer.get_volume()`(読み取り)と
  `context.core.mixer.set_volume(new_volume)`(書き込み)という2回の**別々の**
  pykka actor呼び出しを、その間を保護する仕組み無しに実行しているTOCTOUレース
  (read-modify-write, lost update)。TODO/既知の軽微な残課題を全項目消化済みのため
  自走エージェントがmopidy_mpdのコード品質を再調査して新規発見・追加した項目
  (直前のコミットで`audio_output.py`の`toggleoutput()`について全く同じ構造の
  バグ`get_mute()`->`set_mute()`が`mpdoutputtogglerace-patch.py`により既に
  修正済みだったが、同じ`context.core.mixer`actorに対して構造的に同一の
  read-modify-writeを行う`playback.py`の`volume()`には対応する保護が一切無く、
  `setvol`/`getvol`は既に対応済みなのに相対指定の`volume {CHANGE}`だけが
  取りこぼされている非対称な状態だった)。
  mopidy_mpdは各クライアント接続を別OSスレッドのpykka.ThreadingActor
  (MpdSession)として実行するため、2本の接続がほぼ同時に`volume +10`を送ると
  両方が同じ古いold_volumeを読んだ後に両方が同じnew_volumeを書き込んでしまい、
  本来2回の+10で反映されるべき変化が1回分しか反映されない。両クライアントとも
  OKを受け取るためサイレントに音量がクライアントの意図と食い違ったまま`status`の
  `volume:`フィールドに反映され続ける実害がある。
  verified: mpdvolumerace-patch.py。mpdoutputtogglerace-patch.pyと同じ流儀で
  `playback.py`にモジュールレベルの`threading.Lock()`(`_mixer_volume_lock`)を
  追加し、`volume()`の`get_volume()`->`set_volume()`複合操作全体と`setvol()`の
  `set_volume()`呼び出しをwithブロックで直列化(同じ音量値を書き換える`setvol`が
  `volume`の読み取りウィンドウに割り込むケースも合わせて防止)。パッチ適用後の
  生成ソースは一時コピーに`chmod u+w`して`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`に
  `mpdaddposrace-patch.py`の直後として登録しビルド成功。dev mopidy(6601)を
  実際に起動しMPDで実機確認 — 単一接続での`setvol 40`→`getvol`(40)→
  `volume +10`→`getvol`(50)→`volume -5`→`getvol`(45)が全て従来通り正しく動作
  することを確認(回帰なし)。**TOCTOUレース自体の再現確認**: `setvol 20`で
  基準値を設定した状態から、別10接続で`volume +1`を並行実行するストレステストを
  5ラウンド実施 — 全5ラウンドとも実際の最終`getvol`値が期待値(20+10=30、
  10回の+1が1回も失われていない)と完全一致し、lost updateが発生しないことを
  確認(旧実装なら並行タイミング次第で期待値未満になっていたはず)。さらに
  `setvol 50`5本と`volume +0`5本を同時実行する混在ストレステストも実施し、
  全10本がOKを返した上で最終`getvol`が50(直列化により整合)であることを確認。
  ストレス試験後も接続断・例外0件、mopidy.logにERROR/Traceback 0件。旧来の
  `status`/`tagtypes`の回帰なしを確認。
- [x] `mopidy_mpd/protocol/music_db.py`の`_query_from_mpd_search_parameters()`(旧来の
  空白区切りTYPE/WHAT複数ペア形式、`find TYPE1 WHAT1 TYPE2 WHAT2...`)が、複数の
  TYPE/WHATペアを渡しても`query`dictに全フィールドを積むだけで、新フィルタ式
  `(Tag == "x")`用に導入済みの`__mpd_positives__`(find/search/count/findadd/searchadd/
  searchaddplが共有するローカルpost-filter`_mpd_filter_positives()`への入力)を一切
  生成しない不具合。`find()`自身のdocstringが「GMPC: also uses find album [ALBUM]
  artist [ARTIST] to list album tracks」と明記する、公式に想定された複数タグ同時指定
  (AND検索)が機能していなかった。mopidy_ytmusic.library.search()は
  `if "any" in query: ... elif "track_name" in query: ... elif "albumartist" in query
  or "artist" in query: ... elif "album" in query: ... elif "genre" in query: ...
  elif "uri" in query: ... else: ...`という単一フィールドのみを見るelif連鎖のため、
  query dictに複数フィールドが同時に入っていても優先順位が最も高い1つだけが使われ、
  他のキーは完全に無視される。旧来形式は`__mpd_positives__`を作らないため
  `_mpd_pop_positives()`が返すpositivesが常に空リストとなり、ローカル側でも救済
  されない。結果、例えば`find title "X" artist "Y"`のような複数フィールド指定で
  後続フィールドがサイレントに黙殺され、該当しないはずの曲まで含めて返ってしまう
  (件数が多すぎるだけでエラーにも0件にもならないため発見しづらい)。TODO/既知の
  軽微な残課題を全項目消化済みのため自走エージェントが調査して新規発見・追加した項目
  (163個の既存パッチをgrepで照合し、`mpdfindexactfilter-patch.py`/
  `mpdnegfilter-patch.py`/`mpdfilterkind-patch.py`/`mpdnegonlyfilter-patch.py`は
  いずれも括弧付き新フィルタ式のみが対象で、旧来の空白区切り複数ペア形式の
  複数フィールドAND処理には未着手であることを実際にファイル内容を読んで確認した上で
  着手)。
  verified: mpdfindmultitag-patch.py。新フィルタ式と同じ`__mpd_positives__`機構を
  旧来形式にも配線: 全フィールドがちょうど1値ずつの場合のみ、各`(field, "exact",
  value)`をpositivesへ積む(同一フィールドに複数値が渡された場合は従来通りbackendへの
  結合テキスト検索のままとし誤って過剰制約しない)。これにより既存の
  `_mpd_backend_search_exact()`がpositives有り→backend側exact=True narrowingを
  無効化しローカルの`_mpd_filter_positives`(exact判定、大文字小文字区別は
  find=True/search系=Falseで既存のまま)に委ねるため、backendが1フィールドしか
  見ていなくても残りのフィールドがローカルで正しくAND絞り込みされる。find/search/
  count/findadd/searchadd/searchaddplがこの共通関数を経由するため一括で直る。
  パッチ適用後の生成ソースは一時コピーに`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`にmpdvolumerace-patch.pyの
  直後として登録しビルド成功、生成ソースに新実装(`_mpdfindmultitag_positives`)が
  反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで実機確認 — **不具合の実在と修正を実データで確認**: `find title
  "アイドル"`(単一フィールド)→キング・スーパー・マーチ・バンド版とYOASOBI版の
  2曲がヒット、`find title "アイドル" artist "YOASOBI"`(正しいartist)→YOASOBI版
  1曲のみに正しく絞り込み、`find title "アイドル" artist "BogusArtistXYZ999"`
  (存在しないartist)→**0件**(修正前ならtrack_nameブランチのみでartist条件が
  無視され前者と同じ2曲がヒットしていたはず)。同じ組み合わせを`search`(大文字小文字
  無視)でも確認 — `search title "アイドル" artist "yoasobi"`(小文字)→1曲ヒット、
  `search title "アイドル" artist "bogusxyz"`→0件。`count title "アイドル" artist
  "YOASOBI"`→songs:1、`count title "アイドル" artist "BogusArtistXYZ999"`→
  songs:0。`findadd title "アイドル" artist "YOASOBI"`→`playlistinfo`で正しく
  1曲のみ追加を確認。回帰なし確認: 単一フィールド`find title "アイドル"`
  (2曲、無変更)/`find album "アイドル"`(既存の別限界、無変更)、同一フィールド
  複数値`find artist "YOASOBI" artist "Ayase"`(positives対象外、従来通り結合検索)、
  `sort`/`window`修飾併用、括弧付き新フィルタ式`find "(Artist == \"YOASOBI\")"`
  (無変更に正常動作)、`tagtypes`/`status`の回帰なし。mopidy.logにTraceback/ERROR
  0件を確認。

- [x] `mopidy_ytmusic.library.py`の`YTMusicLibraryProvider.search()`が`query["date"]`
  (MPDの`find`/`search`/`count`/`searchadd`等が使う"date"タグ。`music_db.py`の
  `_LIST_MAPPING`/`_SEARCH_MAPPING`で`"date": "date"`と正式にマップされ、`find()`
  自身のdocstringが"also uses the search type \"date\"."と明記する公式に想定された
  検索タイプ)を一切扱わないif/elifチェーンのため、`any`/`track_name`/
  `albumartist`/`artist`/`album`/`genre`/`uri`のどの分岐にも一致せず常に最終
  `else`へ落ち、何もエラーにならないまま`return None`(0件)を返してしまう不具合。
  同じ「elif連鎖に特定タグの分岐が無く0件になる」パターンは`genre`
  (ytsearchgenre-patch.py)と`uri`(ytsearchuri-patch.py)は既に修正済みだったが、
  `date`はどのパッチにも登場せず未着手のまま残っていた。TODO/既知の軽微な残課題を
  全項目消化済みのため自走エージェントがソースを再監査して新規発見・追加した項目
  (`nix/lib/mopidy-env.nix`の既存186パッチ登録行とconfigs/media/mopidy/の
  パッチファイル一覧を照合し、mopidy_mpd側protocol/*.pyは既に高密度にパッチ済みで
  未パッチの新規バグが見当たらなかったため、mopidy_ytmusic側を精査して発見)。
  verified: ytsearchdate-patch.py。ytsearchgenre-patch.pyと同じ実装で`"date"`分岐を
  `uri`分岐の手前に追加(`any`/`genre`分岐と同じベストエフォートのテキスト検索
  `filter=None`へフォールバック。`music_db.py`の`_mpd_negative_field_values()`等
  post-filter側は既に`date`フィールドをサポート済みのためbackendが結果さえ返せば
  絞り込み自体は元から正しく機能する)。パッチ適用後の生成ソースは一時コピーに
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`にytsearchgenre-patch.pyの直後として登録しビルド成功、
  生成ソースに新実装(`elif "date" in query:`)が反映されていることを確認した上で
  dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  **不具合の再現確認**: 修正前(パッチ適用前のコード読解で確認)は`date`が
  どの分岐にも一致せず即座に`return None`(バックエンド呼び出し自体が発生しない)。
  **修正の確認**: `find date "yoasobi"`→`find any "yoasobi"`と同一の2件
  (album/track)が正しくヒットし、`count date "yoasobi"`→`songs: 2`
  (`find any "yoasobi"`と同じ結果件数)となることを確認、date分岐が実際に
  backendへ委譲されていることを実証。`find date "2020"`は0件だったが、
  `find any "2020"`も同様に0件でありYTMusic検索API自体が裸の年号のみのクエリで
  有効な音楽結果を返さない既存の制約であって本パッチの不具合ではないことを
  比較確認済み。回帰なし確認: `find genre "Pop"`(既存パッチ、無変更に正常動作)、
  `find artist "YOASOBI"`(複数アルバムヒット、無変更)、`tagtypes`/`status`の
  回帰なしを確認。mopidy.logにException/Traceback/ERROR 0件を確認。

- [x] `mopidy_ytmusic.library.py`の`YTMusicLibraryProvider.get_distinct()`が"artist"/
  "albumartist"/"album"の3分岐しか持たず、`mopidy_mpd/protocol/music_db.py`の`list()`
  コマンドが公式docstringで"TYPE should be album, artist, albumartist, date, or genre."
  と明記する残り2TYPEのうち"date"を渡すとどの分岐にも一致せず、初期化直後の空`ret`が
  例外もACKエラーも無く常にそのまま返ってしまう不具合。`get_distinct`は`list`だけでなく
  `count ... group date`(mpdcount-patch.py)/`searchcount ... group date`
  (mpdsearchcount-patch.py)/ネストした`list Album group Date`等でも共有されるため
  波及範囲は広い。同じ関数の`search()`側"date"分岐は既にytsearchdate-patch.pyで
  修正済みだったが、`get_distinct()`側(list/count groupの列挙経路)は一度も
  手当てされていなかった。TODO/既知の軽微な残課題を全項目消化済みのため自走
  エージェントがExploreサブエージェントに187パッチ登録済みnix/lib/mopidy-env.nixと
  configs/media/mopidy/のパッチ一覧・BACKLOG.mdの修正パターンを突き合わせて未パッチ
  箇所の再監査を委任し新規発見・追加した項目("album"分岐がytdistinct-patch.py/
  ytdistinctfilter-patch.pyで2回パッチされ`get_library_albums()`の"year"キーを
  `wanted_dates`フィルタとして既に参照していることから、"year"が有効なデータソース
  であることを既存コードで確認した上で着手。"genre"はライブラリalbum/artist dictに
  トラック単位のジャンル情報が実質無く正しくdistinct値を列挙する術が無いため対象外
  と判断)。
  verified: ytdistinctdate-patch.py。ytdistinctfilter-patch.pyの"album"分岐と対称に、
  `get_library_albums()`から集めた各アルバムの"year"をdistinct値として収集する
  "date"分岐を追加(query内の"artist"/"albumartist"で絞り込み、"album"でも絞り込み
  可能に)。パッチ適用後の生成ソースは一時コピーに`ast.parse`で構文確認、2回適用も
  試し2回目はアンカー不在の`AssertionError`となり冪等(スキップ)であることを確認。
  `nix/lib/mopidy-env.nix`にytdistinctfilter-patch.pyの直後に登録しビルド成功、生成
  ソースに新実装(`elif field == "date":`)が反映されていることを確認した上でdev
  mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  **ロジック検証**: パッチ済みenvの`mopidy_ytmusic.library.YTMusicLibraryProvider`を
  実際にimportし`backend.api.get_library_albums`をMagicMockで差し替えて直接メソッド
  呼び出しで確認: year違いの複数アルバム(2020/2021/year欠落)→無条件で
  `{"2020","2021",""}`(mopidy_mpd側の`_mpd_list_grouped`が`if v`で空文字列を除外する
  仕様と合わせて正しく機能)、`query={"artist":["Artist One"]}`→該当アーティストの
  アルバムのyearのみ`{"2020","2021"}`、`query={"album":["Album C"]}`→該当アルバムの
  yearのみ`{"2020"}`、artist+album組み合わせで該当なし→空集合、
  `get_library_albums`が例外送出→握りつぶして空集合(クラッシュしない)、を確認。
  **実機確認**: `list date`/`list date artist "Foo"`/`count group date`はいずれも
  例外なく`OK`応答(このアカウントはアーティストをフォローしているのみでアルバムを
  ライブラリ保存していないため実データは空、ytdistinct-patch.py検証時と同じ既知の
  アカウント状態でありパッチの不具合ではない — mopidy.logに"YTMusic failed getting
  albums from library"等のエラーが一切出ていないことで確認)。回帰なし確認:
  `list album`/`list artist`/`list Album group AlbumArtist`/`search any "yoasobi"`
  (実データでヒット、Dateタグも従来通り表示)/`tagtypes`/`status`の回帰なし。
  mopidy.logにTraceback/ERROR 0件を確認。

- [x] `tagtypes enable/disable {NAME...}` / `protocol enable/disable {FEATURE...}` /
  `stringnormalization enable/disable {FEATURE...}` (connection.py、mpdstringnorm-patch.py/
  mpdprotocol-patch.pyが追加した2コマンドも同型) が、いずれも `_validate_*(parameters)` で
  `set(parameters).issubset(既知の固定集合)` という大文字小文字を区別する完全一致判定を行って
  おり、`tagtypes disable artist`(小文字)のような入力を `ACK Unknown tag type` で拒否して
  しまう不具合。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントがExplore
  サブエージェントに委任しconnection.py/current_playlist.pyを既存パッチ群と突き合わせて
  新規発見・追加した項目。実MPD(gh rawで実際にsrc/tag/ParseName.cxx・
  src/command/ClientCommands.cxxを取得しソース確認)はこの3コマンドいずれも
  `tag_name_parse_i()`/`protocol_feature_parse_i()`/`string_normalization_parse_i()`と
  大文字小文字を区別しない"_i"サフィックスの専用パーサーで名前解決しており、本実装との
  乖離を確認。mpdprotocol-patch.py自身のコメントに「(StringIsEqualIgnoreCase で
  大文字小文字を区別しない)」と実MPD仕様を明記していながら実装がその通りになっていない
  (コード⇔コメント不一致)ことでも発覚。
  verified: mpdtagtypecase-patch.py。`addtagid`/`cleartagid`(mpdaddtagid-patch.pyの
  `_mpd_canonical_tag_type()`、小文字比較で正規名を1件ずつ解決)と同じ手法を
  `tagtypes`/`stringnormalization`/`protocol`の3関数に適用し、bool検証のみの
  `_validate_*`を正規名リストを返す`_resolve_*`へ置き換え、`update()`/
  `difference_update()`には解決済みの正規名(大文字始まりの`Artist`等)を渡すよう変更
  (検証前の生の文字列をそのまま格納すると出力側`translator._has_value()`の
  `tagtype in tagtypes`判定と一致せずenable/disableが実質無効化されたままになるため、
  issubsetの判定を緩めるだけでなく正規名解決が必須と判断)。パッチ適用後の生成ソースは
  一時コピーに`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`にmpdfindmultitag-patch.pyの直後に登録しビルド成功、生成ソースに
  新実装(`_resolve_tagtypes`/`_resolve_stringnorm_features`/`_resolve_protocol_features`)が
  反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に起動し
  MPDで実機確認 — `tagtypes disable artist`(小文字)→`OK`、直後の`tagtypes`一覧から
  `Artist`が消えている(正規名で正しく除去されたことを確認)、`tagtypes enable Artist`→
  `OK`で復元。`tagtypes disable bogus`(未知タグ)→`ACK Unknown tag type`のまま(回帰なし)。
  `tagtypes disable AlBuM`/`tagtypes enable ALBUM`(混在ケース)→ともに`OK`で正しく
  `Album`が着脱。`protocol enable HIDE_PLAYLISTS_IN_ROOT`(全大文字)→`OK`、
  `protocol`→`feature: hide_playlists_in_root`(正規名で列挙)、
  `protocol disable Hide_Playlists_In_Root`(混在)→`OK`で正しく消滅。
  `protocol enable bogus_feature`→`ACK Unknown protocol feature`(回帰なし)。
  `stringnormalization enable STRIP_DIACRITICS`→`OK`、`stringnormalization`→
  `stringnormalization: strip_diacritics`、`stringnormalization disable
  Strip_Diacritics`(混在)→`OK`で正しく消滅。`stringnormalization enable bogus`→
  `ACK Unknown string normalization`(回帰なし)。回帰なし確認: `status`/`tagtypes`
  (引数無し一覧)/`list album`が正常応答、mopidy.logにTraceback/ERROR 0件を確認。

- [x] フィルタ式 `(Genre == "X")` (単独条件) が mopidy_ytmusic backend では常に0件になる件:
  ytsearchgenre-patch.py が `search()` の "genre" 分岐に "any" と同じベストエフォートの
  テキスト検索を実装済みだったが、mopidy_ytmusic の Track は7箇所全て `genre=""` 固定
  (YouTube Music のトラックメタデータに曲単位のジャンルタグが存在しないため取得しようが
  ない) のため、`_query_from_mpd_filter_expression()` (music_db.py) がフィルタ式の肯定
  条件を無条件で positives へ積み `_mpd_track_matches_positives()` が
  `_mpd_negative_field_values(track, "genre")` (=常に`[]`) を見て無条件却下してしまい、
  backend が実際に見つけた候補が最終的に0件へ丸められてしまっていた不具合。"any"
  フィールドは同種の問題に既に `if field == "any": continue` (ローカル再検証スキップ)
  で対処済みだったが genre は対象外のままだった。TODO/既知の軽微な残課題を全項目
  消化済みのため自走エージェントが調査サブエージェントに委任し music_db.py/library.py
  を突き合わせて新規発見した項目。
  verified: mpdgenrepositivetrust-patch.py。`_mpd_track_matches_positives()` に
  `field == "genre" and len(positives) == 1` (genre が唯一の肯定条件のときだけ) の
  分岐を追加し "any" と同様ローカル再検証をスキップしbackendを信頼する形に修正。
  他フィールドと併用時 (`find genre "X" artist "Y"` 等) は mopidy_ytmusic の
  `search()` が elif 連鎖で genre 分岐へ到達せず backend が実際には genre を見ていない
  (mpdfindmultitag-patch.py が対処した既知の制約と同根) ため対象外のまま維持 (安易に
  一律スキップすると AND のはずが誤って緩んでしまう新たな不具合を生むため)。パッチ
  適用後の生成ソースは一時コピーに`ast.parse`で構文確認、2回適用しても冪等(スキップ)
  であることも確認。`nix/lib/mopidy-env.nix`にmpdtagtypecase-patch.pyの直後に登録し
  ビルド成功、生成ソースに新実装が反映されていることを確認した上でdev mopidy(6601,
  ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  **修正前**: `find "(Genre == \"pop\")"`/`find "(Genre == \"rock\")"`→ともに`OK`のみ
  (0件)。同時に`find "(Artist == \"YOASOBI\")"`は多数ヒットしており genre 経路だけが
  機能不全と確認。
  **修正後**: `find "(Genre == \"pop\")"`→"Radio • Pop"アルバムが1件ヒット、
  `search "(Genre == \"pop\")"`(大文字小文字無視版)も同様に1件、
  `find "(Genre == \"j-pop\")"`→"J-Pop Radio"アルバムが1件ヒット、実在しないジャンル
  `find "(Genre == \"XyzzyNoSuchGenreQwerty123\")"`→`OK`のみ(0件、無関係な結果を
  誤って通過させないことを確認)。**意図的に対象外のまま**: 複合条件
  `find "(Genre == \"pop\") AND (Artist == \"YOASOBI\")"`および旧来ペア形式
  `find genre "pop" artist "YOASOBI"`はいずれも引き続き0件(backendがgenreを見ない
  ケースのため妥当、新たな不具合を生んでいないことを確認)。回帰なし確認:
  `find "(Artist == \"YOASOBI\")"`(22件ヒット、従来通り)、`list album`、
  `search any "yoasobi"`(3件ヒット)、`tagtypes`、`status`がいずれも正常応答。
  mopidy.logにTraceback/ERROR 0件を確認。

- [x] `albumart`/`readpicture` が失敗したuriを一切キャッシュせず、同一の失敗する
  YTMusic API呼び出しを無駄打ちし続ける件: `_mpdart_bytes()` (mpd-patch.py,
  mpdalbumartrace-patch.pyがスレッド安全化) は成功時のみ `_MPDART_CACHE` へ
  キャッシュし、`get_images()` が例外/空・ダウンロード失敗の3経路はいずれも
  キャッシュしない実装だった。TODO/既知の残課題を全項目消化済みのため
  自走エージェントがリサーチサブエージェントに委任しrmpc本体(mierak/rmpc)を
  実際にcloneして調査したところ、`rmpc-shared/src/mpd_client_ext.rs`の
  `find_album_art()`(既定orderは`AlbumArtOrder::EmbeddedFirst`、
  `rmpc/src/core/command.rs`で現在曲のアート取得に実際に使われる)が
  「先にreadpictureを試し、結果がNoneまたはACK50(NoExist)なら自動的に
  albumartへフォールバックする」設計であることを確認した上で新規発見・
  追加した項目。mopidy_ytmusicのlibrary.get_images()(library.py)は、
  アルバム情報欠落/プライベート化/地域制限等で`self.backend.api.get_album()`
  (実際のYouTube Music APIへのネットワーク呼び出し)が失敗するとlibrary.py
  自身が例外を握り潰しimages=[]を返すのみで、成功結果と違って一切
  キャッシュしないため、readpicture->albumartのフォールバック1往復だけで
  同一の失敗するAPI呼び出しを2回連続で無駄打ちし、かつ何もキャッシュに
  残らないため同じ曲が再度表示・再生・キュー投入されるたびに(プロセスが
  生きている限り永久に)繰り返される実害と確認。
  verified: mpdalbumartnegcache-patch.py。`_MPDART_CACHE`と対になる
  負のキャッシュ`_MPDART_NEG_CACHE`(uriの集合)を導入し、`_mpdart_bytes()`の
  3つの失敗経路(get_images()例外・imgs空・ダウンロード失敗)全てで記録、
  既存の`_mpdart_lock`で直列化し`_MPDART_CACHE`と同じ「64件超で全clear」
  というサイズ上限方式を踏襲(mpdalbumartrace-patch.pyと同じ流儀)。
  `_mpdart_send()`は既にdataがfalsyなら`MpdNoExistError`を送出する実装の
  ため応答内容・ACKコードは無変更(副作用は無駄なAPI呼び出し削減のみ)。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`に
  mpdgenrepositivetrust-patch.pyの直後に登録しビルド成功、生成ソースに
  新実装(`_MPDART_NEG_CACHE`/`_mpdart_neg_cache_add`)が反映されていることを
  確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで
  実機確認 — 存在しないアルバムID(`ytmusic:album:BOGUSALBUMID12345negcachetest`)
  に対し`readpicture`→`albumart`→`readpicture`と3回連続で送信、いずれも
  従来通り`ACK [50@0] {readpicture/albumart} No file exists`で応答内容の
  回帰なしを確認した上で、mopidy.logの`YTMusic unable to get image url for
  ytmusic:album:BOGUSALBUMID12345negcachetest`(mopidy_ytmusic側が失敗ごとに
  出すログ)が3回中1回のみ(1回目の実呼び出しのみ実際にAPIを叩き、2回目以降は
  `_MPDART_NEG_CACHE`ヒットでAPI呼び出し自体が発生しなかったことを確認)。
  正キャッシュ側の回帰なし確認: 実データ(YOASOBI「THE BOOK for,」アルバム
  `ytmusic:album:MPREb_a5PIYyducZQ`)で`readpicture`/`albumart`ともに実際の
  画像(55090バイトJPEG、type: image/jpeg)を正しく取得できることを確認
  (成功パスの`_MPDART_CACHE`格納・`_MPDART_NEG_CACHE.discard()`は無害な
  安全策であり実害には無関係)。旧来の`status`/`tagtypes`/`search any
  "yoasobi"`(3件ヒット)の回帰なしを確認。mopidy.logのERROR/Tracebackは
  上記の意図した1件のみで新規リグレッションなし。

- [x] mopidy_ytmusic.library.py の `search()` が MPD の `track` タグ (内部フィールド名
  `track_no`、`mopidy_mpd/protocol/music_db.py` の `_LIST_MAPPING`/`_SEARCH_MAPPING` で
  `"track" -> "track_no"` と正式にマップ) を扱う分岐を持たず、if/elif チェーンのどの
  分岐にも一致しないため常に最終 else へ落ち、何もエラーにならないまま `return None`
  (0件) を返してしまう不具合。TODO/既知の軽微な残課題を全項目消化済みのため自走
  エージェントがリサーチサブエージェントに委任し、`ytsearchgenre-patch.py`/
  `ytsearchdate-patch.py`/`ytsearchuri-patch.py` と同じ「search()のelif連鎖に特定
  タグの分岐が無く常に0件になる」パターンを機械的に洗い出して新規発見・追加した項目。
  genre/date と異なり `track_no` は実データが入る唯一のケースであることを確認済み:
  `albumToTracks()` (library.py) が `for index, song in enumerate(album["tracks"],
  start=1): ... track_no=index` としてアルバムブラウズ/lookup時に `self.TRACKS` へ
  妥当なトラック番号を格納する一方 (他の生成箇所 — playlistToTracks/
  uploadAlbumToTracks 等 — は `track_no=None` 固定)、search() 自身はそのフィールドを
  一切見ずに常に0件を返しており、genre/date (元々データが空で結果的に0件が妥当) より
  実害が大きいと判断。
  verified: ytsearchtrack-patch.py。`ytsearchgenre-patch.py`/`ytsearchdate-patch.py`と
  同じ流儀で、"any" 分岐と同じベストエフォートのテキスト検索
  (`self.backend.api.search(" ".join(query["track_no"]), filter=None)`) を
  `elif "uri" in query:` の手前に追加。パッチ適用後の生成ソースは一時コピーに
  当てて(nix store由来の読み取り専用パーミッションのため`chmod u+w`してから)
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`にytsearchdate-patch.pyの直後に登録しビルド成功、
  生成ソースに新実装(`elif "track_no" in query:`分岐)が反映されていることを
  確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  **修正前(コード読解による確認)**: if/elifチェーンに`track_no`分岐が無く、
  `else`節の`logger.debug(...); return None`へ必ず落ちるため`find track`/
  `search track`は常に`OK`のみ(0件)だったことをソース上で確認。
  **修正後**: 実データを持つアルバム`ytmusic:album:MPREb_a5PIYyducZQ`
  (YOASOBI「THE BOOK for,」)を`lsinfo`でブラウズし`self.TRACKS`に
  `track_no=1`を持つ実トラック(`ytmusic:track:EjaQdBcF6K4`、`Track: 1/12`)を
  投入した上で、`find track "1"`→修正前は無条件0件だったのに対し、修正後は
  ベストエフォートのテキスト検索経由でAPI呼び出しに到達し実際にヒット
  (`ytmusic:track:elzwHzW4020`, "Number One - Bankai" が1件)を確認、
  `find track "Orion"`(該当曲名の一部)→0件(ベストエフォート検索の限界、
  API呼び出し自体は発生しmopidy.logにTraceback無し)。**意図的に対象外のまま**:
  フィルタ式`find "(Track == \"1\")"`は0件のまま
  (`_mpd_track_matches_positives()`によるローカル完全一致の後段再検証が
  `Track.track_no`(int)と文字列"1"の型不一致で弾く、genre専用に対処した
  `mpdgenrepositivetrust-patch.py`と同種の別バグであり、他フィールド併用時の
  誤緩和を避けるためgenre同様に対象を絞る設計判断を踏襲し今回は対象外)。
  回帰なし確認: `find artist "YOASOBI"`(22件)、`find genre "pop"`(1件)、
  `find date "2026"`、`find file "ytmusic:track:EjaQdBcF6K4"`(1件、file/filenameタグ
  経由のuri分岐が無変更)、`search any "yoasobi"`(3件)、`status`がいずれも
  正常応答。mopidy.logにTraceback/ERROR 0件を確認。

- [x] 上記で「意図的に対象外のまま」とした、フィルタ式`find "(Track == "N")"`
  (単独条件) が mopidy_ytmusic backend では常に0件になる不具合。TODO/既知の
  残課題を全項目消化済みのため自走エージェントが調査を継続し、
  `mpdgenrepositivetrust-patch.py`の genre と同種のバグと確認した上で追加した
  項目 (原因の再調査: 直前のエントリでは「`Track.track_no`(int)と文字列の
  型不一致」と記述していたが、実際には`_mpd_negative_field_values()`が
  `str(track.track_no)`へ変換済みのため型不一致は起きない。真因は
  `ytsearchtrack-patch.py`が追加した`search()`の`track_no`分岐が
  `parseSearch()`経由で返す`Track`に`track_no`を一切設定しない
  (`albumToTracks()`経由でアルバムをブラウズ/lookupした場合のみ`track_no`が
  入る) ため、`_mpd_track_matches_positives()`が
  `_mpd_negative_field_values(track, "track_no")`(=常に`[]`、値が無い)を見て
  `if not values: return False`により無条件却下し、backendが実際に見つけた
  best-effort候補が最終的に0件へ丸められてしまうこと。genreの原因
  (`Track.genre`が構造的に常に空文字) とは値が空になる経路が異なるが、
  「ローカル再検証がbackendのbest-effort結果を潰す」という結果は同一。
  verified: mpdtrackpositivetrust-patch.py。`mpdgenrepositivetrust-patch.py`と
  全く同じ設計方針 (`field == "track_no" and len(positives) == 1: continue`、
  track_noが唯一の肯定条件のときだけローカル再検証をスキップしbackendの
  best-effort結果を信頼) をgenreの直後に追加。mopidy_ytmusicのsearch()も
  elif連鎖のためtrack_noを他フィールドと併用すると分岐へ到達せず
  track_noを一切見ない (genreと同根の制約) ので、genre同様「positivesが
  track_no単独のときのみ」に安全のため対象を限定。パッチ適用後の生成
  ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等
  (スキップ) であることも確認。`nix/lib/mopidy-env.nix`に
  mpdalbumartnegcache-patch.pyの直後に登録しビルド成功、生成ソースに
  新実装(`field == "track_no" and len(positives) == 1`)が反映されていることを
  確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで
  実機確認 — 実データを持つアルバム`ytmusic:album:MPREb_a5PIYyducZQ`
  (YOASOBI「THE BOOK for,」)を`lsinfo`でブラウズし`track_no=1`を持つ実
  トラック(`Track: 1/12`)を`self.TRACKS`へ投入した上で、
  **修正前相当の旧来形式** `find track "1"`(フィルタ式を経由せずpositivesの
  ローカル再検証が発生しない経路)は既に1件ヒットしていた
  (`ytmusic:track:elzwHzW4020`, "Number One - Bankai") のに対し、
  **修正前**のフィルタ式`find "(Track == \"1\")"`は0件だったことをソース上の
  分岐 (`if not values: return False`) で確認済み。**修正後**:
  `find "(Track == \"1\")"`→修正前は無条件0件だったのに対し、修正後は旧来
  形式と全く同じ`ytmusic:track:elzwHzW4020`が1件ヒット、`search "(Track ==
  \"1\")"`(大文字小文字無視版)も同一の1件ヒット。**best-effort検索の限界
  (新規リグレッションではないことを確認)**: 存在しないトラック番号
  `find "(Track == \"999999\")"`は0件にならず別の1曲がヒットしたが、
  同一クエリを**旧来形式**`find track "999999"`(本パッチ適用範囲外、修正前
  から存在する経路)で送っても同じく別の1曲がヒットすることを確認 —
  YTMusic検索APIのテキスト relevance マッチによる既知の best-effort の限界
  (genre側で既に許容されている設計と同種) であり、本パッチが新たに
  誤検出を生んだものではないと確認。**意図的に対象外のまま**: 複合条件
  `find "(Track == \"1\") AND (Artist == \"YOASOBI\")"`は引き続き0件
  (backendがtrack_noを見ないケースのため妥当、新たな不具合を生んでいない
  ことを確認)。回帰なし確認: `find "(Genre == \"pop\")"`(1件、genre側の
  同種の信頼ロジックに影響なし)、`find "(Artist == \"YOASOBI\")"`(22件)、
  `status`/`tagtypes`が正常応答。mopidy.logにTraceback/ERROR 0件を確認。

- [x] `prio`/`prioid`/`rangeid`/`addtagid`/`cleartagid` (mpdprio-patch.py/
  mpdrangeid-patch.py/mpdaddtagid-patch.py で実装済み) が、成功時に idle "playlist"
  イベントを一切発火しない不具合。TODO/既知の残課題を全項目消化済みのため自走
  エージェントが、mpdcrossfadeidle-patch.py(crossfade等のidle options未発火)・
  mpdstickeridle-patch.py(sticker set/deleteのidle sticker未発火)と同種のギャップ
  として current_playlist.py を再調査し新規発見・追加した項目。実 MPD
  (MusicPlayerDaemon/MPD src/command/QueueCommands.cxx handle_prio/handle_prioid/
  handle_rangeid、src/command/TagCommands.cxx handle_addtagid/handle_cleartagid) を
  実際に clone してソース確認したところ、いずれも成功時に queue の version を上げ
  IDLE_PLAYLIST を発火する仕様と判明。一方この5コマンドは `context.core.tracklist`
  を一切経由せず translator.py の揮発性ストア(優先度/range/タグ)を直接書き換える
  だけのため、actor.py が拾う mopidy core 由来の `tracklist_changed` イベントに乗れず、
  `idle playlist` 待機中の他クライアント(rmpc含む、`playlistinfo`/`plchangesposid`で
  Prio/Range等を表示する導線あり)は起こされないままだった。
  verified: mpdqueueidle-patch.py。mpdcrossfadeidle-patch.py の
  `_mpdcrossfadeidle_notify()`/mpdstickeridle-patch.py の `_mpdsticker_notify()` と
  全く同じ機構 (`mopidy.listener.send(session.MpdSession, "playlist")`) を
  current_playlist.py 専用の `_mpdqueueidle_notify()` として新設し、5コマンドの
  成功パス末尾に追加 (`playlist` は status.py の SUBSYSTEMS に既存のため未変更)。
  パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix` に
  mpdtrackpositivetrust-patch.py の直後に登録しビルド成功、生成ソースに新実装
  (5箇所の `_mpdqueueidle_notify()` 呼び出し)が反映されていることを確認した上で
  dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 — 2本のTCP接続
  (A/B) で、Aが`idle playlist`待機中にBが`prio 100 "0:1"`/`prioid 50 "<tlid>"`/
  `rangeid <tlid> "5:"`/`addtagid <tlid> Comment "hello world"`/
  `cleartagid <tlid> Comment`を1つずつ実行 — 5コマンド全てでAが即座に
  `changed: playlist`で起床することを確認 (修正前は5つとも一切起床しなかったはずの
  状態からの改善、`OK`のみ返す変更前の実装をソース上でも確認済み)。bare `idle`
  (引数無し)でも同様に`prioid`実行で`changed: playlist`起床を確認。負例:
  無関係な`status`実行後は`idle playlist`が3秒待っても起床しない(誤発火なし)ことを
  確認。回帰なし確認: `playlistid`(Prio/Range/Added等の既存フィールドが正しく反映、
  addtagid→cleartagid後はCommentタグが正しく消えている)、`tagtypes`、`status`、
  `search any "yoasobi"`(3件)の応答が正常。mopidy.logにTraceback/ERROR 0件を確認。

- [x] `rm {NAME}` (stored_playlists.py、ストアドプレイリスト削除) が
  `context.core.playlists.delete(uri).get()` の戻り値 (bool、失敗時 `False`) を
  一切確認せず、削除が実際に失敗しても常に `OK` を返してしまう不具合。TODO/既知の
  残課題を全項目消化済みのため自走エージェントが、直近の一連の `.get()` 抜け/
  戻り値未チェック修正 (mpdsearchaddplsave-patch.py の `searchaddpl` save() None
  未チェック、mpdplaylistcreateguard-patch.py の `searchaddpl`/`playlistclear`
  create() None 未チェック等) と同種のパターンが他にも残っていないか
  `context.core.playlists.*` の呼び出しを再調査し新規発見・追加した項目。
  mopidy.core.playlists.delete() の docstring 通り、削除に失敗した場合は `False`
  を返す契約であり、実際に mopidy_ytmusic.playlist.YTMusicPlaylistsProvider.
  delete() は `api.delete_playlist()` が例外 (ネットワーク瞬断・認証切れ・既に
  削除済み等) を投げると `logger.exception()` した上で `False` を返す設計、既定の
  保存先スキームである mopidy.m3u.playlists の delete() も unlink() が OSError
  (Permission denied 等) を投げると同様に `False` を返す設計であり、実際に踏み
  うる。同じファイル内の `rename()` の末尾にある old_playlist の後始末用
  `context.core.playlists.delete(old_playlist.uri).get()` も同一の未チェック
  パターンだが、rename成功パス(コピー先の作成/保存は既に成功済み)での
  後始末失敗という異なる意味合いを持ち、chmod等による外部からの単純な障害注入では
  create/save側から先に失敗してしまい delete 単体の失敗を安全に単離して実機検証
  できなかったため、本項目のスコープからは対象外のまま残した(将来の別項目向けの
  メモ)。
  verified: mpdplaylistrmguard-patch.py。`save`/`searchaddpl`/`playlistclear`/
  `playlistadd` 等と同じ流儀で、`delete()` の戻り値が偽なら
  `exceptions.MpdSystemError("Failed to delete playlist")` (実MPDの
  ACK_ERROR_SYSTEM相当) を送出するよう変更。パッチ適用後の生成ソースは一時
  コピーに当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix` に mpdqueueidle-patch.py の直後に登録しビルド
  成功、生成ソースに新実装 (`if not context.core.playlists.delete(uri).get():
  raise exceptions.MpdSystemError(...)`) が反映されていることを確認した上で
  dev mopidy(6601, ytmusic実アカウント) を実際に起動しMPDで実機確認 —
  **不具合自体の再現**: パッチを一時的に nix/lib/mopidy-env.nix から除外して
  再ビルドし、`save "RmGuardTest1"` (既定の m3u バックエンド、ローカルディスク
  保存) でプレイリストを作成した上でその保存先ディレクトリ
  (`~/ai/mopidy-dev/data/m3u`) を `chmod 555` (書き込み不可) にした状態で
  `rm "RmGuardTest1"` を送信 → `OK` が返るが `listplaylists` には引き続き
  `RmGuardTest1` が残ったまま (削除が実際には全く行われていない)、mopidy.log には
  `mopidy.m3u.playlists ERROR Error deleting playlist 'm3u:RmGuardTest1.m3u8':
  Permission denied` が記録されているにも関わらず MPD クライアント側には一切
  通知されないことを実際に確認 (パッチ前の実際の不具合として再現確認)。本パッチを
  再適用したビルドで同一の条件 (ディレクトリ書き込み不可) で再実行したところ、
  `rm "RmGuardTest1"` → `ACK [52@0] {rm} Failed to delete playlist` に正しく
  変換され、`listplaylists` の内容も不変 (誤って削除済みと誤認しない) ことを確認。
  ディレクトリを書き込み可能に戻した状態 (通常系) では `rm "RmGuardTest1"` →
  `OK`・`listplaylists` から実際に消えていることを確認。回帰なし確認:
  既存の `rm "DoesNotExistXYZ"` (存在しないプレイリスト) → 従来通り
  `ACK [50@0] {rm} No such playlist`、`save "RmGuardTest2"` →
  `rename "RmGuardTest2" "RmGuardTest3"` → `rm "RmGuardTest3"` の一連の操作が
  正常に `OK` で完走、`tagtypes`/`status`/`search any "yoasobi"` の応答が正常。
  mopidy.logにTraceback 0件を確認。
- [x] `rename {NAME} {NEW_NAME}` (stored_playlists.py) が、新規コピー
  (create+save) 成功後の後始末である旧プレイリスト削除
  `context.core.playlists.delete(old_playlist.uri).get()` の戻り値 (bool、
  失敗時 `False`) を一切確認せず、削除が実際に失敗しても常に `OK` を返して
  しまう不具合。mpdplaylistrmguard-patch.py (`rm` の同型の戻り値未チェック)
  の verified 内に残した「rename() 末尾の同一パターンも残っているが、当時は
  create()/save() 側から先に失敗してしまい delete() 単体の失敗を安全に単離
  して実機検証できなかったため対象外のままにした」というメモを、TODO/既知の
  残課題を全項目消化済みの自走エージェントが引き継ぎ新規に追加した項目。
  verified: mpdplaylistrenameguard-patch.py。`rm`/`searchaddpl`/
  `playlistclear` 等と同じ流儀で、`delete()` の戻り値が偽なら
  `exceptions.MpdSystemError("Failed to delete playlist")` を送出するよう
  変更。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix` に
  mpdplaylistrmguard-patch.py の直後に登録しビルド成功、生成ソースに新実装
  (`if not context.core.playlists.delete(old_playlist.uri).get(): raise
  exceptions.MpdSystemError(...)`) が反映されていることを確認した上で dev
  mopidy(6601, ytmusic実アカウント) を実際に起動しMPDで実機確認。
  **rmguardで単離できなかった delete() 単体失敗の再現方法**: m3u backend の
  delete() は対象の「旧ファイル1つ」だけを `Path.unlink()` するため、
  ディレクトリ全体を書き込み不可にする(rmguard 検証時の手法、create/save も
  道連れで失敗してしまうため rename には使えない)のではなく、macOS の
  `chflags uchg <旧ファイル>` (ユーザ immutable フラグ) を保存済みプレイリスト
  ファイル1つにだけ立てることで、ディレクトリ自体の書き込み権限は保ったまま
  (新ファイルの create/save は成功する) 旧ファイルの unlink だけを
  `Operation not permitted` で失敗させ単離再現することに成功。
  **不具合自体の再現**: 本パッチを一時的に nix/lib/mopidy-env.nix から除外して
  再ビルドし、`save "RenameGuardProbe"` で作成した
  `~/ai/mopidy-dev/data/m3u/RenameGuardProbe.m3u8` に `chflags uchg` を立てた
  状態で `rename "RenameGuardProbe" "RenameGuardProbeNew"` を送信 → `OK` が
  返り `listplaylists` には新旧両方 (`RenameGuardProbe`/`RenameGuardProbeNew`)
  が並んで残ってしまう (複製は成功したのに旧プレイリストが消えていないにも
  関わらずクライアントは成功と誤認する) ことを実際に確認、mopidy.log には
  `mopidy.m3u.playlists ERROR Error deleting playlist
  'm3u:RenameGuardProbe.m3u8': Operation not permitted` が記録されているにも
  関わらず MPD クライアント側には一切通知されないことも確認 (パッチ前の実際の
  不具合として再現確認)。本パッチを再適用したビルドで同一の条件
  (旧ファイルのみ uchg) で再実行したところ、
  `rename "RenameGuardProbe" "RenameGuardProbeNew"` →
  `ACK [52@0] {rename} Failed to delete playlist` に正しく変換され、
  `listplaylists` の内容 (新旧両方残存) も不変 (誤ってrename完全成功と誤認
  しない) ことを確認。回帰なし確認: 通常系の `save`→`rename`(正常ファイル)→
  `listplaylists` (新名のみ) → `rm` の一連の操作が正常に `OK` で完走、既存の
  `rename "NoSuchPlaylistXYZ" "Whatever"`(存在しない旧名) →
  `ACK [50@0] {rename} No such playlist`、`rename` の新名が既存プレイリストと
  衝突 → `ACK [56@0] {rename} Playlist already exists`(いずれも既存の
  create/save より前のガードで無変更)、`tagtypes` の応答が正常。
  mopidy.logにTraceback 0件、想定外のERROR 0件(注入した1件のみ)を確認。
- [x] `mopidy_listenbrainz/playlists.py` の `ListenbrainzPlaylistsProvider.save()` が、
  uri が `listenbrainz:playlist:recommendation` プレフィックス (ListenBrainz公式が
  提供する週次の Weekly Jams/Weekly Exploration 等の推薦プレイリスト) の場合にのみ
  「新しい曲数が既存より厳密に増えている場合のみ実際に保存し、そうでなければ無変更の
  まま既存を返す」というガード (`if not (len(playlist.tracks) > len(found[0].tracks)):
  return found[0]`) を掛けている不具合。ListenBrainz の週次推薦プレイリストは曲数が
  ほぼ固定 (Weekly Jams/Weekly Exploration ともに毎週50曲) のまま中身(曲)だけ総入れ替え
  される運用のため、2週目以降この条件がほぼ常に偽になり、`frontend.py` の
  `import_playlists()` (`_schedule_playlists_import()` が `threading.Timer` で毎週自動実行)
  が新しい週の曲データを渡しても `save()` は一切反映せず1週目に保存されたプレイリストを
  無条件でそのまま返し続ける。呼び出し元はこの戻り値が非Noneであることしか見ておらず、
  ログ上は「保存成功」として扱われ例外もエラーログも一切出ないまま、rmpc/mopidy 側に
  見えるプレイリストの中身は実質的に初回保存時点の曲順のまま恒久的に凍結される
  (ListenBrainz本家では毎週更新されているにもかかわらず気付く手立てが無いサイレントな
  機能不全)。TODO/既知の残課題を全項目消化済みの自走エージェントが新規発見・追加した項目。
  verified: lbplaylistrefresh-patch.py。「曲数が増えているか」ではなく「曲構成(URI列、
  順序込み)が前回保存時と実際に変わっているか」で判定するよう変更 (`new_uris == old_uris`
  なら無変更のまま返す)。元実装の「無駄な再保存を避ける」という意図 (コメント
  "return unchanged playlist for recommendations whose track list isn't increasing" から
  読み取れる、完全に同一の内容を毎週律儀に上書きし続けて `playlist_changed` 相当のイベントを
  空振りさせない配慮) はそのまま維持しつつ、曲数据え置き/減少の更新を一律で握り潰していた
  本体のバグだけを解消。パッチ適用後の生成ソースは一時コピーに `chmod +w` した上で
  `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix` の `listenbrainzPatched` に `lbartistnameguard-patch.py` の
  直後に登録しビルド成功、生成ソースに新実装が反映されていることを確認。ListenBrainz は
  dev環境では認証情報(secrets)が無く `enabled = false` のため実アカウントでの実機起動確認は
  できないが (lbplaylistguard-patch.py 等の既存LB系パッチと同じ制約)、代わりに
  **オフライン単体テスト**でバグの再現とその解消の両方を実証: `ListenbrainzPlaylistsProvider`
  を直接構築し、`create()` で recommendation playlist を用意した上で `save()` を連続呼び出し —
  **パッチ前**(lbplaylistrefresh-patch.py 未適用の旧env)では、week1(50曲, a:0..a:49)保存後に
  week2(同じ50曲だが中身を b:0..b:49 に総入れ替え)を `save()` しても `lookup()` の中身が
  week1 のまま凍結される (バグ再現)、続けて week3(49曲に減少)を `save()` しても反映されない
  (バグ再現) ことを確認。**パッチ後**は同じ入力シーケンスで week2/week3 とも正しく反映される
  ことを確認、かつ week3 と全く同一内容の week4 を再度 `save()` した場合は元実装の意図通り
  無変更のまま返る(無駄な再保存を避ける最適化が維持されている)ことも確認。非recommendation
  プレイリスト (通常の `import_playlists()` が作るプレイリスト等) は従来通り曲数減少でも
  無条件で `save()` される既存動作に回帰が無いことも確認。続けてパッチ済みenvで
  dev mopidy(6601) を実際に起動し、MPD で `ping`/`status` が正常応答し
  mopidy.log に Traceback/ERROR 0件 (`listenbrainz` は設定通り `Disabled extensions` に
  含まれるのみ) であることを確認、ビルド・起動の無回帰を確認した。
- [x] `mopidy_mpd/protocol/current_playlist.py` の `plchangesposid {VERSION}` が、VERSION に
  現在の tracklist version より「大きい」(未来の、まだ実際には割り振られていない) 値を
  渡された場合にも「キュー全曲が変更された」として全件 (cpos/Id) を返してしまう不具合。
  兄弟コマンド `plchanges {VERSION}` (同ファイル) は
  `if version < tracklist_version: ... elif version == tracklist_version: ... else: return`
  という3分岐で、未来のバージョンでは明確に「何も返さない (変更なし)」を返すのに対し、
  `plchangesposid` は元々 `if int(version) != context.core.tracklist.get_version().get():`
  という `!=` 一発の判定しか無く、"未来のバージョン" もこの条件を満たしてしまうため、
  `plchanges` なら空応答になるのと全く同じ入力に対して `plchangesposid` だけキュー全曲を
  返すという矛盾があった。実 MPD 本体 (musicpd.org protocol、GitHub
  MusicPlayerDaemon/MPD の queue まわりの実装は曲ごとの実更新バージョンとの比較のため
  未来バージョン入力に対しては常に「変更なし」) の挙動とも異なる。TODO/既知の残課題を
  全項目消化済みの自走エージェントが新規発見・追加した項目。
  verified: mpdplchangesposidfuture-patch.py。`plchangesposid` の判定を元の `!=` から
  `plchanges` と同じ `version < tracklist_version` へ変更 (`plchangesposid` には
  `plchanges` のメタデータ更新分岐に相当する概念が無いため、version == / > の両方を
  「変更なし」で統一)。パッチ適用後の生成ソースは一時コピーに `chmod +w` した上で
  `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix` の `mpdPatched` に `mpdplaylistrenameguard-patch.py` の直後に
  登録しビルド成功、生成ソースに新実装が反映されていることを確認した上で dev mopidy(6601,
  ytmusic実アカウント) を実際に起動しMPDで実機確認 —
  (1) **パッチ前** (旧env) で `search any "yoasobi"` の結果 (`ytmusic:track:by4SYYWlhEs`)
  を `add`、`status` で現在の `playlist:` (version) を取得しその +999999 を「未来の
  バージョン」として `plchangesposid "<future>"` を送ると `cpos: 0` / `Id: 1` が返り
  バグを実機再現。(2) **パッチ後** (新env) で全く同じ手順を再実行すると
  `plchangesposid "<future>"` は `OK` のみ (空応答) となりバグが解消されたことを確認。
  (3) 同じパッチ後envで `plchanges "<future>"` も従来通り `OK` のみ (回帰なし)、
  `plchangesposid "0"` (過去のバージョン) は従来通り `cpos: 0` / `Id: 1` を返す
  (正常系の回帰なし) ことを確認。(4) 各コマンド実行後も `status` が正常応答しセッションが
  切断されないことを確認。(5) dev mopidy の起動ログ (mopidy.log) に Traceback/ERROR が
  無く、ビルド・起動の無回帰を確認した。
- [x] `mopidy_mpd/protocol/music_db.py` の `list {TYPE} [FILTER] group {GROUPTYPE}...` が、
  主タグ (TYPE) 自身または既に指定済みの group と重複するタグを再度 `group` に渡された
  場合 (例: `list album group album`、`list artist group artist group artist`) にも
  一切検証せず、`_mpd_list_grouped` (mpdlist-patch.py/mpdlistwindow-patch.py由来) が
  同じフィールドの distinct 値の階層をもう一段そのまま再帰してしまい、`Album: X` のような
  行が意味もなく重複して返る不具合 (エラーにならず、件数も値も静かに壊れたレスポンスに
  なる)。TODO/既知の残課題を全項目消化済みの自走エージェントが実 MPD 本体
  (MusicPlayerDaemon/MPD src/command/DatabaseCommands.cxx handle_list) を実際に
  `gh api`/`gh search code` で fetch してソースを確認し新規発見・追加した項目。
  verified: mpdlistgroupconflict-patch.py。実 MPD の該当ロジック (handle_list の group
  ループ内、実ソースで確認):
  ```
  if (group == tagType ||
      std::find(tag_types.begin(), tag_types.end(), group) != tag_types.end()) {
      r.Error(ACK_ERROR_ARG, "Conflicting group");
      return CommandResult::ERROR;
  }
  ```
  つまり実 MPD は group タグが主タグ (tagType) と同じ、または既に集めた group 列に既出の
  場合は即座に `ACK [2@0] {list} Conflicting group` で拒否し1行も返さない。この判定を
  移植: `_mpd_extract_group_params` 内で group 列同士の重複を検出 (`field in groups`)
  して `MpdArgError("Conflicting group")` (error_code=ACK_ERROR_ARG=2、実MPDと同じ
  エラーコード) を送出し、`list_()` 側で主タグ (`field`) と group 列との重複も同様に
  チェック。`count`/`searchcount` は実MPDにそもそも主タグ(TYPE)の概念が無く
  (`handle_count_internal` はgroupが1個のみでこのガード自体が存在しない) このチェックの
  対象外だが、`_mpd_extract_group_params` はcount/searchcountとも共有しているため
  group列同士の重複検出だけは自然と横展開される (意味のある差分なし、無意味な重複
  groupを弾くだけで既存の正常系には影響しない)。パッチ適用後の生成ソースは一時コピーに
  `chmod +w` した上で `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix` の `mpdPatched` に `mpdplchangesposidfuture-patch.py` の
  直後に登録しビルド成功、生成ソースに新実装 (`Conflicting group` の2箇所) が反映されて
  いることを確認した上で dev mopidy(6601, ytmusic実アカウント) を実際に起動しMPDで
  実機確認 — `list album group album`(主タグと同一) → `ACK [2@0] {list} Conflicting
  group`、`list artist group artist group artist`(group列同士で重複) →同じくACK、
  `list artist group artist`(2引数のみの重複) → 同ACK。回帰なし確認:
  `list album group albumartist`/`list album group artist`/`list artist group album`
  (すべて非重複の正常な組み合わせ) → いずれも `OK` で正常応答、`list album`(groupなし)/
  `count group artist` も従来通り `OK`。各ACK後も同一接続で送った `status` が正常応答し
  セッションが切断されないことを確認。`search any "yoasobi"`(実データ2曲+アルバム1件)の
  回帰なしも確認。mopidy.log に Traceback/ERROR 0件、ビルド・起動の無回帰を確認した。
- [x] `mopidy_ytmusic/playlist.py` の `YTMusicPlaylistsProvider.save()` (ytplaylistdup-patch.py
  適用後の版) が、曲追加 `self.backend.api.add_playlist_items()` の戻り値を一切確認せず
  常に成功扱いする不具合。TODO/既知の残課題を全項目消化済みの自走エージェントが
  Explore/general-purposeサブエージェントに新規発見を委任し、`ytmusicapi/mixins/
  playlists.py` の `add_playlist_items()` 実装 (`if "status" in response and
  "SUCCEEDED" in response["status"]: ... else: return response`) を実際に読んで
  発見・追加した項目 (create_playlist()の同種の曖昧戻り値問題も併せて調査したが
  今回のBACKLOG追加は影響範囲がより明確なadd側のみ、create側は別途調査の余地あり)。
  実害: `duplicates=False` (呼び出し側は明示指定しておらずこの既定値のまま) で
  追加先プレイリストに既に同じ videoId がある「重複」とみなされた場合や、その他の
  非例外系サーバーエラーで、ytmusicapi は例外を投げず生レスポンス (`"status"` に
  `"SUCCEEDED"` を含まない) をそのまま返す。`save()` はこれを見ず
  `result.get("playlistEditResults", [])`(失敗時は通常空)をzipするだけで
  `currentOrder += addList` を無条件実行するため、実際には1曲も追加されていないのに
  以後の並べ替え判断材料 (`currentOrder`/`setVideoIdByVideoId`) が「追加成功した」
  前提で汚染される。`playlistadd`/`save` はYouTube Music側が無変更のままMPD
  クライアントへ `OK` を返してしまう「サイレントなデータ欠落」になる。
  verified: ytaddresultcheck-patch.py。ytmusicapi自身が成功判定に使っているのと
  同一の条件 (`isinstance(result, dict) and "SUCCEEDED" in str(result.get("status",
  ""))`) を呼び出し側でも確認し、成功時のみ `setVideoIdByVideoId`/`currentOrder` を
  更新するよう変更 (失敗時は他の失敗系統と同じくログのみ残し例外は投げない、
  `save()` の「ベストエフォートで進める」既存方針を踏襲)。パッチ適用後の生成ソースは
  一時コピーに`chmod +w`した上で`ast.parse`で構文確認、2回適用しても冪等
  (スキップ)であることを確認。`nix/lib/mopidy-env.nix`の`ytmusicPatched`に
  `ytuploadalbumlookup-patch.py`の直後として登録しビルド成功、生成ソースに新実装
  (`add_playlist_items for playlist`ログを含む分岐)が反映されていることを確認。
  実機検証: dev mopidy(6601, ytmusic実アカウント)を実際に起動し、`search any
  "yoasobi"`で実データ取得→`add`でキューへ2回投入→`save NAME`、および
  `playlistadd NAME URI`を2回実行、いずれも`OK`で正常応答し`listplaylist`が
  重複込みの期待通りの内容を返すこと・`status`/`tagtypes`/`close`が正常応答し
  セッションが切断されないことを確認 (このテストアカウントは`create_playlist`が
  既知のHTTP 401書き込み権限不足でm3uへ静かにフォールバックするため、これらの
  実機テストはm3uバックエンド経由の回帰確認に留まり、YTM `add_playlist_items()`
  自体の失敗分岐は実アカウントでは強制できなかった。`listplaylists`で確認した
  ところこのアカウントは保存済みYTMプレイリストが0件で、既存プレイリストを使った
  代替experimentも不可能だった)。このため**オフライン単体テスト**
  (lbnetguard-patch.py/lbtokennetguard-patch.py と同じ手法)でバグの再現と
  修正の両方を実証: ビルド済みenvから抽出した`playlist.py`のパッチ前後2版を
  それぞれ独立した`mopidy_ytmusic`パッケージとして`importlib`でロードし、
  `object.__new__`で`__init__`をバイパスした`YTMusicPlaylistsProvider`に対し
  `add_playlist_items()`が非SUCCEEDEDの生レスポンス(`{"actions": [...]}`、
  `"status"`キー無し)を返す`FakeApi`を注入、`_reorder_playlist()`をスパイに
  差し替えて`save()`(目的順序が同一videoIdを2つ含むプレイリスト、既存
  `pls["tracks"]=[]`)を呼び出したところ、**パッチ前**の生成ソースでは
  `currentOrder`に実際には追加されていない`[VIDEO, VIDEO]`が計上される
  (バグ再現)ことを確認、**パッチ後**は同じ入力で`currentOrder`が空のまま
  (追加失敗が正しく反映される)ことを確認した。mopidy.log の ERROR 3件は
  いずれも今回のテスト操作自体に起因する既知の事象 (前述の`create_playlist`
  401×2件、および意図的に送った不正videoId `zzzzzzzzzzz` の
  `library.py`側`KeyError: 'videoDetails'`×1件、いずれも本パッチの対象外の
  既存挙動) のみで新規リグレッションではないことを確認した。
- [x] `mopidy_mpd/protocol/__init__.py` の共有レンジパーサ `protocol.RANGE()`
  が `START:END` の `START == END` (実MPD仕様 `RangeArg.hxx IsWellFormed()`
  = `start <= end` で明記されるwell-formedな空範囲、例: `delete "0:0"`) を
  一律 `ValueError("End must be larger than start")` にしてしまい、`delete`/
  `move`/`shuffle`/`playlistinfo`/`prio`/`listplaylist`/`listplaylistinfo`/
  `load`/`playlistdelete`/`playlistmove` の全コマンドで `START:END` の両端が
  一致するだけの正当な(0件を指す)呼び出しが `ACK incorrect arguments` に
  なってしまう不具合。TODO全項目消化済みのため自走エージェントが
  mopidy_mpdの共有ヘルパー層 (`RANGE()`は既存の`mpddeleteboundary-patch.py`/
  `mpdprioboundary-patch.py`が対象にした「開区間が境界に一致するケース」とは
  別の、パース自体が失敗する未修正のコードパス) を再調査して新規発見。
  verified: mpdrangeempty-patch.py。`RANGE()`の`start >= stop`判定を
  `start > stop`へ緩和 (`start == stop`はパース成功しslice(start,start)へ)。
  ただしこれだけでは済まないことをソースリーディングで確認: (1)
  `move_range()`が呼ぶ`mopidy/core/tracklist.py`の`move(start,end,...)`は
  `start==end`のとき独自に`end += 1`する特殊扱いを持ち(mopidy core自体は
  パッチ対象外)、RANGE()緩和だけだと`move "0:0" N`が「0曲移動」ではなく
  「position 0の曲を1曲だけ動かす」というACKで拒否されていた状態より悪化した
  サイレントな誤動作に化ける。(2) `shuffle()`が呼ぶ
  `tracklist.shuffle(start,end)`も`start>=end`で独自にAssertionErrorを送出し
  (同じくcore側でパッチ対象外)、緩和後は`shuffle "0:0"`が`except
  AssertionError`経由で`ACK Bad song index`になってしまう。この2箇所には
  `start==end`のときcore呼び出し自体をskipしno-opで直接returnするガードを
  追加(TO解決/検証自体は従来通り行い、実際にcore.tracklist.move()を呼ぶ
  直前だけでskip)。他の対象コマンド(`delete`/`playlistinfo`/`prio`/
  `listplaylist`/`listplaylistinfo`/`playlistdelete`/`playlistmove`)は素の
  Pythonリストスライス(`list[start:end]`)や既存の空リストチェック
  (mpddeleteboundary-patch.py/mpdprioboundary-patch.py)だけで`start==end`を
  正しくno-op扱いできることをソースを読んで確認し、変更不要と判断した。
  パッチ適用後の生成ソースは一時コピーに`chmod +w`した上で`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることを確認。
  `nix/lib/mopidy-env.nix`の`mpdPatched`に`mpdlistgroupconflict-patch.py`の
  直後として登録しビルド成功、生成ソースに新実装(`start > stop`/
  `if start == end: return`×2箇所)が反映されていることを確認した上で
  dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  (1)空キューで`playlistinfo "0:0"`/`delete "0:0"`/`move "0:0" 0`/
  `shuffle "0:0"`のいずれも`OK`(旧実装なら全て`ACK incorrect arguments`)。
  (2)`findadd "(any contains 'yoasobi')"`で実データ2曲をキューへ投入した上で
  `move "0:0" 1`を実行し直後の`playlistinfo`で曲順が完全に不変であることを
  確認(=`move()`のcore呼び出し自体がskipされ、core側の`end+=1`特殊挙動による
  「1曲だけ誤って動く」サイレントバグが起きていないことを実証)。(3)本物の
  逆順レンジ`move "1:0" 0`/`shuffle "5:3"`/`delete "5:3"`(`start > stop`、
  真に不正)が引き続き`ACK [2@0] {...} incorrect arguments`となり回帰なしを
  確認。(4)通常の非空レンジ`move "0:1" 1`が2曲を正しく入れ替え、直後の
  `status`が正常応答することを確認。mopidy起動ログはクリーンでERRORなし。
- [x] `mopidy_ytmusic/playlist.py` の `YTMusicPlaylistsProvider.create()` が
  `self.backend.api.create_playlist()` の戻り値を「truthy かどうか」だけで成功判定し
  ており、失敗時に返る生レスポンス dict (非空なので常に truthy) を playlistId 文字列
  と誤認して壊れた URI を持つ「作成成功したように見える」`Playlist` を返してしまう
  不具合。ytaddresultcheck-patch.py (`save()` の `add_playlist_items()` 戻り値未検証
  バグ、既知の残課題側の直前のエントリ) の verified コメント中で自走エージェント自身が
  「`create_playlist()`の同種の曖昧戻り値問題も併せて調査したが今回のBACKLOG追加は
  影響範囲がより明確なadd側のみ、create側は別途調査の余地あり」と残していたフォロー
  アップを、TODO/既知の残課題を全項目消化済みの自走エージェントが実際に着手し発見・
  追加した項目。`ytmusicapi/mixins/playlists.py` の `create_playlist()` を実際に読んで
  確認したところ、末尾が `return response["playlistId"] if "playlistId" in response
  else response` であり、成功時のみ `str` (playlistId) を返し、失敗時 (タイトルの
  無効文字以外の理由、例えばサーバーエラーやクォータ超過等で応答に `playlistId` が
  無い場合) は例外を投げず生レスポンスの `dict` をそのまま返すことを確認 (add側と全く
  同じ設計の「戻り値の型で成功/失敗を表す」API)。呼び出し側の `create()` は
  `if bId:` という truthy 判定のみで、非空 dict も通過してしまうため
  `uri = f"ytmusic:playlist:{bId}"` で dict の repr を含む壊れた URI を持つ Playlist を
  返してしまう。MPD の `save`/`searchaddpl` (`mopidy.core.playlists.create()` 経由) は
  これを「作成成功」として扱い後続の `save()` 処理へ進むため、実際には YouTube Music
  側にプレイリストが作られていないにもかかわらず `OK` が返り、後続の URI 解決や
  lookup が壊れた bId で静かに失敗し続ける「サイレントなデータ欠落」になる。
  verified: ytcreateplaylistcheck-patch.py。`create_playlist()` の成功判定を
  `isinstance(bId, str) and bId` に変更 (失敗時の dict は明示的に弾く)。パッチ適用後の
  生成ソースは一時コピーに `chmod u+w` した上で `ast.parse` で構文確認、2回適用しても
  冪等 (スキップ) であることも確認。`nix/lib/mopidy-env.nix` の `ytmusicPatched` に
  `ytaddresultcheck-patch.py` の直後として登録しビルド成功。
  **実機検証**: dev mopidy(6601, ytmusic実アカウント) を実際に起動し MPD で
  `save "AutoAgentTestPL"` → `OK`・`listplaylists` に反映・`rm` で後始末、`status`/
  `tagtypes`/`listplaylists` の回帰なしを確認 (このテストアカウントは既知の
  `create_playlist` HTTP 401 書き込み権限不足があり、`save` は ytmusic 側を経由せず
  m3u バックエンドで完結したため、mopidy.log に `YTMusic playlist creation` 系ログは
  出ず、この実機経路だけでは非例外の dict 失敗分岐を強制できなかった。
  ytaddresultcheck-patch.pyの`add_playlist_items()`検証時と同じ制約)。このため
  **オフライン単体テスト**(同patchの検証時と同じ手法)でバグの再現と修正の両方を
  実証: パッチ前後2版の `playlist.py` をそれぞれ独立パッケージとして `importlib` で
  ロードし、`object.__new__` で `__init__` をバイパスした `YTMusicPlaylistsProvider` に
  対し `create_playlist()` が非文字列の生レスポンス dict
  (`{"error": "SERVER_ERROR", "reason": "quota exceeded"}`、例外なし) を返す
  `FakeApi` を注入して `create("MyPlaylist")` を呼び出したところ、**パッチ前**の
  生成ソースでは dict が truthy 判定を通過し
  `uri="ytmusic:playlist:{'error': 'SERVER_ERROR', ...}"` という壊れた URI を持つ
  `Playlist` が返る (バグ再現)ことを確認、**パッチ後**は同じ入力で `None` が返る
  (失敗として正しく検知される)ことを確認した。成功系 (`create_playlist()` が
  `str` を返す) と例外系 (ネットワークエラー等) は両バージョンで従来通り
  (成功時は正しい URI の Playlist、例外時は `None`) であることも同テストで確認し
  回帰がないことを実証した。dev mopidy 起動時・上記実機コマンド実行中とも
  mopidy.log に Traceback/ERROR 0件を確認した。
- [x] `mopidy_ytmusic/playlist.py` の `YTMusicPlaylistsProvider.save()`
  (ytaddresultcheck-patch.py/ytcreateplaylistcheck-patch.py 適用後の版) が、曲削除
  `self.backend.api.remove_playlist_items()` の戻り値を一切確認せず常に成功扱いする
  不具合。TODO/既知の残課題を全項目消化済みの自走エージェントが、ytaddresultcheck-patch.py
  の verified コメントで add 側のみを対象にしていたことを踏まえ、直後の
  `remove_playlist_items()` 呼び出しにも同種の未検証が残っていることに気付き、
  `ytmusicapi/mixins/playlists.py` の `remove_playlist_items()` を実際に読んで
  発見・追加した項目。
  実害: `remove_playlist_items()` は末尾が `return response["status"] if "status" in
  response else response` であり、成功時のみ `"status"` 文字列 (`"STATUS_SUCCEEDED"`
  等) を返す一方、アプリケーションレベルの失敗 (並行編集による setVideoId 失効や
  サーバーエラー等) では例外を投げず `"status"` キーの無い生レスポンス dict を
  そのまま返す (`add_playlist_items()` と対をなす設計だが、成功/失敗を表す型自体が
  str/dict で異なる点が相違)。呼び出し側の `save()` はこれを見ず
  `self.backend.api.remove_playlist_items(bId, videos)` の直後に無条件で
  `setVideoIdByVideoId.pop(t["videoId"], None)` を実行するため、実際には
  YouTube Music 側で曲が削除されていないのに以後の追跡情報から該当エントリが
  消えてしまう「サイレントなデータ不整合」になる (`playlistdelete`/`playlistmove`/
  `rename` 経由の `save()` で発生しうる。次回の `listplaylistinfo` で消えたはずの
  曲が残り続ける)。
  verified: ytremoveresultcheck-patch.py。ytaddresultcheck-patch.py と同じ流儀で、
  `remove_playlist_items()` の戻り値を確認し、成功時 (`isinstance(result, str) and
  "SUCCEEDED" in result`) のみ `setVideoIdByVideoId` から該当エントリを削除、失敗時は
  (他の失敗系統と同じく) `logger.error` でログのみ残し例外は投げない
  (`save()` の「ベストエフォートで進める」既存方針を踏襲)。パッチ適用後の生成ソースは
  一時コピーに `chmod u+w` した上で `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。`nix/lib/mopidy-env.nix` の `ytmusicPatched` に
  `ytcreateplaylistcheck-patch.py` の直後として登録しビルド成功、生成ソースに
  新実装 (`remove_playlist_items for playlist` ログを含む分岐) が反映されていることを
  確認した。
  **実機検証**: dev mopidy(6601, ytmusic実アカウント) を実際に起動し MPD で
  `clear`→`findadd "(any contains 'yoasobi')"`(実データ2曲投入)→
  `save "AutoAgentTestPL2"` → `OK`・`listplaylists`/`listplaylist` に反映・`rm` で
  後始末、`status`/`tagtypes`/`close` の回帰なしを確認 (このテストアカウントは
  ytaddresultcheck-patch.py/ytcreateplaylistcheck-patch.py 検証時と同じ既知の
  `create_playlist` HTTP 401 書き込み権限不足があり `save` は m3u バックエンド
  経由で完結するため、この実機経路だけでは YTM `remove_playlist_items()` 自体の
  失敗分岐は強制できなかった)。このため**オフライン単体テスト**(同じ2パッチの
  検証時と同じ手法) でバグの再現と修正の両方を実証: パッチ前後2版の `playlist.py`
  をそれぞれ独立パッケージとして読み込み、`object.__new__` で `__init__` を
  バイパスした `YTMusicPlaylistsProvider` に対し `remove_playlist_items()` が
  例外を投げず `"status"` キーの無い生レスポンス dict (`{"actions": [...]}`) を
  返す `FakeApi` を注入し、2曲(`AAA`/`BBB`)のうち `BBB` を除去する `save()` を
  呼び出したところ、**パッチ前**の生成ソースでは `BBB` が
  `setVideoIdByVideoId` から消えてしまう (実際には YTM 側に残っているにも
  関わらず「削除成功した」前提で追跡情報が汚染される、バグ再現) ことを確認、
  **パッチ後**は同じ入力で `BBB` が `setVideoIdByVideoId` に正しく残り続ける
  (失敗が検知され誤って追跡を消さない) ことを確認した。成功系
  (`remove_playlist_items()` が `"STATUS_SUCCEEDED"` を返す) も両バージョンで
  従来通り `BBB` が正しく削除される (回帰なし) ことを同テストで確認した。
  dev mopidy 起動時・上記実機コマンド実行中とも mopidy.log に
  Traceback/ERROR 0件 (既知の `create_playlist` 401 を除く) を確認した。
- [x] `mopidy_ytmusic/playlist.py` の `YTMusicPlaylistsProvider.save()`
  (ytaddresultcheck-patch.py/ytcreateplaylistcheck-patch.py/ytremoveresultcheck-patch.py
  適用後の版) が、リネーム時の `self.backend.api.edit_playlist(bId, title=...)` と、
  `_reorder_playlist()` 内の並べ替え時の `self.backend.api.edit_playlist(bId,
  moveItem=...)` の戻り値をどちらも一切確認せず常に成功扱いする不具合。TODO/既知の
  残課題を全項目消化済みの自走エージェントが、ytremoveresultcheck-patch.py の
  verified コメントで「add/remove 側は対応済みだが同じ save() 内で使われる
  edit_playlist() はまだ未検証」であることに気付き、`ytmusicapi/mixins/playlists.py`
  の `edit_playlist()` を実際に読んで発見・追加した項目。
  実害: `edit_playlist()` は末尾が `return response["status"] if "status" in response
  else response` であり、add/remove_playlist_items() と全く同じ設計 (成功時のみ
  "SUCCEEDED" を含む str、失敗時は例外を投げず "status" キーの無い生レスポンス dict)。
  (1) リネーム側: 戻り値を一切見ず、失敗しても `save()` は無条件に新タイトルの
  `Playlist` を返すため、実際には YouTube Music 側のタイトルが変わっていないのに
  「リネーム成功」として扱われるサイレントな不整合になる。(2) 並べ替え側
  (`_reorder_playlist`): 戻り値を見ずに例外が出なければ即座に内部追跡状態
  `working` を「moveItem 成功」の前提で更新するため、実際には失敗しているのに
  `working` を進めてしまうと、ループは末尾側から処理するため以後の moveItem 呼び出しが
  誤った現在順序を前提に setVideoId ペアを算出することになり、1回の失敗が以後の
  全呼び出しへ連鎖的に伝播し曲順が壊れ続ける可能性がある (add/remove 側と同種の
  「戻り値未検証によるサイレントなデータ不整合」だが、こちらは内部状態の破損が
  後続処理に連鎖する点がより深刻)。
  verified: ytplaylisteditcheck-patch.py。ytremoveresultcheck-patch.py と同じ流儀で、
  `edit_playlist()` の戻り値を確認し、(1) リネーム失敗時は他の失敗系統と同じく
  `logger.error` でログのみ残し例外は投げない (save() 全体の「ベストエフォートで
  進める」既存方針を踏襲)、(2) 並べ替え失敗時は例外時と同じく直ちに `return` して
  `working` の更新も後続の moveItem 呼び出しも行わない (誤った前提での連鎖破壊を
  防ぐ) よう修正。パッチ適用後の生成ソースは一時コピーに `chmod u+w` した上で
  `ast.parse` で構文確認、2回適用しても冪等 (スキップ) であることも確認。
  `nix/lib/mopidy-env.nix` の `ytmusicPatched` に `ytremoveresultcheck-patch.py` の
  直後として登録しビルド成功、生成ソースに新実装 (`edit_playlist (rename)`/
  `edit_playlist (moveItem)` ログ分岐) が反映されていることを確認した。
  **実機検証**: dev mopidy(6601, ytmusic実アカウント) を実際に起動し MPD で
  `clear`→`findadd "(any contains 'yoasobi')"`(実データ2曲投入)→
  `save "AutoAgentEditCheckTest"`→`OK`・`listplaylists`に反映→
  `rename "AutoAgentEditCheckTest" "AutoAgentEditCheckTest2"`→`OK`・`listplaylists`で
  新名のみ表示・`listplaylistinfo`でフル情報維持→`rm`で後始末、`status`/`tagtypes`/
  `search any "yoasobi"`の回帰なしを確認 (このテストアカウントは既知の
  `create_playlist` HTTP 401 書き込み権限不足があり、`save`/`rename`はytmusic側を
  経由せずm3uバックエンドで完結したため、mopidy.logに`edit_playlist`系ログは出ず、
  この実機経路だけでは非例外の失敗分岐を強制できなかった。既存2パッチ検証時と
  同じ制約)。このため**オフライン単体テスト**(同じ2パッチの検証時と同じ手法)で
  バグの再現と修正の両方を実証: パッチ前後2版の`playlist.py`をそれぞれ独立パッケージ
  として`importlib`でロードし、`object.__new__`で`__init__`をバイパスした
  `YTMusicPlaylistsProvider`に対し`edit_playlist()`が例外を投げず失敗dict
  (`"status"`キー無し)を返す`FakeApi`を注入して検証 —
  **(1)リネーム失敗**: `save()`呼び出し後、**パッチ前**はエラーログ0件で無音のまま
  「成功したはず」の新タイトルの`Playlist`を返す(バグ再現)、**パッチ後**は同じ入力で
  `edit_playlist (rename) ... did not succeed`のエラーログが出力される(失敗が
  検知される、戻り値自体は既存方針通りベストエフォートで`playlist`のまま)ことを
  確認。**(2)並べ替えの連鎖失敗**: 現在順序`[A,B,C]`→目的順序`[C,B,A]`
  (2回のmoveItemが必要な構成)で1回目のmoveItemが失敗dictを返すよう設定した
  ところ、**パッチ前**は1回目の失敗を無視して`working`を進め2回目のmoveItemも
  実行してしまう(誤った前提での連鎖、バグ再現)ことを確認、**パッチ後**は1回目の
  失敗で直ちに`return`し2回目のmoveItemが呼ばれない(連鎖を阻止)ことを確認した。
  **回帰確認**: 同じ構成で両moveItemが成功する正常系では、パッチ前後とも
  moveItem呼び出し回数が2回で完全に一致(回帰なし)することも同テストで確認した。
  dev mopidy起動時・上記実機コマンド実行中とも mopidy.log に Traceback/ERROR
  0件(既知の`create_playlist` 401を除く)を確認した。
- [x] `mopidy_ytmusic/playlist.py` の `YTMusicPlaylistsProvider.delete()`
  (ytcreateplaylistcheck-patch.py/ytremoveresultcheck-patch.py/ytplaylisteditcheck-patch.py
  適用後の版) が、`self.backend.api.delete_playlist()` の戻り値を一切確認せず、
  例外が出なければ常に成功 (`True`) 扱いする不具合。TODO/既知の残課題を全項目
  消化済みの自走エージェントが、直前3件の save()/create() 側の戻り値未検証修正
  (add/remove/edit_playlist) を踏まえ、同じ playlist.py 内に残る `delete_playlist()`
  だけが未対応であることに気付き、`ytmusicapi/mixins/playlists.py` の
  `delete_playlist()` を実際に読んで発見・追加した項目。
  実害: `delete_playlist()` は末尾が `return response["status"] if "status" in
  response else response` であり、create_playlist()/remove_playlist_items() と
  全く同じ設計 (成功時のみ "SUCCEEDED" を含む str、アプリレベルの失敗時は例外を
  投げず "status" キーの無い生レスポンス dict)。呼び出し側の `delete()` は戻り値を
  完全に無視し `self.backend.api.delete_playlist(bId); return True` としているため、
  実際には YouTube Music 側で削除が失敗していても常に `True` を返す。mopidy core の
  `Playlists.delete()` はこれを見て `playlist_deleted` イベントを発火し、
  mopidy_mpd の `rm` コマンド (`if not context.core.playlists.delete(uri).get():
  raise MpdSystemError`) も `OK` を返してしまうため、rmpc 等のクライアントは
  実際には YTM 側に残っているプレイリストを「削除成功した」と誤認して自分の
  一覧から消してしまい、次回同期時に「削除したはずのプレイリストが復活する」
  サイレントなデータ不整合になる (add/remove/edit 側と同型の一連のバグの最後の
  1箇所)。
  verified: ytdeleteplaylistcheck-patch.py。ytremoveresultcheck-patch.py/
  ytcreateplaylistcheck-patch.py と同じ流儀で、`delete_playlist()` の戻り値を
  ytmusicapi 自身の型 (`isinstance(result, str) and "SUCCEEDED" in result`) で
  確認し、成功時のみ `True`、失敗時は `logger.error` を残して `False` を返す
  (既存の例外系の戻り値仕様と統一)。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` した上で `ast.parse` で構文確認、2回適用しても冪等 (スキップ)
  であることも確認。`nix/lib/mopidy-env.nix` の `ytmusicPatched` に
  `ytplaylisteditcheck-patch.py` の直後として登録しビルド成功、生成ソースに
  新実装が反映されていることを確認した。
  **実機検証**: dev mopidy(6601, ytmusic実アカウント) を実際に起動し MPD で
  `clear`→`findadd "(any contains 'yoasobi')"`(実データ2曲投入)→
  `save "AutoAgentDeleteCheckTest"`→`OK`・`listplaylists`に反映→
  `rm "AutoAgentDeleteCheckTest"`→`OK`・`listplaylists`から消滅、`status`/
  `tagtypes`の回帰なしを確認 (このテストアカウントは既知の`create_playlist`
  HTTP 401書き込み権限不足があり`save`はytmusic側を経由せずm3uバックエンドで
  完結するため、この実機経路だけでは`delete_playlist()`自体の非例外失敗分岐は
  強制できなかった。既存4パッチ検証時と同じ制約)。このため**オフライン単体
  テスト**(同じ手法) でバグの再現と修正の両方を実証: パッチ前後2版の
  `playlist.py`をそれぞれ独立パッケージとして読み込み、`object.__new__`で
  `__init__`をバイパスした`YTMusicPlaylistsProvider`に対し`delete_playlist()`が
  例外を投げず`"status"`キー無しの生レスポンス`{"error": "SERVER_ERROR",
  "reason": "quota exceeded"}`を返す`FakeApi`を注入して`delete()`を呼び出した
  ところ、**パッチ前**は`True`を返す(実際には削除されていないのに成功扱い、
  バグ再現)ことを確認、**パッチ後**は同じ入力で`False`を返す(失敗が正しく
  検知される)ことを確認した。**回帰確認**: `delete_playlist()`が
  `"STATUS_SUCCEEDED"`を返す成功系では、パッチ前後とも`True`を返すことが
  完全に一致することも同テストで確認した。dev mopidy起動時・上記実機コマンド
  実行中とも mopidy.log に Traceback/ERROR 0件(既知の`create_playlist` 401を
  除く)を確認した。
- [x] `mopidy_mpd/protocol/command_list.py` の `command_list_end()` が
  `idle`/`noidle`/`albumart`/`readpicture`/ネストした`command_list_begin`/
  `command_list_ok_begin` を list 内実行から守るガード
  (mpdcmdlistnest-patch.py/mpdcmdlistidle-patch.py/mpdalbumartcmdlist-patch.py)
  自体が、コマンド名抽出に `command.split(" ", 1)[0]` という素のスペース区切り
  を使っており、タブ区切りのコマンド行だとすり抜けてしまう不具合。TODO/既知の
  残課題を全項目消化済みの自走エージェントが、上記3パッチが共通で使っている
  この1行を実際のトークナイザ (`mopidy_mpd/tokenize.py`) の `WORD_RE`
  (`(?:\s+|$)` = スペース・タブいずれの空白の連続も区切りとして受理、と
  docstring にも明記) と突き合わせて再監査し発見・追加した項目。
  実際に確認: `"idle\tdatabase".split(" ", 1)[0] == "idle\tdatabase"`
  (guardの `in (...)` 判定にマッチせずすり抜ける) が
  `tokenize.split("idle\tdatabase") == ["idle", "database"]`
  (本物のハンドラは正しく `idle` として呼ばれる)。つまり
  `command_list_begin` / `idle\tdatabase`(スペースでなくタブ区切り) /
  `command_list_end` を送ると else 節に落ち、
  `context.dispatcher.handle_request("idle\tdatabase", ...)` 経由で本物の
  idle ハンドラが list 内で実際に実行されてしまい、mpdcmdlistidle-patch.py が
  修正したのと全く同じ実害 (`context.subscriptions`/`self.command_list_index`
  汚染 → `command_list_end` への OK 応答が黙って握り潰される →
  以後そのコネクションは「idle 中」に固着し、次にクライアントが何を送っても
  `_idle_filter` が ACK すら返さず即座に TCP 接続を切断) が、タブ区切りという
  別経路から再現する (albumart/readpicture・ネストした command_list_begin も
  同型ですり抜ける)。
  verified: mpdcmdlisttabsplit-patch.py。`command.split(" ", 1)[0]` を
  `re.split(r"\s+", command, 1)[0]` に置き換え (スペース区切り・空白なし・
  空文字列いずれも元の `str.split(" ", 1)[0]` と同じ結果を返すため純粋な
  追加防御で回帰なし)。パッチ適用後の生成ソースは一時コピーに当てて
  `ast.parse` で構文確認、2回適用しても冪等 (スキップ) であることも確認。
  `nix/lib/mopidy-env.nix` に mpdalbumartcmdlist-patch.py の直後として登録し
  ビルド成功、生成ソースに `import re`/新実装が反映されていることを確認した。
  **バグの実機再現**: パッチ適用前の env (同一ビルド設定、dev mopidy 6601) を
  実際に起動し生ソケットで `command_list_begin`/`idle\tdatabase`/
  `command_list_end` を送信 — `command_list_end` への応答が一切返らずタイム
  アウト、続けて同一コネクションで `status` を送ると応答無しでコネクションが
  サーバー側から切断される (`recv()` が空バイト列で connection closed) ことを
  実機で確認 (mpdcmdlistidle-patch.py の描写通りの実害を実際に再現)。
  **修正後の実機検証**: パッチ適用後の dev mopidy(6601, ytmusic実アカウント)
  を実際に起動し MPD で確認 — 同じ `command_list_begin`/`idle\tdatabase`/
  `command_list_end` → `ACK [1@0] {idle} not allowed in a command list`
  (list処理を即座に打ち切り)・続く同一コネクションでの `status` も正常応答
  (接続生存、旧実装ならここで切断されていた)。同様にタブ区切りの
  ネスト `command_list_begin\tfoo` → `ACK [5@0] {} unknown command
  "command_list_begin"`・タブ区切りの `albumart\tfoo` → `ACK [1@0] {albumart}
  not allowed in a command list`、いずれも続く `status` 応答・接続生存を確認。
  旧来のスペース区切り `command_list_begin`/`status`/`tagtypes`/
  `command_list_end` (通常の command list) も無変更で正常応答することを確認、
  スペース区切りの通常の `idle`/`noidle` (list外) も無変更で正常応答、
  実データでの `search any "yoasobi"` の回帰なしも確認。mopidy起動時・上記
  実機コマンド実行中とも mopidy.log に Traceback/ERROR 0件を確認した。
- [x] `mopidy_mpd/dispatcher.py` の `MpdDispatcher._authenticate_filter()` が、
  パスワード認証有効時 (mopidy.conf の `[mpd] password` 設定時) に未認証コマンド
  かどうかを判定するコマンド名抽出で `request.split(" ")[0]` という素のスペース
  区切りを使っており、直前に mpdcmdlisttabsplit-patch.py で修正した
  `command_list.py` の `command.split(" ", 1)[0]` と全く同じ「タブ区切りで
  ガードをすり抜ける」不具合。TODO/既知の残課題を全項目消化済みの自走エージェント
  が、その修正パターンを実トークナイザ (`mopidy_mpd/tokenize.py` の `WORD_RE`、
  スペース・タブいずれの空白も区切りとして受理) と突き合わせ、`dispatcher.py`
  内に同じ `split(" ")` パターンがもう1箇所 (`_authenticate_filter` のこの1行の
  み) 残っていることを `grep` で再監査し発見・追加した項目。
  実害: パスワード認証が有効な構成で、未認証の接続が (仕様上合法な) タブ区切り
  で `password\tXXX` を送ると、`command_name` が `"password\tXXX"` という未知の
  トークン扱いになり `protocol.commands.handlers.get(command_name)` が `None` を
  返すため `auth_required=False` の判定に到達できず、常に
  `MpdPermissionError` (`ACK ... you don't have permission for ...`) で拒否
  される。`close`/`ping`/`commands`/`notcommands` 等の他の認証不要コマンドも
  同じ経路ですり抜けを阻害される。つまりパスワード認証設定時、タブ区切りで
  コマンドを送るクライアントは認証コマンド自体を通せず永久に未認証のまま拒否
  され続ける (このリポジトリの現行 dev/実機設定はパスワード未設定のため通常運用
  では到達しないパスだが、mopidy_mpd の `password` コマンド自体はコード上明確な
  不整合であり、パスワードを設定した検証環境を用意すれば即座に再現・修正確認
  できる)。
  verified: mpdauthtabsplit-patch.py。mpdcmdlisttabsplit-patch.py と同じ流儀で
  `request.split(" ")[0]` を `re.split(r"\s+", request, 1)[0]` に置き換え
  (スペース区切り・空白なし・空文字列いずれも元の `str.split(" ")[0]` と同じ
  結果を返すため純粋な追加防御で回帰なし。`dispatcher.py` は既に `import re`
  済みのため import 追加は不要)。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` した上で `ast.parse` で構文確認、2回適用しても冪等 (スキップ)
  であることも確認。`nix/lib/mopidy-env.nix` に mpdcmdlisttabsplit-patch.py の
  直後として登録しビルド成功、生成ソースに新実装が反映されていることを確認した。
  **実機検証**: `~/ai/mopidy-dev/mopidy-dev.conf` に一時的に
  `[mpd] password = authtabtest` を追加した検証用設定で dev mopidy(6601) を
  実際に起動し、パッチ適用前後のenvを両方ビルドして比較 —
  **パッチ前**: 生ソケットで `password\tauthtabtest`(タブ区切り) を送ると
  `ACK [4@0] {passwordauthtabtest} you don't have permission for
  "passwordauthtabtest"` となり認証が通らず (バグ再現)、続く `status` も
  同様に `ACK ... you don't have permission for "status"` で拒否される
  (未認証のまま固着) ことを確認。一方スペース区切りの `password authtabtest`
  は従来通り `OK` となり認証できることも確認 (回帰起点の確認)。
  **パッチ後**: 同じ `password\tauthtabtest`(タブ区切り) → `OK`・続く
  `status` も正常な全フィールド応答 (認証成功、修正確認)。誤ったタブ区切り
  パスワード `password\twrongpass` → `ACK [3@0] {password} incorrect
  password` (本物のパスワード検証ハンドラに正しく到達しつつ不一致を正しく
  検出、認証バイパスなし)。未認証のままタブ区切りで認証必須コマンドを送る
  `status\tfoo` → 引き続き `ACK ... you don't have permission for "status"`
  (認証必須コマンドのガード自体に回帰なし、素通りするようになったわけではない
  ことを確認)。スペース区切りの `password authtabtest`→`status` の従来経路も
  無変更で正常動作 (回帰なし)。**通常デプロイでの回帰確認**: 検証用の
  `password` 設定を除去した既定の dev.conf (パスワード未設定) でパッチ後の
  env を再起動し、`status`/`tagtypes` が無認証で従来通り正常応答することを
  確認 (このリポジトリの実運用パスに影響がないことを確認)。mopidy起動時・
  上記実機コマンド実行中とも mopidy.log に Traceback/ERROR 0件を確認した。
- [x] `mopidy_listenbrainz/playlists.py` の `ListenbrainzPlaylistsProvider.get_items()` が、
  `mopidy.backend.PlaylistsProvider.get_items()` の契約 ("Returns a list of `Ref` objects
  referring to the playlist's items") に反し、プレイリスト内の曲 (`Ref.track`) ではなく
  マッチしたプレイリスト自身 (`Ref.playlist`) をそのまま返してしまう不具合。TODO/既知の
  軽微な残課題を全項目消化済みのため自走エージェントが、直前の一連の tab区切りガード
  監査 (mpdcmdlisttabsplit-patch.py/mpdauthtabsplit-patch.py) に続けて mopidy_mpd 側の
  再監査では新規発見が尽きたため、これまであまり調査されていなかった
  `mopidy_listenbrainz` (lb-patch.py 系列、既に9パッチ適用済み) の未監査メソッドを
  横断的に洗い出す中で発見・追加した項目。原因: `get_items()` の
  `found = [p for p in self.playlists if p.uri == uri]` (uri一致、高々1件) に対し
  `return [Ref.playlist(uri=p.uri, name=p.name) for p in found]` としており、
  `found[0].tracks` (実際の曲一覧) を一切参照していない。対の
  `mopidy_ytmusic.playlist.YTMusicPlaylistsProvider.get_items()` が
  `[Ref.track(uri=t.uri, name=t.name) for t in tracks]` と正しく実装しているのと対比して
  発見した。実害: `core.playlists.get_items(uri)` は Mopidy-HTTP の JSON-RPC 経由で
  任意のクライアント (本プロジェクトも `[http] enabled=true`、127.0.0.1:6681) から
  呼び出し可能な公開 API。ListenBrainz の recommendation プレイリスト
  (frontend.py の `import_playlists()` が作成する
  `listenbrainz:playlist:recommendation:...`) に対しこれを呼ぶと、期待される
  「プレイリスト内の曲一覧」ではなく「そのプレイリスト自身を指す1件の Ref
  (type が `track` ではなく `playlist`)」が返り、クライアント側はプレイリストの中身を
  一切取得できないサイレントな機能不全となる。rmpc は MPD プロトコルのみ
  (`_get_playlist()` 経由の `core.playlists.lookup()`) を使い `get_items()` 自体を
  呼ばないため rmpc からは到達しないが、HTTP-JSONRPC 経由の一般的な mopidy クライアント
  (Iris 等) には実害あるギャップ。
  verified: lbgetitems-patch.py。`found[0].tracks` を `Ref.track` として返すよう、
  `mopidy_ytmusic` の `get_items()` と同じ形へ修正。パッチ適用後の生成ソースは一時コピーに
  当てて `ast.parse` で構文確認、2回適用しても冪等 (スキップ) であることも確認。
  `nix/lib/mopidy-env.nix` の `listenbrainzPatched` に `lbplaylistrefresh-patch.py` の
  直後として登録しビルド成功、生成ソースに新実装が反映されていることを確認した。
  **実機検証**: dev mopidy(6601, ytmusic実アカウント) を、検証用に一時的に
  `[listenbrainz] enabled = true`(ダミートークン)を追加した設定で起動 (トークンが
  無効なため `ListenbrainzFrontend` 自体は起動時に `RuntimeError` でクラッシュするが、
  `ListenbrainzBackend`/`ListenbrainzPlaylistsProvider` はフロントエンドと独立に
  正常起動し、`create()`/`save()` は元々ネットワーク呼び出しを一切行わないローカル
  操作のため、フロントエンド無しでも本バグの再現・検証には支障ないことを確認した
  上で採用)。HTTP-JSONRPC (127.0.0.1:6681) を実際に叩いて確認 —
  `core.playlists.create(name="listenbrainz:playlist:test1",
  uri_scheme="listenbrainz")` → `Playlist` 作成、`core.playlists.save(...)` で
  ダミー2曲 (`local:track:fakeA.mp3`/`fakeB.mp3`) を設定、
  **パッチ前の旧env**を実際に起動し同じ手順で `core.playlists.get_items(uri=
  "listenbrainz:playlist:test1")` を呼ぶと `[{"type": "playlist", "uri":
  "listenbrainz:playlist:test1", ...}]` (プレイリスト自身1件、曲は0件) というバグを
  実機で再現確認、**パッチ後**の同じ手順では `[{"type": "track", "uri":
  "local:track:fakeA.mp3", ...}, {"type": "track", "uri": "local:track:fakeB.mp3",
  ...}]` (曲2件が正しく反映) となることを確認した。検証後は dev.conf の
  `[listenbrainz]` を `enabled = false` (このリポジトリの既定の dev 設定) へ戻し
  再起動、MPD で `status`/`tagtypes`/`search any "yoasobi"`(実データ3件ヒット)の
  回帰なし・mopidy.log に Traceback/ERROR 0件 (検証用の無効ダミートークンによる
  `ListenbrainzFrontend` の既知のクラッシュを除く、これは検証時のみ意図的に投入した
  設定であり本パッチとは無関係) を確認した。
- [x] `mopidy_mpd/protocol/mount.py` の `mount {PATH} {URI}` ハンドラが、
  `translator.mount_path_used(path)` (busyチェック) → `translator.mount_uri_used(uri)`
  (URI重複チェック) → `translator.mount_add(path, uri)` (追加) という3回の**別々**の
  translator.py呼び出しで構成されており、複合操作全体としてはアトミックでない不具合。
  TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが Explore サブエージェントに
  未パッチ・薄くしか監査されていない領域の横断調査を委任し新規発見した項目。
  `mpdmountrace-patch.py` が `mount_path_used`/`mount_uri_used`/`mount_add`/`mount_list`
  各関数個別に `_mount_lock` (`threading.RLock`) を掛け、dict走査中の `RuntimeError`
  によるセッション切断は解消済みだったが、`mpdpartitionrace-patch.py` が
  `delpartition` について実質的に着手した「複合状態操作は単一ロックスコープで
  アトミックに」という同種の対策が `mount()` ハンドラには及んでいなかった。
  実害: `_mounts` は mount.py のコメント通り session 単位ではなく実MPD仕様通り
  サーバー全体で共有されるため、2接続がほぼ同時に同じ mount point を異なる URI で
  `mount foo nfs://host-a/x` / `mount foo smb://host-b/y` すると、両方が
  (別々にロックを取る) `mount_path_used("foo")` を呼んだ時点ではまだどちらも
  `_mounts` に書き込んでいないため両方とも `False` を観測して "Mount point busy" を
  通過し、両方とも最終的に `mount_add()` を実行してしまう。後勝ちで片方のURIが
  黙って上書きされ、先に `mount` した側は `OK` を受け取ったにもかかわらず
  `listmounts` では自分が指定したURIが跡形もなく消えている
  (実MPDが保証する「mount pointの排他性」が破れ、クライアントに気付かれないまま
  異なるストレージがマウントされる)。同じ理由で `mount_uri_used(uri)`
  (同一URIの二重マウント禁止チェック) も複合操作の外にあるため同時実行下では
  効果が保証されない。
  verified: mpdmounttoctou-patch.py。`translator.py` に `mount_try_add(path, uri)`
  を新設し、busyチェック・URI重複チェック・追加を単一の `_mount_lock` スコープ内で
  アトミックに実行するよう変更 (path/uriの静的フォーマット検証は共有状態を参照
  しないためロック外のまま維持し、元のエラー文言・優先順位を保持)。パッチ適用後の
  生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。`nix/lib/mopidy-env.nix` の `mpdPatched` リスト末尾
  (`mpdrangeempty-patch.py` の直後) に登録しビルド成功、生成ソースに
  `mount_try_add` が反映されていることを確認した。
  **実機検証 (決定的再現テスト)**: まずユニットレベルで、パッチ適用前の
  `translator.py` を実際に import し、旧 `mount()` ハンドラと全く同じ非アトミックな
  3手順 (`mount_path_used` → `mount_uri_used` → `mount_add`、間に
  `threading.Barrier` で確定的にギャップを挿入) を2スレッドから同じ mount point
  `"racepoint"` に異なるURI (`nfs://host-1/x` / `nfs://host-2/x`) で並行実行 —
  **パッチ前**: 2スレッドとも `"OK"` を返す一方 `_mounts` の最終状態は
  `{"racepoint": "nfs://host-1/x"}` のみ (host-2側のURIがOK応答にもかかわらず
  サイレントに失われることを実証)。**パッチ後**: 新設の `mount_try_add()` を同じ
  バリア方式で50スレッド同時実行しても常に `OK` はちょうど1件・残り49件は
  `"busy"` に収束し `_mounts` も1件のみ残ることを確認 (アトミック性の実証)。
  続けて dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、20並列の生ソケット
  接続から `threading.Barrier` で同期させ同じ mount point へ実際に MPD プロトコルで
  `mount race nfs://host-N/path` を同時送信するテストも実施 — `OK` 1件・
  `ACK [2@0] {mount} Mount point busy` 19件に収束し `listmounts` も1件のみ反映
  されることを確認 (自然発生的な黒箱テストでは競合窓が短くレース自体は毎回発生
  しなかったため、上記ユニットレベルの決定的再現テストが本修正の効力の主証跡)。
  既存動作の回帰なし確認: 単一クライアントでの `mount`→`OK`、同一pathへの再
  `mount`→`ACK [2@0] {mount} Mount point busy`、同一uriを別pathへ`mount`→
  `ACK [2@0] {mount} This storage is already mounted`、`unmount`→`OK`、
  空path `mount "" nfs://x/y`→`ACK [2@0] {mount} Bad mount point`、`"://"`を
  含まないuri `mount badtest notaurl`→`ACK [2@0] {mount} Unrecognized storage
  URI` のいずれも既存のエラー文言・優先順位のまま回帰なし。`status`/`tagtypes`/
  `search any "yoasobi"`(実データ複数件ヒット)含め mopidy.log に
  Traceback/ERROR 0件を確認した。
- [x] `rangeid {ID} {START:END}` (mpdrangeid-patch.py が追加) の独自パーサ
  `_mpd_parse_time_range()` に非有限値の TIME (`rangeid 1 "0:nan"` /
  `rangeid 1 "0:inf"` 等) を渡すと、`float()` 変換自体は成功するものの
  (`try/except ValueError` はこの2行のみを囲んでいる)、後段の
  `round(start * 1000), round(end * 1000)` が `round(float("nan"))` で素の
  `ValueError`、`round(float("inf"))`/`round(float("-inf"))` で素の
  `OverflowError` を送出し、いずれも捕捉されずMPDセッションが問答無用で
  切断されてしまう不具合 (サーバ本体は生存、当該コネクションのみ切断)。
  mpdfloatnonfinite-patch.py が `seek`/`seekid`/`seekcur` の共有バリデータ
  `protocol.FLOAT`/`UFLOAT` に対して同種のバグを既に修正していたが、
  `rangeid` はこの共有バリデータを経由しない独自パーサのため対象から
  漏れていた。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが
  Explore サブエージェントに未パッチ・薄くしか監査されていない領域
  (network.py/session.py/dispatcher.py/exceptions.py/actor.py/
  protocol/connection.py/reflection.py/tagtype_list.py/playback.py/status.py/
  stored_playlists.py/stickers.py の既存パッチ未対象部分等) の横断調査を委任し
  新規発見した項目。
  verified: mpdrangeidnonfinite-patch.py。`_mpd_parse_time_range()` の
  `float()` 変換直後 (try ブロック内) に `math.isfinite(start) and
  math.isfinite(end)` の検査を追加し、非有限なら他の不正値と同じ
  `ACK Bad range` に変換するよう修正 (mpdfloatnonfinite-patch.py が
  `protocol.FLOAT`/`UFLOAT` に加えた `math.isfinite()` チェックと同じ発想を、
  共有バリデータを経由しないこの独自パーサにも横展開)。isfinite チェック後の
  `start`/`end` は常に有限のため以後の `round()` は安全になる。パッチ適用後の
  生成ソースは一時コピー (nixストアからのコピーは読み取り専用のため
  `chmod u+w` してから適用) に当てて `ast.parse` で構文確認、2回適用しても
  冪等 (スキップ) であることも確認。`nix/lib/mopidy-env.nix` の `mpdPatched`
  リスト末尾 (`mpdmounttoctou-patch.py` の直後) に登録しビルド成功、生成ソースに
  `math.isfinite` が反映されていることを確認した。
  **実機検証**: dev mopidy(6601, ytmusic実アカウント) を実際に起動し、
  `search any "yoasobi"` でヒットした実トラック (`ytmusic:track:by4SYYWlhEs`)
  を `addid` でキューへ追加 (Id: 1) した上で MPD を実際に叩いて確認 —
  `rangeid "1" "0:nan"` → `ACK [2@0] {rangeid} Bad range` となりセッション
  切断されず続く `status` も正常応答 (`playlistlength: 1` 等、旧実装なら
  ここで素の `ValueError` によりコネクションが切断されていた)、
  `rangeid "1" "0:inf"` → 同様に `ACK [2@0] {rangeid} Bad range` (旧実装なら
  `OverflowError` で切断)、`rangeid "1" "-inf:5"`/`rangeid "1" "nan:"`
  (start側が非有限のケース) も同様に `ACK [2@0] {rangeid} Bad range` で
  切断されないことを確認。回帰なし確認: `rangeid "1" "0:5"` (有効な数値) →
  `OK`、続く `playlistid "1"` で `Range: 0.000-5.000` が正しく反映、
  `rangeid "1" "abc:5"` (既存の非数値エラー) → 引き続き
  `ACK [2@0] {rangeid} Bad range`、`rangeid "1" "5"` (コロン無し) →
  引き続き `ACK [2@0] {rangeid} Bad range`、`rangeid "1" ":"`
  (レンジ解除) → `OK`、以後の `tagtypes`/`search any "yoasobi"`
  (実データ複数件ヒット) の回帰なしを確認。mopidy.log に Traceback/ERROR
  0件を確認した。
- [x] `sticker inc`/`sticker dec` (mpdstickernames-patch.py が追加した
  `_mpd_sticker_inc_dec()`) が VALUE を `int(value)` で手動パースしており、Python の
  `int` は任意精度のため桁数が極端に多い値 (例: `99999999999999999999999999999999`)
  でも `ValueError` にならず成功する。しかしその後 sqlite3 へバインドパラメータとして
  渡す際、SQLite の `INTEGER` 列は 64bit 符号付き整数までしか扱えず、範囲外だと
  `sqlite3` モジュールが素の `OverflowError` ("Python int too large to convert to
  SQLite INTEGER") を送出する。呼び出し元の `sticker()`/`dispatcher.py`/`session.py`
  のいずれも `MpdAckError` 系以外の生例外を捕捉しないため、この `OverflowError` が
  未捕捉のままMPDセッションが問答無用で切断されてしまう不具合 (サーバ本体は生存、
  当該コネクションのみ切断)。`mpdfloatnonfinite-patch.py`/`mpdrangeidnonfinite-patch.py`
  が同種の「手動パースの生例外が未捕捉のままセッション切断を招く」パターンを
  `float()`/`round()` 系 (`seek`/`seekcur`/`rangeid`) で既に修正していたが、対象は
  `sticker inc`/`dec` の `int(value)` 起因の `OverflowError` には未着手だった。
  TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが general-purpose
  サブエージェントに未パッチ・薄くしか監査されていない領域 (音楽DB/キュー/
  プレイリスト/ステータス/stickers/playback 等の大型ファイルの未パッチ関数群、
  mopidy_ytmusic/mopidy_listenbrainz含む) の横断調査を委任し新規発見した項目。
  verified: mpdstickerincoverflow-patch.py。`int(value)` によるパース成功後、
  `sqlite3` の `INTEGER` が扱える範囲 (`-(2**63) <= delta < 2**63`) に収まるかを
  事前検査し、外れていれば非数値の場合と同じ `exceptions.MpdArgError("invalid
  sticker value: {value}")` に変換 (`ON CONFLICT ... DO UPDATE` によるSQL実行前に
  弾くため、SQLite側へは常に安全な範囲の値のみ渡る)。パッチ適用後の生成ソースは
  一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等 (スキップ) である
  ことも確認。`nix/lib/mopidy-env.nix` の `mpdPatched` リスト末尾
  (`mpdrangeidnonfinite-patch.py` の直後) に登録しビルド成功、生成ソースに
  `-(2**63) <= delta < 2**63` が反映されていることを確認した。
  **実機検証**: dev mopidy (6601) を実際に起動し MPD を実際に叩いて確認 —
  `sticker set song "dummy:overflowtest" "counter" "1"` → `OK` で下準備した上で、
  (1) `sticker inc song "dummy:overflowtest" "counter"
  "99999999999999999999999999999999"` (桁数極端に多い値) →
  `ACK [2@0] {sticker} invalid sticker value: ...` となりセッション切断されず、
  続く `status` も正常応答 (旧実装ならここで素の `OverflowError` によりコネクションが
  切断されていた)。(2) 境界値確認: `sticker set ... "counter" "0"` →
  `sticker inc ... "counter" "9223372036854775807"` (int64最大値、範囲内)
  → `OK`、`sticker get` で正しく反映を確認。(3) `9223372036854775808`
  (最大値+1、範囲外の最小のケース) → 同様に `ACK [2@0] {sticker} invalid sticker
  value: ...` で切断されないことを確認。(4) `sticker dec` 側でも同じ極端な値で
  同様に `ACK` となり切断されないことを確認。回帰なし確認: 既存の非数値エラー
  (`sticker inc ... "counter" "abc"` → 引き続き `ACK [2@0] {sticker} invalid
  sticker value: abc`)、範囲内の通常の `sticker inc ... "counter" "5"` → `OK`
  で正しく加算反映、`sticker delete` によるクリーンアップも `OK` で回帰なしを
  確認した。mopidy.log に Traceback/OverflowError 0件を確認した。
- [x] `mopidy_ytmusic.library.py` の `search()` の `"uri"` 分岐 (ytsearchuri-patch.py が
  `lookup()` への委譲へ書き換え済み) が `uri = query["uri"][0]` と無条件にインデックス
  アクセスしており、`query["uri"]` が空リストの場合 `IndexError` (`LookupError` の
  サブクラス) を送出する不具合。TODO/既知の軽微な残課題を全項目消化済みのため
  自走エージェントが Explore サブエージェントに未パッチ・薄くしか監査されていない
  領域の横断調査を委任し新規発見した項目 (mopidy_mpd の主要ハンドラは既存189パッチで
  極めて堅牢化済みと判定されたため mopidy_ytmusic 側へ焦点を移した調査結果)。
  `mopidy.core.LibraryController.search()` は `validation.check_query()` で
  query の値を検証するが、`_check_iterable()` は空リストを正当な値として通過させる
  (文字列でもイテレータでもない通常のリストのため `ValidationError` にならない)。
  さらに `core/library.py` の `search()` 自身が
  `reraise = (TypeError, LookupError)` を `_backend_error_handling()` に渡し、
  一般 `Exception` の握り潰しから `TypeError` と `LookupError` (`IndexError` 含む)
  を意図的に除外している (呼び出し側で「exact引数非対応」検出用に `TypeError` だけを
  捕捉する設計だが、`LookupError` 側を呼び出し元で捕捉していない)。結果として
  `core.library.search()` を `{"uri": []}` で呼ぶと mopidy_ytmusic 側の
  `IndexError` が握り潰されずに呼び出し元まで伝播する。MPD テキストプロトコル自身の
  `find file ""`/`search filename ""` は `mopidy_mpd/protocol/music_db.py` の
  `_query_from_mpd_search_parameters()` が `value.strip()` が真の値のみを query に
  積むため空リストを作れず影響を受けないが、mopidy-http が公開する HTTP JSON-RPC
  (`core.library.search` メソッドへ `{"query": {"uri": []}}` を直接渡す呼び出し)
  からは到達可能 (lbgetitems-patch.py 等がこれまでも前提としてきた「HTTP JSON-RPC も
  正当な入力面」の同じ経路、このリポジトリの dev/検証環境自身も
  HTTP-JSONRPC=127.0.0.1:6681 を標準の検証手段として提供している)。JSON-RPC
  ディスパッチャ自体は例外を `JsonRpcApplicationError` に変換し mopidy プロセス自体は
  生存する (MPD セッション切断系のバグ群より実害は小さい) が、本来穏当なエラーで
  済むべきところ生の `IndexError` のトレースバックが漏れてしまう。
  verified: ytsearchuriempty-patch.py。他の分岐 (対象外URIスキーム) と同じ
  「対象外なら None を返す」という既存の設計に合わせ、`query["uri"]` が空なら
  `[0]` へアクセスする前に `None` を返すガードを追加。パッチ適用後の生成ソースは
  一時コピーに当てて ytsearchuri-patch.py → ytsearchuriempty-patch.py の順で適用し
  `ast.parse` で構文確認、2回適用しても冪等 (スキップ) であることも確認。
  `nix/lib/mopidy-env.nix` の `ytmusicPatched` リストの `ytsearchuri-patch.py` 直後
  (`ytsearchgenre-patch.py` の直前) に登録しビルド成功、生成ソースにガードが
  反映されていることを確認した。
  **実機検証 (決定的再現テスト、fix前後比較)**: まず `nix/lib/mopidy-env.nix` から
  本パッチの登録行のみ一時的に外してビルドし dev mopidy(6601/HTTP-JSONRPC 6681,
  ytmusic 実アカウント) を起動、HTTP JSON-RPC で実際に
  `{"method": "core.library.search", "params": {"query": {"uri": []}}}` を送信して
  **fix前**: `{"error": {"code": 0, "message": "Application error", "data":
  {"type": "IndexError", "message": "list index out of range", "traceback":
  "...mopidy_ytmusic/library.py\", line 846, in search\n    uri =
  query[\"uri\"][0]\n ... IndexError: list index out of range\n"}}}` という
  生例外の伝播を実機で再現・確認した。続けて登録行を復元してビルドし直し
  (同じ dev mopidy を再起動)、**fix後**: 同じリクエストが
  `{"jsonrpc": "2.0", "id": 1, "result": []}` と穏当な空結果に変わることを確認した。
  回帰なし確認: `core.library.search` に `{"any": ["yoasobi"]}` (実データ複数件
  ヒット) → 引き続き正常な `SearchResult` を返す、MPD `find file
  "ytmusic:track:by4SYYWlhEs"` (実トラックの既知URI、ytsearchuri-patch.py が
  対応させた lookup() 委譲経路) → 引き続き `Title: 夜に駆ける` 等の正しい情報を
  返す、`core.library.search` に `{"uri": ["file:///nonexistent"]}`
  (ytmusic以外のスキーム、対象外の既存 else 分岐) → 引き続き `result: []`、
  MPD `status`/`tagtypes` の回帰なしを確認した。mopidy.log に
  Traceback/ERROR 0件 (fix前の意図的な再現テスト時を除く) を確認した。
- [x] `mixrampdelay {SECONDS}` (mpdmixramp-patch.py が実装、引数バリデータは
  `protocol.FLOAT`) の docstring 自身が明記する通り、MPD仕様では `"nan"` は
  「MixRampを無効化してクロスフェードへフォールバックする」ための正当な特殊値
  であり、`translator.py` の初期値も `float("nan")` になっている。ところが
  後発の `mpdfloatnonfinite-patch.py` (seek/seekid/seekcurがnan/infで素の
  ValueError/OverflowErrorを送出しMPDセッションを切断する不具合対策) が
  共有バリデータ `protocol.FLOAT`/`UFLOAT` 自体に `math.isfinite()` チェックを
  追加した際、同じ `protocol.FLOAT` を使う `mixrampdelay` の引数バリデータも
  無差別に巻き込まれ、`mixrampdelay "nan"` を送ると `ACK [2@0] {mixrampdelay}
  incorrect arguments` になってしまう回帰が生じていた。一度でも
  `mixrampdelay 5` のような数値を設定したセッションは、プロトコル経由で
  二度と "nan" (無効化状態) へ戻せなくなる実害あるギャップ。TODO/既知の軽微な
  残課題を全項目消化済みのため自走エージェントが Explore サブエージェントに
  未パッチ・薄くしか監査されていない領域 (playback.py/connection.py/
  network.py/status.py/translator.py/dispatcher.py、mopidy_ytmusic・
  mopidy_listenbrainzのlibrary.py以外のファイル) の横断調査を委任し新規発見
  した項目 (既存パッチ同士の相互作用による回帰、という新しいパターン)。
  verified: mpdmixrampdelaynan-patch.py。mixrampdelay専用の緩和版バリデータ
  `protocol.FLOAT_ALLOW_NAN` を新設し nan のみ明示的に許容 (inf/-inf は
  実MPD仕様上も意味を持たないため引き続き拒否)、`mixrampdelay` の引数
  バリデータをこれに差し替え。seek/seekid/seekcur が依存する
  `protocol.FLOAT`/`UFLOAT` 自体は無変更 (他のnan/inf切断修正への副作用を
  避けるため mixrampdelay だけ個別バリデータへ分離)。パッチ適用後の生成
  ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。`nix/lib/mopidy-env.nix` の `mpdPatched`
  リスト末尾 (`mpdstickerincoverflow-patch.py` の直後) に登録しビルド成功。
  dev mopidy(6601) を実際に起動し MPD で確認 — `mixrampdelay "nan"` → `OK`、
  `status` に `mixrampdelay` フィールドが出ない (仕様通り無効状態)、
  `mixrampdelay "5"` → `OK`・`status` → `mixrampdelay: 5.0`、再度
  `mixrampdelay "nan"` → `OK`・`status` から `mixrampdelay` フィールドが消滅
  (無効化状態への復帰、fix前は同じ操作が `ACK incorrect arguments` になり
  復帰不能だった)。回帰なし確認: `mixrampdelay "inf"`/`mixrampdelay "abc"` →
  引き続き `ACK [2@0] {mixrampdelay} incorrect arguments`、`seekcur "inf"` →
  引き続き `ACK [2@0] {seekcur} incorrect arguments` (mpdfloatnonfinite-patch
  の既存修正に副作用なし)、`mixrampdb "-17"` → `OK`・`status` →
  `mixrampdb: -17.0`、`tagtypes`/`search any "yoasobi"` (実データ複数件
  ヒット)/`list album`/`crossfade "10"`・`status` の `xfade: 10` も回帰なし
  を確認した。mopidy.log に Traceback/ERROR 0件を確認した。
- [x] `mopidy_mpd/protocol/stickers.py` の sticker get/set/delete/list/find/inc/dec/
  stickernames/stickernamestypes は、コマンド呼び出しごとに `sqlite3.connect()` で
  新規接続を開き共有ファイル `<data_dir>/mpd/sticker.db` へ直接 execute()/commit() する。
  volume/output/partition/channel/mount/uri_mapper 等の他の共有可変状態はプロセス内 Lock
  で直列化されているのに対し、sticker.db への書き込みは複数クライアントが独立した
  sqlite3 接続で同時にアクセスするため SQLite 自身のファイルロック競合が起こりうる。
  この場合 sqlite3 モジュールは `sqlite3.OperationalError: database is locked` を素で
  送出するが、`dispatcher.py` の `_catch_mpd_ack_errors_filter`/`_call_handler_filter` は
  `exceptions.MpdAckError`/`pykka.ActorDeadError` しか捕捉しないため、この生例外は
  未捕捉のまま当該クライアントの MPD セッションが無警告で切断されてしまう
  (サーバ本体は生存、当該コネクションのみ切断)。TODO/既知の軽微な残課題を全項目
  消化済みのため自走エージェントが Explore サブエージェントに未パッチ・薄くしか
  監査されていない領域の横断調査を委任し新規発見した項目 (mpdstickerincoverflow-patch.py
  の OverflowError 修正と同種の「sqlite3 起因の生例外が未捕捉」パターンだが、原因は
  int の桁数ではなく複数クライアント同時書き込みによるファイルロック競合)。
  verified: mpdstickersqlerr-patch.py。mopidy_mpd/protocol/playback.py や
  audio_output.py が volume/output操作の失敗を `exceptions.MpdSystemError(...)` に
  変換している既存の慣行に倣い、DB へアクセスする8つのヘルパー関数
  (_mpd_sticker_list/get/set/delete/find_ext/names/namestypes/inc_dec) を新設した
  デコレータ `_mpd_sticker_guard` でラップし、`sqlite3.Error` を
  `exceptions.MpdSystemError("sticker database error: ...")` (ACK_ERROR_SYSTEM=52) へ
  変換。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用
  しても冪等 (スキップ) であることも確認。`nix/lib/mopidy-env.nix` の `mpdPatched`
  リストの `mpdstickerincoverflow-patch.py` 直後に登録しビルド成功。
  **実機検証 (決定的再現テスト、fix前後比較)**: sticker.db の実パス
  (`<data_dir>/mpd/sticker.db`) に対し、MPDとは別のPythonプロセスから生の sqlite3
  接続で `BEGIN IMMEDIATE` により書き込みロックを20秒間保持し続けるスクリプトを用意。
  まず `nix/lib/mopidy-env.nix` から本パッチの登録行のみ一時的に外してビルドし
  dev mopidy(6601, ytmusic 実アカウント) を起動、ロック保持中に MPD で
  `sticker set song "ytmusic:track:contended4" k "v"` を送信したところ、**fix前**:
  約13.8秒後にレスポンスが空 (`b''`) となり接続が切断され (続く`status`も空応答で
  接続死亡を確認)、mopidy.log に
  `sqlite3.OperationalError: database is locked` の生Tracebackが
  `mopidy_mpd/protocol/stickers.py", line 72, in _mpd_sticker_set` から発生している
  ことを確認した。続けて登録行を復元してビルドし直し(同じ dev mopidy を再起動)、
  同じロック保持+`sticker set song "ytmusic:track:contended5" k "v"` の再現手順で
  **fix後**: 約14.5秒後に接続を維持したまま
  `ACK [52@0] {sticker} sticker database error: database is locked` を受信し、続けて
  送った `status` にも正常応答があり接続が生存していることを確認した (fix前は同じ
  操作で接続が切断されていた)。回帰なし確認: `sticker set/get/inc/find/delete`・
  `stickernames`/`stickertypes`/`stickernamestypes` の通常操作 (ロック競合なし) が
  引き続き正常応答、`tagtypes`/`status`/`search any "yoasobi"` (実データ複数件ヒット)
  も回帰なしを確認した。mopidy.log に Traceback/ERROR 0件 (fix前の意図的な再現
  テスト時を除く) を確認した。
- [x] `mopidy_mpd/protocol/stored_playlists.py` の `playlistadd`/`playlistclear`/
  `playlistdelete`/`playlistmove`/`rename`/`save` が、いずれも「`_get_playlist()`で
  ストアドプレイリストの現在の内容を読む → ローカルで加工 → `context.core.playlists.save()`
  (または`create()`+`delete()`) で書き戻す」という read-modify-write を、一切のロック
  無しで行っている件。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  Explore サブエージェントに未パッチ・薄くしか監査されていない領域
  (playback.py/connection.py/network.py/status.py/translator.py/dispatcher.py、
  mopidy_ytmusic・mopidy_listenbrainzのlibrary.py以外のファイル) の横断調査を委任し
  新規発見した項目。2接続がほぼ同時に同じストアドプレイリストへ`playlistadd`等を
  送ると、両方が同じ「変更前」の内容を読み、後勝ちの`save()`が先行クライアントの
  変更を踏み潰す(lost update)。特に`mopidy_ytmusic.playlist.YTMusicPlaylistsProvider.save()`
  (library.pyではなくplaylist.py)は「渡された`playlist.tracks`を目的状態とし、
  save()呼び出し時点でYTM側から改めて取得した実際の現在状態との`Counter`差分だけを
  add/remove APIへ送る」設計のため、後勝ちのsave()は自分が読んだ古い状態を目的状態
  として渡してしまい、その時点で実際にYTM側に存在する(先行クライアントが追加した)
  曲はnewCountsに含まれずremoveCountsに回って**実際にYouTube Music側から削除される**。
  両方の`playlistadd`ともクライアントにはOKが返っており、ACKエラーは一切出ない
  サイレントなデータ消失 (既存の一連のplaylist.py戻り値未検証系パッチ
  (ytaddresultcheck-patch.py等) とは異なる、read-modify-write自体のTOCTOU)。
  verified: mpdplaylisteditrace-patch.py。mpdvolumerace-patch.py/
  mpdoutputtogglerace-patch.pyと同じ流儀でstored_playlists.pyにモジュールレベルの
  `threading.Lock()` (`_stored_playlist_edit_lock`) を導入し、上記6ハンドラそれぞれの
  「読み取り→加工→save()(またはcreate()+delete())」区間を`with`ブロックで直列化。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`/`py_compile`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。まず**ルート原因の決定論的再現**:
  実際の`mopidy_ytmusic.playlist.YTMusicPlaylistsProvider`をenv構築物からimportし、
  スタブAPI(get_playlist/add_playlist_items/remove_playlist_items/edit_playlistの
  戻り値型を実ytmusicapiと同じ意味で模擬)に対し「接続Aが[X,Y]を読みAを追加して
  save() → 実状態[X,Y,A]」に続けて「接続Bが(Aのsaveを知らない)古い[X,Y]を土台に
  Bを追加してsave()」を実行したところ、**fix前のロジックのまま**でも
  最終状態が`[X,Y,B]`となりAが消えることを確定的に再現した
  (`/tmp/ytplaylist_repro.py`、乱数・タイミング非依存)。続けて`nix/lib/mopidy-env.nix`
  から本パッチの登録行のみ一時的に外してビルドし、dev mopidy(6601, ytmusic
  実アカウント) を起動、実際のMPDプロトコル経由でも同じ実害が起きることを検証:
  ベースライン`[X,Y]`を持つプレイリストに対し2本のTCP接続から`threading.Barrier`で
  同期しほぼ同時に異なる2曲を`playlistadd`する試行を15プレイリストで反復したところ、
  **fix前: 15/15回全てで**後から着地した側の曲だけが残り先行側の曲が消える
  lost updateを実機再現した(両方とも応答は`OK`、ACKエラーなし)。続けて登録行を
  復元してビルドし直し(同じ dev mopidy を再起動)、**全く同じ15プレイリストの
  試行を再実行**したところ、**fix後: 0/15回**でlost updateが解消したことを確認した
  (2曲とも正しく残る)。回帰なし確認: 単一接続での逐次`playlistadd`(POSITION指定含む)/
  `playlistdelete`(範囲指定含む)/`playlistmove`/`rename`/`playlistclear`/
  `save`(current queueの保存)がいずれも引き続き正常応答、`tagtypes`/`status`/
  `search any "yoasobi"`(実データ複数件ヒット)も回帰なしを確認した。mopidy.log の
  Traceback は"YTMusic playlist creation failed"のHTTP 401(このテストアカウントの
  一部書き込み権限不足、他の既存BACKLOGエントリでも既出の pre-existing な挙動で
  fix前後とも同数発生、本パッチとは無関係)のみで新規リグレッションではないことを
  確認した。
- [x] `mopidy_mpd/protocol/stored_playlists.py` の `rm` (ストアドプレイリスト削除) だけが、
  兄弟コマンドの `playlistadd`/`playlistclear`/`playlistdelete`/`playlistmove`/`rename`/
  `save` が全て使う `_stored_playlist_edit_lock` (mpdplaylisteditrace-patch.py導入) を
  一切取らずに `context.core.playlists.delete()` を呼んでいた不具合。TODO/既知の残課題を
  全項目消化済みのため自走エージェントが mpdplaylisteditrace-patch.py 適用後の
  stored_playlists.py を再監査し新規発見した項目 (ロック対象コマンド一覧からの rm 単体の
  抜け漏れ)。`rename` はロック保持中に「old_nameの内容を読む→new_nameへcreate()+save()で
  複製→最後に自分自身が`context.core.playlists.delete(old_playlist.uri)`でold_nameを削除」
  という3段の複合操作を行うが、この「最後の自分自身のdelete()」の直前にロックを取らない
  別接続の `rm old_name` が割り込んで先にold_nameを削除してしまうと、rename自身のdelete()
  呼び出しは「既に存在しないものを削除しようとして失敗」となり `.get()` が `False` を返し
  `ACK [52@0] {rename} Failed to delete playlist` をクライアントへ返してしまう。しかし
  実際にはnew_nameの作成(old_nameの曲を複製)は既に成功しており、old_nameも(rmにより)
  確かに削除済みという、rename としては実質成功している状態。クライアントは「rename失敗」
  という誤ったACKを受け取り、rmpc等は新規作成されたプレイリストに気付けない(表示更新を
  スキップしたり、失敗と誤解して同じrenameを再試行し今度はold_nameが既に存在せず別の
  ACKで混乱する等)。
  verified: mpdplaylistrmrace-patch.py。mpdplaylisteditrace-patch.pyが導入済みの
  `_stored_playlist_edit_lock` を `rm()` にもそのまま流用し、「uri解決→delete()」区間を
  他の6コマンドと同じ `with` ブロックで直列化(rm自体のロジックは無変更)。パッチ適用後の
  生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)
  であることも確認。`nix/lib/mopidy-env.nix` の `mpdPatched` リストの
  `mpdplaylisteditrace-patch.py` 直後に登録しビルド成功。
  **実機検証 (決定的再現テスト、fix前後比較)**: まず `nix/lib/mopidy-env.nix` から本
  パッチの登録行のみ一時的に外してビルドし dev mopidy(6601, ytmusic実アカウント) を起動、
  実際のMPDプロトコル経由で「プレイリストPを`playlistadd`で作成→2本のTCP接続から
  `threading.Barrier`で同期しほぼ同時に接続Aが`rename "P" "Q"`、接続Bが`rm "P"`を送信→
  最終状態(`listplaylists`)を確認→次の試行のためP/Qを掃除」を15回反復したところ、
  **fix前: 15回中12回**で`rename`が`ACK [52@0] {rename} Failed to delete playlist`を
  返しているにも関わらず実際にはQが作成されPが削除済み(rename自体は実質成功)という
  spuriousな失敗ACKを実機再現した(残り3回は`rm`がrenameより先に完了しP自体が既に
  無かったため`rename`が正当な`ACK No such playlist`、これは元々バグではない正常系)。
  続けて登録行を復元してビルドし直し(同じ dev mopidy を再起動)、**同じ試行を20回
  実行**したところ、**fix後: 20回中0回**で上記のspurious failureが発生しないことを
  確認した(常に「renameが先に完全に完了しOK、その後のrmは対象が既に無くACKエラー」
  または「rmが先に完全に完了しOK、その後のrenameは対象が既に無くACK No such
  playlist」のいずれかへ綺麗に直列化された)。回帰なし確認: 単一接続での逐次
  `playlistadd`(新規作成/既存への追加)/`listplaylistinfo`/`playlistmove`/`rename`/
  `listplaylists`/`playlistdelete`/`playlistclear`/`rm`(通常・対象無し)/`rename`
  (存在しないold_name)がいずれも引き続き正常応答、`tagtypes`/`status`/
  `search any "yoasobi"`(実データ複数件ヒット)も回帰なしを確認した。mopidy.log の
  Tracebackは"YTMusic playlist creation failed"のHTTP 401(このテストアカウントの
  一部書き込み権限不足によりこのテストで使ったストアドプレイリストは実際には
  `default_playlist_scheme`のm3uバックエンドへフォールバックして作成されていた、
  他の既存BACKLOGエントリでも既出のpre-existingな挙動でfix前後とも同数発生、
  本パッチとは無関係)と、テスト自身のセットアップ/クリーンアップが未作成・
  削除済みのm3uプレイリストへ`rm`/`listplaylistinfo`を投げたことによる
  "Error deleting/reading playlist ... No such file or directory"(mopidy.m3u拡張側の
  想定内エラーログ、rm/listplaylistinfoハンドラは共に既存の`.get()`/`must_exist`検証で
  正しくACKへ変換済み)のみで、mopidy_mpd/stored_playlists.py由来の新規リグレッションは
  0件であることを確認した。
- [x] `mopidy_mpd/session.py` の `MpdSession.on_line_received()` は、コマンド行の先頭文字が
  小文字英字でない場合(実MPDと同じCSRF/cross-protocol scripting対策: ブラウザ経由で
  HTTPリクエスト等の異種プロトコルのバイト列をMPDの待受ポートへ送りつけ、その中に
  紛れ込ませたMPDコマンド文字列を実行させる攻撃を防ぐガード)、即座に
  `self.connection.stop("Malformed command")` を呼んで接続を切断する設計。ところが
  `mopidy_mpd/network.py` の `LineProtocol.on_receive()` は、1回の `recv()` で受信した
  バッファ内の複数行を単一の for ループで最後まで処理しており、`on_line_received()` 内で
  `self.connection.stop()` を呼んでソケットを `close()` してもこれは for ループを
  中断させない(pykka actor は現在処理中のメッセージ本体を中断する機構を持たない)ため、
  攻撃者が1回のTCP書き込みに `"POST / HTTP/1.1"` のような malformed 行と正規のMPD
  コマンド(`clear` 等)を同梱すると、malformed 行でソケットは即座に close() されるにも
  関わらず for ループ自体は継続し、後続の正規コマンドが `dispatcher.handle_request()`
  へ実際に渡され core の状態変更(キュー操作等、パスワード未設定または認証不要な
  コマンドなら何でも)が発火してしまう、CSRF対策のセキュリティ境界すり抜け。
  TODO/既知の残課題を全項目消化済みのため自走エージェントが再監査し新規発見した項目
  (既存パッチ群の「未捕捉例外によるセッション切断」「read-modify-writeの競合」
  「引数バリデーション漏れ」のいずれとも異なる、切断決定後もループが後続コマンドを
  処理し続けてしまうという新種の不具合)。
  verified: mpdrecvhalt-patch.py。`LineProtocol.on_receive()` の for ループ内で
  `on_line_received()` 呼び出し後に `self.connection.stopping` を確認し、真になって
  いれば即座に break して同一チャンク内の後続行の処理を打ち切る。ループ末尾の
  `enable_timeout()` も既に切断済みの接続へ無意味に再設定しないよう `stopping` 済みなら
  スキップ。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix` の
  `mpdPatched` リストの `mpdplaylistrmrace-patch.py` 直後に登録しビルド成功。
  **実機検証 (決定的再現テスト、fix前後比較)**: まず `nix/lib/mopidy-env.nix` から本
  パッチの登録行のみ一時的に外してビルドし dev mopidy(6601) を起動、python socketで
  「接続Aで`clear`→`add "ytmusic:track:..."`→`playlistinfo`で1曲入っていることを確認→
  接続Bで`b"POST / HTTP/1.1\r\nHost: 127.0.0.1:6601\r\nContent-Type: text/plain\r\n\r\nclear\r\n"`
  を1回の`sendall()`で送信(malformed行+smuggleした`clear`)→接続Bの応答は空(切断確認)→
  接続Cで`playlistinfo`」を実行したところ、**fix前: `playlistinfo`が`OK`のみ(曲0件)**、
  つまり切断されたはずの接続Bから紛れ込ませた`clear`が実際に実行されキューが消去されて
  いることを実機再現した。続けて登録行を復元してビルドし直し(同じ dev mopidy を
  再起動)、**全く同じ手順を再実行**したところ、**fix後: `playlistinfo`が1曲(Rick
  Astley - Never Gonna Give You Up)を保持したまま**であり、smuggleした`clear`が
  実行されなかったことを確認した(接続Bの応答は空のままで正しく切断)。回帰なし確認:
  同一チャンクに正規のコマンドを複数パイプライン(`b"status\r\ntagtypes\r\n"`を1回の
  `sendall()`)しても両方とも正しく応答されること、malformed行単体(`b"Bogus\r\n"`)は
  従来通り即座に切断される(応答が空)こと、`search any "yoasobi"`(実データ3件ヒット)も
  回帰なしを確認した。mopidy.log にエラー/Tracebackの新規発生は無いことを確認した。
- [x] `mopidy_listenbrainz/frontend.py` の `ListenbrainzFrontend.import_playlists()` が、
  ListenBrainz側にまだ存在するのに曲解決だけたまたま失敗した recommendation プレイリスト
  (Weekly Jams/Weekly Exploration等) を誤って obsolete 削除してしまう不具合。
  `import_playlists()` はローカルの既存 `listenbrainz:playlist:recommendation:*` を
  `filtered_existing_playlists` に集めておき、`list_playlists_created_for_user()` が
  返す playlist_data ごとに「今回もLB側に存在が確認できたもの」だけ
  `filtered_existing_playlists.pop()` して削除対象から除外し、ループ後に残ったものだけを
  obsolete として `self.playlists.delete()` する設計だが、元実装は
  `tracks = self._collect_playlist_tracks(playlist_data)` で `len(tracks) == 0` の場合に
  `pop()` へ到達する**前**に `continue` してしまう。`_collect_playlist_data()`
  (listenbrainz.py) は `track_mbids` が空のプレイリストを既に `playlist_datas` から
  除外済みのため、`import_playlists()` 側で `tracks` が0件になるのは「LB側にプレイリスト
  データが無い」からではなく、`_collect_playlist_tracks()` 内のローカルライブラリ検索+
  MusicBrainzフォールバック検索(いずれもネットワーク呼び出しを含む)がその回だけ
  全滅した結果でしかない(一時的なネットワーク不調・ライブラリ再インデックス中等で
  容易に起こりうる)。つまり「LB側にはまだ存在するのに曲解決だけ失敗した」プレイリストが
  `filtered_existing_playlists` に残存したまま obsolete 削除ループに巻き込まれ、
  rmpc/mopidy側から見えていたプレイリストが理由もなく消失する(例外もエラーログも
  出ないサイレントなデータ消失)。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  再監査し新規発見した項目 (mopidy_listenbrainz は既存 lb*-patch.py 群が
  「未捕捉例外によるactorクラッシュ/週次再インポート永久停止」系ばかりを対象にしており、
  本件のような「正常終了はするが判定ロジックが誤って削除する」型は未言及)。
  verified: lbimportobsolete-patch.py。既存判定 (`filtered_existing_playlists`からの
  `pop()`) を `tracks == 0` の `continue` より前に移動し、LB側に存在することが確認できた
  時点で無条件にpopして削除対象から外すよう変更 (`already_known` 変数を導入)。
  曲解決に失敗した回はsave/create自体は従来通りスキップし前回保存済みの内容を温存する。
  パッチ適用後の生成ソースは一時コピーに `chmod +w` した上で `ast.parse` で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix` の
  `listenbrainzPatched` に `lbgetitems-patch.py` の直後に登録しビルド成功、生成ソースに
  新実装が反映されていることを確認した。ListenBrainz は dev環境では認証情報(secrets)が
  無く `enabled = false` のため実アカウントでの実機起動確認はできないが
  (lbplaylistrefresh-patch.py 等の既存LB系パッチと同じ制約)、代わりに
  **オフライン単体テスト**でバグの再現とその解消の両方を実証:
  `ListenbrainzFrontend` を `core`/`lb`/`_collect_playlist_tracks` をフェイク/モック化して
  直接構築し `import_playlists()` を呼び出す形で、**パッチ前**(旧env)は「ローカルに
  既存の recommendation プレイリスト1件、LB側の `list_playlists_created_for_user()` は
  同じ playlist_id を含むデータを返す(track_mbids非空)が `_collect_playlist_tracks()` は
  今回0件を返す」状況で `self.playlists.delete()` がそのプレイリストに対し実際に呼ばれる
  ことを確認しバグを再現、**パッチ後**(新env)は全く同じ入力で `delete()` が一切
  呼ばれないことを確認した。回帰確認として5シナリオ(1: LBの一覧に全く含まれない
  真に obsolete なプレイリスト→従来通り削除される、2: 既知プレイリストで曲解決が正常→
  従来通り `save()` される、3: 新規プレイリストで曲解決が正常→従来通り `create()`+
  `save()` される、4: 新規プレイリストで曲解決が全滅→従来通り何もしない、5: 元のバグ
  シナリオの再確認)を全て実行し、いずれも期待通りの結果(意図した削除/保存動作に無回帰)
  であることを確認した。続けてパッチ済みenvで dev mopidy(6601) を実際に起動し、MPDで
  `ping`/`status`/`tagtypes` が正常応答すること、mopidy.log に Traceback/ERROR が
  0件(`listenbrainz` は設定通り `Disabled extensions` に含まれるのみ)であることを
  確認し、ビルド・起動の無回帰を確認した。
- [x] `mopidy_mpd/protocol/partition.py` の `delpartition {NAME}` ハンドラが、
  `translator.partition_exists(name)`(存在確認)/`translator.partition_list()[0]`
  (default判定)/`translator.partition_client_count(name)`(クライアント数確認)/
  `translator.partition_output_count(name)`(出力数確認)/
  `translator.partition_delete(name)`(削除実行)という5回の**別々**の
  translator.py呼び出しで構成されている不具合。mpdpartitionrace-patch.pyが
  個々の呼び出しに`_partition_lock`(threading.RLock)を掛けクラッシュ
  (dict/list走査中のRuntimeError)は解消済みだが、ハンドラ側の「4種のチェック→
  削除」という複合操作全体はアトミックではないまま残っていた。TODO/既知の
  残課題を全項目消化済みのため自走エージェントが再監査して発見した項目
  (mpdmounttoctou-patch.pyがmount.py側の全く同型の複合チェックTOCTOUを
  `mount_try_add()`で単一ロックスコープにまとめて対処済みなのに対し、
  partition.pyのdelpartition側は未着手のまま残っていた)。
  verified: mpdpartitiondeltoctou-patch.py。mpdmounttoctou-patch.pyの
  `mount_try_add()`と同じ流儀で、存在確認・default判定・クライアント数確認・
  出力数確認・削除を1つのtranslator.py側関数`partition_try_delete()`にまとめ
  `_partition_lock`を1回だけ保持したまま最後まで実行するよう変更(partition.py
  側は名前の正規表現バリデーションの後にこの1関数を呼び、返ってきた状態文字列
  に応じて元と同じACKメッセージ・優先順位で例外を送出するだけに変更)。パッチ
  適用後の生成ソースは一時コピーに`chmod +w`した上で`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  `mpdPatched`リストの`mpdrecvhalt-patch.py`直後に登録しビルド成功、生成ソース
  に新実装(`partition_try_delete`)が反映されていることを確認した。
  **実機検証**: パッチ済みenvでdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで確認 — `newpartition p1`→`delpartition p1`(クライアント・出力
  無し)→`OK`、`delpartition bogus`→`ACK [50@0] {delpartition} no such
  partition`、`delpartition default`→`ACK [5@0] {delpartition} cannot delete
  the default partition`、`newpartition p2`→接続Bで`partition p2`へ切替→
  接続Aで`delpartition p2`→`ACK [5@0] {delpartition} partition still has
  clients`(正しく拒否)、接続Bが`partition default`へ戻ってから
  再度`delpartition p2`→`OK`、`status`/`tagtypes`の回帰なしを確認。
  **決定的TOCTOU再現テスト(fix前後比較)**: `translator.py`をfix前
  (mpdpartitionrace-patch.py適用まで、`partition_try_delete`不在)とfix後の
  両方を直接importし、実際のdelpartitionハンドラのロジック(存在確認→
  default判定→クライアント数確認→出力数確認→削除)を素朴に再現した上で、
  「クライアント数確認直後・削除実行前」の実際のTOCTOU窓に
  `threading.Event`で強制的に別スレッドの`partition_switch(999, "p2")`を
  割り込ませるテストを実施 — **fix前**: `partition_delete("p2")`が実行され、
  `p2`は削除されたにもかかわらずsession 999は`partition_get(999)`で引き続き
  `"p2"`を指したままという不整合(存在しないパーティションへの迷子参照)を
  実際に再現。**fix後**: 同じ強制割り込みタイミングで`partition_try_delete`を
  呼んだところ、内部で`_partition_lock`を保持し続けるため`partition_switch`が
  ブロックされてから実行され、`has_clients`と正しく判定されて削除が拒否される
  ことを確認した(`p2`は存在したまま、session 999は引き続き`p2`に所属)。
  mopidy.logにエラー/Tracebackの新規発生は無いことを確認した。
- [x] `mopidy_mpd/protocol/partition.py` の `newpartition {NAME}` ハンドラが、
  「現在のパーティション数が16 (実MPDの暫定上限、mpdpartition-patch.py参照) 未満か」
  の確認 (`translator.partition_list()` で件数取得) と実際の作成
  (`translator.partition_create(name)`) という**別々**のtranslator.py呼び出しで
  構成されている不具合。`partition_list()`/`partition_create()`はそれぞれ独立に
  `_partition_lock`を取得・解放するため両呼び出しの間に隙間があり、2接続が
  ほぼ同時に(現在15個などギリギリで)異なる名前の`newpartition`を送ると両方とも
  「15 < 16」判定を通過してから`partition_create()`を呼び、結果パーティション数が
  17個(実MPD仕様の上限16を超過)になってしまう。TODO/既知の残課題を全項目
  消化済みのため自走エージェントが再監査して発見した項目
  (mpdpartitiondeltoctou-patch.pyがdelpartition側の「存在確認→default判定→
  クライアント数確認→出力数確認→削除」という複合操作の同型TOCTOUを
  `partition_try_delete()`で対処済みなのに対し、newpartition側の
  「件数確認→作成」も全く同じ非アトミック複合操作のまま残っていた。事前に
  Explore サブエージェントへ他の未対応箇所の調査を委任したが、その報告した
  候補 (`playlistinfo()`の`if start and start > len(tl_tracks)`) は実際には
  `start=0`のとき`0 > len(tl_tracks)`が`len`の値に関わらず常にFalseであり
  `and`によるショートサーキットの有無で挙動が変わらないため誤検知と判明、
  不採用とした上で自分で再監査し本項目を発見)。
  verified: mpdnewpartitionrace-patch.py。mpdpartitiondeltoctou-patch.pyの
  `partition_try_delete()`と同じ流儀で、存在確認・上限確認・追加を
  translator.py側の1関数`partition_try_create()`にまとめ`_partition_lock`を
  1回だけ保持したまま最後まで実行するよう変更(partition.py側は名前の
  正規表現バリデーションの後にこの1関数を呼び、返ってきた状態文字列に応じて
  元と同じACKメッセージ・優先順位で例外を送出するだけに変更、旧
  `partition_create()`はこの1箇所からしか呼ばれていないため置き換えて削除)。
  パッチ適用後の生成ソースは一時コピーに`chmod +w`した上で`ast.parse`で構文
  確認、2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  `mpdPatched`リストの`mpdpartitiondeltoctou-patch.py`直後に登録しビルド成功、
  生成ソースに新実装(`partition_try_create`)が反映されていることを確認した。
  **実機検証**: パッチ済みenvでdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで確認 — `newpartition p1`→`OK`、`newpartition p1`(重複)→
  `ACK [56@0] {newpartition} name already exists`、`newpartition`に不正な名前→
  `ACK [2@0] {newpartition} ...`(名前バリデーション回帰なし)、`listpartitions`
  で反映確認、`delpartition p1`→`OK`。上限境界: defaultに加えp0〜p14の15個を
  順次作成し合計16個に到達した状態で17個目`newpartition overflow`→
  `ACK [5@0] {newpartition} too many partitions`(境界値の回帰なし)、
  作成した15個を`delpartition`で全削除し`listpartitions`がdefaultのみに戻る
  ことを確認。`status`/`tagtypes`/`search any "yoasobi"`の回帰なし、
  mopidy.logにTraceback/ERROR無し。
  **決定的TOCTOU再現テスト(fix前後比較)**: `translator.py`をfix前
  (`partition_create`が件数チェックと別呼び出し)とfix後の両方のロジックを
  スタンドアロンで再現した上で、「件数確認直後・作成実行前」の実際のTOCTOU窓に
  2スレッドを`threading.Event`で強制的に同時到達させるテストを実施 — **fix前**:
  15個保持の状態で2スレッドが同時に異なる名前の`newpartition`を実行したところ
  両方とも「15<16」判定を通過して作成に成功し、結果パーティション数が17個
  (上限16を超過)になる不整合を実際に再現。**fix後**: 同じ強制同時実行タイミングで
  `partition_try_create`を呼んだところ、内部で`_partition_lock`を保持し続ける
  ため2スレッド目の判定は1スレッド目の追加が完了してから実行され、正しく
  片方が`None`(成功)・もう片方が`"too_many"`(拒否)となり最終的に16個を
  超えないことを確認した。

- [x] `mopidy_ytmusic/library.py` の `browse()` `ytmusic:mood` (Mood and Genre
  Playlists のカテゴリ一覧そのもの、「Feel good」等のフォルダが並ぶ最上位ページ)
  が、`FEmusic_moods_and_genres` レスポンスの各セクションを無条件に
  `gridRenderer` 持ちと決め打ちし、各カテゴリ項目を無条件に
  `musicNavigationButtonRenderer` の完全な構造(`buttonText.runs[0].text` /
  `clickCommand.browseEndpoint.browseId`/`params`)を持つと決め打ちして
  `nav()` (none_if_absent省略時はKeyError/IndexErrorを送出、ytmusicapi
  navigation.py 132〜143行で確認) 経由でアクセスしている不具合。TODO 全項目
  消化済みのため自走エージェントが調査して新規発見・追加した項目。
  既存の `ytmoodgenre-patch.py` は1階層下の「ytmusic:mood:<params>:<browseId>」
  (個別カテゴリを開いた後の曲/プレイリスト一覧) で全く同型の「1件の想定外構造が
  for ループ全体を道連れにし、そのページが丸ごと空になる」問題を既に修正済み
  (musicTwoRowItemRenderer が browseEndpoint を持たず単曲ミュージックビデオを
  指すケース、musicCarouselShelfRenderer と gridRenderer が混在するケース等、
  実データで確認済み)。同じ弱点がその1階層上のカテゴリ一覧側には手つかずのまま
  残っていた (grep で `FEmusic_moods_and_genres` を扱うパッチが他に存在しない
  ことを確認)。
  verified: ytmoodcategory-patch.py。セクション単位では `gridRenderer` を
  持たないものは`continue`で読み飛ばし、カテゴリ単位では1件ごとに
  try/exceptで囲みパース失敗を警告ログに留めて次のカテゴリへ継続するよう
  修正 (ytmoodgenre-patch.py/ytparsegaps-patch.py/ytautoplaylistfix-patch.py
  と同じ「1件の異常が全体を道連れにしない」流儀)。パッチ適用後の生成ソースは
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  実アカウントの実データでは今回 `FEmusic_moods_and_genres` の全セクションが
  `gridRenderer` かつ全37カテゴリが完全な構造で返り、旧実装でも偶然クラッシュ
  しなかった (dev mopidy(6601) で `lsinfo "YouTube Music/Mood and Genre
  Playlists"` → 37ディレクトリ正常応答、mopidy.log に本パッチの警告ログ・
  Traceback とも0件、続く `lsinfo ".../Feel good"` `tagtypes` `status` も
  正常応答で回帰なしを確認)。そのため実データでの「fix前after crash」の直接
  再現はできなかったが、クラッシュ機構自体はオフラインの単体テストで確定的に
  検証した: `FEmusic_moods_and_genres` と同じ `SINGLE_COLUMN_TAB+SECTION_LIST`
  構造に対し、(a) `gridRenderer` を持たないセクション
  (`musicCarouselShelfRenderer`、ytmoodgenre-patch.py が下の階層で実際に
  混在を確認済みの種別) と (b) `buttonText.runs` が空という1階層下の実例に
  倣った想定外構造のカテゴリ項目、を混ぜた合成レスポンスを与えたところ、
  旧ロジック(パッチ前と同一コード)は1件目の正常カテゴリを集めた直後に
  `IndexError("Unable to find '0' ...")` で例外送出し `moods` ごと失う
  ことを確認、新ロジック(パッチ後と同一コード)は不正な1件だけ警告ログで
  読み飛ばし残り2件(gridRenderer外セクション混在下でも)を正しく回収する
  ことを確認した。

- [x] `mopidy_mpd/protocol/playback.py` の `seek {SONGPOS} {TIME}` に、
  `status`/`currentsong`/`playlistid`/`plchanges` で既に修正済み
  (mpdcurrentsongrace-patch.py/mpdstatusrace-patch.py) なのと全く同型の
  TOCTOUレースだけが対策から漏れて残っていた不具合。TODO 全項目消化済みのため
  自走エージェントが (サブエージェントに調査を委任した上で) mopidy_mpd の
  コード品質を再調査して新規発見・追加した項目。旧実装は
  `tl_track = context.core.playback.get_current_tl_track().get()` (呼び出し1、
  playback proxy経由) の後、別の `context.core.tracklist.index(tl_track).get()`
  (呼び出し2、tracklist proxy経由) で位置を求めており、`context.core` は単一の
  pykka actor (mopidy.core.actor.Core) をラップする ActorProxy で
  `.playback`/`.tracklist` はその Core actor が直接保持する素の Python
  サブコントローラに過ぎないため、この2回は独立したactorメッセージ往復であり
  間隙で他クライアントの `move`/`swap`/`delete` 等が割り込みうる。割り込むと
  `index(tl_track)` は割り込み後の無関係な位置を返し、songposとの一致判定が
  サイレントに(ACKにもならず)誤り、意図しない曲へ再生が切り替わる、または
  必要な切り替えが行われない、という不具合が起こりうる。
  verified: mpdseekrace-patch.py。`mopidy/core/tracklist.py` の
  `TracklistController.index(tl_track=None, tlid=None)` が引数省略時に内部で
  `self.core.playback.get_current_tl_track()` を (別途のactor往復を経ない、
  同一actor内の素の属性アクセスとして) 呼び出し、そのまま
  `self._tl_tracks.index(...)` する実装であることをソース確認した上で活用し、
  `context.core.tracklist.index().get()` という引数無し呼び出し1回だけで
  「現在再生中の曲の位置」を単一の Core actor メッセージ内でアトミックに
  取得するよう修正 (seek()はtl_trackオブジェクト自体を使わず位置比較にしか
  使っていないため、playlistidのTOCTOU修正と同じ「複数呼び出しを1回へ
  一本化しレースそのものを解消する」方針。currentsong/plchangesのような
  tracklist.versionのbounded retryは、tl_track自体も後続で必要とする
  それらのケース用の次善策であり、本件では不要と判断)。パッチ適用後の
  生成ソースは ast.parse で構文確認、2回適用しても冪等(スキップ)であることも
  確認。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、YOASOBI検索
  結果2曲をキューに積んで実機確認 — `play 0`→再生開始、`seek 0 10`
  (現在位置と同じsongposを指定、切り替え不要のケース)→曲は切り替わらず
  `elapsed: 10.000`のみ反映(status確認)、`seek 1 3`(異なるsongpos)→
  ACKにならずOK応答(切り替え判定自体は分岐に入る)、範囲外`seek 99 0`→
  `ACK Bad song index`(既存の引数バリデーション回帰なし)、`seekcur 5`/
  `status`/`tagtypes`/`currentsong`の回帰なしを確認、mopidy.log に
  Traceback/ERROR無し。加えてこの挙動が自分のパッチによる変化ではなく
  pykka actor間のレース窓を無くしたことによる副作用の混入でないことを
  切り分けるため、パッチ未適用の旧env (`fjh4jg8lra50pcr28af4h9zl208rvvch-
  python3-3.13.14-env`) でも同一手順を再実行し、`play`/`seek`の基本応答が
  旧実装と新実装で同一であることを確認した。実際のTOCTOU発火(2接続を
  正確なタイミングで競合させる)は実サーバー上での再現が実務上困難なため、
  mpdnewpartitionrace-patch.py等と同じ「fix前/fix後の決定的スタンドアロン
  再現」手法で、フェイクのcore呼び出し(get_current_tl_track()とindex()の
  間に外部からの割り込みを注入)により、fix前ロジックが割り込み後の
  torn値を無検証で使ってしまうのに対し、fix後(引数無しindex()への一本化)
  はそもそも2回の別呼び出し自体が存在しないためレース窓が構造的に
  発生し得ないことをコードレベルで確認した。

- [x] `readcomments {URI}` / `lsinfo {URI}` (曲そのものの生URIへのフォールバック、
  mpdlsinfouri-patch.py) が、docstring/仕様上許容されている「スキーム無しの生パス
  文字列」(例: `readcomments "test.mp3"`、ライブラリに存在しない未登録の任意文字列)
  を無検証のまま `context.core.library.lookup(uris=[uri])` に渡してしまい、
  `mopidy.core.LibraryController.lookup()` 内部の `validation.check_uris()` が
  `urllib.parse.urlparse(uri).scheme == ""` を検知して送出する
  `mopidy.exceptions.ValidationError` (mopidy_mpd 独自の `exceptions.MpdAckError`
  系統ではない) が `mopidy_mpd/dispatcher.py` の `handle_request()`
  (`except exceptions.MpdAckError`/`except pykka.ActorDeadError` のみ捕捉) にも
  `mopidy_mpd/session.py` の `on_line_received()` にも捕捉されず、pykka actor を
  未捕捉例外のまま突き抜けて当該コネクションが応答無しで即切断されてしまう不具合
  (サーバ本体は生存、当該コネクションのみ切断。mpdseekcurargerr-patch.py 発見時の
  素の ValueError によるセッション切断と同種の被害)。TODO 全項目消化済みのため
  自走エージェントが (サブエージェントに調査を委任した上で) 再調査して新規発見・
  追加した項目。`update`/`rescan` の `_mpdupdate_refresh()` だけは既にこの
  `ValidationError` を try/except で捕捉し「何もせず正常応答」に変換済みだが、
  同じ「クライアント生URIをそのまま `core.library.lookup()`/`core.library.refresh()`
  へ渡す」パターンの `readcomments` と `lsinfo` の生URIフォールバックにはこの防御が
  一切コピーされていなかった (grep で該当箇所を確認)。
  verified: mpdrawuriguard-patch.py。両呼び出しを共通ヘルパ
  `_mpd_lookup_uri_or_no_such_song()` に集約し、`_mpdupdate_refresh()` と同じ
  変換方針で `mopidy.exceptions.ValidationError` を捕捉して空リスト (=
  「そんな曲は無い」) に丸めるよう修正 (`readcomments` は結果空で
  `MpdNoExistError("No such song")` へ、`lsinfo` は既存の
  `except exceptions.MpdNoExistError:` 節内で空なら素の `raise` により元の
  `Not found` へ、いずれも従来のACKエラー系へ自然に合流)。パッチ適用後の生成
  ソースは `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  dev mopidy(6601, ytmusic実アカウント) を実際に起動しMPDで実機確認 —
  **fix前** (パッチ未適用の旧env `8xmm6fmb7zip4qkbj27khy1pp9acpzhr-python3-
  3.13.14-env` で同一 mopidy-dev.conf を使い別プロセスとして起動して比較):
  `readcomments "test.mp3"` 送信後 `recv()` が空バイト列(接続断)で返り、続く
  `status` も空バイト列(接続が既に閉じている)、ログに
  `mopidy.exceptions.ValidationError: Expected a list of URIs, not 'test.mp3'`
  の Traceback(pykka actor 内で未捕捉)を確認。**fix後**: 同じ
  `readcomments "test.mp3"` → `ACK [50@0] {readcomments} No such song`
  となり接続は切断されず、続く `status` も正常応答。同様に
  `lsinfo "no/such/thing.flac"` → `ACK [50@0] {lsinfo} Not found`
  となり接続維持、続く `status` も正常応答。回帰確認として `lsinfo` (ルート、
  YouTube Music ディレクトリ+ストアドプレイリスト一覧)・`tagtypes`・
  `currentsong` の正常応答、mopidy.log に Traceback/ERROR 0件であることを確認。
- [x] `mopidy_mpd/protocol/music_db.py` の `searchaddpl {NAME} {FILTER} ...` が、
  `context.core.playlists.lookup()` でストアドプレイリストの現在の内容を読む →
  `context.core.library.search()` の検索結果とローカルでマージ →
  `context.core.playlists.save()`(または存在しなければ `create()`)で書き戻す、
  という read-modify-write を行っているにもかかわらず、兄弟コマンドの
  `playlistadd`/`playlistclear`/`playlistdelete`/`playlistmove`/`rename`/`save`/`rm`
  (`stored_playlists.py`) が全て使う `_stored_playlist_edit_lock`
  (mpdplaylisteditrace-patch.py/mpdplaylistrmrace-patch.py) の対象外のまま
  取り残されていた不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (サブエージェントに調査を委任した上で) 再調査して新規発見・追加した項目
  (mpdplaylisteditrace-patch.py の対象列挙は `stored_playlists.py` 内の
  6コマンドに限定されており、別ファイル `music_db.py` の兄弟コマンドである
  `searchaddpl` は元々スコープ外だった。`music_db.py` 自体に `threading`/`Lock`
  の記述が皆無であることをソースから直接確認)。
  実害: 接続Aが `playlistadd "P" trackA`、接続Bがほぼ同時に
  `searchaddpl "P" any "query"` を送ると、Aは `_stored_playlist_edit_lock` を
  取った状態で読み取り→save()するが、Bはロックを一切取らずに独立して
  「Pの内容を読む→検索結果を加えてsave()」してしまうため、両者の読み取り〜save()が
  重なると後勝ちのsave()が先行クライアントの追加分を踏み潰す (lost update)。
  mpdplaylisteditrace-patch.py が既に詳述した通り、
  `mopidy_ytmusic.playlist.YTMusicPlaylistsProvider.save()` は「渡された
  `playlist.tracks` を目的状態とし、save() 呼び出し時点でYTM側から改めて取得した
  実際の状態との `Counter` 差分だけを add/remove API へ送る」設計のため、Bが古い
  状態を土台に save() すると、Aが追加した曲は newCounts に含まれず removeCounts に
  回り**実際にYouTube Music側から削除される**。両方とも `OK` が返り、ACKエラーは
  一切出ないサイレントなデータ消失。`searchaddpl` は read と write の間に
  `context.core.library.search()` という時間のかかるネットワークI/Oを挟むため、
  `playlistadd` 同士のレースよりもさらにレース窓が長く発生しやすい。
  verified: mpdsearchaddplrace-patch.py。mpdcrossfade-patch.py 等と同じ
  「protocol/*.py 間で共有する揮発性状態は translator.py に置く」流儀で、
  mpdplaylisteditrace-patch.py が `stored_playlists.py` に導入した
  `_stored_playlist_edit_lock` を `translator.py` へモジュールレベルの共有
  `threading.Lock()` として引き上げ、`stored_playlists.py` 側の定義をこの
  共有オブジェクトへの参照 (`_stored_playlist_edit_lock =
  translator._stored_playlist_edit_lock`) に置き換えた上で、`music_db.py` の
  `searchaddpl` の `lookup()→search()→save()/create()` 区間も同じロックで
  直列化 (`stored_playlists.py` 側の既存7箇所の `with _stored_playlist_edit_lock:`
  はローカル変数名を変えていないため無修正で動作し、実体が同一のLockオブジェクトを
  指すようになることで `searchaddpl` とも相互排他になる)。パッチ適用後の生成
  ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)
  であることも確認。まず**ルート原因の決定論的再現**: `nix/lib/mopidy-env.nix` から
  本パッチの登録行のみ一時的にコメントアウトしてビルドし、dev mopidy(6601, ytmusic
  実アカウント)を起動、`threading.Barrier`で2接続を同期しほぼ同時に
  「接続A: 既存ストアドプレイリストへ`playlistadd`でtrackAを追加」
  「接続B: 同じプレイリストへ`searchaddpl`(`artist "YOASOBI" title "夜に駆ける"`で
  ちょうど1曲にヒットする検索条件)でtrackBを追加」を実行する試行を15プレイリストで
  反復したところ、**fix前: 15/15回全てで**後から着地した側の曲だけが残り先行側の曲が
  消えるlost updateを実機再現した(両方とも応答は`OK`、ACKエラーなし)。続けて
  登録行を復元してビルドし直し(同じ dev mopidy を再起動)、**全く同じ試行を
  再実行**したところ、**fix後: 15/15回**でlost updateが解消し両方の曲が正しく
  残ることを確認した。回帰確認: `playlistadd`/`playlistmove`/`rename`/
  `playlistclear`/`rm`(現行キューの`save`含む)の単一接続での逐次実行が引き続き
  正常応答、`searchaddpl`単体での新規プレイリスト作成+曲追加+`rm`、
  引数無し`searchaddpl`→`ACK incorrect arguments`、`tagtypes`/`status`/
  `count any "YOASOBI"`/`list album`の回帰なしを確認。mopidy.log の
  Traceback/ERROR は全て「YTMusic playlist creation failed」の HTTP 401
  (このテストアカウントの一部書き込み権限不足、mpdplaylisteditrace-patch.py
  検証時にも既出のfix前後とも同数発生する pre-existing な挙動) と
  「Error reading playlist '...': No such file or directory」(m3uバックエンドが
  存在しないm3uファイルへの`rm`/`lookup`を試みる際の既存ノイズ、いずれも
  `music_db.py`/`stored_playlists.py`/`translator.py`に起因するものは0件) のみで、
  本パッチによる新規リグレッションではないことを確認した。
- [!] `mopidy_mpd/protocol/playback.py` の `seek {SONGPOS} {TIME}` / `seekid {SONGID}
  {TIME}` に、直前の `mpdseekrace-patch.py` の修正範囲(「現在曲がsongpos/tlidと
  一致するか」のチェック段階のTOCTOU)の外側に残っている別のTOCTOUレース: 判定後に
  実際に曲を切り替える`play(context, songpos)`/`playid(context, tlid)`の呼び出し
  完了から、直後の無条件`context.core.playback.seek(...)`発行までの間隙には何の
  ガードも無く、この間に別クライアントが`next`/`previous`/`play`/`playid`等で
  現在曲を再び切り替えると、`context.core.playback.seek()`はsongpos/tlidを一切
  指定せず暗黙に「その時点の現在曲」に作用するAPIのため、無関係な曲へサイレントに
  (ACKにもならず)seekしてしまいうる。TODO 全項目消化済みのため自走エージェントが
  (サブエージェントに調査を委任した上で) 再調査して新規発見した項目。
  blocked: mpdseekplayerrace-patch.py として、play()/playid()完了直後・seek()発行
  直前に`context.core.tracklist.index()`/`get_current_tl_track()`で現在曲が
  まだ意図したsongpos/tlidのままか再確認し、不一致ならseekcurの停止中ガード
  (`_MpdSeekCurPlayerSyncError`, ACK_ERROR_PLAYER_SYNC)と同じ方針でACKへ変換する
  実装を行い、ast構文確認・冪等性確認・ビルドまで成功させたが、dev mopidy(6601,
  ytmusic実アカウント)での実機検証で、**他クライアントの割り込みが一切無い単独
  クライアントの普通の`play "0"`→`seek "0" "5"`のような逐次操作でさえ
  `ACK [55@0] {seek} Player synchronization error`を誤って返す**重大な
  false-positiveリグレッションを発見したため revert し未コミットのまま破棄した。
  原因調査: `mopidy/core/playback.py`の`PlaybackController.play()`は
  `_current_tl_track`を即座には更新せず、まず`_pending_tl_track`にのみ
  設定し、`_current_tl_track`への昇格(139-143行目付近`_set_current_tl_track
  (self._pending_tl_track)`)は再生エンジン側のイベント(stream started等)を
  待つ非同期処理であることをソースで確認 (実機ではfakesink+YouTube Music
  ストリーム解決込みで`play`直後から`song`/`songid`が意図した曲に落ち着くまで
  実測で最大0.9秒程度かかることを`status`を100msおきにポーリングして確認)。
  一方`context.core.tracklist.index()`(引数省略時)が内部で呼ぶ
  `get_current_tl_track()`は`_current_tl_track`のみを見て`_pending_tl_track`
  にはフォールバックしないため、この非同期な昇格待ちの間はplay()直後でも
  「まだ意図した曲になっていない」と誤検知してしまう。一方`mopidy/core/
  playback.py`の`PlaybackController.seek()`自体は429行目付近で
  `tl_track = self._current_tl_track or self._pending_tl_track`と
  pending側へのフォールバックを持つ設計であり、素の(パッチ前の)実装でも
  play()直後のseek()は実際には正しく意図した曲(pending)に対して働いていた
  ことが判明した。つまり本パッチが追加した「直後の再確認」は、防ごうとした
  レース(他クライアントの割り込み)を正しく検知できないばかりか、割り込みが
  一切無い正常系の非同期昇格待ちを誤って割り込みと区別できず、修正前より
  悪い(無害な操作までACKエラーにする)結果になっていた。`_pending_tl_track`
  はcore.playback配下のprivateフィールドで、`get_pending_tl_track()`のような
  公開APIも無いため、MPDプロトコル層(本パッチスクリプトのスコープ、
  configs/media/mopidy/とnix/lib/mopidy-env.nixのみ、mopidy core自体は
  パッチ対象外)から「play()/playid()完了直後、pending昇格前でも安全に
  意図した曲かどうか」を正しく判定する手段が無く、根本修正にはmopidy core
  自体への変更が必要でありスコープ外と判断した。今後再挑戦する場合の
  方向性メモ: (a) `_current_tl_track`だけでなく`_pending_tl_track`も見えるよう
  mopidy core側にpublicなgetterを追加する(スコープ外)、(b) 再確認を
  即座にではなく`get_current_tl_track()`が安定するまでポーリングして待つ
  (実測0.9秒程度かかりうる=seekコマンドの応答が不必要に遅延し、かつ待ち時間の
  上限をどこに置くべきか自明でない、が有力な次善策候補)、(c) この残存レース窓
  自体は「他クライアントが再生曲を切り替える」という比較的まれな操作と
  タイミングが重なる必要があり、rmpcはseekid/seekのいずれも送らずseekcurのみ
  使うため実害はrmpc利用シーンでは発生しない(rmpc以外の一般MPDクライアントの
  利用シーンのみが対象)、影響範囲は限定的と判断し優先度を下げる、のいずれか。
- [x] `moveoutput {NAME}` ハンドラ (`mopidy_mpd/protocol/partition.py`) が、現在の
  所属確認 (`translator.output_partition_get(name)`) / 移動先確認
  (`translator.partition_get(id(context.session))`) / 移動実行
  (`translator.output_partition_move(name, dest)`) という3回の別々の
  translator.py 呼び出しで構成されており、個々の呼び出しは
  mpdpartitionrace-patch.py の `_partition_lock` で保護済みでも「現在の所属を
  読む→比較→書き込む」という複合操作全体はアトミックでなかった不具合。
  mount.py の mount ハンドラ (mpdmounttoctou-patch.py) や同じ partition.py 内の
  newpartition/delpartition (mpdnewpartitionrace-patch.py/
  mpdpartitiondeltoctou-patch.py) は既に単一ロックスコープのアトミック関数
  (`*_try_*`) 化済みだったが、moveoutput だけこの手当てが漏れていた。TODO
  全項目消化済みのため自走エージェントが(サブエージェントに調査を委任した上で)
  再監査して新規発見した項目。
  verified: mpdmoveoutputrace-patch.py。mount_try_add()/partition_try_create()/
  partition_try_delete() と同じ流儀で `output_partition_try_move(name, dest)` を
  translator.py に新設し、現在の所属確認・比較・書き込みを `_partition_lock` を
  1回だけ保持したまま単一スコープでアトミックに実行するよう変更 (moveoutput側は
  返ってきた"not_found"/"moved"/"unchanged"の状態文字列で分岐するだけに簡素化)。
  レース自体の証明: 実サーバーはスレッドスケジューリングが揃わずTCP越しに
  正確なレース窓を踏めないため、translator.pyの該当ロジックのみを抽出した
  スタンドアロン再現スクリプトで検証 — 出力の現在の所属がpartition Aの状態で、
  クライアントX(dest=B)がcurrent=Aを読み取った直後(旧実装は読み取りと書き込みが
  別呼び出しのためこの間にロックが解放される)にクライアントY(dest=A、つまり
  「出力は自分のpartition Aにある」と思って何もしないはずの操作)を実行させると、
  旧実装ではYが古いcurrent=A(Xの書き込み前のスナップショット)を見て
  `unchanged`と誤判定しOKを返す一方、実際の出力はXの書き込みにより既にBへ
  移動済みという、ACKエラー無しのサイレントなロストアップデート(Yは「出力は
  自分のpartitionにある」と思い込むが実際は無い)を実機に忠実なロジックで再現。
  新実装(output_partition_try_move、単一ロックスコープ)で同じ操作を行うと、
  Yはロック取得までXの書き込み完了を待たされ、ロック取得後にXが書き込んだ
  最新のcurrent=Bを見て正しく`moved`(→A)と判断し、最終状態もYの認識と一致し
  食い違いが解消することを確認 (再現スクリプトの出力で両ケースを実演)。
  加えて、パッチ適用後の生成ソースは ast.parse で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`に
  mpdnewpartitionrace-patch.pyの直後に登録しビルド成功、生成ソースに新実装が
  反映されていることを確認した上で dev mopidy(6601, ytmusic実アカウント)を
  実際に起動しMPDで実機確認 — `newpartition p1`/`newpartition p2`→OK、
  `partition p1`→OK、`moveoutput Mute`(default→p1)→OK、`outputs`→
  移動後もMute自身の情報は変わらず(1出力のみの設計通り)、別接続からの
  `outputs`(defaultパーティション所属)→`plugin: dummy`(所有権が無いpartitionの
  既存表示、mpdoutputpartition-patch.py由来、回帰なし)、`moveoutput Bogus`
  (存在しない出力名)→`ACK [50@0] {moveoutput} No such output`、別接続からの
  `moveoutput Mute`(p1→defaultへ戻す)→OK、その後の1接続目`outputs`も
  `plugin: dummy`へ追従(状態が全接続で共有されていることを確認)。
  `delpartition p1`(クライアント在席中)→`ACK [5@0] {delpartition} partition
  still has clients`(既存動作、回帰なし)。レースストレステスト: 2接続をそれぞれ
  別partition(rA/rB)に所属させ`moveoutput Mute`を300回ずつ交互に連打する8並行
  スレッドテストを実施 — ACKエラー0件、最終状態は一貫して整合(クラッシュ・
  無応答化なし)、mopidy.logにERROR/Traceback 0件(既存の
  ytmusicテストアカウント起因の401/m3u未存在ファイル起因のノイズのみ)。
  `status`/`tagtypes`/`listpartitions`の回帰なしも確認。
- [x] `mopidy_ytmusic/library.py` の `browse()` `"ytmusic:watch"` (Similar to last
  played) 分岐で、`get_watch_playlist()` が `{"tracks": []}` (キーはあるが曲0件、
  直近曲がラジオ候補を生成できないタイプの動画の場合に起こりうる) を返すと、
  先頭のシード曲を捨てるための `res["tracks"].pop(0)` が無条件に呼ばれており
  `IndexError` を送出する不具合。同じ関数の2行上にある兄弟コード
  `hist[0]["videoId"]` (履歴が空リストの場合の同種の未ガードアクセス) は
  ythistory-patch.py で既に `if hist else None` とガード済みだが、2行下の
  `res["tracks"].pop(0)` は同じ「空リストへの無条件アクセス」パターンにも
  関わらず見落とされたまま残っていた。TODO 全項目消化済みのため自走エージェントが
  (サブエージェントに調査を委任した上で) 再調査して新規発見した項目。
  verified: ytwatchemptypop-patch.py。`res["tracks"].pop(0)` を
  `if res["tracks"]: res["tracks"].pop(0)` で包み、空なら何もしないことで
  例外を防ぐ (以後の `playlistToTracks(res)` は空リストのまま実行され、
  従来通り空のトラック一覧を返す=機能的な回帰なし)。パッチ適用後の生成ソースは
  ast.parse で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix` に ythistory-patch.py の直後に登録しビルド成功、
  生成ソースに新実装が反映されていることを確認。**修正前後の差分の実証**:
  ビルド済み env の `mopidy_ytmusic/library.py` を一時コピーし、
  `get_watch_playlist()` が `{"tracks": []}` を返すよう `FakeBackend` で
  スタブ化した上で `YTMusicLibraryProvider.browse("ytmusic:watch")` を直接
  呼び出すスクリプトで再現 — 修正前(パッチをrevertしたコピー)は
  `IndexError: pop from empty list` が `logger.exception` 経由で
  `mopidy.log` に Traceback として記録された上で `browse()` 自体は
  (呼び出し元 try/except で握り潰され最終行の `return []` に落ちるため)
  `[]` を返す、修正後は同じ入力で Traceback を一切出さず静かに `[]` を返す、
  という差分を確認した (どちらも MPD セッションのクラッシュには至らないが、
  修正によりログノイズが解消される)。さらに dev mopidy(6601, ytmusic
  実アカウント)を実際に起動し MPD で実機確認 — `findadd
  "(any contains \"yoasobi\")"`→`play "0"`(last_id設定)→
  `lsinfo "YouTube Music/Similar to last played"`→実データ6曲がフル情報で
  正常に返り(pop(0)によるシード曲除外を含む通常経路の回帰なし)、
  mopidy.log に本パッチ関連のTraceback/ERRORなし。`status`/`tagtypes`/
  `stop`/`clear`の回帰なしも確認。
- [x] `mopidy_mpd/protocol/stored_playlists.py` の `_check_playlist_name()`
  (`save`/`rename`/`playlistadd`/`playlistclear`/`rm`/`listplaylist`/
  `listplaylistinfo` が共通利用するプレイリスト名バリデータ) が `/`・`\n`・
  `\r` の3文字種しか弾いておらず、空文字列/空白のみの名前
  (`save ""`、`save "   "` 等) を素通ししてしまう不具合。加えて
  `mopidy_mpd/protocol/music_db.py` の `searchaddpl {NAME} ...` はこの
  `_check_playlist_name()` を一度も呼んでおらず、`save`/`rename`/
  `playlistadd`/`playlistclear`/`rm` と非対称にバリデーション自体が
  完全に欠落していた。TODO 全項目消化済みのため自走エージェントが dev
  mopidy を実際に起動し MPD プロトコルを一通り叩いて新規発見した項目
  (最初に着目した `mopidy_ytmusic/library.py` の browse() 内デバッグログ
  `res["songs"]`/`res["tracks"]` 等の素インデックスは、ytmusicapi
  `get_artist()`/`get_playlist()` 等のソースを直接確認したところ該当キーは
  常にデフォルト値でセットされ実際にはKeyErrorになり得ないことが判明し
  誤りと判断、破棄した上での再調査)。
  実害: 空/空白のみの名前で `save`/`searchaddpl` 等を実行すると `OK` が
  返るが、既定の保存先である `mopidy.m3u.playlists`(mopidy core にバンドル、
  パッチ対象外)の `create()`/`save()` は `name.strip()` が空文字列になった
  時点でファイル名が拡張子のみ(例: `.m3u8`)の隠しファイル(dotfile)になる。
  Python の pathlib は先頭がドットのみのファイル名を「拡張子なし」として
  扱う仕様のため、`M3UPlaylistsProvider.as_list()` の
  `entry.suffix not in [".m3u", ".m3u8"]` フィルタに常に弾かれ、この
  プレイリストは `listplaylists`/`listplaylistinfo` に二度と現れず、`rm`/
  `rename` 等の名前引き経路(`context.lookup_playlist_uri_from_name()`は
  as_list() 由来)でも見つけられないため `rm` で消すことも出来ない。
  空/空白違いの複数の名前(`""`/`"   "`/`" "`等)は全て同じ1個の隠しファイル
  へ収束するため、それらを `save` するたびに気付かれないままサイレントに
  上書きされ続ける、永久に不可視・操作不能なゴースト状態になる(rmpc側で
  「新規プレイリスト名」欄が空のまま保存ボタンを押してしまった場合などに
  実際に踏みうる)。実 MPD の C 実装は拡張子付きファイル名を素朴な文字列末尾
  一致で探すため空名前でも一覧に出てくる可能性が高く、この不可視化は
  mopidy 側(pathlib の dotfile 特別扱い)由来の非互換であり、rmpc との
  互換性を保つ本パッチスクリプト群の目的に反する。
  verified: mpdplaylistemptyname-patch.py。実 MPD 互換の「空名前でも一覧に
  出るが分かりにくい」動作を再現するのではなく、他の多数の *guard-patch.py
  と同じく安全側に倒し、`_check_playlist_name()` に空文字列(strip後)
  チェックを追加して `MpdArgError("Bad playlist name")` を送出するよう修正
  (save/rename/playlistadd/playlistclear/rm/listplaylist/listplaylistinfoの
  7コマンドを一括保護)。`searchaddpl` は `stored_playlists.py` が
  `music_db.py` の関数を import する一方向の依存関係(逆方向にすると循環
  import になる)のため `_check_playlist_name()` を import せず、同じ正規
  表現ガードを `music_db.py` 内の `searchaddpl()` 先頭に直接複製して追加。
  パッチ適用後の生成ソースは ast.parse で構文確認、2回適用しても冪等
  (スキップ)であることも確認。`nix/lib/mopidy-env.nix` に
  `mpdrawuriguard-patch.py` の直後に登録しビルド成功、生成ソースに新実装が
  反映されていることを確認した上で dev mopidy(6601, ytmusic実アカウント)を
  実際に起動しMPDで実機確認 — 修正前は `save ""`/`save "   "` がいずれも
  `OK` を返した上で `~/ai/mopidy-dev/data/m3u/.m3u8` という隠しファイルが
  実際に作成され、直後の `listplaylists` には一切現れず `rm ""` も
  `ACK No such playlist` になることをファイルシステムを直接確認して再現
  (`ls -la` で0バイトの `.m3u8` が存在するのに MPD 側からは完全に不可視・
  操作不能であることを実証)。修正後は `save ""`/`save "   "`/
  `rename "soloTest" ""`/`playlistadd "" "ytmusic:track:xyz"`/
  `playlistclear ""`/`rm ""`/`searchaddpl "" any "yoasobi"`/
  `searchaddpl "   " any "yoasobi"` の全てが `ACK [2@0] {cmd} Bad playlist
  name` を返しゴーストファイルの発生自体を防ぐことを確認。回帰確認:
  `save "agent_regress_test"`→`OK`→`rm "agent_regress_test"`→`OK`
  (通常の名前での save/rm は従来通り成功)、`listplaylist ""`/
  `listplaylistinfo ""`(元々 `_check_playlist_name()` を呼ばず
  `_get_playlist()` 直行のため無変更)→`ACK No such playlist`のまま回帰なし。
  `ping`が引き続き`OK`でセッション生存も確認。mopidy.log にTraceback/ERROR
  0件(既存のytmusicテストアカウント起因のノイズのみ)を確認。
- [x] `mopidy_ytmusic/library.py` の `YTMusicLibraryProvider.search()` が
  `query["composer"]`/`["performer"]`/`["comment"]`/`["disc_no"]`/
  `["musicbrainz_albumid"]`/`["musicbrainz_artistid"]`/`["musicbrainz_trackid"]`
  (いずれも `mopidy_mpd/protocol/music_db.py` の `_LIST_MAPPING`/
  `_SEARCH_MAPPING` で正式にマップされた MPD 標準タグ。`_mpd_positive_field_values()`/
  `_mpd_negative_field_values()` 側の post-filter は既にこれら全フィールドを
  実装済み) を一切扱う分岐を持たず、if/elif チェーンのどの条件にも一致しないため
  常に最終 else へ落ちて `return None`(0件)を返してしまう不具合。
  `find`/`search`/`count`/`searchcount` にこれらのタグを指定すると常に
  `OK`(空応答、または `songs: 0`)になり、対象曲が実在してもヒットしない、
  ACKエラーにならないサイレントなデータ不整合。既に3件修正済みの
  `ytsearchgenre-patch.py`(genre)/`ytsearchdate-patch.py`(date)/
  `ytsearchtrack-patch.py`(track_no)と全く同じ「search()の分岐欠落」パターンが、
  未対応のまま残っていた別の7フィールド分。TODO/既知の軽微な残課題を全項目
  消化済みのため自走エージェントが(サブエージェントに調査を委任した上で)
  再調査して新規発見した項目。
  verified: ytsearchmetatag-patch.py。7フィールドをまとめて1つの
  `elif _META_SEARCH_FIELDS.intersection(query):` 分岐で処理し、
  指定された全フィールドの値を連結して `any`/`genre`/`date`/`track_no`
  分岐と同じベストエフォートのテキスト検索(`filter=None`)にフォールバック
  するよう実装(YouTube Musicに真のタグ別絞り込み検索APIは無いため完全な
  等価実装は不可能、常に無条件0件を返す現状よりは有用と判断)。フィールド
  一覧は `_META_SEARCH_FIELDS` というモジュールレベルの `frozenset` 定数に
  一元化。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で
  構文確認、2回適用しても冪等(スキップ)であることも確認(初回実装時に
  MARKER文字列が実際の挿入コード `frozenset(` を含まない不一致で冪等性が
  壊れていたことを2回目適用のテストで検出し、MARKER側を修正して再検証済み)。
  **修正前後の差分の実証**: ビルド前後2つのenv(pre-fix/post-fix)それぞれの
  `mopidy_ytmusic/library.py` を直接 import し、`api.search()` をスタブ化した
  `YTMusicLibraryProvider` インスタンスに対して7フィールド全てで `search()`
  を直接呼び出す比較スクリプトを実行 — pre-fix はスタブAPIが一度も呼ばれず
  (`backend_called=False`)7フィールド全てで無条件 `None` を返す一方、
  post-fix は7フィールド全てでスタブAPIが実際に呼ばれ(`backend_called=True`)
  連結した検索語を伴う結果を返すという差分を実証。`nix/lib/mopidy-env.nix`に
  ytsearchtrack-patch.pyの直後に登録しビルド成功、生成ソースに新実装が
  反映されていることを確認した上で dev mopidy(6601, ytmusic実アカウント)を
  実際に起動しMPDで実機確認 — `find composer "yoasobi"`/`find performer
  "yoasobi"` → 実データ(夜に駆ける/オリオン等)がヒット(修正前は無条件で
  空応答だった分岐)、`find comment "test"`/`find disc "1"`(YouTube Music側に
  意味のある一致が無い語)→ 空応答だが `OK`(ACKエラーにならず、ベストエフォート
  検索として妥当な0件、`genre`/`date`分岐と同じ挙動)、`find musicbrainz_trackid
  "xyz"` → ベストエフォート検索で候補曲がヒット、`count composer "yoasobi"`
  → `songs: 2`/`playtime: 469`(修正前は無条件`songs: 0`)、`searchcount
  performer "yoasobi"` → 同じく`songs: 2`。回帰確認: `tagtypes`(Composer/
  Performer/Comment/Disc/MUSICBRAINZ_*含む全タグタイプ表示、無変更)、
  `find genre "pop"`/`find date "2020"`/`find track "1"`(既存の
  genre/date/track_no分岐)、`list album`、`find artist "YOASOBI"`(実データ
  20件超のアルバム/曲がフル情報で正常応答)、`count any "yoasobi"`、`status`
  の回帰なしを確認。mopidy.log にTraceback/ERROR 0件(既存のytmusicテスト
  アカウント起因のノイズなし、今回はそれも皆無)を確認。
- [x] `mopidy_ytmusic/library.py` の `YTMusicLibraryProvider.browse()` が
  `self.backend.auth` のみを見て `self.backend.oauth` を見ていない箇所が4箇所
  (`"ytmusic:root"` の Home/Artists/Albums 等ディレクトリ追加、`"ytmusic:artist"`
  のアップロード済みアーティスト合流、`"ytmusic:album"` のアップロード済み
  アルバム合流、`"ytmusic:watch"` の未再生時履歴フォールバック) 残っていた
  不具合。`backend.py` の `self.api` 初期化 (`if self.auth and not self.oauth:
  ... elif self.oauth: ...`) や既に修正済みの `self.playlists` 代入
  (ytoauthplaylistguard-patch.py、`if self.auth or self.oauth:`) と異なり、
  `library.py` の `browse()` だけ横展開されずに `self.backend.auth` 単独判定の
  ままだったため、`oauth_json` のみ設定 (`auth_json` は空、
  `self.auth=False, self.oauth=True`) という構成では `self.api` はOAuth認証で
  正しく生成されるのに、`browse("ytmusic:root")` が Home/Artists/Albums/
  Liked Songs/Recently Played/Subscriptions という主要な閲覧用ディレクトリを
  丸ごと欠落させ(`ytmusic:watch` しか残らない)、`ytmusic:artist`/
  `ytmusic:album` はアップロード曲を合流できず、`ytmusic:watch` は同一プロセス
  内でまだ何も再生していない場合に履歴からの種曲取得ができない、というエラーも
  出ないサイレントな機能欠落だった。`search()` は `self.auth` を見ないため無関係に
  動作し、rmpc等のディレクトリブラウザ (`lsinfo` 主経路) だけがこの欠落の影響を
  受ける。TODO/既知の軽微な残課題を全項目消化済みのため自走エージェントが
  (サブエージェントに調査を委任した上で) 再調査して新規発見した項目
  (ytoauthplaylistguard-patch.py が backend.py の `self.playlists` で修正した
  のと全く同型のバグの横展開漏れ)。
  verified: ytoauthlibraryguard-patch.py。`browse()` 内の4箇所とも
  `self.backend.auth` → `self.backend.auth or self.backend.oauth`
  (`ytoauthplaylistguard-patch.py` と同じ条件式) に統一。パッチ適用後の
  生成ソースは一時コピーに当てて `ast.parse` で構文確認、2回適用しても冪等
  (スキップ) であることも確認。**修正前後の差分の実証**: ビルド前後2つの
  env (pre-fix/post-fix) それぞれの `mopidy_ytmusic/library.py` を直接
  import し、`self.auth=False, self.oauth=True` (oauth-onlyのみ設定した構成を
  模した) スタブbackend/API に対して `browse("ytmusic:root")`/
  `browse("ytmusic:artist")`/`browse("ytmusic:album")` を直接呼び出す比較
  スクリプトを実行 — pre-fixは `root` が `['ytmusic:watch']` のみ
  (Home/Artists/Albums欠落)、`artist`/`album` はアップロード分が一切含まれない
  一方、post-fixは `root` に `ytmusic:home`/`ytmusic:artist`/`ytmusic:album`
  が復活し、`artist`/`album` にアップロード分 (`:upload` suffix付きuri) も
  含まれるという差分を実証。`browse("ytmusic:watch")` も同様に
  `playback.last_id is None` のスタブで、pre-fixは `getHistory()` が一度も
  呼ばれず、post-fixは実際に呼ばれることを確認。`nix/lib/mopidy-env.nix` に
  ytoauthplaylistguard-patch.py の直後に登録しビルド成功、生成ソースに
  新実装が反映されていることを確認した上で dev mopidy (6601, ytmusic
  実アカウント=auth_json構成) を実際に起動しMPDで実機確認 —
  auth_json構成(`self.auth=True, self.oauth=False`)では
  `self.auth or self.oauth` は既存の `self.auth` 単独判定と真偽値が一致する
  ため、`lsinfo "YouTube Music"` → Home/Artists/Albums/Liked Songs/
  Recently Played/Subscriptions/Similar to last played/Mood and Genre
  Playlists/Auto Playlists の全ディレクトリが従来通り表示され回帰なしを確認。
  `lsinfo "YouTube Music/Artists"`/`lsinfo "YouTube Music/Albums"`も正常応答
  (該当データ無しでOKのみ)。旧来の`tagtypes`/`status`/`listplaylists`の回帰
  なし・mopidy.log にTraceback/ERROR 0件を確認。
- [x] `addid {URI}` (mopidy_mpd/protocol/current_playlist.py) と `playlistadd {NAME} {URI}`
  (mopidy_mpd/protocol/stored_playlists.py) が、兄弟コマンド `add {URI}` とは異なり、
  docstring/仕様上許容されている「スキーム無しの生パス文字列」(例: `addid "foo.mp3"`)を
  無検証のまま `context.core.tracklist.add(uris=[uri])`/`context.core.library.
  lookup(uris=[track_uri])` へ直接渡してしまう不具合。`add()` は
  `urllib.parse.urlparse(uri).scheme != ""` を事前チェックし、スキーム無しなら
  `context.browse(uri, lookup=False)` 経由で解決してから常にスキーム付きURIに
  変換した上で `tracklist.add()` を呼ぶ安全な設計だが、`addid()`/`playlistadd()`
  にはこのガードが無かった。mopidy.core.TracklistController.add()/
  LibraryController.lookup() は内部で `mopidy.internal.validation.
  check_uris()`/`check_uri()` を呼んでおり、スキーム無しURIには
  `mopidy.exceptions.ValidationError`(`ValueError`のサブクラス、mopidy_mpd
  独自の`MpdAckError`系統ではない)を送出する。`mopidy_mpd/dispatcher.py`の
  `handle_request()`は`except exceptions.MpdAckError`と
  `except pykka.ActorDeadError`しか捕捉しないため、この`ValidationError`は
  pykka actorを未捕捉例外のまま突き抜け、当該コネクションが応答無しで即切断
  されてしまう。mpdrawuriguard-patch.pyが`readcomments`/`lsinfo`の生URI
  フォールバックで修正したのと全く同型のバグだが、`addid`/`playlistadd`へは
  横展開されていなかった。TODO/既知の軽微な残課題を全項目消化済みのため
  自走エージェントが(サブエージェントに調査を委任した上で)再調査して
  新規発見した項目。
  verified: mpdaddidrawuriguard-patch.py。mpdrawuriguard-patch.pyと同じ
  変換方針で`ValidationError`を捕捉し「そんな曲は無い」に丸める。
  `addid()`/`playlistadd()`はいずれも直後に既存の空チェック
  (`if not tl_tracks`/`if not new_tracks`)で`exceptions.MpdNoExistError(
  "No such song")`を送出する構造のため、捕捉時に空のtracklist/lookup結果を
  返すだけで既存の空チェックにそのまま委譲できる設計にした(追加のACK変換
  コード不要)。current_playlist.py/stored_playlists.pyはそれぞれ独立
  モジュールでヘルパーは共有せず(循環import回避、mpdplaylistemptyname-
  patch.pyと同じ理由)各ファイルへ直接複製。パッチ適用後の生成ソースは
  一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)
  であることも確認(初回実装時にMARKER文字列がtry/except間に挟まる
  コメント行と不一致で冪等性が壊れていたことを2回目適用のテストで検出し、
  MARKER側を修正して再検証済み)。`nix/lib/mopidy-env.nix`に
  mpdrawuriguard-patch.pyの直後に登録しビルド成功、生成ソースに新実装が
  反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)を
  実際に起動しMPDで実機確認 —
  `addid "some/relative/path.mp3"`(スキーム無し生パス)→
  `ACK [50@0] {addid} No such song`となりセッション切断されず、続く`status`
  も正常応答(旧実装ならここで素の`ValidationError`によりコネクションが
  切断されていた)。`playlistadd "rawuritestpl" "some/relative/path.mp3"`
  (同様のスキーム無し生パス)→同じく`ACK [50@0] {playlistadd} No such song`
  でセッション生存、後続`status`も正常応答(プレイリストも作成されない
  ことを`rm`が`ACK No such playlist`を返すことで確認)。
  **修正前後の回帰確認**: 実データ検索(`search artist "YOASOBI"`)で得た
  実在のスキーム付きURI(`ytmusic:artist:...`)での`addid`→`Id: 1`で成功、
  同URIでの`playlistadd "rawuritesthappy" ...`→`OK`で成功し
  `listplaylistinfo`で実トラックが正しく反映されていることを確認(happy
  pathの回帰なし)。スキーム付きだが存在しないURI
  (`addid "ytmusic:track:doesnotexist12345"`)→従来通り
  `ACK [50@0] {addid} No such song`(既存のgetTrack()内try/except経由の
  正常なエラーハンドリング、無変更)。旧来の`tagtypes`/`listplaylists`の
  回帰なしを確認。mopidy.logのTraceback/ERRORは、上記の存在しないtrackId
  lookup失敗と、テストアカウントの新規プレイリスト作成権限不足による
  既知のHTTP失敗(mpdplaylistemptyname-patch.py等の検証時にも確認済みの
  pre-existingな挙動)の2件のみで、新規リグレッションでないことを確認した。
- [x] `mopidy_ytmusic.library.YTMusicLibraryProvider.browse()`の`ytmusic:artist`/
  `ytmusic:album`分岐(通常+アップロード計4箇所)と`mopidy_ytmusic.playlist.
  YTMusicPlaylistsProvider.as_list()`が、`get_library_artists()`/
  `get_library_upload_artists()`/`get_library_albums()`/`get_library_upload_albums()`/
  `get_library_playlists()`をいずれも`limit=100`固定で呼んでおり、フォローアーティスト/
  保存アルバム/保存プレイリスト/アップロード済みアーティスト・アルバムのいずれかが
  100件を超えるアカウントで、rmpcから`lsinfo "YouTube Music/Artists"`/
  `lsinfo "YouTube Music/Albums"`/`listplaylists`を送ると101件目以降がエラーも
  ログも無く静かに消える不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (2回のサブエージェント調査委任を経て)改めてmopidy_ytmusicのコード品質を再調査して
  発見した項目。
  verified: ytlibrarylimit-patch.py。ytmusicapi 1.12.0の`get_library_playlists`/
  `get_library_upload_albums`/`get_library_upload_artists`はdocstringで
  「`limit=None`で全件取得」と明記、`get_library_albums`/`get_library_artists`も
  内部の`parse_library_albums`/`parse_library_artists`(ytmusicapi/parsers/library.py)が
  `remaining_limit = None if limit is None else ...`として`limit=None`を素通しし
  continuationを尽きるまで辿る実装であることをソースで確認した上で、該当5箇所を
  `limit=None`へ変更。`get_distinct()`(list/countのgroup列挙経路、ytdistinct-patch.py)は
  既に同じAPI呼び出しにconfig可変の`self.backend.playlist_item_limit`を使っており、
  browse()/as_list()側だけが固定100のままという非対称性があった(`playlist_item_limit`を
  増やしても実際のブラウズ結果は100件で頭打ちのままという実害の筋道を確認)。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`に登録しビルド成功、
  生成ソースに新実装が反映されていることを確認した上でdev mopidy(6601, ytmusic
  実アカウント)を実際に起動しMPDで実機確認 — `tagtypes`/`status`が正常応答しクリーンに
  起動(回帰なし)、`lsinfo "YouTube Music/Artists"`/`lsinfo "YouTube Music/Albums"`/
  `listplaylists`も従来通り正常応答(実アカウントはフォロー0件・保存アルバム0件・
  プレイリスト4件のみで100件超は再現できないため、これは回帰なし確認)。
  **修正前後の差分の実証**: ビルド前後2つのenv(pre-fix/post-fix)それぞれの
  `mopidy_ytmusic/library.py`/`playlist.py`を直接importし、150件のartists/upload_artists/
  albums/upload_albums、150件のplaylistsを返すスタブAPI(`limit`指定時は先頭`limit`件、
  `limit=None`時は全件を返す)に対して`browse("ytmusic:artist")`/`browse("ytmusic:album")`/
  `as_list()`を直接呼び出す比較スクリプトを実行 — pre-fixはartists 200件
  (150+150を100+100に切り捨て)/albums 200件(同様)/playlists 100件(150件を切り捨て)、
  post-fixはartists 300件/albums 300件/playlists 150件と全件取得できることを実証。
  mopidy.logにTraceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic.library.py`の`addThumbnails()`(self.IMAGESキャッシュへサムネイル
  URL/解像度を積む共通ヘルパー)が、各サムネイル要素の`"width"`/`"height"`を`.get()`
  ではなく直接インデックス(`th["width"]`, `th["height"]`)で取得しており、`"url"`は
  持つが`"width"`/`"height"`を欠くサムネイル要素(YouTube側のサムネイル配列に実在する
  形状)が1つでも含まれていると`KeyError`を送出する不具合。`ytimages-patch.py`が
  `playlistToTracks()`に新設したサムネイルキャッシュ処理では既に`.get()`を使っており
  (同種のリスクを認識した書き方)、`addThumbnails()`自体だけがこの防御を欠いていた。
  この`KeyError`は呼び出し元2箇所でいずれも無防備(try/exceptで保護されていない)ため
  深刻な実害になる: (1)`albumToTracks()`は全曲をTrackに変換しretに積み終えた後、
  末尾で`self.addThumbnails(bId, album)`を呼ぶ。ここで例外が起きると
  `ytunavailabletrack-patch.py`が個々の曲を守るtry/exceptの"外側"で関数全体が中断し
  `return ret`に到達しないため、既に成功していたN曲分のパース結果ごと失われ、
  呼び出し元browse()/lookup()の粗い`except Exception: logger.exception`がこれを
  飲み込むためrmpc等のMPDクライアントには「0曲のアルバム」として映る。`get_album(bId)`
  は同じデータを毎回返すため一過性ではなく決定論的に再現する。(2)`getTrack()`は
  `self.TRACKS[bId]`へ書き込んだ直後に`self.addThumbnails(bId, tv["thumbnail"])`を
  無防備に呼んでおり、例外時は`return self.TRACKS[bId]`に到達せず「そんな曲は無い」
  ように見える(addid等がACK No such songを返す)上、`self.TRACKS[bId]`への書き込み
  自体は既に完了しているため次回同じbIdでの呼び出しは`if bId not in self.TRACKS:`
  ブロック全体(addThumbnails呼び出し含む)をスキップし正常に返るという「初回だけ
  失敗する」奇妙な挙動になる。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (サブエージェントに調査を委任した上で)再調査して新規発見した項目。
  verified: ytthumbnailguard-patch.py。(a) `addThumbnails()`内のwidth/height取得を
  `ytimages-patch.py`と同じ`.get()`に修正(根本原因)。(b) `albumToTracks()`/
  `getTrack()`末尾の`addThumbnails`呼び出しをそれぞれ個別のtry/exceptで隔離し、
  サムネイル取得の失敗が既に完成しているトラック一覧/Trackオブジェクトの返却を
  道連れにしないようにした(`ytcipherfail-patch.py`/`ytscrobble-patch.py`と同じ
  「1回限りの外部データ依存呼び出しをtry/exceptで隔離する」流儀)。既存の`addThumbnails`
  関連パッチ(`ytimages-patch.py`/`ytunavailabletrack-patch.py`)は width/height の
  直接インデックスにも呼び出し元2箇所の無防備さにも触れていないことをソース照合で確認
  (重複なし)。パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`に
  `ytlibrarylimit-patch.py`の直後に登録しビルド成功、生成ソースに新実装が反映されて
  いることを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に起動し実機確認。
  **修正前後の差分の実証**: ビルド前後2つのenv(pre-fix/post-fix)それぞれの
  `mopidy_ytmusic/library.py`を直接importし、`"url"`のみで`"width"`/`"height"`を
  欠くサムネイルを含む album dict に対して`albumToTracks()`を、同形状のdataに対して
  `addThumbnails()`を直接呼び出す比較スクリプトを実行 — pre-fixは両方とも
  `KeyError: 'width'`を送出(albumToTracksは1曲も返せずクラッシュ)、post-fixは
  `albumToTracks`が1トラック正常返却・`addThumbnails`も正常完了することを実証。
  実アカウントでの回帰確認: `search artist "YOASOBI"`→実在アルバムURI取得→
  `lsinfo "ytmusic:album:MPREb_J6ZM1JTtGfj"`→トラック情報(Artist/Album/Title/Date/
  Track/AlbumArtist等)が正常返却されることを確認(通常のwidth/height完備サムネイルの
  アルバムで回帰なし)。`tagtypes`/`status`/`listplaylists`も正常応答しクリーンに
  起動、mopidy.logのTraceback/ERRORは0件を確認した。
- [x] `mopidy_ytmusic/playlist.py`の`YTMusicPlaylistsProvider.save()`が、実プレイリストの
  生レスポンス`pls["tracks"]`(削除/非公開/地域制限で再生不能になった曲=videoIdが偽値の
  ものを含む)から`oldCounts`/`setVideoIdByVideoId`/削除候補列挙を作る一方、目的の並び
  `newOrder`は`playlist.tracks`(=`playlistToTracks()`でフィルタ済み、
  `ytunavailabletrack-patch.py`により再生不能曲は最初から含まれない)から作るという
  非対称性を持ち、再生不能曲を「ユーザーが取り除いた曲」と誤認して
  `remove_playlist_items()`へ実際に送信してしまう不具合。`playlistadd`/
  `playlistdelete`/`playlistmove`/`rename`等`core.playlists.save()`を経由するあらゆる
  MPDコマンドが、そのプレイリストに1曲でも再生不能曲を含んでいれば、ユーザーが一切
  意図していないのにその曲を実際にYouTube Music側から削除しうるデータ破壊的な不具合
  (ytmusicapiの`remove_playlist_items()`は`videoId`キーの有無しか見ておらず値が`None`でも
  フィルタを通過しsetVideoId経由の削除リクエストが実際に送信されることをソースで確認)。
  TODO/既知の残課題を全項目消化済みのため自走エージェントが(サブエージェントに調査を
  委任した上で)再調査して新規発見した項目。
  verified: ytplaylistunavailableguard-patch.py。`oldCounts`/`setVideoIdByVideoId`/
  削除候補列挙の対象を`pls["tracks"]`から、videoIdが真値の曲のみに絞った
  `availableTracks`に置き換え(`newOrder`側と対象集合を揃える)。既存の
  `ytplaylistreorder-patch.py`/`ytplaylistdup-patch.py`/`ytaddresultcheck-patch.py`/
  `ytremoveresultcheck-patch.py`/`ytplaylisteditcheck-patch.py`/
  `ytdeleteplaylistcheck-patch.py`をgrepし、いずれも`videoId`偽値/`isAvailable`には
  一切触れておらずこの問題が未対応だったことを確認(重複なし)。パッチ適用後の生成
  ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)で
  あることも確認。**修正前後の差分の実証**: 実アカウントを変更する破壊的操作は
  スコープ外のため、pre-fix/post-fixの2つのenvそれぞれの`mopidy_ytmusic/playlist.py`を
  直接importし、実プレイリストの生レスポンスを模したスタブ`api`(利用可能曲2件+
  videoId無しの再生不能曲1件を返す`get_playlist`、呼び出しを記録する
  `remove_playlist_items`/`add_playlist_items`/`edit_playlist`)に対し、ユーザーが
  並び順を一切変えず(再生不能曲を含まない`playlist.tracks`のまま)`save()`を呼ぶだけの
  比較スクリプトを実行 — pre-fixは`remove_playlist_items(bId, [videoId=None])`が
  実際に呼ばれる(ユーザーが何も変更していないのに削除が発生)ことでバグを再現、
  post-fixは`remove`/`add`/`edit`いずれも呼ばれないことを確認。`nix/lib/mopidy-env.nix`に
  `ytthumbnailguard-patch.py`の直後に登録しビルド成功、生成ソースの
  `oldCounts`/`setVideoIdByVideoId`/削除候補列挙が`availableTracks`を参照するよう
  反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDで実機確認 — `status`/`tagtypes`/`listplaylists`/`lsinfo "YouTube Music"`が
  正常応答しクリーンに起動(回帰なし)、mopidy.logのTraceback/ERRORは0件を確認した
  (プレイリスト保存を伴う書き込み系コマンドは実アカウントのプレイリストを変更する
  破壊的操作のためスコープ外、読み取り専用コマンドのみで確認)。
- [x] `mopidy_ytmusic/playback.py`の`YTMusicPlaybackProvider`が`mopidy.backend.PlaybackProvider`の
  `is_live()`/`should_download()`を一切オーバーライドしておらず、基底クラスの既定実装
  (`mopidy/backend.py`: 常に`False`を返す、"MAY be reimplemented by subclass"と明記)の
  ままになっていた不具合。`change_track()`(playback.py)は実際に
  `self.audio.set_uri(uri, live_stream=self.is_live(uri), download=self.should_download(uri))`
  という形でこの2メソッドの戻り値をGStreamer側へ渡しているため、`is_live()`が常に`False`だと
  現在配信中のライブ動画(YouTube Musicの検索/browse結果に混ざりうるライブコンサート・
  常時配信ラジオ的トラック)も「有限長ファイル」としてバッファリングされてしまう
  (live_stream=Trueは GStreamer側のバッファリング無効化・一時停止時のデータ破棄という
  実際の再生系への差分を持つ、`is_live()`のdocstring参照)。TODO/既知の残課題を全項目
  消化済みのため自走エージェントが(サブエージェントに調査を委任した上で)再調査して
  新規発見した項目。
  verified: ytlivestream-patch.py。実際にこのリポジトリのenvに同梱のyt-dlp
  (`yt_dlp/extractor/youtube/_video.py`)をソース確認し、公開動画抽出コードが
  info dictに`live_status`("is_live"/"was_live"/"post_live"/"is_upcoming"/"not_live")と
  `is_live`(bool)を実際にセットすることを確認(4178行目`'live_status': live_status`、
  `YoutubeDL.py`2794-2798行目がlive_status欠落時にis_live/was_liveから補完する処理も確認)。
  既存のplaywback.py関連パッチ(ytdlp/ytcipherfail/ytaudioformat/ytsongformat/
  ytverifytrackurl)を`grep -n "is_live\|should_download\|live_status"`した結果0件で
  live系には一切未着手だったことを確認した上で着手。change_track()がis_live(uri)を
  呼ぶ際のuriは`self.translate_uri(track.uri)`の戻り値(=`_get_track()`が返す解決済み
  ストリームURL)そのものであり、ytaudioformat-patch.pyの`_audio_format`/
  `_audio_format_uri`と同じ「直近1件のみ」の揮発性キャッシュで十分(change_trackは
  translate_uri()完了を待ってから同期的にis_live()/should_download()を呼ぶため
  複数トラックの解決処理と競合しない)と判断し、`_get_track()`のURL解決成功時に
  `info.get("is_live")`/`info.get("live_status")`から実際のライブ判定を
  `self._ytlive_url`/`self._ytlive_is_live`へ記録、新設した`is_live(uri)`は引数が
  この直近解決結果と一致する時だけその値を返す(不一致なら安全側のFalse)よう実装。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。**修正前後の差分の実証**: 実際のYouTube Music
  API呼び出しを伴わない形で、pre-fix/post-fixの2つのenvそれぞれの
  `mopidy_ytmusic/playback.py`を直接importし(`mopidy_ytmusic`/`yt_dlp`をスタブ化)、
  `is_live: True`/`live_status: "is_live"`を含む偽のyt-dlp info dictに対して
  `translate_uri()`→`is_live(uri)`を呼ぶ比較スクリプトを実行 — pre-fixは
  `is_live(uri)`が常に`False`(基底クラスの既定実装のまま)、post-fixは`True`を
  正しく返すことを実証。`nix/lib/mopidy-env.nix`に`ytplaylistunavailableguard-patch.py`
  の直後に登録しビルド成功、生成ソースに新実装(`_ytlive_url`/`_ytlive_is_live`/
  `is_live()`)が反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)
  を実際に起動しMPDで実機確認 — `tagtypes`/`status`/実データ`search artist "YOASOBI"`
  (アーティスト/アルバム/曲51件)が正常応答しクリーンに起動(回帰なし)、実在の非ライブ曲
  (`ytmusic:track:m9SMT5ipbxk`、YOASOBI「アイドル」)を`add`+`play`で実際に再生開始
  (この曲は`is_live=False`のため`live_stream=False`のまま、既存の非ライブ再生経路には
  一切影響しないことを確認)、`status`→`state: play`/`audio: 48000:16:2`
  (ytaudioformat-patch.pyの記録も無傷)で正常再生継続、mopidy.logのTraceback/ERRORは
  0件を確認した(現在実際に配信中のライブ動画のvideoIdを安定して用意することは
  スコープ外の探索が必要なため、実アカウントでのlive_stream=True自体の実地確認は
  上記の差分実証テストで代替、非ライブ経路の無傷確認は実アカウントで実施)。
- [x] `setvol {VOL}` (`mopidy_mpd/protocol/playback.py`) が範囲外(0-100外、負数含む)の
  VOLをエラーにせず `min(max(0, volume), 100)` で無条件にクランプしてしまう不具合。
  TODO/既知の残課題を全項目消化済みのため自走エージェントが(サブエージェントへ2回の
  調査委任を経て)再調査して新規発見した項目。
  verified: mpdsetvolrange-patch.py。実MPD本体 (MusicPlayerDaemon/MPD, WebFetchで
  直接ソース確認) の `src/command/OtherCommands.cxx handle_setvol` は
  `args.ParseUnsigned(0, 100)` を経由し、`src/protocol/ArgParser.cxx
  ParseCommandArgUnsigned(s, max_value)` が `strtoul(s, &endptr, 10)` の後
  `value > max_value` なら `MakeArgError("Number too large")` を投げてコマンド自体を
  拒否する(音量は変更されないまま)。`strtoul` は先頭 `-` を巨大な unsigned 値へ
  ラップするため `setvol -5` のような負数も同じ経路で弾かれる。よって実MPDでは
  `setvol 999`/`setvol -5` はいずれも `ACK [2@0] {setvol} Number too large` を返すのが
  仕様だが、mopidy_mpd はエラーにならず黙って100/0へ丸めていた。同ファイル内の兄弟
  コマンド `volume {CHANGE}` (相対音量変更) は既に `if change < -100 or change > 100:
  raise exceptions.MpdArgError(...)` で入力自体を検証してから使っており
  (クランプするのは"変更後の絶対値"の方)、`setvol` だけ入力そのものの範囲チェックを
  欠くという非対称性があった。`mpdgetvol-patch.py` の検証時点 (本BACKLOG既出) では
  `setvol 999` のクランプ挙動を確認した上で「既存のmopidy-mpd実装通りでエラーに
  ならない」と回帰なしの文脈でのみ記録され、実MPD本体のソースとの突き合わせがされて
  いなかったため見落とされていた。修正: `MpdArgError("Number too large")` は
  `mpdaddid-patch.py`/`mpdaddpos-patch.py`/`mpdmoveto-patch.py` 等が POSITION の
  範囲外で既に使っている本リポジトリの既存の流儀に揃え、`setvol` の先頭で
  `volume < 0 or volume > 100` を検査し範囲外なら即座に拒否するよう変更(範囲内は
  従来通り無変更)。パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  mpdPatched末尾に登録しビルド成功、生成ソースに新実装が反映されていることを確認した
  上でdev mopidy(6601)を実際に起動しMPDで実機確認 — `setvol 40`→OK・`getvol`→
  `volume: 40`、`setvol 999`→`ACK [2@0] {setvol} Number too large`・直後`getvol`→
  `volume: 40`(変更前のまま維持)、`setvol -5`→同じくACK・`getvol`→`volume: 40`
  (変更前のまま維持)、境界値`setvol 0`→OK・`getvol`→`volume: 0`、`setvol 100`→OK・
  `getvol`→`volume: 100`(0/100自体は従来通り正常に設定可能、回帰なし)、非数値
  `setvol abc`→従来通り`ACK [2@0] {setvol} incorrect arguments`(既存の引数パース
  エラーメッセージ・経路は無変更)。回帰確認: 兄弟コマンド`volume 10`(相対)→OK、
  範囲外`volume -200`→従来通り`ACK [2@0] {volume} Invalid volume value`で無変更、
  `tagtypes`/`status`も正常応答しクリーンに起動、mopidy.logのTraceback/ERRORは0件を
  確認した。
- [x] `mopidy_ytmusic/playback.py` の `_get_track()` が曲のサンプルレート/チャンネル数
  (`status` の `audio` フィールド、`ytaudioformat-patch.py` が導入した揮発性ストア)を
  `if asr and channels:` の中でしか `translator.set_audio_format()` を呼ばずに記録して
  おり、新しく解決した曲の yt-dlp info dict に `asr`/`audio_channels`
  (`requested_formats` 経由のフォールバックも含め)が一切含まれない場合、
  `set_audio_format()` の呼び出し自体がスキップされ、`_audio_format`/`_audio_format_uri`
  が「直前に解決できた別の曲」の値のまま無期限に(次に取得に成功する曲へ切り替わるまで)
  残留してしまう不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (サブエージェントへ2回の調査委任を経て)再調査して新規発見した項目。
  verified: ytaudioformatstale-patch.py。`mpdaudioformat-patch.py`/`ytaudioformat-patch.py`
  検証時点では「曲切替のたびに新曲のasr/channelsが必ず取得できる」前提だったが、直前に
  追加された `ytlivestream-patch.py` のライブ配信対応により、フォーマット解決自体は成功
  するがHLS系フォーマットのためasr/audio_channelsを含まない曲が実際に発生しうるように
  なり、この前提が破綻していた(ライブ配信に限らず、yt-dlpがこれらのキーを提供できない
  任意のフォーマット解決でも同様に発生しうる)。`mopidy_mpd/protocol/status.py` の
  `_status_audio()` は `translator.get_audio_format()` を現在再生中の曲のuriと一切
  突き合わせず無条件に返す設計のため、古い曲のサンプルレート/チャンネル数がstatusに
  表示され続け、同時刻の`currentsong`/`playlistinfo`の`Format`タグ(uri一致時のみ返す
  設計、こちらは不一致のため正しく欠落する)と矛盾する状態になる。修正:
  `ytlivestream-patch.py`の`_ytlive_url`/`_ytlive_is_live`と同じ「新しく解決した曲のuriを
  必ず記録し、値が不明ならNoneにする」設計に揃え、`if asr and channels:`の条件分岐を
  外してset_audio_format()を常に(新曲のuriを伴って)呼び、値はasr/channelsが両方取れた
  時だけ実フォーマット文字列、それ以外はNoneにするよう変更(`get_audio_format()`が
  Noneを返せば`status.py`の既存の`if audio_format:`でaudioフィールド自体を出さない、
  mpdaudioformat-patch.py側は無変更)。パッチ適用後の生成ソースは一時コピーに当てて
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  **差分の実証**: 実際のYouTube Music API呼び出しを伴わない形で、pre-fix/post-fixの
  2つのenvそれぞれの`mopidy_ytmusic/playback.py`を直接importし(yt_dlp.YoutubeDLを
  スタブ化)、track A(asr=48000/audio_channels=2あり)→track B(asr/channels無し、
  ライブHLS系フォーマットを模擬)の順で`_get_track()`を呼ぶ比較スクリプトを実行 —
  pre-fixは`translator.get_audio_format()`がtrack B再生中もtrack Aの`"48000:16:2"`を
  返し続ける(バグ再現)、post-fixは正しく`None`を返す(修正確認)ことを実証。
  `nix/lib/mopidy-env.nix`にytlivestream-patch.pyの直後に登録しビルド成功、生成ソースに
  新実装が反映されていることを確認した上でdev mopidy(6601、ytmusic実アカウント)を実際に
  起動しMPDで実機確認(回帰確認) — 実在の通常曲2曲(`ytmusic:track:m9SMT5ipbxk`
  YOASOBI「アイドル」→`ytmusic:track:qivRUhepWVA`「怪物」、いずれもasr/channels取得
  成功)を順に`add`+`play`/`next`で切り替え、各曲で`status`→`audio: 48000:16:2`・
  `currentsong`→`Format: 48000:16:2`が両曲とも正しく曲ごとの値で一致し続けることを
  確認(通常曲同士の切替では従来通り無変更・回帰なし)、mopidy.logのTraceback/ERRORは
  0件を確認した(実際に現在配信中でasr/channels欠落のライブ動画のvideoIdを安定して
  用意することはスコープ外の探索が必要なため、その具体的なフォーマット欠落パス自体の
  実地確認は上記の差分実証テストで代替)。
- [x] `mopidy_ytmusic/library.py` の `search()` は query に `"album"` タグが含まれていても、
  `filter="albums"` で叩いたYTMusic検索結果を `parseSearch()` に渡すのみで、
  `parseSearch()` の `resultType=="album"` 分岐はマッチしたアルバムを
  `SearchResult.albums`(ブラウズ用プレースホルダ)へ積むだけで `SearchResult.tracks`
  には一切何も追加しない。一方 `mopidy_mpd/protocol/music_db.py` の `find()` は
  「`"album"` が query にある時は `_album_as_track()` によるプレースホルダ変換をせず
  `_get_tracks(results)` の実トラックを返す」設計(docstring 通り GMPC の
  `find album "X" artist "Y"` でアルバムの曲一覧を取得する用途を明記)。実トラックが
  一切供給されないため `find album "X"`(該当アルバムが実在していても)は常に
  コマンド自体は成功(OK)しつつ0件を返す不具合。`count album "X"` も同じ
  `library.search()` を経由するため同様に常に `songs: 0` になっていた。加えて query に
  `"album"` と `"artist"`/`"albumartist"` が両方含まれる場合、既存の分岐順序
  (`elif "albumartist"/"artist"` が `"album"` より先の判定)により artist 側
  (`filter="artists"`、`get_artist()` の albums/singles/songs 一覧のみを走査)が優先され、
  アルバム名は一切バックエンド検索に使われない非対称もあった。TODO/既知の残課題を
  全項目消化済みのため自走エージェントが(Exploreサブエージェントへの調査委任を経て)
  `mopidy_mpd/protocol/*.py` と `mopidy_ytmusic/*.py` を横断的に再調査して新規発見した
  項目。
  verified: ytfindalbumtracks-patch.py。`library.py` の `search()` 内で `album` 分岐を
  `albumartist`/`artist` 分岐より先に判定するよう順序を入れ替え(`find album "X" artist
  "Y"` がアルバム起点の検索を使うようにする)、かつ `parseSearch()` が返した
  `SearchResult.albums` のうち実際に `query["album"]` に一致するもの(exact時は
  casefold完全一致、非exact時は仕様通りcasefold部分一致)だけを対象に、既存の
  `albumToTracks()`(`browse()` の `ytmusic:album:<id>` 展開・`ytalbumtrackartist-patch`
  適用済みで曲別アーティストも正しく持つ、と同一の関数)で実際の曲一覧を取得し
  `SearchResult.tracks` へ追加するよう実装。一致判定を挟まず全 `SearchResult.albums`
  を無条件展開する初版を最初に実装したところ、非exact(`search`)時は `parseSearch(res)`
  がfield指定無し(絞り込み無し)でYTMusicの `filter="albums"` 検索結果を丸ごと
  `SearchResult.albums` へ積むため、`"the book for,"` のような部分一致クエリで無関係な
  十数アルバム分の全曲(数百曲、get_album() API呼び出しも多数)を無駄に展開し、かつ
  実際にはWHATを含まない誤った曲まで結果に混入する重大な回帰を実機テストで検出、
  上記の一致フィルタで修正した。パッチ適用後の生成ソースは一時コピーに当てて
  `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。`nix/lib/
  mopidy-env.nix` に `ytaudioformatstale-patch.py` の直後に登録しビルド成功、生成ソースに
  新実装が反映されていることを確認した上で dev mopidy(6601、ytmusic実アカウント)を
  実際に起動しMPDで実機確認 — 実在のアルバム(YOASOBI「THE BOOK for,」、12曲)に対し
  `find album "THE BOOK for,"` → 修正前は0件だったのが12曲全てをTrack/Album/AlbumArtist
  付きで正しく返す、`find artist "YOASOBI" album "THE BOOK for,"`(組み合わせクエリ)→
  同じく12曲(分岐順序入れ替えの効果を確認)、`count album "THE BOOK for,"` →
  `songs: 12`・`playtime: 2552`(修正前は`songs: 0`)、`find album "THE BOOK for,"
  artist "NoSuchArtistXYZ"`(実在しないアーティストとの組み合わせ)→ 正しく0件
  (`_mpd_filter_positives`側のartist厳密一致で除外)、存在しないアルバム
  `find album "NoSuchAlbumXYZ123"` → OK・0件のまま(エラーにならない、回帰なし)。
  回帰確認: `search album "the book for,"`(部分一致、大文字小文字区別なし)→
  既存のアルバムプレースホルダ20件(修正前と同じ、無関係アルバムも含め無条件、既存の
  設計のまま)に加え、実際に一致するYOASOBIの12曲のみが正しく追加され他の19アルバムは
  展開されない(誤混入なし)ことを確認、`find artist "YOASOBI"`(単独、artist分岐)・
  `search any "YOASOBI"`・`list album artist "YOASOBI"`・実データ
  (`ytmusic:track:m9SMT5ipbxk`)の`add`+`play`+`status`+`stop`+`clear`・`tagtypes`も
  正常応答しクリーンに起動、mopidy.logのTraceback/ERRORは0件を確認した。
- [x] `mopidy_mpd/translator.py` の `_audio_format`/`_audio_format_uri` (status の
  `audio` フィールド・曲メタデータの `Format` タグ共用の揮発性ストア、
  mpdaudioformat-patch.py/mpdsongformat-patch.py 実装) は「直近に解決した1曲分」しか
  覚えない単一値の設計だった。一方 mopidy core の gapless 先読み
  (`mopidy/core/playback.py` の `_on_about_to_finish()`、現在曲Aがまだ再生完了する
  前に次曲Bの`backend.playback.change_track()`を呼ぶ、L184-205) と、明示的な
  `play()`/`playid()` (`PlaybackController._change()`、`_pending_tl_track`にセット
  してから`change_track()`→`play()`を呼ぶ、L330-352) はいずれも、実際に現在曲として
  確定する(`_current_tl_track`への昇格、`_on_stream_changed()`でのみ行われる、
  L130-143)より前に`change_track()`を呼ぶ設計。`mopidy_ytmusic/playback.py`の
  `_get_track()`(ytaudioformat-patch.py/ytaudioformatstale-patch.py)はこの
  `change_track()`の中で同期的に`set_audio_format(fmt, uri=B)`を呼ぶため、Aがまだ
  実際に鳴っている間にストアがBの値で上書きされてしまう。結果、Aの再生完了前の
  この窓では`status`の`audio`はBのフォーマット(またはB未取得ならNone)を返す一方、
  `currentsong`/`playlistinfo`の`Format`タグはuri不一致(ストアは既にBのuri)のため
  Aの値がサイレントに消える——「Aを再生中」と報告しつつAの音声フォーマット情報だけ
  先に失われる内部矛盾が生じていた。TODO/既知の残課題を全項目消化済みのため自走
  エージェントが(Exploreサブエージェントへの調査委任を経て)再調査して新規発見した項目。
  既存のBACKLOG項目`mpdseekplayerrace`(blocked)とは異なり、あちらは
  `_pending_tl_track`/`_current_tl_track`のどちらが「意図した曲」かをMPD層から
  同期的に見分ける必要があり mopidy core に公開APIが無くスコープ外だったのに対し、
  本件は「曲(uri)ごとに別々の値を覚える」だけで mopidy core の昇格タイミングを
  一切問わずに mopidy_mpd 側だけで解決できるため、区別して対応した。
  verified: mpdaudioformatpreload-patch.py。translator.pyの単一値ストアを
  uriをキーとした辞書キャッシュ(`_audio_format_cache`、最大8件、古い順に破棄)へ
  置換し、`set_audio_format(value, uri)`は該当uriのエントリのみ更新(他のuriの値は
  無傷)、`get_song_audio_format(uri)`はそのuriのエントリのみ返すよう統一。
  `status.py`の`_status_audio()`も(`_status_bitrate()`と同じ流儀で)
  `futures["playback.current_tl_track"]`から現在曲のuriを取り、そのuriの値を
  返すよう変更(「直近の1件」ではなく「現在曲の値」に統一)。パッチ適用後の生成
  ソースは一時コピーに当ててast.parseで構文確認、2回適用しても冪等(スキップ)で
  あることも確認。`nix/lib/mopidy-env.nix`にmpdsongformat-patch.pyの直後に登録し
  ビルド成功、生成ソースに新実装が反映されていることを確認した。
  **差分の実証**: 実際のasr/channelsが異なる2曲を安定して用意することはスコープ外の
  探索が必要なため、pre-fix/post-fixの2つのenvそれぞれの`mopidy_mpd/translator.py`を
  直接importして比較するスクリプトを実行(ytaudioformatstale-patch.py/
  ytfindalbumtracks-patch.pyと同じ手法) — 曲A(48000:16:2)を解決後、Aがまだcurrent
  なままの状態で曲B(44100:16:2)を(gapless先読みを模して)解決させたところ、
  pre-fixは`status.audio`が誤ってBの値`44100:16:2`を返し`currentsong(A).Format`は
  `None`になる(バグ再現)、post-fixは両方とも正しくAの値`48000:16:2`を維持する
  (修正確認)ことを実証した。
  dev mopidy(6601、ytmusic実アカウント)を実際に起動しMPDで実機確認(回帰確認) —
  実在の2曲(`ytmusic:track:m9SMT5ipbxk`YOASOBI「アイドル」→
  `ytmusic:track:qivRUhepWVA`「怪物」)を`add`+`play`し、`currentsong`のFormatと
  `status`のaudioが再生開始後(`48000:16:2`)・`seekcur`で終端付近へシークし
  実際に次曲へ切り替わった後(2曲ともたまたま同一フォーマットのため値自体の変化は
  確認できなかったが、切替前後で`song`/`songid`/`file`と`audio`/`Format`が常に
  一致し続けクラッシュや値の消失が一切無いことを確認)、通常動作の回帰なしを確認、
  `stop`/`clear`/`tagtypes`/`search any "YOASOBI"`も正常応答、mopidy.logの
  Traceback/ERRORは0件を確認した。
- [x] `mopidy_listenbrainz/frontend.py`の`ListenbrainzFrontend.track_playback_started()`が
  `self.last_start_time = int(time.time())`で曲の再生開始時刻を記録し、
  `track_playback_ended()`にも`self.last_start_time is None`時のフォールバック
  (`int(time.time()) - duration`)まで用意されているにもかかわらず、
  `self.last_start_time`はファイル内のどこからも読み出されておらず(代入のみ、
  grep済み)、実際にListenBrainzへ送るタイムスタンプは
  `mopidy_listenbrainz/listenbrainz.py`の`Listenbrainz.submit_listen()`が
  呼び出し時点(=`track_playback_ended()`発火時点=曲の再生完了時刻)の
  `int(time.time())`を無条件に使っており、そもそも呼び出し元から時刻を受け取る
  引数自体が存在しなかった不具合。ListenBrainzのsubmit-listens API仕様
  (listenbrainz.readthedocs.io/en/latest/users/json.html)は`listened_at`を
  「the time the listen started」(再生"開始"時刻)と明記しており、一時停止を
  挟んだ曲に限らず全ての曲で`listened_at`が実際の再生開始時刻より曲の再生に
  要した時間(+一時停止時間)だけ未来にずれ、ListenBrainz側の週次おすすめ生成
  (`lbplaylistrefresh-patch.py`が扱う)や時間帯別統計、他ユーザーとの再生順序比較が
  系統的に不正確な値を基に行われてしまっていた。TODO/既知の残課題を全項目
  消化済みのため自走エージェントが(Exploreサブエージェントへの調査委任を経て)
  再調査して新規発見した項目。
  verified: lbstarttimestamp-patch.py。`submit_listen()`に`listened_at: Optional[int]
  = None`引数を追加し`now_playing`以外は呼び出し元指定値(未指定時のみ
  `time.time()`へフォールバック)を使うよう変更、`frontend.py`の
  `track_playback_ended()`呼び出し側で`listened_at=self.last_start_time`を渡す
  よう変更(既存の`None`フォールバックが`track_playback_started`取りこぼし時にも
  安全な値を保証)。パッチ適用後の生成ソースは一時コピーに`chmod +w`した上で
  `ast.parse`で構文確認、2回適用しても冪等(両ファイルとも`already`でスキップ)で
  あることも確認。`nix/lib/mopidy-env.nix`の`listenbrainzPatched`に
  `lbimportobsolete-patch.py`の直後として登録しビルド成功、生成ソースに新実装
  (`listened_at`引数・`frontend.py`側の呼び出し)が反映されていることを確認した。
  **オフライン単体テスト**でバグの再現とその解消の両方を実証(dev環境の
  `mopidy-dev.conf`には`listenbrainz`トークンを設定していないため`Disabled
  extensions`に含まれ実接続では検証できない。lbnetguard-patch.py等既存の
  listenbrainz系項目と同じ手法): `self.session`を常に呼び出し内容を記録する
  偽の`FakeSession`に差し替えた`Listenbrainz`インスタンス(`object.__new__`で
  `__init__`をバイパスし`token`/`url`/`user_name`/`session`を直接セット)に対し
  pre-fix/post-fix双方のenvから`submit_listen()`を直接呼び出し比較 —
  実際の再生開始時刻を模した`fixed_start`(現在時刻の5分前)を渡したところ、
  **pre-fix**は`listened_at`引数自体を受け付けず(`TypeError`)送信される
  `listened_at`は呼び出し時点の現在時刻のまま(`fixed_start`と不一致、バグ再現)、
  **post-fix**は`listened_at`引数を受け付け送信される`listened_at`が
  `fixed_start`と完全一致(修正確認)することを実証した。
  dev mopidy(6601、ytmusic実アカウント)を実際に起動しMPDで実機確認(回帰確認) —
  起動ログの`Enabled extensions`/`Disabled extensions`(`listenbrainz`は設定通り
  disabled)に変化なし、`status`/`tagtypes`/`close`が正常応答、mopidy.logの
  Traceback/ERRORは0件を確認した。
- [x] `mopidy_ytmusic/library.py`の`YTMusicLibraryProvider.__init__()`が`self.TRACKS`/
  `self.ALBUMS`/`self.ARTISTS`/`self.IMAGES`(videoId/browseIdをキーとするライブラリ
  キャッシュ)を素の`{}`として初期化しており、`getTrack()`/`playlistToTracks()`/
  `albumToTracks()`/`artistToTracks()`/`parseSearch()`/`get_images()`等50箇所超の
  書き込み箇所がキャッシュサイズの上限チェックや退避処理を一切持たない不具合。
  この互換レイヤの想定運用(nix経由の常駐サービスとして長時間稼働しrmpcから
  継続的にbrowse/search/lookupされる、再起動されない)では、ブラウズ・検索・再生を
  重ねるたびに4つの辞書へ新規エントリが無条件に追加され続けプロセスの生涯にわたり
  単調増加する。`ytlibrarylimit-patch.py`が`get_library_artists()`/
  `get_library_albums()`等の`limit=100`上限を撤廃し全件取得(`limit=None`)する
  よう修正済みのため、大きなライブラリ・頻繁な検索ほど増加は加速する。この
  「サイズ上限を持たないインプロセスキャッシュ」というバグの類型は本コードベースでも
  既に2箇所で認識・対策済み(`mopidy_mpd/protocol/connection.py`の`_MPDART_CACHE`/
  `_MPDART_NEG_CACHE`は64件超で全消去、`mpdaudioformatpreload-patch.py`が追加した
  `translator.py`の`_audio_format_cache`は8件超で挿入順に破棄)だが、はるかに
  書き込み頻度が高くエントリ点数も多いこの4つのライブラリキャッシュだけが無制限の
  まま取り残されていた。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (Exploreサブエージェントへの調査委任を経て)`mopidy_mpd`/`mopidy_ytmusic`/
  `mopidy_listenbrainz`を横断的に再調査して新規発見した項目。
  verified: ytlibrarycachecap-patch.py。全書き込み箇所(50箇所超、今後追加される
  パッチで増えうる)を個別に修正するのは非現実的なため、`mpdaudioformatpreload-
  patch.py`と同じFIFO(挿入順に破棄)方式を`dict`を継承した1クラス
  `_BoundedLibraryCache`へカプセル化し、`__init__`でのキャッシュ生成箇所
  (`self.TRACKS = {}`等4行)だけを`_BoundedLibraryCache(8192)`へ差し替え。
  `dict`のインターフェース(`cache[key]=value`/`key in cache`/`cache[key]`)は
  そのままのため既存の全書き込み・読み出し箇所は無変更で自動的に上限管理下に入る。
  全ての読み出し箇所は「`if key not in cache: cache[key]=...`」または直後の
  `cache[key]`参照のみ(mopidyの各バックエンド呼び出しはpykka actor経由で単一
  スレッド逐次実行されるため同一呼び出し内での競合は無い)であることをソースを
  精読して確認済みで、退避されたエントリへの参照はキャッシュミスとして扱われ
  APIから再取得されるだけで例外にはならない設計。パッチ適用後の生成ソースは
  一時コピーに`chmod +w`した上で`ast.parse`で構文確認、2回適用しても冪等
  (`already`でスキップ)であることも確認。`_BoundedLibraryCache`単体をオフラインで
  取り出しFIFO退避の実際の挙動(`maxsize=3`で4件目挿入時に最古の1件目のみ退避、
  既存キーの再代入では退避もキー順序の変更も起きない)を検証済み。`nix/lib/
  mopidy-env.nix`の`ytmusicPatched`に`ytfindalbumtracks-patch.py`の直後として
  登録しビルド成功、生成ソースの`self.TRACKS`等が`_BoundedLibraryCache(8192)`に
  置き換わっていることを確認した。dev mopidy(6601、ytmusic実アカウント)を実際に
  起動しMPDで実機確認 — 起動ログにTraceback/ERROR無くクリーンに起動(`Enabled
  extensions: ytmusic, softwaremixer, mpd, http, m3u`)、実データでの
  `search any "YOASOBI"`(album/trackプレースホルダ混在の結果を正しく返す)・
  `find artist "YOASOBI"`(複数アルバムを正しく返す、いずれも内部で`self.ALBUMS`/
  `self.TRACKS`へ書き込み)・`lsinfo "YouTube Music"`・`tagtypes`・実トラック
  (`ytmusic:track:m9SMT5ipbxk`YOASOBI「アイドル」、`self.TRACKS`/`self.ALBUMS`
  経由)の`add`+`play`+`status`(`audio: 48000:16:2`)+`currentsong`(`Format:
  48000:16:2`・`AlbumArtist`等正しく反映)+`stop`+`clear`が全て正常応答、
  mopidy.logのTraceback/ERRORは0件を確認した。
- [x] `mopidy_ytmusic/library.py`の`YTMusicLibraryProvider.parseSearch()`が、
  検索(`search`/`find`コマンド)経由で初めて触れたトラックに対して`self.IMAGES`へ
  一切書き込まないため、その曲の`albumart`/`readpicture`が常に`No file exists`で
  失敗する不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (Explore→general-purposeサブエージェントへ2段階で調査を委任した上で)再調査して
  新規発見した項目。1段階目の候補(`audio_output.py`の`enableoutput`/`disableoutput`の
  mute方向)はupstream mopidy-mpd公式テストスイート(`tests/protocol/test_audio_output.py`、
  `test_enableoutput`が`enableoutput`実行後に`get_mute() is True`を明示的にassert)
  で確認した結果、仮想出力名が"Mute"であることに由来する意図的仕様と判明し誤検出と
  判断・破棄した上で2段階目の調査により本項目を採用した。
  原因: `ytimages-patch.py`が`playlistToTracks()`(ブラウズ経路)向けに「応答に既に
  含まれる`track["thumbnails"]`を追加API呼び出し無しで`self.IMAGES`へキャッシュする」
  対策を導入済みだったが、`parseSearch()`(`search-patch.py`が担う`any`検索等の実処理、
  `search`/`find`コマンドの実体)の2箇所(`resultType == "song"`分岐、および
  `resultType == "artist"`分岐配下の`get_artist()["songs"]["results"]`ループ)には
  一度も横展開されていなかった。upstream `ytmusicapi`(nix closure同梱の1.12.0)の
  `ytmusicapi/parsers/search.py`を確認した結果、`parse_search_result()`/
  `parse_top_result()`はいずれも全resultType共通で無条件に
  `search_result["thumbnails"] = nav(data, THUMBNAILS, True)`をセットしており
  (82行目/209行目)、`get_artist()`の`songs.results`側もdocstring例に
  per-track `"thumbnails"`を含むことを確認済み — つまりデータは応答に確実に
  含まれているのに`parseSearch()`だけがそれを読み捨てていた。実害:
  検索で最初に触れた曲は`self.IMAGES`に一切登録されず、`get_images()`は
  `track.album`が無ければ空、`album`があっても`get_album()`を毎回追加で叩く
  非効率な経路にしかならない。同じ曲を先にアルバム/プレイリスト経由でブラウズ
  していれば`self.IMAGES`にヒットするため、検索経由か否かで`albumart`/
  `readpicture`の成否が変わる非一貫な挙動になっていた。
  verified: ytsearchthumbnail-patch.py。`ytimages-patch.py`と全く同じ流儀
  (解像度小→大の並びを反転して大きい順に)で、`parseSearch()`のsong分岐/
  artist分岐songsサブループの両方のTrack登録直後に`self.IMAGES[videoId]`へ
  キャッシュする処理を追加(2箇所ともアンカーの一意性を確認した上で適用)。
  パッチ適用後の生成ソースは一時コピーに`chmod u+w`した上で`ast.parse`で
  構文確認。`nix/lib/mopidy-env.nix`の`ytmusicPatched`に
  `ytlibrarycachecap-patch.py`の直後として登録しビルド成功、生成ソースの2箇所
  (`self.IMAGES[result["videoId"]]`/`self.IMAGES[song["videoId"]]`)に新規挿入が
  反映されていることを確認した。**修正前後比較で実証**: 旧env(パッチ前)を
  `mpd/port=6602`(別キャッシュ/データディレクトリ)で並行起動し、新env
  (6601、パッチ後)と全く同一の操作列 —
  `search any "YOASOBI"`(YOASOBI「アイドル」`ytmusic:track:m9SMT5ipbxk`を検索の
  みで初めて取得、他経路で未ブラウズ)→`albumart "ytmusic:track:m9SMT5ipbxk" "0"`
  →`readpicture "ytmusic:track:m9SMT5ipbxk" "0"` — を両方に送信して比較。
  **旧env(修正前)**は`albumart`/`readpicture`ともに`ACK [50@0] {albumart} No
  file exists`/`ACK [50@0] {readpicture} No file exists`(不具合再現)、
  **新env(修正後)**は両方とも実JPEGバイト列(`size: 11718`、`type:
  image/jpeg`、先頭`\xff\xd8\xff\xe0`のJPEGマジックバイト込み)を正しく返す
  ことを確認した(修正確認)。新env側は`status`/`tagtypes`/
  `lsinfo "YouTube Music"`/`find artist "YOASOBI"`の回帰なし・mopidy.logの
  Traceback/ERRORは0件(唯一の`ERROR`/`Traceback`はstop.sh実行時の
  `server_socket.shutdown()`が既に切断済みソケットに対し送出する
  `OSError: [Errno 57] Socket is not connected`という無害なシャットダウン時
  ノイズのみ、本パッチとは無関係)を確認した。
- [x] `mopidy_ytmusic/library.py`の`parseSearch()`の`elif result["resultType"] == "album":`
  分岐(search/findコマンドで検索結果自体がアルバムであるケース)が、`result["browseId"]`の
  None/欠落チェックを一切せずそのまま`self.ALBUMS`の辞書キー兼URIサフィックスとして使って
  しまう不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへ調査を委任した上で)再調査して新規発見した項目。
  原因: `ytmusicapi`の`parse_search_result()`(`ytmusicapi/parsers/search.py`193〜194行目)は
  resultTypeが"album"の場合`search_result["browseId"] = nav(data, NAVIGATION_BROWSE_ID, True)`
  と`none_if_absent=True`で取得しており(`nav()`実装、`navigation.py`)、該当パスが無ければ
  例外を投げず`None`を返す。つまりYouTube Music側のレスポンスにブラウズリンクが無いアルバム
  (地域制限・カタログ上未リンクの一部リリース等)では`browseId is None`が実際に起こりうる。
  `ytartistcache-patch.py`(`self.ARTISTS`)/`ytalbumidcache-patch.py`(`self.ALBUMS`、
  `playlistToTracks`/`uploadArtistToTracks`/`parseSearch` song・artist経由songsの4箇所)が
  既に対処した「id=Noneを無条件にキャッシュキーへ使ってしまう」のと全く同じバグクラスだが、
  `parseSearch()`自身の`resultType=="album"`分岐(検索結果が直接アルバムであるケース)だけは
  この横展開から漏れていた。なお同じ`parseSearch()`のartist分岐配下にある
  `get_artist_albums()`/`artistq["albums"]["results"]`/`artistq["singles"]["results"]`由来の
  `self.ALBUMS[album["browseId"]]`等も調査したが、`ytmusicapi`の`parse_album()`/
  `parse_single()`(`parsers/browsing.py`)は`browseId`を`none_if_absent`無しで取得しており
  欠落時は例外化→呼び出し元のtry/exceptでアルバム/アーティスト単位ごと丸ごとスキップされる
  ため、`browseId=None`のまま`self.ALBUMS`へ到達する経路は無く対象外と判断した
  (過大申告を避けるため個別に確認、実際に修正したのは`resultType=="album"`分岐の1箇所のみ)。
  verified: ytsearchalbumidcache-patch.py。`ytalbumidcache-patch.py`と同じ流儀で、
  `browseId`が falsy な場合は`self.ALBUMS`へキャッシュせず都度その場限りの(`uri=""`の)
  `Album`を作って`salbums`へ直接足すよう分岐。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w`した上で`ast.parse`で構文確認、2回適用しても冪等(`already`でスキップ)である
  ことも確認。`nix/lib/mopidy-env.nix`の`ytmusicPatched`に`ytsearchthumbnail-patch.py`の
  直後として登録しビルド成功、生成ソースの`if not result.get("browseId"):`が反映されている
  ことを確認した。**オフライン単体テスト**でバグの再現とその解消の両方を実証(実際の検索結果で
  browseId欠落アルバムを狙って引き当てるのは非決定的なため、`lbstarttimestamp-patch.py`等
  既存項目と同じ手法): `mopidy.models.Album`を使い、パッチ適用前後それぞれの書き込みロジックを
  抽出し`browseId=None`の2つの異なるアルバム(名前が全く異なる)を順に処理させて比較 —
  **パッチ前**は両方とも`self.ALBUMS[None]`という同一キーに書き込まれ、1つ目のアルバムを
  引く参照(`alb1`)も2つ目のアルバムの名前で上書きされてしまうこと(URIも`ytmusic:album:None`
  という壊れた値になること)を確認(不具合再現)。**パッチ後**は`self.ALBUMS`に`None`キーが
  一切追加されず(`ALBUMS`は空のまま)、2つのアルバムはそれぞれ独立した`uri=""`のオブジェクト
  として正しく別々の名前を保持することを確認(修正確認)。回帰確認として`browseId`が実際に
  存在する2件(`MPREb_AAA`/`MPREb_BBB`)も同時に処理させ、従来通り`self.ALBUMS`へ正しく
  キャッシュされ`uri=f"ytmusic:album:{browseId}"`になることも確認した。dev mopidy(6601、
  ytmusic実アカウント)を実際に起動しMPDで実機確認(回帰確認) — 起動ログに
  Traceback/ERROR無くクリーンに起動(`Enabled extensions: softwaremixer, m3u, ytmusic, http,
  mpd`、`YTMusic loaded 9 auto playlists sections`)、実データでの`search any "YOASOBI"`
  (album/trackプレースホルダ混在の結果を正しく返す、`X-AlbumUri`含め正常)・
  `find album "YOASOBI"`(複数アルバムの全トラックをArtist/Album/Track番号付きで正しく返す)・
  `tagtypes`・`status`が全て正常応答、mopidy.logのTraceback/ERRORは0件を確認した。
- [x] `mopidy_ytmusic/playback.py`の`YTMusicPlaybackProvider.last_id`(`library.py`の
  `browse()` `"ytmusic:watch"`分岐=「Similar to last played」が起点曲として使う)が、
  gapless先読み/明示的`play()`の非同期昇格待ちウィンドウ中に次曲の値で上書きされ、
  `status`/`currentsong`が現在曲Aを正しく再生中と報告している間に`ytmusic:watch`だけ
  既に次曲B基準のおすすめを返してしまう不具合。TODO/既知の残課題を全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)新規発見した項目。
  原因: `translate_uri()`(`change_track()`から同期呼び出し)が`self.last_id = bId`を
  無条件に書き込む。mopidy core(`mopidy/core/playback.py`)は`_on_about_to_finish()`
  (gapless先読み)でも`play()`/`_change()`(明示的再生)でも、実際にGStreamerが再生を
  開始し`_on_stream_changed()`が呼ばれて`_current_tl_track`へ昇格するより前に
  `backend.playback.change_track()`を同期呼び出しする(`_pending_tl_track`にセット
  しただけの段階)。このウィンドウ中は「Aがまだ再生中」なのに`translate_uri(B)`が
  先に`self.last_id`をBへ書き換えてしまう。直前のコミット
  (mpdaudioformatpreload-patch.py)が全く同じ呼び出し経路
  (`_on_about_to_finish()`→`change_track()`→`_get_track()`)で`translator.py`の
  単一値ストア(`_audio_format`/`_audio_format_uri`)が次曲の値に上書きされる不具合を
  修正済みだが、あちらは`mopidy_mpd`側の`status`/曲メタデータ限定の修正で
  `mopidy_ytmusic/playback.py`自身の`last_id`には一切触れていなかった
  (`grep "last_id" ~/.dotfiles/configs/media/mopidy/*.py`は`ythistory-patch.py`/
  `ytoauthlibraryguard-patch.py`/`ytsongformat-patch.py`のみヒットし、いずれも
  `library.py`側の読み取り箇所や uri 復元にしか触れず、`playback.py`の書き込み
  タイミング自体は未対応と確認済み)。同じバグクラスの横展開漏れだった。
  verified: ytlastidrace-patch.py。audio formatキャッシュ(曲uriごとの値を保持)とは
  異なるアプローチを採用: last_idは「曲(uri)ごとの値」ではなく「実際に再生が確定した
  1曲」を指す必要があるため、mopidy core自身が`_current_tl_track`への昇格に使っている
  のと全く同じ仕組み(`mopidy.audio.AudioListener`の`stream_changed`イベント、
  GStreamerが実際に新ストリームの再生を開始した時にのみ発火し
  `mopidy/core/playback.py`の`_on_stream_changed()`もこれで昇格タイミングを知る)を
  `YTMusicBackend`(既に`pykka.ThreadingActor`)へmixinし、そこで初めて`last_id`を
  確定させる設計に変更。`translate_uri()`は解決した再生用URLをキーに`bId`を
  `_pending_last_id`辞書へ一時保持するだけに変更(`change_track()`が直後に
  `audio.set_uri(url)`へ渡す`url`と同じ値なので`stream_changed(uri)`の`uri`と一致する
  ことを`mopidy/audio/actor.py`の`on_stream_start()`(`uri = self._audio._pending_uri`、
  `set_uri()`が`_pending_uri = uri`で素通しに設定)を実際に読んで確認済み)、実際に
  鳴り始めてから`backend.stream_changed()`で`self.playback.last_id`へ反映する。
  無制限に増え続けないよう`mpdaudioformatpreload-patch.py`と同じFIFO方式で上限8件
  まで保持。パッチ適用後の生成ソース(`playback.py`/`backend.py`)は一時コピーに
  `chmod u+w`した上で`ast.parse`で構文確認、2回適用しても冪等(`already patched`で
  スキップ)であることも確認。`nix/lib/mopidy-env.nix`の`ytmusicPatched`に
  `ytsearchalbumidcache-patch.py`の直後として登録しビルド成功、生成ソースに
  `_pending_last_id`/`AudioListener` mixin/`stream_changed()`が反映されていることを
  確認した。**オフライン単体テスト**でmopidy core実際の呼び出し順序
  (`translate_uri("A")`→(Aの実再生開始確定)→`translate_uri("B")`(Aがまだ実際に
  再生中のgapless先読みウィンドウ))を模した比較を実施 —
  **修正前ロジック**(`translate_uri`内で`last_id`即時確定)は`translate_uri("B")`
  直後に`last_id`が`'B'`へ書き換わり不具合を再現、**修正後ロジック**
  (`stream_changed`確定後のみ反映)は同じ呼び出し列で`last_id`が`'A'`のまま保たれ、
  その後`stream_changed("url_for_B")`(Bの実再生開始)で初めて`'B'`へ正しく確定する
  ことを確認(修正確認)。さらにdev mopidy(6601、ytmusic実アカウント)を実際に起動し
  MPDで実機の完全なgapless遷移を確認(回帰確認) — YOASOBI「アイドル」→「オリオン」の
  2曲をキューに積み`play`、`seekcur`で終端付近まで進めて実際のgapless自動遷移を
  発生させた上で、遷移前は`currentsong`が「アイドル」を再生中と報告している間
  `lsinfo "YouTube Music/Similar to last played"`がYOASOBI関連曲(勇者/革命道中等)を
  返し、遷移後は`currentsong`が「オリオン」に切り替わった後で同じ`lsinfo`が
  Orion関連曲(劇上/Orion English Version等)へ正しく切り替わることを確認、
  3曲目追加後の再遷移でも同様に追従することを確認した。旧来の`status`/`tagtypes`/
  `stop`/`clear`の回帰なしも確認。mopidy.logの`Traceback`は2件のみで、いずれも
  本パッチと無関係な既知の`KeyError: 'videoDetails'`(`YTMusic failed to get track
  "None"`、`library.py`の無関係な最終フォールバック分岐由来、BACKLOG既出の
  既知ノイズ)、stop.sh実行時の`server_socket.shutdown()`由来の無害な
  `OSError: Socket is not connected`のみで、本パッチ由来のTraceback/ERRORは0件。
- [x] `Added` (MPD 0.24+の曲メタデータ) が `find`/`search`/`lsinfo`/`listplaylistinfo` 等
  キュー外の曲情報応答では常に欠落する不具合を修正。TODO/既知の残課題を全項目消化済みの
  ため自走エージェントが (Explore サブエージェントへの調査委任を経て) rmpc 本体
  (mierak/rmpc) を実際に clone してソース確認したところ、rmpc-mpd/src/commands/
  current_song.rs の `Song.added` フィールドはキュー由来かどうかを問わず全ての曲情報応答で
  解釈される汎用フィールドで、rmpc/src/config/theme/properties.rs の
  `SongProperty::Added()` として rmpc/src/ui/dir_or_song.rs の `CmpByProp::cmp(a.added,
  b.added)` 経由で検索結果/タグブラウザ/ディレクトリ/ストアドプレイリストいずれのペインでも
  ソート・カラム表示に使える設計であることを確認した上で着手。mpdadded-patch.py が実装した
  既存の "Added" は translator.py の `track_to_mpd_format()` 内 `position is not None and
  tlid is not None` (=キュー内の曲) の分岐でのみ出力されており、position/tlidを渡さない
  `music_db.py` の `find`/`search`/`lsinfo`、`stored_playlists.py` の `listplaylistinfo`
  経由では "Added" 行そのものが常に欠落することを実機 (dev mopidy 6601, ytmusic実アカウント)
  で確認した上で着手。
  verified: mpdlibraryadded-patch.py。mopidy core の Track モデルには「ライブラリに実際に
  追加された時刻」という概念が無く(mopidy_ytmusicはYouTube Music側のカタログをその都度
  動的に返すだけでDBという概念自体が無い)、真の意味論の再現は不可能なため、
  mpdadded-patch.pyのキュー用揮発性ストアと同じ設計方針(このMPDセッションで最初にその曲が
  返された時刻を疑似Addedとして採用)を、キュー外の経路(uriキー)にも適用。translator.pyへ
  `_library_added`(uri→ISO8601、初回アクセス時に現在時刻をスタンプしキャッシュ)と
  `get_or_stamp_library_added(uri)`を追加、`track_to_mpd_format()`の
  `position is not None and tlid is not None`分岐に対応する`else`節でこれを呼び出し
  "Added"を追加(既存のキュー内Added `_queue_added`/tlidキーは無変更、同一uriがキューにも
  同時に載っていても両ストアは独立)。ytlibrarycachecap-patch.pyと同根の無制限dict増加を
  避けるため、mpdaudioformatpreload-patch.pyの`_audio_format_cache`と同じFIFO方式で
  8192件超過時に挿入順(古い順)に破棄。パッチ適用後の生成ソースは一時コピー
  (nix store由来ファイルはread-onlyのためchmod u+wしてからコピー)に当てて`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  mpdPatchesリスト末尾(mpdsetvolrange-patch.pyの直後)に登録しビルド成功。dev mopidy
  (6601, ytmusic実アカウント)を実際に起動しMPDで実機確認 — `search any "yoasobi"`で
  返る各トラック/アルバムに新規で"Added"行が付与されることを確認、2秒後に同じ
  `search any "yoasobi"`を再送しても同一トラックのAdded値が変化しない(初回スタンプの
  キャッシュ再利用)ことを確認、新規に初出したトラックには別の新しいAdded値が付与される
  ことも確認。同一トラックを`addid`でキューに積んだ`playlistinfo`のAdded(キュー追加時刻)
  はライブラリ側Addedと異なる値になり両ストアが独立して機能することを確認。
  `playlistadd`で作成したプレイリストの`listplaylistinfo`にもAddedが付与され、既に
  `search`でキャッシュ済みの同一uriは同じAdded値を再利用することを確認。回帰確認:
  `status`/`currentsong`(キュー内Addedのまま、無変更)/`tagtypes`/`listplaylists`/
  `lsinfo "/"`/`clear`いずれも従来通り正常応答、mopidy.logにTraceback/ERROR 0件。
- [x] フィルタ式 `(TAG OP "VALUE")` パーサ (`_query_from_mpd_filter_expression()`,
  music_db.py の find/findadd/search/searchadd/searchaddpl/count/searchcount、
  current_playlist.py の `_pf_search()` 経由で playlistfind/playlistsearch/
  searchplaylist も共有) が、TAG が `_SEARCH_MAPPING` で解決できない未知タグ名の
  節を `if not field or not value.strip(): continue` で黙って読み捨て、他に有効な
  条件が1つでも同居していればコマンド全体がACKにならずOKで(誤った)結果を返して
  しまう不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (Explore サブエージェントへの調査委任を経て) 新規発見した項目。
  実害: dev mopidy(6601, ytmusic実アカウント)で
  `find "(Bogus == \"x\") AND (Artist == \"YOASOBI\")"` を送ると、未知タグ`Bogus`
  の節だけが無視され`Artist == "YOASOBI"`単独と同じ結果がOKで返ることを実機確認
  (同じ式が`(Bogus == "x")`単独ならqueryが空になる副作用でたまたまACKになる
  という非対称性がこれまで見過ごされていた)。同一ファイル内の旧来
  `TYPE VALUE`ペア形式(`_query_from_mpd_search_parameters`の非フィルタ式分岐)は
  既に`field = mapping.get(...); if not field: raise
  exceptions.MpdArgError("incorrect arguments")`で未知タグを即ACKにしており、
  フィルタ式側だけがこの検証を欠く非対称も確認した。実MPD仕様
  (MusicPlayerDaemon/MPDを実際にcloneしてソース確認): `src/song/Filter.cxx`の
  再帰下降パーサはタグ名解決に失敗すると
  `throw FmtRuntimeError("Unknown filter type: {}", name);`を即座に送出し、
  他の条件節の有無に関わらずコマンド全体をACKにする(部分的な条件破棄は一切
  行わない)。rmpc本体(mierak/rmpc)は`custom_query`(オプトイン設定、
  rmpc/src/config/search.rs)有効時にユーザ入力のフィルタ式文字列をほぼそのまま
  find/searchへ渡すため、タグ名の打ち間違いがエラーにならず意図と異なる結果を
  返してしまう実害に繋がる。
  verified: mpdfilterexprtagerr-patch.py。`_query_from_mpd_filter_expression()`の
  `field = mapping.get(tag.lower())`直後を`if not field: raise
  exceptions.MpdArgError(f"Unknown filter type: {tag}")`(値が空文字列
  `(Artist == "")`のケースは本項目のスコープ外のため無変更)に変更。パッチ適用後の
  生成ソースは一時コピー(nix store由来ファイルはread-onlyのためchmod u+wして
  からコピー)に当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ、
  マーカーは既存の`list()`ハンドラ内に元々あった"Unknown filter type"という
  無関係な文字列と衝突しないよう置換後コード片そのものに変更して確認)で
  あることも確認。`nix/lib/mopidy-env.nix`のmpdPatchesリストに
  mpdregexvalidate-patch.pyの直後として登録しビルド成功。dev mopidy(6601,
  ytmusic実アカウント)を実際に起動しMPDで実機確認 —
  `find "(Bogus == \"x\") AND (Artist == \"YOASOBI\")"`/
  `count "(Bogus == \"x\") AND (Artist == \"YOASOBI\")"`/
  `list Album "(Bogus == \"x\") AND (Artist == \"YOASOBI\")"`/
  `searchcount "(Bogus == \"x\") AND (Artist == \"YOASOBI\")"`/
  `playlistfind "(Bogus == \"x\")"`/`find "(Bogus == \"x\")"`(単独)/
  `find "(Bogus != \"x\")"`(否定演算子)がいずれも
  `ACK [2@0] {コマンド名} Unknown filter type: Bogus`となり、以前のように
  未知タグの節だけ無視されOKになる誤動作が解消されたことを確認。回帰確認:
  `find "(Artist == \"YOASOBI\")"`(実データで正しく複数件返る)、
  `search "(Artist contains \"YOASOBI\")"`(同様)、
  `find "(artist == \"YOASOBI\") AND (album == \"x\")"`(両タグとも有効・
  値が実在しないだけ→エラーにならずOKで空リスト、正しい既存動作を維持)、
  旧来の`find artist "YOASOBI"`/`find artist "YOASOBI" album "x"`
  (空白区切り複数ペア形式)、`list album`(無指定)、
  `list Album group Bogus`(→`ACK Unknown tag type: Bogus`、既存のgroup検証は
  無変更で正しく動作)、`status`/`tagtypes`いずれも従来通り正常応答、
  mopidy.logにTraceback/ERROR 0件を確認した。
- [x] `mopidy_ytmusic.library.py` の `YTMusicLibraryProvider.get_distinct()`
  (MPD の `list`/`count ... group`/`stats` が経由するライブラリ登録アーティスト/
  アルバム/年の列挙、artist・albumartist分岐/album分岐/date分岐の計3箇所) が
  `get_library_artists()`/`get_library_albums()` を config 可変の
  `self.backend.playlist_item_limit`(既定100)固定で呼んでおり、保存アーティスト/
  保存アルバムが100件を超えるアカウントで101件目以降をエラーもログも無く
  静かに切り捨てる不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (Explore サブエージェントへの調査委任を経て) 新規発見した項目。
  `ytlibrarylimit-patch.py` が既に修正した `browse()` の
  "ytmusic:artist"/"ytmusic:album" 分岐は同じ `get_library_artists()`/
  `get_library_albums()` を `limit=None`(ytmusicapi が continuation を
  使い果たすまで全件取得)で呼ぶよう直しており、`lsinfo "YouTube Music/Albums"`
  は全件返るのに `list album`/`count group album`/`stats` の `albums:` だけ
  `playlist_item_limit` で頭打ちになるという非対称が残っていた
  (`ytlibrarylimit-patch.py` 自身のコメントが「get_distinct()側は既にconfig可変の
  playlist_item_limitを使っておりbrowse/as_list側だけ非対称だった」と書いた時点では
  get_distinct() 側のこの頭打ち自体はバグとして認識されていなかった)。
  verified: ytdistinctlimit-patch.py。`get_distinct()` 内の3箇所
  (`get_library_artists(limit=self.backend.playlist_item_limit)`、
  `get_library_albums(limit=self.backend.playlist_item_limit)` ×2) を
  `browse()` と同じ `limit=None` に変更(`playlist.py`/`library.py`の
  `get_playlist(bId, limit=playlist_item_limit)` 等、1プレイリスト/アルバム内の
  トラック数を絞る他の `playlist_item_limit` 用途は本項目のスコープ外・意図通りの
  挙動のため無変更)。パッチ適用後の生成ソースは一時コピーに当てて `ast.parse` で
  構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix` の `ytlibrarylimit-patch.py` の直後に登録しビルド成功、
  生成ソースに `limit=None` が反映されていることを確認。実データ検証: 実アカウント
  (dev mopidy 6601) には保存アーティスト/アルバムが0件だったため実データでの
  100件超過は再現できなかったが、パッチ済みビルドの `mopidy_ytmusic.library` を
  実際にインポートし、`get_library_artists()`/`get_library_albums()` が
  渡された `limit` を忠実に尊重する(実ytmusicapiと同じ)スタブAPI(150件返却)+
  `playlist_item_limit=3` の `backend` で `YTMusicLibraryProvider.get_distinct()`
  を直接呼び出し — `get_distinct("artist")`→150件、`get_distinct("album")`→150件、
  `get_distinct("date")`→20件(いずれも `playlist_item_limit=3` を無視し全件相当を
  取得、旧実装なら3件で頭打ち)を確認。回帰確認: dev mopidy(6601, ytmusic実アカウント、
  `playlist_item_limit=3` に一時変更)を実際に起動しMPDで `list album`/`list artist`/
  `list date`/`count group artist`/`stats`/`list Album group AlbumArtist` が
  いずれもエラーなくOK応答(実データ0件のため空/0のまま、ACKにならず正常応答)、
  さらに `playlist_item_limit` を既定(未設定=100)に戻した状態でも `status`/
  `list album`/`list artist`/`stats` が従来通り正常応答することを確認。
  いずれもmopidy.logにTraceback/ERROR新規発生なしを確認した。
- [x] `mopidy_mpd/protocol/audio_output.py` の `outputs()` (mpdoutputpartition-patch.py
  実装) が、現在のセッションのパーティションが仮想出力「Mute」の所属パーティション
  (`translator.output_partition_get("Mute")`) と一致しない場合、default/非defaultを
  区別せず常に `plugin: "dummy"` の偽の1行 (`outputid 0`/`outputname Mute`/
  `outputenabled 0`) を返してしまう不具合。TODO/既知の残課題を全項目消化済みのため
  自走エージェントが (Explore/general-purposeサブエージェントへの調査委任、および
  rmpc本体 mierak/rmpc と実MPD本体 MusicPlayerDaemon/MPD の両方を実際にcloneしての
  再検証を経て) 新規発見した項目。
  実MPD仕様 (`src/output/Print.cxx` の `printAudioDevices()` を実際に取得し確認):
  `for (...) { if (!outputs.Owns(ao)) continue; ... }` という実装で、"dummy" という
  プレースホルダ機構自体が実MPDに一切存在しない (`src/output/plugins/` 配下の全出力
  プラグイン名を確認したが "dummy" は無く "null" という別プラグインがあるのみ、
  NEWS/ソース全文をgrepしても "dummy" は0件)。実MPDは default を含めどの
  パーティションからの `outputs` であっても、そのパーティションが所有していない出力は
  単に列挙から除外する(該当出力ゼロなら空のOKのみ)。この所有権はパーティション作成時の
  `MultipleOutputs::AcquireAll()`(未所有の出力を先着 = 通常はdefaultが総取り)と
  `moveoutput` による明示的な移動でのみ変わる。
  rmpc本体 (`rmpc/src/shared/mpd_client_ext.rs` の `list_partitioned_outputs()`) を
  実際に読むと、非defaultパーティションからの呼び出しでは「defaultへ一時切替→outputs
  取得→元のパーティションへ戻し再度outputs取得→前者のうち後者にplugin!="dummy"で
  同名一致するものだけをCurrentPartition、それ以外はOtherPartition」という2段階の
  突き合わせを行っており、非default側の応答に当該出力が単に「含まれない」場合を
  正しく扱える設計(含まれなければ自動的にOtherPartition側に落ちる)。つまり「dummyと
  いう偽の1行」は実MPD互換の観点でもrmpcの非default分岐の実装の観点でも必要とされて
  おらず、mpdoutputpartition-patch.pyの非default時のこの偽1行は実MPDの応答形状から
  逸脱した過剰実装だったと判明した。さらにrmpcには`rmpc --partition NAME outputs`
  というCLIサブコマンド(`rmpc/src/config/cli.rs`)があり、そのハンドラ
  (`rmpc/src/core/command.rs`)はTUIの`list_partitioned_outputs()`(dummyフィルタ
  あり)を経由せず生の`client.outputs()`をそのままJSON出力するため、非default・
  非所有パーティションから直接`outputs`を叩くと実在しない出力の偽情報が混入した
  JSONを返してしまう実害がある。
  一方 default パーティションが不所有の場合に dummy 行を返す既存の分岐は、rmpc の
  default分岐 (`outputs()`の応答内でplugin=="dummy"の行をOtherPartition扱いする
  ヒューリスティック) 向けに意図的に追加されたものであり、既に(以前の自走エージェント
  実行で)実機検証済みのため本項目では変更していない。本項目は非default時の偽1行だけを
  実MPD準拠の空リストへ修正した。
  verified: mpdoutputpartitionempty-patch.py。`outputs()`の`not
  _mpdoutputpartition_owned(context)`分岐内に
  `translator.partition_get(id(context.session)) ==
  translator.partition_list()[0]`(=defaultかどうか)の判定を追加し、defaultのみ
  従来のdummy行を維持、非defaultは空リスト`[]`を返すよう変更。パッチ適用後の生成
  ソースは一時コピー(nix store由来ファイルはread-onlyのためchmod u+wしてからコピー)に
  当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`のmpdPatchesリストにmpdlibraryadded-patch.pyの直後として
  登録しビルド成功。dev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで実機
  確認 — ①baseline: default(Mute初期所有)で`outputs`→`plugin: mopidy`の実データ行
  (無変更)。②`newpartition work`→`partition work`(Muteはまだdefault所属)→
  `outputs`→修正前は偽の`outputid: 0`/`plugin: dummy`行が返っていたところ、修正後は
  行が一切無い`OK`のみになることを確認。③`moveoutput Mute`(workへ移動)→`outputs`
  (work視点)→`plugin: mopidy`の実データ行(所有時は無変更で正しく動作)。④
  `partition default`(defaultは今やMute不所有)→`outputs`→既存のdummy行
  (`plugin: dummy`)が従来通り返ることを確認(default分岐は意図通り無変更、
  リグレッション無し)。⑤`moveoutput Mute`でdefaultへ戻し`delpartition work`で
  後片付け、`listpartitions`がdefaultのみに戻ることを確認。回帰確認:
  `status`/`tagtypes`/`currentsong`いずれも従来通り正常応答、mopidy.logに
  Traceback/ERROR新規発生なしを確認した。
- [x] `mopidy_mpd/protocol/stickers.py` の `_mpd_sticker_find_ext()`
  (`sticker find {TYPE} {URI} {NAME} ...`、mpdstickerfind-patch.py実装) が
  非空 URI を単純な文字列 `startswith` でしか絞り込んでおらず、ディレクトリ
  境界(`/`)を一切考慮していない不具合。TODO/既知の残課題を全項目消化済みの
  ため自走エージェントが (general-purposeサブエージェントへの調査委任を経て)
  新規発見した項目。`sticker find song "Music/A" rating` を送ると
  "Music/A/song1.mp3"(配下)だけでなく "Music/AB/song2.mp3"(兄弟ディレクトリ、
  文字列としては前方一致するが配下ではない)まで誤って一致してしまう。
  `sticker` コマンドのdocstring自体が「below the specified directory (URI)」
  と明記しており、単純な文字列前方一致ではなく配下判定が仕様上の前提。
  実MPD本体(MusicPlayerDaemon/MPD, WebFetchで直接ソース確認)の
  `src/sticker/SongSticker.cxx` の `sticker_song_find()` は、`base_uri` が
  空でない場合に必ず末尾へ `"/"` を補ってから `StringStartsWith(i.uri,
  base_uri)` で前方一致させており、兄弟ディレクトリを除外する。rmpc本体
  (mierak/rmpc) の `rmpc sticker find <uri> <key>` CLIサブコマンド
  (src/config/cli.rs `StickerCmd::Find`, src/core/command.rs) はユーザ指定の
  任意の非空URIをそのまま `sticker find` へ渡す唯一の経路であり、ディレクトリ
  境界を期待した設計になっている(TUI内部の呼び出しは全て `uri=""` 固定の
  ため影響しない)。
  verified: mpdstickerfinddir-patch.py。`_mpd_sticker_find_ext()` 冒頭で
  `uri` が空でなければ末尾に `"/"` を1つ補った `uri_prefix` を作り(既に
  末尾が `/` の場合は二重付与しない)、`row_uri.startswith(uri)` の判定を
  `row_uri.startswith(uri_prefix)` に変更。パッチ適用後の生成ソースは一時
  コピー(nix store由来ファイルはread-onlyのためchmod u+wしてからコピー)に
  当てて `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix` の `mpdstickerfind-patch.py` の直後に登録し
  ビルド成功。dev mopidy(6601)を実際に起動しMPDで実機確認 —
  `sticker set song "Music/A/song1.mp3" rating "5"` /
  `sticker set song "Music/AB/song2.mp3" rating "5"` の後、
  `sticker find song "Music/A" rating` は修正前なら両方返っていたところ、
  修正後は `Music/A/song1.mp3` のみ返ることを確認。`sticker find song
  "Music/A/" rating`(既に末尾スラッシュ付き)も同じ1件のみを返し二重付与に
  よる回帰が無いことを確認。`sticker find song "" rating`(URIルート指定)は
  従来通り既存の全stickerを返すことも確認。回帰確認: `status`/`tagtypes`/
  `sticker list song "test:2"` いずれも従来通り正常応答、mopidy.logに
  Traceback/ERROR新規発生なしを確認した。
- [x] `mopidy_mpd/protocol/channels.py` の client-to-client messaging
  (mpdchannels-patch.py実装、subscribe/unsubscribe/channels/readmessages/
  sendmessage) が、translator.py の `_channel_subscriptions` を購読元セッションの
  所属パーティション(partition.py, mpdpartition-patch.py)を一切考慮せずサーバー全体で
  横断的に走査してしまう不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任、および実MPD本体
  MusicPlayerDaemon/MPDのソースをgh apiで実際に取得しての再検証を経て)新規発見した項目。
  具体例: クライアントAが`newpartition work`→`partition work`→`subscribe foo`で
  パーティション"work"上でチャンネル"foo"を購読すると、"default"のままのクライアントBが
  `channels`を叩いた際に"work"側でしか購読されていない"foo"が見えてしまう。同様にBが
  `sendmessage foo "hi"`を送ると、無関係な別パーティションのAへメッセージが誤って配送され
  成功応答(OK)になってしまう。実MPD本体(`src/command/MessageCommands.cxx`、gh apiで実際に
  取得し確認)の`handle_channels()`/`handle_send_message()`はいずれも
  `client.GetPartition().clients`(自分の所属パーティションのクライアント集合)のみを走査し、
  他パーティションのクライアントの購読は対象外。`Client::SetPartition()`
  (`src/client/Client.cxx`)は所属`partition->clients`の付け替えのみで購読自体は破棄しない
  ため、「どのパーティション所属として扱われるか」は購読時点ではなく`channels`/
  `sendmessage`呼び出し時点の"現在の"所属で動的に決まる仕様であることも確認した
  (partition_get()の毎回動的解決と同じ設計が正しい)。rmpc本体(mierak/rmpc)は
  subscribe/channels/sendmessage/readmessagesを単なる飾りではなく実IPC基盤として使用
  しており、`rmpcd/src/lua/lualib/mpd/c2c.rs`がLuaスクリプト向けc2c APIを実装、
  `rmpc/src/core/command.rs`の`client.send_message()`でCLIから直接メッセージ送信できる。
  rmpcは`--partition`オプションで複数インスタンスをパーティション単位に隔離する設計
  (`rmpc-mpd/src/client.rs`)を持つため、複数rmpc/rmpcdインスタンスをそれぞれ別
  パーティションで動かすマルチルーム構成では、本来隔離されるべきc2cメッセージ/
  チャンネル一覧が現状漏れ、無関係な別パーティションのLuaスクリプトへ誤配送・傍受され
  うる実害がある。なお`sendmessage`が購読者0人時に`ACK_ERROR_NO_EXIST
  "nobody is subscribed to this channel"`を返す部分は既存実装が既に実MPD仕様通りのため
  無変更。
  verified: mpdchannelpartition-patch.py。translator.pyの`channel_list()`/
  `channel_push_message()`に`partition`引数を追加し、各購読セッションの所属
  パーティション(`partition_get(session_id)`、呼び出し時点で動的解決、
  mpdoutputpartitionempty-patch.pyと同じ流儀)が一致するものだけを対象にするよう変更。
  `channels.py`の`channels()`/`sendmessage()`から`translator.partition_get(
  id(context.session))`を渡すよう変更(subscribe/unsubscribe/readmessagesはセッション
  単位で自己完結しておりパーティションの影響を受けないため無変更)。パッチ適用後の
  生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)
  であることも確認。`nix/lib/mopidy-env.nix`のmpdPatchesリストに
  mpdoutputpartitionempty-patch.pyの直後として登録しビルド成功。dev mopidy(6601)を
  実際に起動し、2本のTCP接続(A/B)を実際に張ってMPDで実機確認 — ①A: `newpartition work`
  →`partition work`→`subscribe foo`。②B(default): `channels`→修正前なら
  `channel: foo`が返るところ、修正後は空(OKのみ)を確認。③B(default):
  `sendmessage foo hi`→修正前ならOK(誤配送)、修正後は`ACK ... nobody is subscribed
  to this channel`を確認。④B: `partition work`に切替後`channels`→`channel: foo`が
  正しく見えることを確認(同一パーティションでの可視性は無変更)。⑤B:
  `sendmessage foo hello2`→OK、A側`readmessages`→`hello2`のみ受信(パーティション外の
  誤配送メッセージ`hi`は含まれない)を確認。⑥後片付けで`delpartition work`が
  正常応答することも確認。回帰確認: 単一パーティション(default同士)での
  `subscribe`/`channels`/`sendmessage`/`readmessages`/`unsubscribe`一連の従来動作、
  および`status`/`tagtypes`/`listpartitions`いずれも従来通り正常応答、mopidy.logに
  Traceback/ERROR新規発生なしを確認した。
- [x] `mopidy_mpd/protocol/music_db.py` の `count()`/`searchcount()` が共有する
  `_mpd_count_grouped()` が、両者に対し無条件で `case_sensitive=False` をハードコード
  しており、`count` が本来持つべき大文字小文字を区別する挙動が実装されていない不具合。
  TODO/既知の残課題を全項目消化済みのため自走エージェントが(general-purpose
  サブエージェントへの調査委任を経て)新規発見した項目。実MPD本体
  (`src/command/DatabaseCommands.cxx`、gh apiで実際に取得し確認) は
  `handle_count()` → `handle_count_internal(..., fold_case=false)`、
  `handle_searchcount()` → `handle_count_internal(..., fold_case=true)` という非対称
  仕様で、`count` は `find` と同じ大文字小文字を区別する厳密一致、`searchcount` のみ
  `search` と同じ大文字小文字を区別しない一致 (musicpd.orgのドキュメントにも
  「searchcountはFILTERがsearchと同様に大文字小文字を区別せずに一致する点を除き
  countと同じ」と明記)。本ファイルの `find()`/`search()` 自体は
  `_mpd_filter_negatives`/`_mpd_filter_positives` にそれぞれ
  `case_sensitive=True`/`False` を正しく渡し分けている
  (`mpdnegfilter-patch.py`/`mpdfilterkind-patch.py` 由来の規約) のに、
  `_mpd_count_grouped()` だけがこの規約から漏れ、`mpdfilterkind-patch.py`/
  `mpdsearchdiacritics-patch.py` が積み上げた現行実装は両方の呼び出しで
  `case_sensitive=False` を直書きしたまま据え置かれていた。実害:
  フィルタ式 `(TAG OP "VALUE")` 1条件だけの `count` でも即座にこの経路を通る。
  ライブラリに実タグ `Artist: YOASOBI` の曲がある状態で `find "(Artist == \"yoasobi\")"`
  (大小不一致) は正しく0件を返すのに対し、`count "(Artist == \"yoasobi\")"` は本来
  同じく0件のはずが大小を無視して一致し `songs: 1` を返してしまい、兄弟コマンドが
  同一フィルタに対し矛盾した結果を返していた。従来形式の複数タグペア
  `count artist "x" album "y"` (`mpdfindmultitag-patch.py` 由来の `__mpd_positives__`
  経由) でも同様に誤爆する(単一タグペアの旧来形式 `count artist "x"` は元々
  backendへの丸投げのみでローカル後段フィルタの対象外であり `find artist "x"` と
  同じ既存の別制約のため今回は対象外・無変更)。
  verified: mpdcountcase-patch.py。`mpdsearchcount-patch.py`(exact引数)/
  `mpdsearchdiacritics-patch.py`(strip_diacritics引数)と全く同じ流儀で、
  `_mpd_count_grouped()` に `case_sensitive=True` (デフォルト、実MPDのcountと一致)
  引数を追加しgroup再帰へも伝播、`searchcount()` 側だけ明示的に
  `case_sensitive=False` を渡すよう変更。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w` して `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix` に `mpdchannelpartition-patch.py` の直後として登録し
  ビルド成功。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、実データ
  (YOASOBI 楽曲群を `search any`/`findadd` でライブラリ確認・キュー投入) で MPD 実機
  確認 — `find "(Artist == \"YOASOBI\")"`(正しい大小)→ヒット、
  `find "(Artist == \"yoasobi\")"`(誤った大小)→0件、修正前は同条件の
  `count "(Artist == \"yoasobi\")"` が `songs: 1` 以上を誤って返していたところ、
  修正後は `find` と整合し `songs: 0` に是正されたことを確認。回帰確認:
  `count "(Artist == \"YOASOBI\")"`(正しい大小)→ `songs: 5`(従来通りヒット)、
  `searchcount "(Artist == \"yoasobi\")"`/`searchcount "(Artist == \"YOASOBI\")"`
  (大小いずれも)→ともに `songs: 5`(searchcountは従来通り大小を区別せず無変更)、
  旧来形式の複数タグペア `count artist "YOASOBI" album "the book 2"`(album部分の
  大小誤り)→ `songs: 0`、正しい大小 `count artist "YOASOBI" album "THE BOOK 2"`→
  `songs: 8`(多義曲込み)と、legacy multi-tag経路でも正しく大小を区別することを確認。
  `count "(Artist != \"YOASOBI\")"`(group無し・肯定条件無し)は
  `mpdnegonlyfilter-patch.py` 由来の既存仕様通り `ACK incorrect arguments` のまま
  無変更(否定のみはgroup指定時のみ許容という既存制約、今回のバグとは無関係)。
  `count group artist`/`count "(...)" group album` 等 group 系は、このdev環境の
  ytmusic personal library認証がテスト時点で切れており `get_distinct` 自体が空を返す
  既知の環境制約(`mpdnegonlyfilter-patch.py` 検証時と同じ制約、`list album`/
  `list artist` も同様に空)のため実データでは未検証だが、`_mpd_count_grouped` の
  group再帰呼び出しへの `case_sensitive` 伝播は `exact`/`strip_diacritics` と全く同じ
  位置引数渡しのパターンで実装しておりdiff上も対称であることをコード上確認。
  旧来の `findadd`/`playlistinfo`/`status`/`tagtypes`/`list album`/`list artist` の
  回帰なし・mopidy.log に Traceback/ERROR 0件を確認した。
- [x] `mopidy_mpd/protocol/stored_playlists.py` の `playlistmove {NAME} {FROM} {TO}` が、
  FROM が well-formed な空範囲 (`START:END` で `START == END`) のとき、TO がプレイリスト長
  を超えていると誤って `ACK Bad song index` を返してしまう不具合。TODO/既知の残課題を
  全項目消化済みのため自走エージェントが(general-purpose サブエージェントへの調査委任を
  経て)新規発見した項目。実MPD本体 (`src/command/PlaylistCommands.cxx` の
  `handle_playlistmove`、gh apiで実際に取得し確認) は
  `if (from.IsEmpty() || from.start == to) return CommandResult::OK;` であり、
  `IsEmpty()` (`start == end`) は `start == to` と全く対等なOR条件として即座に無条件 OK
  を返す (プレイリストの存在確認・TOの範囲チェックにすら進まない)。対して本実装は
  `start == to_pos` の早期returnしか実装しておらず、`start == end` かつ
  `start != to_pos` のケースではそのままロック取得・`_get_playlist()`・境界チェック
  `end > len(tracks) or to_pos > len(tracks) - count` (count=0) へ進んでしまい、
  `to_pos > len(tracks)` だと実MPDなら無条件OKのところ誤って `ACK Bad song index` を
  返していた。兄弟コマンド `move_range()` (current_playlist.py) には
  mpdrangeempty-patch.py で既に `if start == end: return` のガードが入っているのに、
  同パッチのコメントが「playlistmoveは素のスライス/既存チェックだけで正しくno-op扱い
  できる」と誤って結論づけたまま `playlistmove()` だけガードが漏れていた、典型的な
  「兄弟コードパスの取りこぼし」。
  verified: mpdplaylistmoveempty-patch.py。`start == to_pos` の早期returnの直後に
  `start == end` の早期returnを追加し、move_range()と同じくFROMが空範囲の場合は
  プレイリストの存在確認・TOの範囲チェックより前に無条件でOKを返すよう修正。パッチ
  適用後の生成ソースは一時コピーに `chmod u+w` して `ast.parse` で構文確認、2回適用
  しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix` に
  `mpdcountcase-patch.py` の直後として登録しビルド成功。dev mopidy(6601, ytmusic
  実アカウント) を実際に起動し、実データ (YOASOBI 検索結果2曲を `findadd` でキュー投入
  → `save testpl` でストアドプレイリスト化) で MPD 実機確認 —
  **バグ再現**: `playlistmove "testpl" "0:0" "52"` (2曲のプレイリストに対しTOが範囲外)
  → 修正前なら `ACK [2@0] {playlistmove} Bad song index` のところ、修正後は実MPD通り
  `OK` (無変更) を確認。存在しないプレイリストに対しても `playlistmove
  "does-not-exist-xyz" "5:5" "0"` (空範囲) → `OK` (実MPDの`IsEmpty()`が存在確認より前に
  効くのと同じ挙動)、対して非空範囲 `playlistmove "does-not-exist-xyz" "5:6" "0"` →
  従来通り `ACK [50@0] {playlistmove} No such playlist` (既存の存在確認は無変更) を確認。
  回帰確認: `playlistmove "testpl" "0:0" "0"` (start==to_pos、既存の早期return経路)→
  従来通り `OK`、`playlistmove "testpl" "0" "1"` (実際に1曲移動)→ `OK` かつ
  `listplaylistinfo testpl` の曲数2件で無変更(正しく入れ替わったことを確認)、
  `playlistmove "testpl" "0:1" "52"` (非空範囲でTOが範囲外)→従来通り
  `ACK [2@0] {playlistmove} Bad song index` (既存の境界チェックは無変更) を確認。
  mopidy.log の YTMusicBackend による `save` 時の副作用的な `HTTP 401 Unauthorized`
  (`create_playlist`、mpdcountcase-patch.py 検証時と同じ既知のdev環境ytmusic認証切れに
  よるもので `save` 自体は m3u バックエンドで成功しており本件と無関係) を除き
  Traceback/ERROR 新規発生なし。旧来の `findadd`/`save`/`listplaylistinfo`/`rm`/`status`
  の回帰なしを確認した。
- [x] `find`/`search`/`count`/`searchcount`/`findadd`/`searchadd`/`searchaddpl`/
  `searchplaylist`/`playlistfind`/`playlistsearch` が共有するフィルタ式パーサ
  `_query_from_mpd_filter_expression()`/旧式パーサ `_query_from_mpd_search_parameters()`
  (music_db.py) が、実MPD (musicpd.org protocol、Filters節) の `(base "DIR")` 疑似タグ
  (検索範囲をディレクトリ配下に限定する特殊フィルタ) を一切認識しない不具合。TODO/
  既知の残課題を全項目消化済みのため自走エージェントが(general-purposeサブエージェント
  への調査委任を経て)新規発見した項目。実MPD本体 (MusicPlayerDaemon/MPD、gh apiで
  実際にソース取得し確認) の `src/song/Filter.cxx` は `base` を通常のタグ種別とは別の
  特別な擬似タグ (`LOCATE_TAG_BASE_TYPE`) として認識し、対応する `BaseSongFilter`
  (`src/song/BaseSongFilter.cxx`) は `fold_case`/`strip_diacritics` を一切受け取らず
  常に生のURI文字列を `uri_is_child_or_same()` (`src/util/UriRelative.cxx`、
  `suffix=StringAfterPrefix(child,parent)`; `suffix&&*suffix&&(suffix==child||
  suffix[-1]=='/'||*suffix=='/')` というディレクトリ境界判定、かつ空parent="ルート"は
  常に一致) でディレクトリ境界判定する、`(TAG OP "VALUE")` の一般形とは別枠の演算子を
  取らない特殊構文。現状の `_query_from_mpd_filter_expression()` は `head.split()` の
  結果を `len(parts) >= 2` でしか処理しないため、`(base "DIR")` は `head` が `"base "`
  → `parts == ["base"]` (長さ1) となりこのブロックを完全に素通りする。実害: `base`
  単独指定は `query` が空のまま `require_positive` チェックに引っかかり
  `ACK incorrect arguments` (実MPDでは配下の全曲を返すべき正当な問い合わせだが常に
  拒否される)、他のタグ条件と `AND` 併用時は `base` 節が完全に無視されエラーも出さず
  ディレクトリ制限なしの全件が返ってしまう(静かな誤りで最も実害が大きい)。旧式引数列
  パーサ (`find base "DIR"`) 側も `mapping.get("base")` が常に `None` になるため同じく
  `ACK incorrect arguments` で拒否される。BACKLOG.md を `grep -n -i "\bbase\b"` で確認
  したが `gst-plugins-base` 等の無関係ヒットのみで既存パッチとの重複はない。
  verified: mpdbasefilter-patch.py。既存の negatives/positives 後段フィルタ機構
  (mpdnegfilter-patch.py/mpdfilterkind-patch.py) に `kind="base_dir"` を追加する形で
  配線 (backendの `library.search()`/`get_distinct()` は "base" を理解しないため
  query本体には一切触れず、必ず `__mpd_positives__`/`__mpd_negatives__` 経由のローカル
  後段フィルタとしてのみ効かせる。一致判定は `_mpd_negative_field_values(track,"uri")`
  = `[track.uri]` を流用し `_mpd_base_dir_matches()` で実MPDの `uri_is_child_or_same`
  と同じロジックを実装、fold_case/strip_diacriticsは常に対象外)。実装中に、
  `_query_from_mpd_search_parameters()`/`_query_from_mpd_filter_expression()` は
  music_db.py の `find`/`search`/`count`/`findadd`/`searchadd`/`searchaddpl` だけでなく
  `stored_playlists.py` の `searchplaylist()`、`current_playlist.py` の
  `playlistfind`/`playlistsearch` とも共有されているが、後者2つは `_mpd_filter_positives`
  ではなく独自実装の `_pf_matches()` (current_playlist.py) で positives/negatives を
  判定しており、`kind="base_dir"` がどの `elif` にも一致せず静かに無視される(素通りで
  無条件「合格」扱い)別の欠落を発見、`_pf_matches()` にも同じ `_mpd_base_dir_matches()`
  を再利用したbase_dir分岐を追加。さらに `searchplaylist()` は
  `_mpd_pop_positives()`/`_mpd_pop_negatives()` で `__mpd_positives__`/
  `__mpd_negatives__` を `query` から取り出した後に独自の `if not query:` 空判定を
  持っており、base単独指定(queryは本来空でpositivesのみ)がこの独自チェックにも誤って
  弾かれることを発見、`if not query and not positives:` に修正 (`playlistfind`/
  `playlistsearch` 側の `_pf_search()` は元々 `if not query and not negatives and not
  positives:` と既に許容的で無変更)。パッチ適用後の生成ソース(music_db.py/
  current_playlist.py/stored_playlists.pyの3ファイル)は一時コピーに `chmod u+w` して
  `ast.parse` で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix` に `mpdplaylistmoveempty-patch.py` の直後として登録し
  ビルド成功。dev mopidy(6601, ytmusic 実アカウント) を実際に起動し、実データ
  (`find "(artist == 'Titanium T')"` で15件のalbum/track擬似エントリを確認) で MPD
  実機確認 — `find "(artist == 'Titanium T') AND (base 'nonexistent/dir')"`
  (存在しないディレクトリとAND併用、修正前ならbase節が無視され15件そのまま返っていた
  はずの箇所)→ `songs`系0件でOK是正、`find "(artist == 'Titanium T') AND (base '')"`
  (空文字列=ルート、実MPD `uri_is_child_or_same` のparent=="" は常に一致するロジック
  通り全件マッチ)→15件そのまま(root相当)、`find "(artist == 'Titanium T') AND
  (base '<15件中の1件の実uri>')"` (完全一致するuriそのものをbase指定)→そのuriの1件のみ
  ヒットしディレクトリ境界判定の完全一致経路(`uri==base_dir`)を確認、同条件を
  `!(base '<uri>')` へ変えると15件中その1件だけ除外され14件に是正(否定側の経路も
  確認)、legacy構文 `find artist "Titanium T" base "nonexistent/xyz"`/
  `find artist "Titanium T" base "<実uri>"` でも同じ挙動(0件/1件)を確認、`find
  "(base contains 'x')"` (baseに演算子を付けた誤用)→従来通り `ACK Unknown filter
  type: base` を維持(base単独指定の特殊構文以外は通常のタグ探索と同じエラー経路である
  ことを確認)。`count "(artist == 'Titanium T') AND (base 'nonexistent/xyz')"`→
  `songs: 0`、同条件を `base ''` にすると `songs: 5`(count側の正しいAND是正も確認)。
  `searchplaylist`: `findadd`→`save` で5曲のストアドプレイリストを作成し
  `searchplaylist NAME "(base '')"`→全5件、`searchplaylist NAME "(base
  'nonexistent/xyz')"`→修正前ならALL5件を誤って返していたところ、修正後は `OK`
  (0件)に是正、`searchplaylist NAME "(base '<実uri>')"`→その1件のみ、`searchplaylist
  NAME "(artist == 'Titanium T') AND (!(base '<実uri>'))"`→残り4件(否定+AND併用の
  是正も確認)、`searchplaylist NAME "(!(base '<実uri>'))"`(否定のみ、他の正条件無し)→
  実MPD仕様上の既存制約(mpdnegonlyfilter-patch.py由来、否定のみの単独フィルタは
  そもそも不許可)通り `ACK incorrect arguments` を維持(この制約はbase追加の前後で
  変化なし、意図通り)。`playlistfind`/`playlistsearch` (キュー内、`_pf_search`) でも
  legacy構文 `playlistfind base "nonexistent/xyz"`→0件・`playlistfind base
  "<実uri>"`→1件、`playlistsearch`(大小無視系)でも同様に1件ヒットを確認。回帰確認:
  `find`/`search any`/`count any`/`status`/`tagtypes`/`listmounts`/`listpartitions`/
  `channels`/`crossfade`/`sticker get`(no such sticker応答)の従来動作に変化なし。
  mopidy.log は既知の dev 環境 ytmusic 認証切れによる `save`/`create_playlist` の
  `HTTP 401 Unauthorized` (mpdcountcase-patch.py/mpdplaylistmoveempty-patch.py 検証時と
  同じ既知の制約) を除き Traceback/ERROR 新規発生なし。
  既知の制約: mopidy の library は backend 非依存の tag ベース検索で実MPDのような
  「music_directory 相対パス」の概念を持たないため、`base` は track.uri (backend固有の
  完全URI) そのものに対するディレクトリ境界一致となる。ローカルファイルbackend
  (`file:///.../Artist/Album/...`) では実MPDと同じ意味を持つが、この開発環境で唯一
  有効な mopidy_ytmusic の URI (`ytmusic:track:xxx` 等) は "/" を含む階層を持たないため
  実用上ほぼ意味を持たない(mount/crossfadeと同種の、mopidy core自体が持たない機能に
  対する割り切り。上記の実機確認では実uriそのものをbase値に使う完全一致経路と、
  空文字列/存在しないディレクトリ文字列という3パターンで境界判定ロジック自体は
  十分に検証済み)。
- [x] `mopidy_ytmusic/playlist.py` の `YTMusicPlaylistsProvider.lookup()` が、返却する
  `Playlist.uri` を要求id (`bId`、URIから既に解決済みの正しい値) からではなく、
  `api.get_playlist()` 応答の `pls["id"]` から組み立ててしまう不具合。TODO/既知の
  残課題を全項目消化済みのため自走エージェントがgeneral-purposeサブエージェントへ
  新規不具合調査を委任し発見・着手した項目。
  実害: インストール済み ytmusicapi 1.12.0 (`mixins/playlists.py` `get_playlist()`)を
  実際に確認したところ、`playlist["id"]` の由来は owned/非owned で全く異なる ——
  自分が作成した(owned)プレイリストは `EDITABLE_PLAYLIST_DETAIL_HEADER` 配下の
  実プレイリストID(要求bIdと一致)だが、他者作成でライブラリに保存しただけ(非owned、
  YouTube Musicで公開プレイリストを「保存」する一般的な操作で普通に発生する)の
  プレイリストは `RESPONSIVE_HEADER` の `buttons[1]`(Playボタン)
  `.musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint.playlistId`
  (`nav(..., True)` でNone許容の別物のwatchプレイリストID)になる。
  `mopidy_mpd/protocol/stored_playlists.py` の `_get_playlist()` は
  `context.core.playlists.lookup(uri)` の戻り値を `playlistadd`/`playlistclear`/
  `playlistdelete`/`playlistmove`/`rename`/`save` 等あらゆる編集系MPDコマンドの起点に
  使い、`.replace(...)` した上で `save()` (同ファイルの `bId = parse_uri(playlist.uri)`
  で対象再解決) へ渡すため、非owned(ライブラリ保存)プレイリストへのrmpc等からの
  編集操作は、watchプレイリストIDがNoneならサイレントな編集無視、要求idと異なる
  実在IDなら全く無関係なプレイリスト/ラジオへの誤動作という、いずれにせよ静かに
  壊れた挙動になる。`as_list()`/`create()`/`save()`は既に要求id基準でURIを組み立てて
  おり `lookup()` だけが非対称だった。
  verified: ytplaylistlookupid-patch.py。`lookup()` の返却 `uri` を応答の `pls["id"]`
  ではなく要求時に確定している `bId` から組み立てるよう修正 (`as_list()`/`save()`と
  同じ「要求id」の流儀へ統一)。パッチ適用後の生成ソースは一時コピーに`chmod u+w`して
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  **実アカウントでの実データ確認**: dev mopidy(6601, ytmusic実アカウント)を実際に
  起動し、`ytmusic:home`配下の9セクション(Trending community playlists/Hits
  throughout the decades/All time biggest hits等)から収集した36件の多様な非owned
  プレイリスト(`RDCLAK5uy_`系editorial、`PL`系community、`OLAK5uy_`系album由来、
  `RDTMAK5uy_`系algorithmic)全てで`core.playlists.lookup()`のJSON-RPC呼び出しを
  行い、応答の`pls['id']`が要求`bId`と一致する(=このアカウントで実際に遭遇した
  非owned応答では乖離が再現しなかった)ことを一時デバッグログで確認。乖離が実データで
  再現しなかったため、`ytalbumidcache-patch.py`と同じ前例に倣い**オフライン単体テスト**
  で決着 — `YTMusicPlaylistsProvider`を`object.__new__`で直接instantiateし
  `self.backend`を`MagicMock`化した上で、`pls['id']`(`"RDAMPLdifferent999"`)が要求
  `bId`(`"PLrequested123"`)と異なる合成の非owned応答を`get_playlist()`のモック戻り値
  として与えて`lookup()`を直接呼び出し — 修正前(未パッチ`playlist.py`)は
  `uri: ytmusic:playlist:RDAMPLdifferent999`(要求と無関係な誤ったプレイリストを
  指す)を返し不具合を実際に再現、修正後は`uri: ytmusic:playlist:PLrequested123`
  (要求通り)を返すことを確認。回帰確認: `pls['id']`が要求`bId`と一致する通常の
  owned応答では修正前後とも`uri: ytmusic:playlist:PLrequested123`で変化なし。
  `nix/lib/mopidy-env.nix`の`ytmusicPatched`に`ytlastidrace-patch.py`の直後として
  登録しビルド成功、生成ソースの`lookup()`に新実装が反映されていることを確認した
  上でdev mopidy(6601, ytmusic実アカウント)を実際に起動しMPDで確認 — 既存の
  owned実テストプレイリスト(`soloTest`)に対し`rename "soloTest"
  "soloTest_verify_rt"`→`OK`→`rename "soloTest_verify_rt" "soloTest"`→`OK`で
  `listplaylists`が元通り、`playlistadd "soloTest" "ytmusic:track:qDL3zhB8-MM"`
  (YOASOBI実曲)→`OK`→`listplaylistinfo soloTest`で正しく1曲追加を確認→
  `playlistclear "soloTest"`で後始末、`tagtypes`/`status`/`find artist
  "YOASOBI"`の回帰なしを確認。mopidy.log は既知のshutdown時ソケットエラー
  (`stop.sh`のSIGTERM起因、`mopidy_mpd/network.py`の`server.stop()`が既に閉じた
  ソケットへ`shutdown()`する既存の無関係な事象、本パッチと無関係)を除き
  Traceback/ERROR 新規発生なし。
- [x] `mopidy_mpd/translator.py` の `track_to_mpd_format()` が `Track` タグを組み立てる際、
  `track.album.num_tracks`(アルバムの総トラック数)が既知だが `track.track_no`
  (mopidy core `Track.track_no` のデフォルト値は `None`、実際に
  `python3 -c "from mopidy.models import Track; print(Track().track_no)"` で確認済み)が
  未知の曲で `f"{track.track_no or 0}/{num_tracks}"` により `Track: 0/N` という
  「トラック0番」を捏造してしまう不具合。TODO/既知の残課題を全項目消化済みのため
  自走エージェントがgeneral-purposeサブエージェントへ新規不具合調査を委任し発見・
  着手した項目。
  実害: 実MPD(TRACKNUMBERタグの値をそのまま透過するのみ)はファイルにTRACKNUMBERタグが
  無ければTrackフィールド自体を出力せず、位置(N)不明のまま総数(M)だけを"0/M"として
  捏造する経路は実MPDのいかなる実装にも存在しない。加えて直後の`_has_value()`による
  フィルタは`bool(value)`判定のため、album無しの経路の`track.track_no or 0`(int 0)は
  falsyとして除去される一方、album有りの経路のf-string"0/N"(非空文字列)は常にtruthyで
  除去されない、という実装内で閉じた非一貫性でもあった。mopidy_ytmusicの
  `uploadAlbumToTracks()`(library.py、track_no=None固定+album.num_tracks既知)が
  常にこの組み合わせを生成するため、YouTube Musicの「アップロード」ライブラリの
  アルバムをブラウズ/再生するだけで全曲が`Track: 0/N`として返る。rmpc本体
  (mierak/rmpc)を実際にcloneしてソース確認したところ、rmpc/src/ui/song_ext.rs
  `SongProperty::Track`(トラック番号列表示)とrmpc/src/ui/dir_or_song.rs
  (トラック番号によるソートキー)の双方がこの値を素の整数として
  `parse::<u32>()`/`opt_str_parse`するため、"0/12"のような"/"を含む文字列はparseに
  失敗し、表示欄がフォールバックの生文字列化・ソート順の破綻を招く実害あるギャップと
  確認した上で着手。
  verified: mpdtracknofabricate-patch.py。track_no が None (未知) のときは
  album.num_tracksが既知でもTrackタグ自体を出力しない(Genre/Disc等の他の
  「無ければ省略」系タグと同じ流儀に揃える)よう修正。track_noが明示的に0
  (実ファイルのTRACKNUMBER="0"相当)の場合の既存挙動は無変更。パッチ適用後の
  生成ソースは一時コピーに`mopidy_mpd/`ディレクトリ構造を再現して当ててから
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`の`mopidyPatched`に`mpdbasefilter-patch.py`の直後として
  登録しビルド成功。**実データ確認**: dev mopidy(6601, ytmusic実アカウント)を
  実際に起動したが、このテストアカウントには「アップロード」ライブラリ自体が
  存在せず(`lsinfo "YouTube Music"`に該当ディレクトリなし)不具合の自然再現は
  不可だったため、`ytplaylistlookupid-patch.py`と同じ前例に倣い**インストール済み
  パッチ適用後の実モジュールを直接importするオフライン単体確認**で決着 ——
  `mopidy.models.Track`/`Album`の実オブジェクトを使い、(1)`track_no=None`+
  `album.num_tracks=12`→修正前は`Track: 0/12`を捏造していたケースが修正後は
  `Track`キー自体が出力されないことを確認、(2)`track_no=None`+`album=None`→
  従来通り出力なし(無変更)、(3)`track_no=5`+`album.num_tracks=12`→`Track: 5/12`
  (回帰なし)、(4)`track_no=0`明示+`album.num_tracks=12`→`Track: 0/12`のまま
  (既存挙動を意図通り維持)、(5)`track_no=7`+`album=None`→`Track: 7`(回帰なし)、
  の5ケース全て期待通り。**実データでの回帰確認**: 同dev mopidyで実際に
  `search any "YOASOBI"`→`ytmusic:album:MPREb_a5PIYyducZQ`をヒットさせ
  `lsinfo`でアルバム内の実トラックを取得→`Track: 1/12`が正しく表示されることを
  確認(album経由の通常トラックは無変更で正しく動作)、同トラックを`add`して
  `playlistinfo`(Pos/Id付きのキュー経路)でも`Track: 1/12`が回帰なく表示されることを
  確認。旧来の`tagtypes`/`status`/`list album`の回帰なしも確認。mopidy.logには
  このdev環境で既知の無関係な事象(検索結果に含まれる削除/非公開動画への
  `getTrack()`が`KeyError: 'videoDetails'`を送出する既存の未パッチ挙動、
  `ytlookuptrackfail-patch.py`が既に文書化済みの別issueで本パッチとは無関係、
  translator.py側の新規Tracebackはゼロ)を除き新規ERROR/Traceback発生なし。
- [x] `mopidy_ytmusic.library.py` の `parseSearch()` (resultType=="song"分岐) が、
  rmpc既定タグ(`Tag::Any`)に対応する `search any`/`find any` (ytmusicapiの
  `search(filter=None)`、「トップリザルト」形状の応答) 経由で得た曲のArtistを
  丸ごと欠落させる不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  general-purposeサブエージェントへ新規不具合調査を委任し発見・着手した項目。
  実害: 実データ(dev mopidy, ytmusic実アカウント)で`search any "yoasobi"`/`"Ado"`/
  `"Kenshi Yonezu"`を実際に送信して確認したところ、返るsong系レコード全件で
  Artist/AlbumArtist行が完全に欠落する一方、同じ曲・同じ環境で`search title "Idol"`/
  `find artist "Ado"`(tag指定=filter="songs"/"artists"経由)は正しくArtist/Albumを
  返した。原因はfilter=None応答のsongエントリのartistsが実データで
  `[{"name": "Song", "id": None}]`のようなresultType誤表記のダミーのみ、または空に
  なる恒常的なケースで、既存のytartist-patch.pyはこのダミーを正しく除外するが
  除外後の代替取得手段が無く、artists=[]のままTrackが作られていた。rmpcの検索ペインは
  既定タグがAnyのため通常の検索操作で常にArtist列が空白になり、加えて
  `context.core.playlists.lookup()`等の編集系コマンドが経由するlibrary.lookup()は
  self.TRACKSキャッシュヒットを最優先で返すため、一度でもsearch経由で登録された曲は
  同一プロセスの残り寿命ずっとArtist欠落のまま(getTrack()のapi.get_song()
  フォールバックへは二度と到達しない)という実害あるギャップと確認した上で着手。
  verified: ytsearchsongartist-patch.py。parseSearch()のsong分岐でresultType誤表記
  ダミー除外後にartistsが空になった場合のみ、`self.getTrack(videoId)`
  (内部でapi.get_song()を呼びvideoDetails.authorから実アーティスト名を取得)へ
  フォールバックしその`.artists`を採用するよう修正 (search結果自体に十分な
  artistsがある通常検索は従来通り追加API呼び出し無し)。フォールバック導入前に、
  dev mopidy(6601, ytmusic実アカウント)を実際に起動しHTTP JSON-RPC
  (`core.library.lookup`)でmopidyを一度再起動しキャッシュをクリアした直後の
  fresh lookupが`ytmusic:track:by4SYYWlhEs`(YOASOBI「夜に駆ける」)に対し
  `artists: [{"name": "YOASOBI"}]`を実際に返すことを確認し、getTrack()フォールバック
  自体が有効であることを裏付けた上で着手(同じbIdをsearch経由で先に登録した状態での
  lookupは修正前artists欠落を再現・確認済み)。パッチ適用後の生成ソースは一時コピーに
  `chmod u+w`して`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`の`ytmusicPatched`に`ytplaylistlookupid-patch.py`の直後として
  登録しビルド成功。**実データでの修正確認**: dev mopidy(6601, ytmusic実アカウント)を
  実際に起動しMPDで確認 — 修正前は`search any "yoasobi"`/`"Ado"`/`"Kenshi Yonezu"`の
  song系レコード全件でArtist行が欠落していたのが、修正後は同じ3クエリ全件で正しい
  `Artist: YOASOBI`/`Artist: Ado`/`Artist: Kenshi Yonezu`が付与されることを確認、
  `find any "Ado"`(findコマンド側)でも同様に是正。実際に`search any "Ado"`→
  `add "ytmusic:track:TPMdLG7LO-4"`→`playlistinfo`と操作しキュー経路
  (Pos/Id付き)でもArtist行が正しく反映されることを確認(検索画面だけでなく
  実際にadd/再生する経路まで是正されることを確認)。回帰確認: `search title "Idol"`/
  `find artist "Ado"`(tag指定=通常のfilter=songs/artists経由、修正前から動作していた
  経路)、`tagtypes`、`status`、`count any "yoasobi"`、`list album`は無変更で回帰なし。
  mopidy.log に Traceback/ERROR 0件を確認。
- [x] `mopidy_ytmusic/library.py` の `get_distinct()` の `field=="artist"/"albumartist"`
  分岐が引数 `query` を一切見ず、常に `get_library_artists()` の全件を返してしまう
  不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントがgeneral-purpose
  サブエージェントへ新規不具合調査を委任し発見・着手した項目。
  実害: `mopidy_mpd/protocol/music_db.py` の `list_()` のdocstring(MPDプロトコル
  公式仕様の引用)自身が挙げる最も基本的な例 `list "artist" "artist" "ABBA"`
  (「ArtistがABBAのものだけ列挙し `Artist: ABBA` / `OK` を返すべき」)すら効かず、
  実装は `query={"artist": ["ABBA"]}` を素通しして無条件に全アーティストを返す。
  同じ`get_distinct()`内の`album`分岐(`ytdistinctfilter-patch.py`で修正済み)と
  `date`分岐(`ytdistinctdate-patch.py`で修正済み)は既にqueryのartist/albumartist/
  date/albumキーで実際に絞り込む実装になっており、artist/albumartist分岐だけ
  取り残された非対称であることをソース比較で確認した。rmpc本体(mierak/rmpc)は
  `list`系コマンドを`rmpc-mpd`の`list_tag`/`list_tag_grouped`経由で呼び、
  AddRandomModal(グローバルアクション「ランダム追加」)のArtist/AlbumArtistタブ等
  queryで絞り込まれた応答を前提とする経路がある。フィルタが効かないと本来1件に
  絞られるべき応答が常にライブラリ全件になり、絞り込み前提の処理が実質機能しない
  実害あるギャップと確認した上で着手。
  verified: ytartistfilterlist-patch.py。get_distinct()のartist/albumartist分岐に
  album/date分岐と同じ流儀でqueryのartist/albumartistキーの値による等値フィルタ
  (小文字比較、値が無ければ従来通り全件)を追加。パッチ適用後の生成ソースは
  一時コピーに`mopidy_ytmusic/`ディレクトリ構造を再現して当ててから`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  `ytmusicPatched`に`ytsearchsongartist-patch.py`の直後として登録しビルド成功。
  **実データ確認**: dev mopidy(6601, ytmusic実アカウント)を実際に起動したが、
  このテストアカウントは`list artist`/`list album`/`list date`いずれも0件
  (フォロー中アーティスト・保存アルバムとも無し)で、実データでの絞り込み効果自体は
  自然再現不可だったため、`mpdtracknofabricate-patch.py`と同じ前例に倣い**インストール
  済みパッチ適用後の実モジュールを直接importするオフライン単体確認**で決着 ——
  実際の`YTMusicLibraryProvider.get_distinct()`をfakeの`get_library_artists()`
  (Artist One/Artist Twoの2件を返す)に対して呼び、(1)query無し→修正前と同じ
  `{'Artist One', 'Artist Two'}`(無変更、回帰なし)、(2)`{"artist": ["Artist One"]}`→
  `{'Artist One'}`のみ(修正前は2件とも返っていたはずのケースが正しく絞り込まれる)、
  (3)`{"artist": ["ZZZ_NOPE"]}`(存在しない名前)→空集合、(4)`{"albumartist":
  ["Artist Two"]}`→`{'Artist Two'}`のみ(albumartistキーでも同様に効く)、
  (5)`{"artist": ["artist one"]}`(小文字)→`{'Artist One'}`(大小文字を無視して
  マッチ)の5ケース全て期待通り。**実データでの回帰確認**: 同dev mopidyを実際に
  起動しMPDで`list artist`/`list albumartist`/`list artist artist
  "ZZZ_NOT_A_REAL_ARTIST_XYZ"`/`list "artist" "artist" "ABBA" "artist" "TLC"`/
  `list album`/`list date`/`tagtypes`/`status`を実行、全てOKで応答しエラー無し
  (該当アカウントのデータが空のため絞り込み自体の効果は確認できないが、
  クラッシュ・ACK・応答形式の破壊が無いことは確認)。mopidy.logには自分で送った
  無関係なHTTP JSON-RPC直叩き(`core.library.get_distinct`の生戻り値が`set`で
  JSONシリアライズ不可というテスト起因の既知エラー、MPDプロトコル経由の通常呼び出し
  では発生しない)を除き新規ERROR/Tracebackなし。

- [x] `mopidy_mpd/protocol/tagtype_list.py`のTAGTYPE_LISTと`music_db.py`の
  `_LIST_MAPPING`/`_LIST_NAME_MAPPING`(find/search/list/count/sortが導出元と
  する`_SEARCH_MAPPING`/`_SORT_MAPPING`含む)が、実MPD本体が実際に認識する
  タグ名の一部(旧世代の18種+独自X-AlbumUriのみ)しかカバーしておらず、MPD
  0.24以降に追加された標準タグ名を丸ごと未登録にしていた不具合を修正。
  TODO全項目消化済みのため自走エージェントがgeneral-purposeサブエージェントへ
  調査を委任し新規発見。実MPD本体(MusicPlayerDaemon/MPD、gh apiで
  `src/tag/Names.cxx`を実際に取得し確認)には存在するが本実装に無かったタグ:
  AlbumSort/TitleSort/Mood/OriginalDate/ComposerSort/Conductor/Work/Movement/
  MovementNumber/ShowMovement/Ensemble/Location/Grouping/DiscSubtitle/Label/
  MUSICBRAINZ_RELEASETRACKID/MUSICBRAINZ_WORKID/MUSICBRAINZ_RELEASEGROUPIDの
  18種。実MPDはタグ名の認識と実データの有無を別々に扱うため対応データが無い
  タグでも`find`/`search`/`list`/フィルタ式で使用可能で単に0件応答になるが、
  本実装は未登録タグ名を渡されると`ACK incorrect arguments`/`ACK Unknown tag
  type`/`ACK Unknown filter type`で即座に拒否していた。rmpc(mierak/rmpc、
  `filter.rs`の`Tag::Custom(String)`)はAdvanced Searchで任意のタグ名を自由
  入力でき、mopidy-ytmusicがbrowse()で公開する「Mood and Genre Playlists」
  (ytmoodgenre-patch.py既存)からMoodというタグ名を試す導線が実在する。
  実装上の要注意点: mopidyのTrack/Album/Artistモデルにこれらのタグ用フィールド
  はそもそも存在せず、mopidy core自体(`mopidy/core/library.py`の`search()`/
  `get_distinct()`)が固定の既知フィールド集合でqueryを検証するため、単純に
  タグ名をbackendへ渡すクエリのキーとして追加すると`mopidy.exceptions.
  ValidationError`が未捕捉のままセッションが無応答切断される(元のACKより
  悪化する重大な回帰)ことを実機で確認した。このため最終実装は「タグ名としては
  認識するがbackendへは一切送らない」方式に変更: `_PHANTOM_TAG_FIELDS`という
  frozensetを追加し、find/search/count/findadd/searchadd/searchaddpl/
  searchplaylistの2種類のクエリパーサ(旧式TYPE-VALUE列/新式フィルタ式)が
  これらのタグを見たら`(base "DIR")`用の既存ローカルpositives機構
  (mpdbasefilter-patch.py)を流用してqueryへは書き込まずpositives/negatives
  のみへ積み、`list`/`count group TAG`の列挙(`_mpd_list_grouped`/
  `_mpd_count_grouped`)では対象フィールドがphantomなら`get_distinct()`を
  呼ばず即座に空を返すようにした。
  verified: mpdtagnames-patch.py。パッチ適用後の生成ソースを一時コピーに
  `mopidy_mpd/protocol/`構造を再現して当て`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の`mpdPatched`へ
  `mpdtracknofabricate-patch.py`の直後として登録しビルド成功。**実データ確認**:
  dev mopidy(127.0.0.1:6601、mopidy-ytmusic backend実アカウント)を実際に
  起動しMPDプロトコルで直接テスト —
  (1)`tagtypes`が新規18タグ全て(Mood/Conductor/DiscSubtitle等)を含めて応答、
  (2)`find mood "Chill"`/`search mood "Chill"`/`find "(Mood == \"Chill\")"`/
  `find "(Conductor == \"X\")"`/`count mood "Chill"`が(修正前のACKと異なり)
  いずれも`OK`(0件)で応答、
  (3)`list mood`/`list conductor`/`list album group mood`も`OK`(0件)で応答、
  (4)`find genre "Rock" mood "Chill"`/`find "(Genre == \"Rock\") AND (Mood ==
  \"Chill\")"`(実フィールドとphantomフィールドのAND併用)も`OK`(0件、正しく
  不成立)、
  (5)回帰確認として`find artist "a"`/`list artist`/`find "(base \"\")"`/
  `find "(artist == \"a\") AND (base \"\")"`/`search any "the"`(実データで
  実際に曲がヒット)が全て従来通り正常応答、mopidy.logに新規ERROR/Traceback
  無しも確認。

- [x] `mopidy_mpd/translator.py`の`track_to_mpd_format()`(playlistinfo/find/search/
  count/listplaylistinfo/currentsong/playlistfind/playlistsearch全コマンドが共有する
  唯一の整形関数)がGenre/Disc/Composer/Performer等の他の「値があれば出す」系タグを
  全て網羅する一方、`track.comment`だけは一切参照せずどの応答にも`Comment:`行を
  出力しない不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  general-purposeサブエージェントへ新規不具合調査を委任し発見。
  根拠: `Comment`は`mopidy_mpd/protocol/tagtype_list.py`のTAGTYPE_LISTに元々含まれる
  非フィクションのタグで、`session.py`はクライアント接続時の既定tagtypesに
  TAGTYPE_LIST全体(Comment含む)を設定する。実機で`tagtypes`を確認したところ
  実際に`tagtype: Comment`が応答に含まれ、rmpc等は接続直後から「Commentは有効」と
  伝えられる。にもかかわらず`track_to_mpd_format()`に`track.comment`を読む経路が
  一切無いため、実際に値を入れてもfind/search/playlistinfo/currentsongのどの応答にも
  絶対に出てこない。同じ`music_db.py`内の`readcomments`ハンドラ(mpdreadcomments-patch.py
  で有効化済み)は`tracks[0].comment`を直接読んで正しく返せており、`track.comment`が
  バックエンドの持つ正当なフィールドであることは実装内で既に証明済み。Genre/Discという
  他の「値があれば出す」系フィールドと全く同型の欠落であり、意図的なスコープ外ではなく
  単純な網羅漏れと確認した上で着手。
  実害: rmpc(mierak/rmpc)はテーマ/ソート設定で任意の`Tag::Custom("Comment")`を
  曲のプロパティ列やソートキーとして参照できるため、`tagtypes`がComment有効と
  宣言しているのに実データが常に空欄に見えてしまう。
  verified: mpdcommenttag-patch.py。`track.disc_no`/`track.last_modified`の間に
  Genre/Discと同じ流儀で`if track.comment: result.append(("Comment", track.comment))`
  を追加。パッチ適用後の生成ソースは一時コピーに`mopidy_mpd/`ディレクトリ構造を
  再現して当ててから`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix`の`mpdPatched`へ`mpdtagnames-patch.py`の直後として
  登録しビルド成功。**実データ確認**: dev mopidy(127.0.0.1:6601、mopidy-ytmusic
  backend実アカウント)を実際に起動し、(1)`tagtypes`が`Comment`を含めて応答することを
  実機で確認、(2)`mopidy_ytmusic/library.py`は全`Track()`生成箇所で`comment=""`を
  固定しているため実アカウントのデータでは`comment`が常に空文字列で自然再現不可
  (`mpdtracknofabricate-patch.py`/`ytartistfilterlist-patch.py`と同じ前例)、そのため
  同じ手法でパッチ適用後の実`mopidy_mpd.translator.track_to_mpd_format()`を直接importし
  `Track(uri=..., comment="hello world comment")`を渡したところ結果に
  `("Comment", "hello world comment")`が含まれることを確認、`comment=""`のTrackでは
  従来通り`Comment`行が省略される(Genre/Discと同じ空値省略の一貫性)ことも確認。
  **実データでの回帰確認**: 同dev mopidyで`status`/`find artist "a"`を実行し従来通り
  `OK`応答、mopidy.logに新規ERROR/Tracebackなしを確認。

- [x] `status`応答の`bitrate`(instantaneous bitrate in kbps)フィールドが
  mopidy-ytmusicでの実再生中も常に`0`を返してしまう不具合。TODO/既知の残課題を
  全項目消化済みのため自走エージェントがgeneral-purposeサブエージェントへ
  新規不具合調査を委任し発見。
  根拠: `mopidy_mpd/protocol/status.py`の`_status_bitrate()`は
  `current_tl_track.track.bitrate`(mopidy core標準のTrack.bitrateフィールド)を
  そのまま返すが、`mopidy_ytmusic/library.py`のTrack()生成箇所
  (`playlistToTracks`/`uploadArtistToTracks`/`uploadAlbumToTracks`/`albumToTracks`/
  `getTrack`/`parseSearch`の計6箇所)はいずれも`bitrate=0`を無条件でハードコード
  しており、None(未知)ではなく確定値0を返すため`_status_bitrate()`の
  `if ... is None: return 0`分岐を経ずそのまま0が返り続ける。一方
  `mopidy_ytmusic/playback.py`の`_get_track()`は既にyt-dlpの解決結果(info dict)
  からasr/audio_channelsを取り出しytaudioformat-patch.py経由でstatusの`audio`
  フィールドへ供給しているのに、同じinfo dictに含まれる`abr`(実測平均ビットレート、
  kbps単位)は一切参照・伝播しておらず、Format/audioフィールド向けに既に確立された
  仕組み(set_audio_format/get_song_audio_format キャッシュ)と全く同型の未実装
  ギャップと判明。BACKLOG既存の`bitrate`言及(mpdstatusduration-patch.py/
  mpdaudioformat-patch.py関連箇所)はいずれも`time`/`elapsed`/`duration`/`audio`
  フィールド実装時の文脈上の言及のみで、bitrateフィールド自体を対応不要と
  判定した記述は無いことを確認した上で着手。
  実害: rmpc(mierak/rmpc)のテーマでビットレート表示を配置しても、YouTube Music
  再生時は常に`0`のまま実測値が反映されない。
  verified: mpdbitrate-patch.py(mopidy_mpd側、translator.pyへ
  `_bitrate_cache`(uriキー付き揮発性キャッシュ、`_audio_format_cache`と同型)+
  `set_song_bitrate`/`get_song_bitrate`を追加、`_status_bitrate()`をキャッシュ優先
  参照へ変更)とytbitrate-patch.py(mopidy_ytmusic側、`_get_track()`末尾の既存
  asr/channels記録tryブロック直後に同型のtryブロックを追加し、yt-dlpの`abr`
  (無ければ`requested_formats[0]`へフォールバック)を`round()`した整数値で
  `set_song_bitrate(value, uri="ytmusic:track:%s" % bId)`を呼ぶ)の2ファイルに
  分割実装(mopidy_mpd/mopidy_ytmusicは別々のpackage buildのpostPatchで各々の
  ソースツリーにのみ書き込めるため、audioフォーマットの前例(mpdaudioformat-patch.py
  +ytaudioformat-patch.py)と同じくmopidy_mpd/mopidy_ytmusic双方に分けて実装する
  必要があった)。最初からuriキー付きキャッシュとして実装し、audioフォーマット側が
  踏んだ「単一値ストア→gapless先読みレース対策でuriキー付きキャッシュへ改修」という
  手戻り(mpdaudioformatpreload-patch.py)を回避。パッチ適用後の生成ソース3ファイル
  (translator.py/status.py/playback.py)を一時コピーに元のディレクトリ構造を再現して
  当て`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`の`mpdPatched`へ`mpdcommenttag-patch.py`の直後として
  `mpdbitrate-patch.py`を、`ytmusicPatched`へ`ytartistfilterlist-patch.py`の直後として
  `ytbitrate-patch.py`を登録しビルド成功。**実データ確認**: dev mopidy
  (127.0.0.1:6601、mopidy-ytmusic backend実アカウント)を実際に起動しMPDプロトコルで
  直接テスト — `search any "yoasobi"`で実在曲(オリオン - Orion,
  ytmusic:track:fCh0qfxElm8)を取得、`clear`→`add`→`play 0`後の`status`で
  `state: play`/`audio: 48000:16:2`(実データ、既存機能)とともに`bitrate: 133`
  (修正前は常に`0`だったところ、yt-dlpの実測abr≈128.93kbpsに由来する非ゼロ値)を
  確認。`pause 1`後も`bitrate: 133`を維持、`stop`後は`time`/`elapsed`/`bitrate`/
  `duration`/`audio`ともに行自体が消える(既存の「再生中のみ」仕様通り、無変更)。
  **回帰確認**: 同dev mopidyで`tagtypes`/`getvol`/`count any "yoasobi"`が全て従来通り
  正常応答、mopidy.logに新規ERROR/Traceback 0件を確認。

- [x] `mopidy_mpd/protocol/music_db.py`の`search()`が`find()`と異なりqueryに
  `artist`/`albumartist`/`composer`/`performer`/`album`が直接指定されていても
  `_artist_as_track()`/`_album_as_track()`のプレースホルダ(架空Track、Time常に0)を
  無条件に混入させてしまう非対称な不具合。TODO全項目消化済みのため自走エージェントが
  general-purposeサブエージェントへ新規不具合調査を委任し発見。
  根拠: `find()`(365-369行目)はGMPC由来の`find album "X" artist "Y"`(アルバムの
  曲一覧取得)用途のため、queryに`artist`/`albumartist`/`composer`/`performer`が
  あれば`_artist_as_track()`の、`album`があれば`_album_as_track()`のプレースホルダ
  変換をスキップし実トラックのみを返すガードを持つ。一方`search()`(824-826行目)は
  docstring自身が「findとパラメータの意味は同じ、大文字小文字を区別しない点のみ
  違う」と明記するにもかかわらずこのガードが実装されておらず、`artists`/`albums`
  リストを無条件に構築し結果へ混入させる。既存BACKLOGの`ytfindalbumtracks-patch.py`
  項目(9008行目付近)は`_artist_as_track`/`_album_as_track`に触れる唯一の既存
  エントリだが、これは`mopidy_ytmusic/library.py`側の`search()`(バックエンドの
  SearchResult構築、既存アルバムを無条件展開してしまう別バグ)を修正したもので、
  その回帰確認メモは「`search album`はプレースホルダが既存の設計のまま混入する」ことに
  触れているのみで、music_db.py側のfind/search非対称自体を不具合として認定・却下
  した記述ではない。今回初めてこの非対称自体を不具合として特定し着手。
  実害: rmpc(mierak/rmpc)の検索ペイン(src/ui/panes/search/mod.rs)は既定の
  fold_case(大文字小文字を区別しない)有効時にMPDの`search`コマンドを使う。
  Album/Artist列を対象にした検索では、findなら実トラックのみ返る場面でも
  無関係な全アルバム/全アーティスト分のプレースホルダ行が実データの前に大量に
  列挙され、実データがノイズに埋もれてしまう。
  verified: mpdsearchplaceholder-patch.py。`search()`内の
  `artists = [...]; albums = [...]; tracks = ...; result_tracks = artists + albums + tracks`
  を、`find()`と全く同じ`artist`/`albumartist`/`composer`/`performer`/`album`ガード
  条件による`result_tracks`組み立てへ置き換え。パッチ適用後の生成ソースは一時コピーに
  `mopidy_mpd/protocol/`ディレクトリ構造を再現して当ててから`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  `mpdPatched`へ`mpdbitrate-patch.py`の直後として登録しビルド成功。**実データ確認**:
  dev mopidy(127.0.0.1:6601、mopidy-ytmusic backend実アカウント)を実際に起動し
  MPDプロトコルで直接テスト — 実在のアルバム(YOASOBI「THE BOOK for,」、12曲)に対し
  `find album "THE BOOK for,"`(133行、実12曲のみ、修正前後で無変更)と
  `search album "the book for,"`(部分一致・大文字小文字無視)が、修正前は
  アルバムプレースホルダが実12曲の前に混入していたところ修正後は`find`と同じ133行
  (実12曲のみ、プレースホルダ`Title: Album: `行が0件)になることを確認、
  `count album "THE BOOK for,"`→`songs: 12`・`playtime: 2552`(無変更)、
  `searchadd album "THE BOOK for,"`→`OK`後`playlistinfo`が実12曲分(157行)を正しく
  含むことも確認。**回帰確認**: `search any "yoasobi"`(タグ指定無し、`any`のみ)は
  従来通りアルバムプレースホルダを含む(ガード対象外、無変更)、`search artist
  "yoasobi"`はArtistプレースホルダを含まない一方Albumプレースホルダは含む
  (artist指定はalbum側ガードに影響しない、find()と同じ仕様通りの挙動)、
  `find artist "YOASOBI"`(221行)・`tagtypes`(Comment含む38行)・`status`は
  全て従来通り正常応答、mopidy.logに新規ERROR/Traceback 0件を確認。

- [x] mpdtagnames-patch.pyが`_PHANTOM_TAG_FIELDS`機構で実MPD(Names.cxx)準拠の
  未登録タグ18種を追加したが、それ以前から存在していた"base"19種のタグのうち
  `ArtistSort`/`AlbumArtistSort`/`Name`/`MUSICBRAINZ_ALBUMARTISTID`/`X-AlbumUri`
  の5種が元々`_LIST_MAPPING`/`_LIST_NAME_MAPPING`/`_PHANTOM_TAG_FIELDS`に
  未登録のまま放置され、同種の不具合(`tagtypes`応答には含まれ対応を広告するのに
  `find`/`list`/フィルタ式では即`ACK incorrect arguments`/`ACK Unknown tag type`/
  `ACK Unknown filter type`になる非対称)が残っていた。TODO/既知の残課題を
  全項目消化済みのため自走エージェントがgeneral-purposeサブエージェントへ
  新規不具合調査を委任し、mpdtagnames-patch.py適用後の残存ギャップとして発見。
  根拠: `tagtype_list.py`のTAGTYPE_LISTにはこの5タグとも元々含まれていた
  (mpdtagnames-patch.pyが追加した18種とは別、base実装時点から存在)。一方
  `music_db.py`の`_LIST_MAPPING`(find/search/list/countが参照する`_SEARCH_MAPPING`/
  `_SORT_MAPPING`の導出元)にはこの5種のキーが無く、実機(127.0.0.1:6601、
  mopidy-ytmusic backend)で`find artistsort "Test"`等がACKになることを確認済み。
  mopidyのTrack/Album/ArtistモデルにはArtistSort/AlbumArtistSort用の検索可能な
  フィールドが無く(Artist.sortnameはあるがmopidy core.library.search()の固定
  フィールド集合SEARCH_FIELDS/DISTINCT_FIELDSには含まれずbackendへ渡すと
  ValidationErrorで無応答切断になる、mpdtagnames-patch.pyと同じ事情)、
  MUSICBRAINZ_ALBUMARTISTID/Nameも同様、X-AlbumUriはmopidy独自導入タグで
  そもそも対応フィールド概念が無い。よってmpdtagnames-patch.pyと全く同じ
  phantomタグ機構(`_PHANTOM_TAG_FIELDS`)への追加登録のみで解消可能と判断
  (書き込みサイトの分岐コードは18種追加時に既に汎用化済みのため変更不要)。
  実害: rmpc(mierak/rmpc、`filter.rs`の`Tag::Custom(String)`)はAdvanced Searchで
  任意のタグ名を自由入力できる。`tagtypes`が5タグとも対応を広告するのに実際には
  検索に使えないという矛盾がmpdtagnames-patch.py適用後もなお5タグ分残っていた。
  verified: mpdtagnames2-patch.py。`_LIST_MAPPING`/`_LIST_NAME_MAPPING`/
  `_PHANTOM_TAG_FIELDS`の3集合それぞれの末尾(既存18種の直後)へ5タグを恒等
  マッピング(小文字キー→同名)で追加。パッチ適用後の生成ソースは一時コピーに
  `mopidy_mpd/protocol/`ディレクトリ構造を再現して当て`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  `mpdPatched`へ`mpdsearchplaceholder-patch.py`の直後(リスト末尾)として登録し
  ビルド成功。**実データ確認**: dev mopidy(127.0.0.1:6601、mopidy-ytmusic
  backend実アカウント)を実際に起動しMPDプロトコルで直接テスト —
  (1)修正前は`find artistsort "Test"`/`find AlbumArtistSort "Test"`/
  `find Name "Test"`/`find MUSICBRAINZ_ALBUMARTISTID "x"`/`find "X-AlbumUri"
  "Test"`が全て`ACK [2@0] {find} incorrect arguments`、`list ArtistSort`が
  `ACK [2@0] {list} Unknown tag type: ArtistSort`、`find "(ArtistSort ==
  \"Test\")"`が`ACK [2@0] {find} Unknown filter type: ArtistSort`だったことを
  実機で確認済み、
  (2)修正後は同じ5タグへの`find`(TYPE-VALUE形式・フィルタ式形式の両方)と
  `list`が全て`OK`(0件)で応答することを確認、
  (3)`tagtypes`応答には修正前後で変わらず5タグとも含まれることを確認
  (広告と実際の扱いの矛盾が解消)。
  **回帰確認**: `list Artist`/`list Album`/`list Mood`/`find Mood "Chill"`が
  従来通り`OK`、`find Title "a"`が実データ(GOT7「A」等)を正しく返す、`stats`が
  正常応答することを確認、mopidy.logに新規ERROR/Traceback無しも確認。
- [x] `find`/`search`/`count`/`searchcount`/`findadd`/`searchadd`/`searchaddpl`/
  `searchplaylist`/`playlistfind`/`playlistsearch`が共有するフィルタ式パーサ
  `_query_from_mpd_filter_expression()`/旧式パーサ`_query_from_mpd_search_parameters()`
  (music_db.py)が、実MPD(mpd.readthedocs.io protocol、Filters節に
  "(modified-since 'VALUE'): compares the file's time stamp with the given
  value (ISO 8601 or UNIX time stamp)."/"(added-since 'VALUE'): compares time
  stamp when the file was added with the given value"と明記)の
  `modified-since`/`added-since`疑似タグを一切認識しない不具合。TODO/既知の
  残課題を全項目消化済みのため自走エージェントが(general-purposeサブエージェント
  への調査委任を経て)新規発見した項目。実MPD本体(MusicPlayerDaemon/MPD、
  gh apiで実際にソース取得し確認)の`src/song/Filter.cxx`の`ParseExpression()`/
  `SongFilter::Parse()`は`modified-since`/`added-since`を`base`
  (mpdbasefilter-patch.pyで対応済み)と全く同じ枠組み — `LOCATE_TAG_MODIFIED_SINCE`/
  `LOCATE_TAG_ADDED_SINCE`という通常のタグ種別とは別の特殊擬似タグとして認識し、
  演算子を取らない単一の引用値のみを受け取る(フィルタ式`(modified-since "TIME")`・
  legacy構文`find modified-since "TIME"`の両方で同様)。対応する
  `ModifiedSinceSongFilter::Match()`/`AddedSinceSongFilter::Match()`は
  `song.mtime >= value`という以上判定(>=)で、値はISO 8601かUNIXタイムスタンプの
  2形式を受け付ける(`ParseTimeStamp()`)。現状の`_query_from_mpd_filter_expression()`
  は`base`以外の単一トークン(`len(parts) == 1`)を一切処理しないため、
  `(modified-since "2020-01-01")`は`parts == ["modified-since"]`となりどの
  ブロックにも一致せず完全に素通りする。実害(127.0.0.1:6601、mopidy-ytmusic
  実アカウントで確認): `search "((artist contains \"Buzz\") AND (modified-since
  \"2099-01-01\"))"` → 該当節が黙って無視され、`modified-since`無しの
  `search "(artist contains \"Buzz\")"`と全く同じ243件が返る(静かな誤り、
  未来日付=本来0件になるべき条件が一切効いていない)。単独指定
  (`find "(modified-since \"2020-01-01\")"`)は`query`が空のまま
  `require_positive`チェックに引っかかり`ACK incorrect arguments`(実MPDでは
  正当な問い合わせとして受理されるべき)。旧式引数列パーサも`mapping.get()`が
  常に`None`になり同じく`ACK incorrect arguments`で拒否される。translator.pyは
  既に`Added:`(get_or_stamp_library_added、MPDセッション内でこのuriを最初に
  返した近似時刻)と`Last-Modified:`(track.last_modified)の両方をレスポンスへ
  出力済みで、両疑似タグが必要とするデータは既に配線済み — フィルタ式パーサ側が
  認識しないだけだった。BACKLOG.mdを`grep -n
  "modified-since\|added-since\|AddedSince\|ModifiedSince"`で確認したが
  既存パッチとの重複はない。
  verified: mpdsincefilter-patch.py。既存のnegatives/positives後段フィルタ
  機構(mpdnegfilter-patch.py/mpdfilterkind-patch.py/mpdbasefilter-patch.py)に
  `kind="modified_since"/"added_since"`を追加する形で配線(base_dirと同じ設計、
  backendのquery本体には一切触れずローカル後段フィルタとしてのみ効かせる)。
  `_mpd_parse_since_timestamp()`でISO 8601/UNIXタイムスタンプの両形式をパースし
  不正な形式は実MPD同様その場でACK(MpdArgError)にする。music_db.py
  (find/search/count/findadd/searchadd/searchaddpl)だけでなく、
  `_query_from_mpd_filter_expression()`を共有する`current_playlist.py`の
  `_pf_matches()`(playlistfind/playlistsearch/searchplaylistが使う独自実装、
  mpdbasefilter-patch.pyがbase_dir用に同種の分岐を追加済み)にも同じ
  `kind="modified_since"/"added_since"`分岐を追加(追加しないとどのelifにも
  一致せず無条件で「合格」扱いになり静かに無視される別の欠落があったため)。
  パッチ適用後の生成ソース(music_db.py/current_playlist.pyの2ファイル)は
  一時コピーに`mopidy_mpd/`ディレクトリ構造を再現して当て`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。オフラインでも
  `$ENV/bin/python3`(env自身のインタプリタ)で`Track(last_modified=<既知の
  epoch ms>)`の合成Trackオブジェクトを使い、`_query_from_mpd_filter_expression()`
  →`_mpd_track_matches_positives()`/`_mpd_track_excluded()`の一連を直接呼び出し、
  未来日時=不一致・過去日時=一致・UNIXタイムスタンプ形式・AND併用・否定
  (`!(modified-since ...)`)・legacy構文(`find modified-since "TIME"`)・不正な
  TIME形式でMpdArgError(クラッシュではなくACK)になることを個別に確認。
  `nix/lib/mopidy-env.nix`の`mpdPatched`へ`mpdtagnames2-patch.py`の直後
  (リスト末尾)として登録しビルド成功。**実データ確認**: dev mopidy
  (127.0.0.1:6601、mopidy-ytmusic backend実アカウント)を実際に起動し
  MPDプロトコルで直接テスト — `added-since`は`translator.get_or_stamp_library_added()`
  が実際に`now`を記録するため実データで完全にエンドツーエンド確認できた:
  `search "((artist contains \"a\") AND (added-since \"2099-01-01\"))"` →
  0件(修正前は素通りしていた箇所)、同じクエリを`added-since "1970-01-01"`に
  すると`added-since`無しのbaseline(270件)と完全一致、`find
  "(added-since \"2099-01-01\")"`単独指定も`ACK incorrect arguments`ではなく
  `OK`(0件)に是正、`find "(modified-since \"not-a-date\")"`は
  `ACK [2@0] {find} Invalid timestamp: not-a-date`(クラッシュや無応答切断では
  なく正しくACK)、直後の`ping`が`OK`でセッション生存を確認(malformed timestamp
  でセッションが切断されないことを確認)、legacy構文`find artist "a"
  modified-since "1970-01-01"`/`modified-since "2099-01-01"`でも同じ挙動
  (該当時0件/絞り込み)を確認。current_playlist.py側は`findadd "(artist ==
  \"A-Rumenoy\")"`でキューへ実トラックを追加した上で`playlistfind
  "(added-since \"2099-01-01\")"` → 0件、`"(added-since \"1970-01-01\")"` →
  キュー全件と一致、`playlistsearch`でも同様、`save`でストアドプレイリスト化し
  `searchplaylist NAME "(added-since \"2099-01-01\")"` → 0件、
  `"(added-since \"1970-01-01\")"` → 保存した全件と一致、を実機で確認した。
  `modified-since`はmopidy_ytmusic.library.py/playlist.pyが返す全Trackが
  `last_modified=None`固定(YouTube Musicには実MPDのようなファイルmtime概念が
  存在しないため)なため実データでは常に0件になる — これは`base`疑似タグの
  非階層的backend(ytmusic)向け制約(mpdbasefilter-patch.py記載)と同種の、
  backend側にデータが無いことによる正当な制約であり、フィルタロジック自体は
  上記の合成Trackオブジェクトによるオフライン確認で正しいことを確認済み。
  **回帰確認**: mopidy.logに新規ERROR/Traceback無し(save時の`YTMusic
  playlist creation failed`/`HTTP 401 Unauthorized`は既知のdev環境ytmusic
  認証切れ、mpdbasefilter-patch.py検証時と同じ既知事象でsave自体はm3u
  バックエンドで成功しており本件と無関係)を確認した。

- [x] `mpdcmdlistidle-patch.py`がcommand_list内のidle/noidleに対し
  「実MPD(src/client/Process.cxx)がACK_ERROR_NOT_LISTで拒否するのに倣い」と
  ACKを返す実装にしていたが、この根拠自体が実MPD本体ソースと食い違っていた
  不具合。TODO全項目消化済みのため自走エージェントが実MPD本体ソース
  (MusicPlayerDaemon/MPD、GitHubから直接取得)を確認して発見。
  実MPDの`src/client/Process.cxx` `Client::ProcessLine()`:
  ```
  if (cmd_list.IsActive() && IsAsyncCommmand(line)) {
      FmtWarning(...);
      return CommandResult::CLOSE;
  }
  ```
  (`IsAsyncCommmand()`は"idle"/"noidle"の完全一致のみ判定)であり、ACKは
  一切送らない。`src/client/Read.cxx` `OnSocketInput()`の
  `case CommandResult::CLOSE: Close(); return InputResult::CLOSED;`により、
  この行を読み取った時点(`command_list_end`を待たず、コマンドリストへの
  蓄積前)で無応答のままTCP接続を即座に切断する。mpd.readthedocs.ioの
  command lists節も"Only synchronous commands can be used in command
  lists... idle and noidle are not allowed."と書くのみでACK応答を返す
  仕様だとはどこにも書いていない。修正前のmopidy_mpdは、idle/noidleを
  一旦`self.command_list`へ蓄積し`command_list_end`受信時のリプレイ
  ループ内で初めてACKを返し接続は維持したままにする——実MPDより緩い
  (親切な)独自挙動になっており、切断タイミングも「idle行を受信した瞬間」
  ではなく「`command_list_end`を受信した後」まで遅延していた。
  `mpdcmdlistidleclose-patch.py`で`dispatcher.py`の
  `_command_list_filter()`を修正し、list受信中に届いた行がidle/noidle
  ならば`self.command_list`へ積む前に`context.session.close()`で即座に
  切断するよう変更(実MPDの「行を読んだ瞬間、リストへの蓄積前に切断」と
  同じタイミング)。command_list_index/context.subscriptions等の状態には
  一切触れずハンドラも呼ばないため、`mpdcmdlistidle-patch.py`が修正した
  汚染経路とも無関係。`mpdcmdlistidle-patch.py`が`command_list_end()`の
  リプレイループへ追加したidle/noidle分岐は、本パッチ適用後はidle/noidle
  が`self.command_list`に二度と入らなくなるため到達不能になるが、
  albumart/readpicture分岐(`mpdalbumartcmdlist-patch.py`)は引き続き
  有効なのでそのループ自体は残した。
  verified: `~/ai/mopidy-dev/build-run.sh`でdev mopidy起動(MPD=6601)し、
  素のsocketで実MPDプロトコルを実際に叩いて確認した。
  (1) `command_list_begin`/`idle`送信直後、`command_list_end`を送る前の
  時点で既に`recv()`がEOF(`b''`)を返す=接続が即座に切断されていることを
  確認(command_list_endを待たない実MPDと同じタイミング)。
  (2) `noidle`でも同様に即座に切断されることを確認。
  (3) タブ区切り`"idle\tplayer"`をlist内で送っても同様に即座に切断される
  ことを確認(`re.split(r"\s+", ...)`によりmpdcmdlisttabsplit-patch.pyと
  同じトークナイザ規則で正しく検知)。
  (4) 回帰確認: list外での`idle`/`noidle`は従来通り(即応答せず待機し、
  `noidle`で`OK`)動作することを確認。通常のcommand_list
  (`command_list_begin`/`ping`/`ping`/`command_list_end` →`OK`)、
  `command_list_ok_begin`(→`list_OK`/`OK`)は共に正常動作し接続も維持
  されることを確認。list内`albumart`は従来通りACK
  (`{albumart} not allowed in a command list`)を返し接続も維持される
  (mpdalbumartcmdlist-patch.pyの挙動に変化なし)ことを確認。
  mopidy.logに新規ERROR/Traceback無しを確認した。

- [x] find/search/count/playlistfind/playlistsearchが共有するフィルタ式
  パーサ(music_db.py/current_playlist.py)が実MPDの`prio`疑似タグ
  (`(prio >= "N")`、キュー内の曲を優先度でフィルタする)を一切認識せず
  `ACK Unknown filter type: prio`になる不具合。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見した項目。実MPD本体(MusicPlayerDaemon/MPD、gh apiで実際に
  ソース取得し確認)の`src/song/Filter.cxx`の`ParseExpression()`は"prio"を
  `LOCATE_TAG_PRIORITY`というbase/modified-sinceと同じ枠組みの特殊擬似
  タグとして認識するが、base/modified-sinceと違い演算子を伴う
  (`s[0]=='>' && s[1]=='='`のみ許容、それ以外は`'>=' expected`で例外、
  ソース中のTODOコメントで他演算子は実MPD自身も未対応と明記)。値は
  0-255の整数(`value > 0xff`ならエラー)。`src/song/PrioritySongFilter.cxx`
  の`Match()`は`song.priority >= value`。現状の
  `_query_from_mpd_filter_expression()`は`len(parts)==1`の特殊タグ
  (base/modified-since/added-since)しか処理せず、`(prio >= "N")`は
  `parts == ["prio", ">="]`(len==2)のため一般の`len(parts)>=2`分岐に落ち、
  `mapping.get("prio")`が`None`のためACKになる。また実MPD本体では、
  括弧無しの旧式`TAG VALUE`列挙構文(`SongFilter::Parse(tag_string,
  value, ...)`のswitch)には`LOCATE_TAG_PRIORITY`のcaseが無く`default:`
  (通常タグ扱い、未定義に近い挙動)に落ちる — base/modified-since/
  added-sinceが明示的にcaseを持つのとは非対称なため、本パッチも旧式
  パーサ側には一切手を入れず、括弧付きフィルタ式パーサ側にのみ配線した。
  `prio`は実MPDでもキュー限定の概念で、DB由来のLightSong(find/search等の
  音楽データベース検索対象)は`Queue::GetLight()`を経由しないため
  `song.priority`は常にデフォルト値0のまま(実際に優先度を設定できるのは
  `prio`/`prioid`コマンドが操作するキュー内エントリのみ)であり、本パッチも
  この非対称性を忠実に再現する: current_playlist.py側(playlistfind/
  playlistsearch、実際のキューを検索)はtranslator.get_priority(tlid)の
  実データで判定し、music_db.py側(find/search/count等、音楽データベースを
  検索)は常に「優先度0」として判定する(`(prio >= "0")`は常に真、
  `(prio >= "1")`以上は常に偽になる、実MPDのLightSong既定値0と同じ)。
  BACKLOG.mdを`grep -n -i "prio.*filter\|filter.*prio\|
  PrioritySongFilter\|LOCATE_TAG_PRIORITY\|prio >="`で確認したが既出の
  対応/blocked扱いは無い(既存の"prio"/"prioid"関連エントリはコマンド
  自体の実装・TOCTOUレース修正のみを扱っており、フィルタ式の疑似タグ
  としてのprioは未着手だった)。
  verified: mpdpriofilter-patch.py。既存のnegatives/positives後段フィルタ
  機構(mpdnegfilter-patch.py/mpdfilterkind-patch.py/mpdbasefilter-patch.py/
  mpdsincefilter-patch.py)にkind="priority"を追加する形で配線
  (`_mpd_parse_prio_filter_value()`で演算子`>=`と0-255範囲をパース、
  不正な演算子/範囲は実MPD同様その場でACK)。current_playlist.pyの
  `_pf_matches()`にはtlid由来の実優先度を渡す`priority`引数を新設し
  `_pf_search()`から`translator.get_priority(tl_track.tlid)`を渡す
  (stored_playlists.pyのsearchplaylist()はtlidを持たないm3u曲を検索する
  ため既定値0のまま呼ばれ続け、実MPD同様プレイリスト内の曲はキュー優先度
  を持たない扱いになる)。パッチ適用後の生成ソース(music_db.py/
  current_playlist.pyの2ファイル)は一時コピーに`mopidy_mpd/`ディレクトリ
  構造を再現して当てast.parseで構文確認、2回適用しても冪等(スキップ)
  であることも確認。**実データ確認**: `~/ai/mopidy-dev/build-run.sh`で
  dev mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を起動し実際の
  MPDプロトコルで直接テスト —
  (1) `clear`→`add`(2曲、Id=1,2)→`prioid "100" "1"`→`playlistid 1`で
  実際に`Prio: 100`が返ることを確認(既存prioid実装の実データ)。
  (2) `playlistfind "(prio >= \"50\")"` → Id=1(prio=100)のみが該当曲として
  返ることを確認(修正前は`ACK Unknown filter type: prio`)。
  (3) `playlistfind "(prio >= \"200\")"` → 0件(100<200)を確認。
  (4) `playlistsearch "(prio >= \"1\")"` → Id=1のみ該当を確認。
  (5) 否定`playlistfind "(!(prio >= \"50\"))"` → Id=1以外の全曲(22曲)が
  該当することを確認(否定条件が正しく機能)。
  (6) 不正演算子`playlistfind "(prio > \"50\")"` →
  `ACK [2@0] {playlistfind} '>=' expected`(実MPD同様>=以外は拒否)。
  (7) 範囲外`playlistfind "(prio >= \"999\")"` →
  `ACK [2@0] {playlistfind} Invalid priority value`。
  (8) `find "(prio >= \"0\")"`単独指定は0件(空クエリでbackend
  `library.search(query={})`自体が0件を返すためで、
  mpdsincefilter-patch.py検証時と同じ既知の挙動、prioロジック自体の
  不具合ではない)。組み合わせクエリ
  `find "((artist contains \"a\") AND (prio >= \"0\"))"` →
  baseline(artist条件のみ)と同じ113件(DB側は常にpriority=0なので
  `>=0`は常に真、絞り込みが効かないのが正しい)、
  `find "((artist contains \"a\") AND (prio >= \"1\"))"` → 0件
  (DB側priority=0は`>=1`を満たさないため全除外、正しい)を確認。
  **回帰確認**: `find "(artist contains \"a\")"`(113件、変化なし)、
  `find "(bogus == \"x\")"`(`ACK Unknown filter type: bogus`、既存の
  未知タグ拒否は変化なし)を確認。mopidy.logに新規ERROR/Traceback無しを
  確認した。

- [x] `list file [FILTER]`/`list filename [FILTER]`が実MPD(gh apiで
  src/command/DatabaseCommands.cxxのhandle_list/handle_list_fileを確認)では
  他タグ(artist/album等)と全く別実装(フィルタに一致した曲の`file: <uri>`行を
  そのまま列挙するPrintSongUris、group/window非対応)に分岐するのに対し、
  mopidy_mpd(music_db.pyのlist_())は`_LIST_MAPPING`の"file"/"filename"→"uri"
  マッピングを他タグと全く同じ`get_distinct("uri", query)`経路
  (`_mpd_list_grouped`)に流し込んでしまう不具合。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見した項目。実MPD本体`handle_list`は`tag_name`が"file"/"filename"の
  場合、window/groupの解析より前に`handle_list_file`へ即分岐する
  (`filter->Parse(args, false)`で残り引数を`find`同様のフィルタとして解釈し
  `PrintSongUris`で一致曲のuriのみ出力、distinct集合化・sort・group・window
  はいずれも非対応)独自実装。一方mopidy_ytmusic.library.get_distinct()は
  fieldが"artist"/"albumartist"/"album"/"date"の4分岐しかなくfield=="uri"は
  どれにも一致しないため、`list file`/`list filename`は実データが存在しても
  ACKにすらならず常に空応答(OKのみ)になっていた(ACKより気付きにくい
  「静かに0件」の不具合)。BACKLOG.mdを
  `grep -n -i "list file\|list filename\|PrintSongUris\|handle_list_file"`
  で確認したが既出の対応/blocked扱いは無い。
  verified: mpdlistfile-patch.py。music_db.pyのlist_()でfield解決直後、
  field=="uri"(=引数がfile/filename)の場合はgroup/window解析より前に分岐し、
  find()と同じフィルタパース(`_query_from_mpd_search_parameters`+
  negatives/positives)で一致した曲を集め`("file", uri)`のみ出力する専用
  ヘルパ`_mpd_list_file()`へ委譲するよう修正。生成後のmusic_db.pyは一時
  コピーに`mopidy_mpd/`ディレクトリ構造を再現して当てast.parseで構文確認、
  2回適用しても冪等(スキップ)であることも確認。**実データ確認**:
  `~/ai/mopidy-dev/build-run.sh`でdev mopidy(127.0.0.1:6601、mopidy-ytmusic
  実アカウント)を起動し実際のMPDプロトコルで直接テスト —
  (1) `find "(any contains \"yoasobi\")"`でアルバムプレースホルダ1件+実曲
  2件(ytmusic:track:fCh0qfxElm8/by4SYYWlhEs)がヒットすることを確認した上で、
  (2) `list file "(any contains \"yoasobi\")"` →
  `file: ytmusic:track:fCh0qfxElm8`/`file: ytmusic:track:by4SYYWlhEs`の
  2行のみ(アルバムプレースホルダは含まれない、実MPDのPrintSongUrisが実曲
  のみを対象とする挙動と一致)が返ることを確認(修正前は`OK`のみで0件)。
  (3) `list filename "(any contains \"yoasobi\")"` → filenameでも同じ
  結果を確認(file/filenameどちらも同じ"uri"フィールドへマップされる仕様
  通り)。
  (4) `list file "(artist contains \"YOASOBI\")"` → 別タグでの絞り込みも
  実際に5件返ることを確認(uri以外のタグでのフィルタも機能)。
  (5) `list file "(any contains \"zzznosuchtrackzzz\")"` → 該当曲無しで
  `OK`のみ(0件、正しい空応答)を確認。
  **回帰確認**: `list album group album`(`ACK Conflicting group`、
  mpdlistgroupconflict-patch.pyのガードは無変化)、`list bogus "x"`
  (`ACK Unknown tag type: bogus`、既存の未知タグ拒否は変化なし)、
  `search "(any contains \"yoasobi\")"`/`count "(any contains \"yoasobi\")"`
  (件数・応答とも変化なし、find/list以外の兄弟コマンドは無影響)を確認。
  mopidy.logに新規ERROR/Traceback無しを確認した。

- [x] `list TYPE ... group file`/`... group filename`(count/searchcountでも
  同様に`group file`/`group filename`)が、実MPDならACK "Unknown tag type"
  になるべきところ、mopidy_mpdの`_mpd_extract_group_params()`(music_db.py)
  がgroup TAGを他タグと同じ`_LIST_MAPPING.get(tag.lower())`で解決するため
  素通りしてしまい常に0件のOKを返す不具合。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見した項目。mpdlistfile-patch.py(直前のコミット)が`list`のTYPE
  引数自体がfile/filenameの場合の経路を修正したが、その副作用として
  `_LIST_MAPPING["file"/"filename"] = "uri"`が登録済みになり、TYPEとは
  独立した`group`修飾子側の解決でも同じマッピングを素通りしてしまう対応漏れ
  が残っていた。実MPD本体`DatabaseCommands.cxx`の`handle_list()`の`group`
  解析ループは`tag_name_parse_i(s)`でgroupタグ名を解決しており、これは
  `src/tag/Names.cxx`の`tag_item_names_init`(Artist/Album/Title/…/
  MUSICBRAINZ_*等)に基づく——この配列に"File"/"Filename"は存在しない。
  `list`のTYPE引数側のfile/filename特別扱い(`handle_list_file`への分岐)は
  TYPE解決専用でありgroup側の解決には一切適用されない。`handle_count_
  internal()`も同じ`tag_name_parse_i`を使うため`count FILTER group file`
  も同様にACKになる。BACKLOG.mdを`grep -n -i "group file\|group filename\|
  _mpd_extract_group_params"`で確認したが、`_mpd_extract_group_params`
  自体への既存言及(重複group検出/count・searchcountとの共有)はあるものの
  "group file"/"group filename"という組み合わせを不具合として扱った記述は
  無かった。
  verified: mpdlistgroupfile-patch.py。`_mpd_extract_group_params()`で
  group TAGを`_LIST_MAPPING`で解決する前に`tag.lower()`が"file"/"filename"
  なら`MpdArgError("Unknown tag type: %s")`を送出するよう修正
  (list_()/count()/searchcount()が全てこの関数を共有するため3コマンドまとめて
  修正される)。生成後のmusic_db.pyは一時コピーに`mopidy_mpd/`ディレクトリ
  構造を再現して当てast.parseで構文確認、2回適用しても冪等(スキップ)である
  ことも確認。**実データ確認**: `~/ai/mopidy-dev/build-run.sh`でdev
  mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を起動し実際のMPD
  プロトコルで直接テスト——`list album group file`/`list album group
  filename`/`list artist "(any contains \"a\")" group file`/`count "(any
  contains \"a\")" group file`/`searchcount "(any contains \"a\")" group
  filename`のいずれも`ACK [2@0] {CMD} Unknown tag type: file`
  (またはfilename)を返すことを確認(修正前はいずれも`OK`のみ、0件応答)。
  **回帰確認**: `list album group bogus`(既存の未知タグ拒否、変化なし)、
  `list album group artist`(正常なgroup、`OK`で継続動作)、`list album
  group artist group album`(`ACK Conflicting group`、mpdlistgroupconflict-
  patch.pyのガードは無変化)、`list file "(any contains \"a\")"`(TYPE自体が
  file、mpdlistfile-patch.pyの専用経路は無変化)、`tagtypes`を確認。
  mopidy.logに新規ERROR/Traceback無し、mopidy起動もクリーンであることを
  確認した。
- [x] フィルタ式`(Date == "YYYY")`(単独条件)がmopidy_ytmusic backendでは
  `_mpd_track_matches_positives()`(music_db.py)のローカル再検証により
  常に0件になる不具合。TODO/既知の軽微な残課題を全項目消化済みのため
  自走エージェントが調査サブエージェントに委任し、music_db.py/library.py
  を突き合わせて新規発見・追加した項目(mpdgenrepositivetrust-patch.py/
  mpdtrackpositivetrust-patch.pyと同根: mopidy_ytmusicのTrack.dateは
  albumToTracks()/uploadAlbumToTracks()(アルバムを実際にブラウズ/lookup
  した経路)由来のTrackにのみ実データが入り、search()経由(parseSearch())
  やplaylistToTracks()/uploadArtistToTracks()由来のTrackは常に
  date="0000"固定。ytsearchdate-patch.pyがsearch()に"date"単独分岐
  (any/genreと同じベストエフォートのテキスト検索)を追加済みだが、
  music_db.py側のローカル再検証がdateを通常フィールドとして扱うため
  backendが実際に見つけた候補を無条件却下していた)。
  verified: mpddatepositivetrust-patch.py。genre/track_noと全く同じ設計
  ("dateが唯一の肯定条件のときだけ"ローカル再検証をスキップ、他フィールド
  併用時はbackendがdateを見ていないため対象外のまま)。mpdbasefilter-
  patch.py/mpdsincefilter-patch.pyが`_mpd_track_matches_positives()`の
  関数本体を丸ごと文字列一致で書き換えるため、両パッチより後段
  (nix/lib/mopidy-env.nixのmpdPatchedリスト内)に登録。一時コピーに
  `mopidy_mpd/`ディレクトリ構造を再現して当てast.parseで構文確認、2回
  適用しても冪等(スキップ)であることも確認。**実データ確認**:
  `~/ai/mopidy-dev/build-run.sh`でdev mopidy(127.0.0.1:6601、
  mopidy-ytmusic実アカウント)を起動し実際のMPDプロトコルで直接テスト——
  `find date "YOASOBI"`(修正前は`OK`のみ0件)→修正後は実トラック2件
  (「アイドル」「オリオン - Orion」)+アルバム擬似行1件を返すことを確認
  (backendのベストエフォートテキスト検索結果をローカル再検証で却下しなく
  なった)。複合条件`find title "怪物" date "2021"`/`find artist "YOASOBI"
  date "2021"`は、backendが実際にはdate条件を見ていない経路(elif連鎖で
  title/artist分岐が優先)のため設計上引き続き対象外(genre/track_noの
  複合条件と同じ既知の制約、修正しない)。**回帰確認**:
  `find "(Genre == \"pop\")"`(genreの既存trust、正常動作継続)、
  `find "(Track == \"1\")"`(track_noの既存trust、変化なし)、
  `find album "THE BOOK 2" date "2021"`(albumブランチ経由の実データ検索、
  8曲正しくヒット、回帰なし)、`search any "YOASOBI"`/`count any
  "YOASOBI"`/`list album`/`status`/`tagtypes`を確認。mopidy.logに新規
  ERROR/Traceback無し、mopidy起動もクリーンであることを確認した。

- [x] フィルタ式`(Composer == "X")`/`(Performer == "X")`/`(Comment == "X")`/
  `(Disc == "N")`/`(MUSICBRAINZ_TRACKID == "X")`/`(MUSICBRAINZ_ALBUMID ==
  "X")`/`(MUSICBRAINZ_ARTISTID == "X")`(単独条件)がmopidy_ytmusic backend
  では常に0件になる不具合を修正 (mpdmetapositivetrust-patch.py)。TODO全
  項目消化済みのため自走エージェントがgeneral-purposeサブエージェントへの
  調査委任を経て新規発見。mpdgenrepositivetrust-patch.py/
  mpdtrackpositivetrust-patch.py/mpddatepositivetrust-patch.pyと同根:
  mopidy_ytmusicのTrackはcomposers/performers/comment/disc_no/
  musicbrainz_idを(search()/album/playlist/artist経由いずれの構築箇所
  でも)常に空固定で返すため、ytsearchmetatag-patch.pyが追加した
  `_META_SEARCH_FIELDS`単独分岐(any/genreと同じベストエフォートのテキスト
  検索)がbackend側で実トラックを見つけても、`_mpd_track_matches_positives()`
  (music_db.py)がこれらを通常フィールドとして扱い
  `_mpd_negative_field_values()`(常に空リスト)と比較して無条件却下する。
  旧式構文`find composer "X"`はpositivesを生成せずbackend結果をそのまま
  返すため正常動作しており、フィルタ式構文だけが非対称に0件になっていた。
  genre/track_no/dateと同じ設計(該当フィールドが唯一の肯定条件のときのみ
  backendのベストエフォート結果を信頼、他フィールド併用時は対象外のまま)
  で解消。verified: dev mopidy (127.0.0.1:6601, ytmusic実アカウント)に
  対しTCPソケットで直接コマンド送信し確認。修正前:
  `find composer "yoasobi"`→実トラック2件(夜に駆ける/オリオン)+アルバム
  擬似行1件がヒットするのに対し、`find "(Composer == \"yoasobi\")"`/
  `find "(Performer == \"yoasobi\")"`/`search "(Composer == \"yoasobi\")"`
  →いずれも`OK`のみ(0件)、`count "(Composer == \"yoasobi\")"`→
  `songs: 0`という矛盾を確認。修正後: 上記フィルタ式構文が全て旧式構文と
  同じ実トラック2件+アルバム擬似行1件(`count`は`songs: 2`)を返すことを
  確認。**回帰確認**: 複合条件`find "((Composer == \"yoasobi\") AND
  (Title == \"nonexistentxyz\"))"`(該当フィールドが唯一の肯定条件でない
  ため対象外のまま設計通り0件を維持)、`find "(Composer ==
  \"nonexistentxyzabc\")"`(実際に一致がない場合は引き続き正しく0件)を
  確認。mopidy.logに新規ERROR/Traceback無し、mopidy起動もクリーンで
  あることを確認した。

- [x] `tagtypes available`/`tagtypes reset {NAME...}` (実MPD 0.24で追加された
  兄弟サブコマンド) を一切認識せず常に`ACK Unknown sub command`になる不具合を
  修正 (mpdtagtypesavailablereset-patch.py)。TODO全項目消化済みのため自走
  エージェントがgeneral-purposeサブエージェントへの調査委任を経て新規発見。
  実MPD本体(gh rawでsrc/command/ClientCommands.cxx handle_tagtypes()を確認、
  NEWSにも「ver 0.24: new "available" and "reset" subcommands for tagtypes」
  と明記)はall/clear/enable/disable/available/resetの6分岐を持つが、
  mopidy_mpdのconnection.py tagtypes()は前者4つしか実装していなかった。
  `available`はtag_print_types_available(r)(サーバー設定のglobal_tag_mask、
  クライアント個別のenable/disable状態とは無関係)、`reset {NAME...}`は
  `client.tag_mask = None(); tag_mask |= ParseTagMask(request)`(clear+enable
  のアトミック版、ParseTagMaskはrequest空なら"Not enough arguments"送出)。
  mopidy_mpdにmetadata_to_use相当の概念は無いため`available`は
  tagtype_list.TAGTYPE_LIST全件を無条件で返せばよく、既存の兄弟コマンド
  protocol/stringnormalization(mpdtagtypecase-patch.py導入)のavailable実装
  と同型。`reset`は既存の`_resolve_tagtypes()`ヘルパー(空引数チェック含め
  実MPDのParseTagMaskと同じ挙動)をそのまま再利用しclear+updateで実装。
  verified: dev mopidy(127.0.0.1:6601, ytmusic実アカウント)を実際に起動し
  MPDで直接確認——`tagtypes disable Genre Composer`→OK、続く`tagtypes`
  (引数無し)→Genre/Composerを含まない一覧(既存挙動、回帰なし)、
  `tagtypes available`→disable状態と無関係にGenre/Composerを含む全34タグ
  (修正前は`ACK [2@0] {tagtypes} Unknown sub command`だったバグを再現・
  修正確認)、`tagtypes reset Artist Album`→OK、続く`tagtypes`→Artist/Album
  のみ(clear+enableのアトミック動作を確認、修正前はACK)、`tagtypes all`→
  全復元、`tagtypes clear`→空、`tagtypes reset`(引数無し)→
  `ACK [2@0] {tagtypes} Not enough arguments`(実MPDのParseTagMaskと同じ
  エラー、素のValueError等によるセッション切断ではないことを確認)、
  `tagtypes bogus`→`ACK [2@0] {tagtypes} Unknown sub command`(未知サブ
  コマンドの既存拒否、回帰なし)。**回帰確認**: `protocol available`/
  `stringnormalization available`(兄弟コマンド、無変化)、`status`、
  `search any "yoasobi"`(実データ検索、実トラック2件+アルバム擬似行1件、
  回帰なし)を確認。mopidy.logに新規ERROR/Traceback無し、mopidy起動も
  クリーンであることを確認した。

- [x] mpdtracknofabricate-patch.py適用後も`translator.py`の`track_to_mpd_format()`が
  `track.track_no`・`track.album.num_tracks`が両方既知の(mopidy_ytmusicで最も頻繁に
  踏む)通常ケースでは依然`Track: N/M`というスラッシュ結合形式を出力してしまい、
  rmpc本体の既定曲順ソート・トラック番号列表示を壊す不具合。TODO全項目消化済みの
  ため自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。最初にサブエージェントが提案した「mopidy_ytmusicの全トラックで
  Last-Modifiedが常に欠落する」という候補は、過去のセッション記録(本BACKLOG
  10300〜10305行目、mpdsincefilter-patch.pyのverifiedコメント)で既に
  「last_modified=Noneは実MPDのファイルmtimeに相当する概念がYouTube Musicに
  無いための正当な制約であり、フォールバック値(get_or_stamp_library_addedの
  近似時刻等)を偽装すべきでない」と明示的に判断済みだったため却下し、
  データを捏造しない別候補として本件を採用した。
  根拠: mierak/rmpc本体を実際にcloneし直接ソース確認 —
  `rmpc/src/config/defaults.rs`の`default_song_sort()`(ユーザーが何も
  カスタマイズしなくても効く既定曲順)は`[Disc, Track, Artist, Title]`で、
  `rmpc/src/ui/dir_or_song.rs`の`SongProperty::Track`比較は
  `CmpByProp::opt_str_parse::<_, i32>(...)`により両辺を`.parse::<i32>()`し、
  両方失敗した場合(`(Err(_), Err(_))`)にのみ文字列比較にフォールバックする
  実装(283〜320行目)。"3/12"と"10/12"はどちらもi32 parseに失敗するため
  両方とも文字列比較に落ち、`"10/12" < "3/12"`(先頭文字'1'<'3')という
  辞書順でソートされ、アルバムの既定曲順(10曲目以降が2桁目以降の曲より前に
  来る)が破綻する。`rmpc/src/ui/song_ext.rs`の`SongProperty::Track`表示
  (345〜351行目)も`v.last().parse::<u32>()`失敗時に生の"N/M"文字列がそのまま
  フォールバック表示され、パース成功曲(ゼロ埋め"01"/"02"表示)と混在して
  列が不揃いになる。実MPDはTRACKNUMBERタグの値をファイルから読んだ文字列として
  そのまま透過するのみで、位置(N)と総数(M)という別々の整数フィールドを
  サーバー実装が自ら合成してスラッシュ結合する経路は存在しない
  (mpdtracknofabricate-patch.py自身のコメントも同旨を既に指摘していたが、
  当時はtrack_no未知・num_tracks既知の捏造ケースのみを修正対象とし、
  track_no・num_tracks両方既知の通常ケースの"N/M"形式自体は温存していた)。
  mpdtracknoslash-patch.py: `if track.track_no is not None:`ブロックから
  `track.album.num_tracks`とのf-string結合分岐を削除し、track_no既知時は
  常に`("Track", track.track_no)`という整数単体を出力するよう単純化。
  `nix/lib/mopidy-env.nix`の`mpdPatched`へ`mpdtracknofabricate-patch.py`が
  導入したMARKER(`if track.track_no is not None:`)を書き換えるため、その
  直後ではなく他に同関数を触る後続パッチが無いリスト末尾(`mpdtagtypesavailablereset-patch.py`
  の直後)として登録しビルド成功。オフラインで一時コピーに`mpdtracknofabricate-patch.py`
  →`mpdtracknoslash-patch.py`の順に当ててast.parseで構文確認、2回適用しても
  冪等(スキップ)であることも確認。
  verified: dev mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を実際に
  起動しMPDプロトコルで直接テスト — ビルド後の`translator.py`に
  `result.append(("Track", track.track_no))`が反映されていることをソースで確認、
  `search album "THE BOOK"`(実データ、200曲超のヒット)の全応答から`Track:`行を
  抽出したところ`Track: 1`〜`Track: 200`まで一つもスラッシュを含まない整数単体に
  なっていることを確認(2桁・3桁のトラック番号も含め回帰なし)、`lsinfo
  "ytmusic:album:..."`でも同様に`Track: 1`(スラッシュ無し)を確認。**回帰確認**:
  `findadd`でキューに追加した曲の`playlistinfo`でも同じ整数単体のTrackを確認
  (current_playlist.py経由でも同じtranslator関数を共有するため波及済み)、
  `ping`/`status`/`stats`/`tagtypes`/`clear`が正常応答することを確認、
  mopidy.logに新規ERROR/Traceback無し、mopidy起動もクリーンであることを確認した。

- [x] `mopidy_mpd/translator.py`の`track_to_mpd_format()`(currentsong/playlistinfo/
  find/search等全コマンドが共有)がArtist/AlbumArtistは`multi_tag_list()`で出力する
  のにArtist.sortname由来のArtistSort/AlbumArtistSort値は一切読まずどの応答にも
  出力しない不具合を修正 (mpdsortvalue-patch.py)。TODO全項目消化済みのため自走
  エージェントがgeneral-purposeサブエージェントへの調査委任を経て新規発見。
  mpdtagnames2-patch.py(本BACKLOG該当行参照)はArtistSort/AlbumArtistSortを
  find/list/フィルタ式で"認識"できるようにしたが、これはmopidy
  core.library.search()の固定フィールド集合に対応が無いための"phantom"タグ
  登録(検索キーとして使えない)であり、「既に取得済みTrackオブジェクトの
  Artist.sortname値を出力に含める」こととは無関係のまま別の不具合として
  放置されていた。同関数内のMUSICBRAINZ_ALBUMARTISTID/MUSICBRAINZ_ARTISTIDも
  同じくphantom(search不可)扱いだが取得済み値はconcat_multi_valuesで出力する
  既存パターンがあり、ArtistSort/AlbumArtistSortだけがこの対称性から漏れて
  いた。mopidy_ytmusic/library.pyは全Artist生成箇所(11箇所)で
  `Artist(name=..., sortname=a["name"], ...)`と非空値付きで生成しており、
  値は既に存在するのにtranslator.pyがそれを読まず捨てているだけの純粋な
  データロスだった。mierak/rmpc本体(`rmpcd/src/lua/lualib/mpd/types/song.rs`、
  songメタデータを固定enumでなく生の`HashMap<String, MetadataTag>`として保持)
  の`artist_sort`/`album_artist_sort`という専用Luaゲッターは
  `metadata["artistsort"]`/`metadata["albumartistsort"]`をMPD応答から直接
  参照するため、ユーザーのLuaテーマ/スクリプトが`song.artist_sort`を使うと
  本backendに対しては常に`nil`になっていた。修正: Artist/AlbumArtistと全く
  同じ`multi_tag_list()`呼び出しパターンでsortname属性から
  ArtistSort/AlbumArtistSortを追加出力するだけ(値の無いArtistは
  `multi_tag_list`内部で自動的にスキップされ既存のtagtypes無効化/
  フィルタ式非対応には無変更)。
  verified: dev mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を実際に
  起動しMPDプロトコルで直接テスト — `find artist "YOASOBI"`(実データ、アルバム
  擬似行10件超+実トラック多数)の応答全件で`Artist: YOASOBI`の直後に
  `ArtistSort: YOASOBI`、`AlbumArtist: YOASOBI`の直後に
  `AlbumArtistSort: YOASOBI`が出力されることを確認(修正前はArtistSort/
  AlbumArtistSort行が一切無かった)。`search album "THE BOOK 3"`の実トラック
  (`Track: 1`等、通常曲データ)でも同様にArtistSort/AlbumArtistSortが出力
  されることを確認。**回帰確認**: `tagtypes disable ArtistSort
  AlbumArtistSort`後の`find artist "YOASOBI"`では両タグが応答から消えること
  (既存のtagtypesフィルタ機構`_has_value()`が新規出力にも正しく効くことを
  確認)、`tagtypes all`で復元後は再び出力されること、`ping`/`status`/
  `tagtypes`(引数無し一覧)が正常応答することを確認した。mopidy.logに新規
  ERROR/Traceback無し、mopidy起動もクリーンであることを確認した。

- [x] `playlistfind`/`playlistsearch`の`sort {TYPE}`修飾子が、find/search/list/
  countと共有するmusic_db.pyの`_SORT_MAPPING`/`_mpd_extract_sort_params`を
  そのまま使っており、実MPD仕様(mpd.readthedocs.io protocol.htmlの
  playlistfind節に"The type "Last-Modified" can sort by file modification
  time, and "prio" sorts by queue priority."と明記、WebFetchで実際に文面確認
  済み)にある`sort prio`(キュー優先度でソート)を送ると`_SORT_MAPPING`に
  "prio"キーが無いため即`ACK Unknown sort type: prio`になる不具合を修正。
  TODO全項目消化済みのため自走エージェントがgeneral-purposeサブエージェントへ
  調査を委任し新規発見。BACKLOG.mdを`grep -n "sort prio\|playlistfind.*sort\|
  _SORT_MAPPING\|_mpd_extract_sort_params"`で確認し、sort修飾子自体の導入
  (mpdplaylistfind-patch.py)は既出でも"prio"キー欠落は未対応・未blockedと
  確認した。優先度(`prio`/`prioid`)はキュー限定の概念でDB検索
  (find/search/list/count)側には対応する曲が存在しない
  (mpdpriofilter-patch.pyの`(prio >= "N")`フィルタ式実装と同じ非対称性)ため、
  共有の`_SORT_MAPPING`自体には"prio"を追加せず(find/search側にまで
  `sort prio`が波及して誤って有効になるのを防ぐため)、current_playlist.py
  専用の`_PF_SORT_MAPPING`/`_pf_extract_sort_params`を新設し、
  `translator.get_priority(tlid)`の実データでソートするよう実装。
  verified: mpdplaylistfindsortprio-patch.py。パッチ適用後の生成ソースを
  一時コピーに`mopidy_mpd/protocol/`構造を再現して当て`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の
  `mpdPatched`へ`mpdsortvalue-patch.py`の直後(リスト末尾)として登録しビルド
  成功。**実データ確認**: dev mopidy(127.0.0.1:6601、mopidy-ytmusic実
  アカウント)を実際に起動しMPDプロトコルで直接テスト — `clear`→
  `findadd "(any contains \"YOASOBI\")"`でYOASOBI実トラック2曲をキューに
  積み、`prioid 50 <Id1>`/`prioid 80 <Id2>`で優先度を設定した状態で
  (1)修正前は`playlistfind "(any contains \"YOASOBI\")" sort prio`が
  `ACK [2@0] {playlistfind} Unknown sort type: prio`だったことを実機で確認済み、
  (2)修正後は`sort prio`(昇順、Prio50→Prio80の順)/`sort -prio`(降順、
  Prio80→Prio50の順)ともに正しい順序でPos/Id/Prio付きフル情報を返すことを
  確認、(3)`playlistsearch any "yoasobi" sort prio`(小文字部分一致+
  sort prio併用)も同様に正しく動作することを確認。**回帰確認**:
  `playlistfind ... sort Title`(既存のタグソート)が引き続き正常動作、
  `playlistfind ... sort Bogus`(未知sortタイプ)が引き続き
  `ACK Unknown sort type: Bogus`、共有側の`find "(any contains \"YOASOBI\")"
  sort prio`が引き続き`ACK [2@0] {find} Unknown sort type: prio`
  (共有`_SORT_MAPPING`へは波及していないことを確認)、mopidy.logに新規
  ERROR/Traceback無し、mopidy起動もクリーンであることを確認した。

- [x] `count`/`searchcount`が`group`修飾子を`list`と共有の
  `_mpd_extract_group_params()`(末尾から`group TAG`対を繰り返し剥がす
  whileループ、複数連鎖group対応)でパースしており、`count group artist
  group album`のように2組以上の`group`を渡してもACKにならず素通りして
  誤ってネストしたcount結果を返してしまう不具合を修正。TODO全項目消化済み
  のため自走エージェントがgeneral-purposeサブエージェントへ調査を委任し
  新規発見。BACKLOG.md:109-110では`count group album group artist`が
  「album毎に正しくネスト」と記録され正常動作として扱われていたが、実MPD
  本体(gh rawで`src/command/DatabaseCommands.cxx`の`handle_count_internal`
  を実際に取得し確認)は`list`(`handle_list`、whileループで複数group対応)
  と異なり、単一の`if (args.size() >= 2 && args[args.size() - 2] ==
  "group")`でしか末尾groupを剥がさない(0.25時点のmaster/`v0.24`タグ双方で
  同一実装、`count group`導入以来この挙動)。2組目以降の`group`トークンは
  剥がされず`FILTER`側に残り、実MPDでは`SongFilter::Parse()`が未知の
  フィルタ型として`ACK Unknown filter type: group`を返す。修正:
  count/searchcount専用の単一group版`_mpd_extract_single_group_param()`を
  新設(`if`文、高々1組のみ剥がす、`group file`/`group filename`拒否は
  既存の`_mpd_extract_group_params`と同じくmpdlistgroupfile-patch由来の
  チェックを踏襲)し、`count()`/`searchcount()`の呼び出し元だけを差し替え。
  `list()`は無変更(`_mpd_extract_group_params`のまま、正しく複数group
  対応を維持)。剥がされなかった2組目以降の`group X`はそのまま
  `_query_from_mpd_search_parameters`(旧形式のタグ/値ペア解析)へ渡り、
  `_SEARCH_MAPPING`に`"group"`キーが無いため`MpdArgError("incorrect
  arguments")`でACKになる(実MPDとACK文言は異なるが拒否する点は一致、
  この関数を書き換える設計変更は今回のスコープ外)。
  verified: `mpdcountsinglegroup-patch.py`。パッチ適用後の生成ソースを
  一時コピーに`mopidy_mpd/protocol/`構造を再現して当て`ast.parse`で構文
  確認、新設関数を単体exec抽出しても仕様通り(単一group剥がし・
  file/filename拒否・未知タグ拒否)動作することを確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`の`mpdPatched`
  へ`mpdplaylistfindsortprio-patch.py`の直後(リスト末尾)として登録し
  ビルド成功。**実データ確認**: dev mopidy(127.0.0.1:6601、mopidy-ytmusic
  実アカウント)を実際に起動しMPDプロトコルで直接テスト —
  (1)修正前は`count group artist group album`/`searchcount group genre
  group album`が共に素通りしてOK(誤ったネスト結果)だったことを実装前の
  ソース読解で確認済み、(2)修正後は同2コマンドとも
  `ACK [2@0] {count}/{searchcount} incorrect arguments`を返すことを確認、
  (3)旧形式フィルタ併用の`count artist "YOASOBI" group artist group
  album`、同一フィールドを2回指定した`count group artist group artist`も
  同様にACKになることを確認。**回帰確認**: `count group artist`/
  `count group album`/`searchcount group artist`(単一group)は引き続き
  `OK`(songs/playtimeまたは空行)を返すこと、`count`/`searchcount`
  (group無し)も引き続き正常応答すること、`list album group artist`/
  `list genre group artist group album`(`list`は無変更のため複数group
  も引き続き受理されACKにならないこと)、`find artist "YOASOBI"`/
  `search artist "YOASOBI"`が実データ(805行/265行)を引き続き正常返却
  することを確認した。mopidy.logに新規ERROR/Traceback無し、mopidy起動も
  クリーンであることを確認した。
  なお、フィルタ式構文(`(TAG == "VALUE")`)を使った場合の
  `_query_from_mpd_search_parameters`は`parameters[0]`のみを式として
  解釈し、それ以降の残余引数(例: 剥がされなかった2組目の`group X`)を
  検証せず無条件に無視する設計になっており、`count "(Genre == \"Pop\")"
  group artist group album`はACKにならずOKを返すことを実機で確認した
  (実MPDはこのケースもACKになるべきと推測されるが未確認)。これは
  find/search/count/searchcount/findadd/searchadd/searchaddpl/
  searchplaylist/playlistfind/playlistsearch全てが共有する
  `_query_from_mpd_search_parameters`自体の「フィルタ式が残り引数の唯一の
  要素であることを検証しない」というより広範な既知の別不具合であり、
  今回のgroup個数制限とは独立した別項目としてスコープ外とした
  (次回以降の自走エージェントへの申し送り)。

- [x] `find`/`search`/`count`/`searchcount`/`findadd`/`searchadd`/`searchaddpl`/
  `searchplaylist`/`playlistfind`/`playlistsearch`全てが共有する
  `_query_from_mpd_search_parameters()`が、引数リストの先頭がフィルタ式
  (`"(TAG == \"VALUE\")"`等)の場合に`parameters[0]`だけを
  `_query_from_mpd_filter_expression()`へ渡してその戻り値を即returnし、
  `parameters[1:]`に残った引数を一切検証せず無条件に無視してしまう不具合を
  修正。mpdcountsinglegroup-patch.py検証時に実機で発覚しBACKLOG.mdへ
  「次回以降の自走エージェントへの申し送り」として記録されていた既知の
  残課題(TODO全項目消化済みのため過去の自走エージェントが発見・記録)。
  具体例: count/searchcountは`_mpd_extract_single_group_param()`で末尾の
  `group TAG`を高々1組しか剥がさないため、`count "(Genre == \"Pop\")"
  group artist group album`のように2組目のgroupが残ると、剥がされなかった
  `["group","artist"]`が完全に読み捨てられOKになってしまっていた。
  実MPD本体(gh rawでsrc/song/Filter.cxxのSongFilter::Parse(std::span<const
  char *const> args, ...)を実際に取得し確認)は、フィルタ式(先頭"("トークン)
  を1つ消費した後もdoループを継続し、残りの引数を旧来のTAG VALUEペアとして
  同じParse(tag, value)へ渡す(未知タグは"Unknown filter type"で例外→ACK)
  設計であり、フィルタ式と旧形式TAG VALUEペアの混在を許し両方をANDで積み
  重ねる。修正: `_query_from_mpd_search_parameters()`もこれに合わせ、
  フィルタ式消費後にparametersが空でなければ既存の旧形式TAG VALUEペア
  whileループをその残り引数に対して実行しqueryへAND結合で積み増す
  ようにした(未知タグに遭遇すると既存の`MpdArgError("incorrect
  arguments")`がそのまま働きACKになる、実MPDとACK文言は異なるが拒否する点
  はmpdcountsinglegroup-patch.pyのコメントと同じく一致)。フィルタ式自身の
  positives(kind=exact/regex情報付き)はそのまま温存し、mpdfindmultitag-
  patch.pyの「複数フィールドが単一値のみならローカルAND検証を信頼する」
  ヒューリスティックは、母集団(信頼するかどうかの判定対象)を末尾TAG
  VALUEペア部分だけから独立して計算しつつ、ゲート自体は合成後のquery
  合計フィールド数(フィルタ式1+末尾ペア1でも合計2)で判定するよう拡張した
  ——実装当初、末尾ペア単体の個数(`len(_mpdtrailing_query) > 1`)だけを
  ゲートにしたところ、`find "(any contains \"YOASOBI\")" artist
  "NoSuchArtistXYZ"`のような「フィルタ式1個+末尾ペア1個」の組み合わせで
  末尾ペアの条件がbackend側のelif連鎖(mpdfindmultitag-patch.pyのコメント
  参照、mopidy_ytmusic.library.search()は"any"等が有れば他フィールドを
  無視する)にもローカル再検証にも一切効かず黙って無視される回帰を実機で
  発見し、ゲート条件を合成後のquery合計フィールド数へ修正して解消した。
  verified: `mpdfilterexprtrailing-patch.py`。まずオフラインで
  `_query_from_mpd_search_parameters()`単体をパッチ適用済みコピーから
  import し、フィルタ式単体/フィルタ式+未知タグ(ACK)/フィルタ式+有効な
  単一trailing pair(2フィールドで信頼されpositivesに載る)/フィルタ式+
  2個のtrailing pair/フィルタ式+trailing半端(ValueError→ACK)/旧形式
  単体(1フィールドのみ、従来通り非信頼)/旧形式複数(従来通り信頼)/
  旧形式未知タグ(ACK)/否定フィルタ+trailing pair(require_positive=False)/
  フィルタ式+同一フィールド重複trailing(非信頼のまま維持)の全パターンを
  期待通りの戻り値・例外であることを確認。生成ソースは`ast.parse`で構文
  確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`の`mpdPatched`へ`mpdcountsinglegroup-patch.py`の
  直後(リスト末尾)として登録しビルド成功。**実データ確認**: dev
  mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を実際に起動しMPD
  プロトコルで直接テスト — (1)`count "(Genre == \"Pop\")" group artist
  group album`/`searchcount`同様→修正前は素通りOKだったことを実装前の
  ソース読解で確認済み、修正後は`ACK [2@0] {count}/{searchcount}
  incorrect arguments`を返すことを確認。(2)`find "(any contains
  \"YOASOBI\")" bogus`(フィルタ式+未知トークン)→`ACK [2@0] {find}
  incorrect arguments`。(3)`find "(any contains \"YOASOBI\")" artist
  "YOASOBI"`→フィルタ式単体(3件、うちalbumプレースホルダ1件はArtist
  フィールド無しでartist条件に一致せず)から正しく絞り込まれ実トラックの
  みに narrowing されることを確認。(4)`find "(any contains \"YOASOBI\")"
  artist "NoSuchArtistXYZ"`(存在しないartistとのAND)→修正前は3件が
  無条件にそのまま返っていたことを実機で確認済み、修正後は`OK`(0件)を
  返すことを確認。**回帰確認**: `count "(Genre == \"Pop\")" group
  artist`(単一group)/`count "(Genre == \"Pop\")"`(groupなし)は引き続き
  `OK`、`count group artist group album`(旧形式・フィルタ式無しの複数
  group)は引き続き`ACK incorrect arguments`(無変更)、`find "(any
  contains \"YOASOBI\")"`(trailing無し)は引き続き23行(3件)全件返却、
  `find artist "YOASOBI"`(旧形式単体)は引き続き265行の実データを正常
  返却、`list album group artist`(list専用の別ヘルパー、無変更)は引き続き
  `OK`、`find "(any contains \"YOASOBI\")" sort -Date window "0:2"`
  (sort/window併用、find()側で本関数呼び出し前に剥がされるため無関係)は
  引き続き正しく2件を返すことを確認。`status`含めmopidy.logに新規
  ERROR/Traceback無し、mopidy起動もクリーンであることを確認した。

- [x] `readpicture {URI} {OFFSET}` が画像取得失敗時に `albumart` と同一の
  `_mpdart_send()`(mopidy_mpd/protocol/connection.py, mpd-patch.py が追加)を
  共有しており、`_mpdart_bytes()` が失敗(None/空)を返す全経路で常に
  `ACK [50@0] {readpicture} No file exists` を返してしまう不具合を修正。
  TODO全項目消化済みのため自走エージェントが(general-purposeサブエージェントへ
  の調査委任を経て)新規発見。実MPD本体(raw.githubusercontent.comで
  `src/command/FileCommands.cxx` を直接取得し確認、WebFetch要約は使わず
  C++ソース自体を読解)の `handle_read_picture()` は `PrintPictureHandler`
  の `OnPicture()` が一度も呼ばれず `found` がfalseのままでも常に
  `CommandResult::OK` を返すのみで何も出力しない完全な空応答になる
  (offsetが画像サイズを超えた場合の`ACK_ERROR_ARG "Bad file offset"`のみ例外)。
  一方 `handle_album_art()` は該当箇所が見つからない場合に明示的に
  `r.Error(ACK_ERROR_NO_EXIST, "No art file exists")` を投げる——実MPDは
  この2コマンドの「見つからない場合」の応答を意図的に非対称にしている。
  mpd.readthedocs.ioのreadpicture節「If the song file was recognized, but
  there is no picture, the response is successful, but is otherwise empty.」
  とも一致する。既存のalbumart/readpicture関連記述(mpdalbumartnegcache-
  patch.py等)はいずれもこのACK応答自体を「回帰なしの正しい既存動作」の
  前提として検証しており、この非対称性には未着手だった。
  なお、TagAny.cxx(TagScanAny/TagScanDatabase)を確認すると、DBに存在しない
  曲(`GetRealSongUri`が`ACK_ERROR_NO_EXIST "No such song"`を投げる経路)は
  本来ACKになるべきケースだが、mopidy_ytmusicの`library.get_images()`は
  「曲が存在しない」場合も「曲は存在するが画像データが無い」場合も等しく
  空リストを返すのみで区別する情報を持たない。rmpcはreadpictureを常に
  自身が既に把握している(currentsong/playlistinfo等で取得済みの)曲URIに
  対してのみ呼ぶため実運用上「存在しない曲」経路には到達せず、この場では
  「画像取得失敗全般はOK空応答」という実装的に検証可能な範囲まで修正した
  (存在しない曲を区別してACKにする追加のDB問い合わせは行っていない)。
  修正: `_mpdart_send()`の`data`がfalsyな分岐を`with_type`で分岐し、
  readpicture(with_type=True)は例外を投げず戻り値Noneのみ返す(queue_send
  を一切呼ばない完全な空OK応答)。albumart(with_type=False)は現状通り
  `MpdNoExistError`のまま。`mpdreadpictureempty-patch.py`として実装し
  `nix/lib/mopidy-env.nix`の`mpdalbumartnegcache-patch.py`(`_mpdart_send`
  本体を最後に編集した既存パッチ)の直後に登録。
  verified: まずオフラインで、ビルド済みenvのmopidy_mpdパッケージ全体を
  `shutil.copytree`(バイト単位コピー+chmod 0o644、nix storeのread-only
  権限ビット回避)で隔離ディレクトリへコピーしパッチを適用、`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることを確認した。次に
  `nix/lib/mopidy-env.nix`へ登録して`~/ai/mopidy-dev/build-run.sh`でenvを
  再ビルドしdev mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を実際に
  起動しMPDプロトコルで直接テスト: (1)存在しないURI
  `ytmusic:album:BOGUSALBUMID12345readpicturetest2`に対し
  `readpicture "..." "0"`→修正前は`ACK [50@0] {readpicture} No file
  exists`だったことを実装前に実機で確認済み、修正後は`OK`(空応答、size/
  type/binaryフィールド無し)を返すことを確認。(2)同URIへの`albumart`は
  修正前後とも`ACK [50@0] {albumart} No file exists`のまま(無変更)である
  ことを確認。(3)実データのある曲(`search artist "YOASOBI"`で取得した
  実トラックURI)への`readpicture`は引き続き正常に`size:`/`type:`/
  `binary:`ヘッダ+実バイナリデータ(JPEGマジックバイト`\xff\xd8\xff\xe0`
  確認)を返すこと(正常系の回帰無し)を確認。**回帰確認**: `status`が
  引き続き正常応答することを確認、mopidy.logに新規ERROR/Traceback無し、
  mopidy起動もクリーンであることを確認した。

- [x] `status`応答の`xfade`フィールドが、mpdcrossfade-patch.py導入以来、値が0
  (crossfade未設定/`crossfade 0`リセット後の既定状態)でも常に`xfade: 0`を
  出力してしまう不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。実MPD本体
  (raw.githubusercontent.comで`src/command/PlayerCommands.cxx`の
  `handle_status()`を直接取得し確認)は兄弟フィールド`mixrampdelay`
  (mpdmixramp-patch.pyで対応済み、値が0より大きい時のみ出力)と全く同じ
  パターンで、`if (pc.GetCrossFade() > FloatDuration::zero())`のガードで
  crossfadeも値が0より大きい時だけ`xfade`行を出力し、既定値0では行自体を
  省略する。この分岐は少なくともv0.21.26から現行masterまで一貫した長期
  安定仕様。mpdmixramp-patch.py自身のコメントは「crossfadeは対応済み」と
  述べていたが、その「対応済み」の中身(常時出力)自体が実MPD仕様と
  食い違っており、mixrampdelay側だけ条件付き出力に修正されxfade側の
  対応漏れが残っていた(既存の`grep xfade`ヒット16件はいずれも「crossfade
  設定がxfadeへ反映されること」の検証記録のみで、「0の時に行を省略すべき
  か」という論点には未着手だった)。
  修正: `mpdxfadezero-patch.py`として`status.py`の`result`固定リストから
  `("xfade", _status_xfade(futures)),`を除去し、`mixrampdelay`と同じ場所
  (直前)に`xfade = _status_xfade(futures)`/`if xfade > 0: result.append(...)`
  の条件付き出力を追加。`nix/lib/mopidy-env.nix`の`mpdfilterexprtrailing-
  patch.py`(mpdPatchedリスト末尾)の直後に登録。rmpc(rmpc-mpd/src/commands/
  status.rs)のxfadeは`Option<u32>`としてパースされ行が無ければNone扱いに
  なる設計のため、行を省略してもクライアント側への悪影響はない。
  verified: まずオフラインで、ビルド済みenvのmopidy_mpdパッケージ全体を
  `shutil.copytree`(バイト単位コピー+chmod 0o644、nix storeのread-only
  権限ビット回避)で隔離ディレクトリへコピーしパッチを適用、`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることを確認した。次に
  `nix/lib/mopidy-env.nix`へ登録して`~/ai/mopidy-dev/build-run.sh`でenvを
  再ビルドしdev mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を実際に
  起動しMPDプロトコルで直接テスト: (1)crossfade未設定の初期状態`status`→
  `xfade`行が存在しない(修正前は`xfade: 0`が出力されていたことを実装前に
  確認済み)。(2)`crossfade 15`→`OK`、以後`status`→`xfade: 15`が正しく
  出力される。(3)`crossfade 0`(リセット)→`OK`、以後`status`→`xfade`行が
  再び消えることを確認。**回帰確認**: `mixrampdb -17`/`mixrampdelay 3`→
  `status`で`mixrampdb: -17.0`(常時出力、無変更)/`mixrampdelay: 3.0`
  (>0条件付き出力、無変更)が正しく反映されること、`crossfade abc`
  (非数値)が引き続き`ACK [2@0] {crossfade} incorrect arguments`になる
  こと(既存の引数検証のまま無変更)、`tagtypes`が34種のタグを引き続き
  正常に列挙すること、mopidy.logに新規ERROR/Traceback無し、mopidy起動も
  クリーンであることを確認した。

- [x] フィルタ式`(TAG OP "VALUE")`の明示的大文字小文字指定演算子`eq_cs`/`eq_ci`/
  `contains_cs`/`contains_ci`/`starts_with_cs`/`starts_with_ci`とその否定形
  `!eq_cs`/`!eq_ci`/`!contains_cs`/`!contains_ci`/`!starts_with_cs`/
  `!starts_with_ci`、および無印`contains`/`starts_with`の否定形
  `!contains`/`!starts_with`をmopidy_mpdが一切認識していなかった不具合を修正。
  TODO全項目消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任を経て)新規発見。実MPD本体(raw.githubusercontent.comでsrc/song/
  Filter.cxxを直接取得し確認、`ParseStringFilter()`の12エントリ`operators`配列)は
  これらをコマンド単位のfold_case既定値(find/playlistfind=大文字小文字区別、
  search/searchadd/searchaddpl/searchcount/playlistsearch=非区別)を演算子単位で
  上書きする機能として実装しており、`ParseExpression()`の通常タグと同じコード
  経路(`ParseStringFilter()`)から呼ばれる。
  mopidy_mpd側の実害は「未対応で無視される」だけでは済まなかった:
  `_query_from_mpd_filter_expression()`(music_db.py)は未知の演算子トークンを
  `_MPD_POSITIVE_OP_KIND.get(op, "exact")`で黙って"exact"にフォールバックし、
  かつ`_op_is_neg_token = op in ("!=", "!~")`がこれらの否定形(`!eq_cs`等)を
  否定トークンと一切認識しないため、本来除外条件であるはずの
  `(Artist !eq_cs "YOASOBI")`が肯定条件`Artist == "YOASOBI"`として誤解釈され、
  ACKも出さずクエリの正負が完全に反転する(除外のつもりが逆に「YOASOBIのみ」に
  絞り込まれる)というサイレントな不具合だった。
  修正: `_MPD_POSITIVE_OP_KIND`にcs/ci演算子(と無印否定`!contains`/
  `!starts_with`)を追加し新kind`exact_cs`/`exact_ci`/`contains_cs`/
  `contains_ci`/`starts_with_cs`/`starts_with_ci`として登録、`_op_is_neg_token`
  をこれらの否定トークン集合`_MPD_CS_CI_NEG_OPS`も見るよう拡張。後段フィルタ
  `_mpd_track_excluded`/`_mpd_track_matches_positives`(music_db.py、
  find/search/count/searchcount/findadd/searchadd/searchaddpl/searchplaylistが
  共有)と`_pf_matches`(current_playlist.py、playlistfind/playlistsearch専用の
  独自複製実装)双方に、新kindをコマンド単位のcase_sensitive/strict既定値を
  無視して強制的に大文字小文字区別/非区別する分岐を追加(strip_diacriticsは
  既存の共通前処理をそのまま踏襲、実MPD仕様通りcs/ci判定はfold_caseのみを
  上書きしdiacritics除去自体には影響しない)。`mpdfiltercsci-patch.py`として
  実装し`nix/lib/mopidy-env.nix`の`mpdxfadezero-patch.py`(mpdPatchedリスト末尾)
  の直後に登録。
  verified: まずオフラインで、ビルド済みenvのmopidy_mpdパッケージ全体を
  `shutil.copytree`(バイト単位コピー+chmod 0o644、nix storeのread-only権限
  ビット回避)で隔離ディレクトリへコピーしパッチを適用、`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることを確認した。env自身のpython
  (`$ENV/bin/python3`)で`_query_from_mpd_filter_expression()`/
  `_mpd_track_matches_positives()`/`_mpd_track_excluded()`(music_db.py)へ
  合成`Track`/`Artist`を直接与える単体テストで新kind全種の肯定/否定判定を確認。
  次に`nix/lib/mopidy-env.nix`へ登録して`~/ai/mopidy-dev/build-run.sh`でenvを
  再ビルドしdev mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を実際に
  起動しMPDプロトコルで直接テスト: (1)`find "(Artist eq_cs \"yoasobi\")"`
  (小文字)→0件、`find "(Artist eq_cs \"YOASOBI\")"`(大文字)→22件、`find
  "(Artist eq_ci \"yoasobi\")"`(findのcs既定を上書き)→22件、`search "(Artist
  eq_cs \"yoasobi\")"`(searchのci既定を上書き)→0件、と演算子単位の強制が
  コマンド既定値を正しく上書きすることを確認。(2)否定形の正負反転バグ修正を
  実機のqueueで確認(`clear`→`findadd "(Artist == \"YOASOBI\")"`で5曲投入):
  `playlistfind "(Artist !eq_cs \"YOASOBI\")"`(実際のアーティスト名と完全一致)
  →0/5件(全曲除外、修正前は逆に肯定条件として誤解釈され5/5件になっていた
  はず)、`playlistfind "(Artist !eq_cs \"yoasobi\")"`(大文字小文字不一致)→
  5/5件(cs強制のため否定条件が発火せず全曲残存)、`playlistfind "(Artist
  !eq_ci \"yoasobi\")"`(ci強制、大文字小文字不一致でも一致)→0/5件(全曲除外)。
  (3)`contains_cs`/`contains_ci`/`starts_with_cs`/`starts_with_ci`/無印
  `!contains`/`!starts_with`も同じqueueで期待通り(cs版は大文字小文字不一致で
  0件・一致で5件、ci版は常に5件、`!contains`/`!starts_with`はcs既定
  (playlistfind)で大文字小文字一致時のみ正しく除外)であることを確認。
  **回帰確認**: 既存の`==`/`!=`/`contains`/`=~`/`(base ...)`/`AND`結合が
  修正前後で結果件数(5/0/5/5/22/0件)に変化が無いこと、`tagtypes`が37種の
  タグを引き続き正常に列挙すること、mopidy.logに新規ERROR/Traceback無し、
  mopidy起動もクリーンであることを確認した。

- [x] `shuffle`が範囲内に再生中の曲を含む場合でもその位置を一切固定せず全曲を
  無差別にシャッフルしてしまう不具合を修正。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。実MPD本体(raw.githubusercontent.comで`src/queue/PlaylistEdit.cxx`の
  `playlist::Shuffle()`を直接取得し確認)は次の仕様: `playing`(再生中/一時停止中、
  停止していない状態)かつ現在の曲が指定範囲(`songrange`省略時は全体)に含まれる
  場合、まずその曲を`SwapPositions()`で範囲の先頭(`range.start`)へスワップし、
  その後`range.start`を1つ進めてから残りの範囲だけを`ShuffleRange()`する。つまり
  再生中の曲の位置(status応答の`song`)はshuffle実行後も常に範囲の先頭に固定
  される仕様。mopidy_mpd側(`current_playlist.py`の`shuffle()`、
  mpdmoveswaprace-patch.py/mpdrangeempty-patch.py適用後の形)はこの固定処理を
  一切持たず`context.core.tracklist.shuffle(start, end)`を呼ぶだけで、
  呼び出し先の`mopidy/core/tracklist.py`の`Tracklist.shuffle()`も範囲内の
  全曲(再生中の曲を含む)を無差別に`random.shuffle()`するのみだった。
  修正: `mpdshufflepin-patch.py`として`shuffle()`に、range_start/range_endを
  解決した上で(範囲が2曲以上かつ再生中/一時停止中かつ現在の曲が範囲内の場合)
  同ファイル内の既存`swap()`(`move()`を2回呼ぶ位置交換ロジックをそのまま再利用、
  新規実装なし)で現在の曲をrange_startへ入れ替え、range_startを1つ進めた上で
  `core.tracklist.shuffle(range_start, range_end)`を呼ぶよう変更。
  `nix/lib/mopidy-env.nix`の`mpdfiltercsci-patch.py`(mpdPatchedリスト末尾、
  current_playlist.pyへの最後の変更)の直後に登録。
  verified: まずオフラインで、ビルド済みenvのmopidy_mpdパッケージ全体を
  `shutil.copytree`(バイト単位コピー+chmod 0o644、nix storeのread-only
  権限ビット回避)で隔離ディレクトリへコピーしパッチを適用、`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることを確認した。次に
  `nix/lib/mopidy-env.nix`へ登録して`~/ai/mopidy-dev/build-run.sh`でenvを
  再ビルドしdev mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント)を実際に
  起動しMPDプロトコルで直接テスト: (1)`searchadd`で20曲キューに積み`play`で
  再生開始後、引数なし`shuffle`を8回連続実行→毎回`status`の`song`が常に0
  (修正前は`songid`は同一のまま`song`が14,16,17,9,19,16,11,14等とランダムに
  変化することを実装前に確認済み)、`songid`は同一のまま不変であることを確認。
  (2)再生中の曲(`song`=8)を含む範囲`shuffle "5:15"`→`song`が範囲の先頭である
  5に固定されることを確認。(3)再生中の曲(`song`=2)が範囲外の`shuffle
  "10:19"`→`song`は2のまま不変(位置固定処理が範囲外では発動しないことを確認)。
  (4)`stop`後の停止中`shuffle`→`OK`(エラー無し、位置固定処理は状態がstopの
  ため発動しない)。**回帰確認**: `shuffle "0:0"`(空範囲no-op、
  mpdrangeempty-patch.py由来のガード)→`OK`、`shuffle "0:1"`(1曲のみの範囲)→
  `OK`、`shuffle "0:999"`(範囲外end、mpdmoveswaprace-patch.py由来のACK変換)→
  `ACK [2@0] {shuffle} Bad song index`が引き続き正しく発生すること、
  `tagtypes`が37種のタグを引き続き正常に列挙すること、mopidy.logに新規
  ERROR/Traceback無し、mopidy起動もクリーンであることを確認した。

- [x] `sort ArtistSort`/`sort AlbumArtistSort`修飾子がtrack.artists[].sortname値を
  一切見ず常に`sort Artist`/`sort AlbumArtist`と完全に同じ結果になってしまう
  不具合を修正。TODO全項目消化済みのため自走エージェントが(general-purpose
  サブエージェントへの調査委任を経て)新規発見。mpdsortvalue-patch.pyは応答
  本文へのArtistSort/AlbumArtistSort値の出力(表示側)のみ対応済みで、ソート
  キー側の`_mpd_sort_value`/`_SORT_MAPPING`(music_db.py、find/search/list/
  count/findadd/searchadd/searchaddplが共有し、current_playlist.pyの
  playlistfind/playlistsearchも`_PF_SORT_MAPPING = dict(_SORT_MAPPING)`で
  そのまま再利用)は無関係のまま放置されていた別の不具合(mpdsortvalue-patch.py
  が表示とソートの非対称性を扱ったのと同型のパターン)。実MPD本体
  (raw.githubusercontent.comでsrc/tag/Tag.cxxを直接取得し確認、WebFetchの
  要約ではなく生ソースで確認)の`Tag::GetSortValue(TagType type)`はSORT版
  タグの値をまず試し、無ければ`DecaySort()`(ArtistSort→Artist、
  AlbumArtistSort→AlbumArtist)経由で非SORT版を試し、それも無ければ
  `Fallback()`(AlbumArtist→Artist)で更にもう一段フォールバックする3段階
  解決を行う: ArtistSortは「ArtistSort値→Artist値→空」、AlbumArtistSortは
  「AlbumArtistSort値→AlbumArtist値→Artist値→空」の順。mopidy_mpd側の
  `_SORT_MAPPING`は`"artistsort": "artist"`/`"albumartistsort":
  "albumartist"`と、要求を最初から内部フィールド名へ潰してしまうため、
  「SORT版タグ由来か」という情報自体が`_mpd_sort_value(track, field)`へ
  渡る前に失われ、SORT版タグの値が常に無視されていた。
  修正: `mpdsortsortname-patch.py`として`_SORT_MAPPING`で
  "artistsort"/"albumartistsort"を独立フィールド名のまま渡すよう変更し、
  `_mpd_sort_value`に新分岐を追加。既存の"albumartist"分岐が既に持つ
  「album.artists→無ければartist」というFallback(AlbumArtist→Artist)相当の
  フォールバックへ"albumartistsort"分岐から委譲することで、実装を増やさず
  実MPDの3段フォールバック全体を再現(`_mpd_sort_value(track,
  "albumartistsort")`→無ければ`_mpd_sort_value(track, "albumartist")`→
  その内部で無ければ`_mpd_sort_value(track, "artist")`)。
  `nix/lib/mopidy-env.nix`の`mpdshufflepin-patch.py`(mpdPatchedリスト末尾、
  music_db.py/current_playlist.pyの直近の変更で_SORT_MAPPING/
  _mpd_sort_value自体の完全書き換えは無いため挿入位置の安全性は高い)の
  直後に登録。
  verified: まずオフラインで、ビルド済みenvのmopidy_mpdパッケージ全体を
  `shutil.copytree`(バイト単位コピー+chmod 0o644、nix storeのread-only
  権限ビット回避)で隔離ディレクトリへコピーしパッチを適用、`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることを確認。合成`Track`/
  `Artist`/`Album`をenv自身のpython(`$ENV/bin/python3`)で`_mpd_sort_value`/
  `_mpd_sort_tracks`へ直接与え、sortnameありの場合の値優先・sortname無しの
  場合のartistへのフォールバック・album.artists空の場合のalbumartistsort→
  albumartist→artist連鎖、全パターンを単体で確認。次に`nix/lib/
  mopidy-env.nix`へ登録し`~/ai/mopidy-dev/build-run.sh`でenvを再ビルド
  (ビルド成功、生成music_db.pyに新実装が反映済みを確認)しdev mopidy
  (127.0.0.1:6601、mopidy-ytmusic実アカウント)を実際に起動。ただし
  mopidy_ytmusic側は全Artist生成箇所(11箇所超)でsortname==nameと常に
  同一値を設定するため、実データでは`sort ArtistSort`と`sort Artist`が
  区別できない(mpdsort-patch.py/mpdlist-patch.py等、過去の類似項目で
  確立済みの検証手法を踏襲): 検証用スタブbackend(pkg_resources
  entry_pointsで/tmpにdist-info生成、別ポート6602、sortname≠nameの
  Artist/Albumを持つ合成トラック3件、うち1件はsortname省略で
  フォールバック確認用)を実際に起動しMPDプロトコルで直接テスト:
  (1)`find any "Song" sort Artist`→Artist名アルファベット順(Beta<Zeta)で
  Song2,Song1。(2)同条件`sort ArtistSort`→sortname順(Alpha<Zulu)で
  Song1,Song2と`sort Artist`から独立して逆順になることを確認(修正前は
  両者が常に同じ結果だったはず、これが本項目の核心の回帰防止確認)。
  (3)`sort -ArtistSort`(降順)→Song2,Song1と正しく反転。(4)sortname省略の
  Song3を含めた3件`sort ArtistSort`→Song1(Alpha)/Song3(sortname無しの
  ため名前"Charlie Artist"へフォールバック)/Song2(Zulu)の順でフォールバック
  含め正しく解決。(5)`sort AlbumArtistSort`→album.artistsのsortnameを
  正しく参照、album.artistsが空のSong3は album.artists→track.artists
  (sortname無しのため名前)への2段フォールバックも実測で確認。
  (6)`clear`後3曲`add`しキュー化した上で`playlistfind "(any contains
  \"Song\")" sort ArtistSort`→find/searchと同じ順序で返り、
  current_playlist.py側の`_PF_SORT_MAPPING`/`_mpd_sort_value`共有経由で
  修正が自動的に波及することを確認。**回帰確認**: dev mopidy
  (127.0.0.1:6601、実ytmusicデータ)で`find any "yoasobi" sort ArtistSort`/
  `sort AlbumArtistSort`が修正前後で`sort Artist`と同じ結果を維持し
  ACKにならないこと(実データはsortname==nameなので順序に差は出ない、
  想定通り)、`search any "yoasobi" sort -Date`(既存sort field)、
  `find any "yoasobi" sort Track`、`sort Bogus`→
  `ACK [2@0] {find} Unknown sort type: Bogus`、`playlistfind ... sort
  prio`(mpdplaylistfindsortprio-patch.py由来、_mpd_sort_valueとは別分岐)
  全て変化なし、`tagtypes`が引き続き37種のタグを列挙、mopidy.logに新規
  ERROR/Traceback無し、mopidy起動もクリーンであることを確認した。

- [x] `sticker`系コマンド(get/set/delete/list/find/inc/dec)と`stickernamestypes`/
  `stickertypes`がTYPE引数として`song`のみ受け付け、`playlist`等その他ドメインを
  指定すると常に`ACK Unknown sticker domain`になる不具合を修正。TODO全項目消化済み
  のため自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。実MPD本体(gh rawで`src/command/StickerCommands.cxx`を直接取得し確認)
  はMPD 0.24以降`song`/`playlist`/`filter`/タグ種別12種の計4系統をサポートするが、
  mopidy_ytmusicバックエンドはfilter式マッチやタグ値単位の実データ構造を持たない
  ため、このパッチではrmpc(mierak/rmpc)が実際に使いうる最小スコープとして
  `playlist`ドメインのみを追加(filter/タグ種別は別スコープとして対象外)。
  実MPDの`PlaylistHandler::ValidateUri`はURIを`ListPlaylistFiles()`で実在チェック
  し、無ければ`std::invalid_argument`を送出する。`src/command/CommandError.cxx`の
  `ToAck()`で`std::invalid_argument`は`ACK_ERROR_ARG`(2)に変換される
  (`ACK_ERROR_NO_EXIST`(50)ではない点に注意、既存の`_get_playlist()`が使う
  `MpdNoExistError`をそのまま流用すると実MPDと異なるACKコードになってしまう
  ところだった)。ただしこの検証は`Get`/`Set`/`Inc`/`Dec`/`Delete`/`List`でのみ行われ、
  `find`(`DomainHandler::Find`、URIはプレフィックスとして使われる)では呼ばれない
  非対称仕様も確認し再現した。また`DomainHandler::Find()`は`song`ドメインのみ
  `file:`キーで結果を返し、非`song`ドメイン(`playlist`)は`{sticker_type}:`キー
  (`playlist:`)で返す点、`stickernamestypes`のTYPE引数フィルタが実MPD
  (`src/sticker/Database.cxx`の`StickerDatabase::NamesTypes()`、TYPE指定時は
  `type`列でWHERE絞り込み、無指定時は全件)と同様に機能する点も合わせて修正。
  `mpdstickerplaylist-patch.py`として実装し`nix/lib/mopidy-env.nix`の
  `mpdsortsortname-patch.py`(mpdPatchedリスト末尾)の直後に登録。
  verified: まずオフラインで、ビルド済みenvのmopidy_mpdパッケージ全体を
  `shutil.copytree`(バイト単位コピー+chmod 0o644、nix storeのread-only権限
  ビット回避)で隔離ディレクトリへコピーしパッチを適用、`ast.parse`で構文確認、
  2回適用しても冪等(スキップ)であることを確認。env自身のpython
  (`$ENV/bin/python3`)で合成contextを与え`_mpd_sticker_check_type`
  (song/playlist許可、filter拒否)/`_mpd_sticker_validate_uri`
  (songは無検査で常に通過、playlistは存在する名前のみ通過し存在しない名前は
  `MpdArgError`)/`stickertypes()`(song/playlist両方返す)を単体で確認した。
  次に`nix/lib/mopidy-env.nix`へ登録し`~/ai/mopidy-dev/build-run.sh`でenvを
  再ビルドしdev mopidy(127.0.0.1:6601、mopidy-ytmusic実アカウント、m3uバック
  エンド併用)を実際に起動しMPDプロトコルで直接テスト: (1)`searchadd`+`save`で
  実データ入りストアドプレイリスト`StickerTestList`を作成し`sticker set/get/list
  playlist "StickerTestList" rating ...`が正常動作(修正前は`ACK Unknown sticker
  domain: playlist`)。(2)存在しないプレイリスト名`sticker set/get playlist
  "NoSuchPlaylistXYZ" ...`→`ACK [2@0] {sticker} no such playlist: ...`
  (ACK_ERROR_ARG=2であることをACKコードの先頭数字で確認、50ではない)。
  (3)`sticker find playlist "" rating`→URI存在チェックをスキップして
  (find非対称仕様の確認)`playlist: StickerTestList`(`file:`ではなく`playlist:`
  キー)+`sticker: rating=5`を正しく返す。(4)`stickernamestypes`(TYPE無指定)→
  song/playlist両方のname/typeペアを列挙、`stickernamestypes playlist`→
  playlist型のみに絞り込み、`stickernamestypes song`→song型のみに絞り込み、と
  TYPEフィルタが機能することを確認。(5)`sticker inc playlist "StickerTestList"
  rating "2"`→`get`で5→7に正しく加算。(6)`sticker get filter ...`→引き続き
  `ACK Unknown sticker domain: filter`(対象外ドメインのまま無変更)。
  **回帰確認**: `sticker set/get/find song ...`が修正前後で同じ結果(`find`は
  引き続き`file:`キー)、`tagtypes`が引き続き37種のタグを列挙、mopidy.logに
  本パッチに起因する新規ERROR/Traceback無し(save時のYTMusicバックエンドへの
  プレイリスト作成試行401 UnauthorizedログはM3Uバックエンドへのフォールバックで
  save自体はOKを返す既存の環境挙動であり本パッチと無関係)、mopidy起動もクリーン
  であることを確認した。テスト用プレイリスト/スティッカーは全て`delete`/`rm`で
  後片付け済み。

- [x] `sticker find playlist {URI} {NAME}`が完全一致のプレイリスト名を指定しても
  常に0件(`OK`のみ、ACKにはならない「正常応答だが常に空」という気付きにくい型の
  不具合)を返してしまう不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。直前セッションが
  追加した`mpdstickerplaylist-patch.py`(`playlist`ドメイン対応)が、`sticker find`の
  ディレクトリ境界判定(`mpdstickerfinddir-patch.py`、非空URIに末尾"/"を付与してから
  前方一致、元々は`song`ドメインの兄弟ディレクトリ誤爆防止用)をfieldによる分岐なし
  そのまま流用していたため、`sticker set playlist "MyList" rating "5"`直後の
  `sticker find playlist "MyList" rating`が`"MyList".startswith("MyList/")`=Falseで
  必ず外れていた(空uriでの全件検索のみ動作、直前セッションの検証もこのケースしか
  テストしていなかったため見逃されていた)。実MPD本体(gh rawで
  `src/sticker/SongSticker.cxx`の`sticker_song_find()`と
  `src/command/StickerCommands.cxx`の`PlaylistHandler`/`src/sticker/Database.cxx`を
  直接取得し確認)では、末尾"/"付与によるディレクトリ境界判定は`SongHandler::Find`
  (`song`ドメイン専用)だけが行う特別扱いであり、`PlaylistHandler`(および
  `TagHandler`/`FilterHandler`)は基底`DomainHandler::Find()`をオーバーライドせず
  `sticker_database.Find(sticker_type, uri, ...)`へ生のuriをそのまま渡す。
  `Database.cxx`のSQL(`uri LIKE (? || '%')`)は全ドメイン共通の単純前方一致で
  スラッシュ付与を行わないため、`playlist`ドメインでは同一プレフィックスを持つ
  複数のプレイリスト名が同時にヒットするのが実MPDの正しい(意図的な)挙動である
  ことも確認した(平坦な識別子空間にディレクトリ概念を持ち込まない設計)。
  `mpdstickerplaylistfind-patch.py`として実装し`nix/lib/mopidy-env.nix`の
  `mpdstickerplaylist-patch.py`(`_mpd_sticker_find_ext`を最後に触れたパッチ)の
  直後に登録。修正: `_mpd_sticker_find_ext`内で`field == _MPD_STICKER_TYPE`
  (song)の場合のみ末尾"/"を付与し、それ以外(`playlist`)は生のuriをそのまま前方
  一致に使うよう分岐(song分岐の処理内容自体は既存コードと完全に同一のバイト列で
  変更なし)。
  verified: まずオフラインで、ビルド済みenvのmopidy_mpdパッケージ全体を隔離
  ディレクトリへコピーしパッチを適用、`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることを確認。次に`nix/lib/mopidy-env.nix`へ登録し
  `~/ai/mopidy-dev/build-run.sh`でenvを再ビルドしdev mopidy(127.0.0.1:6601、
  mopidy-ytmusic実アカウント)を実際に起動しMPDプロトコルで直接テスト:
  (1)実データ(YOASOBI検索結果)を`findadd`+`save`でストアドプレイリスト
  `StickerFindTestList`として作成、`sticker set playlist "StickerFindTestList"
  rating "5"`→`sticker find playlist "StickerFindTestList" rating`→修正後は
  `playlist: StickerFindTestList`+`sticker: rating=5`を正しく返す(修正前相当の
  コードでは`OK`のみ0件だったロジックであることをコード比較で確認済み)。
  (2)`sticker find playlist "" rating`(空uri、全件検索)は回帰なく引き続き同じ
  1件を返す。(3)`sticker get playlist ...`(既存の完全一致取得コマンド)も回帰なし。
  (4)実MPD仕様の再現確認: 同一プレフィックスを持つ2つ目の実プレイリスト
  `StickerFindTestListMore`(Ayase検索結果で作成)にも`sticker set`した状態で
  `sticker find playlist "StickerFindTestList" rating`を実行すると、実MPDの
  `Database.cxx`生SQL前方一致と同じく両方のプレイリストがヒットすることを確認
  (ディレクトリ境界を持ち込まない、これは バグではなく実MPD準拠の意図した挙動)。
  **回帰確認**: `song`ドメインの`sticker find`(該当分岐のコード自体が変更前と
  バイト単位で同一)、`tagtypes`(37タグ列挙)、`listplaylists`、`status`の他
  フィールドに変化なし。mopidy.logに本パッチに起因する新規ERROR/Traceback無し
  (既存の環境固有401 UnauthorizedログはM3Uフォールバックの既存挙動であり本パッチ
  と無関係)。テスト用プレイリスト/スティッカーは全て`sticker delete`/`rm`で
  後片付け済み。
- [x] `subscribe`/`sendmessage` (client-to-client messaging) に実MPDが持つ1クライアント辺りの
  購読チャンネル数上限(16)・未読メッセージ数上限(64)が一切実装されておらず、無制限に
  サーバー側メモリを消費できてしまう不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  verified: mpdchannellimit-patch.py。実MPD本体(raw.githubusercontent.comで
  `src/client/Client.hxx`の`MAX_SUBSCRIPTIONS=16`/`MAX_MESSAGES=64`、
  `src/client/Subscribe.cxx`の`Client::Subscribe()`(判定順: 不正名→上限到達→重複、
  上限到達チェックが重複チェックより先で、既に上限まで購読済みの状態で同じチャンネル名を
  再度subscribeしてもALREADYではなくFULLになる)/`Client::PushMessage()`(対象クライアントの
  未読メッセージ数が上限ならそのクライアントへの配送だけを黙ってスキップ、ACKにはならない)、
  `src/command/MessageCommands.cxx`の`handle_subscribe()`(FULLを`ACK_ERROR_EXIST`(56)+
  "subscription list is full"にマップ)/`handle_send_message()`(購読者全員へ配送を試み1人でも
  成功すればOK、全員失敗ならACK_ERROR_NO_EXIST "nobody is subscribed to this channel"、
  "無購読"と"全員キュー満杯"を区別しない)を直接取得し確認した上で移植。
  translator.pyに実MPDと同じ定数(`_MPD_MAX_CHANNEL_SUBSCRIPTIONS=16`/
  `_MPD_MAX_CHANNEL_MESSAGES=64`)を追加、`channel_subscribe()`は"ok"/"already"/"full"の
  3値文字列を実MPDと同じ判定順で返すよう変更、`channel_push_message()`は対象セッション毎の
  未読メッセージ数上限チェックを追加(上限到達時はそのセッションのみスキップ、他対象・
  戻り値には無影響)。`protocol/channels.py`の`subscribe()`は"full"時に
  `MpdExistError("subscription list is full")`を返すよう変更(mpdchannelpartition-patch.pyが
  最後に触れた同関数群のためnix listでその直後に登録)。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。dev mopidy(6601, ytmusic実アカウント)を実際に起動し
  MPDプロトコルで直接テスト: (1)1接続で`subscribe ch1`〜`ch16`→全OK、`subscribe ch17`→
  `ACK [56@0] {subscribe} subscription list is full`、上限到達中に既存購読`ch1`への
  再subscribeも`already`ではなく`full`(実MPDの判定順どおり)、`unsubscribe`で2枠空けてから
  新規`subscribe`→OK、既存購読への再subscribe(上限未満)→
  `ACK [56@0] {subscribe} already subscribed to this channel`(回帰なし)。
  (2)2接続で受信側が1チャンネル購読、送信側から`sendmessage`を64回→全OK、受信側
  `readmessages`→`message:`行がちょうど64件、65回目の`sendmessage`→受信側キュー満杯で
  唯一の購読者への配送が失敗し`ACK [50@0] {sendmessage} nobody is subscribed to this channel`
  (実MPDの"無購読"と区別しない仕様どおり、バグではなく仕様どおりの応答であることをテスト
  期待値側で確認済み)。**回帰確認**: `tagtypes`(37タグ列挙)・`status`・`channels`(空リスト)・
  `unsubscribe`未購読チャンネル(`ACK [50@0] not subscribed to this channel`、無変更)・
  `subscribe`不正チャンネル名(`ACK [2@0] Invalid unquoted character`、無変更)・
  `search any "YOASOBI"`(実データ検索)いずれも回帰なし。mopidy.logに本パッチに起因する
  新規ERROR/Traceback無し。
- [x] `idle`/`noidle`が、今回報告した(購読集合との積集合の)サブシステムだけでなく
  蓄積済み`context.events`を丸ごと`set()`で全消去してしまい、未購読・未報告の
  他イベントが握りつぶされる不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  verified: mpdidleconsume-patch.py。実MPD本体(raw.githubusercontent.comで
  `src/client/Idle.cxx`の`Client::IdleNotify()`(`idle_flags &= ~idle_subscriptions`—
  購読中のビットだけをidle_flags(接続生存期間持続する蓄積ビットマスク)から消費し
  未購読分は次回まで持ち越す)、`src/client/Process.cxx`のnoidle処理
  (`idle_waiting=false; WriteOK();`のみでidle_flagsには一切触れない)を直接取得し
  確認した上で移植。`mopidy_mpd/protocol/status.py`の`idle()`(積集合報告後の
  `context.events = set()`)/`noidle()`(キャンセル時の`context.events = set()`)、
  `mopidy_mpd/dispatcher.py`の`handle_idle()`(非同期プッシュ経路、イベント発生時に
  購読中クライアントへ即座に通知する側、同じく報告後の全消去)の3箇所を、
  いずれも「報告した(積集合の)サブシステムのみ`context.events`から差し引く」
  (`noidle()`は実MPD同様eventsのクリア自体を廃止)よう修正。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾に
  登録しビルド成功、生成ソースに新実装が反映されていることを確認した上でdev
  mopidy(6601, ytmusic実アカウント)を実際に起動しMPDプロトコルで直接テスト:
  (1)取りこぼし再現テスト — 1接続が`idle update`で待機中(updateのみ購読)に、
  別接続から`random`をtoggleして`options`イベント、`setvol`で`mixer`イベントを
  同時に発生させても(update購読では一致せず無応答のまま継続、想定通り)、
  その後`noidle`でキャンセルし改めて`idle mixer`→即座に`changed: mixer`、続けて
  `idle options`→即座に`changed: options`と、修正前なら`noidle`の
  `context.events = set()`で消え去っていたはずの2イベントがどちらも正しく
  持ち越されて配信されることを確認。(2)回帰確認 — 報告済みイベントは正しく
  消費され再度は報告されない(新規変化無しの`idle options`は無応答のまま継続)、
  蓄積済みイベントへの即時マッチ(`random`変更後の`idle options`→即
  `changed: options`)、複数サブシステム同時購読(`options`+`mixer`同時変化後の
  `idle options mixer`→両方`changed:`)、不正サブシステム名
  (`idle bogus`→`ACK [2@0] {idle} Unrecognized idle event: bogus`、
  mpdidle-patch.py既存挙動維持)、command_list内`idle`(接続クローズ、
  mpdcmdlistidle-patch.py既存挙動維持)いずれも無変化。mopidy.logに本パッチに
  起因する新規ERROR/Traceback無し。
- [x] `single {STATE}`/`consume {STATE}`(mpdoneshot-patch.pyでoneshot対応済み)が
  表示用3値状態(`"0"`/`"1"`/`"oneshot"`)をmopidy core呼び出し前に`state != "0"`で
  真偽値へ潰しており、mopidy core(`mopidy/core/tracklist.py`の`set_single`/
  `set_consume`)は真偽値が実際に反転した時だけ`options_changed`イベントを発火するため、
  `"1"`⇔`"oneshot"`間の遷移(真偽値はどちらもTrueのまま変化しない)では`idle
  "options"`通知が一切発火しない不具合。rmpc(rmpc-mpd/src/commands/status.rsの
  `OnOffOneshot::cycle()`が`Off→Oneshot→On→Off`の順で3値を送信する通常の
  キーバインド操作)が実際にこの`Oneshot→On`遷移を踏むため、`idle options`で
  待機中の別クライアント(または同一クライアントの別接続)がsingle/consumeの
  ステータス表示更新に一切気付けない、というサイレントな不整合が生じる。TODO
  全項目消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任を経て)新規発見。
  verified: mpdoneshotidle-patch.py。まずmopidy core本体
  (`$ENV/lib/python3.13/site-packages/mopidy/core/tracklist.py`)の`set_single`/
  `set_consume`を直接読み`if self.get_single() != value: self._trigger_options_changed()`
  という真偽値比較のみであることを確認。次に実MPD本体(raw.githubusercontent.comで
  `src/queue/Playlist.cxx`の`playlist::SetSingle`/`SetConsume`を直接取得)を確認し、
  実MPDは`SingleMode`/`ConsumeMode`という3値enumそのものを`if (status ==
  queue.single) return;`で比較するため、ON⇔ONESHOT遷移も値の変化として正しく
  検出し`EmitIdle(IDLE_OPTIONS)`を呼ぶ仕様であることを確認した上で移植。
  mpdcrossfadeidle-patch.pyと同じ自己完結`_mpdoneshotidle_notify()`方式を
  `mopidy_mpd/protocol/playback.py`に追加し、`single()`/`consume()`の末尾で常時
  `listener.send(mpd_session.MpdSession, "options")`を呼ぶよう修正(0⇔1/0⇔oneshot
  遷移ではcore側の発火と重複するが、idleのイベント集合への再追加は冪等でありno-opの
  ため実害無し。actor.pyの`_revert_oneshot()`はoneshot→"0"復帰時に真偽値が
  True→Falseへ実際に反転するためcore経由の既存通知で足りており変更不要)。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用しても
  冪等(スキップ)であることも確認。`nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾
  (mpdidleconsume-patch.pyの直後)に登録しビルド成功、生成ソースに新実装が
  反映されていることを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に
  起動しMPDプロトコルで直接テスト: 2接続のTCPソケットを用い、片方(A)で
  `single "1"`→`status`(`single: 1`確認)、もう片方(B)を`idle options`で
  待機させてからAで`single "oneshot"`→`status`(`single: oneshot`へ変化確認)、
  Bの応答が即座に`changed: options`となることを確認(修正前は無応答のまま
  タイムアウトしていたはずの遷移)。同様に`consume "1"`→`consume "oneshot"`の
  遷移でも同じ手順でBが`changed: options`を即座に受け取ることを確認。
  **回帰確認**: 上記テスト中の`status`応答(partition/volume/repeat/random/
  playlist/playlistlength/mixrampdb/state等の既存フィールド)に変化なし、
  mopidy.logに本パッチに起因する新規ERROR/Traceback無し。
- [x] find/search/count/playlistfind/playlistsearchが共有するフィルタ式パーサ
  (music_db.py/current_playlist.py)が実MPDの`AudioFormat`疑似タグ(`(AudioFormat
  == "RATE:FORMAT:CH")`/`(AudioFormat =~ "PATTERN")`、base/modified-since/
  added-since/prioと同じ枠組みの特殊擬似タグ)を一切認識せず`ACK Unknown filter
  type: AudioFormat`になる不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  verified: mpdaudioformatfilter-patch.py。実MPD本体(gh rawで
  `src/song/Filter.cxx`の`ParseExpression()`/`LOCATE_TAG_AUDIO_FORMAT`分岐、
  `src/song/AudioFormatSongFilter.cxx`の`Match()`
  (`song.audio_format.IsDefined() && song.audio_format.MatchMask(value)`)、
  `src/pcm/AudioParser.cxx`の`ParseAudioFormat()`、`src/pcm/AudioFormat.hxx`の
  `MatchMask()`を直接取得し確認した上で移植。演算子は`==`(完全一致、値に"*"不可)/
  `=~`(ワイルドカードマスク、各フィールドに"*"可)のみ許容、他はACK。値は
  "RATE:FORMAT:CH"(FORMATは8/16/24/24_3/32/f/dsdのいずれか)。比較対象は
  translator.pyの既存`_audio_format_cache`/`get_song_audio_format(uri)`
  (mpdaudioformat-patch.py/ytaudioformat-patch.py/mpdaudioformatpreload-patch.py
  で既に導入済み、status応答のFormatタグ/audioフィールドと共用のuriキー付き
  キャッシュ)を再利用、未解決(None)の曲は常に不一致(実MPDのIsDefined()==false
  相当)。旧式`find AudioFormat "..."`構文は実MPD自身の`SongFilter::Parse()`
  switchにも該当caseが無くdefault落ちする非対称仕様(mpdpriofilter-patch.pyの
  prioと同型)のため、新式`(TAG OP "VALUE")`フィルタ式のみに配線し据え置いた。
  パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で構文確認、2回適用
  しても冪等(スキップ)であることも確認、さらにパース/マッチ関数単体を
  `$ENV/bin/python3`で直接呼び出しexact一致/不一致・maskワイルドカード一致/
  不一致・未解決uri・不正演算子(ACK)・不正な値形式(ACK)を全てオフラインで
  検証済み。`nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾(mpdoneshotidle-
  patch.pyの直後)に登録しビルド成功、dev mopidy(6601, ytmusic実アカウント)を
  実際に起動しMPDプロトコルで直接テスト: 実トラック(ytmusic:track:by4SYYWlhEs)
  をadd+play後`currentsong`で`Format: 48000:16:2`を確認、`find "(AudioFormat ==
  \"48000:16:2\")"`が修正前`ACK [2@0] Unknown filter type: AudioFormat`だった
  ところ修正後は(DB検索側はaudio_formatのみの単独条件だとbackendへの検索語が
  無く常に0件になる、mpdpriofilter-patch.py既存のprio単独条件と全く同じ既知の
  非対称性を実機`find "(prio >= \"0\")"`でも再現確認)`OK`(0件、ACKではない)、
  一方`playlistfind "(AudioFormat == \"48000:16:2\")"`は実際のキューを検索する
  ため該当曲を正しく1件返し、`playlistfind "(AudioFormat == \"44100:16:2\")"`
  (不一致値)は正しく0件、`playlistfind "(AudioFormat =~ \"48000:*:*\")"`
  (ワイルドカードマスク)も正しく1件、否定`playlistfind "(!(AudioFormat ==
  \"48000:16:2\"))"`は正しく0件・`playlistfind "(!(AudioFormat ==
  \"44100:16:2\"))"`(不一致値の否定)は正しく1件を確認。他タグとのAND複合条件も
  実データで確認: `find artist "YOASOBI"`が実際に返した曲(ytmusic:track:
  mJ1N7-HyH1A)をadd+playしFormat確定後、`find "((Artist == \"YOASOBI\") AND
  (AudioFormat == \"48000:16:2\"))"`が該当曲を正しく1件返し、フォーマット値を
  `"44100:16:2"`に変えると正しく0件になることを確認。不正演算子
  `find "(AudioFormat >= \"48000:16:2\")"`→`ACK [2@0] '==' or '=~' expected`、
  不正な値形式`find "(AudioFormat == \"48000:16\")"`→`ACK [2@0] Invalid audio
  format: 48000:16`もいずれも実機確認済み。**回帰確認**: `status`/`tagtypes`
  (37タグ列挙)/`find artist "YOASOBI"`(実データ、多数のalbum/trackエントリ)/
  `search any "YOASOBI"`いずれも修正前後で応答に変化なし、mopidy.logに本パッチに
  起因する新規ERROR/Traceback無し。
- [x] `pause {PAUSE}`(明示引数版、`pause "1"`/`pause "0"`)が現在の再生状態を
  一切確認せず、停止中(STOP)でも強制的に一時停止状態へ遷移させてしまう
  不具合。TODO全項目消化済みのため自走エージェントが(general-purpose
  サブエージェントへの調査委任を経て、最初の候補=MPD多段階パーミッション
  モデル(password@permission)は認証アーキテクチャ全体を横断する大規模改修
  かつ誤実装時のロックアウト/バイパスリスクが高くスコープ外と判断し却下、
  同エージェントへ差し替えを依頼して)新規発見。`mopidy_mpd/protocol/
  playback.py`の`pause()`は引数無し(トグル)分岐(`state is None`)では
  `get_state()`を見てPLAYING/PAUSEDの時だけ動く既存の正しいガードがあるのに、
  明示引数分岐(`elif state:`/`else:`)だけは現在状態を一切見ず
  `context.core.playback.pause()`/`resume()`を無条件に呼ぶ(同一関数内の
  非対称)。実MPD本体(gh rawで`src/command/PlayerCommands.cxx`
  `handle_pause()`と`src/player/Control.cxx`
  `PlayerControl::LockSetPause()`を確認)は
  `switch (state) { case STOP: break; case PLAY: if (pause_flag) Pause();
  break; case PAUSE: if (!pause_flag) Pause(); break; }`という3状態switchで、
  STOP中は`pause_flag`の値に関わらず常に無視する仕様。mopidy core本体
  (`mopidy/core/playback.py`の`pause()`)もbackend呼び出しが成功する限り
  現在状態を見ずに`set_state(PAUSED)`するため、mopidy_mpd側・core側の
  双方に歯止めが無かった。
  verified: mpdpausestopguard-patch.py。まず対象ソース
  (`$ENV/lib/python3.13/site-packages/mopidy_mpd/protocol/playback.py`)を
  読み、引数無し分岐と明示引数分岐の非対称を確認。次に実MPD本体を
  `raw.githubusercontent.com`で直接取得し上記switch仕様を確認した上で移植:
  明示引数分岐にも引数無し分岐と同じ`get_state()`判定を追加し、`pause "1"`は
  PLAYING中のみ、`pause "0"`はPAUSED中のみ実際にcoreを呼ぶよう統一
  (STOP中はどちらも無視)。パッチ適用後の生成ソースは一時コピーに当てて
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾(mpdaudioformatfilter-
  patch.pyの直後)に登録しビルド成功、生成ソースに新実装が反映されている
  ことを確認した上でdev mopidy(6601, ytmusic実アカウント)を実際に起動し
  MPDプロトコルで直接テスト: `searchadd`で実トラックをキューへ追加、`play`
  →`stop`→`status`(`state: stop`確認)→`pause "1"`→`status`が修正前は
  `state: pause`へ誤って遷移していたところ、修正後は`state: stop`のまま
  不変であることを確認。同様に`pause "0"`(停止中)も`state: stop`のまま
  不変であることを確認。回帰確認として、`play`中の`pause "1"`→`state:
  pause`へ正しく遷移、一時停止中の`pause "0"`→`state: play`へ正しく復帰、
  さらに引数無しトグル(`pause`)も従来通りPLAYING⇔PAUSEDを正しく切り替える
  ことを確認。mopidy.logに本パッチに起因する新規ERROR/Traceback無し。

- [x] `single "oneshot"`(mpdoneshot-patch.pyで対応済み)が、対象曲の自然な
  再生終了を待たず`next`/`previous`(rmpcの通常のスキップ操作)を送っただけで
  即座にoffへ戻ってしまう不具合。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を2ラウンド経て)新規発見・
  修正した項目 (`mpdoneshotmanualskip-patch.py`)。
  verified: 実MPD本体(gh rawで直接確認)の該当ソースを精読。
  `src/queue/PlaylistControl.cxx` `playlist::PlayNext()`(明示`next`
  コマンド)は`queue.consume == ConsumeMode::ONE_SHOT`ならoffへ戻す処理は
  あるが`queue.single`には一切触れない。同ファイルの`PlayPrevious()`
  (明示`previous`)はsingle/consumeどちらにも触れない。`src/queue/
  Playlist.cxx` `playlist::BorderPause()`(`queue.single ==
  SingleMode::ONE_SHOT`をoffへ戻す唯一の箇所)は`src/player/Thread.cxx`
  `Player::SongBorder()`(対象曲が自然に終端へ達した時のみ player thread
  から呼ばれる)経由でしか呼ばれずPlayNext()/PlayPrevious()からは呼ばれ
  ない。同ファイルの`QueuedSongStarted()`(自然遷移でキュー済み曲が実際に
  再生開始した時点)はconsumeがONE_SHOTならoffへ戻す(自然終了でもconsume
  は戻る)。まとめると実MPDはsingle oneshotを「自然な曲送り」でのみ戻し、
  next/previous等の明示コマンドでは一切変更しない一方、consume oneshotは
  「自然な曲送り」と明示next両方で戻すが明示previousでは変更しない、という
  非対称仕様。mopidy_mpdの`MpdFrontend._revert_oneshot()`(actor.py)は
  mopidy core `track_playback_ended`イベント(自然遷移/明示next/明示
  previousいずれでも区別なく発火、`_on_stream_changed`/`_on_end_of_stream`
  をソース確認済み)1本だけを見てsingle/consume両方を無条件にoffへ戻して
  いた。修正: next/previousコマンドハンドラ(playback.py)がmopidy coreへ
  渡す直前に由来を揮発性ストア(translator.py
  `mark_pending_manual_track_change`/`pop_pending_manual_track_change`)へ
  記録し、`_revert_oneshot()`がpreviousなら両方とも戻さず・nextなら
  consumeのみ戻す・記録なし(自然遷移)なら従来通り両方戻すよう分岐。
  実機確認(TCP 6601、mopidy-ytmusic実アカウント、5曲キュー): (A)
  `single "oneshot"`→`play "1"`(songid=8)→`next`→songid=9へ実際に遷移
  かつ`single: oneshot`のまま(修正前は`single: 0`に誤って戻っていた
  はずの状況)を確認。(B) 続けて`single "oneshot"`→`previous`→songid=8へ
  実際に遷移かつ`single: oneshot`のまま を確認。(C) `consume "oneshot"`→
  `next`→実際に曲が遷移(playlistlength 5→4、再生済み曲が実際に
  consume削除された)かつ`consume: 0`(実MPDのPlayNext()と一致、この
  ケースは修正前後で不変の正しい既存動作)を確認。(D) 続けて
  `consume "oneshot"`→`previous`→実際に曲が遷移(playlistlength不変、
  previousはconsume削除しない)かつ`consume: oneshot`のまま(修正前は
  誤って`consume: 0`に戻っていたはずの状況)を確認。全ケースとも
  `wait_for_state`ヘルパで`state: play`かつ実際のsongid変化を都度確認して
  おり、コマンド未達/未反映による偽陽性ではないことを担保。mopidy.logに
  本パッチに起因する新規ERROR/Traceback無し(既存の無関係なyt-dlp 403一時
  解決失敗ログのみ、mopidy側は既存の未再生扱いフォールバックで正常継続)。
  自然終了時の単純な両方revertパス(command未設定=None時の分岐)は既存の
  検証済みコードと完全に同一のため今回未再検証(fakesinkの実時間比極端な
  低速進行により自然終了待ちが数時間規模になり現実的に検証不能なため)。
  残存(次回以降への申し送り、本項目のdoneには影響しない): 実機で`next`を
  tracklistが空/current未設定の状態(完全停止中)に
  送った場合、mopidy core `playback.next()`が`_change()`を一切呼ばず
  `track_playback_ended`が発火しないため、記録した`"next"`フラグが
  popされず次の(無関係な)自然終了revert機会まで持ち越されsingleのrevertを
  1回だけ誤って抑制しうる残存エッジケースがある(実MPD自体もこの状態での
  `next`は`PlaylistError::NotPlaying()`で本来ACKすべきところmopidy_mpdは
  元々無反応で許容しており、本パッチ以前からの独立した既知の仕様差)。
  rmpcは実際の再生中にしかnext/previousを送らないため実害範囲は狭く、
  今回は対応範囲外として次回以降への申し送りとする。
- [x] 上記項目自身が申し送った残存エッジケースを修正: `next_()`/`previous()`
  (playback.py) が現在再生中トラックの有無を確認せず無条件に
  next/previous由来フラグ (`translator.mark_pending_manual_track_change()`)
  を立てていたため、完全停止中(current_tl_track無し)に`next`/`previous`を
  送るとフラグがpopされずに残り、次の無関係な自然終了時の`_revert_oneshot()`
  で誤って`single "oneshot"`のrevertを1回抑制してしまう不具合。TODO全項目
  消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任を経て)、直近コミット自身がBACKLOG.mdに明記した申し送り事項を
  裏付け確認した上で修正。
  verified: mpdoneshotmanualskipguard-patch.py。mopidy core本体
  (`mopidy/core/playback.py`の`next()`/`previous()`)を確認したところ、
  `current = self._pending_tl_track or self._current_tl_track`がNone
  (完全停止中/未再生状態)の場合`while current:`ループが一度も回らず
  `_change()`が呼ばれない — `_change()`だけが`_on_stream_changed`/
  `_on_end_of_stream`経由で`track_playback_ended`を発火させるため、この
  状態でのnext/previousは実質何もせずイベントも発火しない。にも関わらず
  mopidy_mpd側の`next_()`/`previous()`はコマンドを受けた時点で無条件に
  `mark_pending_manual_track_change()`を呼んでいたため、フラグが
  pop されないまま残存し得た。修正: `context.core.playback.
  get_current_tl_track().get()`(status.py/current_playlist.pyが現在トラック
  有無の判定に既に使っている既存パターン)がNoneでない場合のみフラグを
  立てるガードを追加。パッチ適用後の生成ソースは一時コピーに当てて
  `ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾(mpdoneshotmanualskip-
  patch.pyの直後)に登録しビルド成功。dev mopidy(6601, ytmusic実アカウント)
  を実際に起動しMPDプロトコルで直接テスト: `clear`→2曲`searchadd`(未再生、
  `status`が`state: stop`かつ`songid`フィールド無しであることを確認=
  `current_tl_track`がNoneの状態)→`single "oneshot"`→この停止状態で`next`
  を送信(ガード対象のケース)→続けて`play "0"`で実際に再生開始→
  `seekcur`で曲の終端付近までシークし自然終了(track_playback_ended)を
  実際に発生させ、`status`をポーリングして`songid`が変化/`state`が
  `stop`になるまで待機 → 自然終了後、修正前なら残存フラグにより
  `single: oneshot`のまま誤って残るはずのところ、修正後は`single: 0`へ
  正しくrevertされることを確認(`playlistlength`は2のまま変化なし=
  consumeは無効のため削除も発生せず、これも正しい)。回帰確認として、
  実際の再生中(`current_tl_track`が存在する状態)に明示`next`/`previous`
  を送るケース(mpdoneshotmanualskip-patch.pyが対応済みの本来ケース)は
  修正前後で不変であることを別途確認 — `single "oneshot"`設定後、再生中に
  `next`→実際にsongidが変化しつつ`single: oneshot`のまま(revertされない
  のが正しい)、続けて`previous`→再びsongidが変化しつつ`single: oneshot`
  のまま、いずれも回帰無し。旧来の`tagtypes`(37タグ列挙)/`status`の他
  フィールド/`stop`の回帰なし・mopidy.logに本パッチに起因する新規
  ERROR/Traceback無し。
- [x] `sticker get/set/delete/list/inc/dec song {URI} ...`が、指定URIが実在する
  曲かどうかを一切検証せず、架空(存在しない/typo/スキーム無し不正形式)のURIに
  対しても無条件で`OK`を返しスティッカーを永続化してしまう不具合。TODO全項目
  消化済みのため自走エージェントが(general-purposeサブエージェントへの調査
  委任を経て)新規発見・修正した項目(`mpdstickersongvalidate-patch.py`)。
  `mpdstickerplaylist-patch.py`が導入した`_mpd_sticker_validate_uri()`
  (`mopidy_mpd/protocol/stickers.py`)はplaylistドメインの分岐
  (`context.lookup_playlist_uri_from_name(uri) is None`)は持つが、songドメイン
  の分岐が存在せず素通しになっていた。
  verified: 実MPD本体(gh rawで`src/command/StickerCommands.cxx`を直接取得し
  確認)の`SongHandler::ValidateUri()`は`database.GetSong(uri)`でURIがDB上に
  実在する曲かを検証し、無ければ例外を送出する(`src/command/CommandError.cxx`
  の`ToAck()`で`std::invalid_argument`→`ACK_ERROR_ARG`(2)、
  `ACK_ERROR_NO_EXIST`(50)ではない点、playlistドメインの既存実装と揃える)。
  この検証はGet/Set/Inc/Dec/Delete/Listのみで行われFind(URIをプレフィックス
  として使う)では呼ばれない非対称仕様のため、`sticker()`本体の既存の
  `if action != "find": _mpd_sticker_validate_uri(...)`ガードにそのまま乗せた。
  修正は`mpdaddidrawuriguard-patch.py`/`mpdplaylistaddpos-patch.py`等と同じ
  既存の`context.core.library.lookup(uris=[uri]).get()`パターンをそのまま
  踏襲し、`ValidationError`(スキーム無し等の不正URI)は空扱いに丸め、lookup
  結果が空(実在しない曲)なら`MpdArgError`で弾く。パッチ適用後の生成ソースは
  一時コピーに当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)である
  ことも確認。`nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾
  (mpdoneshotmanualskipguard-patch.pyの直後)に登録しビルド成功、生成ソースに
  新実装が反映されていることを確認した上でdev mopidy(6601、ytmusic実
  アカウント)を実際に起動しMPDプロトコルで直接テスト: 存在しない
  URI`sticker set song "ytmusic:track:doesnotexist000000" rating "5"`が修正前
  はOKを返し直後の`sticker get song ... rating`が値を読めてしまっていたところ、
  修正後は`ACK [2@0] {sticker} no such song: ...`で正しく拒否されることを確認。
  スキーム無し不正形式`sticker set song "not-a-real-uri-no-scheme" rating "5"`
  も同様にACKされることを確認。baseline として`sticker set playlist
  "NonexistentPlaylist12345XYZ" rating "5"`が既存通り`ACK [2@0] {sticker} no
  such playlist: ...`のまま不変であることも確認。回帰確認: 実在する曲
  (`search artist "YOASOBI"`で取得した`ytmusic:track:mJ1N7-HyH1A`)への
  `sticker set/get/list/inc/delete song`が全て正常動作(rating設定→取得
  (5)→list→inc後取得(6)→delete後`sticker get`が`ACK [50@0] {sticker} no such
  sticker`へ正しく変化)することを確認。`sticker find song "" rating`(実MPD
  仕様通り検証スキップ対象)は修正前後で不変(過去のテスト由来の架空URIの
  スティッカーも引き続き含めて返る、実MPDの`Find`が`ValidateUri`を呼ばない
  仕様と一致)。playlistドメインの`sticker set/get/delete playlist "soloTest"`
  (実在プレイリスト)も正常動作を再確認。`status`/`tagtypes`
  (37タグ列挙)/`stickertypes`(song/playlist)/`listplaylists`いずれも回帰無し。
  架空URI検証時に`mopidy_ytmusic`側で`KeyError: 'videoDetails'`のERRORログが
  出ることを確認したが、これは`library.lookup()`を同じ手法で使う既存の
  `addid`(パッチ済み)へ同じ架空IDを送っても全く同一のログが出ることを別途
  確認済みであり、本パッチ固有の新規回帰ではなく`library.lookup()`共有機構
  自体の既存の挙動(ytmusic側が未知IDを実際にAPI解決しようとして失敗する
  際のログ)であることを確認した。
- [x] `stop`コマンドが`single "oneshot"`/`consume "oneshot"`を意図せずoffへ
  戻してしまう不具合。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見・修正した項目
  (`mpdoneshotstop-patch.py`)。mopidy_mpdの`stop()`(playback.py)は
  next/previous(mpdoneshotmanualskip-patch.py)と違い
  `translator.mark_pending_manual_track_change()`を呼ばないが、mopidy core
  本体(`mopidy/core/playback.py`)の`_on_stream_changed(None)`のコード自身の
  コメント("This code path handles the stop() case, uri should be none.")が
  示す通り、明示`stop`も内部的に`track_playback_ended`イベントを発火させる
  ため、actor.pyの`_revert_oneshot()`がコマンド由来を区別できず
  single/consume両方を無条件でoffへ戻していた。
  verified: 実MPD本体(gh rawで`src/queue/PlaylistControl.cxx`
  `playlist::Stop()`を直接取得し確認)は`pc.LockStop()`/`queued = -1`/
  `playing = false`/(random時のみ)シャッフルのみを行い、`queue.single`/
  `queue.consume`には一切触れない。offへ戻す唯一の箇所は`src/queue/
  Playlist.cxx`の`BorderPause()`(single、自然終了経由のみ)と
  `QueuedSongStarted()`(consume、次曲への実遷移時のみ)であり、いずれも
  `Stop()`からは呼ばれない。修正: `stop()`がcoreへ委譲する直前(実際に
  状態変化を起こす場合、`get_state() != PlaybackState.STOPPED`の時のみ、
  mpdoneshotmanualskipguard-patch.pyのnext/previousと同じno-op除外の考え方)
  に`translator.mark_pending_manual_track_change("stop")`を記録し、
  `_revert_oneshot()`は`stop`由来を`previous`と同じく「single/consume
  どちらも戻さない」扱いにする。パッチ適用後の生成ソースは一時コピーに
  当てて`ast.parse`で構文確認、2回適用しても冪等(スキップ)であることも
  確認。`nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾
  (mpdstickersongvalidate-patch.pyの直後)に登録しビルド成功、dev mopidy
  (TCP 6601、mopidy-ytmusic実アカウント)を実際に起動しMPDプロトコルで
  直接テスト: `searchadd`で実トラックを積み`play`→`single "oneshot"`→
  `stop`を送ると修正前は`status`の`single`が`oneshot`から`0`へ誤って
  戻っていたところ、修正後は`single: oneshot`のまま維持されることを確認。
  `consume "oneshot"`でも同様に`stop`後`consume: oneshot`が維持されることを
  確認。回帰確認: 実際の再生中に明示`next`を送るケース(single維持/consume
  はoff、既存仕様通り)、明示`previous`を送るケース(single/consume共に
  維持、既存仕様通り)がいずれも修正前後で不変であることを別途確認。
  既に`state: stop`のところへ`stop`を再送する二重stopのケース(coreの
  `get_state() != STOPPED`ガードによりそもそもフラグが立たない)でも
  single/consumeのoneshotが誤って消費されないことを確認。mopidy.logに
  本パッチに起因する新規ERROR/Tracebackは無く、起動もクリーン。
- [x] `prio`/`prioid`で設定した優先度が、曲の再生が実際に始まった後も
  `playlistinfo`/`playlistid`にPrioフィールドとして残り続けてしまう不具合。
  TODO全項目消化済みのため自走エージェントが(general-purposeサブエージェント
  への調査委任を経て)新規発見・修正した項目(`mpdprioreset-patch.py`)。
  実MPD本体(gh rawで`src/queue/Playlist.cxx`の`playlist::SongStarted()`を
  直接取得し確認)は"reset a song's priority when playback starts"という
  コメントの通り、`queue.SetPriority(queue.OrderToPosition(current), 0, -1,
  false)`で再生開始した曲の優先度を無条件に0へリセットする。この
  `SongStarted()`は明示`play`/`playid`経由(`src/queue/PlaylistControl.cxx`
  `PlayOrder()`)と自然な曲送り経由(`src/queue/Playlist.cxx`
  `QueuedSongStarted()`)の両方から呼ばれる。mopidy_mpd側
  (`mpdprio-patch.py`が実装した`prio`/`prioid`)にはこのリセット処理が
  一切無く、一度設定した`_queue_priorities`(translator.py)のエントリは
  明示的に`prioid ID 0`等で0を再設定しない限り、曲が再生されようが
  `next`で通り過ぎようが永久に残り続けていた。
  修正: mopidy coreは明示play/自然送りの両方で一律
  `track_playback_started`イベント(`tl_track`引数付き、
  `mopidy/core/playback.py`の`_trigger_track_playback_started()`)を発火
  するため、`actor.py`の`on_event()`にこのイベント用の分岐を1つ追加し、
  既存の`translator.set_priority(tlid, 0)`(priority=0で呼ぶと
  `_queue_priorities`からpopする実装が`mpdprio-patch.py`で既に用意されて
  いる)をそのまま再利用するだけで実MPDの2経路を1箇所のフックでカバー
  できた。新しいロック/ストアは不要。
  verified: パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾(mpdoneshotstop-patch.pyの
  直後)に登録しビルド成功、dev mopidy(TCP 6601、mopidy-ytmusic実アカウント)
  を実際に起動しMPDプロトコルで直接テスト: `searchadd`で実トラックを積み
  `prioid 100 <ID>`→`playlistid <ID>`で`Prio: 100`を確認→`playid <ID>`で
  実際に再生開始(`status`の`songid`が対象IDと一致するまでポーリングして
  確認)→再度`playlistid <ID>`で`Prio:`行が消えていることを確認(修正前は
  残存し続けることも別途確認)。自然な曲送り経路も別途検証: まだ再生
  されていない次曲(pos 1)に`prioid 80`を設定→現在曲(pos 0)再生中は
  `Prio: 80`が維持されることを確認(まだ再生されていない曲の優先度を
  早期に消してしまわないことの確認)→`next`で自然に次曲へ進み実際に
  再生開始したことを`status`で確認→その時点で`Prio:`行が正しく消えて
  いることを確認。mopidy.logに本パッチに起因する新規ERROR/Tracebackは
  無く、起動もクリーン。
- [x] `previous`が`repeat "1"`(`random "0"`)の時、実MPD/mopidy_mpd自身の
  docstring実測テーブルでは前の曲(先頭ならラップして末尾)へ戻るべき
  ところ、常に現在曲を返すだけで戻らない不具合。`consume "1"`単体
  (repeat/random無効)でも同様に誤って現在曲を返してしまう。TODO全項目
  消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任を経て)新規発見・修正した項目(`mpdpreviousrepeat-patch.py`)。
  原因はmopidy_mpd自体ではなくmopidy core本体
  (`mopidy/core/tracklist.py`の`previous_track()`):
  `if self.get_repeat() or self.get_consume() or self.get_random(): return
  tl_track`というOR条件がrepeat/consume/randomのいずれか一つでもTrueなら
  無条件で現在曲を返してしまう。実MPD本体(gh rawで
  `src/queue/PlaylistControl.cxx playlist::PlayPrevious()`を直接取得し
  確認)はsingle/consumeを一切参照せず、`current > 0`なら単純に
  `order = current - 1`、`current == 0`かつ`queue.repeat`なら
  `order = queue.GetLength() - 1`(末尾へラップ)、それ以外(先頭かつ
  repeat無効)は`order = current`(現在曲を再スタート)。mopidy_mpd自身の
  `previous()`docstring(MPD 0.15.4での実測テーブル)も「repeat=T,
  random=.の全行はc=1,2,3→3,1,2(single/consume問わず)」「repeat=.,
  random=.の全行はc=1,2,3→1,1,2(single/consume問わず)」と明記しており、
  実装がこの自己文書化された仕様と食い違っていた。
  修正: `random`が無効な場合のみ、playback.pyの`previous()`ハンドラで
  上記アルゴリズムを`context.core.tracklist.get_tl_tracks()`/`index()`
  から直接計算し、`context.core.playback.play(tl_track)`で反映
  (mpdplayneg-patch.pyで確立済みのtracklist→play()パターンを踏襲)。
  `random`有効時(実測表でも repeat=T,random=T,consume=T の組み合わせは
  "Rand?"と曖昧で、シャッフル順序状態への依存が必要な複雑ケース)は
  既存の委譲(`context.core.playback.previous()`)のまま変更せず、次回
  以降の課題として残す。oneshot(single/consume)のrevert機構
  (`mark_pending_manual_track_change`)は分岐前と同じタイミングで
  呼び続けており、既存の`previous`由来のoneshot非revert挙動に影響なし。
  verified: パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾
  (mpdprioreset-patch.pyの直後)に登録しビルド成功、dev mopidy
  (TCP 6601、mopidy-ytmusic実アカウント、`searchadd album "THE BOOK"`で
  461曲の実キューを構築)を実際に起動しMPDプロトコルで直接テスト:
  (1) `repeat "1"`/`random "0"`で`play 1`→`previous`→`song: 0`
  (修正前は`song: 1`のまま無反応)、(2)同条件で`play 0`→`previous`→
  末尾(`song: 460`)へラップ(修正前は`song: 0`のまま)、(3)`consume "1"`
  単体(`repeat "0"`/`random "0"`)で`play 1`→`previous`→`song: 0`
  (修正前は`song: 1`のまま)をいずれも確認。回帰確認:
  `random "1"`時は`previous`後も`songid`が変化しないこと(既存の委譲
  挙動が変更されていないこと)、全フラグoffの通常`next`/`previous`
  (`play 5`→`next`→`song: 6`→`previous`→`song: 5`)がいずれも修正前後で
  不変であることを確認。mopidy.logに本パッチに起因する新規ERROR/
  Tracebackは無く、起動もクリーン。
- [x] `tagtypes all {余分な引数}` / `tagtypes clear {余分な引数}` が引数を
  無条件で無視し常にOKを返してしまう不具合(実MPDはACK Too many arguments
  を返すべき)。TODO全項目消化済みのため自走エージェントが(general-purpose
  サブエージェントへの調査委任を経て)新規発見・修正した項目
  (`mpdtagtypesargcheck-patch.py`)。
  最初の調査で提示された候補(`previous`の`random "1"`ケース)は別途検証し
  却下: mopidy core本体(`mopidy/core/tracklist.py`)の`_shuffled`は消費型の
  残りキュー(再生済みは`.remove()`され履歴を保持しない)であり、実MPDの
  `queue.order[]`(永続する順列配列)+`current`インデックスに相当する状態を
  持たない。忠実な再現にはMPDのシャッフル順序状態機械をmopidy_mpd側に
  独自実装する必要がありスコープが大きすぎる(このプロジェクトの既存
  ガイダンス「クロスカッティングな変更よりスコープの小さい候補を優先」に
  反する)ため、同じ調査エージェントへ差し戻して別候補を求めた。
  実MPD本体(gh rawでsrc/command/ClientCommands.cxx handle_tagtypes()を
  直接取得し確認)は"all"/"clear"の各分岐冒頭で`if (!request.empty())
  { r.Error(ACK_ERROR_ARG, "Too many arguments"); return
  CommandResult::ERROR; }`という引数チェックを持つ
  (`enable`/`disable`/`reset`はNAMEリストを取るためチェック対象外、
  `available`は実MPD自身にもチェックが無くmopidy_mpdも元々未チェックで
  対象外、これは仕様通り)。兄弟コマンドの`protocol`/`stringnormalization`
  (`mpdprotocol-patch.py`/`mpdstringnorm-patch.py`)は実MPD調査の上で
  all/clear/availableに同じチェックを実装済みだったが、`tagtypes`自体は
  `mpdtagtypesavailablereset-patch.py`がavailable/resetを追加した際にも
  このチェックが移植されず取り残されていた
  (`mopidy_mpd/protocol/connection.py`の`tagtypes()`、"all"/"clear"分岐)。
  修正: `all`/`clear`の各分岐冒頭に`if parameters: raise
  exceptions.MpdArgError("Too many arguments")`を追加(兄弟コマンドの
  既存実装と同じパターン)。
  verified: パッチ適用後の生成ソースは一時コピーに当てて`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。
  `nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾
  (mpdpreviousrepeat-patch.pyの直後)に登録しビルド成功、dev mopidy
  (TCP 6601、mopidy-ytmusic実アカウント)を実際に起動しMPDプロトコルで
  直接テスト: `tagtypes all garbage`→`ACK [2@0] {tagtypes} Too many
  arguments`(修正前はOK)、`tagtypes clear garbage`→同様にACK(修正前は
  OK)を確認。回帰確認: `tagtypes all`/`tagtypes clear`(引数無し)は
  引き続きOK、`tagtypes`(引数無し、一覧表示)/`tagtypes available
  garbage`(実MPD同様チェック無し、正常に一覧を返す)/`tagtypes enable
  Artist Album`→`tagtypes`で`Album`/`Artist`のみ返ることを確認、
  `tagtypes bogus`→`ACK Unknown sub command`は不変、`stringnormalization
  all garbage`/`protocol all garbage`は元から正しくACKすることも再確認。
  `status`/`list album`/`search any "yoasobi"`(実データ2件ヒット)/
  `count any "yoasobi"`/`getvol`/`listmounts`/`listpartitions`/`channels`
  の回帰なし・mopidy.logに新規ERROR/Traceback 0件・起動もクリーンである
  ことを確認。
- [x] 共有レンジパーサ`protocol.RANGE()`が旧MPDバージョンとの互換のため
  受理されるべき裸の(コロン無し)`"-1"`(「リスト全体」を意味する)を
  一切考慮せず`UINT("-1")`の`ValueError`で拒否し、`delete`/`move`/`shuffle`/
  `prio`/`listplaylist`/`listplaylistinfo`/`load`/`playlistdelete`/
  `playlistmove`全てで`"-1"`が`ACK incorrect arguments`になってしまう
  不具合を修正 (`mpdrangeminusone-patch.py`)。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。実MPD本体(gh rawで`src/protocol/ArgParser.cxx`
  `ParseCommandArgRange()`を確認)は`value == -1 && *test == '\0'`
  (コロンで続かない厳密な"-1"のみ)を"compatibility with older MPD
  versions: specifying '-1' makes MPD display the whole list"として
  `RangeArg::All()`(open-ended、`{0, UINT_MAX}`)で受理する。
  `playlistinfo`は元々`parameter == "-1"`を`RANGE()`呼び出し以前に
  自前で特別扱い済み(ncmpc/mpc由来、docstringにも明記)のため無変更。
  `move`/`playlistmove`は実MPDでは`FROM`がopen-ended(`"-1"`含む)だと
  `ACK Open-ended range not supported`で明示的に拒否されるが、
  mopidy_mpdの`move_range()`/`playlistmove()`はopen-ended(`"N:"`)自体を
  元々既に拒否せず受理する実装のため、本パッチはその既存ポリシーを
  変更せず`"-1"`を既存の`"0:"`と同じslice(0, None)へ正規化するのみ
  (新たな非対称は生まない)。BACKLOG.md全体を`RANGE(`/`"-1"`で検索し
  既存のmpdrangeempty-patch.py(start==stop空範囲緩和、別不具合)以外に
  未対応であることを確認済み。
  verified: TCP 6601、mopidy-ytmusic実アカウント。`searchadd artist
  "YOASOBI"`で15曲キュー構築後、`delete "-1"` → `OK`かつ
  `status`の`playlistlength`が15→0(修正前は`ACK [2@0] {delete} incorrect
  arguments`)。同様に`shuffle "-1"` → `OK`、`prio 50 "-1"` → `OK`で
  `playlistinfo`の全15曲に`Prio: 50`が付与されることを確認。回帰なしも
  確認: `delete "-1:5"`(コロン付き、対象外)/`delete "abc"`は従来通り
  ACK、`playlistinfo "-1"`(既存の自前特別扱い)は無変更で動作、通常の
  `delete 0`(単一インデックス)も正常動作。mopidy.logに新規ERROR/
  Traceback無し、起動もクリーン。
- [x] 現行キュー `move [{FROM}|{START:END}] {TO}`(current_playlist.py の
  `move_range()`)が `FROM` に開放端レンジ(`"N:"`、`mpdrangeminusone-patch.py`
  導入後は裸の `"-1"` も同様に `slice(0, None)` へ正規化される)を渡しても
  一切拒否せず、暗黙にキュー末尾までとして受理してしまう不具合を修正
  (`mpdmoveopenended-patch.py`)。TODO 全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。実MPD本体
  (gh rawで`src/command/QueueCommands.cxx` `handle_move()`を確認)はレンジを
  パースした直後、TO解決より前に `range.IsOpenEnded()` なら
  `ACK Open-ended range not supported` で明示的に拒否する(`delete`/`shuffle`
  は同ファイルの`handle_delete`/`handle_shuffle`が`RangeArg::All()`で
  open-endedを意図的に許容しており、`move`だけが拒否対象という非対称は実MPD
  自身の仕様通り)。兄弟コマンド`playlistmove`(stored_playlists.py)は
  `mpdplaylistrange-patch.py`で既にこの拒否を実装済みだったが、現行キューの
  `move`は`mpdrangeminusone-patch.py`自身が「本パッチはその既存ポリシーを
  変更せず…新たな非対称は生まない」と明記した通り意図的に据え置かれたまま
  残っていた。BACKLOG.md全体を`IsOpenEnded`/`Open-ended`/`move_range`で検索し
  playlistmove側の対応以外にこの現行キュー`move`の開放端拒否を実装した既存
  項目が無いことを確認済み。rmpc本体(mierak/rmpc)も確認したが
  `rmpc-mpd/src/single_or_range.rs`のSingleOrRangeは常に有界なrangeしか
  構築せずこの経路を現状踏まないため、rmpc実害の裏付けは取れなかった
  (実MPDとの明確なプロトコル非準拠という理由のみで着手)。
  修正: `move_range()`の`if end is None:`分岐を、従来の
  `end = context.core.tracklist.get_length().get()`(暗黙の末尾補完)から
  `raise exceptions.MpdArgError("Open-ended range not supported")`に変更
  (playlistmoveと同じエラーメッセージ)。パッチ適用後の生成ソースは一時
  コピーに`chmod u+w`して書き込み可にした上で`ast.parse`で構文確認、2回適用
  しても冪等(スキップ)であることも確認。
  verified: `nix/lib/mopidy-env.nix`のmpdPatchedリストの
  `mpdrangeminusone-patch.py`直後に登録しビルド成功、dev mopidy(TCP 6601、
  mopidy-ytmusic実アカウント)を実際に起動しMPDプロトコルで直接テスト:
  `searchadd artist "YOASOBI"`で15曲キュー構築後、`move "5:" "0"`(開放端)→
  `ACK [2@0] {move} Open-ended range not supported`(修正前はOKで暗黙に
  末尾までを受理していた)、`move "-1" "0"`(裸の"-1"、開放端と同義)→同様に
  `ACK [2@0] {move} Open-ended range not supported`。回帰確認: 有界レンジ
  `move "0:2" "5"`→OKで正しく並べ替え(playlistinfoのId順で確認)、単一
  インデックス`move "0" "3"`→OK、`moveid 1 0`(rangeを使わないmoveid)→OKで
  いずれも回帰なし。旧来の`status`/`tagtypes`/`search any "YOASOBI"`
  (実データ2件ヒット)/`count any "YOASOBI"`の回帰なし・mopidy.logに新規
  ERROR/Traceback 0件・起動もクリーンであることを確認。
- [x] `status`の`volume`フィールドがミキサー無し(`mixer.get_volume()`がNone)でも
  常に`volume: -1`を出力してしまう不具合を修正(`mpdstatusvolumeomit-patch.py`)。
  TODO全項目消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任を経て)新規発見。実MPD本体(gh rawで`src/command/PlayerCommands.cxx`
  `handle_status()`を確認)は`if (volume >= 0) r.Fmt("volume: {}\n", volume);`と、
  ミキサーが無い/取得できない場合はvolume行そのものを省略する。単独問い合わせ
  コマンドの`getvol`(`mpdgetvol-patch.py`、同じ`handle_getvol`も`volume >= 0`が
  条件)は既にこの仕様通りだが、`mpdgetvol-patch.py`自身のコメントは
  「statusコマンドの`volume: -1`フォールバックとは異なる仕様」としており、これは
  実MPD本体のソースを確認せずstatus側の既存動作をそのまま「別仕様」と誤って
  追認しただけだった。`mpdxfadezero-patch.py`がmixrampdelayと同じ
  `if 値 > 0: result.append(...)`パターンへ揃えたのと同種の「兄弟フィールド/
  兄弟コマンドとの条件付き出力の不揃い」。rmpc(`rmpc-mpd/src/commands/status.rs`)
  のvolumeは`Option<i8>`としてパースされ行が無ければNone扱いになる設計のため
  行を省略してもクライアント側への悪影響は無い。
  修正: `status.py`の`result`リストから`("volume", _status_volume(futures))`の
  無条件エントリを除去し、`xfade`と同じ位置に
  `volume = _status_volume(futures); if volume >= 0: result.append(("volume",
  volume))`を追加。パッチ適用後の生成ソースは一時コピーに`chmod u+w`して
  書き込み可にした上で`ast.parse`で構文確認、2回適用しても冪等(スキップ)で
  あることも確認。`nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾
  (`mpdmoveopenended-patch.py`の直後)に登録しビルド成功。
  verified: dev mopidy(TCP 6601、mopidy-ytmusic実アカウント)を実際に起動し
  MPDプロトコルで直接テスト。通常状態(ミキサー有り)で`status`→`volume: 100`、
  `getvol`→`volume: 100`(回帰無し)を確認後、`~/ai/mopidy-dev/mopidy-dev.conf`
  の`[audio]`セクションに一時的に`mixer = none`を追加してビルド・再起動、
  ミキサー無し状態で`status`→`volume:`行自体が無い応答(修正前は`volume: -1`)、
  `getvol`→空応答のみ(既存の正しい仕様、無変更)であることを確認。
  `setvol 50`→`ACK [52@0] {setvol} problems setting volume`(ミキサー無しでの
  既存挙動、無変更)、その後の`status`も引き続きvolume行無しで無事応答。
  `tagtypes`の回帰なしも確認。テスト後`mopidy-dev.conf`を元の内容
  (`mixer = none`行を除去)に復元してビルド・再起動し、`status`→
  `volume: 100`/`getvol`→`volume: 100`が元通り返ることを再確認(mopidy-dev.conf
  はdotfilesリポジトリ外のファイルのため恒久変更は残っていない)。
  mopidy.logに新規ERROR/Traceback 0件・起動もクリーンであることを両状態で確認。
- [x] 共有数値引数パーサ`protocol.UINT`/`INT`/`FLOAT`/`UFLOAT`/`FLOAT_ALLOW_NAN`
  (`mopidy_mpd/protocol/__init__.py`)が、実MPD本体の`strtoul()`/`strtol()`/
  `strtod()`(Cロケール、ASCII `0`-`9`限定、末尾に未消費文字が残れば全体を拒否)
  よりも遥かに緩く、全角数字等の非ASCII"digit"文字やPython
  3.6+の数値リテラル構文であるアンダースコア桁区切り(`"1_0"`→10)を無条件に
  受理してしまう不具合を修正(`mpdstrictnumparse-patch.py`)。TODO全項目消化済み
  のため自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。最初の候補(`add ""`が実MPD仕様通りライブラリ全体を追加すべきところ
  無条件no-opになっている不具合)は実MPDソース(gh raw `src/command/
  QueueCommands.cxx handle_add()`)で裏付けが取れたものの、mopidy_ytmusicの
  `browse()`がライブラリ全体の再帰追加を実際のYouTube Music APIへのライブ・
  再帰・無制限深さの呼び出しとして行うことになり、検証时に長時間ハング/実
  アカウントへの大量追加/レート制限抵触のリスクがあり「誤ったACKを返すだけ」
  という安全な失敗範囲に収まらないため却下(過去の権限モデル全体実装却下と
  同じ判断基準)。再調査で本項目へ着地。
  根本原因: `UINT()`の`value.isdigit()`はUnicode対応のため全角数字
  (`"１２３".isdigit()`→True、`int("１２３")`→123)やタイ数字等を通してしまい、
  `INT`/`FLOAT`/`UFLOAT`/`FLOAT_ALLOW_NAN`はisdigit()プレフィルタすら無く
  直接`int()`/`float()`を呼ぶため同じ穴がある上、Pythonの数値リテラルパーサは
  アンダースコア桁区切りも受理する(`int("1_0")`→10、`float("1_00.5")`→100.5、
  UINTだけは`"1_0".isdigit()`がFalseのため偶然この1件のみ通過しない)。
  実MPD本体(gh rawで`src/protocol/ArgParser.cxx`
  `ParseCommandArgUnsigned()`/`ParseCommandArgInt()`を確認)は
  `strtoul(s, &endptr, 10)`/`strtol(s, &test, 10)`が文字列全体を消費しきらない
  場合(`endptr == s || *endptr != 0`)は無条件に`ACK Integer expected`を返す。
  mopidy_mpdのトークナイザ(`mopidy_mpd/tokenize.py` `PARAM_RE`)は`"`/`'`以外の
  `ord >= 0x20`な文字を無条件にクォート無し引数として通すため、`setvol 1_0`や
  全角数字の生UTF-8バイト列もワイヤ上そのまま送信できる。
  BACKLOG.md全体を`isdigit`/`strtoul`/`strtol`/`protocol\.UINT`/`protocol\.INT`/
  `def UINT`/`def INT`で検索し、既存のヒットはUINT対RANGE/UINT対FLOATの意味論的
  な型不一致(setvolの範囲外値等、既にmpdsetvolrange-patch.pyで対応済み)のみで、
  パーサ自体の文字集合の緩さを扱った項目が無いことを確認済み。
  修正方針: 各パーサの`int()`/`float()`変換の直前に、strtol/strtod相当の
  ASCII限定書式(符号+ASCII数字のみ、アンダースコア無し)を要求する正規表現の
  事前検証を追加。FLOAT系は実`strtod`が`"inf"`/`"infinity"`/`"nan"`
  (大文字小文字問わず)を正当な入力としてパース自体は受理する仕様に合わせ、
  これらの特殊形を許容する分岐を正規表現に含めた(これらを最終的に拒否/許容
  するかは既存の`mpdfloatnonfinite-patch.py`/`mpdmixrampdelaynan-patch.py`が
  追加した後段の`math.isfinite()`/`isnan()`チェックの役目のままで無変更)。
  `RANGE()`は内部で`UINT()`を呼ぶ共有実装のため、`UINT()`の修正だけで
  `delete`/`move`/`shuffle`/`prio`等のレンジ引数にも自動的に波及する
  (`RANGE()`自体への変更は不要)。
  verified: `nix/lib/mopidy-env.nix`のmpdPatchedリスト末尾
  (`mpdstatusvolumeomit-patch.py`の直後)に登録しビルド成功。パッチ適用後の
  生成ソースは一時コピーに`chmod u+w`して書き込み可にした上で`ast.parse`で
  構文確認、2回適用しても冪等(スキップ)であることも確認。さらに環境の
  Python本体(`$ENV/bin/python3`、`sys.path`にパッチ適用済みコピーのみを追加)
  で`UINT`/`INT`/`FLOAT`/`UFLOAT`/`FLOAT_ALLOW_NAN`を直接呼び出し、正常値
  (`"40"`/`"-40"`/`"+40"`/`"5.5"`/`".5"`/`"5."`/`"1e10"`)は全て従来通り成功、
  `"1_0"`/`"１２"`(全角)/`"1_0.5"`/`"１２.５"`は全て`ValueError`(拒否)、
  `FLOAT_ALLOW_NAN`の`"nan"`/`"NaN"`は引き続き成功・`"inf"`は引き続き拒否
  であることを事前にオフラインで確認。
  dev mopidy(TCP 6601、mopidy-ytmusic実アカウント、ミキサー有り)を実際に
  起動しMPDプロトコルで直接テスト: `setvol 40`→OK→`setvol 1_0`→修正前はOKで
  volumeが10になっていたところ`ACK [2@0] {setvol} incorrect arguments`
  (`getvol`でvolumeが40のまま無変更なことも確認)、`setvol １２`(全角"12"の
  生UTF-8バイト)も同様に`ACK incorrect arguments`(修正前はOKでvolumeが12に
  なる)、`mixrampdb 1_0.5`/`crossfade 1_0`も同様にACK。回帰確認:
  `setvol 75`/`crossfade 5`/`mixrampdelay 2.5`/`mixrampdb -10.5`は全てOKで
  `status`に正しく反映、`mixrampdelay nan`(MixRamp無効化の正当な特殊値、
  mpdmixrampdelaynan-patch.pyの対象)は引き続きOKで受理され`status`から
  `mixrampdelay:`行が消えることを確認、`seekcur 0`(未再生時)は無関係の既存
  `ACK Not playing`のまま無変更、`tagtypes`も無変更。共有`RANGE()`経由の
  回帰も確認: `searchadd artist "YOASOBI"`(15曲実データ)後
  `delete "0:2"`→OKでplaylistlength 15→13、`delete "-1"`(裸の"-1"互換、
  mpdrangeminusone-patch.py対象)→OKでplaylistlength 13→0、いずれも正常動作。
  mopidy.logに新規ERROR/Traceback/Warning(pkg_resources由来を除く)0件、
  起動もクリーンであることを確認。
- [x] 共有数値引数パーサ`protocol.UINT()`(`mopidy_mpd/protocol/__init__.py`)に
  上限チェックが無く、tlid(SONGID)を受け取る`deleteid`/`playlistid`/`moveid`/
  `swapid`/`prioid`/`rangeid`/`addtagid`/`cleartagid`の計8コマンドで、桁数だけ
  正しい巨大な数字列(例: `"9999999999"`)を渡すと実MPDと異なるACKコードが
  返ってしまう不具合を修正(`mpduintmax-patch.py`)。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。
  実MPD本体(gh rawで`src/protocol/ArgParser.cxx`
  `ParseCommandArgUnsigned()`を確認)は`strtoul(s, &endptr, 10)`の後
  `value > max_value`(呼び出し側が省略した場合はunsigned最大値
  `std::numeric_limits<unsigned>::max()` == 4294967295)を即座に
  `ACK_ERROR_ARG`(コード2)`Number too large`として拒否する。
  `src/command/QueueCommands.cxx`の`handle_deleteid`/`handle_playlistid`/
  `handle_moveid`/`handle_swapid`/`handle_prioid`等はいずれも
  `args.ParseUnsigned(0)`としてこれを共通利用しており、SONGIDが実在するか
  どうかを見る前段でパースだけで弾かれる。
  一方mopidy_mpdの`UINT()`はPythonの任意精度`int()`をそのまま使うため上限が
  無く、パースは常に成功し、後段の「そのtlidがキューに存在するか」判定
  (`exceptions.MpdNoExistError("No such song")`, `ACK_ERROR_NO_EXIST`=50)へ
  フォールスルーしてしまう。つまり実MPDならACK 2(引数エラー)になるべき場面で
  mopidy_mpdはACK 50(存在しない)を返してしまい、ACKコード自体が非互換になる。
  `delete`/`move`/`shuffle`/`prio`等のPOSITION(RANGE)系コマンドは既存の境界
  チェック(`mpddeleteboundary-patch.py`/`mpdprioboundary-patch.py`)が
  `start > 実際の長さ`を先にACK 2として弾くため影響を受けない。
  BACKLOG.md全体を`4294967295`/`UINT32`/`ParseCommandArgUnsigned`/
  `Number too large`等で検索し、既存の`mpdsetvolrange-patch.py`/
  `mpdprioboundary-patch.py`/`mpdstrictnumparse-patch.py`はいずれも意味論的な
  範囲/クランプや文字集合の緩さを扱ったもので、`UINT()`自体に上限が無い点は
  未着手であることを確認済み。
  修正: `UINT()`の`int(value)`直後にunsigned最大値(`0xFFFFFFFF`)超過チェックを
  追加し、超過時は`ValueError("Number too large")`を送出。既存の
  `Commands.add()`ラッパーがValueErrorを`exceptions.MpdArgError`(ACK 2)へ
  変換する流儀により対応。共有`RANGE()`は`UINT()`を内部で呼ぶため自動的に
  波及するが、`delete`/`move`/`shuffle`/`prio`は既存の境界チェックが先に効く
  ため実害の無い変更に留まる。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで
  直接接続。`search any "YOASOBI"`→`addid "ytmusic:track:by4SYYWlhEs"`で実tlid
  (Id: 1)を用意後、`deleteid "9999999999"`/`playlistid "9999999999"`/
  `moveid "9999999999" "0"`/`swapid "9999999999" "1"`/
  `prioid "10" "9999999999"`/`rangeid "9999999999" "0:5"`/
  `addtagid "9999999999" "comment" "x"`/`cleartagid "9999999999"`の全8コマンド
  が修正前`ACK [50@0] No such song`から修正後`ACK [2@0] incorrect arguments`
  (ValueError経由でACKコード2、実MPDのNumber too largeと同じACKコード)へ
  変化することを確認。回帰確認: 実在するtlid(`playlistid "1"`)は正しい曲情報
  を返し、`deleteid "1"`で正常に削除、`status`/`tagtypes`も無変更で応答。
  mopidy.logに新規ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] `find`/`search`/`findadd`/`searchadd`/`list`/`playlistfind`/`playlistsearch`/
  `searchplaylist`/`sticker find`が共有する`window`修飾子パーサ
  `_mpd_parse_window()`(`mopidy_mpd/protocol/music_db.py`、
  mpdwindow-patch.pyで新設)が、コロンを含まない裸の数値(`window "5"`等)や
  裸の`"-1"`を一律`ACK Invalid window`で拒否してしまう不具合を修正
  (`mpdwindowbare-patch.py`)。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawで`src/protocol/ArgParser.cxx`
  `ParseCommandArgRange()`を確認。`window`引数自体も
  `src/command/DatabaseCommands.cxx`/`PlaylistCommands.cxx`双方で
  `args.ParseRange(...)`経由でこの同じ関数を呼ぶ)はコロン無しの裸の数値を
  `strtol()`でパースした後、文字列全体が厳密に`"-1"`の場合のみ「旧バージョン
  MPDとの互換性のため、"-1"はリスト全体を表示する」という特別分岐で
  `RangeArg::All()`(`slice(0, None)`相当)を、それ以外の非負の裸の数値は
  `RangeArg::Single(n)`(`slice(n, n+1)`、単一要素レンジ)を返す。
  mopidy_mpd側では同じreal MPD関数(`ParseCommandArgRange()`)を参照する
  兄弟パーサ`protocol.RANGE()`(`delete`/`move`/`shuffle`/`prio`等が使用)は
  既にこの2分岐を実装済み(裸の`"-1"`はmpdrangeminusone-patch.pyで追加、
  裸の数値->単一要素は元々の実装時点から正しい)なのに対し、`window`修飾子
  専用に後発で新設された`_mpd_parse_window()`だけはコロンの有無のみで
  必須/エラーと判定する実装のまま、この2分岐が一切移植されていなかった。
  mpdwindow-patch.py導入時の検証記録(「`window "5"`はACKになるのが正しい」
  という結論)はreal MPD本体のC++ソースを未確認のまま`window {START:END}`
  というプロトコル文書の書式表記だけを根拠にした誤った結論だったと判明。
  BACKLOG.md全体を`_mpd_parse_window`/`Invalid window`で検索し既存の言及は
  mpdwindow-patch.py導入時の(誤った)検証記録のみであることを確認済み。
  呼び出し元(`mpdfindaddpos-patch.py`/`mpdlistwindow-patch.py`/
  `mpdplaylistfindsortprio-patch.py`/`mpdsearchplaylist-patch.py`/
  `mpdstickerfind-patch.py`)はいずれもこの共有関数をimportして呼ぶだけで
  本体を編集していないことも確認済み(登録順は影響を受けない)。
  修正: `_mpd_parse_window()`の先頭に裸の`"-1"`(`slice(0, None)`)/コロン
  無し非負整数(`slice(n, n+1)`)の2分岐を追加。コロンを含む既存の
  `START:END`/`START:`構文は無変更。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで
  直接接続。`clear`後`findadd "(any contains \"yoasobi\")" window "0"`が
  修正前`ACK [2@0] {findadd} Invalid window: 0`、修正後は`playlistinfo`で
  ちょうど1件(単一要素レンジ)が追加されることを確認。`window "-1"`は
  同条件の無window時と同じ全2件(実データ、旧互換でリスト全体)、
  `window "0:2"`(既存のコロン構文)も全2件で回帰なし。`window "abc"`/
  `window "-2"`/`window "5:2"`は修正前後とも変わらずACK(異常値は従来通り
  拒否)。`list album window "0"`も正常応答(OK)。mopidy.logに新規
  ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] `find`/`search`/`findadd`/`searchadd`/`list`/`playlistfind`/`playlistsearch`/
  `searchplaylist`/`sticker find`が共有する`window`修飾子パーサ
  `_mpd_parse_window()`(`mopidy_mpd/protocol/music_db.py`)が数値部分の妥当性
  チェックにPythonの`str.isdigit()`+素の`int()`を使っており、実MPDの共有
  パーサが持つ2つの検証軸(ASCII数字限定・UINT32上限チェック)の両方を
  欠いている不具合を修正(`mpdwindowstrict-patch.py`)。TODO全項目消化済み
  のため自走エージェントが(general-purposeサブエージェントへの調査委任を
  経て)新規発見。
  `str.isdigit()`はUnicode対応のため全角数字等も真になる
  (`"５".isdigit()` -> True, `int("５")` -> 5)。よって`window "５"`
  (全角5)が現状`slice(5, 6)`として黙って受理されてしまう。また`int()`は
  任意精度のため上限が無く、`window "99999999999999999999"`のような
  桁数だけ正しい巨大な数値もパースに成功し`slice()`を構築してしまう。
  実MPD本体(gh rawで`src/protocol/ArgParser.cxx`の
  `ParseCommandArgRange()`を確認)は各数値要素を`strtol(s, &test, 10)`で
  パースし、`test == s`(数字として1文字も消費できない=全角数字などは
  ASCII基準で非数値)または末尾に余分な文字が残る場合は
  `ACK Integer or range expected`を返し、さらに
  `value > std::numeric_limits<int>::max()`の場合は`ACK Number too large`
  を返す。
  mopidy_mpd側では全く同じreal MPD関数(`ParseCommandArgRange`)を参照する
  兄弟パーサ`protocol.RANGE()`(protocol/__init__.py、
  `delete`/`move`/`shuffle`/`prio`等が使用)は、この2つの検証軸を既に
  `UINT()`(mpdstrictnumparse-patch.pyがASCII限定正規表現
  `_MPD_STRICT_UINT_RE`を、mpduintmax-patch.pyが上限`_MPD_UINT_MAX`
  =0xFFFFFFFFチェックを追加済み)への委譲によって両方とも実装している。
  しかし`window`修飾子専用の`_mpd_parse_window()`(mpdwindow-patch.py新設、
  mpdwindowbare-patch.pyがコロン無し裸数値/裸"-1"分岐を追加)だけは独自に
  `str.isdigit()`+`int()`を直書きしており、`RANGE()`経由の`UINT()`が持つ
  この2つの保護のどちらも受けていなかった。
  BACKLOG.md全体を`_mpd_parse_window`/`isdigit`/`UINT`で検索し、window
  修飾子について全角数字/上限超過の観点は既存項目に無いことを確認済み。
  呼び出し元(`find`/`search`/`list`/`playlistfind`/`playlistsearch`/
  `searchplaylist`/`sticker find`/`findadd`/`searchadd`)はいずれもこの
  共有関数をimportして呼ぶだけで本体を編集するpatchはmpdwindow-patch.py/
  mpdwindowbare-patch.py以外に無い(`grep -l "_mpd_parse_window" *.py`で
  確認済み)。
  修正: `_mpd_parse_window()`の数値パース部分を素の`str.isdigit()`/`int()`
  から`protocol.UINT()`呼び出し(ValueError捕捉 -> 既存の
  `MpdArgError(f"Invalid window: {value}")`へ変換)へ置き換え、`RANGE()`
  と同じASCII限定・上限チェックを共有させる。裸の`"-1"`特別分岐(文字列
  完全一致)は数値パースを経由しないため無変更。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケット
  で直接接続。`clear`後`findadd "(any contains \"yoasobi\")"`で2件の実
  トラックを投入。`find "(any contains \"yoasobi\")" window "５"`(全角5)
  が修正前は`slice(5,6)`として黙って受理されていたところ修正後
  `ACK [2@0] {find} Invalid window: ５`に変化することを確認。
  `window "99999999999999999999"`(UINT32上限超過)も同様に修正後
  `ACK [2@0] {find} Invalid window: ...`に変化することを確認(修正前は
  黙って受理)。回帰確認: `window "0"`(コロン無し裸数値、単一要素レンジ)
  は引き続き正常応答、`window "-1"`(裸の互換全体表示)は無window時と同じ
  全3件(album placeholder含む)、`window "0:2"`(既存のコロン構文)も
  全2件で回帰なし、`window "abc"`(不正値)は修正前後とも変わらずACK。
  mopidy.logに新規ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] 共有レンジパーサ`protocol.RANGE()`(`mopidy_mpd/protocol/__init__.py`)
  と兄弟の`_mpd_parse_window()`(`mopidy_mpd/protocol/music_db.py`)が、
  コロンの後ろが完全な空文字列ではなく空白文字だけの場合(例:`"5: "`)を
  実MPDが拒否すべきところ黙ってopen-endedレンジとして受理してしまう
  不具合を修正(`mpdwindowwhitespace-patch.py`)。TODO全項目消化済みの
  ため自走エージェントが(general-purposeサブエージェントへの調査委任を
  経て)新規発見。
  実MPD本体(gh rawで`src/protocol/ArgParser.cxx`の
  `ParseCommandArgRange()`を確認)は`strtol(++test, &test2, 10)`の後
  `*test2 != '\0'`ならACK Integer or range expectedを返し、
  `test == test2`(=open-ended)の判定はその後に来る。`strtol()`は数値を
  1文字も読めなかった場合`endptr`に変換開始前の元のポインタを入れる
  仕様(libc `strtol`を`ctypes`経由で実測して確認: 入力`" "`に対し
  `endptr`はコロン直後の位置のまま、`*endptr == ' '`)のため、コロン直後
  が空白のみの`"5: "`は`test2`がその空白位置を指したまま
  `*test2 != '\0'`が真になり、open-ended判定に到達する前に拒否される。
  open-endedになるのはコロン直後が真に何も無い`"5:"`のみ。
  mopidy_mpd側は`RANGE()`が`if stop.strip():`、`_mpd_parse_window()`が
  `end_s = end_s.strip(); if end_s:`という形でコロン後の文字列を先に
  `.strip()`してからtruthy判定しており、`"5: "`は`.strip()`後に
  空文字列になってどちらも黙ってopen-endedへ倒れてしまっていた。
  BACKLOG.md全体を`stop.strip`/`end_s.strip`/`whitespace-only`/
  `空白のみ`/`trailing whitespace`/`Integer or range expected`/
  `window "5: "`で検索し、この空白のみ残余ケースは既存項目
  (mpdstrictnumparse-patch.py=全角数字等の非ASCII文字、
  mpduintmax-patch.py=UINT32上限超過)とは別軸の不具合で既存項目に
  含まれないことを確認済み。
  修正: 両関数ともコロン後の残り文字列を`.strip()`した後の値で
  truthy判定するのをやめ、strip前の元の文字列そのもので判定するように
  変更(`if stop:`/`if end_s:`、strip呼び出し自体を削除)。非空だが
  空白のみの残余はstrip前の値のまま後段の`UINT()`へ渡り、ASCII限定
  正規表現(mpdstrictnumparse-patch.py)が空白を拒否することで正しく
  ACKになる。真に空の`"5:"`はstrip前後で変わらず空文字列のままなので
  既存のopen-ended/単一要素挙動に回帰は無い。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケット
  で直接接続。`playlistinfo "5: "`(コロン後に半角スペース1文字)が
  修正前`OK`(open-endedとして誤受理)、修正後
  `ACK [2@0] {playlistinfo} incorrect arguments`に変化することを確認
  (queue空/2曲populated両方の状態で再現)。
  `findadd "(any contains \"yoasobi\")" window "0: "`も同様に修正後
  `ACK [2@0] {findadd} Invalid window: 0: `に変化することを確認(修正前は
  黙って受理)。回帰確認: `playlistinfo "5:"`(真に空、open-ended、
  populated queueで2曲全件返却)/`playlistinfo "1:3"`(通常の閉区間)は
  修正前後とも変わらずOK、`window "0:2"`(既存のコロン構文)/
  `window "0"`(裸の単一要素)/`window "-1"`(裸の互換全体表示)は
  いずれも修正前後とも変わらずOKで回帰なし、`playlistinfo "5:3"`
  (start>stopの不正値)も修正前後とも変わらずACK。mopidy.logに新規
  ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] find/search/findadd/searchadd/searchaddpl/playlistfind/playlistsearchが
  共有する`sort TYPE`修飾子(`music_db.py`の`_SORT_MAPPING`)が擬似sortタイプ
  "Last-Modified"は認識するのに常に対で存在するはずの"Added"だけ未登録で、
  `sort Added`/`sort -Added`が即座に`ACK Unknown sort type: Added`になる
  不具合を修正(`mpdsortadded-patch.py`)。TODO全項目消化済みのため自走
  エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。
  実MPD本体(gh rawで`src/command/DatabaseCommands.cxx ParseSortTag()`を
  確認)は
  ```
  if (StringIsEqualIgnoreCase(s, "Last-Modified"))
      return TagType(SORT_TAG_LAST_MODIFIED);
  if (StringIsEqualIgnoreCase(s, "Added"))
      return TagType(SORT_TAG_ADDED);
  ```
  という隣接する2分岐でLast-Modified/Addedを常に有効な擬似sortタイプとして
  対で登録しており(`src/song/Filter.hxx`でも`SORT_TAG_LAST_MODIFIED`/
  `SORT_TAG_ADDED`は隣接する定数)、`src/command/QueueCommands.cxx`
  (playlistfind/playlistsearch用パーサ)にも同一の対が存在する。
  mopidy_mpd側は`_SORT_MAPPING`に"last-modified"のみ登録済みで"added"が
  丸ごと抜けていた。既存の`mpdadded-patch.py`はキュー内tlidの`Added:`
  タグ「表示」(MPD0.24+)を実装したもので本項目(sort修飾子)とは無関係。
  BACKLOG.md全体を`SORT_TAG_ADDED`/`sort Added`/`"added"`(sort文脈)で
  検索し既存項目に含まれないことを確認済み。
  修正: `_SORT_MAPPING`に`"added": "added"`を追加するだけ(track_no/disc_no
  等と同様の恒等マッピング)。`mopidy.models.Track`にはadded属性が無いため
  既存の`_mpd_sort_value()`汎用フォールバック(`getattr(track, field, None)
  or ""`)がfield=="added"に対して常に""を返し、安定ソートの無変化(no-op)
  となる。これは実MPD自身がTitleSort/ComposerSort(`Tag.cxx DecaySort()`に
  フォールバック定義が無く「値が無ければ空扱い」)に対して取る挙動と同じ
  クラスの安全な振る舞いであり、新規のデータ捏造は不要。
  `current_playlist.py`の`_PF_SORT_MAPPING = dict(_SORT_MAPPING)`
  (`mpdplaylistfindsortprio-patch.py`)は`music_db.py`のこの辞書をそのまま
  複製するため、この1箇所の修正でplaylistfind/playlistsearchにも自動的に
  波及する。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケット
  で直接接続。`search any "yoasobi" sort Added`/`sort -Added`が修正前
  `ACK [2@0] {search} Unknown sort type: Added`、修正後2件の実トラック+
  1件のalbum placeholderを含む`OK`応答に変化することを確認。`clear`+
  `findadd "(any contains \"yoasobi\")"`後の`playlistfind ... sort Added`
  も同様に修正後`OK`(修正前ACK)に変化することを確認。回帰確認:
  `sort Last-Modified`/`sort ArtistSort`/`sort -Track`は修正前後とも同一の
  応答順序で回帰なし(元々3件のみで安定ソートのため順序不変)、
  `sort Bogus`(未知のsortタイプ)/`playlistfind ... sort Bogus`は修正後も
  変わらず`ACK Unknown sort type`。mopidy.logに新規ERROR/Traceback 0件、
  起動もクリーンであることを確認。
- [x] `sticker set {TYPE} {URI} {NAME} {VALUE}` が NAME 空文字列を検証せず無条件で
  OK を返し sticker.db に name="" の壊れた行を永続化してしまう不具合を修正
  (`mpdstickersetnameguard-patch.py`)。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawで`src/command/StickerCommands.cxx`の`handle_sticker()`を確認)は
  set/inc/decの3コマンドとも同一の`if (StringIsEmpty(sticker_name)) { r.FmtError(
  ACK_ERROR_ARG, "empty sticker name"); ... }`ガードを持つ(get/delete/find には
  この検証は無く、これは実MPD側の意図的な非対称)。mopidy_mpd側では
  mpdstickernames-patch.pyがMPD 0.24の`inc`/`dec`(`_mpd_sticker_inc_dec()`)を
  新規追加した際に`if not name: raise exceptions.MpdArgError("empty sticker name")`
  を移植したが、`set`(`_mpd_sticker_set()`、mpdsticker-patch.py由来のより古い実装)
  には同じチェックが一度も移植されず取り残されていた。
  BACKLOG.md全体を`empty sticker name`/`sticker set`で検索し、inc/dec側の空名
  チェック導入時の記述(mpdstickernames-patch.py)とinc/decの桁上限
  (mpdstickerincoverflow-patch.py)のみがヒットし、set側の空文字列チェック欠落への
  言及は既存項目に存在しないことを確認済み。
  修正: `_mpd_sticker_inc_dec()`と同一文言のガードを`_mpd_sticker_set()`の先頭に追加。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで直接接続。
  `search any "YOASOBI"`で得た実track URI(`ytmusic:track:by4SYYWlhEs`)に対し
  `sticker set song "<uri>" "" "5"`が修正前`OK`(直後の`sticker list song "<uri>"`に
  `sticker: =5`という壊れた行が出現)、修正後`ACK [2@0] {sticker} empty sticker name`
  になることを確認。回帰確認: `sticker set song "<uri>" "rating" "5"`(通常名)は
  引き続き`OK`で`sticker get song "<uri>" "rating"`が正しく`rating=5`を返す、
  `sticker inc song "<uri>" "" "1"`(既存の空名チェック)は修正前後とも変わらず
  同じACKを返す。`status`/`tagtypes`も無変更で応答。mopidy.logに新規
  ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] `next`/`previous` が完全停止中(`state: stop`)でも一切確認せず無条件で
  `context.core.playback.next()`/`previous()` を呼んでしまい、実MPDならACKで
  拒否すべき操作をサイレントに実行しキューの現在位置ポインタ(`song`/`songid`)
  まで実際に動かしてしまう不具合を修正 (`mpdnextprevstopguard-patch.py`)。TODO
  全項目消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任を経て)新規発見。
  実MPD本体(gh rawで`src/queue/PlaylistControl.cxx`の`playlist::PlayNext()`/
  `playlist::PlayPrevious()`を確認)はどちらも先頭で
  `if (!playing) throw PlaylistError::NotPlaying();`
  を無条件で行う。`playing`はSTOPPEDでは常にfalseで、`PlaylistResult::NOT_PLAYING`
  は`src/command/CommandError.cxx`の`ToAck()`で`ACK_ERROR_PLAYER_SYNC`(55、
  メッセージ"Not playing"固定)に写像される。これは`seekcur`
  (`mpdseekcurstop-patch.py`)が`playlist::SeekCurrent()`の同じ`!playing`ガードに
  対して既に実装済みのパターンと全く同一の非対称性が`next`/`previous`にも残って
  いたもの(`mpdoneshotmanualskip-patch.py`/`mpdoneshotmanualskipguard-patch.py`/
  `mpdpreviousrepeat-patch.py`はnext/previousのoneshot revert挙動や曲送り
  アルゴリズム自体は精査済みだが、そもそも停止中に呼べてしまうこと自体は
  未対応のまま残っていた)。BACKLOG.md全体を`PlayNext`/`PlayPrevious`/`NotPlaying`/
  `Not playing`/`PLAYER_SYNC`で検索し、`mpdoneshotmanualskip-patch.py`自身が
  「実MPD自体もこの状態でのnextはPlaylistError::NotPlaying()で本来ACKすべき
  ところmopidy_mpdは元々無反応で許容しており…今回は対応範囲外として次回以降への
  申し送りとする」と明記していた残存課題そのものであることを確認済み。
  実害: `stop`後(一度でも再生した曲があれば`get_current_tl_track()`は非Noneの
  まま残り続ける、`mpdseekcurstop-patch.py`参照)に`next`を送ると実MPDなら
  `ACK [55@0] {next} Not playing`になるところ、mopidy-mpdは`OK`を返した上で
  `status`の`song`/`songid`が実際に次の曲へ進んでしまう(`state`は`stop`のまま)。
  修正: `seekcur`(`mpdseekcurstop-patch.py`)が既に定義済みの
  `_MpdSeekCurPlayerSyncError`(同一モジュール内、`error_code =
  ACK_ERROR_PLAYER_SYNC`)をそのまま再利用し(Pythonのモジュールレベル関数は
  呼び出し時点で解決されるため定義順は無関係)、`next_()`/`previous()`の先頭に
  `get_state() == PlaybackState.STOPPED`ガードを追加。`stop`自体
  (`mpdoneshotstop-patch.py`)やSTOPPED以外(PLAY/PAUSE)での既存のoneshot revert
  挙動・`previous()`のrepeat/consumeアルゴリズム(`mpdpreviousrepeat-patch.py`)は
  無変更。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで
  直接接続。`clear`+`findadd "(any contains \"yoasobi\")"`(2曲)+`play "0"`で
  `state: play`/`song: 0`/`songid: 1`確認後`stop`し`status`が`state: stop`/
  `song: 0`のところへ`next`を送ると、修正前は`OK`を返し直後の`status`が
  `state: stop`のまま`song: 1`/`songid: 2`へサイレントに進行、修正後は
  `ACK [55@0] {next} Not playing`になり`song`/`songid`が不変であることを確認。
  `previous`も同様に修正後`ACK [55@0] {previous} Not playing`になることを確認。
  回帰確認: 再生中(`state: play`)の`next`/`previous`は修正前後とも変わらず`OK`で
  実際に曲が切り替わる、一時停止中(`state: pause`、実MPDの`playing`はPLAY/PAUSE
  両方を含む)の`next`も修正前後とも変わらず`OK`(ACKに巻き込まれない)ことを
  確認。mopidy.logに新規ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] `sticker get/set/delete/list/inc/dec song {URI}` が、存在しない曲URIに対して
  ACK_ERROR_ARG(2)を返していたが実MPDと異なるACKコードだった不具合を修正
  (`mpdstickersongnoexist-patch.py`)。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  `mpdstickersongvalidate-patch.py`自身のコメントは「`SongHandler::ValidateUri()`は
  `database.GetSong(uri)`で`std::invalid_argument`(ACK 2)を送出しplaylistドメインと
  揃える」としていたが、これは実MPD本体のソースの誤読だった。実際には(gh rawで
  `src/db/plugins/simple/SimpleDatabasePlugin.cxx`の`GetSong()`を確認)存在しない
  URIに対しGetSong()が送出するのは`throw DatabaseError(DatabaseErrorCode::NOT_FOUND,
  "No such song")`であり、`src/command/CommandError.cxx`の`ToAck(DatabaseErrorCode)`
  はNOT_FOUNDを`ACK_ERROR_NO_EXIST`(50)に写像する(CONFLICTのみACK_ERROR_ARG)。
  playlistドメイン(`PlaylistHandler::ValidateUri`、`ListPlaylistFiles()`ベースの
  実装)は実際に`std::invalid_argument`(→ACK 2)を送出するため、songとplaylistは
  実MPDでは異なるACKコードを返す非対称仕様であり、`mpdstickersongvalidate-patch.py`
  が両方をACK 2に揃えたのは誤りだった。mopidy_mpd内の他の「存在しない曲」判定
  (`mpdaddid-patch.py`/`mpdmoveto-patch.py`/`mpdprio-patch.py`/`mpdrangeid-patch.py`
  等多数)は一貫して`exceptions.MpdNoExistError("No such song")`(ACK 50)を使って
  おり、stickers.pyのsong分岐だけがこの規約から外れていた。
  BACKLOG.md全体を`no such song`/`ACK_ERROR_ARG`/`MpdNoExistError`/`sticker`で検索し、
  song分岐のACKコード自体を疑う既存記述が無いことを確認済み。
  修正: `_mpd_sticker_validate_uri()`のsong分岐のみ、送出する例外を
  `exceptions.MpdArgError`から`exceptions.MpdNoExistError`へ変更(playlist分岐は
  実MPD準拠のため無変更)。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで直接
  接続。存在しないURI`ytmusic:track:doesnotexist000000`への`sticker set/get/delete/
  list/inc song "<uri>" ...`がいずれも修正前`ACK [2@0] {sticker} no such song: ...`、
  修正後`ACK [50@0] {sticker} no such song: ...`になることを確認。回帰確認:
  `sticker set playlist "NonexistentPlaylist12345XYZ" rating "5"`(存在しない
  playlist名)は修正前後とも変わらず`ACK [2@0] {sticker} no such playlist: ...`、
  `search any "yoasobi"`で得た実track URIに対する`sticker set/get/delete song`は
  修正前後とも変わらず正常動作(`OK`/`sticker: rating=9`)することを確認。
  mopidy.logに新規ERROR/Traceback 0件(bogus URIへの`library.lookup()`起因の
  `KeyError: 'videoDetails'`は`mpdstickersongvalidate-patch.py`自身の検証記録
  でも既知の既存ノイズであり回帰ではないことを確認済み)、起動もクリーンで
  あることを確認。
- [x] `add`/`addid`/`move`/`moveid`/`findadd`/`searchadd`/`load` が共有する
  POSITION/TOパーサ(`_mpd_add_position`/`_mpd_addid_position`/`_mpd_move_to`
  (current_playlist.py)、`_mpd_parse_addpos_position`(music_db.py)、
  `_mpd_load_position`(stored_playlists.py))が数値部分の妥当性チェックに
  Pythonの`str.isdigit()`+素の`int()`を直書きしており、実MPDの共有パーサが
  持つ2つの検証軸(ASCII数字限定・UINT32上限チェック)の両方を欠いて全角数字や
  巨大数値を絶対/相対位置として黙って受理してしまう不具合を修正
  (`mpdpositionstrict-patch.py`)。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  `str.isdigit()`はUnicode対応のため全角数字等も真になる(例:
  `"０".isdigit()`->True、`int("０")`->0)。よって`add URI "０"`(全角0)や
  `moveid ID "１"`(全角1)が絶対位置として黙って受理・実行されてしまう。また
  Pythonの`int()`は任意精度のため上限が無く、桁数だけ正しい巨大な数値も
  パースに成功してしまう。
  実MPD本体(gh rawでsrc/protocol/ArgParser.cxxのParseCommandArgUnsigned()、
  src/command/PositionArg.cxxのParseInsertPosition()/ParseMoveDestination()が
  数値部分をこれ経由でパースすることを確認)は`strtoul(s, &endptr, 10)`を使い、
  `endptr == s`(1文字も数字として消費できない=全角数字等はASCII基準で非数値)
  または末尾に余分な文字が残る場合ACK Integer expectedを、
  `value > max_value`の場合ACK Number too largeを返す。
  兄弟パーサ`protocol.UINT()`は既にこの2軸を`_MPD_STRICT_UINT_RE`
  (mpdstrictnumparse-patch.py)と`_MPD_UINT_MAX`=0xFFFFFFFFチェック
  (mpduintmax-patch.py)への統合で実装済みであり、兄弟の`_mpd_parse_window()`
  (music_db.py)も同じ理由からUINT()への委譲へ既に修正済み
  (mpdwindowstrict-patch.py)。しかし本項目が対象とする5つのPOSITION/TOパーサ
  だけは独自に`str.isdigit()`/`int()`を直書きしたままで、`UINT()`が持つこの
  2つの保護のどちらも受けていなかった。
  BACKLOG.md全体を`_mpd_add_position`/`_mpd_addid_position`/`_mpd_move_to`/
  `_mpd_parse_addpos_position`/`_mpd_load_position`/`isdigit`で検索し、これら
  5関数自体の数値検証について既存項目が無いことを確認済み
  (`mpdaddposrace-patch.py`はTOCTOUレースの修正であり、これら関数の数値パース
  本体には触れていない)。
  修正: 5関数それぞれの数値パース部分を`protocol.UINT()`呼び出しへ置き換え。
  current_playlist.py/stored_playlists.pyの3関数は`protocol.commands.add()`の
  validatorとして使われており、送出したValueErrorは共通フレームワーク側
  (`protocol/__init__.py`)で自動的に`MpdArgError("incorrect arguments")`へ
  変換されるため、そのまま`protocol.UINT()`の結果を返すだけでよい。
  music_db.pyの`_mpd_parse_addpos_position`はvalidator経由ではなく直接呼び
  出されるため、ValueErrorを明示的に捕捉し既存の
  `MpdArgError("incorrect arguments")`へ変換する処理を残した。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで
  直接接続。`clear`+`add "ytmusic:track:..."`後、`add "ytmusic:track:..."
  "０"`(全角0)が修正前`OK`(実際にposition 0へ挿入、`playlistinfo`で確認)、
  修正後`ACK [2@0] {add} incorrect arguments`に変化することを確認。同様に
  `moveid "N" "１"`(全角1)が修正前`OK`(実際にposition 1へ移動)、修正後
  `ACK [2@0] {moveid} incorrect arguments`に変化。`findadd "(any contains
  \"YOASOBI\")" position "２"`(全角2)、`load "NAME" "0:1" "２"`も同様に修正前
  OK、修正後ACKへ変化することを確認。巨大数値(`"99999999999999999999"`)も
  `add`で同様にACKへ変化することを確認。回帰確認: 半角の絶対位置(`"0"`/`"1"`/
  `"2"`)、相対位置(`"+0"`、再生中の曲が無い場合は既存通り
  `ACK [55@0] {add} No current song`)は5コマンド全てで修正前後とも変わらず
  正常動作、`searchadd artist "YOASOBI"`(position指定無し)も無変更。
  mopidy.logに新規ERROR/Traceback 0件(playlist save時のytmusicアカウント
  401エラーはmopidy_ytmusicのplaylist作成が非対応な既存の環境固有事象であり
  本パッチと無関係であることを確認済み)、起動もクリーンであることを確認。
- [x] `searchaddpl {NAME} {FILTER} [sort {TYPE}] [window {START:END}]
  [position {POS}]` のPOSITION引数が、直前項目(`mpdpositionstrict-patch.py`)の
  修正対象5関数に含まれず、`searchaddpl()`本体にインラインで書かれた
  `str.isdigit()`+素の`int()`のまま取り残されていた不具合を修正
  (`mpdsearchaddplposstrict-patch.py`)。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  `mpdpositionstrict-patch.py`は名前付き関数5つ(`_mpd_add_position`/
  `_mpd_addid_position`/`_mpd_move_to`(current_playlist.py)、
  `_mpd_parse_addpos_position`(music_db.py、findadd/searchadd用)、
  `_mpd_load_position`(stored_playlists.py))を対象に一括修正したが、
  searchaddplのPOSITION処理は`mpdsearchaddplpos-patch.py`が`searchaddpl()`の
  関数本体を丸ごと書き換えた際にインラインで追加されたコードであり、名前付き
  関数の一覧には含まれず対象外のまま残っていた。実機のビルド済みソースを
  `grep isdigit`した結果、この1箇所のみが残存していることを確認済み。
  実MPD本体(gh rawでsrc/command/DatabaseCommands.cxxのhandle_searchaddpl()を
  確認)はPOSITIONを`ParseQueuePosition(args, UINT_MAX)`経由でパースしており、
  これは他のposition/window/UINT系コマンドと全く同じ`ParseCommandArgUnsigned()`
  (`strtoul`ベースの共有厳密パーサ)に委譲している。mopidy_mpd側で同じreal MPD
  関数を参照する兄弟パーサ`protocol.UINT()`は既にASCII数字限定・UINT32上限
  チェックの両方を実装済み(mpdstrictnumparse-patch.py/mpduintmax-patch.py)。
  BACKLOG.md全体を`searchaddpl`/`isdigit`で検索し、position引数の全角数字/
  UINT32上限超過についての既存項目が無いことを確認済み(既存項目は`"abc"`の
  ような非数値や`"999"`のような範囲外の絶対値についてのみ検証済み)。
  修正: `searchaddpl()`内の`_position_value.isdigit()`+`int()`を
  `protocol.UINT()`呼び出しへ置換し、`ValueError`を既存の
  `MpdArgError("incorrect arguments")`へ変換する処理を追加。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで
  直接接続。`searchaddpl "PosTestList" "(Artist == \"YOASOBI\")" position
  "０"`(全角0)が修正前`OK`(実際にposition 0へ挿入)、修正後
  `ACK [2@0] {searchaddpl} incorrect arguments`に変化することを確認。
  `position "99999999999999999999"`(巨大数値)も同様にACKへ変化。回帰確認:
  半角の絶対位置(`"0"`、実際に挿入されplaylistが作成されることを確認)、
  position修飾子省略(末尾に正常追加)、既存の範囲外エラー
  (`position "999999"`→`ACK [2@0] {searchaddpl} Bad position`、無変更)は
  修正前後とも変わらず正常動作。mopidy.logに新規ERROR/Traceback 0件、起動も
  クリーンであることを確認。適用前にビルド済みソースを`/tmp`へ隔離コピーし
  パッチを当ててから`ast.parse()`で構文確認、2回連続適用でも冪等
  (2回目は"already applied, skip")であることを確認済み。

- [x] `sticker`コマンドのURI実在検証(`_mpd_sticker_validate_uri()`)が、action名
  や各actionごとの引数個数が正しいかのチェックより先に無条件で走ってしまい、
  「actionが未知語、または既知actionだが引数個数が違う」という壊れたコマンドに
  対して、本来返すべき引数エラー(ACK_ERROR_ARG=2)より先にURI不在エラー
  (ACK_ERROR_NO_EXIST=50)が出てしまう不具合を修正。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawでsrc/command/StickerCommands.cxx handle_sticker()を確認)は
  `args.size() == N && StringIsEqual(cmd, "get")`のようにコマンド名と引数個数が
  完全一致した分岐内でのみ`handler->Get/Set/Inc/Dec/Delete/List()`
  (=DomainHandler::ValidateUri()、URI検証の発生源)を呼び出し、どの分岐にも
  一致しない場合は`r.Error(ACK_ERROR_ARG, "bad request")`に落ちてURI検証は
  一切行われない。mopidy_mpd側の`sticker()`(stickers.py)は関数冒頭で
  `_mpd_sticker_check_type(field)`の直後、actionが"find"以外なら無条件で
  `_mpd_sticker_validate_uri(context, field, uri)`を呼んでから各action分岐
  (get/set/delete/inc/dec/list、未知語ならエラー)へ進んでいたため、この
  非対称が生じていた。
  修正: 関数冒頭の無条件`_mpd_sticker_validate_uri()`呼び出しを削除し、
  get/set/delete/inc/dec/listの各分岐内、その分岐固有の引数個数チェックが
  通った直後(ヘルパー呼び出しの直前)に個別に呼ぶよう移動(find分岐は元々
  呼んでおらず無変更、実MPDのDomainHandler::Find()もURI検証を行わない
  非対称仕様と一致)。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで
  直接接続。`sticker foobar song "存在しないuri" name`(未知action)が
  修正前`ACK [50@0] {sticker} no such song: ...`、修正後
  `ACK [2@0] {sticker} Unknown sticker action: foobar`に変化することを確認。
  `sticker get song "存在しないuri" name1 name2`(get本来は1名までのところ
  余分な引数)も修正前`ACK [50@0]`、修正後`ACK [2@0] {sticker} wrong number
  of arguments`に変化。回帰確認: 正しい引数個数のまま存在しないURIを指定した
  `sticker get song "存在しないuri" ratingname`は修正前後とも変わらず
  `ACK [50@0] {sticker} no such song: ...`(mpdstickersongnoexist-patch.pyの
  成果を破壊していないことを確認)。`sticker set playlist "存在しない
  プレイリスト名" rating "5"`も無変更で`ACK [2@0] {sticker} no such
  playlist: ...`(playlistドメインは実MPD通りACK 2のまま)。実在する曲URIに
  対する`sticker set/get/list/inc/dec/delete song`の一連の正常系ラウンド
  トリップ(rating 5→6→5→削除→get時ACK 50 no such sticker)も全て無変更で
  正常動作。mopidy.logの新規ERROR/Tracebackは0件(既知の`KeyError:
  'videoDetails'`ノイズは存在しないURIへのlibrary.lookup()由来の既存挙動、
  mpdstickersongvalidate-patch.py導入時から確認済みのもので新規ではない)。
  適用前にビルド済みソースを`/tmp`へ隔離コピーしパッチを当ててから
  `ast.parse()`で構文確認、2回連続適用でも冪等(2回目は"already fixed,
  skip")であることを確認済み。

- [x] `getvol`/`setvol`/相対 `volume {CHANGE}` (mopidy_mpd/protocol/playback.py) が
  mpdpartition-patch.py の追加したパーティション機構を一切考慮せず、常に単一
  グローバルな `context.core.mixer` actor へ直接アクセスしてしまう不具合。TODO
  全項目消化済みのため自走エージェント (general-purposeサブエージェントへの調査
  委任を経て) が新規発見・追加した項目。実MPD本体 (MusicPlayerDaemon/MPD、raw
  curlでソース直接確認: `src/command/OtherCommands.cxx` `handle_getvol`/
  `handle_setvol`/`handle_volume`、`src/mixer/Memento.cxx`
  `MixerMemento::GetVolume`/`SetVolume`) はいずれも `client.GetPartition()` で
  得た「そのパーティションが所有する出力集合 (`partition.outputs`)」に対して
  のみ動作する: `handle_getvol` は所有出力0件で `GetVolume()` が負値を返すため
  `volume:` 行自体を省略した空応答、`handle_setvol` は所有出力0件への
  `SetVolume()` が対象無しの暗黙no-opながらコマンド自体は常に `OK`、
  `handle_volume` (相対指定) は `old_volume < 0` を明示チェックし
  `ACK_ERROR_SYSTEM "No mixer"` を返す。mopidy_mpd には core.mixer actor が
  唯一つしか存在せず「パーティション所有の出力集合」という概念自体が無いため、
  mpdoutputpartition-patch.py が audio_output.py の
  `outputs`/`enableoutput`/`disableoutput`/`toggleoutput` 向けに導入した「唯一の
  仮想出力 "Mute" の所属パーティション == 自セッションの所属パーティション」
  という同じ判定 (`translator.output_partition_get("Mute") ==
  translator.partition_get(id(context.session))`) を playback.py の3ハンドラにも
  適用することで代替可能と判明。実害: `newpartition` で別パーティションを作り
  `moveoutput Mute` で仮想出力をそちらへ移した後でも、元のパーティション
  (Muteをもう所有していない) から `getvol`/`setvol`/`volume` を実行すると
  引き続き実際のグローバル音量を読み書きできてしまう。rmpc
  (`rmpc-mpd/src/mpd_client.rs` の `send_volume`/`send_set_vol`、idle Mixer
  イベント経由の `getvol`) はこれら3コマンドを実際に使うため到達可能な実害の
  あるギャップと判明。
  verified: mpdvolumepartition-patch.py。playback.py に
  `_mpdvolumepartition_owned(context)` ヘルパを追加 (audio_output.py の
  `_mpdoutputpartition_owned` と同一ロジック、mpdpartition-patch.py が既に持つ
  揮発性ストアを参照するのみで新規状態は持たない)。`getvol` は非所有時に空応答、
  `setvol` は非所有時に暗黙no-opで早期return (`OK` のまま値変更なし)、`volume`
  は非所有時に実MPDの `ACK_ERROR_SYSTEM "No mixer"` と同じ
  `MpdSystemError("No mixer")` を送出するよう変更。パッチ適用後のソースは
  一時コピーに当てて `ast.parse()` で構文確認、2回適用しても冪等 (2回目は
  "already applied, skip") であることも確認。dev mopidy (6601, ytmusic実
  アカウント) を実際に起動し、2本のTCP接続 (A=default固定, B) でMPDプロトコル
  を直接叩いて確認 — ベースライン A `getvol`(所有時)→実音量値(回帰なし)、
  `newpartition p2`→OK、B `partition p2`→OK、B `getvol`(moveoutput前、Mute
  はまだdefault所属)→空応答(`volume:`行なし)、B `moveoutput Mute`→OK、B
  `getvol`(所有後)→実音量値、A `getvol`(非所有化後)→空応答(`volume:`行なし、
  修正前は実音量値を返し続けていた)、A `setvol 77`(非所有)→`OK`だが実際には
  無変化(直後のB `getvol`が変更前の値のまま不変であることで確認)、A
  `volume +5`(非所有)→`ACK [52@0] {volume} No mixer`、B `setvol 33`(所有)→
  実際に変更されB `getvol`で33に反映、B `volume +10`(所有)→実際に変更され
  `getvol`で43に反映、A `moveoutput Mute`(defaultへ戻す)→OK、A `getvol`
  (再所有後)→43(パーティション跨ぎでも音量値自体はcore.mixerの実状態のまま
  保持され続けることも確認)、A `setvol 50`/`volume -5`(通常の単一パーティション
  運用、所有時)の回帰確認も無変化(50→45に正しく反映)。B切断・
  `delpartition p2`もOK。mopidy.log に ERROR/Traceback 0件を確認。

- [x] `sticker find`の`eq`/`lt`/`gt`整数比較演算子と`sort value_int`が使う
  `_mpd_sticker_as_int()`(mpdstickerfind-patch.py)がPythonの厳密な
  `int(value)`(ValueError以外は受理、それ以外は一律0)で数値変換しており、
  実MPD本体が同じ比較にSQLiteの`CAST(value AS INT)`を使う(前置数値
  プレフィックスのみを読み取り、直後に非数字が続いてもエラーにせずそこまでの
  数値を返す)のと変換規則が食い違う不具合を修正。TODO全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て)新規
  発見。実MPD本体(gh rawでsrc/sticker/Database.cxxを確認)は
  `STICKER_SQL_FIND_EQ_INT`/`_LT_INT`/`_GT_INT`が
  `"...AND CAST(value AS INT)=?"`のようなSQLを使い、`sort value_int`も
  `ORDER BY CAST(value AS INT)`を使う。実機sqlite3バイナリで直接検証した
  SQLiteのCAST(TEXT AS INTEGER)規則: `CAST('42abc' AS INTEGER)`=42、
  `CAST('-3.9' AS INTEGER)`=-3、`CAST('  12.5  ' AS INTEGER)`=12、数字が
  全く無ければ`CAST('abc' AS INTEGER)`=0、64bit符号付き整数の範囲外は
  上下限にクランプ(`CAST('99999999999999999999' AS INTEGER)`=
  9223372036854775807)。stickerの値はクライアントが`sticker set`で任意の
  文字列を書き込めるため、単位付き数値等の「前置数値+ゴミ文字列」が現実に
  ありうるが、mopidy_mpdの`int()`はこれをValueErrorとして一律0扱いして
  しまい、実MPDなら得られるはずの正しい数値との比較・並び順を返せていなかった
  (BACKLOG.md全体を`_mpd_sticker_as_int`/`CAST(value AS INT)`/`value_int`で
  検索し既存項目が無いことを確認済み)。
  修正: mpdstickerintcast-patch.py。`_mpd_sticker_as_int()`を正規表現
  (`^[ \t\r\n\f\v]*([+-]?[0-9]+)`)による前置数値プレフィックス抽出+64bit
  範囲クランプへ置換(`_mpd_sticker_match()`のeq/lt/gt分岐と
  `sort value_int`の両方が内部でこの共有関数を呼ぶため1箇所の修正で両方に
  伝播)。適用前にビルド済みソースを`/tmp`へ隔離コピーしパッチを当ててから
  `ast.parse()`で構文確認、2回連続適用でも冪等(2回目は"already present,
  skip")であることを確認済み。オフライン単体テストで実装した関数と実sqlite3
  バイナリの`CAST(? AS INTEGER)`を30種類超のedge case(通常の整数、小数、
  ゴミ文字混在、空文字列、全角/アラビア数字、複数符号、アンダースコア区切り、
  タブ/改行等の空白、64bit境界超過、`inf`/`nan`等)で突き合わせ完全一致する
  ことを確認済み。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで
  直接接続。`search any "yoasobi"`で取得した実在2曲URIに対し
  `sticker set song URI1 myrating "5abc"`/`sticker set song URI2 myrating
  "10"`を実行後、`sticker find song "" myrating eq "5"`が修正前0件(空応答、
  "5abc"がint()失敗で0扱いのため`eq "5"`(5)に一致しない)→修正後URI1が
  ヒット(CAST('5abc')=5と一致)することを確認。`gt "3"`は修正後URI1・URI2
  両方(5>3、10>3)、`lt "8"`はURI1のみ(5<8、10は<8でない)、
  `sort value_int`はURI1(5)→URI2(10)の順に正しくソートされることを確認。
  回帰確認: 通常の整数値のみ("5"/"10")での`eq`/`sort -value_int`(降順)/
  文字列比較演算子`=`は修正前後とも変わらず正常動作、mopidy.logに新規
  ERROR/Traceback 0件、起動もクリーンであることを確認。

- [x] find/search/count/playlistfind/playlistsearchが共有するフィルタ式
  パーサの`(prio >= "VALUE")`疑似タグ用ヘルパ`_mpd_parse_prio_filter_value()`
  (music_db.py、mpdpriofilter-patch.py導入)が、数値部分の妥当性チェックに
  Pythonの生の`re.fullmatch(r"\d+", raw_value)`+素の`int()`を使っており
  全角数字等の非ASCII"digit"文字を黙って受理してしまう不具合を修正。
  TODO全項目消化済みのため自走エージェントが(general-purposeサブエージェント
  への調査委任を経て)新規発見。Python正規表現の`\d`はデフォルトでUnicode
  対応のため`re.fullmatch(r"\d+", "５０")`はTrue、`int("５０")`は50になる
  (実測で確認済み)。既に`mpdstrictnumparse-patch.py`/`mpduintmax-patch.py`/
  `mpdwindowstrict-patch.py`/`mpdpositionstrict-patch.py`/
  `mpdsearchaddplposstrict-patch.py`で繰り返し修正されてきた
  「str.isdigit()/生の\dはUnicode桁を誤って受理する」バグと全く同じクラス
  だが、`prio`フィルタのVALUEパーサだけは横展開が漏れていた。
  実MPD本体(gh rawでsrc/song/Filter.cxx ParseExpression()の
  LOCATE_TAG_PRIORITY分岐を確認)は`strtoul(s, &endptr, 10)`を使い、
  `endptr == s`(1文字も数字として消費できない)ならACK Number expectedを
  返す。strtoulはCロケールのASCII '0'-'9'のみを走査するため全角数字は
  1文字も消費できずエラーになる。兄弟パーサ`protocol.UINT()`は既に
  `_MPD_STRICT_UINT_RE`(mpdstrictnumparse-patch.py)へこの検証を統合済み
  であり、本パッチはこれに委譲する。BACKLOG.md全体を
  `_mpd_parse_prio_filter_value`で検索し、既出はmpdpriofilter-patch.py
  本体(prioフィルタ機能自体の新規実装)のみでVALUEの数値検証の緩さを
  扱った項目が無いことを確認済み。
  修正: mpdpriofiltervaluestrict-patch.py。
  `_mpd_parse_prio_filter_value()`の`re.fullmatch(r"\d+", raw_value)`+
  `int(raw_value)`を`protocol.UINT(raw_value)`呼び出し(ValueError捕捉->
  既存の`MpdArgError("Number expected")`へ変換)へ置換。0-255範囲チェックは
  無変更。パッチ適用後の生成ソースは一時コピーに当てて`ast.parse()`で
  構文確認、2回連続適用しても冪等(2回目は"already present, skip")である
  ことを確認済み。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケット
  で直接接続。`search any "YOASOBI"`で取得した実在曲URIを`add`し、
  `prioid "50" "1"`でId=1にPrio: 50を設定した上で:
  `playlistfind "(prio >= \"５０\")"`(全角50)が修正前OK(Id=1が誤って
  ヒット、int("５０")==50として解釈)、修正後`ACK [2@0] {playlistfind}
  Number expected`に変化することを確認。
  回帰確認: 半角`"50"`は修正前後ともId=1がヒットし変化なし、範囲外の
  半角`"999"`は修正前後とも`ACK [2@0] {playlistfind} Invalid priority
  value`で変化なし、不正演算子`prio > "50"`は修正前後とも
  `ACK [2@0] {playlistfind} '>=' expected`で変化なし。mopidy.logに
  新規ERROR/Traceback 0件、起動もクリーンであることを確認。

- [x] `sticker`系コマンドとstickertypes/stickernamestypesが実MPD 0.24+の
  4つ目のドメインである"filter"(URI引数をMPDフィルタ式としてパースし、
  DB内に1件でもマッチすればそのフィルタ式文字列自体をstickerのキーとして
  扱うドメイン)を一切受け付けず、常に`ACK Unknown sticker domain: filter`
  になる不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  song/playlist/タグ種別17種(mpdstickerplaylist-patch.py/
  mpdstickertagdomain-patch.py)の3ドメインは既に対応済みだったが、実MPD
  本体のドメイン一覧はもう1つ"filter"を含んでいた。
  実MPD本体(gh rawでsrc/command/StickerCommands.cxx handle_sticker()、
  src/sticker/TagSticker.cxx MakeSongFilter()/FilterMatches()を確認)は
  `StringIsEqual(sticker_type, "filter")`をsong/playlistに続き3番目
  (タグ名解決より前)に判定しFilterHandlerへディスパッチする。
  FilterHandler::ValidateUri()はURIをSongFilterとしてパースし、DB内に
  1件でもマッチ(`FilterMatches(database, filter)`)しなければ
  `std::invalid_argument`(CommandError.cxxのToAck()でACK_ERROR_ARG(2)、
  既存のplaylist/タグドメインと同じコード)を送出する。FilterHandler/
  TagHandlerはどちらもDomainHandler::Find()をオーバーライドしない
  (songのみ独自Find()でディレクトリ境界処理を持つ)ため、
  `sticker find filter <URI> ...`のURIはフィルタ式としてはパースされず
  他の非songドメインと同じ生のuri前方一致のままであり、mopidy_mpd側の
  `_mpd_sticker_find_ext`は既にfield非song時はディレクトリ境界処理を
  スキップする実装のためfind側の変更は不要と判明。
  mopidy_mpdにはreal MPDの`SongFilter::ToExpression()`相当の正規化
  シリアライザが無いため、ValidateUri相当のマッチ判定はfind()コマンドと
  全く同じフィルタ式パーサ/検索パイプライン
  (`_query_from_mpd_filter_expression`/`_mpd_pop_negatives`/
  `_mpd_pop_positives`/`_mpd_filter_negatives`/`_mpd_filter_positives`、
  いずれもmusic_db.py)を再利用して「1件でも実曲がマッチするか」だけを
  判定し、正規化はせずクライアントが送った生の文字列をそのまま
  sticker DBのキーとして扱う(簡略化、パッチコメントに明記)。real MPDの
  FilterMatches()はDB内の実曲のみを対象としartist/album見出し等の
  合成placeholderは含まないため、find()自身が行う`_artist_as_track`/
  `_album_as_track`によるplaceholder合成は使わず`_get_tracks(results)`
  のみで判定する。
  修正: mpdstickerfilterdomain-patch.py。`_MPD_STICKER_DOMAINS`に
  `"filter"`を追加(stickertypes/stickernamestypesの既存実装が自動的に
  filterドメインを反映)、`_mpd_sticker_validate_uri()`に
  `_mpd_sticker_validate_filter()`呼び出しの分岐を追加。適用前に
  ビルド済みソースを`/tmp`へ隔離コピーしパッチを当ててから`ast.parse()`
  で構文確認済み。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケット
  で直接接続。`stickertypes`が修正後`stickertype: filter`を新たに含むことを
  確認。`sticker set filter "(Artist == \"YOASOBI\")" testrating "1"`が
  修正前`ACK [2@0] {sticker} Unknown sticker domain: filter`→修正後`OK`に
  変化し、続く`sticker get filter "(Artist == \"YOASOBI\")" testrating`が
  `sticker: testrating=1`を返すことを確認。実在しないアーティストの
  フィルタ式(`(Artist == "NoSuchArtistXYZ123")`)への`sticker set`が
  `ACK [2@0] {sticker} no matches found: (Artist == "NoSuchArtistXYZ123")`
  になることを確認(FilterHandler::ValidateUri()のACK_ERROR_ARG(2)と
  一致)。`sticker list filter ...`/`sticker find filter "(Artist"
  testrating`(前方一致、`filter: (Artist == "YOASOBI")`として出力される
  ことも確認)/`stickernamestypes filter`/`sticker delete filter ...`も
  全て正常動作を確認。
  回帰確認: 未知ドメイン(`sticker set bogusdomain ...`)は修正前後とも
  `ACK [2@0] {sticker} Unknown sticker domain: bogusdomain`で変化なし。
  フィルタ式としてパース不能な文字列(`sticker set filter "not a filter
  expr" ...`)は`ACK [2@0] {sticker} incorrect arguments`(既存の
  find/searchと同じrequire_positiveガード由来)。`find artist "YOASOBI"`
  (song domainの既存機能、265行)は無変更で正常動作。mopidy.logに新規
  ERROR/Traceback 0件、起動もクリーンであることを確認。

- [x] `albumart`/`readpicture` が共有する `_mpdart_send()` (mpd-patch.py) が、
  クライアント指定の OFFSET が画像の実サイズ (total) を超えている場合を一切
  検証しておらず、`offset >= total` を一律「転送完了(空バイナリ)」として常に
  OK を返してしまう不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。隣接する
  mpdreadpictureempty-patch.py は「画像取得自体が失敗した場合」のACK非対称
  のみを修正しており、offsetの境界チェックには未着手だった。
  実MPD本体(gh rawでsrc/command/FileCommands.cxxを確認)はこの2コマンドとも
  offsetがサイズ超過の場合を明確にACK_ERROR_ARG(2)で拒否する:
  albumart(`read_stream_art()`)は`if (offset > art_file_size) r.Error(
  ACK_ERROR_ARG, "Offset too large")`、readpicture(`PrintPictureHandler::
  OnPicture()`/`RethrowError()`)は`if (offset > buffer.size()) bad_offset
  = true`→`ProtocolError(ACK_ERROR_ARG, "Bad file offset")`。どちらも
  `offset == total`(残り0バイトちょうど)のみ空バイナリでOKを許容する境界は
  共通だが、エラーメッセージ文言はコマンドごとに異なる。
  修正: mpdartoffsetguard-patch.py。`total = len(data)`直後に`offset >
  total`のガードを追加し、with_type(readpictureかどうか)に応じて実MPDと
  同じメッセージでMpdArgError(ACK_ERROR_ARG)を送出。`offset == total`の
  既存の空バイナリ応答は無変更。パッチ適用後の生成ソースは一時コピーに
  当ててから`ast.parse()`で構文確認、2回連続適用しても冪等(2回目は
  "already applied, skip")であることを確認済み。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケット
  で直接接続。`search any "YOASOBI"`で取得した実在曲URI
  (`ytmusic:track:by4SYYWlhEs`、size=75973)に対し、`readpicture URI 0`で
  正常にJPEGバイナリ(size/type/binary込み)を取得後、`readpicture URI
  76473`(size+500、offset>total)が修正前OK(binary: 0)→修正後
  `ACK [2@0] {readpicture} Bad file offset`に変化することを確認。同様に
  `albumart URI 76473`が修正前OK→修正後`ACK [2@0] {albumart} Offset too
  large`に変化することを確認。
  回帰確認: `offset == total`(75973ちょうど)は修正前後とも
  `size: 75973\nbinary: 0`でOK(readpicture/albumart両方)、中間offset
  (8192)は修正前後ともJPEGバイナリの続きを正常に返す(readpicture/
  albumart両方)ことを確認。既存の「画像取得自体が失敗」ケース(bogus URI)
  はmpdreadpictureempty-patch.py導入時の非対称のまま無変更
  (readpicture→OK空応答、albumart→`ACK [50@0] No file exists`)。
  `status`/`tagtypes`の回帰なしも確認。mopidy.logに新規ERROR/Traceback
  0件、起動もクリーンであることを確認。
- [x] `stickertypes` が実MPD 0.24+と異なりクライアント接続ごとの`tagtypes`
  enable/disable/clear状態を一切反映せず、常に全17タグドメインを列挙して
  しまう不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawでsrc/command/StickerCommands.cxx handle_sticker_types()
  を確認)は`const auto tag_mask = global_tag_mask & r.GetTagMask();`で
  接続ごとのタグマスク(`tagtypes`コマンドが操作するのと同じマスク)と
  sticker_allowed_tags(17タグの固定許可リスト)の両方を満たすタグ名のみを
  列挙するが、mopidy_mpd側の`stickertypes()`(mpdstickertagdomain-patch.py
  導入)は`_MPD_STICKER_TAG_DOMAIN_NAMES`を無条件にそのまま返しており
  `context.session.tagtypes`を一切参照していなかった。一方
  `stickernamestypes {TYPE}`(`handle_sticker_names_types()`)は別マスク
  (`sticker_allowed_tags`のみ、接続ごとのtagtypesマスクとは無関係)で判定
  しており対象外(gh rawで実MPD本体を確認、既存の`_mpd_sticker_resolve_
  domain()`のままで正しい)。mopidy_mpdにはglobal_tag_mask相当(サーバ設定
  `metadata_to_use`)が無いため常に全許可扱いとし`context.session.tagtypes`
  のみで絞る(mpdtagtypesavailablereset-patch.py導入時の既存方針を踏襲)。
  修正: mpdstickertypesmask-patch.py。`stickertypes()`のタグドメイン列挙
  部分を新規ヘルパ`_mpd_sticker_types_tagmask(context)`に切り出し、
  `_MPD_STICKER_TAG_DOMAIN_NAMES`を`context.session.tagtypes`でフィルタ
  してから返すよう変更(song/playlist/filterの固定3種は無条件のまま無変更)。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケット
  で直接接続。`stickertypes`(既定、全タグ有効)→全17タグ+song/playlist/
  filterの20行が修正前後とも変化なし。`tagtypes clear`→OK後の
  `stickertypes`が修正前は変わらず20行のまま、修正後は`stickertype: song`/
  `playlist`/`filter`の3行のみに変化。`tagtypes enable Artist`→OK後は
  `stickertype: Artist`が追加され4行。`tagtypes all`→OK後は20行に復帰
  (回帰無し)。回帰確認: `stickernamestypes`(引数無し)/`stickernamestypes
  Artist`(タグドメイン指定)/`search artist "YOASOBI"`(55件)/
  `count "(Artist == \"YOASOBI\")"`(songs: 5)/`status`/`tagtypes`(37行)/
  `list album group artist`は修正前後とも無変更。mopidy.logに新規ERROR/
  Traceback 0件、起動もクリーンであることを確認。

- [x] `outputset {ID} {NAME} {VALUE}` (MPD 0.24+の出力ランタイム属性設定コマンド)が
  mopidy_mpd 3.3.0に丸ごと欠落しており常に `ACK unknown command "outputset"` に
  なっていた不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見・再検討。
  mpdplaylistlength-patch.py の調査時(mpd.readthedocs.io protocol リファレンス
  全文照合)で見つかった未実装6件のうち、outputsetは「mopidyのaudio output抽象に
  runtime attributeの概念が無い」という理由で見送られていた。しかしこの理由は
  実MPD本体側でも同じ結論(属性を持たない出力プラグインは常に拒否)であり、
  コマンド自体を未実装のままにする理由にはならないと判明: gh rawで
  src/command/OutputCommands.cxx handle_outputset()を確認すると、
  `CheckPartitionOutput(partition, i)`でID有効性/パーティション所属を検証した後
  `IsValidAttributeName(name)`(英数字と`_`のみ、空文字不可)を検証し、最後に
  `ao.SetAttribute(name, value)`を呼ぶ。src/output/Interface.cxxの基底実装
  (属性を一切持たないプラグインが継承するデフォルト)は
  `throw std::invalid_argument("Unsupported attribute")`のみで、これは
  CommandError.cxxのToAck()でACK_ERROR_ARG(2)にマップされる
  (std::invalid_argument→2は既にmpdstickersongvalidate-patch.py/
  mpdstickersongnoexist-patch.py等で確認済みの変換規則)。つまり実MPDの
  「属性を持たない出力」に対する`outputset`の正しい応答は「常にACK 2
  Unsupported attribute」であり、mopidy_mpdの単一仮想出力("Mute", id 0)でも
  同じ応答形を再現できる。ID/パーティション検証はsrc/output/OutputCommand.cxxの
  CheckPartitionOutput()実装を確認: idx>=出力数はACK_ERROR_NO_EXIST(50)
  "No such audio output"、所属パーティション不一致もACK_ERROR_NO_EXIST(50)
  (メッセージは実MPDでは"Audio output not in this partition"と別だが、
  mpdoutputpartition-patch.pyが導入した既存のenableoutput/disableoutput/
  toggleoutputも両ケースを同一メッセージ"No such audio output"に統合済みのため、
  本パッチもその既存の簡略化方針を踏襲し新たな不整合を持ち込まない)。
  修正: mpdoutputset-patch.py。audio_output.pyに
  `outputset(context, outputid, name, value)`ハンドラを新規追加。既存の
  `_mpdoutputpartition_owned(context)`(mpdoutputpartition-patch.py導入)を
  そのまま再利用してID/所属チェックとし、有効なら`IsValidAttributeName`相当
  (`^[A-Za-z0-9_]+$`)で属性名を検証してから常に`MpdArgError("Unsupported
  attribute")`を送出する(実際には何も変更しない、mpdcrossfade-patch.py等が
  確立済みの「プロトコル層のみ・機能的効果ゼロ」パターンと同種)。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)にPythonソケットで
  直接接続。`outputset 0 foo bar` -> 修正前 `ACK [5@0] {} unknown command
  "outputset"` -> 修正後 `ACK [2@0] {outputset} Unsupported attribute`。
  `outputset 1 foo bar`(存在しないID) -> `ACK [50@0] {outputset} No such audio
  output`。`outputset 0 "bad name!" bar`(不正な属性名) -> `ACK [2@0]
  {outputset} Illegal attribute name`。引数不足(`outputset 0 foo`) -> `ACK
  [2@0] {outputset} wrong number of arguments for "outputset"`(既存の汎用
  arg-count検証が自動対応、追加コード不要)。回帰確認: `outputs`(plugin:
  mopidy, outputenabled: 0)/`status`は修正前後で無変更。mopidy.logに新規
  ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] `actor.py` の `_CORE_EVENTS_TO_IDLE_SUBSYSTEMS` (upstream mopidy-mpd 3.3.0の
  元々のソース、パッチ対象外) が mopidy core の `stream_title_changed` イベント
  (ストリーム再生中に GStreamer が報告する title タグが現在曲の名前と食い違った際に
  `mopidy/core/actor.py Core.tags_changed()` が発火、mopidy_ytmusic のライブストリーム
  URI (ytlivestream-patch.py) でも起こりうる) を idle サブシステム `"playlist"` へ
  誤って割り当てている不具合を修正。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawで doc/protocol.rst / src/Partition.cxx を確認)は「現在再生中の
  曲のタグが変化した(例: ストリームから受信)」を明確に idle サブシステム `"player"`
  の説明として定義しており(protocol.rst: "the player has been started, stopped or
  seeked or tags of the currently playing song have changed (e.g. received from
  stream)")、実装側の `Partition::OnPlayerTagModified()` も `EmitIdle(IDLE_PLAYER);`
  と "player" のみを発火する("playlist" には一切触れない)。一方 mopidy_mpd は
  `"stream_title_changed": "playlist",` と誤って"playlist"サブシステムに割り当てて
  おり、`idle player` のみを購読する一般的なMPDクライアント(mpc/ncmpcpp等)は
  ストリームのタイトル変化で一切起床しない(意味的に無関係な `idle playlist` 側で
  誤って発火する)。同じ辞書内の他のイベント(playback_state_changed/seeked→player、
  tracklist_changed→playlist、playlist_changed/playlist_deleted/playlists_loaded→
  stored_playlist、options_changed→options、volume_changed→mixer、mute_changed→
  output)は全て実MPDのIDLE_*定義と一致しておりこの1エントリのみが非対称であることを
  確認済み。BACKLOG.md全体をstream_title_changedで検索し既存項目が無いことを
  確認済み。
  修正: mpdstreamtitleidle-patch.py。`_CORE_EVENTS_TO_IDLE_SUBSYSTEMS`辞書の該当
  エントリの値を`"playlist"`から`"player"`へ変更するのみ(1行)。パッチ適用後の
  生成ソースは`ast.parse()`で構文確認済み。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)を実際にビルド・起動して
  確認。ストリームのtitleタグ変化を実際にGStreamer経由で発火させるのは本テスト
  アカウントの実データでは再現困難(通常のオンデマンド曲はAPIのtitleとGStreamerの
  タグが一致するため)なため、mpdsearchcount-patch.py等と同様にオフライン検証で
  実コードパスを直接確認: パッチ済みenvの実インタプリタで`mopidy_mpd.actor`を
  import し(GI_TYPELIB_PATH/GST_PLUGIN_SYSTEM_PATH_1_0を稼働中プロセスの環境変数
  から採取)、`MpdFrontend`を`object.__new__()`でインスタンス化(pykka/GLib依存を
  回避)、`send_idle`をキャプチャして`on_event()`(実コード、再実装ではない)を
  直接呼び出し、`stream_title_changed`→`['player']`(修正前は`['playlist']`)、
  かつ`tracklist_changed`→`['playlist']`/`seeked`→`['player']`/`playlist_changed`→
  `['stored_playlist']`/`playback_state_changed`→`['player']`/`options_changed`→
  `['options']`/`volume_changed`→`['mixer']`/`mute_changed`→`['output']`/
  `playlists_loaded`→`['stored_playlist']`/`playlist_deleted`→`['stored_playlist']`
  の他9エントリが全て無変更であることを確認。加えてTCP 6601での実プロトコル
  回帰確認: `findadd`で実データ2曲をキューに追加後、`idle player`購読中に
  無関係な`random 1`(optionsドメイン)では起床しない(正しい)ことを確認、
  `play 0`(実際に再生開始、`playback_state_changed`実発火)では
  `changed: player`で正しく起床することを確認、`idle playlist`購読中に`clear`
  (`tracklist_changed`実発火)では`changed: playlist`で正しく起床することを確認
  (どちらも本パッチが触れていないエントリの回帰無し)。`status`/`currentsong`も
  無変更。mopidy.logに新規ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] `sticker inc`/`sticker dec` の `_mpd_sticker_inc_dec()` が VALUE を Python の厳密な
  `int(value)` + 64bit範囲チェックで事前検証し、非数値/オーバーフローだと
  `ACK invalid sticker value` を返してしまう不具合。TODO/既知の軽微な残課題を全項目
  消化済みのため自走エージェントが(general-purposeサブエージェントへの調査委任を経て)
  新規発見。実MPD本体(gh rawで src/command/StickerCommands.cxx handle_sticker()/
  DomainHandler::Inc()/Dec() および src/sticker/Database.cxx
  StickerDatabase::IncValue()/DecValue() を確認)はVALUEに対し一切の数値検証を行わない:
  `args[4]`(生の文字列)をそのまま`IncValue(type, uri, name, value)`へ渡し、
  `BindAll(s, type, uri, name, value, value)`で"INSERT INTO sticker (type, uri, name,
  value) VALUES (?, ?, ?, ?) ON CONFLICT(type, uri, name) DO UPDATE set value = value +
  ?"の2箇所(新規行のvalue列、および加算オペランド)へ同じ生文字列をバインドするのみで、
  数値変換はSQLite自身の算術時の暗黙型変換(TEXT値への数値親和性変換、CAST(TEXT AS
  INTEGER)と同じ前置数値プレフィックス規則)に委ねている。つまり実MPDは新規作成時
  クライアントが送った生の文字列をそのまま保存し(数値として解釈すらしない)、既存
  スティッカーへのinc/decのみSQLiteの数値親和性変換で計算される。BACKLOG.md全体を
  `invalid sticker value`/`IncValue`/`DecValue`/`_mpd_sticker_inc_dec`で検索したが、
  mpdstickernames-patch.py(実MPD未確認のままACK仕様を新規実装した箇所)と
  mpdstickerincoverflow-patch.py(Pythonのint()起因のOverflowError未捕捉クラッシュを
  ACKへ変換しただけ)のみがヒットし、どちらも「VALUEを実MPDがそもそも検証しない」
  という点は検討されていなかったことを確認済み。
  verified: mpdstickerincraw-patch.py。既に実MPDのSQLite CAST(value AS INT)相当の
  セマンティクスへ合わせ込み済みの`_mpd_sticker_as_int()`(mpdstickerintcast-patch.py、
  前置数値プレフィックス抽出+64bit範囲クランプ、実sqlite3で検証済み)を再利用し、
  `int(value)`の厳密パース+ACKを削除。INSERT時のvalue列バインドも`str(delta)`
  (Pythonが解釈した数値の文字列化)ではなく生の`value`(クライアントが送った文字列
  そのもの)に変更し、新規作成時に生文字列を保存する実MPDの挙動を再現。nix/lib/
  mopidy-env.nixのmpdPatchedリスト末尾(mpdstreamtitleidle-patch.pyの直後)に登録
  (`_mpd_sticker_as_int`を導入したmpdstickerintcast-patch.py、および
  `_mpd_sticker_inc_dec`を最後にfull-body-replaceしたmpdstickerincoverflow-patch.py
  の両方より後段であることを`grep -l`で確認済み)。パッチ適用後の生成ソースは
  `ast.parse()`で構文確認済み。dev mopidy(6601, ytmusic実アカウント)を実際に
  ビルド・起動しMPDで実機確認 — 実データ(`search any "YOASOBI"`で取得した実track
  URI)に対し `sticker set song URI counter "5"` → OK、`sticker inc song URI counter
  "abc"`(非数値)が修正前`ACK [2@0] {sticker} invalid sticker value: abc`、修正後
  `OK`(既存値5に0加算=無変化、`sticker get`で確認)に変化。別の実track URIへ
  `sticker inc song URI2 newname "5abc"`(既存スティッカー無し、新規作成)が修正前
  ACK、修正後OKかつ`sticker get song URI2 newname`が生文字列`5abc`をそのまま返す
  ことを確認(数値解釈せず生文字列保存する実MPD挙動の再現を確認)。巨大な数値
  (10**32桁)も同様にACK→OKへ変化。回帰確認: `sticker inc song URI counter "3"`
  (通常数値)→OKかつcounter=8→11のように正しく加算、`sticker dec ... "2"`→正しく
  減算、未知ドメイン`sticker inc bogusdomain "x" name "1"`→引き続き`ACK [2@0]
  Unknown sticker domain: bogusdomain`(無変更)、NAME空文字列`sticker inc song URI ""
  "1"`→引き続き`ACK [2@0] empty sticker name`(mpdstickernames-patch.py由来のガード、
  無変更)、タグドメイン(`sticker inc artist "YOASOBI" plays "1"`)も正常動作、
  `status`/`tagtypes`の回帰なし。**確認した既存挙動(バグではない)**:
  極端な巨大値をincした後にさらにincすると、SQLiteが64bit整数範囲を超えた算術結果を
  REAL(浮動小数点、指数表記のTEXT表現)へ自動的に昇格させ、その後のCAST(TEXT AS
  INTEGER)が指数表記の仮数部の整数プレフィックスのみを読み取ってしまうため一見
  不可解な値になる場合がある(例: 実sqlite3で`CAST('5' AS INTEGER) +
  9223372036854775807`→REAL→次に`+3`すると`12`になる、`CAST('9.223...e+18' AS
  INTEGER)`=9であることを実sqlite3バイナリで直接再現・確認済み)。これは
  value列がVARCHAR(TEXT親和性)であることに起因する純粋なSQLiteエンジン自体の
  挙動であり、実MPD本体も全く同一のSQL文/同一のカラム型(VARCHAR)を使うため
  100%同じ結果になる(mopidy_mpd固有の非互換ではない、修正不要と判断)。
  mopidy.logに新規ERROR/Traceback 0件、起動もクリーンであることを確認。
- [x] `find`/`search`/`findadd`/`searchadd`/`searchaddpl`(music_db.py)と
  `playlistfind`/`playlistsearch`(current_playlist.py)が共有・独自に持つ末尾修飾子
  パーサ`_mpd_extract_sort_params()`/`_pf_extract_sort_params()`が、`sort TYPE`/
  `window START:END`修飾子対を`while len(params) >= 2 and params[-2].lower() in
  ("sort", "window"):`というループで任意の順序・任意の回数剥がしてしまい、
  本来ACKになるべき不正な組み合わせ(`window`が`sort`より前、`sort`/`window`の
  重複)を黙って受理してしまう不具合。TODO全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawでsrc/command/DatabaseCommands.cxx ParseDatabaseSelection()を
  確認)は非ループの一発勝負: `if (args.size() >= 2 &&
  StringIsEqual(args[args.size() - 2], "window")) { ...; args.pop_back();
  args.pop_back(); }` で末尾ペアが"window"なら1回だけ剥がし、続けて(剥がした後の)
  `if (args.size() >= 2 && StringIsEqual(args[args.size() - 2], "sort")) { ...;
  args.pop_back(); args.pop_back(); }` で末尾ペアが"sort"なら1回だけ剥がす。
  つまりコマンド上の並びは常に`FILTER [sort TYPE] [window START:END]`(sortが
  windowより前)でなければならず、剥がしきれなかった余った"sort"/"window"
  トークンはそのまま`filter.Parse(args, ...)`(mopidy_mpd側では
  `_query_from_mpd_search_parameters()`の旧式TAG VALUEループ、`mapping.get(tag)`が
  Noneになり`MpdArgError("incorrect arguments")`)に渡り未知タグとしてACKになる。
  BACKLOG.mdを`_mpd_extract_sort_params`/`_pf_extract_sort_params`等で検索したが
  該当ヒットはこの関数の新設(mpdsort-patch.py)/window対応追加
  (mpdwindow-patch.py)/`sort prio`対応(mpdplaylistfindsortprio-patch.py)/
  window単発パーサとの使い分け確認(mpdwindowbare-patch.py)のみで、順序検証・
  重複検出は未対応・未blockedと確認。
  修正: mpdsortwindoworder-patch.py(music_db.pyの`_mpd_extract_sort_params`)/
  mpdpfsortwindoworder-patch.py(current_playlist.pyの独自コピー
  `_pf_extract_sort_params`、mpdbasefilter-patch.pyが`_mpd_track_matches_positives`/
  `_pf_matches`を個別に直したのと同じクロスファイル重複のため2ファイルに分割)。
  どちらも`while`ループを「まず`window`を1回だけ剥がす→続けて`sort`を1回だけ
  剥がす」という実MPD準拠の非ループ判定に置換するのみ(sort/windowそれぞれの
  値パース・エラー処理・戻り値の形は無変更)。nix/lib/mopidy-env.nixの
  mpdPatchedリスト末尾(mpdstickerincraw-patch.pyの直後)に登録。
  `_mpd_extract_sort_params`をfull-body-replaceした最後のパッチが
  mpdwindow-patch.pyであること(以降のパッチはこの関数を再度full-body-replace
  していないこと)を`grep -l`で確認済み、`_pf_extract_sort_params`は
  mpdplaylistfindsortprio-patch.pyが唯一の新設元であることも確認済み。
  パッチ適用後の生成ソースは、既に稼働中のenvから対象2ファイルを含む
  mopidy_mpdパッケージ全体を一時ディレクトリへコピーし新パッチを適用した上で
  `ast.parse()`により構文確認済み(既にpatch済みの現行版に対する再適用で
  MARKERスキップも正常動作することを確認)。
  verified: 実機(dev mopidy TCP 6601、実ytmusicアカウント)を実際にビルド・
  起動して確認。`search any "YOASOBI"`で実データ存在を確認した上で:
  `find "(Artist == \"YOASOBI\")" window "0:1" sort Artist`(順序が逆)/
  `sort Artist sort Title`(sort重複)/`window "0:1" window "1:2"`(window重複)が
  修正前いずれも`OK`(本来ACKになるべき)だったのが修正後すべて
  `ACK [2@0] {find} incorrect arguments`に変化することを確認。回帰確認:
  正しい順序`sort Artist window "0:1"`/`sort`単独/`window`単独/両方無し
  はいずれも修正前後で同一の正常な結果(OK+期待通りのトラック列、ソート・
  windowスライスも正しく適用)。`playlistfind`/`playlistsearch`側も同様に
  (`clear`+`findadd`で実データをキューに投入した上で)順序が逆/sort重複が
  修正前OK→修正後ACKに変化、正しい順序/`sort`単独/`window`単独/両方無し/
  playlistfind専用の`sort prio`はいずれも無変更で正常動作することを確認。
  `findadd "(Artist == \"YOASOBI\")" sort Artist window "0:2"`(正常系の
  sort+window併用)が2曲のみキューに追加されること(windowスライスが
  sort適用後の結果に正しく効くこと)も確認。`status`/`tagtypes`の回帰なし、
  mopidy.logに新規ERROR/Traceback 0件、起動もクリーンであることを確認。

- [x] volume_changed/mute_changed 由来の idle 通知("mixer"/"output")が
  actor.py `MpdFrontend.send_idle()` 経由で接続中の全パーティションへ
  無条件ブロードキャストされてしまう不具合。TODO 全項目消化済みのため
  自走エージェントが(general-purpose サブエージェントへの調査委任を経て)
  新規発見した項目。mpdvolumepartition-patch.py/mpdoutputpartition-patch.py
  は唯一の仮想出力 "Mute" の所属パーティション
  (`translator.output_partition_get("Mute")`) と自セッションの所属
  (`translator.partition_get(id(context.session))`) が一致する場合のみ
  getvol/setvol/相対volume/enableoutput/disableoutput/toggleoutput/
  outputset/outputs が実際に mixer 状態を読み書きするよう既に絞り込み済み
  (非所有時: setvol は暗黙 no-op で OK、volume は ACK No mixer)。だが
  これらの操作が実際に `context.core.mixer` 経由で volume_changed/
  mute_changed を発火させた際、actor.py の `on_event()` は
  `_CORE_EVENTS_TO_IDLE_SUBSYSTEMS`("volume_changed":"mixer",
  "mute_changed":"output") を経由して `send_idle()` を呼ぶだけで、
  `send_idle()` は `mopidy.listener.send(session.MpdSession, subsystem)`
  により接続中の全 MpdSession へ無条件 broadcast する。所有パーティションの
  クライアントが setvol 等で実際に mixer を操作すると、非所有パーティション
  で `idle mixer`/`idle output` を購読中の無関係なクライアントまで誤って
  起床してしまう(そのクライアント自身の getvol は空応答のままなのに、で
  ある)。実 MPD 本体(gh raw で MusicPlayerDaemon/MPD を実際に確認)は
  この非対称が無いことを特定: `src/Partition.cxx`
  `Partition::OnMixerVolumeChanged()`/`OnMixerChanged()` はどちらも自
  パーティション限定の `EmitIdle(IDLE_MIXER)` のみを呼ぶ
  (`Partition::EmitIdle` は Partition.hxx で自パーティションの idle_monitor
  のみを操作、他パーティションのクライアントには一切通知しない)。
  `src/output/OutputCommand.cxx` `audio_output_enable_index()`/
  `disable_index()`/`toggle_index()`、`src/command/OutputCommands.cxx`
  `handle_outputset()` も全て `partition.EmitIdle(IDLE_OUTPUT)`(コマンドを
  発行したクライアント自身のパーティション限定、`CheckPartitionOutput()` が
  非所有出力へのアクセス自体を先に弾くため必然的に所有パーティションのみに
  なる)。直近の実MPDコミット(2026-07-17
  `d9f2c3666dfcf1483598e88416958445a6e4ccff` "output/MultipleOutputs: install
  new MixerListener on moveoutput")のログ文言 "This finally fixes 'mixer'
  idle events on non-default partitions. Previously, the MixerListener always
  pointed to the initial (default) partition." が、まさにこの「mixer idle
  が本来のパーティションを無視して漏れる」バグ自体が実MPD側でも直近まで
  存在した実例であることを裏付けている。一方 `src/command/
  PartitionCommands.cxx` `handle_moveoutput()` 自体が発火する idle "output"
  は `instance.EmitIdle(IDLE_OUTPUT)`(`Instance::OnIdle()` が全パーティ
  ションを走査して EmitIdle する、`Instance.cxx` 確認済み)であり、これは
  意図的に全パーティション broadcast が正しい(出力の所属パーティションが
  変わったこと自体は全体に関わるため)。partition.py
  (mpdpartition-patch.py)の `_mpdpartition_notify("output")` は既にこの
  全体 broadcast と同じ機構(`mopidy.listener.send`)を使っており、そちらは
  対象外(今回のスコープは volume_changed/mute_changed という mixer 実操作
  由来の idle のみ)。BACKLOG.md 全体を `MixerListener`/`partition.*mixer`/
  `output_partition_get`/`idle.*partition` で検索したが、既存のパーティション
  関連項目は (a) moveoutput/newpartition/delpartition 自身が正しく
  changed: output/changed: partition を発火すること、(b) volume 値自体が
  パーティション間で共有される(既存の許容された制約)こと、のみを検証して
  おり、idle 通知そのもののスコープ漏れは未検証・未対応だった。
  verified: mpdidlemixerpartition-patch.py。実装は channels.py の
  `_mpdchannels_notify_targeted`(実MPDの `Client::PushMessage()` 相当、
  メッセージ受信対象だけへ個別配送する既存機構)と同じ
  `pykka.messages.ProxyCall` 直接 `tell()` を使い、volume_changed/
  mute_changed の2イベントだけ、唯一の仮想出力 "Mute" の所属パーティションと
  同じパーティションに属するセッションのみへ個別配送するよう変更
  (`actor.py` に新規 `_send_idle_mixer_output()` を追加)。対象セッション
  一覧を得るため、channels.py の購読時遅延登録(`_channel_actor_refs`)とは
  別に、subscribe 未実行の接続も含めた全セッションの actor_ref を
  session.py の `on_start`/`on_stop` で無条件に登録/破棄する新規ストア
  (`translator.py` `_session_actor_refs`/`session_register`/
  `session_unregister`/`mixer_output_idle_targets()`)を追加。実機確認
  (TCP 6601、実ytmusicアカウント、2〜3接続 A/B/C): `newpartition p2` →
  B を `partition p2` へ切替(A は default に残り Mute を所有)。(1) B
  (非所有, p2)が `idle mixer` 購読中に A(所有)が `setvol` → 修正前は
  B が誤って `changed: mixer` で起床していたはずが、修正後は起床しない
  ことを確認。(2) A(所有)が `idle mixer` 購読中に B(非所有)が
  `setvol`(実際には無音 no-op)→ A は起床しない(mute_changed/
  volume_changed 自体が発火しないため無変更、regression確認)。(3)
  `moveoutput "Mute"` を B から実行し所有権を p2 へ移動(`getvol`で A が
  空応答・B が実 volume を返すことで所有権移動自体を確認)。(4) 所有権
  移動後、A(now非所有)が `idle mixer` 購読中に B(now所有)が `setvol`
  → 修正後は A は起床しない(所有権が変わってもスコープが正しく追随する
  ことを確認)。(5) regression: C も `partition p2` へ加え(B と同じ
  partition, 新オーナー)`idle mixer` 購読中に B が `setvol` →
  `changed: mixer` で正しく起床すること(同一パーティション内の配送は
  引き続き機能すること)を確認。(6) regression: 本パッチが対象としない
  他 subsystem("options")は `random 1` 実行で異なるパーティションの
  クライアントにも引き続き `changed: options` が届くこと(mopidy core は
  パーティション毎に独立した再生状態を持たないため意図的に無変更)を確認。
  `status`/`tagtypes`/`find` の回帰なし、mopidy.log に新規ERROR/Traceback
  0件、起動もクリーンであることを確認。

- [x] find/search/count/searchcount/findadd/searchadd/searchaddpl/list/
  playlistfind/playlistsearch/searchplaylist が共有するフィルタ式パーサ
  `_query_from_mpd_filter_expression`(music_db.py、`(TAG OP "VALUE")`形式の
  クオート値を1文字ずつ `buf` へ積むループ)が VALUE の長さに一切上限を
  設けていない不具合。TODO/既知の残課題を全項目消化済みのため自走エージェント
  が(general-purpose サブエージェントへの調査委任を経て)新規発見した項目。
  実MPD本体(gh raw で `src/song/Filter.cxx` `ExpectQuoted()` を確認、要約
  ではなく生のC++ソース)はクオート文字列を1バイトずつ `char buffer[4096]`
  へ積んでいき `length >= sizeof(buffer)`(4096バイト到達)で
  `throw std::runtime_error("Quoted value is too long")` する。この関数は
  `(TAG OP "VALUE")` 形式のフィルタ式構文専用のクオート値パーサで、
  `ParseStringFilter()`/`SongFilter::Parse()` から呼ばれ、上記コマンド群の
  ハンドラ(`DatabaseCommands.cxx`/`QueueCommands.cxx`)が全て経由する。
  例外はそのまま `ACK_ERROR_ARG`(2) としてクライアントへ返る。旧式構文
  `find TAG VALUE` の VALUE はコマンドライン全体のトークナイザ
  (`Tokenizer.cxx`)が別途処理済みの引数であり `ExpectQuoted` を通らないため
  この上限はフィルタ式構文専用(旧式構文は対象外)。BACKLOG.md 全体を
  "too long"/"4096"/"4095"/"Quoted value" で検索したが既出無く、多数ある
  フィルタ式関連パッチのいずれもVALUEの長さは扱っていないことを確認済み。
  current_playlist.py は `_query_from_mpd_filter_expression` を
  `from mopidy_mpd.protocol.music_db import ...` で直接再利用(独自複製では
  ない)しているため、music_db.py 側の1箇所を直すだけで
  playlistfind/playlistsearch/searchplaylist にも自動的に伝播する。
  verified: mpdfiltervaluelength-patch.py。クオート値抽出ループ内で1文字
  追加する都度、実MPDの `buffer[length++] = *s++; if (length >=
  sizeof(buffer)) throw` と同じタイミング(バイト追加直後)で UTF-8 バイト長
  を判定し、4096バイト到達で `exceptions.MpdArgError("Quoted value is too
  long")` を送出するよう変更(real MPD はワイヤ上の生バイト列を数えるため
  文字数ではなくUTF-8エンコード後のバイト長で判定し実MPDの挙動に近づけた)。
  実機確認(TCP 6601、mopidy-ytmusic 実アカウント): `find "(Artist ==
  \"` + "A"*5000 + `\")"`(5000バイトのクオート値)が修正前は `OK`(0件、
  無制限に受理)だったが修正後は `ACK [2@0] {find} Quoted value is too
  long` に変化することを確認。同じ5000バイト値を `search`/`count`/
  `list album (...)` でも同様にACKへ変化することを確認。`clear`+
  `findadd "(Artist == \"YOASOBI\")"` で実データを積んだ後の
  `playlistfind "(Artist == \"` + "A"*5000 + `\")"` も同様にACKへ変化し
  (current_playlist.py 経由での伝播を確認)、通常の `playlistfind
  "(Artist == \"YOASOBI\")"`(71行、YOASOBI楽曲)は無変更であることを確認。
  境界値検証: 4095バイト(`"A"*4095`)は修正前後とも `OK`、4096バイト
  (`"A"*4096`)はちょうど `ACK` に切り替わることを確認。マルチバイト文字
  混在時も UTF-8 バイト長基準で同じ閾値になることを確認(全角「あ」
  1365文字=4095バイトは `OK`、2100文字=6300バイトは `ACK`)。通常の短い
  `find "(Artist == \"YOASOBI\")"` は無変更、mopidy.log に新規
  ERROR/Traceback 0件、mopidy が正常に起動し続けることを確認。

- [x] `mopidy_mpd/network.py` の `LineProtocol.on_receive()` が受信バッファ
  `self.recv_buffer` のサイズに一切上限を設けておらず、クライアントが改行
  (`\n`)を含まない任意長のバイト列を送り続けるだけで1接続がサーバー
  プロセスのメモリを無制限に消費でき、接続も切断されない不具合。TODO/
  既知の残課題を全項目消化済みのため自走エージェントが(general-purpose
  サブエージェントへの調査委任を経て)新規発見した項目。実MPD本体(gh raw
  で `src/event/BufferedSocket.hxx` の `StaticFifoBuffer<std::byte, 8192>
  input;`(接続ごとに固定8192バイトの入力バッファ)と
  `src/event/BufferedSocket.cxx` の `ResumeInput()` を確認、要約ではなく
  生のC++ソース)は、改行未検出のまま追加データを要求する状態
  (`InputResult::MORE`)で `input.IsFull()` になった時点で
  `OnSocketError(std::make_exception_ptr(std::runtime_error(
  "Input buffer is full")))` を呼んで即座に接続を切断する。この
  `BufferedSocket` は `src/client/Client.hxx` が `FullyBufferedSocket`
  経由で継承しており、MPDのテキストプロトコル接続(`Client`)全てに適用
  される制限であることも確認済み。BACKLOG.md 全体を
  "recv_buffer"/"LineProtocol"/"parse_lines"/"Input buffer" で検索した
  ところ、`network.py`/`LineProtocol` に対する既存パッチは
  `mpdrecvhalt-patch.py`(同一 `recv()` チャンク内の後続行処理を打ち切る
  CSRF対策の穴)と `mpdencodeguard-patch.py`(`encode()` の UnicodeError
  時の None 伝播)の2件のみで、いずれも受信バッファの上限とは無関係の
  別種の不具合であり本項目は既出無しと確認した。
  verified: mpdrecvbufcap-patch.py。実MPDと同じ `_MAX_RECV_BUFFER_SIZE =
  8192` をモジュールレベルに追加し、`on_receive()` の `parse_lines()`
  ループ後(そのチャンクで切り出せる完全な行を全て処理し終えた後)、改行
  の来ない残りの `recv_buffer` がこの上限を超えていれば
  `self.connection.stop("Input buffer is full")` で切断するよう変更。
  ループの前ではなくループの後で判定することで、1回の `recv()` チャンク
  に正規のコマンド行と改行無しの巨大な残りバイト列が両方含まれる場合でも
  先行する正規コマンドはまず処理される。実機確認(TCP 6601、生ソケット):
  改行を含まない8192バイトちょうどの送信では接続が維持され続ける
  (`OK`/切断どちらも起きない、real MPDの `IsFull()` 境界と同じ「満杯
  未満は継続」)一方、8193バイト(1バイト超過)では即座に接続が切断
  (recv() が EOF を返す)されることを確認し、境界がちょうど8192/8193で
  切り替わることを確認。修正前はこの上限が無いため20000バイトの改行無し
  データを送信しても接続がREADY状態のまま維持され続けることも確認済み。
  通常のMPDコマンド行(`status`/`tagtypes`/`find "(Artist ==
  \"YOASOBI\")"` 等、数十〜数百バイト)は全て無変更で正常応答することを
  回帰確認、mopidy.log に新規ERROR/Traceback 0件、mopidy が正常に起動し
  続けることを確認。

- [x] `mpdauthtabsplit-patch.py` がBACKLOG.md上は「実装済み」と記録されて
  いたにもかかわらず、実際にビルドされたソース上では対象の
  `MpdDispatcher._authenticate_filter()` が一切書き換わっておらず、
  修正が謳っていたタブ区切りコマンド認証バイパス不具合(`[mpd] password`
  設定時、未認証接続が `password\tXXX`(タブ区切り)を送るとコマンド名が
  `request.split(" ")[0]` により `"password\tXXX"` という未知トークン
  扱いになり、`protocol.commands.handlers.get()` が None を返して
  `auth_required=False` 判定に到達できず永久に
  `ACK you don't have permission for ...` で拒否され続ける)が未修正の
  まま残っていた不具合。TODO/既知の残課題を全項目消化済みのため自走
  エージェントが(general-purposeサブエージェントへの調査委任を経て)
  BACKLOG.md自身の過去記録を再監査して発見した項目(過去記録を鵜呑みに
  せず実ビルド済みソースで裏取りする手法)。
  原因: `mpdauthtabsplit-patch.py` の冪等性チェックが
  `if NEW in s: skip`(`NEW = '            command_name = re.split(r"\s+", request, 1)[0]\n'`
  という置換後リテラルがファイル全体のどこかに存在するだけでスキップ)
  という設計だったため、`nix/lib/mopidy-env.nix` でこのパッチより先に
  登録されている `mpdcmdlistidleclose-patch.py` が同じ `dispatcher.py`
  の別関数 `_command_list_filter()` へ全く同一のリテラル行を偶然挿入
  していたことにより、`mpdauthtabsplit-patch.py` 実行時には既にこの
  文字列がファイル中に(別関数の中に)存在し、`_authenticate_filter()`
  自体は一度も書き換えられないまま常に「既にパッチ済み、skip」と誤判定
  されていた。実機確認(ビルド済みenvの `mopidy_mpd/dispatcher.py` を
  直接grep)で、`_authenticate_filter()` 内(95行目)が
  `command_name = request.split(" ")[0]` のまま未修正で残っている一方、
  `_command_list_filter()` 内(106行目、`mpdcmdlistidleclose-patch.py`
  由来)は `re.split(r"\s+", ...)` に既に修正済みという非対称を確認し、
  `OLD count=1`/`NEW in s: True` (誤スキップ条件が真であること)を
  python上でも再現確認した。
  修正: `mpdauthtabsplit-patch.py` の冪等性判定を `if NEW in s: skip`
  から `if OLD not in s: skip` に変更。`OLD = '            command_name = request.split(" ")[0]\n'`
  は `_authenticate_filter()` 内にのみ出現する行であり、このパッチが
  書き換えるべき1箇所を正確に指すため、ファイル全体を巻き込む
  誤検出が起きない。
  verified: 実機確認(TCP 6601)。まず `/tmp` にビルド済み
  `mopidy_mpd` を分離コピーし修正版パッチを単体適用、
  `_authenticate_filter()` の該当行が `re.split(r"\s+", ...)` に
  正しく書き換わること・`ast.parse` で構文が壊れないこと・2回目実行が
  正しく「既にパッチ済み、skip」になる(冪等)ことを確認。次に
  `~/ai/mopidy-dev/mopidy-dev.conf` の `[mpd]` に一時的に
  `password = testpass123` を追加して `build-run.sh` で実ビルド・
  実起動し、修正前は `password\ttestpass123`(タブ区切り)を送ると
  `ACK you don't have permission for "password"` になっていたはずの
  ところ、修正後は `password\ttestpass123` → `OK`(認証成功)、
  認証後の `status` も正常応答することを確認。誤ったパスワードを
  タブ区切りで送った場合は `ACK [3@0] {password} incorrect password`
  (実際のパスワード認証ハンドラに到達している証拠)になることも確認。
  既存のスペース区切り `password "testpass123"` は無変更で `OK`、
  未認証時の `status`/`ping`(space区切り、auth_required=False)も
  無変更で規定通り動作することを回帰確認。テスト後 `mopidy-dev.conf`
  を元の(password未設定)状態に戻し再ビルド・再起動し、通常運用時
  (パスワード認証無効)の未認証 `status` が引き続き正常応答すること・
  mopidy.log に新規ERROR/Traceback 0件・mopidy が正常に起動し続ける
  ことを確認。

- [x] find/search/count/searchcount/findadd/searchadd/searchaddpl/list
  (music_db.py) / playlistfind/playlistsearch (current_playlist.py) /
  sticker find (stickers.py) / searchplaylist (stored_playlists.py) が
  共有・独自実装している末尾修飾子キーワード `sort`/`window`/`group`/
  `position` の判定が `params[-2].lower() == "sort"` のように `.lower()`
  で大文字小文字を無視して行われており、`SORT`/`Window`/`GROUP`/
  `Position` 等どんな大文字小文字の組み合わせでも修飾子として誤って
  受理してしまう不具合(4ファイル計12箇所)。TODO/既知の残課題を
  全項目消化済みのため自走エージェントが(general-purposeサブエージェント
  への調査委任を経て)新規発見。
  実MPD本体(gh rawで src/util/StringAPI.hxx StringIsEqual() [strcmpベースの
  大文字小文字を区別する比較、大文字小文字を無視する版はStringIsEqualIgnoreCase()
  として別に存在]、src/command/DatabaseCommands.cxx ParseDatabaseSelection()
  [find/search系 sort/window]・handle_list() [window/group]・
  handle_count_internal() [group]・ParseQueuePosition()/ParseInsertPosition()
  [findadd/searchadd/searchaddplのposition]、src/command/StickerCommands.cxx
  [sticker findのsort/window]、src/command/PlaylistCommands.cxx
  handle_searchplaylist() [window] を確認)はこれら修飾子キーワードの
  判定に例外なくStringIsEqualを使っており、修飾子として認識されるのは
  小文字リテラル完全一致のときのみ。剥がされなかったトークンはそのまま
  フィルタ式/引数パーサに渡り、未知タグ・引数エラーとしてACKになる。
  一方、修飾子の後に続くTYPE側(sort TYPEのDB系タグ名解決)は
  ParseSortTag()/tag_name_parse_i()がStringIsEqualIgnoreCase/大文字小文字
  非依存であり、これは既存のmopidy_mpd実装(`_SORT_MAPPING.get(type_.lower())`
  等)と一致している。ズレているのはキーワード自身の判定のみ。
  BACKLOG.mdをgrepで確認したが、mpdsortwindoworder-patch.py/
  mpdpfsortwindoworder-patch.py(sort/windowの順序・重複)を含む既存の
  sort/window/group/position関連パッチはいずれも「値の種類」「順序」
  「個数上限」は検証済みでも「キーワード自身の大文字小文字」は未着手
  だったことを確認。
  修正: mpdmodifierkeywordcase-patch.py。同一原因(キーワード比較への
  誤った`.lower()`適用)・同一修正形(`.lower()`を削除するだけ)が
  sort/window/group/positionの4種の修飾子・4ファイル・計12箇所に
  横展開されていたため、mpdmetapositivetrust-patch.pyと同様に1パッチで
  まとめて修正。
  verified: 実機確認(TCP 6601、mopidy-ytmusic実アカウント、findadd後の
  実キュー/save後の実プレイリストあり)。修正前は全てOKだった以下が
  修正後は全てACK(未消費トークンがフィルタ/引数パーサへ渡った結果の
  ACKのためコマンドにより文言は異なる)に変化することを確認:
  `find "(Artist == \"YOASOBI\")" SORT Artist`/`WINDOW "0:1"`/
  `count "(Artist == \"YOASOBI\")" GROUP artist`/
  `findadd "(Artist == \"YOASOBI\")" POSITION "0"` →
  `ACK [2@0] incorrect arguments`、`list Album Group Artist` →
  `ACK [2@0] Unknown filter type`、
  `playlistfind "(Artist == \"YOASOBI\")" Sort Artist`/
  `searchplaylist NAME "(Artist == \"YOASOBI\")" Window "0:1"` →
  `ACK [2@0] incorrect arguments`、
  `sticker find song "" rating Window "0:1"` →
  `ACK [2@0] Unknown sticker operator: Window`(Windowが修飾子として
  認識されずop/op_value解釈に落ちた結果、これも未消費トークンが後続
  パーサでエラーになる想定通りの経路)。小文字の`sort`/`window`/
  `group`/`position`は前後で無変更(実データ返却)であることを回帰
  確認、`status`/`tagtypes`/`ping`も無変更。mopidy.log新規
  ERROR/Tracebackはテスト用`save`コマンドがYTMusic API認証(401、
  この検証用playlist作成に固有のdev環境既知制限、本パッチとは無関係)
  で1件失敗した以外0件、mopidyが正常に起動し続けることを確認。

- [x] `mopidy_mpd/tokenize.py` の `split()` がコマンド名自体のトークナイズ
  失敗時(先頭が`[a-z][a-z0-9_]*`にマッチしない、または行頭に空白が
  ある)に投げる `MpdUnknownError("Invalid word character")` /
  `("Letter expected")` がどちらも `command` 引数を省略しており、
  `exceptions.MpdAckError.__init__()` のデフォルト `command=None` の
  まま例外が生成される不具合。TODO/既知の残課題を全項目消化済みの
  ため自走エージェントが(general-purposeサブエージェントへの調査
  委任を経て)新規発見。
  `dispatcher.py` の `_call_handler()` は
  `tokens = tokenize.split(request)` (try節の外でここが例外送出源)、
  続く `try: return protocol.commands.call(tokens, ...)` の
  `except MpdAckError as exc: if exc.command is None: exc.command = tokens[0]`
  という補完コードはコマンド名のトークナイズ自体は成功した後続エラー
  (引数エラー等)専用の救済でしかなく、`tokenize.split()` 自身が
  投げた例外はこの補完を一切通らない。結果、`MpdAckError.get_mpd_ack()`
  の `f"{{{self.command}}}"` が `None` をそのまま文字列化し、ACK応答
  に文字通り `{None}` というPython内部表現が漏れる。
  実MPD本体(gh rawで `src/client/Response.hxx` の
  `const char *command = "";`[コマンド名判明前のデフォルトは空文字列]、
  `src/client/Response.cxx` `Error()` の
  `Fmt("ACK [{}@{}] {{{}}} ", code, list_index, command)` を確認)は
  コマンド名判明前のトークナイズエラーでも `command` は空文字列のまま
  であり、`{None}` のような内部実装の漏洩は起きない。mopidy_mpd自身も
  空行(No command given)の場合は `MpdNoCommand.__init__` が
  `kwargs["command"] = ""` を明示注入しており(同じ関数内、同種の
  トークナイズ前エラー)正しく `{}` と表示されるため、この2箇所だけが
  既存の慣習から外れていた。
  BACKLOG.md全体を `{None}`/`command=None`/`Invalid word character`/
  `Letter expected` で検索したが既出無しと確認。
  修正: mpdtokenizecommandnone-patch.py。該当2箇所の `raise` に
  `command=""` を明示指定(`MpdNoCommand` と同じ流儀)。
  `dispatcher.py` 側は変更不要。
  verified: 実機確認(TCP 6601)。`sta$tus\n`(先頭は小文字sで
  session.pyのCSRFガード`line[0].islower()`を通過するが`$`が
  `WORD_RE`にマッチしない)を送ると、修正前は
  `ACK [5@0] {None} Invalid word character`(オフラインでの単体
  パッチ適用前後比較・`MpdAckError.__init__`のデフォルト`command=None`
  経由で再現を確認)だったのが、修正後は実機で
  `ACK [5@0] {} Invalid word character` に変化することを確認。
  なお行頭空白(` status\n`)を使う `Letter expected` 経路は
  `session.py`のCSRFガード(`line[0].islower() and line[0].isalpha()`)
  が行頭空白の行を`tokenize.split()`に渡す前に切断するため、TCP
  経由では現状到達不能と判明(コード自体は`tokenize.py`内に実在し
  直接呼び出し等では到達しうるため、同一関数内の対称性を保つため
  同じ修正を適用)。回帰確認: 未知コマンド`nosuchcommand`は
  `ACK [5@0] {} unknown command "nosuchcommand"`(`tokens[0]`補完
  経由、無変更)、既存の引数エラー`find "unterminated`(quote未閉じ)
  は`ACK [2@0] {find} Missing closing '"'`(`MpdArgError`が
  `command=command`を明示設定済みのため無変更)、正常系`status`も
  無変更で正しく応答することを確認。mopidy.log新規ERROR/Traceback
  0件、mopidyが正常に起動し続けることを確認。

- [x] `mopidy_mpd/dispatcher.py` の `MpdDispatcher.command_list`
  (`command_list_begin`/`command_list_ok_begin` 〜 `command_list_end` の
  間に蓄積される、まだ実行されていないコマンド文字列のPythonリスト)に
  一切サイズ上限が設けられていない不具合。TODO/既知の残課題を全項目
  消化済みのため自走エージェントが(general-purposeサブエージェントへの
  調査委任を経て)新規発見。
  `mpdrecvbufcap-patch.py`(実MPDのBufferedSocket、固定8192バイトの
  「1行分の受信バッファ」上限)とは別レイヤの不具合: 改行区切りの
  正規のコマンド行を `command_list_begin` 〜 `command_list_end` の間に
  大量に送り続けるだけで、個々の行はrecv_bufferの8192バイト制限を
  毎回クリアしたまま `self.command_list` へ無条件に `append()` され
  続け、`command_list_end` が届く(またはクライアントが接続を維持する
  限り永遠に届かない)まで、サーバー側メモリが無制限に伸び続ける。
  実MPD本体(gh rawで直接ソースを取得して確認、WebFetch要約に頼らず):
  - `src/client/Config.cxx`: `CLIENT_MAX_COMMAND_LIST_DEFAULT (2048*1024)`
    (デフォルト2MiB、config key `max_command_list_size` で変更可能、
    `client_max_command_list_size` にバイト単位で格納)。
  - `src/command/CommandListBuilder.cxx` `CommandListBuilder::Add()`:
    `size_t len = strlen(cmd) + 1; size += len; if (size > client_max_command_list_size) return false;`
    — 1行ごとに `strlen+1` バイトを累積し、上限超過で追加を拒否。
  - `src/client/Process.cxx` `Client::ProcessLine()`:
    `if (!cmd_list.Add(line)) { FmtWarning(..., "command list size is larger than the max ({})", ...); return CommandResult::CLOSE; }`
    — ACKは一切送らず、警告ログのみ出してその場で接続を切断する
    (`CommandResult::CLOSE` は `src/client/Read.cxx` の
    `OnSocketInput()` 経由で `Close()` を呼ぶ)。
    `mpdcmdlistidleclose-patch.py` がlist内idle/noidleに対して既に
    確立済みの「ACK無し・即座に`session.close()`」と同じ挙動パターン。
  BACKLOG.md全体を `max_command_list`/`command_list_size`/
  「コマンドリスト」の サイズ/上限 で検索したが既出無しと確認。
  修正: mpdcmdlistsizecap-patch.py。`dispatcher.py` にモジュールレベル
  定数 `_MPD_MAX_COMMAND_LIST_SIZE = 2048 * 1024`(実MPDのデフォルトと
  同値)を追加し、`MpdDispatcher.__init__()` で `self.command_list_size = 0`
  を初期化。`command_list.py` の `command_list_begin()`/
  `command_list_ok_begin()` でも同様に0へリセットする。
  `_command_list_filter()` でlist受信中の各行を `self.command_list` へ
  appendする前に `len(request.encode("utf-8")) + 1`(実MPDの
  `strlen+1` と同じUTF-8バイト数基準。`mpdstrictnumparse-patch.py`/
  `mpdwindowstrict-patch.py` 以来の「Pythonの文字数ベースではなく
  実MPDのバイト数ベースに合わせる」既存方針を踏襲)を
  `command_list_size` へ加算し、上限を超えたらidle/noidleと全く同じ
  `self.context.session.close(); return []` で切断する。
  verified: 実機確認(TCP 6601、生ソケット)。改行終端の短いコマンド行
  (`ping\n` を大量に連結)を `command_list_begin` の後に
  `command_list_end` を送らず合計約2,120,000バイト(2MiB超)まで
  送り続けたところ、修正前は接続が維持され続けていたのに対し、
  修正後は閾値超過後に無応答のまま切断される(ソケットが
  `ConnectionResetError`/EOFを返す)ことを確認。回帰確認: 通常サイズの
  `command_list_begin`/`status`/`ping`/`command_list_end` および
  `command_list_ok_begin`(`list_OK` 応答含む)は前後で無変更に完走、
  上限未満(500,000バイト)のcommand_listも正常に `OK` で完走、
  既存のlist内idle/noidle即時切断(`mpdcmdlistidleclose-patch.py`)も
  無変更に動作、`status`/`tagtypes` も無変更。mopidy.log新規
  ERROR/Traceback 0件、mopidyクリーン起動を確認。

- [x] 非推奨コマンド `playlist`(引数なし、`current_playlist.py`)が
  `playlistinfo` へそのまま委譲しており、タグ・時間等の詳細メタデータを
  丸ごと返してしまう不具合。TODO/既知の残課題を全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を
  経て)新規発見。実MPD本体(gh rawで `src/command/QueueCommands.cxx`
  `handle_playlist()` / `src/PlaylistPrint.cxx` `playlist_print_uris()`
  / `src/queue/Print.cxx` `queue_print_uris()` / `src/SongPrint.cxx`
  `song_print_uri()` を確認)はこの非推奨コマンドを
  `POS:file: URI` のみの1行/曲(タグ一切無し)で返す。BACKLOG.md全体を
  `"def playlist(context)"`/`queue_print_uris`/`playlist_print_uris`/
  "旧式"/"レガシー" 等で検索したが既出無しと確認(ヒットしたのは
  stickernamestypesのTYPE="playlist"やidleサブシステム"playlist"の
  誤発火など無関係な既知修正のみ)。修正: mpdplaylistlegacyformat-
  patch.py。`current_playlist.py` の `playlist(context)` を、
  `listplaylist()` と同種の「URIのみ」出力(`pos:file: uri`)へ置き換え。
  verified: 実機確認(TCP 6601、mopidy-ytmusic実アカウント、
  `searchadd "(any contains \"YOASOBI\")"` で2曲キュー投入)。修正前は
  `playlist` と `playlistinfo` が完全に同一のArtist/Title/Time等を
  含む詳細出力を返していたのが、修正後は `playlist` のみ
  `0:file: ytmusic:track:...` `1:file: ytmusic:track:...` の2行
  (タグ無し)に変化、`playlistinfo` は無変更であることを確認。回帰確認:
  空キュー時の `playlist` (`OK`のみ、無変更)、`status`/`ping`/
  `tagtypes` 無変更。mopidy.log新規ERROR/Traceback 0件、mopidyクリーン
  起動を確認。

- [x] `next` が一時停止中(`state: pause`)に送られても再生状態をそのまま
  保持してしまい、曲だけ切り替わって無音のまま一時停止状態を維持してしまう
  不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。mopidy
  core本体(`mopidy/core/playback.py` `PlaybackController.next()`)は自身の
  docstringに"The current playback state will be kept. If it was playing,
  playing will continue. If it was paused, it will still be paused, etc."
  と明記する設計。実MPD本体(gh rawで`src/queue/PlaylistControl.cxx`
  `playlist::PlayNext()` -> `PlayOrder()` -> `src/player/Control.cxx`
  `PlayerControl::Play()`を確認)は次の曲が実在する限り必ず`PlayOrder()`
  経由で`Play()`を呼び、`Play()`は
  `if (state == PlayerState::PAUSE) PauseLocked(lock);`
  で一時停止中だった場合は無条件に解除して再生を再開する。つまり実MPDの
  `next`/`previous`はどちらも「常に再生を再開する」動作であり、mopidy
  coreの「状態を保持する」という設計自体が実MPD仕様と逆。この非対称は
  既に`previous`側だけ`mpdpreviousrepeat-patch.py`の副産物(random無効時に
  `context.core.playback.play(tl_track)`という常にPLAYINGを強制する経路へ
  書き換え済み)で直っており、`next`側は素の
  `context.core.playback.next().get()`のまま残っていた。BACKLOG.md全体を
  `keep_state_on_song_change`/`next_keep_state`/`unpause it`/
  `previous.*pause`/`next.*pause` 等で検索したが既出無しと確認(previous
  のrepeat/consume折り返し不具合を扱った既存項目はpause保持の非対称自体
  には一切言及していないことを確認済み)。修正: mpdnextresumepause-
  patch.py。`next_(context)`呼び出し直前の状態がPAUSEDだった場合のみ記録
  しておき、`next()`実行後もなおPAUSEDのまま(次の曲が実在しbackend側が
  pauseを維持したケース)であれば`context.core.playback.resume()`で明示的
  に再開する。キュー末尾で`self.stop()`経由のSTOPPEDへ落ちた場合(実MPDの
  `PlayNext()`もこのケースのみ`PlayOrder()`を経由せず`Stop()`を呼ぶ)は
  ガード条件を満たさず`resume()`は呼ばれない。
  verified: 実機確認(TCP 6601、mopidy-ytmusic実アカウント、
  `searchadd "(any contains \"YOASOBI\")"` で2曲キュー投入)。`play "0"`
  ->`pause 1`->`status`で`state: pause`確認->`next`->修正前は`status`が
  `song: 1`(曲は切り替わっている)なのに`state: pause`のまま(実際に無音)
  だったのが、修正後は`song: 1`かつ`state: play`へ正しく遷移することを
  確認。同一状態から`previous`を送ると修正前後とも`state: play`へ正しく
  戻ることも確認し、修正前のnext/previousの非対称を直接確認した。回帰
  確認: 完全停止中(`state: stop`)の`next`は修正後も`ACK [55@0] {next}
  Not playing`のまま不変(`mpdnextprevstopguard-patch.py`のガード無変更)、
  再生中(`state: play`)の`next`は修正後も`state: play`のまま不変、
  キュー末尾で一時停止中に`next`を送ると`state: stop`へ正しく遷移(誤って
  `state: play`へ復活しないことを確認)、`previous`が一時停止中に再開する
  既存挙動は無変更、`ping`/`tagtypes`無変更。mopidy.log新規ERROR/
  Traceback 0件、mopidyクリーン起動を確認。

- [x] 非推奨の相対 `volume {CHANGE}` (mopidy_mpd/protocol/playback.py) が、
  クランプ後も音量に変化が無い no-op (`change=0`、あるいは既に 0/100 に
  張り付いていて相対変化がクランプで吸収されるケース) でも常に
  `context.core.mixer.set_volume(new_volume)` を無条件に呼んでしまう
  不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (general-purpose サブエージェントへの調査委任を経て) 新規発見した項目。
  実MPD本体 (MusicPlayerDaemon/MPD、raw curl で src/command/
  OtherCommands.cxx `handle_volume()` を直接確認) は
  `new_volume != old_volume` の場合のみミキサー書き込みと
  `partition.EmitIdle(IDLE_MIXER)` を行う (兄弟コマンド `handle_setvol()`
  にはこのガードが無く常に書き込む非対称もあわせて確認、`volume`
  相対指定コマンド固有の挙動)。dev環境が使う `mopidy/audio/actor.py`
  `SoftwareMixer.set_volume()` は値が変わったかどうかに関係なく
  `trigger_volume_changed()` を無条件に呼ぶため、mopidy_mpd 側は値が
  全く変化していないのに `volume_changed` core イベント経由で
  `changed: mixer` の idle 通知を誤発火させていた
  (mpdidlemixerpartition-patch.py が対処した「パーティション越しに漏れる」
  問題とは別軸で、同一パーティション内であっても無駄な起床が起きる)。
  BACKLOG.md 全体の既存 volume 関連項目 (mpdvolumerace/
  mpdvolumepartition/mpdsetvolrange/mpdgetvol/mpdstatusvolumeomit/
  mpdidlemixerpartition) はレース・パーティション所有・範囲外
  バリデーション・空応答条件・パーティション越し idle 漏れのみを扱って
  おり、本件 (同一パーティション内での no-op 時の idle 抑制) は
  未対応と確認した。
  verified: mpdvolumenoopidle-patch.py。mpdvolumepartition-patch.py が
  既に書き換えた `volume()` 本体の `new_volume = min(max(0, old_volume +
  change), 100)` 算出直後に、実MPDと同じ `new_volume != old_volume`
  ガードを追加し、no-op時は `set_volume()` を呼ばず `success = True`
  (変化なしも成功扱い) とした。適用前にビルド済みソースを `/tmp` へ
  隔離コピーしパッチを当ててから `ast.parse()` で構文確認、2回連続適用
  でも冪等 (2回目は "already applied, skip") であることを確認済み。
  実機確認 (TCP 6601、2接続 A/B、mopidy-ytmusic実アカウント):
  `setvol 50` で基準値を設定後 B の `idle mixer` で先行イベントを
  drain、再度 `idle mixer` 購読した状態で A が `volume 0` (50+0=50の
  真の no-op) を送信すると、修正前は B が誤って `changed: mixer` で
  起床していたはずが、修正後は起床しないことを確認 (`getvol` も
  前後で50のまま不変)。直後に同じ B の購読で A が `volume +10`
  (50→60の実際の変化) を送信すると正しく `changed: mixer` で起床する
  ことも確認 (`getvol` は60に変化)、no-op 抑制が実際の変化検知を
  壊していないことを確認。回帰確認: `setvol` は実MPD同様ガード無しの
  ままで、同一値への `setvol 60` (no-op) でも変わらず `changed: mixer`
  が発火すること (real MPD の非対称どおり) を確認、`status`/`tagtypes`
  無変更、mopidy.log新規ERROR/Traceback 0件、mopidyクリーン起動を確認。

- [x] `list {TYPE} [FILTER] group {GROUPTYPE} group {GROUPTYPE} ...`
  のように `group` 修飾子を2組以上連鎖させた場合、mopidy_mpd
  (`_mpd_extract_group_params`/`_mpd_list_grouped`、music_db.py、
  mpdlist-patch.py 由来) が実MPDと逆順にネスト階層を組んでしまう不具合。
  TODO全項目消化済みのため自走エージェントが (general-purpose
  サブエージェントへの調査委任を経て) 新規発見した項目 (1回目の候補
  `searchplaylist` の `window` 修飾子境界条件は rmpc 本体のRustソースを
  `git clone` して `grep` した結果 `searchplaylist` という文字列が
  一切存在せず実害が理論上/到達不能と判断し不採用、2回目の調査で
  rmpc が実際に発行するコマンド経路に絞り込んで本件を発見)。実MPD本体
  (gh raw で `src/command/DatabaseCommands.cxx` `handle_list()` を確認)
  の group ループ:
  ```
  while (args.size() >= 2 && StringIsEqual(args[args.size() - 2], "group")) {
      tag_types.emplace_back(group);   // 末尾から剥がしつつ「末尾に追加」
      args.pop_back(); args.pop_back();
  }
  tag_types.emplace_back(tagType);
  ```
  末尾から剥がした順 (ワイヤ上最後の group 句が最初に剥がされる) に
  `emplace_back` (末尾追加) するため、`list Album group AlbumArtist
  group Date` は `tag_types = [Date, AlbumArtist, Album]` になる。
  `src/db/DatabasePrint.cxx` `PrintUniqueTags()` は `tag_types.front()`
  を最外周として使い以降 `subspan(1)` で再帰的に内側へ潜るため、実MPD
  での実際のネスト順は Date (最外周) → AlbumArtist → Album (最内周)。
  一方 mopidy_mpd の `_mpd_extract_group_params` は同じく末尾から剥がす
  が `groups.insert(0, field)` (先頭挿入) のため、剥がした順がそのまま
  ワイヤ上の記述順 (先頭が先) に戻ってしまい `groups = [AlbumArtist,
  Date]` になる。`_mpd_list_grouped()` は `groups[0]` を最外周として
  使うため、mopidy での実際のネスト順は AlbumArtist (最外周) → Date →
  Album (最内周) と実MPDと完全に逆順になる。rmpc本体
  (github.com/mierak/rmpc を `git clone --depth 1` して確認) の
  `rmpc-mpd/src/mpd_client.rs` `send_list_tag_grouped()`/
  `rmpc/src/ui/panes/tag_browser.rs` `queue_root_fetch()` が
  `self.tags[0].group_by.len() > 1` のとき実際に複数の `group` 句を
  連結して `list TAG group G1 group G2` を発行する経路として実装・
  テスト済み (`tag_browser.rs` 内の `grouped_album_sorted_by_date_tag()`
  テストフィクスチャが `group_by` 3段構成を検証) であることを確認して
  おり、ユーザが Browser ペインの `group_by` を3段以上に設定すると
  到達するrmpc互換上の実在ギャップと判断した。BACKLOG.md 全体を
  `insert(0` や group のネスト順序等で検索したが既出無し。
  `mpdlistgroupconflict-patch.py` (group 列同士の重複検出)・
  `mpdlistgroupfile-patch.py` (`group file`/`filename` の拒否) は本件とは
  別軸で無関係、`mpdcountsinglegroup-patch.py` 導入により count/
  searchcount は単一 group のみ (順序が問題になり得ない) のため対象外、
  影響は list のみ。
  verified: mpdlistgroupnestorder-patch.py。この dev アカウントの
  YTMusic 保存済みライブラリが `stats` で `artists: 0 albums: 0 songs: 0`
  と完全に空で、`list`/`get_distinct` はライブラリ (検索結果ではなく
  saved library) に依存するため実データでの目視確認は不可
  (既知の環境制約、過去の `modified-since` 検証等と同じ理由)。そのため
  実際にビルド・デプロイされた `_mpd_extract_group_params()` を
  (`/tmp` へ隔離コピーしパッチ適用、`ast.parse()` で構文確認、2回連続
  適用でも "already applied, skip" で冪等なことを確認した上で) 直接
  実行し、`params=["group","albumartist","group","date"]` に対し修正後は
  `groups=['date','albumartist']` を返すこと、および実MPDの
  pop末尾+`emplace_back`(末尾追加)アルゴリズムをそのまま再現した対照
  ロジックが同じ `['date','albumartist']` を返すことを確認し両者が
  一致することを検証した (修正前の未パッチ site-packages 上の同関数は
  `['albumartist','date']` で不一致だったことも対照確認済み)。rmpc の
  3段 `group_by` 構成 (`group artist group albumartist group date`)
  相当の3組連鎖でも修正後 `['date','albumartist','artist']` が実MPD
  再現ロジックと一致することを確認。実機確認 (TCP 6601、
  mopidy-ytmusic実アカウント): dev mopidy をビルド・起動しクリーンに
  起動すること (mopidy.log 新規ERROR/Traceback 0件) を確認した上で、
  `list Album group AlbumArtist group Date`/3組連鎖/単一 group
  (`list Album group AlbumArtist`) がいずれも (ライブラリ空のため0件
  ではあるが) ACK にならず `OK` を返すこと (回帰なし) を確認、既存の
  `list Album group Album` (Conflicting group)/`list Album group file`
  (Unknown tag type)/`count group artist group album` (incorrect
  arguments) のACK挙動が全て無変更であることも確認。

- [x] `crossfade`/`mixrampdb`/`mixrampdelay`(mpdcrossfade-patch.py/
  mpdmixramp-patch.py)と`replay_gain_mode`(mpdreplaygain-patch.py)が、
  translator.py上で単なるプロセス全体共有のグローバル変数として実装されて
  おり、`newpartition`(mpdpartition-patch.py)で作った複数パーティション間で
  値が漏れてしまう不具合。TODO/既知の残課題を全項目消化済みのため自走
  エージェントが(general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawで確認): src/command/PlayerCommands.cxx
  handle_crossfade/handle_mixrampdb/handle_mixrampdelayはいずれも
  `client.GetPlayerControl().SetXxx(...)`を呼び、src/Partition.hxx
  (`PlayerControl pc;`)の通りPlayerControlはパーティション毎に独立した
  インスタンスを持つ。handle_replay_gain_modeも`partition.SetReplayGainMode
  (new_mode)`を呼び、src/Partition.hxx(`ReplayGainMode replay_gain_mode`)の
  通りreplay_gain_mode自体がPartitionインスタンス自身のメンバであり、
  SetReplayGainMode()は自パーティションのみを書き換える(mpdreplaygain-
  patch.py導入時の既存コメント「実MPDのReplayGainModeもプロセス全体で共有
  される」は実MPDソース未確認のまま書かれた誤りだったと判明)。
  BACKLOG.md全体をcrossfade/mixramp/replay_gain/パーティションの組み合わせ
  で検索したが、mpdvolumepartition-patch.py/mpdoutputpartition-patch.py/
  mpdidlemixerpartition-patch.pyはmixer(音量)/output(出力)のパーティション
  所有権のみを扱っており、crossfade/mixramp/replay_gain_modeの値そのものが
  パーティション毎に独立していない件は未対応・未blockedと確認。
  修正: mpdplayercontrolpartition-patch.py。mpdpartition-patch.pyの
  _session_partition/_output_partitionと同じ「パーティション名をキーとする
  辞書」方式に4値を変更し、set_/get_の各関数へpartition引数(既定値
  "default")を追加。playback.py側の各ハンドラは
  `translator.partition_get(id(context.session))`
  (mpdvolumepartition-patch.pyと同じパターン)で自セッションの所属
  パーティション名を取得しset_/get_へ渡す。delpartition(mpdpartitiondel
  toctou-patch.pyのpartition_try_delete())で不要になったパーティションの
  エントリを各辞書から削除しメモリリークを防ぐ。
  verified: 実機確認(TCP 6601、mopidy-ytmusic実アカウント、2接続
  A(default)/B(newpartition zoneXへ切替))。A側で`crossfade 15`/
  `mixrampdb -10.5`/`mixrampdelay 2.5`/`replay_gain_mode track`を実行後、
  修正前はB側の`status`/`replay_gain_status`に`xfade: 15`/
  `mixrampdb: -10.5`/`mixrampdelay: 2.5`/`replay_gain_mode: track`が
  漏れて表示されていたのが、修正後はB側の`status`にxfade/mixrampdelay行が
  出ず`mixrampdb: 0.0`のまま(既定値、mpdxfadezero-patch.py/mpdmixramp-
  patch.pyの既存条件付き出力ロジックと整合)、`replay_gain_status`も
  `replay_gain_mode: off`のまま無変更であることを確認。A側は引き続き
  設定値通り(`xfade: 15`/`mixrampdb: -10.5`/`mixrampdelay: 2.5`/
  `replay_gain_mode: track`)反映されることも確認。`delpartition zoneX`後に
  `newpartition zoneX`で再作成したパーティションが既定値(xfade/mixrampdelay
  行無し、mixrampdb: 0.0)に戻ることも確認(delpartition時の辞書クリーン
  アップが機能)。`status`/`ping`/`tagtypes`/`listpartitions`の既存挙動に
  回帰無し、mopidy.log新規ERROR/Traceback 0件。
  **既知の残課題(スコープ外)**: 上記4値の変更が発火するidle "options"通知
  (mpdcrossfadeidle-patch.py/mpdreplaygain-patch.pyの
  `_mpdcrossfadeidle_notify`/`_mpdreplaygain_notify`)は本パッチでは無条件に
  全パーティションへbroadcastされるままで未対応。repeat/random/single/
  consumeはmopidy coreの単一tracklistを全パーティションが共有するため元々
  どのパーティションからも見えるべき値だが、同じ"options"通知に相乗りする
  crossfade/mixramp/replay_gain_modeの変更だけを選択的にパーティション限定
  配送するには、mpdidlemixerpartition-patch.pyと同種の個別配送機構
  (`_session_actor_refs`経由のProxyCall直接tell())が別途必要。値自体の
  漏洩(本項目が修正したstatus/replay_gain_statusの実害)とは別軸の問題の
  ため、将来セッションの独立項目として残す。

- [x] 直上の項目(mpdplayercontrolpartition-patch.py)が残した既知の残課題を
  解消。`crossfade`/`mixrampdb`/`mixrampdelay`(mpdcrossfadeidle-patch.py)/
  `replay_gain_mode`(mpdreplaygain-patch.py)の変更が発火するidle "options"
  通知が、値自体はパーティション毎の辞書に分離済み(直上の項目)なのに
  通知だけ`mopidy.listener.send(MpdSession, "options")`による無条件全
  パーティションbroadcastのままだった不具合。TODO/既知の残課題を全項目
  消化済みのため自走エージェントが直上の項目自身の残課題コメントを起点に
  新規着手。
  実MPD本体(gh rawで再確認): src/command/PlayerCommands.cxx
  handle_crossfade/handle_mixrampdb/handle_mixrampdelay/
  handle_replay_gain_modeはいずれも`partition.EmitIdle(IDLE_OPTIONS)`を
  呼び、`Partition::EmitIdle`は自パーティションのidle_monitorのみを操作する
  (mpdidlemixerpartition-patch.pyがmixer/outputで既に確認済みのPartition::
  EmitIdleと同一機構)。一方repeat/random/single/consume
  (`_mpdoneshotidle_notify`等)はmopidy coreの単一tracklistを全パーティション
  が共有する値のため、そちらは既存の全体broadcastのままが引き続き正しい
  (直上の項目自身のコメントの通り、対象外)。
  修正: mpdcrossfadeidlepartition-patch.py。mpdidlemixerpartition-patch.py
  が確立した「pykka `ProxyCall`を対象セッションのactor_refへ直接`tell()`する
  個別配送」機構をそのまま再利用。translator.pyの`_session_actor_refs`/
  `_session_partition`を使い、`mixer_output_idle_targets()`(出力所有
  パーティション基準)と並ぶ汎用版として、任意のパーティション名を直接指定
  できる`partition_idle_targets(partition)`を追加。playback.pyの
  `_mpdcrossfadeidle_notify()`/`_mpdreplaygain_notify()`を、呼び出し元が
  既に計算済みのpartition(`translator.partition_get(id(context.session))`)
  を受け取り、`mixer_output_idle_targets()`と同じ`ProxyCall`直接`tell()`で
  当該パーティションのセッションだけへ配送するよう変更。呼び出し箇所
  (crossfade/mixrampdb/mixrampdelay/replay_gain_mode)は、インライン計算
  していたpartitionを変数へ束ねてnotifyへ渡すだけの変更で済んだ。
  verified: オフライン検証(`/tmp`へ隔離コピーしパッチ適用、`ast.parse()`で
  構文確認、2回連続適用で"already patched, skip"となり冪等なことを確認)の
  上で、dev mopidyをビルド・起動(mopidy.log新規ERROR/Traceback 0件、
  クリーン起動)。実機確認(TCP 6601、mopidy-ytmusic実アカウント、3接続
  A(default)/B・C(newpartition zoneXへ切替)): B(`idle options`購読中)に
  対しA側で`crossfade 15`/`mixrampdb -10.5`/`mixrampdelay 2.5`/
  `replay_gain_mode track`を順に実行→修正後はBはいずれも起床せず(修正前は
  誤って起床していたはずの箇所)。対照としてB側で`crossfade 7`を実行し
  同じくzoneXパーティションの別接続C(`idle options`購読中)が`changed:
  options`で正しく起床することを確認(個別配送機構自体が機能している
  ことの確認)。回帰確認: A側で`repeat 1`/`repeat 0`を実行するとzoneXの
  Bは引き続き`changed: options`で起床する(repeat/random/single/consumeの
  全体broadcastは無変更)ことを確認。`status`のxfade/mixrampdb/
  mixrampdelay/partition各行と`replay_gain_status`がA/Bで直上の項目通り
  引き続き独立していること(回帰なし)、`ping`/`tagtypes`/`status`の基本
  応答に異常が無いことも確認。mopidy.log clean。

- [x] `newpartition {NAME}`(`mopidy_mpd/protocol/partition.py`)で作成した
  新パーティションの`replay_gain_mode`が、実MPDと異なり常に`off`で始まって
  しまう不具合。TODO/既知の残課題を全項目消化済みのため自走エージェントが
  (general-purposeサブエージェントへの調査委任を経て)新規発見。
  実MPD本体(gh rawで`src/Partition.cxx`の
  `Partition::Partition(const char *_name, const Partition &src)`が
  `SetReplayGainMode(src.replay_gain_mode)`を呼ぶこと、
  `src/command/PartitionCommands.cxx`の`handle_newpartition()`が
  `instance.partitions.emplace_back(name, client.GetPartition())`で呼び出し
  クライアントの現在所属パーティションをsrcとして渡すことを確認。NEWS
  ver 0.24.13にも「configuration: copy replay_gain_mode when creating a new
  partition」と明記)は新パーティション作成時に作成元パーティションの
  `replay_gain_mode`をコピーする。一方`pc`(PlayerControl、crossfade/
  mixrampdb/mixrampdelay保持)は同コンストラクタが委譲する基底コンストラクタ
  内で`config.player`(mpd.confの静的設定)から都度新規構築されるだけで
  srcの実行時状態を引き継がない(replay_gain_modeだけが例外的にコピー対象と
  なる非対称仕様)ことも確認。
  `mpdplayercontrolpartition-patch.py`はこの4値をパーティション名キーの辞書に
  変更したが、`translator.partition_try_create()`は`_partitions.append(name)`
  するだけで`_replay_gain_mode[name]`を一切初期化しないため、
  `get_replay_gain_mode(name)`は常にフォールバック既定値`"off"`を返して
  いた。BACKLOG.md全体を`newpartition`/`replay_gain`/`SetReplayGainMode`で
  検索したが、直近の`mpdplayercontrolpartition-patch.py`/
  `mpdcrossfadeidlepartition-patch.py`はパーティション間の値漏洩/idle通知
  漏洩のみを扱っており、newpartition作成時点でのコピー漏れは既出無し・
  blocked指定も無しと確認。
  修正: `mpdnewpartitionreplaygain-patch.py`。`partition_try_create(name,
  source_partition="default")`へ拡張し、既存の`_partition_lock`スコープ内
  (TOCTOU安全性維持)で`_replay_gain_mode[name] =
  _replay_gain_mode.get(source_partition, "off")`を追加、`newpartition()`
  ハンドラが`translator.partition_get(id(context.session))`(既存の
  `mpdvolumepartition-patch.py`等と同じパターン)で呼び出しクライアントの
  現在所属パーティションを取得しsource_partitionとして渡す。crossfade/
  mixrampdb/mixrampdelayは実MPD同様デフォルトのまま変更しない。
  verified: mpdnewpartitionreplaygain-patch.py。オフライン検証(`/tmp`へ
  隔離コピーしパッチ適用、`ast.parse()`で構文確認、2回連続適用でも
  "already patched, skip"で冪等なことを確認)の上で、dev mopidyをビルド・
  起動(mopidy.log新規ERROR/Traceback0件、クリーン起動)。実機確認
  (TCP 6601、mopidy-ytmusic実アカウント、3接続A(default)/B/C):
  A側で`replay_gain_mode track`実行後`newpartition "zoneY"`→Bを
  `partition "zoneY"`で切替後`replay_gain_status`→修正前は`off`のはずが
  修正後`replay_gain_mode: track`(defaultから正しく継承)に変化。さらに
  B側(zoneY、`replay_gain_mode album`/`crossfade 20`設定済み)から
  `newpartition "zoneZ"`し、Cを`partition "zoneZ"`で切替→
  `replay_gain_status`が`replay_gain_mode: album`(defaultではなく実際の
  作成元zoneYの値を継承、コピー元を正しく参照していることを確認)、
  `status`にxfade行が出ない(crossfade/mixrampdbは引き続きコピーされず
  デフォルトのまま、回帰なし)ことを確認。A側(default)の
  `replay_gain_status`が`track`のまま無変更(他パーティションからの影響
  無し)であることも確認。`delpartition`によるzoneY/zoneZ後始末も正常。
  mopidy.log新規ERROR/Traceback0件。

- [x] `mopidy_ytmusic/library.py`の`parseSearch()`(`search()`経由、"any"/genre/date/
  track_no/`_META_SEARCH_FIELDS`等`filter=None`で呼ぶ全ての検索パスが通る共通
  パーサ)のif/elifチェーンがresultType "song"/"album"/"artist"の3種類しか処理
  しておらず、ytmusicapi 1.12.0の検索結果に頻出するresultType "video"
  (`ytmusicapi/parsers/search.py`の`ALL_RESULT_TYPES`に"video"が既に列挙されて
  おり、"song"/"video"/"album"共通で`videoId`/`artists`/`duration`を
  `parse_song_runs()`経由でパースする、songとほぼ同一構造の結果)を素通しし
  黙って捨てている不具合。TODO/既知の残課題を全項目消化済みのため自走エージェ
  ントが(general-purposeサブエージェントへの調査委任を経て)新規発見。
  実機確認(dev mopidy、実ytmusicアカウント、TCP 6601): YouTube Music上で公式
  ミュージックビデオが強く優勢な人気曲だと、`search any`/`find any`(rmpcの
  検索UIが実際に発行するのはこのany検索)の無フィルタ結果がresultType
  "video"のみで占められ一致する"song"/"album"が1件も無いことがあり、その場合
  `parseSearch()`は空の`SearchResult`を返す。`search any "打上花火"`/
  `"紅蓮華"`/`"despacito"`/`"wonderwall"`はいずれも`OK`(0件)だったが、同じ曲は
  `search title "打上花火"`(filter="songs"、resultTypeがsongに絞られる別経路)
  では20件ヒットする — 曲自体は存在し再生可能なのにany検索という主要経路
  でだけ発見不能になる非一貫なコンテンツ欠落。mopidy.logにエラー/例外は一切
  出ない(if/elifチェーンがどの分岐にもマッチせずthrough-する、例外を投げない
  黙殺なので既存のtry/except(1652行目)にも捕捉されない)ため、ログからは原因
  が全く分からない。BACKLOG.mdを"resultType.*video"/"video.*resultType"/
  "Music Video"/"parseSearch"(83件全読)で検索したが既出無し(listall/seekの
  blocked2件とも無関係)と確認。
  修正: `ytsearchvideoresult-patch.py`。song分岐(`result["resultType"] ==
  "song"`)と全く同じロジック(artists解決・`self.ARTISTS`キャッシュ・album有無
  の処理・Track登録・`self.TRACKS`キャッシュ・`ytsearchthumbnail-patch.py`が
  既に確立した`self.IMAGES`サムネイルキャッシュ)をresultType "video"にも複製
  して追加。`field=="track"`によるタイトル完全一致フィルタは複製しない —
  videoがfield="track"経由(filter="songs"のexact検索、`search()`の
  track_name分岐)で渡ってくることは無く(filter="songs"はytmusicapi側で
  resultTypeをsongに絞る)、fieldは常にNoneのまま呼ばれる経路(any/genre/
  date/track_no/meta-tag、いずれもfilter=None)でしかvideo分岐に到達しない
  ため。album有無の判定はsong分岐と同じ`result.get("album")`を使う(video
  結果は`parse_song_runs()`のalbum-runがあれば`album`キーを持ちうるため、
  無条件のNone決め打ちにはしない)。`ytparsegaps-patch.py`同様
  `result.get("artists") or []`でフォールバックしartists欠落時のKeyErrorも
  踏まない。
  verified: オフライン検証(`/tmp`へ隔離コピーしパッチ適用、`ast.parse()`で
  構文確認、2回連続適用で"already patched, skip"となり冪等なことを確認)の
  上で、dev mopidyをビルド・起動(mopidy.log新規ERROR/Traceback/WARNING0件、
  クリーン起動)。実機確認(TCP 6601、mopidy-ytmusic実アカウント):
  `search any "打上花火"`/`"紅蓮華"`/`"despacito"`/`"wonderwall"`が修正前は
  いずれも`OK`(0件、事前に確認済み)だったのに対し、修正後はすべて実トラック
  (`file: ytmusic:track:...`、Artist/Title/Time等の詳細情報付き)を返すことを
  確認。回帰確認: `search any "yoasobi"`(修正前後で3件、うちalbum
  プレースホルダ1件+実トラック2件)が無変更、`search title "打上花火"`
  (20件)が無変更、`status`/`ping`の基本応答に異常が無いことを確認。
  mopidy.log新規ERROR/Traceback/WARNING0件、クリーン起動。

- [x] `mopidy_ytmusic/library.py`の`parseSearch()`(`search()`経由、"any"/genre/date/
  track_no/`_META_SEARCH_FIELDS`等`filter=None`で呼ぶ全ての検索パスが通る共通
  パーサ)のif/elifチェーンがresultType "song"/"video"/"album"/"artist"の4種類しか
  処理しておらず、ytmusicapi 1.12.0の`ALL_RESULT_TYPES`に含まれるresultType
  "episode"(ポッドキャストの個別エピソード)を素通しし黙って捨てている不具合。
  `ytsearchvideoresult-patch.py`がresultType "video"分岐を追加した時と全く同じ
  穴が別のresultTypeにも残っていた。TODO/既知の残課題を全項目消化済みのため
  自走エージェントが(general-purposeサブエージェントへの調査委任を経て、
  point 74の「mopidy_ytmusicバックエンドのデータ不整合」角度を起点に)新規発見。
  実害確認: `ytmusicapi/parsers/search.py`の`parse_search_result()`はresultType
  "episode"に対して"song"/"video"と同じ経路(`if result_type in ["song", "video",
  "episode"]:`)で実在・再生可能な`videoId`を設定し、date/podcast(番組)情報も
  付与する。つまりエピソードは即再生可能なTrackとして扱えるデータを持つが、
  `parseSearch()`にはresultType "episode"用の分岐が無く、if/elifチェーンをどれ
  にも一致せず素通りし例外も出さず黙って捨てられる(既存のtry/exceptにも捕捉
  されない、ログからは原因が全く分からない)。実機確認(dev mopidy、実ytmusic
  アカウント、TCP 6601): ytmusicapi.search(filter=None)直接呼び出しで実在
  エピソード(videoType="MUSIC_VIDEO_TYPE_PODCAST_EPISODE"、実videoId付き)が
  ヒットする検索語("NHKラジオ ニュース")で`search any "NHKラジオ ニュース"`を
  送ると修正前は`OK`(0件)、直接APIでは見えているエピソードがMPD経由では一切
  発見不能だった。
  修正: `ytsearchepisoderesult-patch.py`。video分岐と同じ構造でepisode分岐を
  追加するが、videoと違いepisodeの実データには`artists`/`duration`が存在せず
  (`parse_search_result()`がresultType=="episode"の場合に設定するのはtitle/
  videoId/videoType/live/date/podcast/thumbnailsのみ)、代わりに
  `result["podcast"] = {"id","name"}`(番組のbrowseId+表示名)がある。番組の
  browseId(MPSPプレフィックス)は`ytmusic:artist:`名前空間が期待するアーティ
  ストIDではなくポッドキャスト番組のIDのため、self.ARTISTSキャッシュに誤った
  型のURIで登録するとrmpc側でアーティスト名クリック時に誤ったbrowse結果に
  繋がる実害がある(home-patch.pyが同じ理由でポッドキャスト番組自体を素通し
  せず除外しているのと同種の配慮)。そのためuri無し・id無しの名前だけの
  Artistとして追加しクリック不可能なテキスト表示に留めた。album/durationは
  捏造せず既存の安全なプレースホルダ(album=None)・フォールバック
  (`_yt_track_length_ms()`のキー欠如時0)に委ねた。
  verified: オフライン検証(`/tmp`へ隔離コピーしパッチ適用、`ast.parse()`で
  構文確認、2回連続適用で"already patched, skip"となり冪等なことを確認)の
  上で、dev mopidyをビルド・起動(mopidy.log新規ERROR/Traceback/WARNING0件、
  クリーン起動)。実機確認(TCP 6601、mopidy-ytmusic実アカウント):
  `search any "NHKラジオ ニュース"`が修正前`OK`(0件)だったのに対し、修正後は
  実エピソード1件(`file: ytmusic:track:zbJ215DayMw`、Artist欄に番組名
  「教科書にない「生」の英語を聴く｜ネイティブのリアルな英会話ポッドキャスト」、
  Title欄にエピソード名、Date: 0000プレースホルダ)を返すことを確認。
  回帰確認: `search any "yoasobi"`(3件、うちalbumプレースホルダ1件+実トラック
  2件)が無変更、`search title "打上花火"`(20件)が無変更、`status`/`ping`/
  `tagtypes`の基本応答に異常が無いことを確認。mopidy.log新規ERROR/Traceback/
  WARNING0件、クリーン起動。
