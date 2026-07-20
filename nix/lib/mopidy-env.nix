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

  ytmusicPatched = mkPatched pkgs.mopidy-ytmusic [
    (patchDir + "/ytdlp-patch.py") # ストリーム解決を pytube→yt-dlp へ委譲
    (patchDir + "/search-patch.py") # any 検索が album=None で 0 件になるのを是正
    (patchDir + "/home-patch.py") # ブラウズに ytmusic:home (get_home) を追加
  ];

  mpdPatched = mkPatched pkgs.mopidy-mpd [
    (patchDir + "/mpd-patch.py") # binarylimit + albumart/readpicture
    (patchDir + "/mpdsearch-patch.py") # 新 MPD フィルタ式 (Tag contains "x") を解釈
    (patchDir + "/mpdlist-patch.py") # list の group 修飾 (list Album group AlbumArtist)
    (patchDir + "/mpdsort-patch.py") # search/find の sort 修飾 (sort -Track 等)
    (patchDir + "/mpdwindow-patch.py") # search/find の window 修飾 (ページング)
    (patchDir + "/mpdcount-patch.py") # count の group 修飾 (count group artist 等)
    (patchDir + "/mpdsticker-patch.py") # sticker get/set/delete/list/find (sqlite永続化)
    (patchDir + "/mpdreadcomments-patch.py") # readcomments を有効化 (comment を返却、無ければ空)
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
  ++ [ ps.yt-dlp ]
)
