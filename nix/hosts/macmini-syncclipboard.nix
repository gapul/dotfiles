{ pkgs, ... }:
let
  app = pkgs.callPackage ../pkgs/syncclipboard.nix { };
in
{
  # Credentials and localhost-only Kestrel config live in the user's private
  # Application Support/SyncClipboard directory, never in the Nix store.
  # Tailscale Serve exposes HTTPS port 5033 within the tailnet only.
  launchd.user.agents.syncclipboard.serviceConfig = {
    Label = "org.nixos.syncclipboard";
    ProgramArguments = [
      "${app}/Applications/SyncClipboard.app/Contents/MacOS/SyncClipboard.Desktop.MacOS"
      "--shutdown-previous"
    ];
    LimitLoadToSessionType = "Aqua";
    RunAtLoad = true;
    KeepAlive = true;
    ThrottleInterval = 10;
    StandardOutPath = "/Users/gapul/Library/Logs/syncclipboard-launchd.log";
    StandardErrorPath = "/Users/gapul/Library/Logs/syncclipboard-launchd.log";
  };
}
