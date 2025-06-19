# LSP Auto-Configuration System
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.lsp;
in
{
  config = mkIf (cfg.enable && cfg.autoDetection) {
    # Project type detection and auto-configuration
    home-manager.users.yuki.home.file.".config/lsp/project-types.json" = {
      text = builtins.toJSON {
        project_types = {
          nodejs = {
            detection_files = [ "package.json" "yarn.lock" "pnpm-lock.yaml" "node_modules" ];
            required_servers = [ "typescript" "html" "css" "json" ];
            optional_servers = [ "eslint" "prettier" ];
            settings = {
              typescript = {
                preferences = {
                  includePackageJsonAutoImports = "on";
                };
              };
            };
          };
          
          rust = {
            detection_files = [ "Cargo.toml" "Cargo.lock" "src/main.rs" "src/lib.rs" ];
            required_servers = [ "rust" ];
            settings = {
              rust-analyzer = {
                cargo = {
                  allFeatures = true;
                };
                checkOnSave = {
                  command = "clippy";
                };
              };
            };
          };
          
          python = {
            detection_files = [ "requirements.txt" "pyproject.toml" "setup.py" "poetry.lock" "__pycache__" ];
            required_servers = [ "python" ];
            optional_servers = [ "mypy" "black" "isort" ];
            settings = {
              python = {
                analysis = {
                  typeCheckingMode = "basic";
                  autoImportCompletions = true;
                };
              };
            };
          };
          
          go = {
            detection_files = [ "go.mod" "go.sum" "main.go" ];
            required_servers = [ "go" ];
            settings = {
              gopls = {
                gofumpt = true;
                analyses = {
                  unusedparams = true;
                  shadow = true;
                };
              };
            };
          };
          
          java = {
            detection_files = [ "pom.xml" "build.gradle" "gradlew" "src/main/java" ];
            required_servers = [ "java" ];
            settings = {
              java = {
                configuration = {
                  runtimes = [];
                };
              };
            };
          };
          
          php = {
            detection_files = [ "composer.json" "composer.lock" "index.php" ];
            required_servers = [ "php" ];
            settings = {
              intelephense = {
                files = {
                  maxSize = 1000000;
                };
              };
            };
          };
          
          ruby = {
            detection_files = [ "Gemfile" "Gemfile.lock" "Rakefile" ];
            required_servers = [ "ruby" ];
            settings = {
              solargraph = {
                diagnostics = true;
                completion = true;
              };
            };
          };
          
          docker = {
            detection_files = [ "Dockerfile" "docker-compose.yml" "docker-compose.yaml" ".dockerignore" ];
            required_servers = [ "dockerfile" ];
          };
          
          terraform = {
            detection_files = [ "*.tf" "*.tfvars" "terraform.tfstate" ];
            required_servers = [ "terraform" ];
          };
          
          nix = {
            detection_files = [ "flake.nix" "shell.nix" "default.nix" ];
            required_servers = [ "nix" ];
            settings = {
              nil = {
                formatting = {
                  command = [ "nixpkgs-fmt" ];
                };
              };
            };
          };
        };
      };
    };

    # Auto-configuration service script
    home-manager.users.yuki.home.file."bin/lsp-auto-config" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # LSP Auto-Configuration Service
        set -euo pipefail
        
        PROJECT_DIR="''${1:-.}"
        CONFIG_FILE="''${2:-$PROJECT_DIR/.vscode/settings.json}"
        
        echo "🔧 LSP Auto-Configuration Service"
        echo "================================="
        
        # Load project type definitions
        PROJECT_TYPES_FILE="$HOME/.config/lsp/project-types.json"
        if [[ ! -f "$PROJECT_TYPES_FILE" ]]; then
          echo "❌ Project types configuration not found"
          exit 1
        fi
        
        # Detect project type
        DETECTED_TYPES=()
        
        cd "$PROJECT_DIR"
        
        if command -v jq >/dev/null 2>&1; then
          # Use jq for project type detection
          while IFS= read -r project_type; do
            while IFS= read -r detection_file; do
              if [[ -f "$detection_file" ]] || [[ -d "$detection_file" ]] || ls $detection_file >/dev/null 2>&1; then
                DETECTED_TYPES+=("$project_type")
                echo "✅ Detected $project_type project (found: $detection_file)"
                break
              fi
            done < <(jq -r ".project_types.\"$project_type\".detection_files[]" "$PROJECT_TYPES_FILE" 2>/dev/null || true)
          done < <(jq -r '.project_types | keys[]' "$PROJECT_TYPES_FILE")
        fi
        
        if [[ ''${#DETECTED_TYPES[@]} -eq 0 ]]; then
          echo "⚠️ No specific project type detected, using generic configuration"
          DETECTED_TYPES=("generic")
        fi
        
        # Generate configuration based on detected types
        REQUIRED_SERVERS=()
        OPTIONAL_SERVERS=()
        
        for project_type in "''${DETECTED_TYPES[@]}"; do
          if [[ "$project_type" != "generic" ]]; then
            # Extract required servers
            while IFS= read -r server; do
              if [[ ! " ''${REQUIRED_SERVERS[@]} " =~ " $server " ]]; then
                REQUIRED_SERVERS+=("$server")
              fi
            done < <(jq -r ".project_types.\"$project_type\".required_servers[]?" "$PROJECT_TYPES_FILE" 2>/dev/null || true)
            
            # Extract optional servers
            while IFS= read -r server; do
              if [[ ! " ''${OPTIONAL_SERVERS[@]} " =~ " $server " ]]; then
                OPTIONAL_SERVERS+=("$server")
              fi
            done < <(jq -r ".project_types.\"$project_type\".optional_servers[]?" "$PROJECT_TYPES_FILE" 2>/dev/null || true)
          fi
        done
        
        # Add common servers for all projects
        COMMON_SERVERS=("yaml" "markdown" "bash")
        for server in "''${COMMON_SERVERS[@]}"; do
          if [[ ! " ''${REQUIRED_SERVERS[@]} " =~ " $server " ]]; then
            REQUIRED_SERVERS+=("$server")
          fi
        done
        
        echo ""
        echo "📋 Configuration Summary:"
        echo "  Project types: ''${DETECTED_TYPES[*]}"
        echo "  Required servers: ''${REQUIRED_SERVERS[*]}"
        if [[ ''${#OPTIONAL_SERVERS[@]} -gt 0 ]]; then
          echo "  Optional servers: ''${OPTIONAL_SERVERS[*]}"
        fi
        
        # Create project-specific LSP configuration
        mkdir -p "$(dirname "$CONFIG_FILE")"
        
        # Generate VS Code settings if target is VS Code
        if [[ "$CONFIG_FILE" == *".vscode/settings.json" ]]; then
          echo ""
          echo "🎯 Generating VS Code configuration..."
          
          # Create basic VS Code settings
          cat > "$CONFIG_FILE" << EOF
        {
          "// Auto-generated LSP configuration": "$(date)",
          "editor.formatOnSave": true,
          "editor.codeActionsOnSave": {
            "source.organizeImports": true,
            "source.fixAll": true
          },
          "files.watcherExclude": {
            "**/node_modules/**": true,
            "**/target/**": true,
            "**/.git/**": true,
            "**/result/**": true,
            "**/result-*/**": true
          }
        EOF
          
          # Add language-specific settings for detected project types
          for project_type in "''${DETECTED_TYPES[@]}"; do
            if [[ "$project_type" != "generic" ]]; then
              # Add project-specific settings from JSON config
              SETTINGS=$(jq -r ".project_types.\"$project_type\".settings?" "$PROJECT_TYPES_FILE" 2>/dev/null || echo "{}")
              if [[ "$SETTINGS" != "null" && "$SETTINGS" != "{}" ]]; then
                echo "," >> "$CONFIG_FILE"
                echo "  \"// Settings for $project_type\":" >> "$CONFIG_FILE"
                echo "$SETTINGS" | jq -r 'to_entries[] | "  \"\(.key)\": \(.value),"' >> "$CONFIG_FILE"
              fi
            fi
          done
          
          # Close JSON
          echo "}" >> "$CONFIG_FILE"
          
          # Format JSON properly
          if command -v jq >/dev/null 2>&1; then
            jq '.' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
          fi
        fi
        
        # Create .lsp-config.json for other editors
        LSP_CONFIG_FILE="$PROJECT_DIR/.lsp-config.json"
        cat > "$LSP_CONFIG_FILE" << EOF
        {
          "timestamp": "$(date -Iseconds)",
          "detected_types": [$(printf '"%s",' "''${DETECTED_TYPES[@]}" | sed 's/,$//')],,
          "required_servers": [$(printf '"%s",' "''${REQUIRED_SERVERS[@]}" | sed 's/,$//')],,
          "optional_servers": [$(printf '"%s",' "''${OPTIONAL_SERVERS[@]}" | sed 's/,$//')],,
          "project_info": {
            "path": "$(pwd)",
            "auto_configured": true
          }
        }
        EOF
        
        # Format JSON
        if command -v jq >/dev/null 2>&1; then
          jq '.' "$LSP_CONFIG_FILE" > "$LSP_CONFIG_FILE.tmp" && mv "$LSP_CONFIG_FILE.tmp" "$LSP_CONFIG_FILE"
        fi
        
        echo ""
        echo "✅ Auto-configuration complete!"
        echo "📁 Generated: $CONFIG_FILE"
        echo "📁 Generated: $LSP_CONFIG_FILE"
        echo ""
        echo "💡 Next steps:"
        echo "  - Restart your editor to apply changes"
        echo "  - Run 'lsp-health' to verify server status"
        echo "  - Use 'lsp-detect --help' for more options"
      '';
    };

    # Auto-configuration trigger on directory change (zsh integration)
    home-manager.users.yuki.programs.zsh.initContent = mkAfter ''
      # LSP Auto-configuration on directory change
      lsp_auto_config_chpwd() {
        # Only run in project directories (has git, or specific project files)
        if [[ -d .git ]] || [[ -f package.json ]] || [[ -f Cargo.toml ]] || [[ -f go.mod ]] || [[ -f requirements.txt ]] || [[ -f flake.nix ]]; then
          # Check if we need to update LSP config
          if [[ ! -f .lsp-config.json ]] || [[ .lsp-config.json -ot . ]]; then
            echo "🔧 Auto-configuring LSP for this project..."
            lsp-auto-config . >/dev/null 2>&1 || true
          fi
        fi
      }
      
      # Register the function to run on directory change
      if [[ -n "$ZSH_VERSION" ]]; then
        autoload -U add-zsh-hook
        add-zsh-hook chpwd lsp_auto_config_chpwd
      fi
    '';
  };
}