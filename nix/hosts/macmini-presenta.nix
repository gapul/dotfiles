# Presenta (gapul/presenta-prototypes) — the slide IDE served at presenta.gapul.net through the
# macmini tunnel, which points at 127.0.0.1:3141.
#
# Deploys follow main by themselves: every two minutes presenta-deploy fetches the repo and, when
# main moved, builds that commit in its own release directory while the old one keeps serving,
# migrates the database, points `current` at the new release and restarts the app. A failed
# build leaves `current` alone and sends an ntfy alert. So shipping is `git push` to main; the
# hand-run rsync into ~/Developer is no longer the production copy.
#
# Layout under ~/.local/share/presenta: repo (a clone), releases/<sha>, current -> releases/<sha>,
# data (uploaded slide assets, shared by every release). The secrets are ~/.config/presenta/env.local,
# symlinked into each release as .env.local (next reads it from the working directory).
# A manual restart is `sudo launchctl kickstart -k system/org.nixos.presenta`.
#
# Postgres is its own instance rather than nix-darwin's services.postgresql: that one is a user
# agent, so it would only run while someone is logged in, and it wants /var/lib to be writable
# by the login user. This one listens on localhost only and keeps its data under the user's
# state directory.
#
# Backups: the slide images and clips (~/.local/share/presenta/data) and the secrets (~/.config)
# are taken by restic, see home/macmini-backup.nix. The database is dumped at 4:30 into /Users/Shared/presenta-backups,
# which home/macmini-backup.nix picks up at 5:00 — a copy of a running PGDATA would not restore.
{ pkgs, user, ... }:
let
  home = "/Users/${user.username}";
  state = "${home}/.local/state/presenta";
  share = "${home}/.local/share/presenta";
  appDir = "${share}/current";
  envFile = "${home}/.config/presenta/env.local";
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
  deploy = pkgs.writeShellScript "presenta-deploy" ''
    set -euo pipefail
    export HOME=${home}
    export PATH=${home}/.local/bin:/etc/profiles/per-user/${user.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin
    repo=${share}/repo

    notify() {
      if [ -r ${home}/.config/ntfy/url ] && [ -r ${home}/.config/ntfy/token ]; then
        /usr/bin/curl -fsS --max-time 15 -H "Authorization: Bearer $(cat ${home}/.config/ntfy/token)" \
          -H "Title: presenta deploy (macmini)" -H "Tags: warning" -d "$1" "$(cat ${home}/.config/ntfy/url)" >/dev/null 2>&1 || true
      fi
    }

    # The private repo is read with gh's token: the login keychain is locked for a daemon, so
    # git's osxkeychain helper cannot answer, and the machine's SSH key is a deploy key for another repo.
    git_() { git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; }
    if [ ! -d "$repo/.git" ]; then
      mkdir -p ${share}/releases
      git_ clone --quiet https://github.com/gapul/presenta-prototypes.git "$repo"
    fi
    git_ -C "$repo" fetch --quiet origin main
    rev=$(git -C "$repo" rev-parse origin/main)
    [ "$(readlink ${share}/current 2>/dev/null || true)" = "${share}/releases/$rev" ] && exit 0

    echo "$(date '+%F %T') deploying $rev"
    release=${share}/releases/$rev
    rm -rf "$release"
    git -C "$repo" worktree prune
    git -C "$repo" worktree add --detach --force "$release" "$rev" >/dev/null
    ln -sfn ${envFile} "$release/.env.local"
    ln -sfn ${share}/data "$release/data"
    if ! (
      cd "$release"
      set -a; . ${envFile}; set +a
      pnpm install --frozen-lockfile --reporter=silent
      pnpm build
      pnpm db:migrate
    ); then
      notify "build or migration of $rev failed; still serving $(basename "$(readlink ${share}/current)")"
      exit 1
    fi
    ln -sfn "$release" ${share}/current.new && mv -h ${share}/current.new ${share}/current
    sudo -n /bin/launchctl kickstart -k system/org.nixos.presenta
    echo "$(date '+%F %T') serving $rev"

    # Keep the three newest releases for a quick roll back (point current at one and kickstart).
    ls -1dt ${share}/releases/*/ | tail -n +4 | while read -r old; do
      git -C "$repo" worktree remove --force "$old" || rm -rf "$old"
    done
  '';
in
{
  # launchd opens the log files but does not create their directory.
  system.activationScripts.postActivation.text = ''
    sudo -u ${user.username} mkdir -p ${state} ${share}/releases ${share}/data ${home}/.config/presenta
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

  launchd.daemons.presenta-deploy = {
    serviceConfig = {
      ProgramArguments = [ "${deploy}" ];
      UserName = user.username;
      RunAtLoad = true;
      StartInterval = 120;
      ProcessType = "Background";
      StandardOutPath = "${state}/deploy.log";
      StandardErrorPath = "${state}/deploy.log";
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
