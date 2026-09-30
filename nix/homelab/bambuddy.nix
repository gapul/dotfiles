# Control panel for the Bambu printer (Bambuddy). Where the phone goes to "pick from the SD
# card and print".
#
# Background. Bambu's Authorization Control blocked starting prints from third-party
# slicers. Putting the printer in LAN Only + Developer Mode restores local control, but at
# the cost of killing Bambu Handy — it's a cloud-dependent app, so it won't connect even on
# the same Wi-Fi. The "check on it from outside" and "pick a file and print" roles Handy
# had now land here.
#
# Both this and Home Assistant's ha-bambulab are kept because their roles differ. That one is
# the monitoring and automation side; its only public service is send_command, and pybambu has
# no FTP, so it can't list files on the SD card. Uploading, selecting, and deleting belong here.
#
# It also includes a firmware update helper for LAN-only setups. Every published version gets
# a Usable / Unavailable / Installed badge, so this is also the place for the monthly check
# (OTA doesn't arrive while in LAN Only, so the update itself is done by hand via microSD).
#
# Runs on bridge. Upstream's compose defaults to host networking, but that's for finding the
# printer via SSDP, and on this box both 8000 and 3000 are already taken. The printer can be
# added by IP (192.168.116.97), so dropping discovery to avoid the conflicts is the better
# trade. The virtual printer feature (990 / 8883 / 322 / 50000-) isn't used either, so only
# the one UI port needs to be open.
#
# No secrets needed. The printer's access code is entered in the UI and stored in the data
# directory. There are no files to place by hand before rebuild.
{
  lib,
  ...
}:

{
  # A new service, so no data migrates from an old host. Create the bind mount sources first.
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/bambuddy 0700 root root -"
    "d /var/lib/homelab/bambuddy/data 0700 root root -"
    "d /var/lib/homelab/bambuddy/logs 0700 root root -"
  ];

  virtualisation.oci-containers.containers."bambuddy" = {
    # Beta tags (0.2.2b1 etc.) never become latest by design, so latest points at stable.
    # latest is fine, consistent with the other stacks.
    image = "ghcr.io/maziggy/bambuddy:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
      # The entrypoint chowns /app/data and /app/logs, then drops privileges with gosu.
      # The default 1000:1000 can't write to the root-owned bind mount sources, so it runs as
      # root like the other stacks.
      "PUID" = "0";
      "PGID" = "0";
      # This variable assumes host networking, but on bridge it still sets the listen port
      # inside the container, so set it explicitly. Externally it's exposed on 8010 via ports below.
      "PORT" = "8000";
    };
    volumes = [
      "/var/lib/homelab/bambuddy/data:/app/data:rw"
      "/var/lib/homelab/bambuddy/logs:/app/logs:rw"
    ];
    ports = [
      "8010:8000/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-bambuddy" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
