# Secondary home DNS. The primary is blocky on homeserver (homelab/blocky.nix).
#
# ## Why a second one is needed
#
# The router (192.168.116.254) hands itself out as DNS via DHCP, and its forwarding
# stopped. LAN devices couldn't resolve names while blocky, right next to it, answered
# normally (confirmed 2026-09-11). Pointing clients at blocky instead of the router removes
# that detour, but then name resolution for the whole house stops the moment blocky goes
# down. DHCP can hand out two servers, so put a second one in place before switching.
#
# This machine is chosen because it's always powered, on the same LAN, and already under
# declarative management.
#
# ## How it differs from the NixOS side
#
# nix-darwin has no services.blocky, so write the config file and start it as a launchd
# daemon. Port 53 is below 1024, so it runs as root (an agent isn't enough). The config
# contents are shared with homeserver via lib/blocky-settings.nix; the only difference
# is the listen address.
{ pkgs, ... }:
let
  # Every address on the host rather than a list of them. The LAN address is a DHCP reservation
  # (192.168.116.100) and the tailnet DNS setting points at the tailnet one (100.105.135.49), but
  # naming them made blocky depend on both being assigned: when the router lost its reservations
  # on 2026-10-09 this host came back as .77, the bind failed, and blocky restart-looped for a
  # week, taking the loopback and tailnet listeners down with the LAN one. macOS has no
  # ip_nonlocal_bind, and nothing else here wants port 53.
  settings = import ../lib/blocky-settings.nix {
    listen = ":53";
  };

  # blocky reads YAML. JSON is a subset of YAML, so it can be passed as is.
  configFile = pkgs.writeText "blocky.yml" (builtins.toJSON settings);

  # The macOS application firewall silently drops incoming connections to binaries it
  # doesn't recognize. Nix binaries are ad-hoc signed, so they hit this every time, and it
  # breaks in the most confusing way: resolvable from loopback, no response from the LAN
  # (same as ComfyUI's 8188).
  #
  # The allowance is added here, not in activation. ALF checks "allow incoming to this
  # binary?" when the process starts, so ordering is everything. In activation, there's no
  # guaranteed order between adding the allowance and launchd starting the daemon; in fact,
  # on the first deploy on 2026-09-11 the allowance was in place but the LAN still got no
  # response (fixed by restarting it by hand). Adding its own store path right before
  # startup means neither ordering nor updates need thought.
  #
  # The registration is retried in the background for a while. At boot the daemon starts
  # before the firewall accepts changes, the one-shot `--add` fails silently, and the entry
  # from the previous store path is all that is left: loopback answers, LAN and tailnet do
  # not (found 2026-09-26 after a rebuild had moved blocky to a new store path).
  launch = pkgs.writeShellScript "blocky-with-firewall" ''
    fw=/usr/libexec/ApplicationFirewall/socketfilterfw
    if [ -x "$fw" ]; then
      (
        for _ in 1 2 3 4 5 6; do
          "$fw" --add ${pkgs.blocky}/bin/blocky >/dev/null 2>&1
          "$fw" --unblockapp ${pkgs.blocky}/bin/blocky >/dev/null 2>&1
          # ALF keys the rule on the ad-hoc signing identifier, so --listapps keeps showing
          # the first store path that was ever added, not this one; any blocky entry means
          # the rule exists.
          "$fw" --listapps 2>/dev/null | grep -q -- "-blocky-[^/]*/bin/blocky" && exit 0
          sleep 20
        done
      ) &
    fi
    exec ${pkgs.blocky}/bin/blocky --config ${configFile}
  '';
in
{
  # `command` rather than ProgramArguments: nix-darwin then waits for /nix/store, which macOS 27
  # mounts after launchd starts daemons (see the minecraft daemons in macmini.nix).
  launchd.daemons.blocky = {
    command = "${launch}";
    serviceConfig = {
      RunAtLoad = true;
      # Restarts blocky if it exits for any other reason (list download panics, a bad config).
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "/var/log/blocky.log";
      StandardErrorPath = "/var/log/blocky.log";
    };
  };

  # This host's own lookups go through blocky too. The brew tailscaled (open source, not the App
  # Store build) only writes /etc/resolver/search.tailscale on macOS and cannot replace the
  # system resolver, so "Use Tailscale DNS" did nothing here: the Mac kept the router's DHCP DNS,
  # plain and unfiltered (found 2026-10-17). Local blocky first, homeserver over the tailnet when
  # it is down. No public server as a third entry: mDNSResponder races the listed servers rather
  # than trying them in order, so a public one would answer around the blocklists.
  networking.knownNetworkServices = [ "Ethernet" ];
  networking.dns = [
    "127.0.0.1"
    "100.127.129.31"
  ];
}
