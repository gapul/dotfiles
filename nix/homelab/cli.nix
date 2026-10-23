{
  lib,
  pkgs,
  ...
}:
let
  # HTTP goes through Bun's fetch; jq is only used to colour JSON output.
  hs = import ../lib/bun-script.nix { inherit pkgs; } {
    name = "hs";
    # Only hs.ts, so editing the rest of configs/homelab does not rebuild the CLI.
    src = lib.fileset.toSource {
      root = ../../configs/homelab;
      fileset = ../../configs/homelab/hs.ts;
    };
    main = "hs.ts";
    runtimeInputs = with pkgs; [
      jq
      openssh
      podman
      rclone
      restic
      systemd
      ytdl-sub
    ];
  };
in
{
  # Mail migration staging: mbsync mirrors the provider's IMAP mailbox and
  # notmuch indexes the mirror locally.  No account or credentials are
  # configured here; adding the packages is intentionally inert until the
  # Sakura migration is scheduled.
  environment.systemPackages = [
    hs
    pkgs.isync
    pkgs.notmuch
  ];

  environment.etc."homelab/ytdl-sub-config.yaml".source = ../../configs/homelab/ytdl-sub-config.yaml;
  environment.etc."homelab/ytdl-sub-subscriptions.yaml".source =
    ../../configs/homelab/ytdl-sub-subscriptions.yaml;
  environment.etc."homelab/formera/example-form.json".source =
    ../../configs/homelab/formera/example-form.json;

  systemd.services.api-contract-check = {
    description = "Check that supported application APIs still exist";
    path = [ pkgs.curl ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/api-contract-check.sh}";
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };

  systemd.timers.api-contract-check = {
    description = "Daily application API contract check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:30:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };
}
