# Nix Quality of Life Tools
# Enhances Nix development experience with better tooling and visualization

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.nix-qol;
in
{
  options.dotfiles.development.nix-qol = {
    enable = mkEnableOption "Nix Quality of Life tools";
    
    nom = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable nix-output-monitor (nom) for better build output";
      };
    };
    
    tree = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable nix-tree for dependency visualization";
      };
    };
    
    fastfetch = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable fastfetch for system information";
      };
    };
    
    aliases = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable convenient aliases for Nix commands";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install QoL packages
    home-manager.users.yuki.home.packages = with pkgs; [
      # Nix visualization and monitoring
    ] ++ optionals cfg.nom.enable [
      nix-output-monitor  # Better build output with progress bars
    ] ++ optionals cfg.tree.enable [
      nix-tree           # Interactive dependency tree explorer
    ] ++ optionals cfg.fastfetch.enable [
      fastfetch          # Fast system information display
    ];

    # Fastfetch configuration (managed by nix-qol, programs.fastfetch disabled in flake.nix)
    home-manager.users.yuki.home.file.".config/fastfetch/config.jsonc" = mkIf cfg.fastfetch.enable {
      text = builtins.toJSON {
        "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
        logo = {
          source = "auto";
          type = "auto";
          width = 65;
          height = 20;
        };
        display = {
          size = {
            binaryPrefix = "si";
          };
          color = {
            keys = "blue";
            title = "blue";
          };
          separator = " → ";
        };
        modules = [
          {
            type = "title";
            color = {
              user = "blue";
              at = "white";
              host = "green";
            };
          }
          "separator"
          "os"
          "host" 
          "kernel"
          "uptime"
          "packages"
          "shell"
          {
            type = "display";
            compactType = "original";
          }
          "de"
          "wm"
          "wmtheme"
          "theme"
          "icons"
          "font"
          "cursor"
          "terminal"
          "terminalfont"
          "cpu"
          "gpu"
          "memory"
          "swap"
          "disk"
          "localip"
          "battery"
          "poweradapter"
          "locale"
          "break"
          {
            type = "colors";
            paddingLeft = 2;
            symbol = "circle";
          }
        ];
      };
    };

    # Shell aliases for enhanced Nix commands
    home-manager.users.yuki.programs.zsh.shellAliases = mkIf cfg.aliases.enable (mkMerge [
      # Basic Nix commands with nom
      (mkIf cfg.nom.enable {
        "nb" = "nom build";  # nix-build with progress (nom)
        "nix-shell" = "nom develop"; 
        "ns" = "nom develop";
      })
      
      # Nix tree exploration
      (mkIf cfg.tree.enable {
        "nix-deps" = "nix-tree";
        "ndeps" = "nix-tree";
        "nix-why" = "nix-tree --why";
      })
      
      # System information
      (mkIf cfg.fastfetch.enable {
        "sysinfo" = "fastfetch";
        "sys" = "fastfetch";
        "neofetch" = "fastfetch";  # Alias for muscle memory
      })
      
      # Enhanced Nix operations
      {
        "nix-gc" = "nix store gc --verbose";
        "nix-clean" = "nix-collect-garbage -d && nix store optimise";
        "nix-generations" = "nix profile history";
        "nix-search" = "nix search nixpkgs";
        "nix-info" = "nix-shell -p nix-info --run nix-info";
        "flake-update" = "nix flake update";
        "flake-check" = "nix flake check";
        "flake-show" = "nix flake show";
      }
    ]);

    # Nix configuration for better UX
    home-manager.users.yuki.home.sessionVariables = {
      # Enable nom for build commands
      NIX_OUTPUT_MONITOR = mkIf cfg.nom.enable "1";
    };

    # Shell functions for advanced Nix operations
    home-manager.users.yuki.programs.zsh.initContent = mkIf cfg.enable ''
      # Nix QoL functions
      
      # Show package information with tree view
      nix-package-info() {
        if [[ -z "$1" ]]; then
          echo "Usage: nix-package-info <package-name>"
          return 1
        fi
        
        echo "📦 Package Information: $1"
        echo "========================"
        
        # Search for package
        echo "🔍 Search results:"
        nix search nixpkgs "$1" | head -10
        echo ""
        
        # Show package details if available
        if nix-instantiate --eval -E "with import <nixpkgs> {}; $1.meta.description or null" 2>/dev/null; then
          echo "📋 Description:"
          nix-instantiate --eval -E "with import <nixpkgs> {}; $1.meta.description" 2>/dev/null | tr -d '"'
          echo ""
        fi
      }
      
      # Build and explore dependencies  
      nb-explore() {
        if [[ -z "$1" ]]; then
          echo "Usage: nb-explore <derivation>"
          return 1
        fi
        
        echo "🏗️  Building with monitoring..."
        ${if cfg.nom.enable then "nom build" else "nix build"} "$1"
        
        if [[ $? -eq 0 ]]; then
          echo "✅ Build successful!"
          if command -v nix-tree >/dev/null 2>&1; then
            echo "🌳 Exploring dependencies..."
            nix-tree "$1"
          fi
        fi
      }
      
      # System cleanup with progress
      nix-cleanup() {
        echo "🧹 Nix System Cleanup"
        echo "===================="
        
        echo "📊 Current store size:"
        du -sh /nix/store 2>/dev/null || echo "Could not measure store size"
        
        echo ""
        echo "🗑️  Collecting garbage..."
        nix-collect-garbage -d
        
        echo ""
        echo "🔧 Optimizing store..."
        nix store optimise
        
        echo ""
        echo "📊 New store size:"
        du -sh /nix/store 2>/dev/null || echo "Could not measure store size"
        
        ${if cfg.fastfetch.enable then ''
          echo ""
          echo "🖥️  System information:"
          fastfetch
        '' else ""}
      }
      
      # Flake development helper
      nix-dev() {
        local flake_path="''${1:-.}"
        echo "🚀 Entering development environment: $flake_path"
        
        if [[ -f "$flake_path/flake.nix" ]]; then
          ${if cfg.nom.enable then "nom develop" else "nix develop"} "$flake_path"
        else
          echo "❌ No flake.nix found in $flake_path"
          return 1
        fi
      }
    '';

    # Health check script
    home-manager.users.yuki.home.file."bin/nix-qol-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Nix QoL Tools Health Check
        set -euo pipefail
        
        echo "🔧 Nix Quality of Life Tools Health Check"
        echo "========================================"
        
        # Check nix-output-monitor
        ${if cfg.nom.enable then ''
          if command -v nom >/dev/null 2>&1; then
            echo "✅ nix-output-monitor (nom): Available"
            echo "   Try: nom build .#some-package"
          else
            echo "❌ nix-output-monitor (nom): Not found"
          fi
        '' else ''
          echo "⚪ nix-output-monitor: Disabled"
        ''}
        
        # Check nix-tree
        ${if cfg.tree.enable then ''
          if command -v nix-tree >/dev/null 2>&1; then
            echo "✅ nix-tree: Available"
            echo "   Try: nix-tree .#some-package"
          else
            echo "❌ nix-tree: Not found"
          fi
        '' else ''
          echo "⚪ nix-tree: Disabled"
        ''}
        
        # Check fastfetch
        ${if cfg.fastfetch.enable then ''
          if command -v fastfetch >/dev/null 2>&1; then
            echo "✅ fastfetch: Available"
            echo "   Try: fastfetch"
          else
            echo "❌ fastfetch: Not found"
          fi
        '' else ''
          echo "⚪ fastfetch: Disabled"
        ''}
        
        echo ""
        echo "🛠️  Available functions:"
        echo "   • nix-package-info <package>  - Package information with tree"
        echo "   • nb-explore <drv>            - Build and explore dependencies"
        echo "   • nix-cleanup                 - System cleanup with progress"
        echo "   • nix-dev [path]              - Enter development environment"
        
        echo ""
        echo "🔗 Useful aliases:"
        ${if cfg.aliases.enable then ''
          echo "   • nb         - nom build"
          echo "   • ns         - nom develop"  
          echo "   • ndeps      - nix-tree"
          echo "   • sysinfo    - fastfetch"
          echo "   • nix-clean  - full cleanup"
        '' else ''
          echo "   • Aliases disabled"
        ''}
      '';
    };
  };
}