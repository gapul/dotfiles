# Single source of truth (SSO) for restic backups.
#
# The darwin version (home/restic-backup.nix, launchd), the linux version
# (home/restic-backup-linux.nix, systemd) and the backup recipes in Justfile all
# pull the same values from here.
#
# Important: repository / forget retention policy / archive tag must be kept
#   identical across all hosts to avoid corrupting the "shared restic repository"
#   (Mac and pve share the same repo — restic shared repo). This is the sole
#   definition point, so a change here propagates to both hosts + Justfile.
#
# The three scripts (backup / check / monitor) also live here. They used to be copy-pasted
# into both host modules, where the only real differences were the notify implementation,
# the backup paths and BSD-vs-GNU date. Those are the arguments to mkScripts below; the
# platform modules keep only what is genuinely platform-shaped — launchd agents vs systemd
# units. `home` alone is still enough for the Justfile, which imports this for the paths only.
{ home }:
rec {
  repository = "rclone:google-drive:restic-backup";
  rcloneConf = "${home}/.config/rclone/rclone.conf";
  passwordFile = "${home}/.config/restic/password";

  # Marker tag for cold archives. just archive adds it via --tag, forget retains it via --keep-tag.
  # If the adding side (Justfile) and the retaining side (forgetInvocation below) drift apart, cold gets treated as warm and is pruned.
  archiveTag = "archive";

  # The retention policy as data. The homeserver backs up through NixOS'
  # services.restic.backups, which takes a list of flags rather than a shell
  # snippet, so keeping this as the one definition is what stops a third host
  # from thinning the shared repository on a different schedule.
  #   --keep-tag archive: cold archives are kept forever. Only warm (untagged) snapshots are thinned out.
  retentionArgs = [
    "--keep-tag ${archiveTag}"
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];

  # Hosts expected to write to the shared repository every day. The monitor below
  # is the only staleness alarm any of them has, and asking the repository for its
  # single newest snapshot cannot answer "did *this* host stop" — one healthy host
  # keeps the whole alarm quiet. Hence an explicit list: a decommissioned host must
  # be removed from it (pve is gone, folded into homeserver), and a new host that is
  # not added to it can stop backing up unnoticed.
  monitoredHosts = [
    "MacBook-Mini"
    "homeserver"
    "macmini"
    "rpi4"
  ];

  # forget retention policy invocation (shared by both hosts' backupScript).
  # Note: the indentation/newlines of this string go directly into the generated script's byte stream.
  #   Both backupScripts expand this at a 4-space indent position, so the layout
  #   below is reproduced from retentionArgs rather than reflowed.
  forgetInvocation = ''
    restic forget --prune \
      ${builtins.elemAt retentionArgs 0} \
      ${builtins.concatStringsSep " " (builtins.tail retentionArgs)} || true'';

  # Same policy, scoped to the host running it and without prune. For hosts that
  # write to the shared repository but are not the one that repacks it: prune walks
  # the whole repository over rclone and takes an exclusive lock, so having a second
  # host do it buys nothing and collides with the first.
  forgetOwnHostOnly = ''
    restic forget --host "$(hostname -s)" \
      ${builtins.elemAt retentionArgs 0} \
      ${builtins.concatStringsSep " " (builtins.tail retentionArgs)} || true'';

  # Contents of the env file that emits the same values for Justfile / interactive shells.
  #   home-manager places it at ~/.config/restic/env and Justfile's restic_env sources it.
  envFileText = ''
    # Auto-generated (nix/lib/restic-common.nix). Do not edit by hand.
    export RESTIC_REPOSITORY="${repository}"
    export RESTIC_PASSWORD_FILE="${passwordFile}"
    export RCLONE_CONFIG="${rcloneConf}"
    export RESTIC_ARCHIVE_TAG="${archiveTag}"
  '';

  # The scheduled scripts, shared by both platforms.
  #   passwordFile   sops-managed path (differs from the plain passwordFile above, which is for the Justfile)
  #   logFile        where the run log is appended
  #   backupPaths    non-reproducible user data to protect
  #   extraExcludes  exclude patterns on top of the shared list
  #   extraPathPkgs  packages the platform's notify needs (libnotify on Linux)
  #   notifyBody     shell body of notify() — takes "$1" title, "$2" message, must never fail
  #   parseSnapshotTime  shell expression turning an ISO8601 $latest into an epoch (BSD vs GNU date)
  mkScripts =
    {
      pkgs,
      lib,
      passwordFile,
      logFile,
      backupPaths,
      extraExcludes ? [ ],
      extraPathPkgs ? [ ],
      # PATH の先頭に置くディレクトリ。macOS で TCC の許可を保たせるために、
      # 署名済みの安定した場所に置いた restic を store の分より先に見せる用途。
      # 空なら何も足さない (Linux 側は素の store パスのまま)。
      pathPrefix ? "",
      # 間引きの一文。既定は repo 全体を prune する側で、共有リポジトリに書くだけの
      # ホストは forgetOwnHostOnly を渡す。
      forgetSnippet ? forgetInvocation,
      notifyBody,
      parseSnapshotTime,
    }:
    let
      resticEnv = ''
        export PATH=${lib.optionalString (pathPrefix != "") "${pathPrefix}:"}${
          lib.makeBinPath (
            [
              pkgs.restic
              pkgs.rclone
              pkgs.coreutils
              pkgs.jq
            ]
            ++ extraPathPkgs
          )
        }:$PATH
        export RESTIC_REPOSITORY="${repository}"
        export RESTIC_PASSWORD_FILE="${passwordFile}"
        export RCLONE_CONFIG="${rcloneConf}"
        # The main process continues even if notification fails.
        notify() {
          ${notifyBody}
        }
      '';

      # Exclude: regenerable / huge / DL temp files
      excludeFile = pkgs.writeText "restic-excludes" (
        lib.concatStringsSep "\n" (
          [
            "**/node_modules"
            "**/.direnv"
            "**/.venv"
            "**/target"
            "**/dist"
            "**/build"
            "**/.next"
            "**/.expo"
            "**/.git/objects"
          ]
          ++ extraExcludes
        )
        + "\n"
      );
    in
    {
      backup = pkgs.writeShellScript "restic-backup" ''
        set -uo pipefail
        ${resticEnv}
        mkdir -p "$(dirname ${logFile})"
        exec >>"${logFile}" 2>&1
        echo "==================== $(date '+%Y-%m-%d %H:%M:%S') backup start ===================="

        if ! rclone about google-drive: >/dev/null 2>&1; then
          echo "SKIP: cannot reach the google-drive remote (rclone authorize may be incomplete)"
          exit 0
        fi

        if ! restic snapshots >/dev/null 2>&1; then
          echo "repository not found, running init"
          restic init || { echo "ERROR: restic init failed"; exit 1; }
        fi

        restic backup \
          --verbose=1 \
          --exclude-file=${excludeFile} \
          ${lib.concatStringsSep " " (map (p: "\"${p}\"") backupPaths)}
        rc=$?

        # --keep-tag archive: exclude cold archives (tagged via just archive with --tag archive) from
        #   the keep policy and retain them forever. Prune only warm (untagged) ones.
        #   (restic also refuses to delete the last snapshot in each group, so double protection)
        ${forgetSnippet}

        echo "==================== $(date '+%Y-%m-%d %H:%M:%S') backup done (rc=$rc) ===================="
        if [ "$rc" -ne 0 ]; then
          notify "restic ⚠️ backup failed" "restic backup failed with rc=$rc. Please check the log: ${logFile}"
        fi
        exit $rc
      '';

      # Integrity check (weekly). Notify if corruption is detected
      check = pkgs.writeShellScript "restic-check" ''
        set -uo pipefail
        ${resticEnv}
        exec >>"${logFile}" 2>&1
        echo "-------------------- $(date '+%Y-%m-%d %H:%M:%S') check start --------------------"
        if ! rclone about google-drive: >/dev/null 2>&1; then
          echo "SKIP: remote unreachable"; exit 0
        fi
        if restic check; then
          echo "check OK"
        else
          echo "check FAILED"
          notify "restic ⚠️ possible repository corruption" "restic check failed. Please check the log"
        fi
      '';

      # Run monitoring (daily). Notify if the last successful snapshot is old/missing
      monitor = pkgs.writeShellScript "restic-monitor" ''
        set -uo pipefail
        ${resticEnv}
        max_age_days=2

        if ! rclone about google-drive: >/dev/null 2>&1; then
          notify "restic ⚠️ backup not running" "google-drive not authenticated. Please run rclone authorize drive"
          exit 0
        fi
        snapshots=$(restic snapshots --json 2>/dev/null)
        if [ -z "$snapshots" ]; then
          notify "restic ⚠️ repository unreadable" "restic snapshots returned nothing. A stale exclusive lock will do this"
          exit 0
        fi
        now=$(date +%s)
        # One listing, then per host, because the repository is shared: every host's
        # snapshots live in it and the newest one overall says nothing about any
        # particular host.
        for host in ${lib.concatStringsSep " " monitoredHosts}; do
          latest=$(printf '%s' "$snapshots" | jq -r --arg h "$host" 'map(select(.hostname == $h) | .time) | max // empty')
          if [ -z "$latest" ]; then
            notify "restic ⚠️ no snapshots ($host)" "$host has never backed up to the shared repository"
            continue
          fi
          last_epoch=${parseSnapshotTime}
          # 解釈に失敗すると 0 が返る。そのまま引き算すると「20676 日前」という
          # 嘘の警告になり、本物の遅延と見分けが付かなくなる。別の文言で出す。
          if [ "$last_epoch" -eq 0 ]; then
            notify "restic ⚠️ 日付を解釈できない ($host)" "最後のスナップショットの時刻が読めない: $latest"
            continue
          fi
          age_days=$(( (now - last_epoch) / 86400 ))
          if [ "$age_days" -ge "$max_age_days" ]; then
            notify "restic ⚠️ backup is stale ($host)" "the last backup of $host was $age_days days ago"
          fi
        done
      '';
    };
}
