{
  config,
  lib,
  pkgs,
  ...
}:
let
  agentStateRepo = "${config.home.homeDirectory}/Developer/github.com/gapul/ai-agent-state";
  stateDir = "${config.xdg.stateHome}/ai-agent-state-sync";
in
{
  home.activation.agentStateSyncDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /bin/mkdir -p "${stateDir}"
  '';

  # Session files are mutable, so synchronize them out of band rather than making
  # the live Claude/Codex directories Git worktrees. The script only publishes from
  # a device whose live state changed; idle devices only pull and restore.
  launchd.agents.ai-agent-state-sync = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "ai-agent-state-sync" ''
          export PATH="${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
          export CODEX_HOME="${config.xdg.dataHome}/codex"
          export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude"
          export XDG_STATE_HOME="${config.xdg.stateHome}"
          exec "${agentStateRepo}/scripts/sync-auto"
        ''}"
      ];
      RunAtLoad = true;
      StartInterval = 60;
      ThrottleInterval = 30;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "${stateDir}/sync.log";
      StandardErrorPath = "${stateDir}/sync.log";
    };
  };
}
