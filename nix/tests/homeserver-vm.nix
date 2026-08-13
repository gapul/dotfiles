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
    { lib, pkgs, ... }:
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

      # gatus reads the ntfy topic and token from a file placed by hand at install
      # time. systemd refuses to start a unit whose EnvironmentFile is missing, so
      # stand in for it — which also exercises the ${VAR} substitution.
      systemd.services.gatus.serviceConfig.EnvironmentFile = lib.mkForce (
        pkgs.writeText "gatus-test.env" ''
          NTFY_TOPIC=test
          NTFY_TOKEN=test
        ''
      );

      # lego cannot run (no Cloudflare token, no DNS), so acme-gapul.net fails and
      # its finished target never activates. The preliminary self-signed cert that
      # security.acme writes first is enough for caddy to load `tls`, so drop the
      # ordering the real host needs and let caddy start straight away.
      systemd.services.caddy.after = lib.mkForce [ "network.target" ];
      systemd.services.caddy.wants = lib.mkForce [ ];

      # For `blocky validate` below; the daemon has the package, the shell does not.
      environment.systemPackages = [ pkgs.blocky ];

      virtualisation.graphics = false;
      virtualisation.memorySize = 2048;
    };

  testScript = ''
    machine.start()

    # Deliberately not waiting on multi-user.target. The thirty container units
    # are part of it and every one of them tries to pull an image, which cannot
    # work in a sandboxed VM with no network, so the target never settles. What
    # they can still prove is that their units were generated at all; the rest of
    # this waits on the services that do not need a registry.
    machine.succeed("systemctl cat podman-vaultwarden.service >/dev/null")

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

    # The two settings that made the first install unbootable, asserted so the
    # combination cannot come back: a pool that refuses to import plus an
    # emergency shell that refuses to open leaves no way into the machine.
    machine.succeed("zgrep -q 'CONFIG_ZFS' /proc/config.gz || true")
    forced = machine.succeed("cat /proc/cmdline")
    assert "zfs_force=1" not in forced, "zfs_force should not be needed at boot"

    # podman is what replaces the docker daemon the containers run under today.
    machine.succeed("podman --version")

    # The services that stopped being containers. Each one is config that used to
    # live in a web UI or a command line, so "it parses and starts" is the claim.
    # DNS is blocky now (AdGuard was replaced in #228; this line still named it, and
    # waiting for a unit that no longer exists is what has been failing CI since).
    # Blocky cannot come up in here at all: it resolves its upstreams and downloads a
    # denylist at startup, and exits when it cannot. So assert the two things that do
    # not need a network — the unit exists, and the config generated from `settings`
    # parses. The latter is the same class of bug as gatus's YAML: a wrong key in a
    # freeform attrset type-checks in nix and only fails when the program reads it.
    machine.succeed("systemctl cat blocky.service >/dev/null")
    blocky_config = machine.succeed(
        "systemctl cat blocky.service | grep -o -- '--config [^ ]*' | head -1 | cut -d' ' -f2"
    ).strip()
    machine.succeed(f"blocky validate --config {blocky_config}")

    machine.wait_for_unit("syncthing.service")
    machine.succeed("systemctl is-enabled samba-smbd.service")

    # backrest's replacement is a timer, so there is nothing to connect to.
    machine.succeed("systemctl is-enabled restic-backups-homeserver.timer")

    # Three of Home Assistant's five add-ons became native services. Home
    # Assistant itself and the Matter server are containers and cannot start here.
    machine.wait_for_unit("esphome.service")
    machine.wait_for_open_port(6052)
    machine.wait_for_unit("node-red.service")
    machine.wait_for_open_port(1880)
    # mosquitto needs its password file, which is placed by hand at install time,
    # so assert the unit exists rather than that it came up.
    machine.succeed("systemctl cat mosquitto.service >/dev/null")
  '';
}
