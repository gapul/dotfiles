{ lib, pkgs, ... }:
let
  # api.anthropic.com, claude.ai and platform.claude.com all resolve into this range. The Mac
  # mini has no IPv6 upstream, so the v4 range is the whole of it.
  anthropicAddr = "160.79.104.0";
  anthropicNet = "${anthropicAddr}/23";

  # With the Mullvad exit node on, claude.ai answered every request with a Cloudflare challenge
  # (403, cf-mitigated: challenge), which Claude Code cannot pass (2026-10-31). A /23 via the
  # Ethernet router is more specific than anything tailscaled installs, so Anthropic skips the
  # exit node. The router comes from DHCP rather than `route get default`, which points at the
  # utun while the exit node is on.
  skipExitNode = pkgs.writeShellApplication {
    name = "anthropic-skip-exit-node";
    text = ''
      gw=$(/usr/sbin/ipconfig getoption en0 router) || exit 0
      [ -n "$gw" ] || exit 0
      current=$(/sbin/route -n get ${anthropicNet} 2>/dev/null)
      if echo "$current" | /usr/bin/grep -q "destination: ${anthropicAddr}$" \
        && echo "$current" | /usr/bin/grep -q "gateway: $gw$"; then
        exit 0
      fi
      /sbin/route -q -n delete -net ${anthropicNet} >/dev/null 2>&1 || true
      /sbin/route -n add -net ${anthropicNet} "$gw"
    '';
  };
in
{
  launchd.daemons.anthropic-skip-exit-node = {
    # `command` (not ProgramArguments) so nix-darwin wraps it in wait4path; see
    # macmini-homeserver-monitor.nix.
    command = lib.getExe skipExitNode;
    serviceConfig = {
      RunAtLoad = true;
      # Re-checked every minute: a DHCP renewal or link flap drops the route.
      StartInterval = 60;
      ProcessType = "Background";
      StandardOutPath = "/var/log/anthropic-skip-exit-node.log";
      StandardErrorPath = "/var/log/anthropic-skip-exit-node.log";
    };
  };
}
