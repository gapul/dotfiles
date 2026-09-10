{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Speech synthesis is a server workload.  Keep the model cache and the
  # resident engine on the always-on Mac mini; workstation clients use the
  # stable Tailscale address below.
  aivisEngine = pkgs.callPackage ../pkgs/aivisspeech-engine.nix { };
in
{
  home.packages = [ aivisEngine ];

  home.activation.aivisSpeechStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /bin/mkdir -p "${config.home.homeDirectory}/.local/share/AivisSpeech-Engine"
  '';

  launchd.agents.aivisspeech-engine = {
    enable = true;
    config = {
      ProgramArguments = [
        "${lib.getExe aivisEngine}"
        "--host"
        "0.0.0.0"
        "--port"
        "10101"
        "--no-use_gpu"
        "--disable_sentry"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/aivisspeech-engine.log";
      StandardErrorPath = "/tmp/aivisspeech-engine.log";
    };
  };
}
