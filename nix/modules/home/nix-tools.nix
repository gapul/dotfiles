# Nix tools component (ECS: profile). nix-index/comma/agent-skills/nh.
{
  config,
  ...
}:
{
  # Weekly generated database: use nix-locate / command-not-found / comma
  # commonly across all OSes without building a local DB.
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.nix-index-database.comma.enable = true;

  programs.agent-skills = {
    enable = true;
    sources.local = {
      path = ../../../configs/agents/skills;
      filter.maxDepth = 1;
    };
    skills.enableAll = [ "local" ];
    targets.agents.enable = true;
  };

  # nh: convenient wrapper for nh darwin / nh home
  programs.nh = {
    enable = true;
    flake = "${config.home.homeDirectory}/.dotfiles/nix";
  };
}
