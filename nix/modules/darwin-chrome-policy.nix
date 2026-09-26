# Google Chrome as the browser with no filtering in front of it (hosts/darwin.nix explains why
# the cask is back). The home DNS (blocky on the tailnet, lib/blocky-settings.nix) drops affiliate
# click-tracking hosts on purpose, and a point-site card application routed through them is
# silently rejected weeks later. Chrome resolves through DNS-over-HTTPS to 1.1.1.1 instead, so
# the system resolver never sees its queries, and blocky stays strict for everything else.
#
# Only a managed policy makes Chrome do this reliably. Measured on 2026-09-27 with a headless
# Chrome 154 against https://one.one.one.one/help: a pre-seeded `dns_over_https` in the
# profile's Local State and a user-level `defaults write com.google.Chrome` both left DoH off;
# a root-owned plist under /Library/Managed Preferences turned it on ("Using DoH: Yes"). Chrome
# treats that directory as MDM-delivered, so the policy is mandatory and the UI cannot undo it.
#
# Written as a copy rather than a symlink into the store: cfprefsd reads managed preferences
# from regular files and re-reads them when the file changes. Runs as root in postActivation,
# which nix-darwin executes on every switch, so the file tracks this declaration.
{
  lib,
  pkgs,
  user,
  ...
}:
let
  policy = {
    DnsOverHttpsMode = "secure";
    # Space-separated list; the second is Cloudflare's other anycast address. Given by IP on
    # purpose: a hostname here would have to be resolved through the very resolver being bypassed.
    DnsOverHttpsTemplates = "https://1.1.1.1/dns-query https://1.0.0.1/dns-query";
  };
  plist = pkgs.writeText "com.google.Chrome.plist" (lib.generators.toPlist { } policy);
  dir = "/Library/Managed Preferences/${user.username}";
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    /bin/mkdir -p "${dir}"
    if ! /usr/bin/cmp -s ${plist} "${dir}/com.google.Chrome.plist"; then
      /usr/bin/install -m 0644 -o root -g wheel ${plist} "${dir}/com.google.Chrome.plist"
      # cfprefsd caches managed preferences per user; a running Chrome picks the change up on
      # its next start, cfprefsd itself on its next launch.
      /usr/bin/killall -u ${user.username} cfprefsd 2>/dev/null || true
    fi
  '';
}
