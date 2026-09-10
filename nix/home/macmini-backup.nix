{
  config,
  pkgs,
  lib,
  ...
}:
# macmini の restic バックアップ。母艦の restic-backup.nix と同じ共通ライブラリを使う。
#
# 元は ~/.local/bin/restic-macmini-offsite.sh と手書きの plist で、対象が ~/Developer
# だけだった。宣言の外にあったこと自体もだが、~/.config(Claude の履歴など)と ~/ai が
# 一度も守られていなかったのが実害。
#
# 母艦と違う点は3つ。
#   - sops の入り口が違う。母艦は home-manager 側が人間の age 鍵で開けるが、こちらは
#     hosts/macmini.nix のシステム側 sops が自分の SSH ホスト鍵で開いて、同じ場所に置く。
#     パスは共通ライブラリの既定(=元の手置きの場所)のままなので、このファイルは
#     どちらで置かれたかを知らずに済む。
#   - 画面が無いので osascript は使わず、通知は ntfy だけ。
#   - 共有リポジトリ全体の prune/check/鮮度監視を担当する。常時稼働ホストへ
#     control-plane を集約し、母艦は自分のスナップショットを送るだけにする。
#
# 各データ保有ホストは自分の backup だけを実行する。共有リポジトリを排他的に
# repack/check する主体はこの Mac mini だけにし、同時実行とノートのスリープを避ける。
let
  home = config.home.homeDirectory;
  common = import ../lib/restic-common.nix { inherit home; };

  # 共通ライブラリの既定パスをそのまま使う。中身はシステム側 sops が置く
  # (hosts/macmini.nix)。手置きだった頃と同じ場所なので、ここは変わらない。
  inherit (common) passwordFile;
  logFile = "${home}/Library/Logs/restic-backup.log";

  ntfyUrlFile = "${home}/.config/ntfy/url";
  ntfyTokenFile = "${home}/.config/ntfy/token";

  scripts = common.mkScripts {
    inherit
      pkgs
      lib
      passwordFile
      logFile
      ;
    backupPaths = [
      # 作業ツリー一式。旧スクリプトが見ていた唯一の対象で、ホーム直下に散っていた
      # 書類も projects/ 配下へ集めてある(~/Documents は macOS の TCC が ssh と
      # launchd からの走査を拒むため、この機械では使わない)。
      "${home}/Developer"
      # マイクラのワールド。実体は mcsrv のホーム(このエージェントからは読めない)なので、
      # 4:40 の minecraft-backup が固めたものをここで拾う。offsite はこれが唯一の経路。
      "/Users/Shared/minecraft-backups"
      # ~/ai は 2026-08-12 に畳んだ。パスとして残すと lstat が失敗して毎朝 ntfy が鳴るので、
      # 中身は宣言済みのレイアウトどおりに散らしてある。manabi-dashboard はさらに 2026-08-13 に
      # サービスとして gapul/manabi へ切り出し、この機械では /Users/Shared/manabi の clone に
      # なった——git にある以上ここで拾う必要はない。止まった mopidy-dev は ~/tmp へ退避した。
      # ここが今まで完全に無防備だった。Claude Code の履歴 (~/.config/claude) や
      # 各ツールの状態が入っている。store へのシンボリックリンクは中身を追わない。
      "${home}/.config"
      # Hermes の状態。専用ユーザーのホームは gapul から読めない(drwx------)ので、
      # マイクラと同じ方式にした——root の daemon が固めてここへ置き、restic はそれを拾う。
      # 中身は state.db(Discord の会話 525 件、全文検索インデックス込み)と .env 一式で、
      # どちらも作り直せない。hermes-agent 本体と node は再インストールできるので入れない。
      "/Users/Shared/hermes-backups"
    ];
    extraExcludes = [
      "**/.DS_Store"
      # 再取得できる重みとキャッシュ。ai/ に .gguf を置くことがある。
      "**/*.gguf"
      "**/*.safetensors"
      "**/*.bin"
      "**/models"
      # models だけでは GPT-SoVITS の pretrained_models を拾えない。s2G488k.pth や
      # s1v3.ckpt、bigvgan_generator.pt が素通りして、落とし直せる配布物 4.3GiB を
      # 毎日 Google Drive へ運んでいた(2026-08-12 実測。これで 100MB 弱まで落ちる)。
      "**/pretrained_models"
      "**/*.pth"
      "**/*.ckpt"
      "**/*.pt"
      "**/node_modules"
      "**/.venv"
      "**/.direnv"
      "**/target"
      "**/dist"
      "**/build"
      "**/.next"
      "**/.expo"
      "**/.git/objects"
      # このリポジトリを開ける鍵をこのリポジトリの中に入れない。母艦側のモジュールが
      # 冒頭で書いている方針と同じで、鍵はパスワードマネージャに置く。
      "**/.config/restic"
      # Claude Code が置き直せるもの。versions は数百MB のバイナリ。
      "**/.config/claude/cache"
      "**/.config/claude/downloads"
      "**/.config/claude/versions"
    ];
    notifyBody = ''
      if [ -r "${ntfyUrlFile}" ] && [ -r "${ntfyTokenFile}" ]; then
        /usr/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $(cat "${ntfyTokenFile}")" \
          -H "Title: restic (macmini)" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -d "$1: $2" \
          "$(cat "${ntfyUrlFile}")" >/dev/null 2>&1 || true
      fi'';
    # Fractional seconds の有無に依存せず YYYY-MM-DDTHH:MM:SS だけを読む。
    parseSnapshotTime = ''$(date -j -f "%Y-%m-%dT%H:%M:%S" "''${latest:0:19}" +%s 2>/dev/null || echo 0)'';
  };
in
{
  home.packages = [ pkgs.restic ];

  # 旧スクリプトと同じ 5:00。母艦は 13:00 なので、共有リポジトリのロックが重ならない。
  launchd.agents = {
    # 5:00 backup, followed by the sole repository-wide retention/prune pass.
    restic-backup = import ../lib/launchd-agent.nix {
      program = "${scripts.backup}";
      schedule = [
        {
          Hour = 5;
          Minute = 0;
        }
      ];
      nice = 5;
      longRunning = true;
    };

    # Repository integrity belongs to the always-on control-plane host.
    restic-check = import ../lib/launchd-agent.nix {
      program = "${scripts.check}";
      schedule = [
        {
          Weekday = 0;
          Hour = 14;
          Minute = 0;
        }
      ];
      nice = 5;
      longRunning = true;
    };

    # One monitor checks freshness for every host in the shared repository.
    restic-monitor = import ../lib/launchd-agent.nix {
      program = "${scripts.monitor}";
      schedule = [
        {
          Hour = 19;
          Minute = 0;
        }
      ];
      nice = 5;
    };
  };
}
