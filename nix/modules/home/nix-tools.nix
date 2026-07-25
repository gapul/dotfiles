# Nix ツール component (ECS: profile)。nix-index/comma/agent-skills/nh。
{
  config,
  pkgs,
  lib,
  agentSkills ? null,
  ...
}:
{
  # Weekly generated database: nix-locate / command-not-found / comma を
  # ローカルDB構築なしで全OS共通利用する。
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

  # nh: nh darwin / nh home の便利ラッパー
  programs.nh = {
    enable = true;
    flake = "${config.home.homeDirectory}/.dotfiles/nix";
  };
}
