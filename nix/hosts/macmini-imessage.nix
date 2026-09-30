# Resident iMessage bridge (launchd) and config generation. Lives on the system side (nix-darwin).
#
# Building and signing the bridge itself is owned by the home side (nix/home/macmini-imessage.nix).
# This part is on the system side for two reasons:
#
#   1. TCC identity. macOS 26 decides permissions for launchd jobs by "the executable launchd
#      spawned". home-manager's launchd.agents always wraps it in
#      `/bin/sh -c '/bin/wait4path /nix/store && exec …'`, so /bin/sh is what gets checked
#      for Full Disk Access and the grant on the signed binary does not apply
#      (measured on 2026-09-29: wrapped, chat.db gives EPERM; spawned directly, it is readable).
#      nix-darwin emits serviceConfig.ProgramArguments into the plist as written.
#   2. Ordering. config.yaml needs the tokens, which system-side sops places.
#      home-manager activation runs before sops, so creating it there would not produce it on
#      the switch right after installation. Here it can be ordered after sops in postActivation
#      (next after mkAfter = 1500).
#
# The job waits until config.yaml appears (KeepAlive.PathState), so a rebuild before the
# tokens are in place does not break anything.
{
  lib,
  pkgs,
  user,
  ...
}:
let
  home = "/Users/${user.username}";
  dataDir = "${home}/.local/share/mautrix-imessage";
  tokenDir = "${home}/.config/mautrix-imessage"; # placed by sops in hosts/macmini.nix
  stable = "${home}/.local/libexec/tcc/mautrix-imessage"; # placed by the home-side tcc-stable-binary
  configFile = "${dataDir}/config.yaml";

  # Missing keys are filled in by the bridge at startup from its bundled example config.
  # Only what differs from the defaults is written here.
  settings = {
    homeserver = {
      # The homeserver's tailnet address. Synapse listens on 0.0.0.0:8008.
      address = "http://100.127.129.31:8008";
      # Upstream defaults to going through mautrix-wsproxy, but the tailnet is reachable both
      # ways, so plain HTTP.
      websocket_proxy = null;
      domain = "gapul.net";
      software = "standard";
    };
    appservice = {
      # 0.0.0.0 avoids crashing when startup comes before Tailscale and the tailnet address
      # cannot be bound. From outside it is protected by ALF (hosts/macmini.nix) and hs_token.
      hostname = "0.0.0.0";
      port = 29332; # pairs with the registration in nix/homelab/matrix-imessage.nix
      database = {
        type = "sqlite3-fk-wal";
        uri = "file:${dataDir}/mautrix-imessage.db?_txlock=immediate";
      };
      id = "imessage";
      bot = {
        username = "imessagebot";
        displayname = "iMessage bridge bot";
      };
      ephemeral_events = true;
      # Injected during activation.
      as_token = "";
      hs_token = "";
    };
    imessage.platform = "mac";
    bridge = {
      user = "@gapul:gapul.net";
      username_template = "imessage_{{.}}";
      # No suffix, same as the other bridges (Signal etc., nixpkgs defaults).
      displayname_template = "{{.}}";
      command_prefix = "!im";
      # Group rooms into an "iMessage" space, same as the other bridges (bridgev2 default).
      personal_filtering_spaces = true;
      # Built without libheif, so conversion is impossible (pkgs/mautrix-imessage.nix).
      convert_heif = false;
      # Backfill of past history. It only applies once, when a room is first created, and the
      # default only takes the last 0.5 days / 100 messages. Signing the mini into iCloud and
      # syncing Messages brings the full history down into chat.db, so stream as much of it as
      # possible into the new rooms (2026-09-29). Deferred backward backfill is Beeper-only and
      # does not work on plain Synapse (same situation as the backfill comment in
      # matrix-bridges.nix).
      backfill = {
        initial_limit = 5000;
        initial_sync_max_age = 3650;
        # Do not mark old chats as read. Unread state follows the iMessage side.
        unread_hours_threshold = -1;
      };
    };
    logging = {
      min_level = "info";
      writers = [
        {
          type = "stdout";
          format = "pretty-colored";
        }
      ];
    };
  };
  settingsFile = (pkgs.formats.yaml { }).generate "mautrix-imessage-config.yaml" settings;
in
{
  # After sops (mkAfter = 1500). Writes only when both tokens exist. Runs as root, so
  # ownership is handed back to the user. Changing settings does not change the plist, but
  # this script rewrites the config every time, so it takes effect on the next restart.
  system.activationScripts.postActivation.text = lib.mkOrder 1600 ''
    if [ -r '${tokenDir}/as_token' ] && [ -r '${tokenDir}/hs_token' ]; then
      /bin/mkdir -p '${dataDir}'
      /usr/sbin/chown ${user.username} '${dataDir}'
      (
        umask 077
        AS_TOKEN="$(cat '${tokenDir}/as_token')" HS_TOKEN="$(cat '${tokenDir}/hs_token')" \
          ${pkgs.yq-go}/bin/yq \
            '.appservice.as_token = strenv(AS_TOKEN) | .appservice.hs_token = strenv(HS_TOKEN)' \
            '${settingsFile}' > '${configFile}.tmp'
      )
      /usr/sbin/chown ${user.username} '${configFile}.tmp'
      /bin/mv '${configFile}.tmp' '${configFile}'
    else
      echo "mautrix-imessage: token files missing under ${tokenDir}; config.yaml not written" >&2
    fi
  '';

  launchd.user.agents.mautrix-imessage.serviceConfig = {
    # Spawn the signed binary directly without wrapping. See the comment at the top for why.
    # -n: the config is created by the activation above. Do not let the bridge write it back.
    ProgramArguments = [
      stable
      "-c"
      configFile
      "-n"
    ];
    WorkingDirectory = dataDir;
    KeepAlive.PathState.${configFile} = true;
    # Without Full Disk Access, or while chat.db has no messages yet (the bridge dies immediately
    # as "not logged in"), cycling at the default 10 seconds only bloats the log.
    ThrottleInterval = 60;
    StandardOutPath = "${dataDir}/bridge.log";
    StandardErrorPath = "${dataDir}/bridge.log";
  };
}
