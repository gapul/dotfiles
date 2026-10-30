{
  config,
  lib,
  pkgs,
  ...
}:
# Dead man's switch for the homelab, moved here from the retired Raspberry Pi
# (2026-08-24). The mini pings Healthchecks only while homeserver answers on
# SSH; silence — homeserver down, this Mac down, or the whole house offline —
# makes Healthchecks alert. Service-level checks are gatus's job on homeserver
# itself; this agent only answers "is the box alive at all" from a second machine.
let
  # The ping URL identifies the check and lets anyone who has it spoof
  # heartbeats, so it stays out of the public repo. Hand-placed file, same
  # pattern as the ntfy credentials in macmini-backup.nix.
  hcUrlFile = "${config.home.homeDirectory}/.config/healthchecks/homelab-url";
  homeserver = "100.127.129.31";

  watchdog = pkgs.writeShellApplication {
    name = "homelab-watchdog";
    bashOptions = [ ];
    text = ''
      [ -r "${hcUrlFile}" ] || exit 0
      # A full key exchange, not just an open port: on 2026-10-28 sshd kept accepting TCP but
      # reset every connection before the banner for two hours, and `nc -z` called that alive.
      if /usr/bin/ssh-keyscan -T 8 -t ed25519 ${homeserver} 2>/dev/null | /usr/bin/grep -q ssh-ed25519; then
        /usr/bin/curl -fsS -m 10 "$(cat "${hcUrlFile}")" >/dev/null 2>&1
      fi
    '';
  };
in
{
  # Not lib/launchd-agent.nix: that helper is shaped for calendar jobs, and a
  # heartbeat wants the opposite (fixed short interval, fire at load so a
  # reboot doesn't look like an outage).
  launchd.agents.homelab-watchdog = {
    enable = true;
    config = {
      ProgramArguments = [ (lib.getExe watchdog) ];
      StartInterval = 120;
      RunAtLoad = true;
      ProcessType = "Background";
    };
  };
}
