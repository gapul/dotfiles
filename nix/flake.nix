{
  description = "Yuki's macOS Configuration with nix-darwin and home-manager";

  inputs = {
    # Core inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Secret management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Mac App Store management
    mas-nix = {
      url = "github:johnstonsmith/mas-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Additional inputs for specific tools
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, sops-nix, mas-nix, flake-utils }:
    let
      system = "aarch64-darwin"; # Apple Silicon Mac
      pkgs = nixpkgs.legacyPackages.${system};
      
      # Common configuration
      username = "yuki";
      homeDirectory = "/Users/${username}";
      dotfilesDirectory = "${homeDirectory}/dotfiles";
    in
    {
      # System configuration
      darwinConfigurations = {
        "Yukis-Laptop" = nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit username homeDirectory dotfilesDirectory; };
          modules = [
            ./darwin.nix
            sops-nix.darwinModules.sops
            mas-nix.darwinModules.mas
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./home.nix;
                extraSpecialArgs = { inherit username homeDirectory dotfilesDirectory; };
              };
            }
          ];
        };
        
        # Default configuration alias
        default = nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit username homeDirectory dotfilesDirectory; };
          modules = [
            ./darwin.nix
            sops-nix.darwinModules.sops
            mas-nix.darwinModules.mas
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./home.nix;
                extraSpecialArgs = { inherit username homeDirectory dotfilesDirectory; };
              };
            }
          ];
        };
      };

      # Standalone home-manager configuration (for non-nix-darwin systems)
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit username homeDirectory dotfilesDirectory; };
        modules = [ ./home.nix ];
      };

      # Development shells for projects
      devShells.${system} = {
        # Default development shell
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            git
            gh
            neovim
            tmux
            starship
          ];
          shellHook = ''
            echo "🚀 Entering development environment"
            echo "Available tools: git, gh, neovim, tmux, starship"
          '';
        };

        # Python development
        python = pkgs.mkShell {
          buildInputs = with pkgs; [
            python312
            python312Packages.pip
            python312Packages.virtualenv
            python312Packages.black
            python312Packages.flake8
          ];
          shellHook = ''
            echo "🐍 Python development environment"
            python --version
          '';
        };

        # Node.js development
        node = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs_20
            nodePackages.npm
            nodePackages.yarn
            nodePackages.typescript
          ];
          shellHook = ''
            echo "📦 Node.js development environment"
            node --version
            npm --version
          '';
        };

        # Rust development
        rust = pkgs.mkShell {
          buildInputs = with pkgs; [
            rustc
            cargo
            rust-analyzer
            rustfmt
            clippy
          ];
          shellHook = ''
            echo "🦀 Rust development environment"
            rustc --version
          '';
        };
      };

      # Formatting for nix files
      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}