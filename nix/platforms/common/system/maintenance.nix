{ config, lib, pkgs, ... }:

with lib;

{
  options.dotfiles.system.maintenance = {
    enable = mkEnableOption "System maintenance automation";
    
    autoGarbageCollection = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic garbage collection";
    };
    
    autoOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic store optimization";
    };
    
    retentionDays = mkOption {
      type = types.int;
      default = 30;
      description = "Number of days to retain old generations";
    };
  };

  config = mkIf config.dotfiles.system.maintenance.enable {
    # Nix maintenance automation
    nix = {
      # Automatic garbage collection
      gc = mkIf config.dotfiles.system.maintenance.autoGarbageCollection {
        automatic = true;
        interval = { Weekday = 7; Hour = 3; Minute = 0; };  # Weekly on Sunday 3AM
        options = "--delete-older-than ${toString config.dotfiles.system.maintenance.retentionDays}d";
      };
      
      # Automatic store optimization
      optimise = mkIf config.dotfiles.system.maintenance.autoOptimization {
        automatic = true;
        interval = { Weekday = 7; Hour = 4; Minute = 0; };  # After GC on Sunday 4AM
      };
    };
    
    # Maintenance tools available system-wide
    environment.systemPackages = with pkgs; [
      # System maintenance utilities
      ncdu          # Disk usage analyzer
      dust          # Modern du replacement
      procs         # Modern ps replacement
      bottom        # System monitor
      
      # Nix-specific tools
      nix-tree      # Nix store analysis
      nix-du        # Nix store disk usage
    ];
    
    # System-wide shell aliases for maintenance
    environment.shellAliases = {
      # Nix maintenance commands
      nix-gc = "nix-collect-garbage --delete-older-than ${toString config.dotfiles.system.maintenance.retentionDays}d";
      nix-gc-all = "nix-collect-garbage -d";
      nix-optimize = "nix store optimise";
      nix-repair = "nix store repair";
      
      # System information
      nix-size = "nix path-info -Sh";
      nix-generations = "nix profile history";
      
      # Darwin-specific (when available)
      darwin-generations = "darwin-rebuild --list-generations";
      hm-generations = "home-manager generations";
    };
  };
}