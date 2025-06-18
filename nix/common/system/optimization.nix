{ config, lib, pkgs, ... }:

with lib;

{
  options.dotfiles.system.optimization = {
    enable = mkEnableOption "System optimization configuration";
    
    nixBuildOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Nix build optimization settings";
    };
    
    macOSOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable macOS-specific optimizations";
    };
    
    performanceProfiles = mkOption {
      type = types.enum [ "balanced" "performance" "battery" ];
      default = "balanced";
      description = "System performance profile";
    };
  };

  config = mkIf config.dotfiles.system.optimization.enable {
    # Nix daemon optimization (for nix-darwin)
    nix = mkIf config.dotfiles.system.optimization.nixBuildOptimization {
      settings = {
        # Build optimization
        max-jobs = "auto";
        cores = 0;
        
        # Binary caches for faster builds
        substituters = [
          "https://cache.nixos.org/"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
        
        # Store optimization
        auto-optimise-store = true;
        min-free = 1073741824;    # 1GB
        max-free = 5368709120;    # 5GB
        
        # Experimental features
        experimental-features = [ "nix-command" "flakes" ];
        
        # Development features
        keep-outputs = true;
        keep-derivations = true;
        
        # Security
        sandbox = true;
        
        # Logging
        log-lines = 50;
        show-trace = true;
      };
      
      # Garbage collection automation
      gc = {
        automatic = true;
        interval = { Weekday = 7; Hour = 3; Minute = 0; };  # Weekly on Sunday 3AM
        options = "--delete-older-than 30d";
      };
      
      # Store optimization
      optimise = {
        automatic = true;
        interval = { Weekday = 7; Hour = 4; Minute = 0; };  # After GC
      };
    };
    
    # macOS specific optimizations
    system = mkIf (config.dotfiles.system.optimization.macOSOptimization && pkgs.stdenv.isDarwin) {
      defaults = {
        # Performance optimizations
        NSGlobalDomain = {
          # Faster animation times
          NSWindowResizeTime = 0.1;
          
          # Disable automatic termination of inactive apps  
          NSDisableAutomaticTermination = false;
          
          # Performance profile based settings
        } // (if config.dotfiles.system.optimization.performanceProfiles == "performance" then {
          # High performance settings
          NSAutomaticWindowAnimationsEnabled = false;
          NSScrollAnimationEnabled = false;
        } else if config.dotfiles.system.optimization.performanceProfiles == "battery" then {
          # Battery optimized settings
          NSAppSleepDisabled = false;
        } else {
          # Balanced settings (default)
        });
        
        dock = {
          # Faster dock animations
          autohide-delay = 0.0;
          autohide-time-modifier = 0.2;
          expose-animation-duration = 0.1;
          launchanim = false;
        };
        
        finder = {
          # Disable disk image verification
          DisableAllAnimations = (config.dotfiles.system.optimization.performanceProfiles == "performance");
        };
        
        # Disable spotlight indexing on mounted volumes
        ".GlobalPreferences"."com.apple.SpotlightServer" = {
          ExternalVolumesIgnore = true;
          InternalVolumesIgnore = false;
        };
      };
    };
    
    # System-wide optimization packages
    environment.systemPackages = with pkgs; [
      # Performance monitoring tools
      htop
      btop
      bottom
      
      # Disk optimization
      ncdu
      dust
      
      # Memory optimization
      procs
    ];
  };
}