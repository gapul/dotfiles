# Multi-Platform Dotfiles Configuration
# Supports: macOS (nix-darwin), Linux (NixOS + non-NixOS), WSL, Android (nix-on-droid)
{
  description = "Cross-platform dotfiles configuration supporting macOS, Linux, WSL, and Android";

  inputs = {
    # Core inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Platform-specific systems
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # NixOS (for Linux support)
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    
    # Android support
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Secret management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Additional utilities
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, nixos-hardware, nix-on-droid, sops-nix, flake-utils }:
    let
      # Supported systems
      supportedSystems = [
        "aarch64-darwin"  # Apple Silicon macOS
        "x86_64-darwin"   # Intel macOS
        "x86_64-linux"    # Intel/AMD Linux
        "aarch64-linux"   # ARM Linux (including Android)
      ];
      
      # User configuration
      username = "yuki";
      homeDirectory = if builtins.pathExists "/Users" then "/Users/${username}" else "/home/${username}";
      dotfilesDirectory = "${homeDirectory}/dotfiles";
      
      # Platform detection and configuration
      mkPlatformConfig = system: 
        let
          lib = nixpkgs.lib;
          pkgs = nixpkgs.legacyPackages.${system};
          platformInfo = import ./common/platform-detection.nix { inherit lib pkgs; };
        in {
          inherit pkgs platformInfo lib;
          specialArgs = { inherit username homeDirectory dotfilesDirectory platformInfo; };
        };
      
      # Common modules for all platforms
      commonModules = [
        ./common/platform-detection.nix
        ./common/home/shell.nix
        ./common/themes/default.nix
        ./common/development/default.nix
        ./common/automation/default.nix
      ];
      
      # Darwin-specific modules
      darwinModules = commonModules ++ [
        ./darwin/system/default.nix
        sops-nix.darwinModules.sops
      ];
      
      # Linux-specific modules  
      linuxModules = commonModules ++ [
        ./linux/desktop/default.nix
      ];
      
      # WSL-specific modules
      wslModules = commonModules ++ [
        ./wsl/integration/default.nix
      ];
      
      # Android-specific modules
      androidModules = [
        ./android/termux/default.nix
      ];

    in
    {
      # macOS configurations (nix-darwin)
      darwinConfigurations = {
        # Apple Silicon Mac
        "Yukis-Laptop" = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = (mkPlatformConfig "aarch64-darwin").specialArgs;
          modules = darwinModules ++ [
            { nixpkgs.config.allowUnfree = true; }
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./common/home/shell.nix;
                extraSpecialArgs = (mkPlatformConfig "aarch64-darwin").specialArgs;
              };
            }
          ];
        };
        
        # Intel Mac
        "Intel-Mac" = nix-darwin.lib.darwinSystem {
          system = "x86_64-darwin";
          specialArgs = (mkPlatformConfig "x86_64-darwin").specialArgs;
          modules = darwinModules ++ [
            { nixpkgs.config.allowUnfree = true; }
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./common/home/shell.nix;
                extraSpecialArgs = (mkPlatformConfig "x86_64-darwin").specialArgs;
              };
            }
          ];
        };
        
        # Default (current system)
        default = if builtins.currentSystem == "aarch64-darwin" 
          then self.darwinConfigurations."Yukis-Laptop"
          else self.darwinConfigurations."Intel-Mac";
      };

      # NixOS configurations (for Linux)
      nixosConfigurations = {
        # Desktop Linux
        "linux-desktop" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = (mkPlatformConfig "x86_64-linux").specialArgs;
          modules = [
            # Hardware configuration would be system-specific
            { nixpkgs.config.allowUnfree = true; }
            ./linux/nixos/system.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./linux/nixos/home.nix;
                extraSpecialArgs = (mkPlatformConfig "x86_64-linux").specialArgs;
              };
            }
          ];
        };
        
        # ARM Linux (Raspberry Pi, etc.)
        "linux-arm" = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = (mkPlatformConfig "aarch64-linux").specialArgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ./linux/nixos/system.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./linux/nixos/home.nix;
                extraSpecialArgs = (mkPlatformConfig "aarch64-linux").specialArgs;
              };
            }
          ];
        };
      };

      # Standalone home-manager configurations (for non-NixOS Linux, WSL)
      homeConfigurations = {
        # Generic Linux (non-NixOS)
        "${username}@linux" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; };
          extraSpecialArgs = (mkPlatformConfig "x86_64-linux").specialArgs;
          modules = linuxModules;
        };
        
        # WSL configuration
        "${username}@wsl" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; };
          extraSpecialArgs = (mkPlatformConfig "x86_64-linux").specialArgs;
          modules = wslModules;
        };
        
        # ARM Linux home-manager only
        "${username}@linux-arm" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { system = "aarch64-linux"; config.allowUnfree = true; };
          extraSpecialArgs = (mkPlatformConfig "aarch64-linux").specialArgs;
          modules = linuxModules;
        };
        
        # macOS home-manager only (fallback)
        "${username}@darwin" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { system = "aarch64-darwin"; config.allowUnfree = true; };
          extraSpecialArgs = (mkPlatformConfig "aarch64-darwin").specialArgs;
          modules = commonModules;
        };
      };

      # Android configurations (nix-on-droid)
      nixOnDroidConfigurations = {
        "android" = nix-on-droid.lib.nixOnDroidConfiguration {
          pkgs = import nixpkgs { system = "aarch64-linux"; config.allowUnfree = true; };
          extraSpecialArgs = (mkPlatformConfig "aarch64-linux").specialArgs;
          modules = androidModules;
        };
      };

      # Development shells for each platform
      devShells = flake-utils.lib.eachDefaultSystemMap (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          platformConfig = mkPlatformConfig system;
        in {
          # Default development shell
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              git
              gh
              neovim
              tmux
              starship
              just  # Task runner
            ];
            shellHook = ''
              echo "🚀 Multi-platform dotfiles development environment"
              echo "Platform: ${system}"
              echo "Available tools: git, gh, neovim, tmux, starship, just"
              echo ""
              echo "Common commands:"
              echo "  just rebuild    - Rebuild current platform configuration"
              echo "  just switch     - Switch to new configuration"
              echo "  just test       - Test configuration"
              echo "  just --list     - Show all available tasks"
            '';
          };

          # Platform testing shell
          test = pkgs.mkShell {
            buildInputs = with pkgs; [
              nixpkgs-fmt
              statix
              deadnix
              alejandra
            ];
            shellHook = ''
              echo "🧪 Testing environment for multi-platform dotfiles"
              echo "Available tools: nixpkgs-fmt, statix, deadnix, alejandra"
            '';
          };
        }
      );

      # Formatting for nix files
      formatter = flake-utils.lib.eachDefaultSystemMap (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt
      );
      

      
      # Documentation and examples
      apps = flake-utils.lib.eachDefaultSystemMap (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          # Platform detection utility
          detect-platform = {
            type = "app";
            program = "${pkgs.writeShellScript "detect-platform" ''
              #!/bin/bash
              echo "System: $(uname -s)"
              echo "Architecture: $(uname -m)"
              echo "Platform: $(nix eval --raw .#platformInfo.platform)"
              echo "Capabilities: $(nix eval --json .#platformInfo.capabilities | ${pkgs.jq}/bin/jq)"
            ''}";
          };
          
          # Comprehensive setup utility (replaces install.sh/setup.sh)
          setup = {
            type = "app";
            program = "${pkgs.writeShellScript "setup" ''
              #!/bin/bash
              set -euo pipefail
              
              # Colors
              RED='\033[0;31m'
              GREEN='\033[0;32m'
              YELLOW='\033[1;33m'
              BLUE='\033[0;34m'
              NC='\033[0m'
              
              log_info() { echo -e "''${BLUE}[INFO]''${NC} $1"; }
              log_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
              log_warning() { echo -e "''${YELLOW}[WARNING]''${NC} $1"; }
              log_error() { echo -e "''${RED}[ERROR]''${NC} $1"; }
              
              echo "🚀 Dotfiles System Setup - Phase 4 Complete"
              echo "========================================="
              
              # Detect platform
              case "$(uname -s)" in
                Darwin)
                  PLATFORM="macOS"
                  INSTALL_CMD="nix run nix-darwin -- switch --flake .#default"
                  ;;
                Linux)
                  if [[ -f /etc/nixos/configuration.nix ]]; then
                    PLATFORM="NixOS"
                    INSTALL_CMD="sudo nixos-rebuild switch --flake .#linux-desktop"
                  elif [[ -n "''${WSL_DISTRO_NAME:-}" ]]; then
                    PLATFORM="WSL"
                    INSTALL_CMD="home-manager switch --flake .#${username}@wsl"
                  elif [[ -d /data/data/com.termux ]]; then
                    PLATFORM="Android/Termux"
                    INSTALL_CMD="nix-on-droid switch --flake .#android"
                  else
                    PLATFORM="Generic Linux"
                    INSTALL_CMD="home-manager switch --flake .#${username}@linux"
                  fi
                  ;;
                *)
                  log_error "Unsupported platform: $(uname -s)"
                  exit 1
                  ;;
              esac
              
              log_info "Detected Platform: $PLATFORM"
              echo ""
              
              # Check prerequisites
              log_info "Checking prerequisites..."
              
              if ! command -v nix &> /dev/null; then
                log_error "Nix is not installed. Please install Nix first:"
                echo "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
                exit 1
              fi
              
              log_success "Nix is available"
              
              # Execute installation
              log_info "Executing: $INSTALL_CMD"
              echo ""
              
              if eval "$INSTALL_CMD"; then
                log_success "✅ System setup completed successfully!"
                echo ""
                log_info "🎯 Phase 4 Features Available:"
                echo "  • AI Development Environment (dev-health, ai-tools-health)"
                echo "  • Enterprise Automation (auto-health, deploy-manager)"
                echo "  • Multi-platform Support (4 platforms)"
                echo "  • Advanced Security (SOPS-nix, Git-crypt)"
                echo ""
                log_info "📚 Next steps:"
                echo "  • Review: README.md for system overview"
                echo "  • Setup: docs/SETUP_GUIDE.md for detailed configuration"
                echo "  • Develop: docs/DEVELOPMENT_ENVIRONMENT_GUIDE.md"
                echo "  • Automate: docs/AUTOMATION_GUIDE.md"
              else
                log_error "❌ Setup failed. Check error messages above."
                exit 1
              fi
            ''}";
          };
          
          # Quick install wrapper
          install = {
            type = "app";
            program = "${pkgs.writeShellScript "install" ''
              #!/bin/bash
              echo "🔄 Redirecting to setup..."
              exec nix run .#setup
            ''}";
          };
        }
      );
    };
}