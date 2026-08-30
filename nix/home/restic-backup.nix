{
  config,
  pkgs,
  lib,
  ...
}:
# Encrypted backup + integrity check + run monitoring via restic, scheduled by launchd (macOS only).
# Backend is the existing rclone google-drive remote (rclone_conf from [[project_xdg_migration]]).
#
# Division of responsibility:
#   - system/app/config are reproducible via nix+dotfiles (no backup needed)
#   - what we protect here is only the "non-reproducible user data"
#
# Prerequisites (if unmet, backup just skips harmlessly):
#   1. Re-auth rclone google-drive: (`rclone authorize "drive"` → put the token into sops's rclone_conf)
#   2. The repository is auto-init'd on the first success
#
# Note (circular dependency): the restic passphrase, age key, and ssh key are "the keys to this repo itself",
#   so they're not protected by restic. Always store them separately in a password manager (Bitwarden/Ente).
let
  home = config.home.homeDirectory;

  # SSO: repository / retention policy / archive tag / rclone conf live in nix/lib/restic-common.nix.
  #   The linux version (restic-backup-linux.nix) and the Justfile pull the same values. To avoid breaking the shared repo.
  common = import ../lib/restic-common.nix { inherit home; };

  passwordFile = config.sops.secrets."restic_password".path;
  logFile = "${home}/Library/Logs/restic-backup.log";

  # ntfy failure notification (homelab's ntfy.gapul.net). The URL (topic included) and token are sops-managed.
  #   If they're unexpanded/unreadable, notify quietly falls back to osascript only.
  ntfyUrlFile = config.sops.secrets."unified_calendar/ntfy_url".path;
  ntfyTokenFile = config.sops.secrets."unified_calendar/ntfy_token".path;

  # The three scripts live in lib/restic-common.nix (shared with the linux version).
  # Only the macOS-shaped bits are passed in here: notify goes through osascript (works in
  # launchd's GUI session) plus an ntfy push, and BSD date needs the fractional seconds
  # trimmed before it will parse restic's ISO8601 timestamp.
  # TCC の許可を保たせるための安定した置き場。理由は下の activation を参照。
  tccBinDir = "${home}/.local/libexec/tcc";

  scripts = common.mkScripts {
    inherit
      pkgs
      lib
      passwordFile
      logFile
      ;
    pathPrefix = tccBinDir;
    backupPaths = [
      "${home}/Documents"
      "${home}/Pictures"
      "${home}/Downloads"
      "${home}/Movies"
      "${home}/Music"
      # Only the Syncthing share, never ~/Sync itself: its siblings are rclone mounts of Google
      # Drive, and the restic repository lives on that same Drive, so backing up the mount would
      # feed the repository into itself.
      "${home}/Sync/syncthing" # Syncthing share (local-primary replicated data)
      # Single-player worlds. The multiplayer ones moved to the macmini, where the server tars
      # /Users/mcsrv/server into /Users/Shared/minecraft-backups every ten minutes and
      # home/macmini-backup.nix picks that up - so those are covered over there, not here.
      "${home}/Library/Application Support/minecraft/saves"
      # PrismLauncher の instance。中身の大半はワールドではなく MOD 構成で、38MB のうち
      # modded が 26MB を占める。個々の MOD は再ダウンロードできるが「どれをどの版で組んだか」
      # の再現には手間がかかるので、ワールドと一緒に取る。ランチャーの assets/libraries/java
      # (合計 1.6GB) はここに含まれない — あれは起動すれば取り直せる。
      "${home}/Library/Application Support/PrismLauncher/instances"
      # Steam のセーブ。ほとんどは Steam Cloud 側にあり、ローカルに残るのは 192KB しかない。
      # 容量を食わないので、クラウド同期の対象外なタイトルのために取っておく。
      "${home}/Library/Application Support/Steam/userdata"
      "${home}/Desktop" # small, but the only home dir that was silently outside the set
      # Voice Memos. iCloud sync for these is off (CloudRecordings_ckAssets is empty), so the
      # group container is the only copy. CloudRecordings.db carries the titles, so take the
      # whole container rather than just the .m4a files.
      "${home}/Library/Group Containers/group.com.apple.VoiceMemos.shared"
      "${home}/.local/share/keystats" # keystats time series (a re-run cannot recreate it)
      # ActivityWatch, same class as keystats: 8 months and 1.1M events of what was on screen,
      # recorded once and never recomputable. aw-server keeps it in one SQLite file.
      "${home}/Library/Application Support/activitywatch/aw-server"
      # Zen's profile. Bookmarks already ride floccus, so what is actually at stake here is the
      # history and the per-extension settings; the caches under it are excluded below.
      "${home}/Library/Application Support/zen/Profiles"
    ];
    extraExcludes = [
      "**/.DS_Store"
      "**/*.photoslibrary"
      "**/ae-mcp-commands"
      # Zen's profile is ~1GB and almost all of it is refetchable browser cache. Keep places.sqlite
      # and the extension state, drop the rest.
      "**/zen/Profiles/*/cache2"
      "**/zen/Profiles/*/startupCache"
      "**/zen/Profiles/*/shader-cache"
      "**/zen/Profiles/*/thumbnails"
      "**/zen/Profiles/*/settings/**"
      "**/zen/Profiles/*/minidumps"
      "**/zen/Profiles/*/datareporting"
      # aw-server rotates .bak copies next to the live DB; the live one is what matters.
      "**/aw-server/*.db.bak.*"
    ];
    notifyBody = ''
      /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
      if [ -r "${ntfyUrlFile}" ] && [ -r "${ntfyTokenFile}" ]; then
        /usr/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $(cat "${ntfyTokenFile}")" \
          -H "Title: restic (mac)" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -d "$1: $2" \
          "$(cat "${ntfyUrlFile}")" >/dev/null 2>&1 || true
      fi'';
    # 先頭 19 文字が "YYYY-MM-DDTHH:MM:SS"。小数秒が付く形と付かない形の両方が来るので
    # `cut -d. -f1` だと後者でタイムゾーンごと残って解釈に失敗し、`|| echo 0` の
    # 既定値 (epoch 0) が「20676 日前」という嘘の警告になっていた。
    parseSnapshotTime = ''$(date -j -f "%Y-%m-%dT%H:%M:%S" "''${latest:0:19}" +%s 2>/dev/null || echo 0)'';
  };

  # longRunning: the backup and the integrity check both stream the whole set to Drive and
  # must not be reaped mid-flight. The monitor only reads the last snapshot's timestamp.
  agent =
    program: schedule:
    import ../lib/launchd-agent.nix {
      inherit program schedule;
      nice = 5;
      longRunning = true;
    };
