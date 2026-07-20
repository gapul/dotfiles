# Mopidy 実行環境 (本体 + 拡張 + yt-dlp を単一 site-packages に束ねた python env)。
# 宣言モジュール home/mopidy.nix と、macmini の自走テスト鏡の両方から import して
# 同一定義を共有する (パッチ適用のドリフト防止)。
#
# nixpkgs 素の mopidy-ytmusic / mopidy-mpd / mopidy-listenbrainz は現行 YouTube/rmpc に
# 対し不足があるため、configs/media/mopidy/*.py のビルド時パッチを焼き込む。
# 新しいパッチを足したら、対象拡張の patch リストに追記するだけでよい。
{ pkgs }:
let
  inherit (pkgs) lib;
  py = pkgs.python3;
  toM = py.pkgs.toPythonModule;
  patchDir = ../../configs/media/mopidy;

  # 拡張に postPatch として python パッチ群を順に当てる
  mkPatched =
    pkg: scripts:
    pkg.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + lib.concatMapStrings (s: "${py.interpreter} ${s}\n") scripts;
    });

  # ブランチの4パッチ + 母艦の Now Playing フロントエンド同梱を統合。
  # cp(フロントエンド配置)が必要なため mkPatched でなく overrideAttrs で明示。
  ytmusicPatched = pkgs.mopidy-ytmusic.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + "${py.interpreter} ${patchDir + "/ytdlp-patch.py"}\n" # ストリーム解決を pytube→yt-dlp へ
      + "${py.interpreter} ${patchDir + "/search-patch.py"}\n" # any 検索が album=None で0件を是正
      + "${py.interpreter} ${patchDir + "/home-patch.py"}\n" # ブラウズに ytmusic:home (get_home)
      + "${py.interpreter} ${patchDir + "/ytdistinct-patch.py"}\n" # get_distinct("album") 有効化
      + "${py.interpreter} ${patchDir + "/ytliked-patch.py"}\n" # Liked の非音楽アイテムのクラッシュ修正
      + "${py.interpreter} ${patchDir + "/ytartist-patch.py"}\n" # 検索の誤爆アーティスト表記を除外
      + "${py.interpreter} ${patchDir + "/ytimages-patch.py"}\n" # プレイリスト/Liked のトラックart確実化
      # macOS Now Playing フロントエンドを同梱・登録 (mopidy本体が音源として名乗る)
      + "cp ${patchDir + "/nowplaying_fe.py"} mopidy_ytmusic/nowplaying_fe.py\n"
      + "${py.interpreter} ${patchDir + "/nowplaying-patch.py"}\n";
  });

  mpdPatched = mkPatched pkgs.mopidy-mpd [
    (patchDir + "/mpd-patch.py") # binarylimit + albumart/readpicture
    (patchDir + "/mpdsearch-patch.py") # 新 MPD フィルタ式 (Tag contains "x") を解釈
    (patchDir + "/mpdlist-patch.py") # list の group 修飾 (list Album group AlbumArtist)
    (patchDir + "/mpdsort-patch.py") # search/find の sort 修飾 (sort -Track 等)
    (patchDir + "/mpdwindow-patch.py") # search/find の window 修飾 (ページング)
    (patchDir + "/mpdcount-patch.py") # count の group 修飾 (count group artist 等)
    (patchDir + "/mpdsticker-patch.py") # sticker get/set/delete/list/find (sqlite永続化)
    (patchDir + "/mpdreadcomments-patch.py") # readcomments を有効化 (comment を返却、無ければ空)
    (patchDir + "/mpdprio-patch.py") # prio/prioid を実装 (優先度を保存し playlistinfo の Prio へ反映)
    (patchDir + "/mpdaddid-patch.py") # addid の POSITION に相対指定 (+N/-N) を追加
    (patchDir + "/mpdgetvol-patch.py") # getvol (音量問い合わせ) を追加
  ];

  listenbrainzPatched = mkPatched pkgs.mopidy-listenbrainz [
    (patchDir + "/lb-patch.py") # 空 release_name 送信の 400 を修正
  ];
in
py.withPackages (
  ps:
  (map toM [
    pkgs.mopidy
    ytmusicPatched
    mpdPatched
    listenbrainzPatched
  ])
  ++ [
    ps.yt-dlp
    ps.pyobjc-core # nowplaying_fe が MediaPlayer.framework を叩くため
    ps.pyobjc-framework-Cocoa
  ]
)
