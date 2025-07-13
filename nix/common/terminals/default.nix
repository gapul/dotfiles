# Terminal Applications Configuration
# Terminal emulators and their configurations
{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./wezterm.nix
  ];

  options.dotfiles.terminals = {
    enable = mkEnableOption "Terminal applications configuration";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "Terminal configuration profile";
    };
    
    defaultTerminal = mkOption {
      type = types.enum [ "wezterm" "kitty" "alacritty" "terminal" ];
      default = "wezterm";
      description = "Default terminal application";
    };
  };

  config = mkIf config.dotfiles.terminals.enable {
    # Enable terminal applications based on profile
    dotfiles.terminals.wezterm.enable = mkDefault (
      config.dotfiles.terminals.defaultTerminal == "wezterm"
    );
    
    # Terminal applications via Homebrew for better macOS integration
    homebrew.casks = mkIf (config.dotfiles.terminals.profile != "minimal") [
      "wezterm"
      "kitty"
      "alacritty"
    ];
  };
}