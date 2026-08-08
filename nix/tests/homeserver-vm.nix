{
  pkgs,
  user,
  ...
}:
# Boots the home server config in a VM and drives one request end to end.
#
# This is the safety net for a migration that has no per-service rollback: the old
# Proxmox is wiped in one go, so "it builds" is not enough — the services have to
# actually come up. Two things here are otherwise unverifiable from a Mac:
#   - gatus's settings are a freeform attrset, so a wrong key type-checks fine in
#     nix and only fails when gatus parses its YAML
#   - the Caddyfile is assembled by string interpolation in hosts/homeserver.nix
#
# status.gapul.net is the one vhost whose upstream lives inside the VM (gatus on
# localhost), so a single request through caddy exercises the generated Caddyfile,
# the cert wiring, the proxy, and gatus all at once.
pkgs.testers.runNixOSTest {
  name = "homeserver-vm";

  node.specialArgs = { inherit user; };
  node.pkgsReadOnly = false;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../hosts/homeserver.nix
      ];

      # disko is not imported, so the test framework supplies the root filesystem
      # and none of the ZFS config applies. Boot/hardware bits that a VM provides
      # itself have to be pushed out of the way.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
      boot.kernelParams = lib.mkForce [ ];

      # No tailnet to join, and nothing under test needs it.
      services.tailscale.enable = lib.mkForce false;

      # lego cannot run (no Cloudflare token, no DNS), so acme-gapul.net fails and
      # its finished target never activates. The preliminary self-signed cert that
      # security.acme writes first is enough for caddy to load `tls`, so drop the
      # ordering the real host needs and let caddy start straight away.
      systemd.services.caddy.after = lib.mkForce [ "network.target" ];
      systemd.services.caddy.wants = lib.mkForce [ ];

      virtualisation.graphics = false;
      virtualisation.memorySize = 2048;
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # gatus parses its own YAML at startup; reaching this line means the settings
    # generated from the `sites` table are schema-valid.
    machine.wait_for_unit("gatus.service")
    machine.wait_for_open_port(8084)

    machine.wait_for_unit("caddy.service")
    machine.wait_for_open_port(443)

    status = machine.succeed(
        "curl -sk --resolve status.gapul.net:443:127.0.0.1"
        " -o /dev/null -w '%{http_code}' https://status.gapul.net/"
    ).strip()
    assert status == "200", f"caddy -> gatus returned {status}, expected 200"

    # A vhost whose upstream is off-box must still be routed by caddy rather than
    # rejected outright: a 502 proves the vhost matched and the proxy tried.
    upstream = machine.succeed(
        "curl -sk --resolve vault.gapul.net:443:127.0.0.1"
        " -o /dev/null -w '%{http_code}' https://vault.gapul.net/"
    ).strip()
    assert upstream == "502", f"unreachable upstream gave {upstream}, expected 502"

    # podman is what replaces the docker daemon the containers run under today.
    machine.succeed("podman --version")

    # The services that stopped being containers. Each one is config that used to
    # live in a web UI or a command line, so "it parses and starts" is the claim.
    machine.wait_for_unit("adguardhome.service")
    machine.wait_for_open_port(3080)
    machine.succeed("ss -lntup | grep -q ':53 '")
    machine.wait_for_unit("syncthing.service")
    machine.succeed("systemctl is-enabled samba-smbd.service")

    # backrest's replacement is a timer, so there is nothing to connect to.
    machine.succeed("systemctl is-enabled restic-backups-homeserver.timer")
  '';
}
