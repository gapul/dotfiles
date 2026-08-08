{
  # The one stack that could not be converted as a container. dperson/samba takes
  # its credentials as command-line arguments:
  #   command: -u "gapul;<password>" -s "media;/media;yes;no;no;gapul"
  # which put a live password in a compose file in this repo's reach, and in the
  # output of `ps` on the host. The native module keeps the share declarative and
  # the password out of nix entirely: samba stores it in its own tdb, set once by
  # hand with `sudo smbpasswd -a gapul` (same shape as `tailscale up`).
  #
  # Note the change in reach: the container published 139/445 on the LAN bridge,
  # while this host only trusts tailscale0. SMB is therefore tailnet-only now,
  # like everything else here. A LAN client would need those ports opened.
  services.samba = {
    enable = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "homeserver";
        "security" = "user";
        "map to guest" = "never";
      };
      media = {
        # /srv is what /mnt/jellyfin-media became: one dataset for bulk data.
        path = "/srv";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "gapul";
      };
    };
  };
}
