{
  config,
  lib,
  pkgs,
  ...
}:
let
  # A prototype deck editor whose PPTX export only runs in a browser, so the app itself
  # has to be resident somewhere. The Mac mini is the always-on host; the workstation
  # reaches it over an SSH tunnel and everyone else over the Cloudflare tunnel below.
  root = "${config.home.homeDirectory}/Developer/github.com/gapul/presenta-prototypes";
  port = "3141";

  # Handed out to testers, so it is a plain tunnel with no Access policy in front of it:
  # anyone with the link can open the editor. Everything it can reach is this one port.
  hostname = "presenta.gapul.net";
  tunnel = "a4946214-cf23-49c6-96ba-0f375df201d3";
  tunnelConfig = "${config.xdg.dataHome}/cloudflared/presenta.yml";

  start = pkgs.writeShellScript "presenta-studio-start" ''
    export PATH="${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin"

    if [ ! -d "${root}/node_modules" ]; then
      echo "presenta-prototypes is not installed at ${root}; nothing to serve"
      exit 0
    fi

    cd "${root}"

    # Rebuild on every start. The source arrives here by rsync, so a deploy is "copy, then
    # kickstart this agent" — and serving whatever `.next` happened to be lying around is
    # exactly how a fixed layout went two review rounds without ever reaching the renderer.
    pnpm build || exit 1

    # Bound to loopback: macOS's firewall drops inbound connections to this port anyway, so
    # every client already comes through `ssh -N -L ${port}:127.0.0.1:${port} macmini` or
    # the tunnel, which dials the same loopback address from this machine.
    exec pnpm start -H 127.0.0.1 -p ${port}
  '';
in
{
  launchd.agents.presenta-studio = {
    enable = true;
    config = {
      ProgramArguments = [ "${start}" ];
      RunAtLoad = true;
      # A clean exit means the checkout is absent, which restarting cannot fix.
      KeepAlive.SuccessfulExit = false;
      ProcessType = "Interactive";
      WorkingDirectory = root;
      StandardOutPath = "/tmp/presenta-studio.log";
      StandardErrorPath = "/tmp/presenta-studio.log";
    };
  };

  # The public entrance. Credentials are a {AccountTag, TunnelID, TunnelSecret} json next
  # to the config, created once through the Cloudflare API; they are not in the store, so
  # this agent starts as a no-op until that file exists.
  launchd.agents.presenta-tunnel = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          [ -f "${tunnelConfig}" ] || exit 0
          exec /run/current-system/sw/bin/cloudflared tunnel --no-autoupdate --config "${tunnelConfig}" run
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/tmp/presenta-tunnel.log";
      StandardErrorPath = "/tmp/presenta-tunnel.log";
    };
  };

  home.activation.presentaStudioNote = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${root}/node_modules" ]; then
      echo "presenta-studio: run 'pnpm install' in ${root} to start serving"
    fi
    if [ ! -f "${tunnelConfig}" ]; then
      echo "presenta-studio: ${hostname} stays dark until ${tunnelConfig} and its credentials exist (tunnel ${tunnel})"
    fi
  '';
}