in
{
  home.packages = [ pkgs.restic ];

  # restic passphrase (stored in sops's defaultSopsFile = secrets/secrets.yaml)
  sops.secrets."restic_password".path = common.passwordFile;

  # env sourced by the Justfile / interactive shell (SSO for repo/password/rclone/archiveTag).
  home.file.".config/restic/env".text = common.envFileText;

  # For ntfy failure notifications (URL is a publish endpoint including the topic, token is a Bearer tk_...).
  #   Even if unset, notify still works with osascript only, so it's harmless.
  sops.secrets."unified_calendar/ntfy_url".path = "${home}/.config/ntfy/url";
  sops.secrets."unified_calendar/ntfy_token".path = "${home}/.config/ntfy/token";

  # フルディスクアクセスを rebuild で失わないようにする。
  #
  # restic は Documents や Library の下を読むのでフルディスクアクセスが要る。
  # ところが TCC は許可をバイナリの場所と署名で識別するので、素の store パスを
  # 登録すると **更新のたびに別物になって許可が切れる**。実際、ボイスメモが
  # 読めずにバックアップから漏れていた。
  #
  # store の restic は ad-hoc 署名で、同一性が cdhash になる。中身が変われば
  # 別物。自己署名の identity で署名し直すと要件が
  #   identifier "net.gapul.tcc.restic" and certificate root = H"..."
  # だけになり、cdhash が入らない。場所を固定した上でこの署名にすれば、
  # restic を更新しても同じものとみなされる (実測で確認)。
  #
  # Developer ID を使わないのは、TCC が Apple 発行かどうかを見ていないから。
  # コード署名の鍵は用途を絞るほど安全なので、TCC のために撒かない。
  #
  # 与えるのは一度だけ: システム設定 > プライバシーとセキュリティ >
  # フルディスクアクセス に ~/.local/libexec/tcc/restic を追加する。
  home.activation.tccStableRestic = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${../../configs/bin/tcc-stable-binary} \
      ${pkgs.restic}/bin/restic restic || true
  '';

  launchd.agents = {
    # daily 13:00 backup
    restic-backup = agent "${scripts.backup}" [
      {
        Hour = 13;
        Minute = 0;
      }
    ];
    # weekly (Sun) 14:00 integrity check
    restic-check = agent "${scripts.check}" [
      {
        Weekday = 0;
        Hour = 14;
        Minute = 0;
      }
    ];
    # daily 19:00 run monitoring
    restic-monitor = agent "${scripts.monitor}" [
      {
        Hour = 19;
        Minute = 0;
      }
    ];
  };
}
