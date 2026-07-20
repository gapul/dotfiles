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

  ytmusicPatched = pkgs.mopidy-ytmusic.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + "${py.interpreter} ${patchDir + "/ytdlp-patch.py"}\n" # ストリーム解決を pytube→yt-dlp へ
      + "${py.interpreter} ${patchDir + "/search-patch.py"}\n" # any 検索が album=None で0件を是正
      + "${py.interpreter} ${patchDir + "/home-patch.py"}\n" # ブラウズに ytmusic:home (get_home)
      # macOS Now Playing フロントエンドを同梱・登録 (mopidy本体が音源として名乗る)
      + "cp ${patchDir + "/nowplaying_fe.py"} mopidy_ytmusic/nowplaying_fe.py\n"
      + "${py.interpreter} ${patchDir + "/nowplaying-patch.py"}\n";
  });

  mpdPatched = mkPatched pkgs.mopidy-mpd [
    (patchDir + "/mpd-patch.py") # binarylimit + albumart/readpicture
    (patchDir + "/mpdsearch-patch.py") # 新 MPD フィルタ式 (Tag contains "x") を解釈
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
