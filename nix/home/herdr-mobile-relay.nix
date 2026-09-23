{ config, pkgs, ... }:
# herdr-mobile-relay (github.com/0cv/herdr-mobile-relay): a phone PWA for the
# herdr agents running on this machine — see which agent is blocked, answer its
# approval, send a prompt, read the pane. Nothing herdr itself offers; its
# official phone story is "ssh in and use the TUI".
#
# The plugin is installed and upgraded by herdr (`herdr plugin install
# 0cv/herdr-mobile-relay`); that drops a verified release bundle under
# ~/.local/share/herdr-mobile-relay/current and the relay's own config
# (token, instance id, push subscriptions) under herdr's plugin config dir.
# What the plugin cannot do is keep the relay running without Cloudflare: its
# only background-service path bundles a cloudflared tunnel, and its
# gateway/direct paths expect a foreground "Quick Start" pane left open. This
# agent is that missing service. Loaded on both Macs: each herdr server gets its
# own relay, and the phone app lists them side by side.
#
# Transport: none of the plugin's three (temporary tunnel, Cloudflare named
# tunnel, community WebRTC gateway). The relay stays on loopback and
# `tailscale serve` puts it on the tailnet as https://<host>.ts.net:8375 with
# a real certificate, which the PWA needs for Web Push. The phone is always on
# the tailnet, so no third party sits in the path. The setup QR is printed by
# `herdr-mobile-relay-qr` (one-use invitation, ten minutes).
#
# Upgrade caveat: the plugin's upgrade flips the `current` symlink but only
# restarts a service it installed itself, so after `herdr plugin install`
# bounce this one: `launchctl kickstart -k gui/$UID/org.nix-community.home.herdr-mobile-relay`.
let
  home = config.home.homeDirectory;
  release = "${home}/.local/share/herdr-mobile-relay/current";
  configDir = "${home}/.config/herdr/plugins/config/herdr-mobile-relay.events";
  port = "8375";
  # The Tailscale.app CLI: /usr/local/bin on the workstation, /opt/homebrew/bin on the
  # mac mini (brew-installed). Resolved at run time so one module serves both.
  tailscale = "$(command -v tailscale || ls /opt/homebrew/bin/tailscale /usr/local/bin/tailscale 2>/dev/null | head -1)";
  # The plugin's scripts read HERDR_PLUGIN_CONFIG_DIR/HERDR_RELAY_ENV to find
  # relay.env; the relay binary reads the same two. Keep every caller on one
  # config so `assert_service_env_matches` never trips.
  relayEnv = ''
    export HERDR_PLUGIN_CONFIG_DIR="${configDir}"
    export HERDR_RELAY_ENV="${configDir}/relay.env"
    export HERDR_BIN="${config.home.profileDirectory}/bin/herdr"
    export PATH="${config.home.profileDirectory}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    tailscale=${tailscale}
  '';
  serve = pkgs.writeShellScript "herdr-mobile-relay" ''
    ${relayEnv}
    # Plugin not installed yet (fresh machine): idle instead of crash-looping.
    if [ ! -x "${release}/herdr-mobile-relay" ] || [ ! -f "$HERDR_RELAY_ENV" ]; then
      sleep 600
      exit 0
    fi
    set -a
    . "$HERDR_RELAY_ENV"
    set +a
    export HERDR_RELAY_HOST=127.0.0.1
    export HERDR_RELAY_PORT=${port}
    # Idempotent; tailscale keeps the serve config across reboots itself.
    [ -n "$tailscale" ] &&
      "$tailscale" serve --bg --https=${port} http://127.0.0.1:${port} >/dev/null 2>&1
    exec "${release}/herdr-mobile-relay" serve
  '';
  qr = pkgs.writeShellScriptBin "herdr-mobile-relay-qr" ''
    ${relayEnv}
    host="$("$tailscale" status --self --json | ${pkgs.jq}/bin/jq -r '.Self.DNSName | rtrimstr(".")')"
    exec bash "${release}/relay/setup-link.sh" "$host:${port}"
  '';
in
{
  home.packages = [ qr ];

  launchd.agents.herdr-mobile-relay = {
    enable = true;
    config = {
      ProgramArguments = [ "${serve}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "${home}/Library/Logs/herdr-mobile-relay.log";
      StandardErrorPath = "${home}/Library/Logs/herdr-mobile-relay.log";
    };
  };
}
