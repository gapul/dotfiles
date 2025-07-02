{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    dotfiles.context.projectDetection = {
      enable = mkEnableOption "Intelligent project detection and analysis";
      
      languageDetection = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Automatic programming language detection";
        };
        
        frameworks = mkOption {
          type = types.listOf types.str;
          default = [
            "react" "vue" "angular" "svelte"
            "django" "fastapi" "flask" "rails"
            "express" "nestjs" "nextjs"
            "spring" "quarkus" ".net"
            "gatsby" "nuxt" "remix"
          ];
          description = "Supported framework detection patterns";
        };
        
        minAccuracy = mkOption {
          type = types.int;
          default = 80;
          description = "Minimum detection accuracy percentage (0-100)";
        };
      };
      
      projectScale = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Project scale and complexity analysis";
        };
        
        metrics = mkOption {
          type = types.listOf types.str;
          default = [
            "file_count" "line_count" "dependency_count" 
            "git_history" "contributor_count" "complexity_score"
          ];
          description = "Scale analysis metrics to collect";
        };
        
        thresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            small_max_lines = 1000;
            medium_max_lines = 10000;
            small_max_files = 50;
            medium_max_files = 500;
          };
          description = "Scale classification thresholds";
        };
      };
      
      developmentPhase = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Development phase detection";
        };
        
        phases = mkOption {
          type = types.listOf types.str;
          default = ["initial" "active" "maintenance" "legacy" "archived"];
          description = "Supported development phases";
        };
      };
      
      teamAnalysis = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Team size and collaboration pattern analysis";
        };
        
        gitAnalysis = mkOption {
          type = types.bool;
          default = true;
          description = "Git history-based team analysis";
        };
      };
    };
  };

  config = mkIf config.dotfiles.context.projectDetection.enable {
    environment.systemPackages = with pkgs; [
      # Project analysis tools
      (writeShellScriptBin "project-detect-context" ''
        #!/bin/bash
        
        # Intelligent project context detection
        
        set -euo pipefail
        
        PROJECT_PATH="''${1:-.}"
        OUTPUT_FORMAT="''${2:-json}"  # json, yaml, or summary
        
        if [ ! -d "$PROJECT_PATH" ]; then
          echo "Error: Project path does not exist: $PROJECT_PATH" >&2
          exit 1
        fi
        
        cd "$PROJECT_PATH"
        
        # Initialize analysis results
        TIMESTAMP=$(date +%s)
        PROJECT_NAME=$(basename "$(pwd)")
        
        echo "🔍 Analyzing project: $PROJECT_NAME"
        echo "📁 Path: $(pwd)"
        echo "⏰ Analysis started at: $(date)"
        echo ""
        
        # Language detection
        ${optionalString config.dotfiles.context.projectDetection.languageDetection.enable ''
          echo "🔤 Language Analysis:"
          LANGUAGES=$(${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .languages then .languages | to_entries[] | "\(.key): \(.value.code) lines (\(.value | (.code/(.code+.comments+.blanks)*100 | floor))%)" else empty end' | head -5)
          
          if [ -n "$LANGUAGES" ]; then
            echo "$LANGUAGES" | while read -r line; do
              echo "  📝 $line"
            done
            
            # Determine primary language
            PRIMARY_LANG=$(echo "$LANGUAGES" | head -1 | cut -d: -f1)
            echo "  🎯 Primary language: $PRIMARY_LANG"
          else
            echo "  ⚠️  No code files detected"
            PRIMARY_LANG="unknown"
          fi
          echo ""
        ''}
        
        # Framework detection
        ${optionalString config.dotfiles.context.projectDetection.languageDetection.enable ''
          echo "🚀 Framework Detection:"
          
          # Check package.json for JavaScript frameworks
          if [ -f "package.json" ]; then
            FRAMEWORKS=""
            
            # React detection
            if ${pkgs.jq}/bin/jq -e '.dependencies.react or .devDependencies.react' package.json >/dev/null 2>&1; then
              FRAMEWORKS="$FRAMEWORKS React"
              
              # TypeScript detection
              if ${pkgs.jq}/bin/jq -e '.dependencies.typescript or .devDependencies.typescript or .dependencies."@types/react"' package.json >/dev/null 2>&1; then
                FRAMEWORKS="$FRAMEWORKS + TypeScript"
              fi
              
              # Next.js detection
              if ${pkgs.jq}/bin/jq -e '.dependencies.next or .devDependencies.next' package.json >/dev/null 2>&1; then
                FRAMEWORKS="$FRAMEWORKS + Next.js"
              fi
            fi
            
            # Vue detection
            if ${pkgs.jq}/bin/jq -e '.dependencies.vue or .devDependencies.vue' package.json >/dev/null 2>&1; then
              FRAMEWORKS="$FRAMEWORKS Vue.js"
            fi
            
            # Angular detection
            if ${pkgs.jq}/bin/jq -e '.dependencies."@angular/core" or .devDependencies."@angular/core"' package.json >/dev/null 2>&1; then
              FRAMEWORKS="$FRAMEWORKS Angular"
            fi
            
            if [ -n "$FRAMEWORKS" ]; then
              echo "  🎨 JavaScript: $FRAMEWORKS"
            fi
          fi
          
          # Python framework detection
          if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
            PYTHON_FRAMEWORKS=""
            
            # Check for Django
            if grep -q "django" requirements.txt 2>/dev/null || grep -q "django" pyproject.toml 2>/dev/null; then
              PYTHON_FRAMEWORKS="$PYTHON_FRAMEWORKS Django"
            fi
            
            # Check for FastAPI
            if grep -q "fastapi" requirements.txt 2>/dev/null || grep -q "fastapi" pyproject.toml 2>/dev/null; then
              PYTHON_FRAMEWORKS="$PYTHON_FRAMEWORKS FastAPI"
            fi
            
            # Check for Flask
            if grep -q "flask" requirements.txt 2>/dev/null || grep -q "flask" pyproject.toml 2>/dev/null; then
              PYTHON_FRAMEWORKS="$PYTHON_FRAMEWORKS Flask"
            fi
            
            if [ -n "$PYTHON_FRAMEWORKS" ]; then
              echo "  🐍 Python: $PYTHON_FRAMEWORKS"
            fi
          fi
          
          # Nix detection
          if [ -f "flake.nix" ] || [ -f "default.nix" ] || [ -f "shell.nix" ]; then
            echo "  ❄️  Nix: Flake-based project"
          fi
          
          # Docker detection
          if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ]; then
            echo "  🐳 Docker: Containerized project"
          fi
          
          # Infrastructure as Code
          if [ -f "terraform.tf" ] || [ -d ".terraform" ]; then
            echo "  🏗️  Terraform: Infrastructure as Code"
          fi
          
          if [ -d ".github/workflows" ] || [ -f ".gitlab-ci.yml" ]; then
            echo "  🔄 CI/CD: Automated workflows detected"
          fi
          
          echo ""
        ''}
        
        # Project scale analysis
        ${optionalString config.dotfiles.context.projectDetection.projectScale.enable ''
          echo "📊 Project Scale Analysis:"
          
          # File count
          FILE_COUNT=$(find . -type f -not -path '*/.*' -not -path '*/node_modules/*' -not -path '*/target/*' -not -path '*/__pycache__/*' | wc -l)
          echo "  📄 Total files: $FILE_COUNT"
          
          # Line count
          if command -v ${pkgs.tokei}/bin/tokei >/dev/null; then
            LINE_COUNT=$(${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .Total then .Total.code else 0 end')
            echo "  📝 Lines of code: $LINE_COUNT"
          else
            LINE_COUNT=0
          fi
          
          # Git analysis
          if [ -d ".git" ]; then
            if git rev-parse --git-dir > /dev/null 2>&1 && git log -1 > /dev/null 2>&1; then
              COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
              CONTRIBUTOR_COUNT=$(git log --format='%aN' | sort -u | wc -l 2>/dev/null || echo "0")
              LAST_COMMIT=$(git log -1 --format='%cr' 2>/dev/null || echo "unknown")
            else
              COMMIT_COUNT=0
              CONTRIBUTOR_COUNT=0
              LAST_COMMIT="no commits"
            fi
            
            echo "  📊 Git commits: $COMMIT_COUNT"
            echo "  👥 Contributors: $CONTRIBUTOR_COUNT"
            echo "  🕐 Last commit: $LAST_COMMIT"
          fi
          
          # Scale classification
          SCALE_CATEGORY="unknown"
          if [ "$LINE_COUNT" -lt "${toString config.dotfiles.context.projectDetection.projectScale.thresholds.small_max_lines}" ] && 
             [ "$FILE_COUNT" -lt "${toString config.dotfiles.context.projectDetection.projectScale.thresholds.small_max_files}" ]; then
            SCALE_CATEGORY="small"
          elif [ "$LINE_COUNT" -lt "${toString config.dotfiles.context.projectDetection.projectScale.thresholds.medium_max_lines}" ] && 
               [ "$FILE_COUNT" -lt "${toString config.dotfiles.context.projectDetection.projectScale.thresholds.medium_max_files}" ]; then
            SCALE_CATEGORY="medium"
          else
            SCALE_CATEGORY="large"
          fi
          
          echo "  🎯 Scale category: $SCALE_CATEGORY"
          echo ""
        ''}
        
        # Development phase detection
        ${optionalString config.dotfiles.context.projectDetection.developmentPhase.enable ''
          echo "🔄 Development Phase Analysis:"
          
          PHASE="unknown"
          
          if [ -d ".git" ] && git rev-parse --git-dir > /dev/null 2>&1 && git log -1 > /dev/null 2>&1; then
            COMMITS_LAST_MONTH=$(git log --since="1 month ago" --oneline 2>/dev/null | wc -l || echo "0")
            COMMITS_LAST_WEEK=$(git log --since="1 week ago" --oneline 2>/dev/null | wc -l || echo "0")
            TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "0")
            
            if [ "$TOTAL_COMMITS" -lt 10 ]; then
              PHASE="initial"
            elif [ "$COMMITS_LAST_WEEK" -gt 5 ]; then
              PHASE="active"
            elif [ "$COMMITS_LAST_MONTH" -gt 2 ]; then
              PHASE="maintenance"
            elif [ "$COMMITS_LAST_MONTH" -eq 0 ] && [ "$TOTAL_COMMITS" -gt 50 ]; then
              PHASE="legacy"
            else
              PHASE="maintenance"
            fi
            
            echo "  📈 Recent activity: $COMMITS_LAST_WEEK commits this week, $COMMITS_LAST_MONTH this month"
          else
            PHASE="unknown"
            echo "  ⚠️  No git history available"
          fi
          
          echo "  🎯 Development phase: $PHASE"
          echo ""
        ''}
        
        # Team analysis
        ${optionalString config.dotfiles.context.projectDetection.teamAnalysis.enable ''
          echo "👥 Team Analysis:"
          
          if [ -d ".git" ] && git rev-parse --git-dir > /dev/null 2>&1 && git log -1 > /dev/null 2>&1; then
            # Get contributor statistics
            CONTRIBUTORS=$(git log --format='%aN' 2>/dev/null | sort | uniq -c | sort -nr)
            MAIN_CONTRIBUTOR=$(echo "$CONTRIBUTORS" | head -1 | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
            MAIN_COMMITS=$(echo "$CONTRIBUTORS" | head -1 | awk '{print $1}')
            TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "0")
            
            if [ "$TOTAL_COMMITS" -gt 0 ]; then
              MAIN_PERCENTAGE=$((MAIN_COMMITS * 100 / TOTAL_COMMITS))
              echo "  🏆 Main contributor: $MAIN_CONTRIBUTOR ($MAIN_COMMITS commits, $MAIN_PERCENTAGE%)"
            fi
            
            TEAM_SIZE=$(echo "$CONTRIBUTORS" | wc -l)
            echo "  👨‍💻 Team size: $TEAM_SIZE contributors"
            
            # Collaboration pattern
            if [ "$TEAM_SIZE" -eq 1 ]; then
              COLLABORATION="solo"
            elif [ "$TEAM_SIZE" -le 3 ]; then
              COLLABORATION="small_team"
            elif [ "$TEAM_SIZE" -le 10 ]; then
              COLLABORATION="medium_team"
            else
              COLLABORATION="large_team"
            fi
            
            echo "  🤝 Collaboration pattern: $COLLABORATION"
          else
            COLLABORATION="unknown"
            echo "  ⚠️  No git repository found or no commits"
          fi
          
          echo ""
        ''}
        
        # Output summary
        echo "✅ Analysis Complete!"
        echo "📋 Project Context Summary:"
        echo "  📦 Name: $PROJECT_NAME"
        echo "  📁 Path: $(pwd)"
        if [ -n "''${PRIMARY_LANG:-}" ]; then
          echo "  🔤 Primary Language: $PRIMARY_LANG"
        fi
        if [ -n "''${SCALE_CATEGORY:-}" ]; then
          echo "  📊 Scale: $SCALE_CATEGORY"
        fi
        if [ -n "''${PHASE:-}" ]; then
          echo "  🔄 Phase: $PHASE"
        fi
        if [ -n "''${COLLABORATION:-}" ]; then
          echo "  👥 Team: $COLLABORATION"
        fi
        
        # Save context data
        CONTEXT_DIR="$HOME/.local/share/dotfiles-context/projects"
        mkdir -p "$CONTEXT_DIR"
        
        PROJECT_HASH=$(echo "$(pwd)" | ${pkgs.coreutils}/bin/sha256sum | cut -c1-16)
        CONTEXT_FILE="$CONTEXT_DIR/$PROJECT_HASH.json"
        
        # Create JSON output
        cat > "$CONTEXT_FILE" << EOF
{
  "project_name": "$PROJECT_NAME",
  "project_path": "$(pwd)",
  "analysis_timestamp": $TIMESTAMP,
  "primary_language": "''${PRIMARY_LANG:-unknown}",
  "scale_category": "''${SCALE_CATEGORY:-unknown}",
  "development_phase": "''${PHASE:-unknown}",
  "collaboration_pattern": "''${COLLABORATION:-unknown}",
  "file_count": ''${FILE_COUNT:-0},
  "line_count": ''${LINE_COUNT:-0},
  "contributor_count": ''${CONTRIBUTOR_COUNT:-0},
  "commit_count": ''${COMMIT_COUNT:-0}
}
EOF
        
        echo ""
        echo "💾 Context saved to: $CONTEXT_FILE"
      '')
      
      # Framework-specific detection
      (writeShellScriptBin "project-detect-framework" ''
        #!/bin/bash
        
        # Specialized framework detection
        
        set -euo pipefail
        
        PROJECT_PATH="''${1:-.}"
        
        cd "$PROJECT_PATH"
        
        echo "🚀 Framework Detection for: $(basename "$(pwd)")"
        echo ""
        
        # Language-specific framework detection
        
        # JavaScript/TypeScript
        if [ -f "package.json" ]; then
          echo "📦 JavaScript/TypeScript Project:"
          
          # React ecosystem
          if ${pkgs.jq}/bin/jq -e '.dependencies.react' package.json >/dev/null 2>&1; then
            echo "  ⚛️  React: $(${pkgs.jq}/bin/jq -r '.dependencies.react' package.json)"
            
            # Next.js
            if ${pkgs.jq}/bin/jq -e '.dependencies.next' package.json >/dev/null 2>&1; then
              echo "    🔺 Next.js: $(${pkgs.jq}/bin/jq -r '.dependencies.next' package.json)"
            fi
            
            # Gatsby
            if ${pkgs.jq}/bin/jq -e '.dependencies.gatsby' package.json >/dev/null 2>&1; then
              echo "    🎨 Gatsby: $(${pkgs.jq}/bin/jq -r '.dependencies.gatsby' package.json)"
            fi
          fi
          
          # Vue ecosystem
          if ${pkgs.jq}/bin/jq -e '.dependencies.vue' package.json >/dev/null 2>&1; then
            echo "  🖖 Vue.js: $(${pkgs.jq}/bin/jq -r '.dependencies.vue' package.json)"
            
            # Nuxt
            if ${pkgs.jq}/bin/jq -e '.dependencies.nuxt' package.json >/dev/null 2>&1; then
              echo "    ⛰️  Nuxt.js: $(${pkgs.jq}/bin/jq -r '.dependencies.nuxt' package.json)"
            fi
          fi
          
          # Angular
          if ${pkgs.jq}/bin/jq -e '.dependencies."@angular/core"' package.json >/dev/null 2>&1; then
            echo "  🅰️  Angular: $(${pkgs.jq}/bin/jq -r '.dependencies."@angular/core"' package.json)"
          fi
          
          # Express.js
          if ${pkgs.jq}/bin/jq -e '.dependencies.express' package.json >/dev/null 2>&1; then
            echo "  🚄 Express.js: $(${pkgs.jq}/bin/jq -r '.dependencies.express' package.json)"
          fi
          
          # NestJS
          if ${pkgs.jq}/bin/jq -e '.dependencies."@nestjs/core"' package.json >/dev/null 2>&1; then
            echo "  🐈 NestJS: $(${pkgs.jq}/bin/jq -r '.dependencies."@nestjs/core"' package.json)"
          fi
          
          echo ""
        fi
        
        # Python frameworks
        if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
          echo "🐍 Python Project:"
          
          # Django
          if grep -q "django" requirements.txt 2>/dev/null || grep -q "django" pyproject.toml 2>/dev/null; then
            VERSION=$(grep "django" requirements.txt 2>/dev/null | head -1 || echo "django")
            echo "  🎸 Django: $VERSION"
          fi
          
          # FastAPI
          if grep -q "fastapi" requirements.txt 2>/dev/null || grep -q "fastapi" pyproject.toml 2>/dev/null; then
            VERSION=$(grep "fastapi" requirements.txt 2>/dev/null | head -1 || echo "fastapi")
            echo "  ⚡ FastAPI: $VERSION"
          fi
          
          # Flask
          if grep -q "flask" requirements.txt 2>/dev/null || grep -q "flask" pyproject.toml 2>/dev/null; then
            VERSION=$(grep "flask" requirements.txt 2>/dev/null | head -1 || echo "flask")
            echo "  🌶️  Flask: $VERSION"
          fi
          
          echo ""
        fi
        
        # Infrastructure detection
        echo "🏗️  Infrastructure & Tools:"
        
        # Docker
        if [ -f "Dockerfile" ]; then
          echo "  🐳 Docker: Dockerfile found"
        fi
        if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
          echo "  🐙 Docker Compose: Multi-container setup"
        fi
        
        # Kubernetes
        if [ -d "k8s" ] || [ -d "kubernetes" ] || find . -name "*.yaml" -exec grep -l "apiVersion.*v1" {} \; | head -1 >/dev/null; then
          echo "  ☸️  Kubernetes: Configuration detected"
        fi
        
        # Terraform
        if [ -f "main.tf" ] || [ -f "terraform.tf" ] || [ -d ".terraform" ]; then
          echo "  🏗️  Terraform: Infrastructure as Code"
        fi
        
        # CI/CD
        if [ -d ".github/workflows" ]; then
          WORKFLOW_COUNT=$(ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | wc -l)
          echo "  🔄 GitHub Actions: $WORKFLOW_COUNT workflows"
        fi
        
        if [ -f ".gitlab-ci.yml" ]; then
          echo "  🦊 GitLab CI: Pipeline configuration"
        fi
        
        if [ -f "Jenkinsfile" ]; then
          echo "  🤖 Jenkins: Pipeline as Code"
        fi
        
        echo ""
        echo "✅ Framework detection complete!"
      '')
      
      # Project scale analysis
      (writeShellScriptBin "project-analyze-scale" ''
        #!/bin/bash
        
        # Comprehensive project scale analysis
        
        set -euo pipefail
        
        PROJECT_PATH="''${1:-.}"
        
        cd "$PROJECT_PATH"
        
        echo "📊 Project Scale Analysis for: $(basename "$(pwd)")"
        echo ""
        
        # File and directory analysis
        echo "📁 File System Analysis:"
        
        TOTAL_FILES=$(find . -type f | wc -l)
        CODE_FILES=$(find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.rs" -o -name "*.cpp" -o -name "*.c" -o -name "*.nix" \) | wc -l)
        CONFIG_FILES=$(find . -type f \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" -o -name "*.ini" \) | wc -l)
        DOC_FILES=$(find . -type f \( -name "*.md" -o -name "*.rst" -o -name "*.txt" \) | wc -l)
        
        echo "  📄 Total files: $TOTAL_FILES"
        echo "  💻 Code files: $CODE_FILES"
        echo "  ⚙️  Config files: $CONFIG_FILES"
        echo "  📚 Documentation: $DOC_FILES"
        
        # Language-specific analysis
        if command -v ${pkgs.tokei}/bin/tokei >/dev/null; then
          echo ""
          echo "🔤 Language Breakdown:"
          ${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .languages then .languages | to_entries[] | "  \(.key): \(.value.code) lines, \(.value.reports | length) files" else empty end' | head -8
          
          TOTAL_LINES=$(${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .Total then .Total.code else 0 end')
          TOTAL_COMMENTS=$(${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .Total then .Total.comments else 0 end')
          COMMENT_RATIO=$((TOTAL_COMMENTS * 100 / (TOTAL_LINES + 1)))
          
          echo ""
          echo "📝 Code Statistics:"
          echo "  📊 Total lines of code: $TOTAL_LINES"
          echo "  💬 Comment lines: $TOTAL_COMMENTS ($COMMENT_RATIO%)"
        fi
        
        # Git analysis
        if [ -d ".git" ]; then
          echo ""
          echo "📈 Git Repository Analysis:"
          
          COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "0")
          BRANCHES=$(git branch -r | wc -l 2>/dev/null || echo "0")
          CONTRIBUTORS=$(git log --format='%aN' | sort -u | wc -l 2>/dev/null || echo "0")
          TAGS=$(git tag | wc -l 2>/dev/null || echo "0")
          
          echo "  📊 Commits: $COMMITS"
          echo "  🌿 Branches: $BRANCHES"  
          echo "  👥 Contributors: $CONTRIBUTORS"
          echo "  🏷️  Tags: $TAGS"
          
          # Recent activity
          COMMITS_LAST_MONTH=$(git log --since="1 month ago" --oneline | wc -l 2>/dev/null || echo "0")
          COMMITS_LAST_WEEK=$(git log --since="1 week ago" --oneline | wc -l 2>/dev/null || echo "0")
          
          echo "  📅 Recent activity: $COMMITS_LAST_WEEK commits this week, $COMMITS_LAST_MONTH this month"
          
          # Repository age
          FIRST_COMMIT=$(git log --reverse --format='%ct' | head -1 2>/dev/null || echo "0")
          if [ "$FIRST_COMMIT" != "0" ]; then
            CURRENT_TIME=$(date +%s)
            AGE_DAYS=$(((CURRENT_TIME - FIRST_COMMIT) / 86400))
            echo "  📆 Repository age: $AGE_DAYS days"
          fi
        fi
        
        # Dependency analysis
        echo ""
        echo "📦 Dependency Analysis:"
        
        if [ -f "package.json" ]; then
          DEPS=$(${pkgs.jq}/bin/jq -r '.dependencies // {} | length' package.json 2>/dev/null || echo "0")
          DEV_DEPS=$(${pkgs.jq}/bin/jq -r '.devDependencies // {} | length' package.json 2>/dev/null || echo "0")
          echo "  📦 npm dependencies: $DEPS production, $DEV_DEPS development"
        fi
        
        if [ -f "requirements.txt" ]; then
          PY_DEPS=$(grep -c "^[^#]" requirements.txt 2>/dev/null || echo "0")
          echo "  🐍 Python dependencies: $PY_DEPS"
        fi
        
        if [ -f "Cargo.toml" ]; then
          RUST_DEPS=$(grep -c "^[a-zA-Z]" Cargo.toml 2>/dev/null || echo "0")
          echo "  🦀 Rust dependencies: $RUST_DEPS"
        fi
        
        if [ -f "go.mod" ]; then
          GO_DEPS=$(grep -c "^[[:space:]]*[a-zA-Z]" go.mod 2>/dev/null || echo "0")
          echo "  🐹 Go dependencies: $GO_DEPS"
        fi
        
        # Complexity assessment
        echo ""
        echo "🧮 Complexity Assessment:"
        
        COMPLEXITY_SCORE=0
        
        # Lines of code factor
        if [ "$TOTAL_LINES" -gt 50000 ]; then
          COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 30))
        elif [ "$TOTAL_LINES" -gt 10000 ]; then
          COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 20))
        elif [ "$TOTAL_LINES" -gt 1000 ]; then
          COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 10))
        fi
        
        # File count factor
        if [ "$CODE_FILES" -gt 200 ]; then
          COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 20))
        elif [ "$CODE_FILES" -gt 50 ]; then
          COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 10))
        fi
        
        # Language diversity factor
        if command -v ${pkgs.tokei}/bin/tokei >/dev/null; then
          LANGUAGE_COUNT=$(${pkgs.tokei}/bin/tokei --output json . 2>/dev/null | ${pkgs.jq}/bin/jq -r 'if .languages then .languages | length else 0 end')
          if [ "$LANGUAGE_COUNT" -gt 5 ]; then
            COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 15))
          elif [ "$LANGUAGE_COUNT" -gt 3 ]; then
            COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 10))
          fi
        fi
        
        # Team size factor
        if [ "$CONTRIBUTORS" -gt 10 ]; then
          COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 15))
        elif [ "$CONTRIBUTORS" -gt 3 ]; then
          COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + 10))
        fi
        
        echo "  🎯 Complexity score: $COMPLEXITY_SCORE/100"
        
        if [ "$COMPLEXITY_SCORE" -lt 20 ]; then
          COMPLEXITY_LEVEL="Simple"
        elif [ "$COMPLEXITY_SCORE" -lt 40 ]; then
          COMPLEXITY_LEVEL="Moderate"
        elif [ "$COMPLEXITY_SCORE" -lt 60 ]; then
          COMPLEXITY_LEVEL="Complex"
        else
          COMPLEXITY_LEVEL="Highly Complex"
        fi
        
        echo "  📊 Complexity level: $COMPLEXITY_LEVEL"
        
        # Scale classification
        echo ""
        echo "📏 Scale Classification:"
        
        if [ "$TOTAL_LINES" -lt "${toString config.dotfiles.context.projectDetection.projectScale.thresholds.small_max_lines}" ] && 
           [ "$CODE_FILES" -lt "${toString config.dotfiles.context.projectDetection.projectScale.thresholds.small_max_files}" ]; then
          SCALE="Small"
          echo "  🐣 Scale: Small project"
          echo "    • Good for learning and prototyping"
          echo "    • Can be managed by 1-2 developers"
          echo "    • Fast iteration and deployment"
        elif [ "$TOTAL_LINES" -lt "${toString config.dotfiles.context.projectDetection.projectScale.thresholds.medium_max_lines}" ] && 
             [ "$CODE_FILES" -lt "${toString config.dotfiles.context.projectDetection.projectScale.thresholds.medium_max_files}" ]; then
          SCALE="Medium"
          echo "  🐧 Scale: Medium project"
          echo "    • Requires team coordination"
          echo "    • Benefits from CI/CD practices"
          echo "    • Modular architecture recommended"
        else
          SCALE="Large"
          echo "  🐘 Scale: Large project"
          echo "    • Enterprise-grade architecture needed"
          echo "    • Strong testing and documentation required"
          echo "    • Multiple teams coordination"
        fi
        
        echo ""
        echo "✅ Scale analysis complete!"
        echo "📋 Summary: $SCALE, $COMPLEXITY_LEVEL complexity"
      '')
      
      # Development phase detection
      (writeShellScriptBin "project-detect-phase" ''
        #!/bin/bash
        
        # Development phase detection and lifecycle analysis
        
        set -euo pipefail
        
        PROJECT_PATH="''${1:-.}"
        
        cd "$PROJECT_PATH"
        
        echo "🔄 Development Phase Analysis for: $(basename "$(pwd)")"
        echo ""
        
        if [ ! -d ".git" ]; then
          echo "⚠️  No git repository found. Limited analysis available."
          echo ""
        fi
        
        # Initialize phase analysis
        PHASE="unknown"
        CONFIDENCE=0
        INDICATORS=()
        
        # Git-based analysis
        if [ -d ".git" ]; then
          echo "📈 Git Activity Analysis:"
          
          TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "0")
          COMMITS_LAST_WEEK=$(git log --since="1 week ago" --oneline | wc -l 2>/dev/null || echo "0")
          COMMITS_LAST_MONTH=$(git log --since="1 month ago" --oneline | wc -l 2>/dev/null || echo "0")
          COMMITS_LAST_3_MONTHS=$(git log --since="3 months ago" --oneline | wc -l 2>/dev/null || echo "0")
          COMMITS_LAST_YEAR=$(git log --since="1 year ago" --oneline | wc -l 2>/dev/null || echo "0")
          
          echo "  📊 Total commits: $TOTAL_COMMITS"
          echo "  📅 Last week: $COMMITS_LAST_WEEK commits"
          echo "  📅 Last month: $COMMITS_LAST_MONTH commits"
          echo "  📅 Last 3 months: $COMMITS_LAST_3_MONTHS commits"
          echo "  📅 Last year: $COMMITS_LAST_YEAR commits"
          
          # Calculate commit frequency trends
          if [ "$TOTAL_COMMITS" -gt 0 ]; then
            FIRST_COMMIT_DATE=$(git log --reverse --format='%ct' | head -1 2>/dev/null || echo "0")
            CURRENT_TIME=$(date +%s)
            
            if [ "$FIRST_COMMIT_DATE" != "0" ]; then
              REPO_AGE_DAYS=$(((CURRENT_TIME - FIRST_COMMIT_DATE) / 86400))
              if [ "$REPO_AGE_DAYS" -gt 0 ]; then
                AVG_COMMITS_PER_DAY=$((TOTAL_COMMITS / REPO_AGE_DAYS))
                echo "  📊 Average: $AVG_COMMITS_PER_DAY commits/day over $REPO_AGE_DAYS days"
              fi
            fi
          fi
          
          echo ""
        fi
        
        # Phase classification logic
        echo "🎯 Phase Classification:"
        
        # Initial phase indicators
        if [ "$TOTAL_COMMITS" -lt 10 ]; then
          PHASE="initial"
          CONFIDENCE=80
          INDICATORS+=("Very few commits ($TOTAL_COMMITS)")
        
        # Active development indicators
        elif [ "$COMMITS_LAST_WEEK" -gt 3 ] || [ "$COMMITS_LAST_MONTH" -gt 10 ]; then
          PHASE="active"
          CONFIDENCE=90
          INDICATORS+=("High recent activity: $COMMITS_LAST_WEEK weekly, $COMMITS_LAST_MONTH monthly")
          
        # Maintenance phase indicators
        elif [ "$COMMITS_LAST_3_MONTHS" -gt 2 ] && [ "$COMMITS_LAST_3_MONTHS" -lt 20 ]; then
          PHASE="maintenance"
          CONFIDENCE=75
          INDICATORS+=("Moderate activity: $COMMITS_LAST_3_MONTHS commits in 3 months")
          
        # Legacy phase indicators  
        elif [ "$COMMITS_LAST_YEAR" -eq 0 ] && [ "$TOTAL_COMMITS" -gt 50 ]; then
          PHASE="legacy"
          CONFIDENCE=85
          INDICATORS+=("No activity in past year despite $TOTAL_COMMITS total commits")
          
        # Archive indicators
        elif [ "$COMMITS_LAST_YEAR" -eq 0 ] && [ "$TOTAL_COMMITS" -lt 50 ]; then
          PHASE="archived"
          CONFIDENCE=70
          INDICATORS+=("No recent activity and limited commit history")
          
        else
          PHASE="maintenance"
          CONFIDENCE=60
          INDICATORS+=("Default classification based on activity patterns")
        fi
        
        echo "  🏷️  Phase: $PHASE (confidence: $CONFIDENCE%)"
        echo ""
        
        # Additional indicators analysis
        echo "🔍 Supporting Indicators:"
        
        # README and documentation
        if [ -f "README.md" ] || [ -f "README.rst" ] || [ -f "README.txt" ]; then
          README_LINES=$(wc -l README.* 2>/dev/null | head -1 | awk '{print $1}' || echo "0")
          if [ "$README_LINES" -gt 50 ]; then
            INDICATORS+=("Well-documented ($README_LINES lines in README)")
            echo "  📚 Documentation: Comprehensive README ($README_LINES lines)"
          else
            echo "  📚 Documentation: Basic README present"
          fi
        else
          INDICATORS+=("Limited documentation")
          echo "  📚 Documentation: No README found"
        fi
        
        # Testing infrastructure
        if [ -d "test" ] || [ -d "tests" ] || [ -f "pytest.ini" ] || [ -f "jest.config.js" ]; then
          INDICATORS+=("Testing infrastructure present")
          echo "  🧪 Testing: Test infrastructure detected"
        else
          echo "  🧪 Testing: No obvious test infrastructure"
        fi
        
        # CI/CD presence
        if [ -d ".github/workflows" ] || [ -f ".gitlab-ci.yml" ] || [ -f "Jenkinsfile" ]; then
          INDICATORS+=("CI/CD pipeline configured")
          echo "  🔄 CI/CD: Automated workflows detected"
        else
          echo "  🔄 CI/CD: No automation detected"
        fi
        
        # Package management and versioning
        if [ -f "package.json" ]; then
          VERSION=$(${pkgs.jq}/bin/jq -r '.version // "unknown"' package.json 2>/dev/null)
          echo "  📦 Version: $VERSION (npm)"
        elif [ -f "pyproject.toml" ]; then
          VERSION=$(grep "version" pyproject.toml | head -1 | cut -d'"' -f2 2>/dev/null || echo "unknown")
          echo "  📦 Version: $VERSION (Python)"
        elif [ -f "Cargo.toml" ]; then
          VERSION=$(grep "version" Cargo.toml | head -1 | cut -d'"' -f2 2>/dev/null || echo "unknown")
          echo "  📦 Version: $VERSION (Rust)"
        fi
        
        # License presence
        if [ -f "LICENSE" ] || [ -f "LICENSE.txt" ] || [ -f "LICENSE.md" ]; then
          INDICATORS+=("Licensed project")
          echo "  ⚖️  License: Present"
        else
          echo "  ⚖️  License: Not found"
        fi
        
        echo ""
        
        # Phase-specific recommendations
        echo "💡 Recommendations for $PHASE phase:"
        
        case "$PHASE" in
          "initial")
            echo "  🌱 Focus on core functionality and MVP"
            echo "  📝 Establish coding standards and documentation"
            echo "  🧪 Set up basic testing infrastructure"
            echo "  🔄 Consider setting up CI/CD early"
            ;;
          "active")
            echo "  🚀 Maintain high code quality standards"
            echo "  🧪 Ensure comprehensive test coverage"
            echo "  📚 Keep documentation up to date"
            echo "  🔍 Consider code reviews and automated quality checks"
            ;;
          "maintenance")
            echo "  🔧 Focus on bug fixes and security updates"
            echo "  📊 Monitor for technical debt accumulation"
            echo "  🔒 Prioritize security patches"
            echo "  📈 Consider gradual modernization"
            ;;
          "legacy")
            echo "  🛡️  Focus on security and stability"
            echo "  📋 Document critical knowledge"
            echo "  🔄 Consider migration planning"
            echo "  ⚠️  Limit new feature development"
            ;;
          "archived")
            echo "  📦 Consider archiving the repository"
            echo "  📚 Preserve important documentation"
            echo "  🔗 Document replacement or successor projects"
            ;;
        esac
        
        echo ""
        echo "✅ Phase analysis complete!"
        echo "📋 Summary: $PHASE phase with $CONFIDENCE% confidence"
      '')
    ];
  };
}