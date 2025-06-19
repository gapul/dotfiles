{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.containers;
in
{
  options.dotfiles.development.containers = {
    enable = mkEnableOption "Development containers support";
    
    dockerSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Docker-based development containers";
    };
    
    podmanSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Podman-based development containers";
    };
    
    vscodeIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable VS Code Dev Containers integration";
    };
    
    nixShellIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Nix shell integration with containers";
    };
    
    commonImages = mkOption {
      type = types.listOf types.str;
      default = [
        "mcr.microsoft.com/devcontainers/base:ubuntu"
        "mcr.microsoft.com/devcontainers/typescript-node"
        "mcr.microsoft.com/devcontainers/python"
        "mcr.microsoft.com/devcontainers/go"
        "mcr.microsoft.com/devcontainers/rust"
      ];
      description = "Common development container images to pre-pull";
    };
    
    customTemplates = mkOption {
      type = types.attrsOf types.path;
      default = {};
      description = "Custom devcontainer templates";
    };
    
    prebuiltImages = mkOption {
      type = types.listOf types.str;
      default = [
        "node:18"
        "python:3.11"
        "golang:1.21"
        "rust:latest"
        "ubuntu:22.04"
      ];
      description = "Images to pre-pull for faster container startup";
    };
    
    autoSetup = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically setup dev containers when entering project directories";
    };
    
    resourceLimits = mkOption {
      type = types.attrsOf types.str;
      default = {
        memory = "4g";
        cpus = "2";
        swap = "1g";
      };
      description = "Custom devcontainer templates";
    };
  };

  config = mkIf cfg.enable {
    # Docker support (NixOS only - macOS uses Docker Desktop via Homebrew)
    # programs.docker = mkIf (cfg.dockerSupport && pkgs.stdenv.isLinux) {
    #   enable = true;
    #   enableOnBoot = true;
    #   autoPrune = {
    #     enable = true;
    #     dates = "weekly";
    #     flags = [ "--all" ];
    #   };
    # };

    # Development tools
    home-manager.users.yuki.home.packages = with pkgs; [
      # Container tools
      docker-compose
      docker-buildx
      
      # Development container CLI
      devcontainer
      
      # Nix integration tools
      nixpkgs-fmt
      nil
      
      # VS Code extensions via nix-vscode-extensions
    ] ++ optionals cfg.podmanSupport [
      podman
      podman-compose
    ];

    # Development container configurations
    home-manager.users.yuki.home.file = mkMerge [
      # VS Code Dev Containers configuration
      (mkIf cfg.vscodeIntegration {
        ".vscode/settings.json".text = builtins.toJSON {
          "dev.containers.dockerPath" = "${pkgs.docker}/bin/docker";
          "dev.containers.dockerComposePath" = "${pkgs.docker-compose}/bin/docker-compose";
          "dev.containers.defaultExtensions" = [
            "ms-vscode-remote.remote-containers"
            "ms-vscode.vscode-json"
          ];
        };
      })
      
      # Nix shell integration scripts
      (mkIf cfg.nixShellIntegration {
        "bin/devcontainer-nix" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Nix-integrated devcontainer launcher
        set -euo pipefail
        
        DEVCONTAINER_JSON="$1"
        PROJECT_DIR="$(dirname "$DEVCONTAINER_JSON")"
        
        # Generate shell.nix if it doesn't exist
        if [[ ! -f "$PROJECT_DIR/shell.nix" ]]; then
          cat > "$PROJECT_DIR/shell.nix" << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        
        pkgs.mkShell {
          buildInputs = with pkgs; [
            # Add project-specific dependencies here
          ];
          
          shellHook = '''
            echo "Development environment ready!"
          ''';
        }
        EOF
        fi
        
        # Launch devcontainer with Nix integration
        ${pkgs.devcontainer}/bin/devcontainer up --workspace-folder "$PROJECT_DIR"
      '';
        };
      })
    ];

    # Container health monitoring (NixOS only - disabled for macOS compatibility)
    # systemd.user.services.devcontainer-monitor = mkIf (cfg.dockerSupport && pkgs.stdenv.isLinux) {
    #   Unit = {
    #     Description = "Development container health monitor";
    #     After = [ "docker.service" ];
    #   };
    #   
    #   Service = {
    #     Type = "oneshot";
    #     ExecStart = ''
    #       ${pkgs.docker}/bin/docker system prune -f --volumes --filter "until=24h"
    #     '';
    #   };
    #   
    #   Install = {
    #     WantedBy = [ "default.target" ];
    #   };
    # };
    # 
    # systemd.user.timers.devcontainer-monitor = mkIf (cfg.dockerSupport && pkgs.stdenv.isLinux) {
    #   Unit = {
    #     Description = "Run devcontainer monitor daily";
    #   };
    #   
    #   Timer = {
    #     OnCalendar = "daily";
    #     Persistent = true;
    #   };
    #   
    #   Install = {
    #     WantedBy = [ "timers.target" ];
    #   };
    # };

    # macOS-specific Docker Desktop integration (disabled for compatibility)
    # Note: launchd configuration requires system-level nix-darwin module access
    # This would typically be configured at the system level, not in home-manager
    /*
    launchd.agents.docker-desktop-integration = mkIf (cfg.dockerSupport && pkgs.stdenv.isDarwin) {
      serviceConfig = {
        Label = "com.docker.docker-desktop-integration";
        ProgramArguments = [
          "${pkgs.docker}/bin/docker"
          "system"
          "events"
          "--format"
          "json"
        ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };
    */
  };
}