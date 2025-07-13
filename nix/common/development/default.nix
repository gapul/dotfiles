{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./containers
    ./lsp/module.nix
    # ./ai-tools  # Merged into ai-platform module
    ./ai-platform  # Phase 5: Advanced AI integration (includes legacy ai-tools functionality)
    ./project-env
    ./test-integration.nix
    ./web  # Web development environment
    ./cli-tools.nix  # Enhanced CLI tools integration
    ./nix-qol.nix  # Phase 6: Nix Quality of Life tools
  ];

  options.dotfiles.development = {
    enable = mkEnableOption "Advanced development environment";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" "ai-powered" ];
      default = "standard";
      description = "Development environment profile";
    };
  };

  config = mkIf config.dotfiles.development.enable {
    # Enhanced CLI tools integration 
    dotfiles.development.cli-tools.enable = mkDefault true;
    dotfiles.development.cli-tools.profile = mkDefault "standard";
    dotfiles.development.cli-tools.atuin = mkDefault true;
    dotfiles.development.cli-tools.zoxide = mkDefault true;
    dotfiles.development.cli-tools.starship = mkDefault true;
    
    # Individual tool controls
    dotfiles.development.cli-tools.navigation = mkDefault true;
    dotfiles.development.cli-tools.content = mkDefault true;
    dotfiles.development.cli-tools.git = mkDefault true;
    
    # Enable components based on profile
    dotfiles.development.containers.enable = mkDefault (
      elem config.dotfiles.development.profile [ "standard" "full" "ai-powered" ]
    );
    
    dotfiles.development.lsp.enable = mkDefault true;
    
    # AI Tools module (merged into ai-platform)
    # dotfiles.development.ai-tools.enable = mkDefault (
    #   elem config.dotfiles.development.profile [ "full" "ai-powered" ]
    # );
    
    # AI Platform module (Phase 5.1 + Phase 6)
    dotfiles.development.ai-platform.enable = mkDefault (
      elem config.dotfiles.development.profile [ "full" "ai-powered" ]
    );
    
    # Advanced Ollama configuration (Phase 6)
    dotfiles.development.ai-platform.ollama.enable = mkDefault (
      config.dotfiles.development.ai-platform.enable
    );
    dotfiles.development.ai-platform.ollama.models = mkDefault [
      "codellama:7b"
      "llama2:7b" 
      "mistral:7b"
      "phi:2.7b"
    ];
    dotfiles.development.ai-platform.ollama.autoStart = mkDefault true;
    dotfiles.development.ai-platform.ollama.cliIntegration = mkDefault true;
    dotfiles.development.ai-platform.ollama.neovimIntegration = mkDefault true;
    
    # Project-env module
    dotfiles.development.project-env.enable = mkDefault (
      elem config.dotfiles.development.profile [ "standard" "full" "ai-powered" ]
    );
    
    # Web development environment (temporarily disabled)
    web.enable = mkDefault false;
    
    # Web development profile mapping
    web.profile = mkDefault (
      if config.dotfiles.development.profile == "minimal" then "minimal"
      else if config.dotfiles.development.profile == "standard" then "standard"
      else if config.dotfiles.development.profile == "full" then "full"
      else "full"  # ai-powered maps to full
    );
    
    # Enable desktop development for full profiles
    web.features.desktop = mkDefault (
      elem config.dotfiles.development.profile [ "full" "ai-powered" ]
    );

    # Profile-specific configurations
    dotfiles.development.lsp.enabledLanguages = mkDefault (
      if config.dotfiles.development.profile == "minimal" then
        [ "nix" "bash" "markdown" ]
      else if config.dotfiles.development.profile == "standard" then
        [ "typescript" "html" "css" "json" "python" "nix" "yaml" "markdown" "bash" ]
      else
        [ "typescript" "html" "css" "json" "rust" "go" "python" "nix" "yaml" "markdown" "bash" "c_cpp" "lua" "sql" ]
    );

    # Project-env supported types temporarily disabled
    # dotfiles.development.project-env.supportedTypes = mkDefault (
    #   if config.dotfiles.development.profile == "minimal" then
    #     [ "nodejs" "python" ]
    #   else if config.dotfiles.development.profile == "standard" then
    #     [ "nodejs" "python" "rust" "go" "react" "nextjs" "docker" ]
    #   else
    #     [ "nodejs" "python" "rust" "go" "php" "ruby" "java" "react" "nextjs" "vue" "angular" "docker" "terraform" ]
    # );

    # Common development tools for all profiles (modern CLI tools moved to modern-cli module)
    home-manager.users.yuki.home.packages = with pkgs; [
      # Version control (core Git tools only, TUI moved to modern-cli)
      git
      git-lfs
      gitui  # Keep as alternative to lazygit
      
      # Text processing (core tools only, modern alternatives in modern-cli)
      fzf  # Fuzzy finder - still widely used directly
      jq
      yq-go  # YAML processor (Go version, consistent with automation modules)
      
      # Network tools
      curl
      wget
      httpie
      
      # File management (legacy tools for compatibility)
      tree  # Keep for simple tree display
      
      # Process management (legacy htop kept for compatibility)
      htop  # Keep as fallback
      procs  # Modern ps replacement
      
      # Development utilities
      just
      gnumake  # make command
      cmake
      
      # Documentation
      tldr
      man-pages
    ] ++ optionals (config.dotfiles.development.profile != "minimal") [
      # Database tools
      sqlite
      postgresql
      redis
      
      # Cloud tools
      awscli2
      google-cloud-sdk
      terraform
      
      # Container tools
      podman
      buildah
      skopeo
      
      # Monitoring
      lsof
      tcpdump
      # netstat-nat - Linux only, not available on macOS
    ];

    # Enhanced shell configuration for development
    home-manager.users.yuki.programs.zsh = {
      enable = true;
      shellAliases = {
        # Git shortcuts
        gs = "git status";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gl = "git log --oneline";
        gd = "git diff";
        
        # Development shortcuts (modern CLI replacements handled by modern-cli module)  
        ps = "procs";  # Keep procs alias here as it's development-specific
        
        # Nix shortcuts
        nix-build = "nix build";
        nix-shell = "nix develop";
        nix-search = "nix search nixpkgs";
        
        # Docker/Podman shortcuts
        d = "docker";
        dc = "docker-compose";
        p = "podman";
      };
      
      initContent = ''
        # Development environment helpers
        dev() {
          if [[ -f shell.nix ]] || [[ -f flake.nix ]]; then
            nix develop
          elif [[ -f .envrc ]]; then
            direnv allow && direnv reload
          else
            echo "No development environment found"
            echo "Run 'project-init' to set up a new environment"
          fi
        }
        
        # Quick project setup
        mkproject() {
          local name="$1"
          local type="''${2:-nodejs}"
          mkdir -p "$name"
          cd "$name"
          project-init "$name" "$type" .
        }
        
        # Development environment status
        devstatus() {
          echo "🛠️  Development Environment Status"
          echo "================================="
          
          # Check if we're in a project
          if git rev-parse --git-dir > /dev/null 2>&1; then
            echo "📁 Project: $(basename "$(git rev-parse --show-toplevel)")"
          fi
          
          # Check development files
          if [[ -f shell.nix ]]; then
            echo "❄️  Nix shell: Available"
          fi
          
          if [[ -f flake.nix ]]; then
            echo "❄️  Nix flake: Available"
          fi
          
          if [[ -f .envrc ]]; then
            echo "🔄 direnv: Available"
          fi
          
          if [[ -f package.json ]]; then
            echo "📦 Node.js: $(node --version 2>/dev/null || echo "Not available")"
          fi
          
          if [[ -f requirements.txt ]] || [[ -f pyproject.toml ]]; then
            echo "🐍 Python: $(python --version 2>/dev/null || echo "Not available")"
          fi
          
          if [[ -f Cargo.toml ]]; then
            echo "🦀 Rust: $(rustc --version 2>/dev/null || echo "Not available")"
          fi
          
          if [[ -f go.mod ]]; then
            echo "🐹 Go: $(go version 2>/dev/null || echo "Not available")"
          fi
        }
        
        # Clean development environment
        devclean() {
          echo "🧹 Cleaning development environment..."
          
          # Clean Nix store
          if command -v nix &> /dev/null; then
            nix store gc --verbose
          fi
          
          # Clean direnv
          if command -v direnv &> /dev/null; then
            direnv reload
          fi
          
          # Clean Docker
          if command -v docker &> /dev/null; then
            docker system prune -f
          fi
          
          # Clean Node.js
          if [[ -d node_modules ]]; then
            echo "Cleaning node_modules..."
            rm -rf node_modules
            if [[ -f package.json ]]; then
              npm install
            fi
          fi
          
          echo "✅ Development environment cleaned!"
        }
      '';
    };

    # Git configuration enhancements
    home-manager.users.yuki.programs.git = {
      enable = true;
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
        rerere.enabled = true;
        
        # Development-specific settings
        core = {
          editor = "nvim";
          autocrlf = false;
          filemode = true;
        };
        
        # Better diff and merge
        diff = {
          algorithm = "patience";
          compactionHeuristic = true;
        };
        
        merge = {
          tool = "nvimdiff";
          conflictstyle = "diff3";
        };
        
        # Useful aliases
        alias = {
          st = "status";
          co = "checkout";
          br = "branch";
          ci = "commit";
          unstage = "reset HEAD --";
          last = "log -1 HEAD";
          visual = "!gitk";
          
          # Development workflow aliases
          feature = "checkout -b";
          develop = "checkout develop";
          main = "checkout main";
          sync = "!git fetch origin && git rebase origin/main";
          
          # Useful logs
          lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
          ll = "log --pretty=format:'\%C(yellow)\%h\%Cred\%d\\ \%Creset\%s\%Cblue\\ [\%cn]\' --decorate --numstat";
          
          # File operations
          ignore = "!gi() { curl -sL https://www.toptal.com/developers/gitignore/api/$@ ;}; gi";
        };
      };
    };

    # VS Code configuration for development
    home-manager.users.yuki.home.file.".vscode/global-settings.json" = mkIf config.dotfiles.development.lsp.vscodeIntegration {
      text = builtins.toJSON {
        # Editor settings
        "editor.fontSize" = 14;
        "editor.fontFamily" = "'JetBrains Mono', 'Fira Code', monospace";
        "editor.fontLigatures" = true;
        "editor.minimap.enabled" = false;
        "editor.scrollBeyondLastLine" = false;
        "editor.renderWhitespace" = "boundary";
        "editor.rulers" = [ 80 120 ];
        
        # File explorer
        "explorer.confirmDelete" = false;
        "explorer.confirmDragAndDrop" = false;
        "files.autoSave" = "afterDelay";
        "files.autoSaveDelay" = 1000;
        
        # Terminal
        "terminal.integrated.fontSize" = 13;
        "terminal.integrated.shell.osx" = "/bin/zsh";
        
        # Git
        "git.enableSmartCommit" = true;
        "git.confirmSync" = false;
        "git.autofetch" = true;
        
        # Extensions
        "extensions.autoUpdate" = false;
        "extensions.ignoreRecommendations" = false;
        
        # Workbench
        "workbench.startupEditor" = "newUntitledFile";
        "workbench.editor.enablePreview" = false;
        "workbench.colorTheme" = "Default Dark+";
        
        # Search
        "search.exclude" = {
          "**/node_modules" = true;
          "**/bower_components" = true;
          "**/*.code-search" = true;
          "**/result" = true;
          "**/result-*" = true;
        };
      };
    };

    # Development environment health check
    home-manager.users.yuki.home.file."bin/dev-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🏥 Development Environment Health Check"
        echo "======================================"
        
        # Check core tools
        echo "📋 Core Development Tools:"
        
        tools=(
          "git:Git version control"
          "nix:Nix package manager" 
          "nvim:Neovim editor"
          "zsh:Z shell"
          "curl:HTTP client"
          "jq:JSON processor"
          "rg:Fast text search"
          "fd:Fast file finder"
          "fzf:Fuzzy finder"
        )
        
        for tool_desc in "''${tools[@]}"; do
          tool="''${tool_desc%%:*}"
          desc="''${tool_desc##*:}"
          
          if command -v "$tool" &> /dev/null; then
            echo "✅ $tool: $desc"
          else
            echo "❌ $tool: $desc (not found)"
          fi
        done
        
        echo ""
        echo "🧩 Development Components:"
        
        # Check LSP
        ${if config.dotfiles.development.lsp.enable then ''
          echo "✅ LSP: Language Server Protocol enabled"
          $HOME/bin/lsp-health
        '' else ''
          echo "⚪ LSP: Disabled"
        ''}
        
        # Check Containers
        ${if config.dotfiles.development.containers.enable then ''
          echo "✅ Containers: Development containers enabled"
          if command -v docker &> /dev/null; then
            echo "  🐳 Docker: $(docker --version)"
          fi
        '' else ''
          echo "⚪ Containers: Disabled"
        ''}
        
        # Check AI Platform (includes legacy AI Tools functionality)
        ${if config.dotfiles.development.ai-platform.enable then ''
          echo "✅ AI Platform: Enabled"
          if command -v ai-platform-health &> /dev/null; then
            ai-platform-health
          fi
        '' else ''
          echo "⚪ AI Platform: Disabled"
        ''}
        
        # Check AI Platform (Phase 5)
        ${if config.dotfiles.development.ai-platform.enable then ''
          echo "✅ AI Platform: Enabled"
          if command -v ai-platform-health &> /dev/null; then
            ai-platform-health
          fi
        '' else ''
          echo "⚪ AI Platform: Disabled"
        ''}
        
        # Check Performance System (Phase 5)
        ${if config.dotfiles.performance.enable or false then ''
          echo "✅ Performance System: Enabled"
          if command -v performance-health &> /dev/null; then
            performance-health
          fi
        '' else ''
          echo "⚪ Performance System: Disabled"
        ''}
        
        # Check Enterprise Security (Phase 5)
        ${if config.dotfiles.security.enterprise.enable or false then ''
          echo "✅ Enterprise Security: Enabled"
          if command -v security-health &> /dev/null; then
            security-health
          fi
        '' else ''
          echo "⚪ Enterprise Security: Disabled"
        ''}
        
        # Check Universal Platform Integration (Phase 5)
        ${if config.dotfiles.universal.platform.enable or false then ''
          echo "✅ Universal Platform Integration: Enabled"
          if command -v universal-platform-manager &> /dev/null; then
            universal-platform-manager status
          fi
        '' else ''
          echo "⚪ Universal Platform Integration: Disabled"
        ''}
        
        # Check Modern CLI Tools (Phase 5) - temporarily disabled
        ${if false then ''
          echo "✅ Modern CLI Tools: Enabled"
          if command -v modern-cli-health &> /dev/null; then
            modern-cli-health
          else
            echo "  🔧 Core replacements:"
            for tool in eza bat ripgrep fd; do
              if command -v "$tool" &> /dev/null; then
                echo "    ✅ $tool"
              else
                echo "    ❌ $tool"
              fi
            done
            
            echo "  🧭 Navigation & Git:"
            for tool in zoxide lazygit yazi; do
              if command -v "$tool" &> /dev/null; then
                echo "    ✅ $tool"
              else
                echo "    ❌ $tool"
              fi
            done
            
            echo "  📊 Monitoring:"
            for tool in bottom; do
              if command -v "$tool" &> /dev/null; then
                echo "    ✅ $tool"
              else
                echo "    ❌ $tool"  
              fi
            done
          fi
        '' else ''
          echo "⚪ Modern CLI Tools: Disabled"
        ''}
        
        # Check Web Development Environment
        ${if config.web.enable or false then ''
          echo "✅ Web Development Environment: Enabled"
          if command -v web-env-health &> /dev/null; then
            web-env-health
          fi
        '' else ''
          echo "⚪ Web Development Environment: Disabled"
        ''}
        
        # Project Environment temporarily disabled
        echo "⚪ Project Environment: Temporarily disabled"
        
        echo ""
        echo "⚙️  Profile: ${config.dotfiles.development.profile}"
        echo "📊 Status: Development environment ready!"
      '';
    };
  };
}