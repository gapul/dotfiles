{ lib, ... }:
# Turn off Determinate Nix's telemetry on both Macs. Two separate channels
# (https://docs.determinate.systems/guides/telemetry/):
#
#   - general telemetry from determinate-nixd: OS/CPU/RAM, language and timezone, feature usage, and
#     a device id tied to the FlakeHub account. detsys-ids-client reads only the environment
#     variable DETSYS_IDS_TELEMETRY=disabled; there is no config-file switch.
#   - crash reports uploaded to Sentry. telemetry.sentry.endpoint = null in
#     /etc/determinate/config.json makes determinate-nixd drop /etc/nix/sentry-endpoint, which is
#     where the nix CLI reads its DSN from (nix-src src/nix/main.cc), so this one file covers both.
#
# Cost, accepted on 2026-10-10: Determinate rolls features out through the same telemetry, so
# with it off, flags handed out per account (lazy-trees, the native Linux builder) may not be
# enabled. The Linux builder stays on the FOSS side (macmini-linux-builder.nix) instead.
let
  label = "systems.determinate.nix-daemon";
  plist = "/Library/LaunchDaemons/${label}.plist";
  plistBuddy = "/usr/libexec/PlistBuddy";
in
{
  environment.etc."determinate/config.json".text = builtins.toJSON {
    telemetry.sentry.endpoint = null;
  };

  # nix processes started from a shell. Redundant with the file above for Sentry; kept so a
  # stray /etc/nix/sentry-endpoint (e.g. after a Determinate upgrade) is still ignored.
  environment.variables = {
    DETSYS_IDS_TELEMETRY = "disabled";
    NIX_SENTRY_ENDPOINT = "";
  };

  # determinate-nixd is started by launchd from Determinate's own plist, and SIP refuses
  # `launchctl setenv` in the system domain, so the variable goes into that plist. Determinate may
  # rewrite the plist on upgrade; every activation puts it back. Reloading the job only when the
  # plist actually changed: the daemon's sockets are owned by launchd, so a reload costs a moment
  # of queued connections, not failed builds.
  system.activationScripts.postActivation.text = lib.mkOrder 1700 ''
    if [ -f ${plist} ]; then
      current="$(${plistBuddy} -c 'Print :EnvironmentVariables:DETSYS_IDS_TELEMETRY' ${plist} 2>/dev/null || true)"
      if [ "$current" != disabled ]; then
        echo "disabling Determinate telemetry in ${label}..." >&2
        ${plistBuddy} -c 'Add :EnvironmentVariables dict' ${plist} 2>/dev/null || true
        ${plistBuddy} -c 'Delete :EnvironmentVariables:DETSYS_IDS_TELEMETRY' ${plist} 2>/dev/null || true
        ${plistBuddy} -c 'Add :EnvironmentVariables:DETSYS_IDS_TELEMETRY string disabled' ${plist}
        launchctl bootout system/${label} 2>/dev/null || true
        # bootout returns before the job is fully gone; bootstrap fails with EIO until it is.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          launchctl bootstrap system ${plist} 2>/dev/null && break
          sleep 1
        done
        launchctl print system/${label} >/dev/null \
          || echo "warning: ${label} did not come back; run: sudo launchctl bootstrap system ${plist}" >&2
      fi
    fi
  '';
}
