{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    dotfiles.context.projectDetection = {
      enable = mkEnableOption "Intelligent project detection and analysis system";
      
      languageDetection = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable programming language detection";
        };
        
        supportedLanguages = mkOption {
          type = types.listOf types.str;
          default = [
            "rust" "python" "javascript" "typescript" "go" "java" 
            "c" "cpp" "nix" "bash" "lua" "ruby" "php" "kotlin" "swift"
          ];
          description = "List of supported programming languages for detection";
        };
      };
      
      frameworkDetection = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable framework and library detection";
        };
        
        frameworks = mkOption {
          type = types.attrsOf (types.listOf types.str);
          default = {
            web = ["react" "vue" "angular" "svelte" "nextjs" "nuxt" "express" "fastapi" "django" "rails"];
            mobile = ["react-native" "flutter" "ionic" "cordova"];
            desktop = ["electron" "tauri" "qt" "gtk"];
            backend = ["spring" "laravel" "gin" "fiber" "actix"];
            ai = ["pytorch" "tensorflow" "scikit-learn" "huggingface"];
          };
          description = "Framework detection patterns by category";
        };
      };
      
      projectScale = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable project scale analysis";
        };
        
        thresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            small = 1000;     # < 1K lines
            medium = 10000;   # 1K - 10K lines
            large = 100000;   # 10K - 100K lines
            enterprise = 1000000; # > 100K lines
          };
          description = "Line count thresholds for project scale classification";
        };
      };
      
      developmentPhase = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable development phase detection";
        };
        
        phases = mkOption {
          type = types.listOf types.str;
          default = [
            "planning" "development" "testing" "staging" 
            "production" "maintenance" "deprecated"
          ];
          description = "Supported development phases";
        };
      };
    };
  };

  config = mkIf config.dotfiles.context.projectDetection.enable {
    environment.systemPackages = with pkgs; [
      # Project analysis command
      (writeShellScriptBin "project-detect-context" ''
        #!/bin/bash
        
        # Intelligent project context detection
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        OUTPUT_FORMAT="''${2:-summary}"  # summary, json, detailed
        
        echo "🔍 Project Context Detection"
        echo "============================"
        echo "Analyzing: $PROJECT_DIR"
        echo "⏰ Detection time: $(date)"
        echo ""
        
        if [[ ! -d "$PROJECT_DIR" ]]; then
          echo "❌ Directory not found: $PROJECT_DIR"
          exit 1
        fi
        
        cd "$PROJECT_DIR"
        
        # Initialize detection data
        PROJECT_NAME=$(basename "$PROJECT_DIR")
        LANGUAGES_DETECTED=""
        FRAMEWORKS_DETECTED=""
        PROJECT_SCALE="unknown"
        DEV_PHASE="unknown"
        TOTAL_LINES=0
        
        case "$OUTPUT_FORMAT" in
          "summary"|"detailed"|"json")
            
            # Language detection
            ${optionalString config.dotfiles.context.projectDetection.languageDetection.enable ''
              echo "🔤 Language Analysis:"
              
              # Get language statistics using tokei if available
              if command -v tokei >/dev/null 2>&1; then
                TOKEI_OUTPUT=$(${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .languages then .languages | to_entries[] | "\(.key): \(.value.code) lines (\(.value | (.code/(.code+.comments+.blanks)*100 | floor))%)" else empty end' 2>/dev/null || echo "")
                
                if [[ -n "$TOKEI_OUTPUT" ]]; then
                  echo "$TOKEI_OUTPUT" | while read -r line; do
                    echo "  📊 $line"
                  done
                  
                  # Extract primary language
                  PRIMARY_LANG=$(${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .languages then .languages | to_entries | max_by(.value.code) | .key else "unknown" end' 2>/dev/null || echo "unknown")
                  TOTAL_LINES=$(${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .Total then .Total.code else 0 end' 2>/dev/null || echo "0")
                  
                  echo "  🎯 Primary language: $PRIMARY_LANG"
                  echo "  📏 Total code lines: $TOTAL_LINES"
                  LANGUAGES_DETECTED="$PRIMARY_LANG"
                else
                  echo "  ⚠️  Unable to analyze languages with tokei"
                fi
              else
                # Fallback language detection
                echo "  📁 File-based language detection:"
                
                # Count common file extensions
                RUST_FILES=$(find . -name "*.rs" -type f 2>/dev/null | wc -l | tr -d ' ')
                PYTHON_FILES=$(find . -name "*.py" -type f 2>/dev/null | wc -l | tr -d ' ')
                JS_FILES=$(find . -name "*.js" -type f 2>/dev/null | wc -l | tr -d ' ')
                TS_FILES=$(find . -name "*.ts" -type f 2>/dev/null | wc -l | tr -d ' ')
                GO_FILES=$(find . -name "*.go" -type f 2>/dev/null | wc -l | tr -d ' ')
                NIX_FILES=$(find . -name "*.nix" -type f 2>/dev/null | wc -l | tr -d ' ')
                
                [[ "$RUST_FILES" -gt 0 ]] && echo "    🦀 Rust: $RUST_FILES files" && LANGUAGES_DETECTED="rust"
                [[ "$PYTHON_FILES" -gt 0 ]] && echo "    🐍 Python: $PYTHON_FILES files" && LANGUAGES_DETECTED="python"
                [[ "$JS_FILES" -gt 0 ]] && echo "    📜 JavaScript: $JS_FILES files" && LANGUAGES_DETECTED="javascript"
                [[ "$TS_FILES" -gt 0 ]] && echo "    📘 TypeScript: $TS_FILES files" && LANGUAGES_DETECTED="typescript"
                [[ "$GO_FILES" -gt 0 ]] && echo "    🐹 Go: $GO_FILES files" && LANGUAGES_DETECTED="go"
                [[ "$NIX_FILES" -gt 0 ]] && echo "    ❄️  Nix: $NIX_FILES files" && LANGUAGES_DETECTED="nix"
                
                # Estimate total lines
                TOTAL_LINES=$(find . -name "*.rs" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.nix" -type f 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
                echo "    📊 Estimated total lines: $TOTAL_LINES"
              fi
              echo ""
            ''}
            
            # Framework detection
            ${optionalString config.dotfiles.context.projectDetection.frameworkDetection.enable ''
              echo "🏗️  Framework Analysis:"
              
              # Check for common framework indicators
              FRAMEWORKS_FOUND=""
              
              # Package.json analysis
              if [[ -f "package.json" ]]; then
                echo "  📦 Node.js project detected"
                
                # React detection
                if grep -q "react" package.json 2>/dev/null; then
                  echo "    ⚛️  React framework detected"
                  FRAMEWORKS_FOUND="react"
                fi
                
                # Next.js detection
                if grep -q "next" package.json 2>/dev/null; then
                  echo "    🔺 Next.js framework detected"
                  FRAMEWORKS_FOUND="nextjs"
                fi
                
                # Vue detection
                if grep -q "vue" package.json 2>/dev/null; then
                  echo "    💚 Vue.js framework detected"
                  FRAMEWORKS_FOUND="vue"
                fi
                
                # Express detection
                if grep -q "express" package.json 2>/dev/null; then
                  echo "    🚂 Express.js framework detected"
                  FRAMEWORKS_FOUND="express"
                fi
              fi
              
              # Cargo.toml analysis
              if [[ -f "Cargo.toml" ]]; then
                echo "  🦀 Rust project detected"
                
                # Actix detection
                if grep -q "actix" Cargo.toml 2>/dev/null; then
                  echo "    🕷️  Actix web framework detected"
                  FRAMEWORKS_FOUND="actix"
                fi
                
                # Tauri detection
                if grep -q "tauri" Cargo.toml 2>/dev/null; then
                  echo "    🦋 Tauri desktop framework detected"
                  FRAMEWORKS_FOUND="tauri"
                fi
              fi
              
              # Go modules analysis
              if [[ -f "go.mod" ]]; then
                echo "  🐹 Go project detected"
                
                # Gin detection
                if grep -q "gin-gonic/gin" go.mod 2>/dev/null; then
                  echo "    🍸 Gin framework detected"
                  FRAMEWORKS_FOUND="gin"
                fi
                
                # Fiber detection
                if grep -q "gofiber/fiber" go.mod 2>/dev/null; then
                  echo "    🧵 Fiber framework detected"
                  FRAMEWORKS_FOUND="fiber"
                fi
              fi
              
              # Python requirements analysis
              if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then
                echo "  🐍 Python project detected"
                
                # Django detection
                if grep -q -i "django" requirements.txt pyproject.toml 2>/dev/null; then
                  echo "    🎸 Django framework detected"
                  FRAMEWORKS_FOUND="django"
                fi
                
                # FastAPI detection
                if grep -q -i "fastapi" requirements.txt pyproject.toml 2>/dev/null; then
                  echo "    ⚡ FastAPI framework detected"
                  FRAMEWORKS_FOUND="fastapi"
                fi
              fi
              
              # Nix flake analysis
              if [[ -f "flake.nix" ]]; then
                echo "  ❄️  Nix flake project detected"
                FRAMEWORKS_FOUND="nix-flake"
              fi
              
              FRAMEWORKS_DETECTED="$FRAMEWORKS_FOUND"
              echo ""
            ''}
            
            # Project scale analysis
            ${optionalString config.dotfiles.context.projectDetection.projectScale.enable ''
              echo "📊 Project Scale Analysis:"
              
              # Determine project scale based on lines of code
              if [[ "$TOTAL_LINES" -gt ${toString config.dotfiles.context.projectDetection.projectScale.thresholds.enterprise} ]]; then
                PROJECT_SCALE="enterprise"
                SCALE_EMOJI="🏢"
                SCALE_DESC="Enterprise scale (${toString config.dotfiles.context.projectDetection.projectScale.thresholds.enterprise}+ lines)"
              elif [[ "$TOTAL_LINES" -gt ${toString config.dotfiles.context.projectDetection.projectScale.thresholds.large} ]]; then
                PROJECT_SCALE="large"
                SCALE_EMOJI="🏗️"
                SCALE_DESC="Large scale (${toString config.dotfiles.context.projectDetection.projectScale.thresholds.large}-${toString config.dotfiles.context.projectDetection.projectScale.thresholds.enterprise} lines)"
              elif [[ "$TOTAL_LINES" -gt ${toString config.dotfiles.context.projectDetection.projectScale.thresholds.medium} ]]; then
                PROJECT_SCALE="medium"
                SCALE_EMOJI="🏠"
                SCALE_DESC="Medium scale (${toString config.dotfiles.context.projectDetection.projectScale.thresholds.medium}-${toString config.dotfiles.context.projectDetection.projectScale.thresholds.large} lines)"
              elif [[ "$TOTAL_LINES" -gt ${toString config.dotfiles.context.projectDetection.projectScale.thresholds.small} ]]; then
                PROJECT_SCALE="small"
                SCALE_EMOJI="🏡"
                SCALE_DESC="Small scale (${toString config.dotfiles.context.projectDetection.projectScale.thresholds.small}-${toString config.dotfiles.context.projectDetection.projectScale.thresholds.medium} lines)"
              else
                PROJECT_SCALE="micro"
                SCALE_EMOJI="🧩"
                SCALE_DESC="Micro scale (< ${toString config.dotfiles.context.projectDetection.projectScale.thresholds.small} lines)"
              fi
              
              echo "  $SCALE_EMOJI Scale: $PROJECT_SCALE"
              echo "  📏 Details: $SCALE_DESC"
              echo "  📊 Code lines: $TOTAL_LINES"
              
              # File count analysis
              TOTAL_FILES=$(find . -type f -not -path '*/.*' 2>/dev/null | wc -l | tr -d ' ')
              echo "  📁 Total files: $TOTAL_FILES"
              
              # Directory depth analysis
              MAX_DEPTH=$(find . -type d 2>/dev/null | awk -F/ '{print NF-1}' | sort -rn | head -1)
              echo "  📐 Max directory depth: $MAX_DEPTH"
              echo ""
            ''}
            
            # Development phase detection
            ${optionalString config.dotfiles.context.projectDetection.developmentPhase.enable ''
              echo "🔄 Development Phase Analysis:"
              
              # Git analysis for development phase
              if git rev-parse --git-dir > /dev/null 2>&1 && git log -1 > /dev/null 2>&1; then
                # Check for recent activity
                DAYS_SINCE_COMMIT=$(git log -1 --format="%ct" | xargs -I {} date -j -f %s {} +%s 2>/dev/null | xargs -I {} bash -c 'echo $(( ($(date +%s) - {}) / 86400 ))' 2>/dev/null || echo "999")
                
                # Check for version tags
                LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
                
                # Check for CI/CD files
                CI_FILES=$(find . -name ".github" -o -name ".gitlab-ci.yml" -o -name "Jenkinsfile" -o -name ".circleci" 2>/dev/null | wc -l | tr -d ' ')
                
                # Check for deployment configs
                DEPLOY_FILES=$(find . -name "docker-compose.yml" -o -name "Dockerfile" -o -name "*.yaml" -o -name "*.yml" 2>/dev/null | grep -E "(deploy|k8s|kube)" | wc -l | tr -d ' ')
                
                # Determine phase
                if [[ "$DAYS_SINCE_COMMIT" -gt 365 ]]; then
                  DEV_PHASE="deprecated"
                  PHASE_EMOJI="💀"
                  PHASE_DESC="No activity for over a year"
                elif [[ "$DAYS_SINCE_COMMIT" -gt 90 ]]; then
                  DEV_PHASE="maintenance"
                  PHASE_EMOJI="🔧"
                  PHASE_DESC="Low activity - maintenance mode"
                elif [[ -n "$LATEST_TAG" ]] && [[ "$DEPLOY_FILES" -gt 0 ]]; then
                  DEV_PHASE="production"
                  PHASE_EMOJI="🚀"
                  PHASE_DESC="Tagged release with deployment configs"
                elif [[ "$CI_FILES" -gt 0 ]]; then
                  DEV_PHASE="staging"
                  PHASE_EMOJI="🧪"
                  PHASE_DESC="CI/CD configured - staging phase"
                elif [[ "$DAYS_SINCE_COMMIT" -lt 7 ]]; then
                  DEV_PHASE="development"
                  PHASE_EMOJI="💻"
                  PHASE_DESC="Active development - recent commits"
                else
                  DEV_PHASE="testing"
                  PHASE_EMOJI="🔬"
                  PHASE_DESC="Moderate activity - testing phase"
                fi
                
                echo "  $PHASE_EMOJI Phase: $DEV_PHASE"
                echo "  📋 Details: $PHASE_DESC"
                echo "  📅 Last commit: $DAYS_SINCE_COMMIT days ago"
                [[ -n "$LATEST_TAG" ]] && echo "  🏷️  Latest tag: $LATEST_TAG"
                echo "  🤖 CI/CD files: $CI_FILES"
                echo "  🚢 Deploy configs: $DEPLOY_FILES"
              else
                echo "  ⚠️  Not a Git repository or no commits"
                DEV_PHASE="planning"
                echo "  📝 Phase: planning (no version control detected)"
              fi
              echo ""
            ''}
            
            # Summary output
            case "$OUTPUT_FORMAT" in
              "summary")
                echo "📋 Project Summary:"
                echo "  📁 Name: $PROJECT_NAME"
                echo "  🔤 Language: $LANGUAGES_DETECTED"
                echo "  🏗️  Framework: $FRAMEWORKS_DETECTED"
                echo "  📊 Scale: $PROJECT_SCALE"
                echo "  🔄 Phase: $DEV_PHASE"
                echo "  📏 Lines: $TOTAL_LINES"
                ;;
                
              "json")
                # Save JSON data
                CONTEXT_DIR="$HOME/.local/share/dotfiles-context/projects"
                mkdir -p "$CONTEXT_DIR"
                
                TIMESTAMP=$(date +%s)
                CONTEXT_FILE="$CONTEXT_DIR/project-$PROJECT_NAME-$TIMESTAMP.json"
                
                cat > "$CONTEXT_FILE" << EOF
{
  "timestamp": $TIMESTAMP,
  "detection_time": "$(date)",
  "project": {
    "name": "$PROJECT_NAME",
    "path": "$PROJECT_DIR",
    "language": "$LANGUAGES_DETECTED",
    "framework": "$FRAMEWORKS_DETECTED",
    "scale": "$PROJECT_SCALE",
    "development_phase": "$DEV_PHASE",
    "metrics": {
      "total_lines": $TOTAL_LINES,
      "total_files": ''${TOTAL_FILES:-0},
      "max_depth": ''${MAX_DEPTH:-0},
      "days_since_commit": ''${DAYS_SINCE_COMMIT:-999}
    }
  }
}
EOF
                
                echo ""
                echo "💾 Project context saved to: $CONTEXT_FILE"
                ;;
            esac
            ;;
            
          *)
            echo "Usage: project-detect-context [directory] [format]"
            echo ""
            echo "Formats:"
            echo "  summary        - Human-readable summary (default)"
            echo "  json           - JSON output with data storage"
            echo "  detailed       - Detailed analysis"
            ;;
        esac
      '')
      
      # Framework-specific detection
      (writeShellScriptBin "project-detect-framework" ''
        #!/bin/bash
        
        # Detailed framework detection
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        
        echo "🏗️  Framework Detection"
        echo "====================="
        echo "Analyzing: $PROJECT_DIR"
        echo ""
        
        cd "$PROJECT_DIR"
        
        # Web frameworks
        echo "🌐 Web Frameworks:"
        [[ -f "package.json" ]] && grep -q "react" package.json && echo "  ⚛️  React"
        [[ -f "package.json" ]] && grep -q "vue" package.json && echo "  💚 Vue.js"
        [[ -f "package.json" ]] && grep -q "angular" package.json && echo "  🅰️  Angular"
        [[ -f "package.json" ]] && grep -q "svelte" package.json && echo "  🧡 Svelte"
        [[ -f "package.json" ]] && grep -q "next" package.json && echo "  🔺 Next.js"
        
        echo ""
        
        # Backend frameworks
        echo "🔧 Backend Frameworks:"
        [[ -f "Cargo.toml" ]] && grep -q "actix" Cargo.toml && echo "  🕷️  Actix Web"
        [[ -f "go.mod" ]] && grep -q "gin" go.mod && echo "  🍸 Gin"
        [[ -f "requirements.txt" ]] && grep -q "django" requirements.txt && echo "  🎸 Django"
        [[ -f "requirements.txt" ]] && grep -q "fastapi" requirements.txt && echo "  ⚡ FastAPI"
        [[ -f "package.json" ]] && grep -q "express" package.json && echo "  🚂 Express.js"
        
        echo ""
        
        # Development tools
        echo "🛠️  Development Tools:"
        [[ -f "flake.nix" ]] && echo "  ❄️  Nix Flake"
        [[ -f "Dockerfile" ]] && echo "  🐳 Docker"
        [[ -f "docker-compose.yml" ]] && echo "  🐙 Docker Compose"
        [[ -d ".github" ]] && echo "  🐙 GitHub Actions"
        [[ -f ".gitlab-ci.yml" ]] && echo "  🦊 GitLab CI"
      '')
      
      # Project scale analysis
      (writeShellScriptBin "project-analyze-scale" ''
        #!/bin/bash
        
        # Project scale and complexity analysis
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        
        echo "📊 Project Scale Analysis"
        echo "========================"
        echo "Analyzing: $PROJECT_DIR"
        echo ""
        
        cd "$PROJECT_DIR"
        
        # Code metrics
        if command -v tokei >/dev/null 2>&1; then
          echo "📈 Code Metrics:"
          ${pkgs.tokei}/bin/tokei --sort lines
          echo ""
        fi
        
        # File analysis
        echo "📁 File Analysis:"
        TOTAL_FILES=$(find . -type f -not -path '*/.*' | wc -l | tr -d ' ')
        SOURCE_FILES=$(find . -name "*.rs" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" -o -name "*.cpp" -o -name "*.c" | wc -l | tr -d ' ')
        CONFIG_FILES=$(find . -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" -o -name "*.nix" | wc -l | tr -d ' ')
        
        echo "  📊 Total files: $TOTAL_FILES"
        echo "  💻 Source files: $SOURCE_FILES"
        echo "  ⚙️  Config files: $CONFIG_FILES"
        
        # Directory structure
        echo ""
        echo "📐 Directory Structure:"
        MAX_DEPTH=$(find . -type d | awk -F/ '{print NF-1}' | sort -rn | head -1)
        DIR_COUNT=$(find . -type d | wc -l | tr -d ' ')
        
        echo "  📏 Max depth: $MAX_DEPTH levels"
        echo "  📂 Total directories: $DIR_COUNT"
        
        # Complexity indicators
        echo ""
        echo "🧮 Complexity Indicators:"
        
        # Dependencies
        DEPS_COUNT=0
        [[ -f "package.json" ]] && DEPS_COUNT=$((DEPS_COUNT + $(grep -c '".*":' package.json 2>/dev/null || echo 0)))
        [[ -f "Cargo.toml" ]] && DEPS_COUNT=$((DEPS_COUNT + $(grep -c '=' Cargo.toml 2>/dev/null || echo 0)))
        [[ -f "go.mod" ]] && DEPS_COUNT=$((DEPS_COUNT + $(grep -c 'require' go.mod 2>/dev/null || echo 0)))
        
        echo "  📦 Dependencies: $DEPS_COUNT"
        
        # Git metrics (if available)
        if git rev-parse --git-dir > /dev/null 2>&1; then
          COMMIT_COUNT=$(git rev-list --all --count 2>/dev/null || echo 0)
          CONTRIBUTOR_COUNT=$(git log --format='%an' | sort -u | wc -l | tr -d ' ')
          echo "  📝 Commits: $COMMIT_COUNT"
          echo "  👥 Contributors: $CONTRIBUTOR_COUNT"
        fi
      '')
      
      # Development phase detection
      (writeShellScriptBin "project-detect-phase" ''
        #!/bin/bash
        
        # Development phase detection
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        
        echo "🔄 Development Phase Detection"
        echo "============================="
        echo "Analyzing: $PROJECT_DIR"
        echo ""
        
        cd "$PROJECT_DIR"
        
        # Git analysis
        if git rev-parse --git-dir > /dev/null 2>&1; then
          echo "📊 Git Analysis:"
          
          # Recent activity
          LAST_COMMIT=$(git log -1 --format="%cr" 2>/dev/null || echo "No commits")
          echo "  📅 Last commit: $LAST_COMMIT"
          
          # Commit frequency
          COMMITS_LAST_MONTH=$(git log --since="1 month ago" --oneline 2>/dev/null | wc -l | tr -d ' ')
          echo "  📈 Commits (last month): $COMMITS_LAST_MONTH"
          
          # Branch analysis
          BRANCH_COUNT=$(git branch -r 2>/dev/null | wc -l | tr -d ' ')
          echo "  🌳 Remote branches: $BRANCH_COUNT"
          
          # Tags
          TAG_COUNT=$(git tag 2>/dev/null | wc -l | tr -d ' ')
          LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "No tags")
          echo "  🏷️  Tags: $TAG_COUNT (latest: $LATEST_TAG)"
          
          echo ""
        fi
        
        # CI/CD indicators
        echo "🤖 CI/CD Analysis:"
        [[ -d ".github/workflows" ]] && echo "  ✅ GitHub Actions configured"
        [[ -f ".gitlab-ci.yml" ]] && echo "  ✅ GitLab CI configured"
        [[ -f "Jenkinsfile" ]] && echo "  ✅ Jenkins configured"
        [[ -d ".circleci" ]] && echo "  ✅ CircleCI configured"
        
        echo ""
        
        # Deployment indicators
        echo "🚀 Deployment Analysis:"
        [[ -f "Dockerfile" ]] && echo "  🐳 Docker containerized"
        [[ -f "docker-compose.yml" ]] && echo "  🐙 Docker Compose ready"
        [[ -d "k8s" ]] || [[ -d "kubernetes" ]] && echo "  ☸️  Kubernetes configs"
        [[ -f "vercel.json" ]] && echo "  ▲ Vercel deployment"
        [[ -f "netlify.toml" ]] && echo "  🌐 Netlify deployment"
        
        echo ""
        
        # Quality indicators
        echo "🔍 Quality Analysis:"
        [[ -f ".pre-commit-config.yaml" ]] && echo "  ✅ Pre-commit hooks"
        [[ -d "tests" ]] || [[ -d "test" ]] && echo "  🧪 Test directory present"
        [[ -f "README.md" ]] && echo "  📖 Documentation present"
        [[ -f "CHANGELOG.md" ]] && echo "  📋 Changelog maintained"
      '')
    ];
  };
}