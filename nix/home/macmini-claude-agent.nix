# claude-agent: automatic fixes and reviews, resident on the mac mini.
#
# When an issue is opened, when a GitHub Actions run fails, or when a pull request
# appears, Claude Code on the mini opens a fixing pull request or leaves a review.
#
# ## Why this lives in home-manager and not in the system config
#
# nix-darwin's system-level launchd.agents land in /Library/LaunchAgents, and on a
# machine with no GUI login they start in a root context. claude refuses
# --dangerously-skip-permissions under root or sudo, which is how the predecessor of
# this agent spent every hour of 2026-09 waking up and achieving nothing. Owning the
# LaunchAgent as the user removes the problem rather than working around it.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  home = config.home.homeDirectory;
  runtime = ../../configs/macmini/claude-agent;
  stateDir = "${config.xdg.stateHome}/claude-agent";

  # One entry point for everything: launchd, the per-repository caller workflow
  # (which runs on the self-hosted runner on this same machine), and running it by
  # hand. The real files sit in the store, so the only way to change the agent is to
  # edit the repository and rebuild — what is running cannot be edited in place.
  # The whole directory goes into the store, so lib.ts and repos.json sit next to the
  # entry point. lib.ts sets PATH itself (gh, git and claude come from the user profile).
  entry = import ../lib/bun-script.nix { inherit pkgs; } {
    name = "claude-agent";
    src = runtime;
    main = "claude-agent.ts";
  };

  # launchd carries almost no shell environment, so hand over what the scripts need.
  # LANG is passed on to git, gh and claude. (When this was bash it was not optional:
  # with an empty locale bash swallowed the multi-byte character after a variable
  # reference into the variable's name and died under set -u. The predecessor of this
  # agent lost a full day to exactly that.)
  agentEnv = {
    HOME = home;
    LANG = "en_US.UTF-8";
    XDG_STATE_HOME = config.xdg.stateHome;
    CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
  };

  mkAgent =
    {
      command,
      interval,
      logName,
    }:
    {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe entry)
          command
        ];
        RunAtLoad = true;
        StartInterval = interval;
        # "Background" is a band macOS may throttle and eventually reap. A claude run
        # can take tens of minutes, so use "Standard", which keeps the low IO priority
        # and the nice value but stops the reaping.
        ProcessType = "Standard";
        LowPriorityIO = true;
        Nice = 10;
        EnvironmentVariables = agentEnv;
        StandardOutPath = "${stateDir}/${logName}.log";
        StandardErrorPath = "${stateDir}/${logName}.log";
      };
    };
in
{
  home.file.".local/bin/claude-agent".source = lib.getExe entry;

  home.activation.claudeAgentDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /bin/mkdir -p "${stateDir}/logs" "${stateDir}/seen" "${stateDir}/repos"
  '';

  # Walk repos.json every five minutes. Reacting immediately to an event is the
  # caller workflow's job in each repository; this is the net underneath it.
  launchd.agents.claude-agent-poll = mkAgent {
    command = "poll";
    interval = 300;
    logName = "poller";
  };

  # Check the agent's own health once an hour. Deliberately not run through GitHub
  # Actions: monitoring built on top of the watched system goes quiet exactly when
  # that system breaks.
  launchd.agents.claude-agent-monitor = mkAgent {
    command = "monitor";
    interval = 3600;
    logName = "monitor";
  };
}
