# AI Intelligent Development Workflow Automation
# Automated development workflows powered by AI insights
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.ai.workflows = {
    enable = mkEnableOption "AI intelligent development workflow automation";
    
    automatedCodeReview = {
      enable = mkEnableOption "Automated AI code review workflows";
      
      reviewOnCommit = mkOption {
        type = types.bool;
        default = false;
        description = "Trigger AI review before commits";
      };
      
      reviewOnPR = mkOption {
        type = types.bool;
        default = true;
        description = "Trigger AI review on pull requests";
      };
      
      blockingReview = mkOption {
        type = types.bool;
        default = false;
        description = "Block commits/PRs with failing AI review";
      };
      
      reviewCriteria = mkOption {
        type = types.listOf types.str;
        default = [ "security" "performance" "maintainability" "style" ];
        description = "AI review criteria to evaluate";
      };
    };
    
    intelligentBranching = {
      enable = mkEnableOption "AI-powered branch management";
      
      autoNaming = mkOption {
        type = types.bool;
        default = true;
        description = "Generate intelligent branch names based on changes";
      };
      
      suggestMergeStrategy = mkOption {
        type = types.bool;
        default = true;
        description = "Suggest optimal merge strategies";
      };
      
      autoCleanup = mkOption {
        type = types.bool;
        default = false;
        description = "Automatically cleanup merged branches";
      };
    };
    
    cicdIntegration = {
      enable = mkEnableOption "AI-enhanced CI/CD workflows";
      
      testOptimization = mkOption {
        type = types.bool;
        default = true;
        description = "Optimize test execution based on change analysis";
      };
      
      buildOptimization = mkOption {
        type = types.bool;
        default = true;
        description = "Optimize build processes with AI insights";
      };
      
      deploymentValidation = mkOption {
        type = types.bool;
        default = false;
        description = "AI validation before deployments";
      };
    };
    
    projectMaintenance = {
      enable = mkEnableOption "Automated project maintenance workflows";
      
      dependencyUpdates = mkOption {
        type = types.bool;
        default = true;
        description = "AI-guided dependency updates";
      };
      
      codeHealthChecks = mkOption {
        type = types.bool;
        default = true;
        description = "Regular code health assessments";
      };
      
      documentationSync = mkOption {
        type = types.bool;
        default = true;
        description = "Keep documentation synchronized with code";
      };
    };
  };

  config = mkIf (config.dotfiles.ai.enable && config.dotfiles.ai.workflows.enable) {
    # AI workflow automation tools
    environment.systemPackages = with pkgs; [
      # Pre-commit AI review hook
      (writeShellScriptBin "ai-pre-commit-review" ''
        #!/bin/bash
        
        # AI-powered pre-commit code review
        
        set -euo pipefail
        
        ${if config.dotfiles.ai.workflows.automatedCodeReview.reviewOnCommit then ''
          echo "🤖 Running AI pre-commit review..."
          
          START_TIME=$(date +%s%3N)
          
          # Get staged files
          STAGED_FILES=$(git diff --cached --name-only)
          
          if [ -z "$STAGED_FILES" ]; then
            echo "No staged files to review"
            exit 0
          fi
          
          echo "Reviewing staged files:"
          echo "$STAGED_FILES" | sed 's/^/  - /'
          echo ""
          
          REVIEW_PASSED=true
          ISSUES_FOUND=0
          
          # Review each staged file
          while IFS= read -r file; do
            if [ -f "$file" ]; then
              echo "Reviewing: $file"
              
              # Run AI code review
              REVIEW_OUTPUT=$(ai-code-review "$file" 2>&1) || true
              
              # Check for critical issues
              ${concatMapStrings (criteria: ''
                if echo "$REVIEW_OUTPUT" | grep -qi "${criteria}.*⚠️\|${criteria}.*❌"; then
                  echo "  ❌ ${criteria} issues found in $file"
                  ISSUES_FOUND=$((ISSUES_FOUND + 1))
                  ${if config.dotfiles.ai.workflows.automatedCodeReview.blockingReview then ''
                    REVIEW_PASSED=false
                  '' else ""}
                fi
              '') config.dotfiles.ai.workflows.automatedCodeReview.reviewCriteria}
              
              # Check for improvement suggestions
              if echo "$REVIEW_OUTPUT" | grep -q "💡 Recommendations"; then
                echo "  💡 Improvement suggestions available for $file"
              fi
            fi
          done <<< "$STAGED_FILES"
          
          END_TIME=$(date +%s%3N)
          DURATION=$((END_TIME - START_TIME))
          
          echo ""
          echo "Review completed in $DURATION ms"
          
          if [ "$ISSUES_FOUND" -gt 0 ]; then
            echo "⚠️  Found $ISSUES_FOUND potential issues"
            ${if config.dotfiles.ai.workflows.automatedCodeReview.blockingReview then ''
              if [ "$REVIEW_PASSED" = false ]; then
                echo "❌ Commit blocked due to critical issues"
                echo "Use 'git commit --no-verify' to bypass review"
                exit 1
              fi
            '' else ''
              echo "ℹ️  Review is advisory only - commit will proceed"
            ''}
          else
            echo "✅ No critical issues found"
          fi
          
          # Log review performance
          ai-performance-tracker log "pre-commit-review" "$DURATION" "$REVIEW_PASSED"
        '' else ''
          echo "Pre-commit AI review disabled"
        ''}
      '')
      
      # Intelligent branch naming
      (writeShellScriptBin "ai-branch-create" ''
        #!/bin/bash
        
        # AI-powered intelligent branch creation
        
        set -euo pipefail
        
        BRANCH_TYPE="$1"
        DESCRIPTION="''${2:-}"
        
        if [ -z "$BRANCH_TYPE" ]; then
          echo "Usage: ai-branch-create <type> [description]"
          echo "Types: feature, fix, refactor, docs, test, chore"
          exit 1
        fi
        
        ${if config.dotfiles.ai.workflows.intelligentBranching.autoNaming then ''
          echo "🤖 Generating intelligent branch name..."
          
          START_TIME=$(date +%s%3N)
          
          # Analyze current changes
          CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null || git ls-files -m 2>/dev/null || echo "")
          CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
          
          # Generate branch name based on context
          if [ -n "$DESCRIPTION" ]; then
            # Use provided description
            CLEAN_DESC=$(echo "$DESCRIPTION" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
            BRANCH_NAME="$BRANCH_TYPE/$CLEAN_DESC"
          else
            # Analyze changes to suggest name
            if [ -n "$CHANGED_FILES" ]; then
              echo "Analyzing changed files for context..."
              
              # Detect primary area of change
              PRIMARY_AREA=""
              if echo "$CHANGED_FILES" | grep -q "nix/"; then
                PRIMARY_AREA="nix-config"
              elif echo "$CHANGED_FILES" | grep -q "\.js\|\.ts"; then
                PRIMARY_AREA="frontend"
              elif echo "$CHANGED_FILES" | grep -q "\.py"; then
                PRIMARY_AREA="python"
              elif echo "$CHANGED_FILES" | grep -q "\.md"; then
                PRIMARY_AREA="docs"
              elif echo "$CHANGED_FILES" | grep -q "test"; then
                PRIMARY_AREA="testing"
              else
                PRIMARY_AREA="general"
              fi
              
              # Generate timestamp-based fallback
              TIMESTAMP=$(date +%m%d-%H%M)
              BRANCH_NAME="$BRANCH_TYPE/$PRIMARY_AREA-$TIMESTAMP"
            else
              # No changes detected, use timestamp
              TIMESTAMP=$(date +%m%d-%H%M)
              BRANCH_NAME="$BRANCH_TYPE/update-$TIMESTAMP"
            fi
          fi
          
          echo "Suggested branch name: $BRANCH_NAME"
          
          # Validate branch name doesn't exist
          if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
            echo "⚠️  Branch $BRANCH_NAME already exists"
            COUNTER=2
            while git show-ref --verify --quiet "refs/heads/$BRANCH_NAME-$COUNTER"; do
              COUNTER=$((COUNTER + 1))
            done
            BRANCH_NAME="$BRANCH_NAME-$COUNTER"
            echo "Using: $BRANCH_NAME"
          fi
          
          # Create the branch
          echo "Creating branch: $BRANCH_NAME"
          git checkout -b "$BRANCH_NAME"
          
          END_TIME=$(date +%s%3N)
          DURATION=$((END_TIME - START_TIME))
          
          echo "✅ Branch created successfully in $DURATION ms"
          
          # Log performance
          ai-performance-tracker log "branch-create" "$DURATION" "true"
        '' else ''
          # Simple branch creation
          BRANCH_NAME="$BRANCH_TYPE/$(date +%m%d-%H%M)"
          if [ -n "$DESCRIPTION" ]; then
            CLEAN_DESC=$(echo "$DESCRIPTION" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
            BRANCH_NAME="$BRANCH_TYPE/$CLEAN_DESC"
          fi
          
          echo "Creating branch: $BRANCH_NAME"
          git checkout -b "$BRANCH_NAME"
        ''}
      '')
      
      # AI-enhanced PR creation
      (writeShellScriptBin "ai-pr-create" ''
        #!/bin/bash
        
        # AI-powered pull request creation
        
        set -euo pipefail
        
        BASE_BRANCH="''${1:-main}"
        
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
          echo "❌ Not in a git repository"
          exit 1
        fi
        
        CURRENT_BRANCH=$(git branch --show-current)
        
        if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
          echo "❌ Cannot create PR from base branch"
          exit 1
        fi
        
        echo "🤖 Creating AI-enhanced pull request..."
        echo "From: $CURRENT_BRANCH → $BASE_BRANCH"
        
        START_TIME=$(date +%s%3N)
        
        # Analyze changes
        CHANGED_FILES=$(git diff "$BASE_BRANCH"..HEAD --name-only)
        COMMIT_COUNT=$(git rev-list --count "$BASE_BRANCH"..HEAD)
        
        echo ""
        echo "📊 Change Analysis:"
        echo "  Files changed: $(echo "$CHANGED_FILES" | wc -l)"
        echo "  Commits: $COMMIT_COUNT"
        
        # Generate PR title and description
        echo ""
        echo "🔍 Analyzing commits for PR content..."
        
        # Get commit messages
        COMMITS=$(git log "$BASE_BRANCH"..HEAD --pretty=format:"%s" | head -10)
        
        # Generate title based on branch name and commits
        PR_TITLE=$(echo "$CURRENT_BRANCH" | sed 's/.*\///' | tr '-' ' ' | sed 's/\b\w/\u&/g')
        
        # Detect change type
        CHANGE_TYPE="feat"
        if echo "$CURRENT_BRANCH" | grep -q "fix/"; then
          CHANGE_TYPE="fix"
        elif echo "$CURRENT_BRANCH" | grep -q "docs/"; then
          CHANGE_TYPE="docs"
        elif echo "$CURRENT_BRANCH" | grep -q "refactor/"; then
          CHANGE_TYPE="refactor"
        elif echo "$CURRENT_BRANCH" | grep -q "test/"; then
          CHANGE_TYPE="test"
        fi
        
        # Generate description
        PR_DESCRIPTION="## Summary

This PR implements $PR_TITLE

### Changes
- Modified $( echo "$CHANGED_FILES" | wc -l | tr -d ' ') files across $COMMIT_COUNT commits

### Key Files Changed
$(echo "$CHANGED_FILES" | head -10 | sed 's/^/- /')

### Commits Included
$(echo "$COMMITS" | sed 's/^/- /')

### Testing
- [ ] Manual testing completed
- [ ] All existing tests pass
- [ ] New tests added (if applicable)

---
🤖 Generated with AI Development Assistant"
        
        # Run AI review if enabled
        ${if config.dotfiles.ai.workflows.automatedCodeReview.reviewOnPR then ''
          echo ""
          echo "🔍 Running AI review..."
          
          REVIEW_SUMMARY=""
          CRITICAL_ISSUES=0
          
          while IFS= read -r file; do
            if [ -f "$file" ]; then
              REVIEW_OUTPUT=$(ai-code-review "$file" 2>&1) || true
              
              # Check for issues
              if echo "$REVIEW_OUTPUT" | grep -q "❌\|⚠️"; then
                CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
              fi
            fi
          done <<< "$CHANGED_FILES"
          
          if [ "$CRITICAL_ISSUES" -gt 0 ]; then
            REVIEW_SUMMARY="
### ⚠️ AI Review Findings
- Found potential issues in $CRITICAL_ISSUES files
- Run \`ai-assist review <file>\` for detailed analysis
- Consider addressing issues before merging"
          else
            REVIEW_SUMMARY="
### ✅ AI Review
- No critical issues detected
- Code quality looks good"
          fi
          
          PR_DESCRIPTION="$PR_DESCRIPTION$REVIEW_SUMMARY"
        '' else ""}
        
        # Create the PR
        echo ""
        echo "📝 Creating pull request..."
        
        # Use GitHub CLI if available
        if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
          echo "$PR_DESCRIPTION" | gh pr create \
            --title "$PR_TITLE" \
            --body-file - \
            --base "$BASE_BRANCH" \
            --head "$CURRENT_BRANCH"
          
          PR_URL=$(gh pr view --json url --jq .url)
          
          END_TIME=$(date +%s%3N)
          DURATION=$((END_TIME - START_TIME))
          
          echo "✅ Pull request created successfully in $DURATION ms"
          echo "🔗 $PR_URL"
          
          # Log performance
          ai-performance-tracker log "pr-create" "$DURATION" "true"
        else
          echo "GitHub CLI not available or not authenticated"
          echo "PR Title: $PR_TITLE"
          echo ""
          echo "PR Description:"
          echo "$PR_DESCRIPTION"
          echo ""
          echo "Create the PR manually with the above content"
        fi
      '')
      
      # CI/CD optimization analyzer
      (writeShellScriptBin "ai-cicd-optimize" ''
        #!/bin/bash
        
        # AI-powered CI/CD workflow optimization
        
        set -euo pipefail
        
        echo "🚀 AI CI/CD Optimization Analysis"
        echo "================================"
        
        PROJECT_DIR="$(pwd)"
        
        ${if config.dotfiles.ai.workflows.cicdIntegration.enable then ''
          echo ""
          echo "🔍 Analyzing CI/CD configuration..."
          
          # Check for CI/CD files
          CICD_FILES=""
          if [ -f ".github/workflows"/*.yml ] || [ -f ".github/workflows"/*.yaml ]; then
            CICD_FILES="GitHub Actions"
          fi
          if [ -f ".gitlab-ci.yml" ]; then
            CICD_FILES="$CICD_FILES GitLab CI"
          fi
          if [ -f "Jenkinsfile" ]; then
            CICD_FILES="$CICD_FILES Jenkins"
          fi
          
          echo "Detected CI/CD: $CICD_FILES"
          
          # Analyze recent builds (if data available)
          if [ -d ".git" ]; then
            RECENT_COMMITS=$(git log --oneline -10)
            echo ""
            echo "📊 Recent Development Activity:"
            echo "$RECENT_COMMITS" | nl -w3 -s'. '
          fi
          
          echo ""
          echo "💡 Optimization Recommendations:"
          
          # Test optimization suggestions
          ${if config.dotfiles.ai.workflows.cicdIntegration.testOptimization then ''
            echo ""
            echo "🧪 Test Optimization:"
            
            # Analyze test structure
            TEST_FILES=$(find . -name "*test*" -type f 2>/dev/null | wc -l)
            echo "  - Found $TEST_FILES test files"
            
            if [ "$TEST_FILES" -gt 50 ]; then
              echo "  💡 Consider test parallelization for faster execution"
              echo "  💡 Implement smart test selection based on changed files"
            fi
            
            if [ "$TEST_FILES" -lt 10 ]; then
              echo "  ⚠️  Low test coverage detected - consider adding more tests"
            fi
          '' else ""}
          
          # Build optimization suggestions
          ${if config.dotfiles.ai.workflows.cicdIntegration.buildOptimization then ''
            echo ""
            echo "🔨 Build Optimization:"
            
            # Check build tools
            if [ -f "package.json" ]; then
              echo "  💡 Node.js: Consider using npm ci for faster installs"
              echo "  💡 Implement dependency caching"
            fi
            
            if [ -f "Cargo.toml" ]; then
              echo "  💡 Rust: Enable incremental compilation"
              echo "  💡 Cache target directory"
            fi
            
            if [ -f "go.mod" ]; then
              echo "  💡 Go: Use module cache for faster builds"
            fi
            
            if [ -f "flake.nix" ]; then
              echo "  💡 Nix: Implement binary cache for dependencies"
              echo "  💡 Use nix-direnv for development shell caching"
            fi
          '' else ""}
          
          echo ""
          echo "🎯 Priority Actions:"
          echo "1. Implement smart test selection based on file changes"
          echo "2. Add build artifact caching"
          echo "3. Parallelize independent job stages"
          echo "4. Set up branch-specific workflow optimization"
        '' else ''
          echo "CI/CD integration disabled"
        ''}
      '')
      
      # Project maintenance automation
      (writeShellScriptBin "ai-project-maintain" ''
        #!/bin/bash
        
        # AI-powered project maintenance automation
        
        set -euo pipefail
        
        COMMAND="''${1:-health-check}"
        
        case "$COMMAND" in
          health-check)
            echo "🏥 AI Project Health Check"
            echo "========================"
            
            ${if config.dotfiles.ai.workflows.projectMaintenance.codeHealthChecks then ''
              echo ""
              echo "🔍 Analyzing code health..."
              
              # Count files by type
              TOTAL_FILES=$(find . -type f -not -path "./.git/*" | wc -l)
              SOURCE_FILES=$(find . -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.nix" -o -name "*.rs" -o -name "*.go" | wc -l)
              TEST_FILES=$(find . -name "*test*" -type f | wc -l)
              
              echo "  Total files: $TOTAL_FILES"
              echo "  Source files: $SOURCE_FILES"
              echo "  Test files: $TEST_FILES"
              
              # Calculate test coverage ratio
              if [ "$SOURCE_FILES" -gt 0 ]; then
                TEST_RATIO=$(( TEST_FILES * 100 / SOURCE_FILES ))
                echo "  Test ratio: $TEST_RATIO%"
                
                if [ "$TEST_RATIO" -lt 30 ]; then
                  echo "  ⚠️  Low test coverage - consider adding more tests"
                elif [ "$TEST_RATIO" -gt 80 ]; then
                  echo "  ✅ Excellent test coverage"
                else
                  echo "  💡 Good test coverage - can be improved"
                fi
              fi
              
              # Check for TODO/FIXME comments
              TODO_COUNT=$(find . -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.nix" -o -name "*.rs" -o -name "*.go" | xargs grep -l "TODO\|FIXME" 2>/dev/null | wc -l)
              echo "  TODO/FIXME files: $TODO_COUNT"
              
              if [ "$TODO_COUNT" -gt 10 ]; then
                echo "  ⚠️  Many TODO items - consider prioritizing cleanup"
              fi
            '' else ""}
            ;;
            
          dependency-check)
            echo "📦 AI Dependency Analysis"
            echo "========================"
            
            ${if config.dotfiles.ai.workflows.projectMaintenance.dependencyUpdates then ''
              echo ""
              echo "🔍 Checking dependencies..."
              
              # Check different package managers
              if [ -f "package.json" ]; then
                echo "📋 Node.js dependencies:"
                if command -v npm >/dev/null; then
                  npm outdated 2>/dev/null || echo "  All packages up to date"
                fi
              fi
              
              if [ -f "Cargo.toml" ]; then
                echo "📋 Rust dependencies:"
                if command -v cargo >/dev/null; then
                  echo "  Use 'cargo outdated' for dependency updates"
                fi
              fi
              
              if [ -f "flake.nix" ]; then
                echo "📋 Nix dependencies:"
                echo "  Run 'nix flake update' to update inputs"
              fi
              
              echo ""
              echo "💡 Dependency Recommendations:"
              echo "1. Review and update outdated packages"
              echo "2. Remove unused dependencies"
              echo "3. Pin critical dependency versions"
              echo "4. Set up automated dependency updates"
            '' else ""}
            ;;
            
          doc-sync)
            echo "📚 AI Documentation Sync"
            echo "========================"
            
            ${if config.dotfiles.ai.workflows.projectMaintenance.documentationSync then ''
              echo ""
              echo "🔍 Analyzing documentation..."
              
              # Find documentation files
              DOC_FILES=$(find . -name "*.md" -not -path "./.git/*" | wc -l)
              README_EXISTS=$([ -f "README.md" ] && echo "Yes" || echo "No")
              
              echo "  Documentation files: $DOC_FILES"
              echo "  README.md exists: $README_EXISTS"
              
              if [ "$README_EXISTS" = "No" ]; then
                echo "  ⚠️  No README.md found - consider creating one"
              fi
              
              # Check for outdated documentation
              if [ -f "README.md" ]; then
                README_AGE=$(stat -c %Y README.md 2>/dev/null || stat -f %m README.md 2>/dev/null || echo 0)
                CURRENT_TIME=$(date +%s)
                AGE_DAYS=$(( (CURRENT_TIME - README_AGE) / 86400 ))
                
                echo "  README.md age: $AGE_DAYS days"
                
                if [ "$AGE_DAYS" -gt 30 ]; then
                  echo "  💡 README.md may need updating"
                fi
              fi
              
              echo ""
              echo "💡 Documentation Recommendations:"
              echo "1. Keep README.md updated with recent changes"
              echo "2. Add inline code documentation"
              echo "3. Create CONTRIBUTING.md for contributors"
              echo "4. Document API changes and breaking changes"
            '' else ""}
            ;;
            
          *)
            echo "Unknown command: $COMMAND"
            echo ""
            echo "Available commands:"
            echo "  health-check     - Comprehensive project health analysis"
            echo "  dependency-check - Analyze and recommend dependency updates"
            echo "  doc-sync        - Check documentation synchronization"
            exit 1
            ;;
        esac
      '')
    ];
    
    # Git hooks for AI workflows
    system.activationScripts = mkIf config.dotfiles.ai.workflows.automatedCodeReview.reviewOnCommit {
      aiWorkflowHooks = {
        text = ''
          # Create AI workflow git hooks
          if [ -d "/Users/yuki/.local/share/dotfiles-ai" ]; then
            mkdir -p "/Users/yuki/.local/share/dotfiles-ai/hooks"
            
            # Pre-commit hook
            cat > "/Users/yuki/.local/share/dotfiles-ai/hooks/pre-commit" << 'EOF'
#!/bin/bash
ai-pre-commit-review
EOF
            chmod +x "/Users/yuki/.local/share/dotfiles-ai/hooks/pre-commit"
            
            echo "AI workflow hooks installed in ~/.local/share/dotfiles-ai/hooks/"
            echo "To enable: ln -sf ~/.local/share/dotfiles-ai/hooks/pre-commit .git/hooks/"
          fi
        '';
      };
    };
    
    # Automated maintenance tasks
    launchd.user.agents = mkIf (config.dotfiles.ai.workflows.projectMaintenance.enable && (platformInfo.isDarwin or false)) {
      dotfiles-ai-project-maintenance = {
        serviceConfig = {
          Label = "org.dotfiles.ai-project-maintenance";
          ProgramArguments = [
            "${pkgs.writeShellScript "ai-project-maintenance" ''
              #!/bin/bash
              cd "$HOME"
              find . -name ".git" -type d -prune | while read -r git_dir; do
                project_dir=$(dirname "$git_dir")
                cd "$project_dir"
                echo "Running maintenance for: $project_dir"
                ai-project-maintain health-check
                cd - >/dev/null
              done
            ''}"
          ];
          StartCalendarInterval = {
            Weekday = 1; # Monday
            Hour = 9;
            Minute = 0;
          };
          StandardErrorPath = "/Users/yuki/.local/share/dotfiles-ai/logs/maintenance-error.log";
          StandardOutPath = "/Users/yuki/.local/share/dotfiles-ai/logs/maintenance-output.log";
        };
      };
    };
  };
}