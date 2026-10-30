# Helium's DNS over HTTPS to the home blocky (dns2.gapul.net, the same endpoint the iOS
# profile uses). The system resolver already reaches blocky inside the tailnet's WireGuard, so
# this is not about hiding the queries: Chromium only turns Encrypted Client Hello on when the
# HTTPS records come from its own DoH resolver, so this is what hides the server name (SNI).
# Blocking is unchanged, because the answers come from the same blocky.
#
# A managed plist for the same reason as modules/darwin-chrome-policy.nix: DoH is not taken from
# the user-level defaults that modules/home/darwin-helium.nix writes (those arrive as
# "Recommended"). Only these keys become mandatory; the rest of that domain stays recommended.
{
  lib,
  pkgs,
  user,
  ...
}:
let
  policy = {
    # automatic, not secure: dns2 is a tailnet address served by the homeserver alone, and with
    # Tailscale off or the homeserver down Helium falls back to the system resolver instead of
    # failing every lookup.
    DnsOverHttpsMode = "automatic";
    DnsOverHttpsTemplates = "https://dns2.gapul.net/dns-query";
  };
  plist = pkgs.writeText "net.imput.helium.plist" (lib.generators.toPlist { escape = true; } policy);
  dir = "/Library/Managed Preferences/${user.username}";
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    /bin/mkdir -p "${dir}"
    if ! /usr/bin/cmp -s ${plist} "${dir}/net.imput.helium.plist"; then
      /usr/bin/install -m 0644 -o root -g wheel ${plist} "${dir}/net.imput.helium.plist"
      /usr/bin/killall -u ${user.username} cfprefsd 2>/dev/null || true
    fi
  '';
}
