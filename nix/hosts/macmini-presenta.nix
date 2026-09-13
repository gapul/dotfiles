# Presenta (gapul/presenta-prototypes) — the slide IDE served at presenta.gapul.net through the
# macmini tunnel, which points at 127.0.0.1:3141.
#
# Only the runtime is declared here. The app itself is a checkout that gets built in place
# (`pnpm install && pnpm db:migrate && pnpm build`), and its secrets live in the checkout's
# .env.local, which next reads from the working directory. A restart after a deploy is
# `sudo launchctl kickstart -k system/org.nixos.presenta`.
#
# Postgres is its own instance rather than nix-darwin's services.postgresql: that one is a user
# agent, so it would only run while someone is logged in, and it wants /var/lib to be writable
# by the login user. This one listens on localhost only and keeps its data under the user's
# state directory.
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
in
{
  # launchd opens the log files but does not create their directory.
  system.activationScripts.postActivation.text = ''
    sudo -u ${user.username} mkdir -p ${state}
  '';

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
        "/bin/wait4path ${appDir}/.next && exec ${pkgs.pnpm}/bin/pnpm start -H 127.0.0.1 -p 3141"
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
