# AI Context-Aware Development Assistance System
# Intelligent context awareness for enhanced development assistance
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.ai.contextAware = {
    enable = mkEnableOption "AI context-aware development assistance";
    
    environmentDetection = {
      enable = mkEnableOption "Automatic development environment detection";
      
      languageContext = mkOption {
        type = types.bool;
        default = true;
        description = "Detect and adapt to programming language context";
      };
      
      frameworkContext = mkOption {
        type = types.bool;
        default = true;
        description = "Detect and adapt to framework context (React, Django, etc.)";
      };
      
      projectContext = mkOption {
        type = types.bool;
        default = true;
        description = "Understand project structure and conventions";
      };
      
      taskContext = mkOption {
        type = types.bool;
        default = true;
        description = "Adapt to current development task context";
      };
    };
    
    intelligentSuggestions = {
      enable = mkEnableOption "Context-aware intelligent suggestions";
      
      codeCompletion = mkOption {
        type = types.bool;
        default = true;
        description = "Context-aware code completion suggestions";
      };
      
      testSuggestions = mkOption {
        type = types.bool;
        default = true;
        description = "Context-aware test generation suggestions";
      };
      
      documentationSuggestions = mkOption {
        type = types.bool;
        default = true;
        description = "Context-aware documentation suggestions";
      };
      
      refactoringSuggestions = mkOption {
        type = types.bool;
        default = false;
        description = "Context-aware refactoring suggestions";
      };
    };
    
    workflowAdaptation = {
      enable = mkEnableOption "Workflow adaptation based on context";
      
      gitWorkflow = mkOption {
        type = types.bool;
        default = true;
        description = "Adapt Git workflow to project conventions";
      };
      
      buildSystem = mkOption {
        type = types.bool;
        default = true;
        description = "Adapt to project build system and conventions";
      };
      
      deploymentContext = mkOption {
        type = types.bool;
        default = false;
        description = "Understand deployment context and environment";
      };
    };
    
    learningSystem = {
      enable = mkEnableOption "AI learning from user patterns";
      
      userPreferences = mkOption {
        type = types.bool;
        default = true;
        description = "Learn and adapt to user coding preferences";
      };
      
      projectPatterns = mkOption {
        type = types.bool;
        default = true;
        description = "Learn project-specific patterns and conventions";
      };
      
      teamPatterns = mkOption {
        type = types.bool;
        default = false;
        description = "Learn team coding patterns and conventions";
      };
    };
  };

  config = mkIf (config.dotfiles.ai.enable && config.dotfiles.ai.contextAware.enable) {
    # Context-aware AI tools
    environment.systemPackages = with pkgs; [
      # Environment context detector
      (writeShellScriptBin "ai-detect-context" ''
        #!/bin/bash
        
        # AI-powered development context detection
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        OUTPUT_FORMAT="''${2:-summary}"
        
        echo "🔍 AI Context Detection"
        echo "======================"
        echo "Project: $PROJECT_DIR"
        echo ""
        
        START_TIME=$(date +%s%3N)
        
        CONTEXT_FILE="$HOME/.local/share/dotfiles-ai/context/$(basename "$PROJECT_DIR")-context.json"
        mkdir -p "$(dirname "$CONTEXT_FILE")"
        
        # Initialize context data
        {
          echo "{"
          echo "  \"metadata\": {"
          echo "    \"project_path\": \"$PROJECT_DIR\","
          echo "    \"detected_at\": \"$(date -Iseconds)\","
          echo "    \"detector_version\": \"1.0\""
          echo "  },"
        } > "$CONTEXT_FILE"
        
        ${if config.dotfiles.ai.contextAware.environmentDetection.languageContext then ''
          echo "🔍 Language Context Detection..."
          
          # Detect primary languages
          declare -A LANG_FILES
          declare -A LANG_LINES
          
          while IFS= read -r file; do
            if [ -f "$file" ]; then
              EXT=$(echo "$file" | sed 's/.*\\.//')
              case "$EXT" in
                js|jsx) LANG="javascript" ;;
                ts|tsx) LANG="typescript" ;;
                py) LANG="python" ;;
                rs) LANG="rust" ;;
                go) LANG="go" ;;
                nix) LANG="nix" ;;
                c|h) LANG="c" ;;
                cpp|cxx|hpp) LANG="cpp" ;;
                java) LANG="java" ;;
                rb) LANG="ruby" ;;
                php) LANG="php" ;;
                *) LANG="other" ;;
              esac
              
              LANG_FILES["$LANG"]=$((''${LANG_FILES["$LANG"]:-0} + 1))
              LINES=$(wc -l < "$file" 2>/dev/null || echo 0)
              LANG_LINES["$LANG"]=$((''${LANG_LINES["$LANG"]:-0} + LINES))
            fi
          done < <(find "$PROJECT_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.rs" -o -name "*.go" -o -name "*.nix" -o -name "*.c" -o -name "*.cpp" -o -name "*.java" -o -name "*.rb" -o -name "*.php" \) 2>/dev/null)
          
          # Find primary language by lines of code
          PRIMARY_LANG=""
          MAX_LINES=0
          for lang in "''${!LANG_LINES[@]}"; do
            if [ "''${LANG_LINES[$lang]}" -gt "$MAX_LINES" ]; then
              MAX_LINES="''${LANG_LINES[$lang]}"
              PRIMARY_LANG="$lang"
            fi
          done
          
          {
            echo "  \"language_context\": {"
            echo "    \"primary_language\": \"$PRIMARY_LANG\","
            echo "    \"languages\": {"
            for lang in "''${!LANG_FILES[@]}"; do
              echo "      \"$lang\": {"
              echo "        \"files\": ''${LANG_FILES[$lang]},"
              echo "        \"lines\": ''${LANG_LINES[$lang]}"
              echo "      },"
            done | sed '$ s/,$//'
            echo "    }"
            echo "  },"
          } >> "$CONTEXT_FILE"
        '' else ''
          echo "  \"language_context\": { \"detected\": false }," >> "$CONTEXT_FILE"
        ''}
        
        ${if config.dotfiles.ai.contextAware.environmentDetection.frameworkContext then ''
          echo "🎯 Framework Context Detection..."
          
          FRAMEWORKS=""
          
          # Detect frameworks based on files and dependencies
          if [ -f "$PROJECT_DIR/package.json" ]; then
            if grep -q "react" "$PROJECT_DIR/package.json"; then
              FRAMEWORKS="$FRAMEWORKS\"react\","
            fi
            if grep -q "vue" "$PROJECT_DIR/package.json"; then
              FRAMEWORKS="$FRAMEWORKS\"vue\","
            fi
            if grep -q "angular" "$PROJECT_DIR/package.json"; then
              FRAMEWORKS="$FRAMEWORKS\"angular\","
            fi
            if grep -q "express" "$PROJECT_DIR/package.json"; then
              FRAMEWORKS="$FRAMEWORKS\"express\","
            fi
            if grep -q "next" "$PROJECT_DIR/package.json"; then
              FRAMEWORKS="$FRAMEWORKS\"nextjs\","
            fi
          fi
          
          if [ -f "$PROJECT_DIR/requirements.txt" ] || [ -f "$PROJECT_DIR/pyproject.toml" ]; then
            if grep -q "django" "$PROJECT_DIR/requirements.txt" "$PROJECT_DIR/pyproject.toml" 2>/dev/null; then
              FRAMEWORKS="$FRAMEWORKS\"django\","
            fi
            if grep -q "flask" "$PROJECT_DIR/requirements.txt" "$PROJECT_DIR/pyproject.toml" 2>/dev/null; then
              FRAMEWORKS="$FRAMEWORKS\"flask\","
            fi
            if grep -q "fastapi" "$PROJECT_DIR/requirements.txt" "$PROJECT_DIR/pyproject.toml" 2>/dev/null; then
              FRAMEWORKS="$FRAMEWORKS\"fastapi\","
            fi
          fi
          
          if [ -f "$PROJECT_DIR/Cargo.toml" ]; then
            if grep -q "actix" "$PROJECT_DIR/Cargo.toml"; then
              FRAMEWORKS="$FRAMEWORKS\"actix\","
            fi
            if grep -q "rocket" "$PROJECT_DIR/Cargo.toml"; then
              FRAMEWORKS="$FRAMEWORKS\"rocket\","
            fi
          fi
          
          if [ -f "$PROJECT_DIR/flake.nix" ]; then
            FRAMEWORKS="$FRAMEWORKS\"nix\","
          fi
          
          # Remove trailing comma
          FRAMEWORKS=$(echo "$FRAMEWORKS" | sed 's/,$//')
          
          {
            echo "  \"framework_context\": {"
            echo "    \"detected_frameworks\": [$FRAMEWORKS],"
            echo "    \"build_system\": \"$([ -f "$PROJECT_DIR/package.json" ] && echo "npm" || [ -f "$PROJECT_DIR/Cargo.toml" ] && echo "cargo" || [ -f "$PROJECT_DIR/go.mod" ] && echo "go" || [ -f "$PROJECT_DIR/Makefile" ] && echo "make" || echo "unknown")\""
            echo "  },"
          } >> "$CONTEXT_FILE"
        '' else ''
          echo "  \"framework_context\": { \"detected\": false }," >> "$CONTEXT_FILE"
        ''}
        
        ${if config.dotfiles.ai.contextAware.environmentDetection.projectContext then ''
          echo "📁 Project Context Detection..."
          
          # Analyze project structure
          TOTAL_FILES=$(find "$PROJECT_DIR" -type f -not -path "./.git/*" | wc -l)
          TOTAL_DIRS=$(find "$PROJECT_DIR" -type d -not -path "./.git/*" | wc -l)
          
          # Detect project type
          PROJECT_TYPE="unknown"
          if [ -f "$PROJECT_DIR/package.json" ]; then
            PROJECT_TYPE="nodejs"
          elif [ -f "$PROJECT_DIR/Cargo.toml" ]; then
            PROJECT_TYPE="rust"
          elif [ -f "$PROJECT_DIR/go.mod" ]; then
            PROJECT_TYPE="go"
          elif [ -f "$PROJECT_DIR/pyproject.toml" ] || [ -f "$PROJECT_DIR/setup.py" ]; then
            PROJECT_TYPE="python"
          elif [ -f "$PROJECT_DIR/flake.nix" ]; then
            PROJECT_TYPE="nix"
          fi
          
          # Detect testing framework
          TESTING_FRAMEWORK="unknown"
          if [ -d "$PROJECT_DIR/tests" ] || [ -d "$PROJECT_DIR/__tests__" ]; then
            if [ "$PROJECT_TYPE" = "nodejs" ] && grep -q "jest\|mocha\|cypress" "$PROJECT_DIR/package.json" 2>/dev/null; then
              TESTING_FRAMEWORK="jest"
            elif [ "$PROJECT_TYPE" = "python" ] && find "$PROJECT_DIR" -name "*test*.py" | head -1 | grep -q "test_"; then
              TESTING_FRAMEWORK="pytest"
            elif [ "$PROJECT_TYPE" = "rust" ]; then
              TESTING_FRAMEWORK="cargo-test"
            fi
          fi
          
          # Detect CI/CD
          CI_CD="none"
          if [ -d "$PROJECT_DIR/.github/workflows" ]; then
            CI_CD="github-actions"
          elif [ -f "$PROJECT_DIR/.gitlab-ci.yml" ]; then
            CI_CD="gitlab-ci"
          elif [ -f "$PROJECT_DIR/Jenkinsfile" ]; then
            CI_CD="jenkins"
          fi
          
          {
            echo "  \"project_context\": {"
            echo "    \"project_type\": \"$PROJECT_TYPE\","
            echo "    \"structure\": {"
            echo "      \"total_files\": $TOTAL_FILES,"
            echo "      \"total_directories\": $TOTAL_DIRS"
            echo "    },"
            echo "    \"testing_framework\": \"$TESTING_FRAMEWORK\","
            echo "    \"ci_cd\": \"$CI_CD\","
            echo "    \"has_readme\": $([ -f "$PROJECT_DIR/README.md" ] && echo "true" || echo "false"),"
            echo "    \"has_license\": $([ -f "$PROJECT_DIR/LICENSE" ] && echo "true" || echo "false")"
            echo "  },"
          } >> "$CONTEXT_FILE"
        '' else ''
          echo "  \"project_context\": { \"detected\": false }," >> "$CONTEXT_FILE"
        ''}
        
        ${if config.dotfiles.ai.contextAware.environmentDetection.taskContext then ''
          echo "🎯 Task Context Detection..."
          
          # Analyze recent Git activity
          TASK_CONTEXT="development"
          RECENT_BRANCH=""
          RECENT_COMMITS=""
          
          if [ -d "$PROJECT_DIR/.git" ]; then
            cd "$PROJECT_DIR"
            
            RECENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
            RECENT_COMMITS=$(git log --oneline -5 --pretty=format:"%s" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
            
            # Analyze branch name for context
            if echo "$RECENT_BRANCH" | grep -q "feature/"; then
              TASK_CONTEXT="feature-development"
            elif echo "$RECENT_BRANCH" | grep -q "fix/"; then
              TASK_CONTEXT="bug-fixing"
            elif echo "$RECENT_BRANCH" | grep -q "refactor/"; then
              TASK_CONTEXT="refactoring"
            elif echo "$RECENT_BRANCH" | grep -q "test/"; then
              TASK_CONTEXT="testing"
            elif echo "$RECENT_BRANCH" | grep -q "docs/"; then
              TASK_CONTEXT="documentation"
            fi
            
            cd - >/dev/null
          fi
          
          # Analyze current working files
          WORKING_FILES=""
          if [ -d "$PROJECT_DIR/.git" ]; then
            cd "$PROJECT_DIR"
            WORKING_FILES=$(git status --porcelain 2>/dev/null | head -10 | cut -c4- | tr '\n' ',' | sed 's/,$//')
            cd - >/dev/null
          fi
          
          {
            echo "  \"task_context\": {"
            echo "    \"current_task\": \"$TASK_CONTEXT\","
            echo "    \"current_branch\": \"$RECENT_BRANCH\","
            echo "    \"recent_commits\": \"$RECENT_COMMITS\","
            echo "    \"working_files\": \"$WORKING_FILES\""
            echo "  },"
          } >> "$CONTEXT_FILE"
        '' else ''
          echo "  \"task_context\": { \"detected\": false }," >> "$CONTEXT_FILE"
        ''}
        
        # AI recommendations based on context
        echo "💡 Generating Context-Aware Recommendations..."
        
        {
          echo "  \"ai_recommendations\": {"
          echo "    \"suggested_actions\": ["
          
          RECOMMENDATIONS=""
          
          # Language-specific recommendations
          if [ "$PRIMARY_LANG" = "javascript" ] || [ "$PRIMARY_LANG" = "typescript" ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Setup ESLint and Prettier for code quality\","
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Add TypeScript if not already using it\","
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Consider adding Husky for Git hooks\","
          fi
          
          if [ "$PRIMARY_LANG" = "python" ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Setup Black and isort for code formatting\","
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Add type hints using mypy\","
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Consider using poetry for dependency management\","
          fi
          
          if [ "$PRIMARY_LANG" = "rust" ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Use clippy for additional linting\","
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Add rustfmt configuration\","
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Consider using cargo-audit for security\","
          fi
          
          # Project-specific recommendations
          if [ "$TESTING_FRAMEWORK" = "unknown" ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Setup testing framework for better code quality\","
          fi
          
          if [ "$CI_CD" = "none" ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Setup CI/CD pipeline for automated testing\","
          fi
          
          if [ ! -f "$PROJECT_DIR/README.md" ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Create README.md for project documentation\","
          fi
          
          # Task-specific recommendations
          if [ "$TASK_CONTEXT" = "feature-development" ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Consider writing tests for new features\","
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Update documentation for new functionality\","
          fi
          
          if [ "$TASK_CONTEXT" = "bug-fixing" ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Add regression tests for fixed bugs\","
            RECOMMENDATIONS="$RECOMMENDATIONS      \"Consider refactoring related code\","
          fi
          
          # Remove trailing comma and empty items
          echo "$RECOMMENDATIONS" | sed 's/,$//g' | grep -v '^[[:space:]]*$'
          
          echo "    ],"
          echo "    \"context_score\": $([ -n "$PRIMARY_LANG" ] && echo 80 || echo 40),"
          echo "    \"confidence\": \"$([ -n "$PRIMARY_LANG" ] && [ "$PROJECT_TYPE" != "unknown" ] && echo "high" || echo "medium")\""
          echo "  }"
          echo "}"
        } >> "$CONTEXT_FILE"
        
        END_TIME=$(date +%s%3N)
        DURATION=$((END_TIME - START_TIME))
        
        echo ""
        echo "✅ Context detection completed in $DURATION ms"
        echo "📄 Context saved: $CONTEXT_FILE"
        
        # Display context summary
        if [ "$OUTPUT_FORMAT" = "summary" ]; then
          echo ""
          echo "📊 Context Summary:"
          echo "=================="
          echo "Primary Language: $PRIMARY_LANG"
          echo "Project Type: $PROJECT_TYPE"
          echo "Current Task: $TASK_CONTEXT"
          echo "Testing Framework: $TESTING_FRAMEWORK"
          echo "CI/CD: $CI_CD"
          echo ""
          echo "💡 Key Recommendations:"
          jq -r '.ai_recommendations.suggested_actions[]?' "$CONTEXT_FILE" 2>/dev/null | head -3 | sed 's/^/  • /'
        elif [ "$OUTPUT_FORMAT" = "json" ]; then
          cat "$CONTEXT_FILE"
        fi
        
        # Create symlink to latest
        ln -sf "$CONTEXT_FILE" "$HOME/.local/share/dotfiles-ai/context/latest-context.json"
        
        # Log performance
        ai-performance-tracker log "context-detection" "$DURATION" "true"
      '')
      
      # Context-aware code suggestions
      (writeShellScriptBin "ai-context-suggest" ''
        #!/bin/bash
        
        # AI context-aware code suggestions
        
        set -euo pipefail
        
        ACTION="''${1:-help}"
        FILE="''${2:-}"
        
        echo "🧠 AI Context-Aware Suggestions"
        echo "==============================="
        
        CONTEXT_FILE="$HOME/.local/share/dotfiles-ai/context/latest-context.json"
        
        if [ ! -f "$CONTEXT_FILE" ]; then
          echo "❌ No context information found"
          echo "Run 'ai-detect-context' first to analyze project context"
          exit 1
        fi
        
        PRIMARY_LANG=$(jq -r '.language_context.primary_language // "unknown"' "$CONTEXT_FILE")
        PROJECT_TYPE=$(jq -r '.project_context.project_type // "unknown"' "$CONTEXT_FILE")
        TASK_CONTEXT=$(jq -r '.task_context.current_task // "development"' "$CONTEXT_FILE")
        
        echo "Context: $PRIMARY_LANG | $PROJECT_TYPE | $TASK_CONTEXT"
        echo ""
        
        case "$ACTION" in
          help)
            echo "Available context-aware suggestions:"
            echo "  ai-context-suggest code <file>      - Context-aware code suggestions"
            echo "  ai-context-suggest test <file>      - Context-aware test suggestions"
            echo "  ai-context-suggest docs <file>      - Context-aware documentation suggestions"
            echo "  ai-context-suggest refactor <file>  - Context-aware refactoring suggestions"
            echo "  ai-context-suggest workflow         - Context-aware workflow suggestions"
            ;;
            
          code)
            ${if config.dotfiles.ai.contextAware.intelligentSuggestions.codeCompletion then ''
              if [ -z "$FILE" ]; then
                echo "Usage: ai-context-suggest code <file>"
                exit 1
              fi
              
              echo "💡 Context-Aware Code Suggestions for: $FILE"
              echo ""
              
              # Language-specific suggestions
              case "$PRIMARY_LANG" in
                javascript|typescript)
                  echo "🟨 JavaScript/TypeScript Context:"
                  if [ "$PROJECT_TYPE" = "nodejs" ]; then
                    echo "  • Add proper error handling with try-catch blocks"
                    echo "  • Use async/await for asynchronous operations"
                    echo "  • Consider adding JSDoc comments for functions"
                    if echo "$TASK_CONTEXT" | grep -q "feature"; then
                      echo "  • Add input validation for new features"
                      echo "  • Consider performance implications of new code"
                    fi
                  fi
                  ;;
                  
                python)
                  echo "🐍 Python Context:"
                  echo "  • Add type hints for function parameters and returns"
                  echo "  • Use docstrings for function documentation"
                  echo "  • Follow PEP 8 style guidelines"
                  if echo "$TASK_CONTEXT" | grep -q "feature"; then
                    echo "  • Consider using dataclasses for structured data"
                    echo "  • Add proper exception handling"
                  fi
                  ;;
                  
                rust)
                  echo "🦀 Rust Context:"
                  echo "  • Use Result<T, E> for error handling"
                  echo "  • Consider borrowing vs. ownership for parameters"
                  echo "  • Add documentation with /// comments"
                  if echo "$TASK_CONTEXT" | grep -q "feature"; then
                    echo "  • Design with zero-cost abstractions in mind"
                    echo "  • Consider thread safety implications"
                  fi
                  ;;
                  
                nix)
                  echo "❄️  Nix Context:"
                  echo "  • Use lib functions for common operations"
                  echo "  • Add proper option descriptions"
                  echo "  • Consider platform compatibility"
                  if echo "$TASK_CONTEXT" | grep -q "feature"; then
                    echo "  • Test on multiple platforms"
                    echo "  • Consider security implications"
                  fi
                  ;;
              esac
            '' else ''
              echo "Code completion suggestions disabled"
            ''}
            ;;
            
          test)
            ${if config.dotfiles.ai.contextAware.intelligentSuggestions.testSuggestions then ''
              if [ -z "$FILE" ]; then
                echo "Usage: ai-context-suggest test <file>"
                exit 1
              fi
              
              echo "🧪 Context-Aware Test Suggestions for: $FILE"
              echo ""
              
              TESTING_FRAMEWORK=$(jq -r '.project_context.testing_framework // "unknown"' "$CONTEXT_FILE")
              
              echo "Testing Framework: $TESTING_FRAMEWORK"
              echo ""
              
              case "$PRIMARY_LANG" in
                javascript|typescript)
                  echo "🟨 JavaScript/TypeScript Test Suggestions:"
                  echo "  • Test both success and error cases"
                  echo "  • Mock external dependencies"
                  echo "  • Test async function behavior"
                  if [ "$TESTING_FRAMEWORK" = "jest" ]; then
                    echo "  • Use Jest's snapshot testing for UI components"
                    echo "  • Consider using beforeEach for test setup"
                  fi
                  ;;
                  
                python)
                  echo "🐍 Python Test Suggestions:"
                  echo "  • Use pytest fixtures for test setup"
                  echo "  • Test edge cases and boundary conditions"
                  echo "  • Mock external API calls"
                  if [ "$TESTING_FRAMEWORK" = "pytest" ]; then
                    echo "  • Use parametrized tests for multiple scenarios"
                    echo "  • Consider using pytest-cov for coverage"
                  fi
                  ;;
                  
                rust)
                  echo "🦀 Rust Test Suggestions:"
                  echo "  • Test both Ok and Err cases for Results"
                  echo "  • Use #[should_panic] for error condition tests"
                  echo "  • Test concurrent code with proper synchronization"
                  if [ "$TESTING_FRAMEWORK" = "cargo-test" ]; then
                    echo "  • Use cargo-tarpaulin for coverage analysis"
                    echo "  • Consider property-based testing with proptest"
                  fi
                  ;;
              esac
            '' else ''
              echo "Test suggestions disabled"
            ''}
            ;;
            
          docs)
            ${if config.dotfiles.ai.contextAware.intelligentSuggestions.documentationSuggestions then ''
              if [ -z "$FILE" ]; then
                echo "Usage: ai-context-suggest docs <file>"
                exit 1
              fi
              
              echo "📚 Context-Aware Documentation Suggestions for: $FILE"
              echo ""
              
              case "$PRIMARY_LANG" in
                javascript|typescript)
                  echo "🟨 JavaScript/TypeScript Documentation:"
                  echo "  • Add JSDoc comments with @param and @returns"
                  echo "  • Document complex algorithms and business logic"
                  echo "  • Include usage examples in comments"
                  ;;
                  
                python)
                  echo "🐍 Python Documentation:"
                  echo "  • Add comprehensive docstrings using Google or NumPy style"
                  echo "  • Document function parameters, returns, and exceptions"
                  echo "  • Consider adding type information in docstrings"
                  ;;
                  
                rust)
                  echo "🦀 Rust Documentation:"
                  echo "  • Use /// for public API documentation"
                  echo "  • Add examples that can be tested with cargo test"
                  echo "  • Document panic conditions and safety requirements"
                  ;;
                  
                nix)
                  echo "❄️  Nix Documentation:"
                  echo "  • Add clear descriptions to all options"
                  echo "  • Document example usage and common patterns"
                  echo "  • Explain any platform-specific behavior"
                  ;;
              esac
            '' else ''
              echo "Documentation suggestions disabled"
            ''}
            ;;
            
          workflow)
            ${if config.dotfiles.ai.contextAware.workflowAdaptation.enable then ''
              echo "🔄 Context-Aware Workflow Suggestions"
              echo ""
              
              CURRENT_BRANCH=$(jq -r '.task_context.current_branch // "unknown"' "$CONTEXT_FILE")
              CI_CD=$(jq -r '.project_context.ci_cd // "none"' "$CONTEXT_FILE")
              
              echo "Current Branch: $CURRENT_BRANCH"
              echo "CI/CD: $CI_CD"
              echo ""
              
              case "$TASK_CONTEXT" in
                feature-development)
                  echo "🚀 Feature Development Workflow:"
                  echo "  • Create feature branch following naming convention"
                  echo "  • Write tests before implementing features (TDD)"
                  echo "  • Regular commits with descriptive messages"
                  echo "  • Create PR with comprehensive description"
                  ;;
                  
                bug-fixing)
                  echo "🐛 Bug Fixing Workflow:"
                  echo "  • Create reproduction test case first"
                  echo "  • Fix the minimal code necessary"
                  echo "  • Verify fix doesn't break existing functionality"
                  echo "  • Add regression test to prevent future issues"
                  ;;
                  
                refactoring)
                  echo "🔧 Refactoring Workflow:"
                  echo "  • Ensure all tests pass before starting"
                  echo "  • Make small, incremental changes"
                  echo "  • Run tests after each refactoring step"
                  echo "  • Update documentation as needed"
                  ;;
              esac
              
              # CI/CD specific suggestions
              if [ "$CI_CD" != "none" ]; then
                echo ""
                echo "🔄 CI/CD Integration:"
                echo "  • Ensure all tests pass in CI pipeline"
                echo "  • Check for security vulnerabilities"
                echo "  • Verify code coverage meets requirements"
                echo "  • Review deployment checklist"
              fi
            '' else ''
              echo "Workflow adaptation disabled"
            ''}
            ;;
            
          *)
            echo "Unknown action: $ACTION"
            echo "Run 'ai-context-suggest help' for available options"
            exit 1
            ;;
        esac
        
        # Log usage
        ai-performance-tracker log "context-suggest" "100" "true"
      '')
      
      # Adaptive workflow manager
      (writeShellScriptBin "ai-adaptive-workflow" ''
        #!/bin/bash
        
        # AI adaptive workflow management
        
        set -euo pipefail
        
        COMMAND="''${1:-status}"
        
        echo "🔄 AI Adaptive Workflow Manager"
        echo "==============================="
        
        case "$COMMAND" in
          status)
            echo ""
            echo "📊 Current Workflow Status:"
            
            # Check current context
            CONTEXT_FILE="$HOME/.local/share/dotfiles-ai/context/latest-context.json"
            
            if [ -f "$CONTEXT_FILE" ]; then
              PRIMARY_LANG=$(jq -r '.language_context.primary_language // "unknown"' "$CONTEXT_FILE")
              PROJECT_TYPE=$(jq -r '.project_context.project_type // "unknown"' "$CONTEXT_FILE")
              TASK_CONTEXT=$(jq -r '.task_context.current_task // "development"' "$CONTEXT_FILE")
              CURRENT_BRANCH=$(jq -r '.task_context.current_branch // "unknown"' "$CONTEXT_FILE")
              
              echo "  Language: $PRIMARY_LANG"
              echo "  Project Type: $PROJECT_TYPE"
              echo "  Current Task: $TASK_CONTEXT"
              echo "  Current Branch: $CURRENT_BRANCH"
              
              # Suggest optimal workflow
              echo ""
              echo "💡 Recommended Workflow:"
              
              case "$TASK_CONTEXT" in
                feature-development)
                  echo "  1. 📝 Write/update tests for new feature"
                  echo "  2. 💻 Implement feature incrementally"
                  echo "  3. 🧪 Run tests frequently during development"
                  echo "  4. 📚 Update documentation"
                  echo "  5. 🔍 Run AI code review before commit"
                  echo "  6. 📤 Create PR with AI-generated description"
                  ;;
                  
                bug-fixing)
                  echo "  1. 🔍 Create reproduction test case"
                  echo "  2. 🔧 Implement minimal fix"
                  echo "  3. ✅ Verify all tests pass"
                  echo "  4. 📊 Run regression testing"
                  echo "  5. 📋 Update issue tracking"
                  ;;
                  
                *)
                  echo "  1. 🔍 Analyze current context with ai-detect-context"
                  echo "  2. 💡 Get suggestions with ai-context-suggest"
                  echo "  3. 🚀 Follow project-specific conventions"
                  echo "  4. 🧪 Maintain test coverage"
                  ;;
              esac
            else
              echo "  ❌ No context detected"
              echo "  Run 'ai-detect-context' to analyze project"
            fi
            ;;
            
          adapt)
            echo ""
            echo "🔧 Adapting workflow to current context..."
            
            # Re-detect context
            ai-detect-context > /dev/null
            
            # Set up context-aware Git hooks
            if [ -d ".git" ]; then
              echo "Setting up context-aware Git hooks..."
              
              # Pre-commit hook
              mkdir -p .git/hooks
              {
                echo "#!/bin/bash"
                echo "# Context-aware pre-commit hook"
                echo ""
                echo "ai-pre-commit-review"
                echo ""
                echo "# Context-specific checks"
                echo "CONTEXT_FILE=\"\$HOME/.local/share/dotfiles-ai/context/latest-context.json\""
                echo "if [ -f \"\$CONTEXT_FILE\" ]; then"
                echo "  PRIMARY_LANG=\$(jq -r '.language_context.primary_language // \"unknown\"' \"\$CONTEXT_FILE\")"
                echo "  case \"\$PRIMARY_LANG\" in"
                echo "    javascript|typescript)"
                echo "      if command -v eslint >/dev/null; then"
                echo "        echo \"Running ESLint...\""
                echo "        eslint . || exit 1"
                echo "      fi"
                echo "      ;;"
                echo "    python)"
                echo "      if command -v black >/dev/null; then"
                echo "        echo \"Running Black formatter...\""
                echo "        black --check . || exit 1"
                echo "      fi"
                echo "      ;;"
                echo "    rust)"
                echo "      if command -v cargo >/dev/null; then"
                echo "        echo \"Running Cargo check...\""
                echo "        cargo check || exit 1"
                echo "      fi"
                echo "      ;;"
                echo "  esac"
                echo "fi"
              } > .git/hooks/pre-commit
              
              chmod +x .git/hooks/pre-commit
              echo "✅ Context-aware Git hooks installed"
            fi
            
            echo "✅ Workflow adapted to current context"
            ;;
            
          learn)
            echo ""
            echo "🧠 Learning from user patterns..."
            
            ${if config.dotfiles.ai.contextAware.learningSystem.enable then ''
              # Analyze Git history for patterns
              if [ -d ".git" ]; then
                echo "Analyzing Git commit patterns..."
                
                PATTERNS_FILE="$HOME/.local/share/dotfiles-ai/patterns/user-patterns.json"
                mkdir -p "$(dirname "$PATTERNS_FILE")"
                
                # Extract commit patterns
                COMMIT_PATTERNS=$(git log --pretty=format:"%s" -20 | \
                  sed 's/^/  "/' | sed 's/$/"/' | tr '\n' ',' | sed 's/,$//')
                
                # Extract branch naming patterns
                BRANCH_PATTERNS=$(git branch -a | grep -v HEAD | \
                  sed 's/^[* ] //' | sed 's/remotes\/origin\///' | \
                  head -10 | sed 's/^/  "/' | sed 's/$/"/' | tr '\n' ',' | sed 's/,$//')
                
                {
                  echo "{"
                  echo "  \"commit_patterns\": [$COMMIT_PATTERNS],"
                  echo "  \"branch_patterns\": [$BRANCH_PATTERNS],"
                  echo "  \"learned_at\": \"$(date -Iseconds)\""
                  echo "}"
                } > "$PATTERNS_FILE"
                
                echo "✅ User patterns learned and saved"
              else
                echo "❌ Not in a Git repository"
              fi
            '' else ''
              echo "Learning system disabled"
            ''}
            ;;
            
          *)
            echo "Unknown command: $COMMAND"
            echo ""
            echo "Available commands:"
            echo "  status  - Show current workflow status and recommendations"
            echo "  adapt   - Adapt workflow to current context"
            echo "  learn   - Learn patterns from user behavior"
            ;;
        esac
      '')
    ];
  };
}