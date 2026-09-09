{
  pkgs,
  ...
}:
let
  hs = pkgs.writeShellApplication {
    name = "hs";
    runtimeInputs = with pkgs; [
      curl
      jq
      openssh
      podman
      rclone
      restic
      systemd
      util-linux
      ytdl-sub
    ];
    text = builtins.readFile ../../configs/homelab/hs.sh;
  };
in
{
  environment.systemPackages = [ hs ];

  environment.etc."homelab/ytdl-sub-config.yaml".source = ../../configs/homelab/ytdl-sub-config.yaml;
  environment.etc."homelab/ytdl-sub-subscriptions.yaml".source =
    ../../configs/homelab/ytdl-sub-subscriptions.yaml;

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
