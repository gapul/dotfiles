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
#   - sops を持たないホストなので(flake の macminiHeadless が "no sops")、パスワードと
#     ntfy の資格情報は手置きのファイルをそのまま読む。共通ライブラリの既定パスが
#     まさにその場所なので、宣言と手置きの境界はここだけで済む。
#   - 画面が無いので osascript は使わず、通知は ntfy だけ。
#   - forget は自ホスト分だけで prune しない。共有リポジトリを repack するのは母艦の役。
#
# 鮮度の監視はここには置かない。母艦の restic-monitor が monitoredHosts を列挙して
# ホスト別に見ており、そこに macmini は入っている。整合性チェック(restic check)も
# リポジトリ全体の話なので母艦の週次に任せる。
let
  home = config.home.homeDirectory;
  common = import ../lib/restic-common.nix { inherit home; };

  # sops が無いので共通ライブラリの既定(手置き)をそのまま使う。
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
    forgetSnippet = common.forgetOwnHostOnly;
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
    ];
    extraExcludes = [
      "**/.DS_Store"
      # 再取得できる重みとキャッシュ。ollama のモデルは ~/.local/share 配下なので
      # そもそも対象外だが、ai/ にも .gguf を置くことがある。
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
    parseSnapshotTime = ''$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo "$latest" | cut -d. -f1)" +%s 2>/dev/null || echo 0)'';
  };
in
{
  home.packages = [ pkgs.restic ];

  # 旧スクリプトと同じ 5:00。母艦は 13:00 なので、共有リポジトリのロックが重ならない。
  launchd.agents.restic-backup = import ../lib/launchd-agent.nix {
    program = "${scripts.backup}";
    schedule = [
      {
        Hour = 5;
        Minute = 0;
      }
    ];
    nice = 5;
    # 母艦と同じ理由。Developer と minecraft のスナップショットを丸ごと流すので、
    # Background バンドに置くと途中で刈られうる。
    longRunning = true;
  };
}
