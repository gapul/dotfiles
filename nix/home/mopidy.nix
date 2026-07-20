{ config, pkgs, ... }:
# 端末で YouTube Music を低発熱再生する Mopidy 基盤。
# ・ブラウザ再生 (映像デコード + WindowServer 合成で発熱) をやめ、音声のみを GStreamer で鳴らす。
# ・アカウント連携 (ライブラリ/ミックス/ラジオ=新曲開拓) は mopidy-ytmusic + ytmusicapi。
# ・再生履歴は mopidy-listenbrainz で ListenBrainz に記録 (従来運用の継続)。
# ・操作は MPD クライアント rmpc (127.0.0.1:6600 が既定接続先) から。
#
# nixpkgs 素の mopidy-ytmusic 0.3.9 / mopidy-listenbrainz 0.3.0 は現行 YouTube/LB に対し
# そのままでは動かないため、ビルド時に 2 つのパッチを当てている (configs/media/mopidy/*.py):
#   1. ytdlp-patch.py     : ストリーム解決を壊れた pytube cipher から yt-dlp へ差し替え
#   2. lb-patch.py        : 空 release_name を送って 400 になる不具合を修正
let
  home = config.home.homeDirectory;

  # 本体+拡張+パッチを束ねた実行環境は nix/lib/mopidy-env.nix に集約 (テスト鏡と共有)。
  mopidyEnv = import ../lib/mopidy-env.nix { inherit pkgs; };

  confPath = "${home}/.config/mopidy/mopidy.conf";
  authPath = "${home}/.config/mopidy/browser.json";

  # ログイン時は sops-nix (設定/認証を生成) と mopidy 起動が並走しうる。
  # config に token が載り、認証ファイルが読めるようになるまで待ってから起動する。
  startScript = pkgs.writeShellScript "mopidy-start" ''
    conf="${confPath}"
    for _ in $(seq 1 60); do
      if [ -r "$conf" ] && [ -r "${authPath}" ] && grep -q '^token = .' "$conf" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    exec ${mopidyEnv}/bin/mopidy --config "$conf"
  '';
in
{
  home.packages = [
    mopidyEnv
    pkgs.rmpc # MPD TUI クライアント (既定で 127.0.0.1:6600 に接続)
  ];

  # YouTube 認証 (ytmusicapi browser 形式 = ヘッダ + Cookie の JSON)。
  # Google セッション Cookie を含むため sops 管理。復号ファイルを mopidy が auth_json で読む。
  # NOTE: Cookie は期限切れになる。切れたら Zen の cookie から再生成して sops を更新する。
  sops.secrets."ytmusic/browser_json" = {
    path = authPath;
    mode = "0400";
  };

  # LB トークンは template 埋め込み用に宣言 (placeholder を使うため path は不要)。
  sops.secrets."listenbrainz/token" = { };

  # mopidy.conf は LB トークンを含むため sops.templates で生成 (平文で置かない)。
  sops.templates."mopidy.conf" = {
    path = confPath;
    content = ''
      [core]
      cache_dir = ${home}/.cache/mopidy
      data_dir = ${home}/.local/share/mopidy

      [audio]
      output = autoaudiosink

      [mpd]
      enabled = true
      hostname = 127.0.0.1
      port = 6600

      [http]
      enabled = true
      hostname = 127.0.0.1
      port = 6680

      [ytmusic]
      enabled = true
      oauth_json =
      auth_json = ${authPath}

      [listenbrainz]
      enabled = true
      token = ${config.sops.placeholder."listenbrainz/token"}
      url = api.listenbrainz.org
    '';
  };

  # mopidy を常駐 (ログイン時起動 + 死活監視)。rmpc はこれに繋ぐだけ。
  launchd.agents.mopidy = {
    enable = true;
    config = {
      ProgramArguments = [ "${startScript}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive"; # 音声再生のため優先度を落とさない
      StandardOutPath = "/tmp/mopidy.out";
      StandardErrorPath = "/tmp/mopidy.err";
    };
  };
}
