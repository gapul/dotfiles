# Presenta (gapul/presenta-prototypes) — the slide IDE served at presenta.gapul.net through the
# macmini tunnel, which points at 127.0.0.1:3141.
#
# Deploys follow main by themselves: every two minutes presenta-deploy fetches the repo and, when
# main moved, builds that commit in its own release directory while the old one keeps serving,
# runs the browser test suite against it on a side port with a throwaway database, migrates the
# production database, points `current` at the new release and restarts the app. A failed
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
# Video: presenta-video (workers/video, its own dependencies) renders the deck with Remotion and has
# the AivisSpeech engine on this machine read the speaker notes. It is a per-machine service, not
# part of a release.
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
  cloudflaredDir = "${home}/.local/share/cloudflared";
  tunnelConfig = pkgs.writeText "presenta-tunnel.yml" ''
    tunnel: a4946214-cf23-49c6-96ba-0f375df201d3
    credentials-file: ${cloudflaredDir}/presenta.json
    ingress:
      - hostname: presenta.gapul.net
        service: http://127.0.0.1:3141
      - service: http_status:404
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

    e2e() (
      set -euo pipefail
      exec >${state}/e2e.log 2>&1
      cd "$1"
      db=postgresql://presenta@127.0.0.1:${pgPort}/presenta_e2e
      ${postgres}/bin/dropdb -h 127.0.0.1 -p ${pgPort} -U presenta --if-exists presenta_e2e
      ${postgres}/bin/createdb -h 127.0.0.1 -p ${pgPort} -U presenta presenta_e2e
      # Set here, so next does not take production values from .env.local; the mailer points
      # nowhere, so a test never sends real mail.
      export DATABASE_URL=$db DATABASE_URL_UNPOOLED=$db AI_LIVE=0 \
        AUTH_SECRET=$(openssl rand -hex 32) EMAIL_TOKEN_SECRET=$(openssl rand -hex 32) \
        APP_BASE_URL=http://127.0.0.1:3151 AUTH_URL=http://127.0.0.1:3151 \
        MAILER_URL=http://127.0.0.1:9/ MAILER_TOKEN=$(openssl rand -hex 16)
      pnpm db:migrate
      pnpm exec playwright install chromium >/dev/null
      # Uploads go to a scratch directory, not the shared production data.
      rm -rf ${state}/e2e-data && mkdir -p ${state}/e2e-data
      export PRESENTA_DATA_DIR=${state}/e2e-data
      pnpm start -H 127.0.0.1 -p 3151 &
      server=$!
      trap 'kill $server 2>/dev/null || true' EXIT
      for _ in $(seq 60); do
        curl -fsS http://127.0.0.1:3151/api/health >/dev/null 2>&1 && break
        sleep 1
      done
      E2E_BASE_URL=http://127.0.0.1:3151 pnpm test:e2e
    )
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
      # 動画ワーカーは別パッケージ（アプリの依存には入っていない）。
      pnpm --dir workers/video install --frozen-lockfile --reporter=silent
    ); then
      notify "build of $rev failed; still serving $(basename "$(readlink ${share}/current)")"
      exit 1
    fi

    # Browser tests gate the switch: the new release runs on a side port against a throwaway
    # database before production is migrated or touched. Releases without the suite skip this.
    if grep -q '"test:e2e"' "$release/package.json"; then
      if ! e2e "$release"; then
        notify "end-to-end tests failed for $rev; still serving $(basename "$(readlink ${share}/current)"). Log: ${state}/e2e.log"
        exit 1
      fi
    fi

    if ! (cd "$release" && set -a && . ${envFile} && set +a && pnpm db:migrate); then
      notify "migration of $rev failed; still serving $(basename "$(readlink ${share}/current)")"
      exit 1
    fi
    ln -sfn "$release" ${share}/current.new && mv -h ${share}/current.new ${share}/current
    sudo -n /bin/launchctl kickstart -k system/org.nixos.presenta
    sudo -n /bin/launchctl kickstart -k system/org.nixos.presenta-video
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

  # Store-path jobs use `command` so nix-darwin waits for /nix/store, which macOS 27 mounts after
  # launchd starts daemons (see the minecraft daemons in macmini.nix).
  launchd.daemons.presenta-backup = {
    command = "${pgDump}";
    serviceConfig = {
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
    command = "${pgRun}";
    serviceConfig = {
      UserName = user.username;
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${state}/postgres.log";
      StandardErrorPath = "${state}/postgres.log";
    };
  };

  # The tunnel that publishes presenta.gapul.net (ingress -> 127.0.0.1:3141). Its credentials file
  # was created once with `cloudflared tunnel create` and cannot live in the store, so it stays in
  # ~/.local/share/cloudflared. This used to be a hand-started process, and the 2026-09-15 reboot for
  # the macOS 27 update left the site answering 530 until someone noticed.
  launchd.daemons.presenta-tunnel = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path ${cloudflaredDir}/presenta.json && exec ${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate --config ${tunnelConfig} run"
      ];
      UserName = user.username;
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${state}/tunnel.log";
      StandardErrorPath = "${state}/tunnel.log";
    };
  };

  # 動画の書き出し。資料の発表原稿を読み上げ、Remotion がスライドを描いて mp4 にする。
  #
  # 読み上げはこの機械で動いている AivisSpeech エンジン（home/macmini-aivisspeech.nix、
  # VOICEVOX と同じ API）に頼む。VOICEVOX 本体（0.25.2）も置いてみたが、macOS 27 では
  # /synthesis のたびに libffi の trampoline で落ちる（DYLD_LIBRARY_PATH でも直らない）。
  # キューは DB（VideoJob）なので、ここは待ち受けるだけ。アプリと同じ data/ とデータベースを見る。
  launchd.daemons.presenta-video = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path ${appDir}/workers/video/node_modules && set -a && . ${envFile} && set +a && exec pnpm --dir ${appDir}/workers/video watch"
      ];
      UserName = user.username;
      WorkingDirectory = "${appDir}/workers/video";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 5;
      EnvironmentVariables = {
        HOME = home;
        PATH = "${home}/.local/bin:/etc/profiles/per-user/${user.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin";
        PRESENTA_DATA_DIR = "${share}/data";
        VOICEVOX_URL = "http://100.105.135.49:10101";
        # AivisSpeech の「まお・ノーマル」。話者一覧は /speakers で引ける。
        VOICEVOX_SPEAKER = "888753760";
        # pnpm はここに端末が無いと node_modules の作り直しで止まる（CI と同じ扱いにする）。
        CI = "true";
      };
      StandardOutPath = "${state}/video.log";
      StandardErrorPath = "${state}/video.log";
    };
  };

  launchd.daemons.presenta-deploy = {
    command = "${deploy}";
    serviceConfig = {
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
