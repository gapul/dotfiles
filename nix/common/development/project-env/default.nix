# Project-Specific Environment Auto-Setup
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.project-env;
in
{
  options.dotfiles.development.project-env = {
    enable = mkEnableOption "Project-specific environment auto-setup";
    
    supportedTypes = mkOption {
      type = types.listOf (types.enum [ 
        "nodejs" "python" "rust" "go" "php" "ruby" "java" "react" "nextjs" "vue" "angular" 
        "docker" "terraform" "nix" "general" 
      ]);
      default = [ "nodejs" "python" "rust" "go" "react" "nextjs" "docker" "nix" ];
      description = "Supported project types for auto-setup";
    };
    
    autoDetection = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically detect project type on directory change";
    };
    
    direnvIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable direnv integration for environment management";
    };
    
    nixShellGeneration = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically generate shell.nix files";
    };
  };

  config = mkIf cfg.enable {
    # Required packages for project environment management
    home-manager.users.yuki.home.packages = with pkgs; [
      # Environment management
      direnv
      
      # Language-specific tools
      nodejs
      python3
      rustc
      cargo
      go
      
      # Build tools
      gnumake
      
      # Project analysis
      tokei
      tree
    ];

    # Enable direnv integration
    home-manager.users.yuki.programs.direnv = mkIf cfg.direnvIntegration {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    # Project auto-setup script
    home-manager.users.yuki.home.file."bin/project-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Project Environment Auto-Setup
        set -euo pipefail
        
        PROJECT_NAME="''${1:-}"
        PROJECT_TYPE="''${2:-auto}"
        PROJECT_DIR="''${3:-.}"
        
        if [[ -z "$PROJECT_NAME" ]]; then
          echo "Usage: project-init <project_name> [type] [directory]"
          echo "Supported types: nodejs, python, rust, go, nix, react, nextjs"
          exit 1
        fi
        
        cd "$PROJECT_DIR"
        
        # Auto-detect project type if not specified
        if [[ "$PROJECT_TYPE" == "auto" ]]; then
          if [[ -f package.json ]]; then
            PROJECT_TYPE="nodejs"
          elif [[ -f Cargo.toml ]]; then
            PROJECT_TYPE="rust"
          elif [[ -f go.mod ]]; then
            PROJECT_TYPE="go"
          elif [[ -f requirements.txt ]]; then
            PROJECT_TYPE="python"
          elif [[ -f flake.nix ]]; then
            PROJECT_TYPE="nix"
          else
            PROJECT_TYPE="general"
          fi
        fi
        
        echo "🚀 Setting up $PROJECT_TYPE project: $PROJECT_NAME"
        
        # Create project structure based on type
        case "$PROJECT_TYPE" in
          "nodejs"|"react"|"nextjs")
            if [[ ! -f package.json ]]; then
              npm init -y
            fi
            
            ${if cfg.direnvIntegration then ''
              if [[ ! -f .envrc ]]; then
                echo "use node" > .envrc
              fi
            '' else ""}
            
            ${if cfg.nixShellGeneration then ''
              if [[ ! -f shell.nix ]]; then
                cat > shell.nix << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        pkgs.mkShell {
          buildInputs = with pkgs; [ nodejs npm ];
          shellHook = "echo 'Node.js development environment ready!'";
        }
        EOF
              fi
            '' else ""}
            ;;
            
          "python")
            if [[ ! -f requirements.txt ]]; then
              touch requirements.txt
            fi
            
            ${if cfg.direnvIntegration then ''
              if [[ ! -f .envrc ]]; then
                echo "use python" > .envrc
              fi
            '' else ""}
            ;;
            
          "rust")
            if [[ ! -f Cargo.toml ]]; then
              cargo init --name "$PROJECT_NAME" .
            fi
            ;;
            
          "go")
            if [[ ! -f go.mod ]]; then
              go mod init "$PROJECT_NAME"
            fi
            ;;
            
          "nix")
            if [[ ! -f flake.nix ]]; then
              cat > flake.nix << EOF
        {
          description = "$PROJECT_NAME";
          inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
          outputs = { self, nixpkgs }: {
            devShells.x86_64-linux.default = with nixpkgs.legacyPackages.x86_64-linux; mkShell {
              buildInputs = [ ];
            };
          };
        }
        EOF
            fi
            
            ${if cfg.direnvIntegration then ''
              if [[ ! -f .envrc ]]; then
                echo "use flake" > .envrc
              fi
            '' else ""}
            ;;
        esac
        
        echo "✅ Project setup complete!"
      '';
    };

    # Shell aliases for project management
    home-manager.users.yuki.programs.zsh.shellAliases = {
      proj-init = "project-init";
    };
  };
}