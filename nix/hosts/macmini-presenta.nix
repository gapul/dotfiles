# Presenta (gapul/presenta-prototypes) — the slide IDE served at presenta.gapul.net through the
# macmini tunnel, which points at 127.0.0.1:3141.
#
# Only the runtime is declared here. The app itself is a checkout that gets built in place
# (`pnpm install && pnpm db:migrate && pnpm build`), and its secrets live in the checkout's
# .env.local, which next reads from the working directory. The app waits for .next/BUILD_ID,
# which `next build` writes last, so a fresh checkout does not crash-loop through its build.
# A restart after a deploy is `sudo launchctl kickstart -k system/org.nixos.presenta`.
#
# Postgres is its own instance rather than nix-darwin's services.postgresql: that one is a user
# agent, so it would only run while someone is logged in, and it wants /var/lib to be writable
# by the login user. This one listens on localhost only and keeps its data under the user's
# state directory.
#
# Backups: the slide images and clips sit in the checkout's data/assets, which restic already
# takes with ~/Developer. The database is dumped at 4:30 into /Users/Shared/presenta-backups,
# which home/macmini-backup.nix picks up at 5:00 — a copy of a running PGDATA would not restore.
{ pkgs, user, ... }:
let
  home = "/Users/${user.username}";
  state = "${home}/.local/state/presenta";
  appDir = "${home}/Developer/github.com/gapul/presenta-prototypes";
  postgres = pkgs.postgresql_18;
  pgPort = "55432";
  # initdb once, then hand over to postgres itself. The database the app uses is created by
  # the first `pnpm db:migrate` (prisma creates it when it is missing).
  pgRun = pkgs.writeShellScript "presenta-postgres-run" ''
    set -eu
    data=${state}/postgres
    if [ ! -s "$data/PG_VERSION" ]; then
      mkdir -p "$data"
      ${postgres}/bin/initdb -D "$data" -U presenta --auth=trust --encoding=UTF8 --locale=C
    fi
    exec ${postgres}/bin/postgres -D "$data" -h 127.0.0.1 -p ${pgPort} -k "$data"
  '';
  backupDir = "/Users/Shared/presenta-backups";
  # One dump, replaced each night; restic keeps the history. Written beside and moved into place
  # so a failed run never leaves restic a truncated file.
  pgDump = pkgs.writeShellScript "presenta-backup" ''
    set -eu
    ${postgres}/bin/pg_dump -h 127.0.0.1 -p ${pgPort} -U presenta -Fc presenta > ${backupDir}/presenta.dump.tmp
    mv ${backupDir}/presenta.dump.tmp ${backupDir}/presenta.dump
    echo "$(date '+%F %T') dumped $(wc -c < ${backupDir}/presenta.dump) bytes"
  '';
in
{
  # launchd opens the log files but does not create their directory.
  system.activationScripts.postActivation.text = ''
    sudo -u ${user.username} mkdir -p ${state}
    install -d -m 0700 -o ${user.username} ${backupDir}
  '';

  launchd.daemons.presenta-backup = {
    serviceConfig = {
      ProgramArguments = [ "${pgDump}" ];
      UserName = user.username;
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 30;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "${backupDir}/backup.log";
      StandardErrorPath = "${backupDir}/backup.log";
    };
  };

  launchd.daemons.presenta-postgres = {
    serviceConfig = {
      ProgramArguments = [ "${pgRun}" ];
      UserName = user.username;
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${state}/postgres.log";
      StandardErrorPath = "${state}/postgres.log";
    };
  };

  launchd.daemons.presenta = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path ${appDir}/.next/BUILD_ID && exec ${pkgs.pnpm}/bin/pnpm start -H 127.0.0.1 -p 3141"
      ];
      UserName = user.username;
      WorkingDirectory = appDir;
      RunAtLoad = true;
      KeepAlive = true;
      EnvironmentVariables = {
        HOME = home;
        # pnpm start runs next through node, and the AI panel shells out to the claude CLI.
        PATH = "${home}/.local/bin:/etc/profiles/per-user/${user.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin";
        NODE_ENV = "production";
      };
      StandardOutPath = "${state}/app.log";
      StandardErrorPath = "${state}/app.log";
    };
  };
}
