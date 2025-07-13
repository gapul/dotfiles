{ config, lib, pkgs, ... }:

{
  imports = [
    # Development Environment
    ./development/modern-cli.nix
    ./development/ai-platform/ollama.nix
    ./development/ai-platform/cli-integration.nix
    ./development/project-env/project-detection.nix
    ./development/ci-cd/ci-cd-optimizer.nix

    # System Management
    ./system/health-check.nix
    ./system/notification.nix
    ./system/nix-darwin-management.nix

    # Security
    ./security/security-baseline.nix

    # Applications and Tools
    ./apps/editors.nix
    ./apps/terminal.nix
    ./apps/browsers.nix
    ./apps/productivity.nix
    ./apps/media.nix
    ./apps/utilities.nix
  ];

  # デフォルト設定の有効化
  config = {
    # Core system components (always enabled)
    dotfiles.system.health-check.enable = lib.mkDefault true;
    dotfiles.system.notification.enable = lib.mkDefault true;
    dotfiles.system.nix-darwin-management.enable = lib.mkDefault true;

    # Development tools (recommended)
    dotfiles.development.modern-cli.enable = lib.mkDefault true;
    dotfiles.development.ai-platform.ollama.enable = lib.mkDefault false; # Opt-in
    dotfiles.development.project-env.project-detection.enable = lib.mkDefault true;
    dotfiles.development.ci-cd.optimizer.enable = lib.mkDefault false; # Opt-in

    # Security baseline (recommended)
    dotfiles.security.baseline.enable = lib.mkDefault true;
  };
}