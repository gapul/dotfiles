{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    dotfiles.context.toolConfiguration = {
      enable = mkEnableOption "Intelligent development tool configuration system";

      developerProfiles = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable dynamic developer profile switching";
        };

        profiles = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Human-readable profile name";
              };
              description = mkOption {
                type = types.str;
                description = "Profile description";
              };
              languages = mkOption {
                type = types.listOf types.str;
                description = "Primary programming languages for this profile";
              };
              frameworks = mkOption {
                type = types.listOf types.str;
                description = "Frameworks and tools associated with this profile";
              };
              keyBindings = mkOption {
                type = types.enum [ "vim" "emacs" "vscode" "jetbrains" "custom" ];
                default = "vim";
                description = "Preferred key binding style";
              };
              complexity = mkOption {
                type = types.enum [ "minimal" "standard" "advanced" "expert" ];
                default = "standard";
                description = "Tool complexity level";
              };
            };
          });
          default = {
            full_stack_web = {
              name = "Full Stack Web Developer";
              description = "Modern web development with JavaScript/TypeScript";
              languages = [ "javascript" "typescript" "html" "css" ];
              frameworks = [ "react" "nextjs" "nodejs" "express" ];
              keyBindings = "vscode";
              complexity = "standard";
            };
            systems_engineer = {
              name = "Systems Engineer";
              description = "Low-level programming and systems administration";
              languages = [ "rust" "go" "c" "python" ];
              frameworks = [ "kubernetes" "docker" "terraform" ];
              keyBindings = "vim";
              complexity = "advanced";
            };
            data_scientist = {
              name = "Data Scientist";
              description = "Data analysis and machine learning";
              languages = [ "python" "r" "sql" "julia" ];
              frameworks = [ "jupyter" "pandas" "tensorflow" "pytorch" ];
              keyBindings = "vscode";
              complexity = "standard";
            };
            mobile_developer = {
              name = "Mobile Developer";
              description = "Cross-platform mobile application development";
              languages = [ "swift" "kotlin" "dart" "javascript" ];
              frameworks = [ "react_native" "flutter" "ios" "android" ];
              keyBindings = "vscode";
              complexity = "standard";
            };
            devops_engineer = {
              name = "DevOps Engineer";
              description = "Infrastructure automation and deployment";
              languages = [ "yaml" "bash" "python" "hcl" ];
              frameworks = [ "ansible" "terraform" "jenkins" "gitlab" ];
              keyBindings = "vim";
              complexity = "expert";
            };
          };
          description = "Predefined developer profiles";
        };
      };

      contextualSettings = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable context-aware tool settings";
        };

        projectBasedConfig = mkOption {
          type = types.bool;
          default = true;
          description = "Adjust settings based on current project";
        };

        performanceMode = mkOption {
          type = types.bool;
          default = true;
          description = "Enable performance-aware configuration adjustments";
        };

        collaborationMode = mkOption {
          type = types.bool;
          default = true;
          description = "Enable collaboration-optimized settings";
        };
      };

      editorIntegration = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable intelligent editor configuration";
        };

        supportedEditors = mkOption {
          type = types.listOf types.str;
          default = [ "neovim" "vscode" "zed" "cursor" ];
          description = "Editors to configure automatically";
        };

        lspConfiguration = mkOption {
          type = types.bool;
          default = true;
          description = "Enable automatic LSP server configuration";
        };

        themeSync = mkOption {
          type = types.bool;
          default = true;
          description = "Sync editor themes with system themes";
        };

        formatOnSave = mkOption {
          type = types.bool;
          default = true;
          description = "Enable format on save based on project type";
        };
      };

      terminalOptimization = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable intelligent terminal configuration";
        };

        shellCustomization = mkOption {
          type = types.bool;
          default = true;
          description = "Customize shell based on work context";
        };

        promptAdaptation = mkOption {
          type = types.bool;
          default = true;
          description = "Adapt shell prompt to current project and context";
        };

        aliasOptimization = mkOption {
          type = types.bool;
          default = true;
          description = "Optimize aliases based on frequently used commands";
        };
      };

      toolchainManagement = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable intelligent toolchain management";
        };

        versionAutoSwitch = mkOption {
          type = types.bool;
          default = true;
          description = "Automatically switch tool versions based on project";
        };

        dependencyOptimization = mkOption {
          type = types.bool;
          default = true;
          description = "Optimize dependency management tools";
        };

        buildSystemTuning = mkOption {
          type = types.bool;
          default = true;
          description = "Tune build systems for optimal performance";
        };
      };
    };
  };

  config = mkIf config.dotfiles.context.toolConfiguration.enable {
    environment.systemPackages = with pkgs; [
      # Tool configuration commands
      (writeShellScriptBin "context-configure-tools" ''
                #!/bin/bash
        
                # Intelligent development tool configuration system
        
                set -euo pipefail
        
                ACTION="''${1:-detect}"
                PROFILE="''${2:-auto}"
                FORCE="''${3:-false}"
        
                echo "🔧 Development Tool Configuration"
                echo "================================="
                echo "Action: $ACTION"
                echo "Profile: $PROFILE" 
                echo "⏰ Configuration time: $(date)"
                echo ""
        
                # Configuration directory
                CONFIG_DIR="$HOME/.local/share/dotfiles-context/tools"
                mkdir -p "$CONFIG_DIR"
        
                # Detect current development context
                detect_development_context() {
                  echo "🔍 Detecting development context..."
          
                  PROJECT_TYPE="unknown"
                  PROJECT_LANGUAGES=()
                  PROJECT_FRAMEWORKS=()
          
                  # Check for common project files
                  if [[ -f "package.json" ]]; then
                    PROJECT_TYPE="nodejs"
                    PROJECT_LANGUAGES+=("javascript")
            
                    # Check for specific frameworks
                    if grep -q "react" package.json 2>/dev/null; then
                      PROJECT_FRAMEWORKS+=("react")
                    fi
                    if grep -q "next" package.json 2>/dev/null; then
                      PROJECT_FRAMEWORKS+=("nextjs")
                    fi
                    if grep -q "vue" package.json 2>/dev/null; then
                      PROJECT_FRAMEWORKS+=("vue")
                    fi
                    if grep -q "typescript" package.json 2>/dev/null; then
                      PROJECT_LANGUAGES+=("typescript")
                    fi
            
                  elif [[ -f "Cargo.toml" ]]; then
                    PROJECT_TYPE="rust"
                    PROJECT_LANGUAGES+=("rust")
            
                  elif [[ -f "go.mod" ]]; then
                    PROJECT_TYPE="go"
                    PROJECT_LANGUAGES+=("go")
            
                  elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "Pipfile" ]]; then
                    PROJECT_TYPE="python"
                    PROJECT_LANGUAGES+=("python")
            
                    # Check for specific frameworks
                    if [[ -f "manage.py" ]]; then
                      PROJECT_FRAMEWORKS+=("django")
                    fi
                    if grep -q "flask" requirements.txt 2>/dev/null; then
                      PROJECT_FRAMEWORKS+=("flask")
                    fi
                    if grep -q "fastapi" requirements.txt 2>/dev/null; then
                      PROJECT_FRAMEWORKS+=("fastapi")
                    fi
            
                  elif [[ -f "Gemfile" ]]; then
                    PROJECT_TYPE="ruby"
                    PROJECT_LANGUAGES+=("ruby")
                    if grep -q "rails" Gemfile 2>/dev/null; then
                      PROJECT_FRAMEWORKS+=("rails")
                    fi
            
                  elif [[ -f "composer.json" ]]; then
                    PROJECT_TYPE="php"
                    PROJECT_LANGUAGES+=("php")
                    if grep -q "laravel" composer.json 2>/dev/null; then
                      PROJECT_FRAMEWORKS+=("laravel")
                    fi
            
                  elif [[ -f "pom.xml" ]] || [[ -f "build.gradle" ]]; then
                    PROJECT_TYPE="java"
                    PROJECT_LANGUAGES+=("java")
                    if grep -q "spring" pom.xml 2>/dev/null; then
                      PROJECT_FRAMEWORKS+=("spring")
                    fi
            
                  elif [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]]; then
                    PROJECT_TYPE="docker"
                    PROJECT_FRAMEWORKS+=("docker")
            
                  elif [[ -f "terraform.tf" ]] || [[ -f "main.tf" ]]; then
                    PROJECT_TYPE="terraform"
                    PROJECT_LANGUAGES+=("hcl")
                    PROJECT_FRAMEWORKS+=("terraform")
            
                  elif [[ -f "kubernetes.yaml" ]] || [[ -f "k8s" ]]; then
                    PROJECT_TYPE="kubernetes"
                    PROJECT_FRAMEWORKS+=("kubernetes")
                  fi
          
                  # Check for additional context files
                  if [[ -f ".nvmrc" ]]; then
                    NODE_VERSION=$(cat .nvmrc)
                    echo "  📦 Node.js version specified: $NODE_VERSION"
                  fi
          
                  if [[ -f ".python-version" ]]; then
                    PYTHON_VERSION=$(cat .python-version)
                    echo "  🐍 Python version specified: $PYTHON_VERSION"
                  fi
          
                  if [[ -f ".ruby-version" ]]; then
                    RUBY_VERSION=$(cat .ruby-version)
                    echo "  💎 Ruby version specified: $RUBY_VERSION"
                  fi
          
                  echo "  🎯 Project type: $PROJECT_TYPE"
                  echo "  💻 Languages: ''${PROJECT_LANGUAGES[*]:-none}"
                  echo "  🚀 Frameworks: ''${PROJECT_FRAMEWORKS[*]:-none}"
                  echo ""
                }
        
                # Determine optimal developer profile
                ${lib.optionalString config.dotfiles.context.toolConfiguration.developerProfiles.enable ''
                  determine_optimal_profile() {
                    echo "👤 Determining optimal developer profile..."
            
                    OPTIMAL_PROFILE="full_stack_web"  # Default
            
                    # Profile selection based on detected context
                    case "$PROJECT_TYPE" in
                      "rust"|"go"|"c")
                        OPTIMAL_PROFILE="systems_engineer"
                        ;;
                      "python")
                        if printf '%s\n' "''${PROJECT_FRAMEWORKS[@]}" | grep -q "jupyter\|pandas\|tensorflow"; then
                          OPTIMAL_PROFILE="data_scientist"
                        else
                          OPTIMAL_PROFILE="full_stack_web"
                        fi
                        ;;
                      "swift"|"kotlin")
                        OPTIMAL_PROFILE="mobile_developer"
                        ;;
                      "terraform"|"kubernetes"|"docker")
                        OPTIMAL_PROFILE="devops_engineer"
                        ;;
                      "nodejs"|"javascript"|"typescript")
                        OPTIMAL_PROFILE="full_stack_web"
                        ;;
                      *)
                        OPTIMAL_PROFILE="full_stack_web"
                        ;;
                    esac
            
                    echo "  🎯 Recommended profile: $OPTIMAL_PROFILE"
            
                    # Set profile-specific configuration variables
                    case "$OPTIMAL_PROFILE" in
                      "senior_developer")
                        OPTIMAL_PROFILE_KEYBINDINGS="vim"
                        OPTIMAL_PROFILE_COMPLEXITY="advanced"
                        ;;
                      "full_stack_web")
                        OPTIMAL_PROFILE_KEYBINDINGS="vscode"
                        OPTIMAL_PROFILE_COMPLEXITY="standard"
                        ;;
                      "mobile_developer")
                        OPTIMAL_PROFILE_KEYBINDINGS="xcode"
                        OPTIMAL_PROFILE_COMPLEXITY="standard"
                        ;;
                      "devops_engineer")
                        OPTIMAL_PROFILE_KEYBINDINGS="vim"
                        OPTIMAL_PROFILE_COMPLEXITY="advanced"
                        ;;
                      "data_scientist")
                        OPTIMAL_PROFILE_KEYBINDINGS="jupyter"
                        OPTIMAL_PROFILE_COMPLEXITY="standard"
                        ;;
                      *)
                        OPTIMAL_PROFILE_KEYBINDINGS="vim"
                        OPTIMAL_PROFILE_COMPLEXITY="standard"
                        ;;
                    esac
            
                    echo ""
                  }
                ''}
        
                # Configure editor settings
                ${lib.optionalString config.dotfiles.context.toolConfiguration.editorIntegration.enable ''
                  configure_editor_settings() {
                    local profile="$1"
                    echo "📝 Configuring editor settings for profile: $profile"
            
                    # Neovim configuration
                    if command -v nvim >/dev/null 2>&1; then
                      echo "  🚀 Configuring Neovim..."
              
                      NVIM_CONFIG_DIR="$HOME/.config/nvim"
                      mkdir -p "$NVIM_CONFIG_DIR/lua/context"
              
                      # Create context-aware configuration
                      cat > "$NVIM_CONFIG_DIR/lua/context/profile.lua" << EOF
        -- Auto-generated context-aware Neovim configuration
        -- Profile: $profile
        -- Generated: $(date)

        local M = {}

        M.profile = "$profile"
        M.project_type = "$PROJECT_TYPE"
        M.languages = {$(printf '"%s", ' "''${PROJECT_LANGUAGES[@]}")}
        M.frameworks = {$(printf '"%s", ' "''${PROJECT_FRAMEWORKS[@]}")}

        -- Profile-specific settings
        M.settings = {
          -- LSP settings based on detected languages
          lsp_servers = {},
  
          -- Theme preferences
          theme = "auto",
  
          -- Key bindings
          keybindings = "''${OPTIMAL_PROFILE_KEYBINDINGS:-vim}",
  
          -- Complexity level  
          complexity = "''${OPTIMAL_PROFILE_COMPLEXITY:-standard}"
        }

        -- Language-specific LSP servers
        $(for lang in "''${PROJECT_LANGUAGES[@]}"; do
          case "$lang" in
            "typescript"|"javascript")
              echo 'table.insert(M.settings.lsp_servers, "ts_ls")'
              echo 'table.insert(M.settings.lsp_servers, "eslint")'
              ;;
            "python")
              echo 'table.insert(M.settings.lsp_servers, "pyright")'
              echo 'table.insert(M.settings.lsp_servers, "ruff_lsp")'
              ;;
            "rust")
              echo 'table.insert(M.settings.lsp_servers, "rust_analyzer")'
              ;;
            "go")
              echo 'table.insert(M.settings.lsp_servers, "gopls")'
              ;;
          esac
        done)

        return M
        EOF
              
                      echo "    ✅ Neovim context configuration updated"
                    fi
            
                    # VS Code configuration
                    if command -v code >/dev/null 2>&1; then
                      echo "  💙 Configuring VS Code..."
              
                      VSCODE_CONFIG_DIR="$HOME/.config/Code/User"
                      mkdir -p "$VSCODE_CONFIG_DIR"
              
                      # Create context-aware settings
                      cat > "$VSCODE_CONFIG_DIR/context-settings.json" << EOF
        {
          "// Context": "Auto-generated for profile: $profile",
          "// Generated": "$(date)",
          "// Project Type": "$PROJECT_TYPE",
  
          "editor.formatOnSave": ${lib.boolToString config.dotfiles.context.toolConfiguration.editorIntegration.formatOnSave},
          "editor.codeActionsOnSave": {
            "source.fixAll": true,
            "source.organizeImports": true
          },
  
        $(if [[ " ''${PROJECT_LANGUAGES[*]} " =~ " typescript " ]] || [[ " ''${PROJECT_LANGUAGES[*]} " =~ " javascript " ]]; then
          echo '  "typescript.preferences.quoteStyle": "single",'
          echo '  "javascript.preferences.quoteStyle": "single",'
        fi)

        $(if [[ " ''${PROJECT_LANGUAGES[*]} " =~ " python " ]]; then
          echo '  "python.defaultInterpreterPath": "./venv/bin/python",'
          echo '  "python.formatting.provider": "black",'
        fi)

        $(if [[ " ''${PROJECT_LANGUAGES[*]} " =~ " rust " ]]; then
          echo '  "rust-analyzer.checkOnSave.command": "clippy",'
          echo '  "rust-analyzer.cargo.buildScripts.enable": true,'
        fi)

          "workbench.colorTheme": "auto"
        }
        EOF
              
                      echo "    ✅ VS Code context configuration updated"
                    fi
            
                    echo ""
                  }
                ''}
        
                # Configure terminal settings
                ${lib.optionalString config.dotfiles.context.toolConfiguration.terminalOptimization.enable ''
                  configure_terminal_settings() {
                    local profile="$1"
                    echo "🖥️  Configuring terminal settings for profile: $profile"
            
                    # Shell aliases based on project type
                    ALIASES_FILE="$HOME/.local/share/dotfiles-context/aliases-$profile.sh"
                    cat > "$ALIASES_FILE" << EOF
        # Auto-generated aliases for profile: $profile
        # Generated: $(date)

        # Project-specific aliases
        $(case "$PROJECT_TYPE" in
          "nodejs")
            echo 'alias nr="npm run"'
            echo 'alias ni="npm install"'
            echo 'alias nid="npm install --save-dev"'
            echo 'alias nig="npm install -g"'
            echo 'alias nt="npm test"'
            echo 'alias nb="npm run build"'
            echo 'alias nd="npm run dev"'
            ;;
          "python")
            echo 'alias py="python"'
            echo 'alias pip="python -m pip"'
            echo 'alias venv="python -m venv"'
            echo 'alias activate="source venv/bin/activate"'
            echo 'alias req="pip install -r requirements.txt"'
            echo 'alias freeze="pip freeze > requirements.txt"'
            ;;
          "rust")
            echo 'alias cb="cargo build"'
            echo 'alias cr="cargo run"'
            echo 'alias ct="cargo test"'
            echo 'alias cc="cargo check"'
            echo 'alias cf="cargo fmt"'
            echo 'alias ccl="cargo clippy"'
            ;;
          "go")
            echo 'alias gb="go build"'
            echo 'alias gr="go run"'
            echo 'alias gt="go test"'
            echo 'alias gm="go mod"'
            echo 'alias gi="go install"'
            ;;
        esac)

        # Framework-specific aliases
        $(for framework in "''${PROJECT_FRAMEWORKS[@]}"; do
          case "$framework" in
            "docker")
              echo 'alias dc="docker-compose"'
              echo 'alias dcu="docker-compose up"'
              echo 'alias dcd="docker-compose down"'
              echo 'alias dcl="docker-compose logs"'
              ;;
            "kubernetes")
              echo 'alias k="kubectl"'
              echo 'alias kg="kubectl get"'
              echo 'alias kd="kubectl describe"'
              echo 'alias ka="kubectl apply"'
              ;;
            "terraform")
              echo 'alias tf="terraform"'
              echo 'alias tfi="terraform init"'
              echo 'alias tfp="terraform plan"'
              echo 'alias tfa="terraform apply"'
              ;;
          esac
        done)

        # Profile-specific optimizations
        $(case "$profile" in
          "systems_engineer")
            echo 'alias ll="ls -la"'
            echo 'alias grep="grep --color=auto"'
            echo 'alias ps="ps aux"'
            echo 'alias df="df -h"'
            echo 'alias free="free -h"'
            ;;
          "devops_engineer")
            echo 'alias watch="watch -n 1"'
            echo 'alias ports="netstat -tuln"'
            echo 'alias logs="journalctl -f"'
            ;;
        esac)

        # Load these aliases in current session
        echo "🔧 Context aliases loaded for $profile profile"
        EOF
            
                    # Source the aliases file
                    source "$ALIASES_FILE" 2>/dev/null || true
            
                    echo "    ✅ Terminal aliases configured"
                    echo "    📁 Aliases file: $ALIASES_FILE"
                    echo ""
                  }
                ''}
        
                # Configure development toolchain
                ${lib.optionalString config.dotfiles.context.toolConfiguration.toolchainManagement.enable ''
                  configure_toolchain() {
                    local profile="$1"
                    echo "⚙️  Configuring development toolchain for profile: $profile"
            
                    # Version management
                    echo "  📦 Managing tool versions..."
            
                    # Node.js version management
                    if [[ " ''${PROJECT_LANGUAGES[*]} " =~ " javascript " ]] || [[ " ''${PROJECT_LANGUAGES[*]} " =~ " typescript " ]]; then
                      if [[ -f ".nvmrc" ]] && command -v nvm >/dev/null 2>&1; then
                        echo "    📦 Setting Node.js version from .nvmrc"
                        nvm use 2>/dev/null || echo "    ⚠️  Could not switch Node.js version"
                      fi
                    fi
            
                    # Python version management
                    if [[ " ''${PROJECT_LANGUAGES[*]} " =~ " python " ]]; then
                      if [[ -f ".python-version" ]] && command -v pyenv >/dev/null 2>&1; then
                        echo "    🐍 Setting Python version from .python-version"
                        pyenv local "$(cat .python-version)" 2>/dev/null || echo "    ⚠️  Could not switch Python version"
                      fi
                    fi
            
                    # Ruby version management
                    if [[ " ''${PROJECT_LANGUAGES[*]} " =~ " ruby " ]]; then
                      if [[ -f ".ruby-version" ]] && command -v rbenv >/dev/null 2>&1; then
                        echo "    💎 Setting Ruby version from .ruby-version"
                        rbenv local "$(cat .ruby-version)" 2>/dev/null || echo "    ⚠️  Could not switch Ruby version"
                      fi
                    fi
            
                    # Build system optimization
                    echo "  🚀 Optimizing build systems..."
            
                    # Configure parallel builds based on CPU cores
                    CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "4")
                    PARALLEL_JOBS=$((CPU_CORES > 8 ? 8 : CPU_CORES))
            
                    # Project-specific build optimizations
                    case "$PROJECT_TYPE" in
                      "rust")
                        echo "    🦀 Optimizing Cargo build settings"
                        mkdir -p "$HOME/.cargo"
                        cat > "$HOME/.cargo/config.toml" << EOF
        [build]
        jobs = $PARALLEL_JOBS

        [target.x86_64-apple-darwin]
        rustflags = ["-C", "link-arg=-undefined", "-C", "link-arg=dynamic_lookup"]

        [target.aarch64-apple-darwin] 
        rustflags = ["-C", "link-arg=-undefined", "-C", "link-arg=dynamic_lookup"]
        EOF
                        ;;
                      "nodejs")
                        echo "    📦 Optimizing npm/yarn settings"
                        if command -v npm >/dev/null 2>&1; then
                          npm config set jobs $PARALLEL_JOBS
                        fi
                        ;;
                      "go")
                        echo "    🐹 Optimizing Go build settings"
                        export GOMAXPROCS=$CPU_CORES
                        ;;
                    esac
            
                    echo "    ✅ Toolchain optimization completed"
                    echo ""
                  }
                ''}
        
                # Save configuration state
                save_configuration_state() {
                  local profile="$1"
          
                  TIMESTAMP=$(date +%s)
                  STATE_FILE="$CONFIG_DIR/config-state-$TIMESTAMP.json"
          
                  cat > "$STATE_FILE" << EOF
        {
          "timestamp": $TIMESTAMP,
          "configuration_time": "$(date)",
          "profile": "$profile",
          "project_context": {
            "type": "$PROJECT_TYPE",
            "languages": [$(printf '"%s",' "''${PROJECT_LANGUAGES[@]}" | sed 's/,$//')],
            "frameworks": [$(printf '"%s",' "''${PROJECT_FRAMEWORKS[@]}" | sed 's/,$//')],
            "directory": "$(pwd)"
          },
          "system_context": {
            "cpu_cores": $CPU_CORES,
            "parallel_jobs": $PARALLEL_JOBS,
            "platform": "$(uname)"
          },
          "configured_tools": {
            "editor": true,
            "terminal": true,
            "toolchain": true
          }
        }
        EOF
          
                  echo "💾 Configuration state saved to: $STATE_FILE"
                }
        
                case "$ACTION" in
                  "detect"|"auto")
                    detect_development_context
                    determine_optimal_profile
            
                    if [[ "$PROFILE" == "auto" ]]; then
                      PROFILE="$OPTIMAL_PROFILE"
                    fi
            
                    echo "🔧 Configuring tools for profile: $PROFILE"
                    echo ""
            
                    configure_editor_settings "$PROFILE"
                    configure_terminal_settings "$PROFILE"
                    configure_toolchain "$PROFILE"
            
                    save_configuration_state "$PROFILE"
            
                    echo "✨ Tool configuration completed successfully!"
                    echo "📋 Profile: $PROFILE"
                    echo "🎯 Context: $PROJECT_TYPE (''${PROJECT_LANGUAGES[*]:-none})"
                    ;;
            
                  "profile")
                    if [[ "$PROFILE" == "auto" ]]; then
                      echo "❌ Please specify a profile name"
                      exit 1
                    fi
            
                    echo "🔧 Applying profile: $PROFILE"
                    configure_editor_settings "$PROFILE"
                    configure_terminal_settings "$PROFILE"
                    configure_toolchain "$PROFILE"
                    save_configuration_state "$PROFILE"
                    echo "✅ Profile applied successfully"
                    ;;
            
                  "status")
                    echo "📊 Current Tool Configuration Status:"
            
                    # Show recent configurations
                    echo ""
                    echo "📚 Recent Configurations:"
                    find "$CONFIG_DIR" -name "config-state-*.json" -type f 2>/dev/null | sort -r | head -5 | while read -r file; do
                      if [[ -f "$file" ]]; then
                        CONFIG_TIME=$(${pkgs.jq}/bin/jq -r '.configuration_time' "$file" 2>/dev/null || echo "unknown")
                        CONFIG_PROFILE=$(${pkgs.jq}/bin/jq -r '.profile' "$file" 2>/dev/null || echo "unknown")
                        PROJECT_TYPE=$(${pkgs.jq}/bin/jq -r '.project_context.type' "$file" 2>/dev/null || echo "unknown")
                        echo "  📅 $CONFIG_TIME: $CONFIG_PROFILE ($PROJECT_TYPE)"
                      fi
                    done
            
                    # Show current context
                    detect_development_context
                    ;;
            
                  "reset")
                    echo "🔄 Resetting tool configuration to defaults..."
            
                    # Remove context-specific configurations
                    rm -f "$HOME/.config/nvim/lua/context/profile.lua" 2>/dev/null || true
                    rm -f "$HOME/.config/Code/User/context-settings.json" 2>/dev/null || true
                    rm -f "$HOME/.local/share/dotfiles-context/aliases-"*.sh 2>/dev/null || true
            
                    echo "✅ Tool configuration reset completed"
                    ;;
            
                  *)
                    echo "Usage: context-configure-tools <action> [profile] [force]"
                    echo ""
                    echo "Actions:"
                    echo "  detect/auto    - Auto-detect context and configure tools"
                    echo "  profile <name> - Apply specific developer profile"
                    echo "  status         - Show current configuration status"
                    echo "  reset          - Reset to default configuration"
                    echo ""
                    echo "Profiles:"
                    echo "  full_stack_web    - Modern web development"
                    echo "  systems_engineer  - Low-level systems programming"
                    echo "  data_scientist    - Data analysis and ML"
                    echo "  mobile_developer  - Mobile app development"
                    echo "  devops_engineer   - Infrastructure and automation"
                    echo ""
                    echo "Force: true/false - Force reconfiguration"
                    ;;
                esac
      '')

      # Profile management utility
      (writeShellScriptBin "context-manage-profiles" ''
                #!/bin/bash
        
                # Developer profile management system
        
                set -euo pipefail
        
                ACTION="''${1:-list}"
                PROFILE_NAME="''${2:-}"
        
                echo "👤 Developer Profile Management"
                echo "=============================="
                echo "Action: $ACTION"
                echo ""
        
                PROFILES_DIR="$HOME/.local/share/dotfiles-context/profiles"
                mkdir -p "$PROFILES_DIR"
        
                case "$ACTION" in
                  "list")
                    echo "📋 Available Developer Profiles:"
                    echo ""
            
                    # Built-in profiles
                    echo "🏗️  Built-in Profiles:"
                    echo "  • full_stack_web    - Modern web development (JS/TS, React, Node.js)"
                    echo "  • systems_engineer  - Systems programming (Rust, Go, C, Python)"
                    echo "  • data_scientist    - Data analysis (Python, R, Jupyter, ML)"
                    echo "  • mobile_developer  - Mobile apps (Swift, Kotlin, React Native)"
                    echo "  • devops_engineer   - Infrastructure (Terraform, K8s, Docker)"
                    echo ""
            
                    # Custom profiles
                    echo "🎨 Custom Profiles:"
                    if [[ "$(ls -A "$PROFILES_DIR" 2>/dev/null | wc -l)" -eq 0 ]]; then
                      echo "  No custom profiles found."
                      echo ""
                      echo "  Create a custom profile with:"
                      echo "  context-manage-profiles create <name>"
                    else
                      for profile_file in "$PROFILES_DIR"/*.json; do
                        if [[ -f "$profile_file" ]]; then
                          PROFILE_NAME=$(basename "$profile_file" .json)
                          DESCRIPTION=$(${pkgs.jq}/bin/jq -r '.description // "No description"' "$profile_file" 2>/dev/null)
                          LANGUAGES=$(${pkgs.jq}/bin/jq -r '.languages | join(", ")' "$profile_file" 2>/dev/null)
                          echo "  • $PROFILE_NAME - $DESCRIPTION"
                          echo "    Languages: $LANGUAGES"
                        fi
                      done
                    fi
                    ;;
            
                  "create")
                    if [[ -z "$PROFILE_NAME" ]]; then
                      echo "Usage: context-manage-profiles create <profile-name>"
                      exit 1
                    fi
            
                    echo "🎨 Creating custom profile: $PROFILE_NAME"
            
                    PROFILE_FILE="$PROFILES_DIR/$PROFILE_NAME.json"
            
                    # Interactive profile creation
                    echo "📝 Profile Configuration:"
                    echo ""
            
                    read -p "Description: " DESCRIPTION
                    read -p "Primary languages (comma-separated): " LANGUAGES_INPUT
                    read -p "Frameworks/tools (comma-separated): " FRAMEWORKS_INPUT
                    read -p "Key binding style [vim/emacs/vscode/jetbrains]: " KEYBINDINGS
                    read -p "Complexity level [minimal/standard/advanced/expert]: " COMPLEXITY
            
                    # Convert comma-separated inputs to JSON arrays
                    LANGUAGES_JSON=$(echo "$LANGUAGES_INPUT" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
                    FRAMEWORKS_JSON=$(echo "$FRAMEWORKS_INPUT" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
            
                    cat > "$PROFILE_FILE" << EOF
        {
          "name": "$PROFILE_NAME",
          "description": "$DESCRIPTION",
          "created": "$(date)",
          "languages": [$LANGUAGES_JSON],
          "frameworks": [$FRAMEWORKS_JSON],
          "keyBindings": "''${KEYBINDINGS:-vim}",
          "complexity": "''${COMPLEXITY:-standard}",
          "custom": true
        }
        EOF
            
                    echo ""
                    echo "✅ Custom profile created: $PROFILE_FILE"
                    echo "🔧 Apply with: context-configure-tools profile $PROFILE_NAME"
                    ;;
            
                  "edit")
                    if [[ -z "$PROFILE_NAME" ]]; then
                      echo "Usage: context-manage-profiles edit <profile-name>"
                      exit 1
                    fi
            
                    PROFILE_FILE="$PROFILES_DIR/$PROFILE_NAME.json"
                    if [[ ! -f "$PROFILE_FILE" ]]; then
                      echo "❌ Profile not found: $PROFILE_NAME"
                      exit 1
                    fi
            
                    echo "📝 Editing profile: $PROFILE_NAME"
            
                    if command -v nvim >/dev/null 2>&1; then
                      nvim "$PROFILE_FILE"
                    elif command -v vim >/dev/null 2>&1; then
                      vim "$PROFILE_FILE"
                    elif command -v nano >/dev/null 2>&1; then
                      nano "$PROFILE_FILE"
                    else
                      echo "📁 Profile file: $PROFILE_FILE"
                      echo "Edit with your preferred editor."
                    fi
                    ;;
            
                  "delete")
                    if [[ -z "$PROFILE_NAME" ]]; then
                      echo "Usage: context-manage-profiles delete <profile-name>"
                      exit 1
                    fi
            
                    PROFILE_FILE="$PROFILES_DIR/$PROFILE_NAME.json"
                    if [[ -f "$PROFILE_FILE" ]]; then
                      rm "$PROFILE_FILE"
                      echo "✅ Profile deleted: $PROFILE_NAME"
                    else
                      echo "❌ Profile not found: $PROFILE_NAME"
                    fi
                    ;;
            
                  "export")
                    if [[ -z "$PROFILE_NAME" ]]; then
                      echo "Usage: context-manage-profiles export <profile-name>"
                      exit 1
                    fi
            
                    PROFILE_FILE="$PROFILES_DIR/$PROFILE_NAME.json"
                    if [[ -f "$PROFILE_FILE" ]]; then
                      echo "📤 Exporting profile: $PROFILE_NAME"
                      cat "$PROFILE_FILE"
                    else
                      echo "❌ Profile not found: $PROFILE_NAME"
                    fi
                    ;;
            
                  *)
                    echo "Usage: context-manage-profiles <action> [profile-name]"
                    echo ""
                    echo "Actions:"
                    echo "  list              - List all available profiles"
                    echo "  create <name>     - Create a new custom profile"
                    echo "  edit <name>       - Edit an existing custom profile"
                    echo "  delete <name>     - Delete a custom profile"
                    echo "  export <name>     - Export profile configuration"
                    ;;
                esac
      '')

      # Tool optimization analyzer
      (writeShellScriptBin "context-analyze-tools" ''
        #!/bin/bash
        
        # Development tool usage analysis and optimization
        
        set -euo pipefail
        
        ANALYSIS_TYPE="''${1:-usage}"
        DAYS="''${2:-7}"
        
        echo "📊 Development Tool Analysis"
        echo "==========================="
        echo "Analysis type: $ANALYSIS_TYPE"
        echo "Period: Last $DAYS days"
        echo ""
        
        CONFIG_DIR="$HOME/.local/share/dotfiles-context/tools"
        
        case "$ANALYSIS_TYPE" in
          "usage")
            echo "🔧 Tool Usage Patterns:"
            
            # Analyze shell history for tool usage
            if [[ -f "$HOME/.zsh_history" ]]; then
              echo "  📈 Most used commands (last $DAYS days):"
              
              # Get recent commands
              CUTOFF_DATE=$(date -d "$DAYS days ago" +%s 2>/dev/null || date -j -v-"$DAYS"d +%s)
              awk -F';' '{ if (substr($1, 3) >= '$CUTOFF_DATE') print $2 }' "$HOME/.zsh_history" 2>/dev/null | head -1000 | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | while read -r count cmd; do
                echo "    $cmd: $count uses"
              done
            fi
            
            echo ""
            echo "  🎯 Development tool usage:"
            
            # Check for common development tools
            TOOLS=("git" "npm" "yarn" "pip" "cargo" "go" "docker" "kubectl" "terraform")
            for tool in "''${TOOLS[@]}"; do
              if command -v "$tool" >/dev/null 2>&1; then
                USAGE_COUNT=$(awk -F';' '{ if (substr($1, 3) >= '$CUTOFF_DATE') print $2 }' "$HOME/.zsh_history" 2>/dev/null | grep -c "^$tool " || echo "0")
                if [[ "$USAGE_COUNT" -gt 0 ]]; then
                  echo "    $tool: $USAGE_COUNT uses"
                fi
              fi
            done
            ;;
            
          "performance")
            echo "⚡ Performance Analysis:"
            
            # Check build times
            echo "  🚀 Build Performance:"
            if [[ -f "package.json" ]]; then
              echo "    📦 npm/yarn build times:"
              # This would analyze build logs in a real implementation
              echo "      (Build time analysis requires integration with build tools)"
            fi
            
            # Check resource usage during development
            echo ""
            echo "  💻 Resource Usage During Development:"
            echo "    🖥️  Average CPU usage: (monitoring required)"
            echo "    💾 Memory consumption: (monitoring required)"
            echo "    💿 Disk I/O patterns: (monitoring required)"
            ;;
            
          "recommendations")
            echo "💡 Optimization Recommendations:"
            
            # Analyze current setup and suggest improvements
            echo "  🔧 Configuration Optimizations:"
            
            # Check if running latest tool versions
            echo "    📦 Tool Version Check:"
            if command -v npm >/dev/null 2>&1; then
              NPM_VERSION=$(npm --version)
              echo "      npm: $NPM_VERSION"
            fi
            
            if command -v node >/dev/null 2>&1; then
              NODE_VERSION=$(node --version)
              echo "      Node.js: $NODE_VERSION"
            fi
            
            # Performance suggestions
            echo ""
            echo "  ⚡ Performance Suggestions:"
            echo "    • Enable parallel builds where possible"
            echo "    • Use package manager caches"
            echo "    • Configure incremental builds"
            echo "    • Use fast SSD for node_modules and build outputs"
            echo "    • Enable language server performance optimizations"
            
            # Workflow suggestions
            echo ""
            echo "  🔄 Workflow Improvements:"
            echo "    • Set up pre-commit hooks for code quality"
            echo "    • Configure automatic formatting on save"
            echo "    • Use task runners for repetitive operations"
            echo "    • Enable hot reload for faster development cycles"
            ;;
            
          *)
            echo "Usage: context-analyze-tools <type> [days]"
            echo ""
            echo "Types:"
            echo "  usage           - Analyze tool usage patterns"
            echo "  performance     - Analyze performance metrics"
            echo "  recommendations - Get optimization suggestions"
            echo ""
            echo "Days: Number of days to analyze (default: 7)"
            ;;
        esac
        
        echo ""
        echo "💡 Tool Analysis Complete"
      '')
    ];
  };
}
