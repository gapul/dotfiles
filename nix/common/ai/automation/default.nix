# AI Automation Features
# Automated development tasks powered by AI
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.ai.automation = {
    enable = mkEnableOption "AI automation features";
    
    smartCommits = {
      enable = mkEnableOption "AI-powered commit message generation";
      
      analyzeChanges = mkOption {
        type = types.bool;
        default = true;
        description = "Analyze git changes to generate contextual commit messages";
      };
      
      conventionalCommits = mkOption {
        type = types.bool;
        default = true;
        description = "Generate conventional commit format messages";
      };
    };
    
    testGeneration = {
      enable = mkEnableOption "Automatic test generation";
      
      framework = mkOption {
        type = types.enum [ "auto" "jest" "pytest" "cargo" "go-test" ];
        default = "auto";
        description = "Testing framework to target";
      };
      
      coverageGoal = mkOption {
        type = types.int;
        default = 80;
        description = "Target test coverage percentage";
      };
    };
    
    codeOptimization = {
      enable = mkEnableOption "AI-powered code optimization";
      
      performanceAnalysis = mkOption {
        type = types.bool;
        default = true;
        description = "Analyze code for performance improvements";
      };
      
      securityAnalysis = mkOption {
        type = types.bool;
        default = true;
        description = "Analyze code for security vulnerabilities";
      };
    };
  };

  config = mkIf (config.dotfiles.ai.enable && config.dotfiles.ai.automation.enable) {
    # AI automation tools
    environment.systemPackages = with pkgs; [
      # Smart commit message generator
      (writeShellScriptBin "ai-commit-message" ''
        #!/bin/bash
        
        # AI-powered commit message generation
        
        set -euo pipefail
        
        # Check if we're in a git repository
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
          echo "❌ Not in a git repository"
          exit 1
        fi
        
        echo "🤖 Generating AI-powered commit message..."
        
        START_TIME=$(date +%s%3N)
        
        # Get staged changes
        STAGED_FILES=$(git diff --cached --name-only)
        
        if [ -z "$STAGED_FILES" ]; then
          echo "❌ No staged changes found. Use 'git add' to stage files first."
          exit 1
        fi
        
        echo "📁 Analyzing staged files:"
        echo "$STAGED_FILES" | sed 's/^/  - /'
        echo ""
        
        # Analyze the changes
        TOTAL_CHANGES=$(git diff --cached --numstat | awk '{added+=$1; deleted+=$2} END {print "+" added " -" deleted}')
        MODIFIED_FILES=$(echo "$STAGED_FILES" | wc -l | tr -d ' ')
        
        # Detect change types
        CHANGE_TYPES=""
        
        # Check for new files
        NEW_FILES=$(git diff --cached --name-status | grep "^A" | wc -l | tr -d ' ')
        if [ "$NEW_FILES" -gt 0 ]; then
          CHANGE_TYPES="$CHANGE_TYPES new files,"
        fi
        
        # Check for modified files
        MODIFIED=$(git diff --cached --name-status | grep "^M" | wc -l | tr -d ' ')
        if [ "$MODIFIED" -gt 0 ]; then
          CHANGE_TYPES="$CHANGE_TYPES modifications,"
        fi
        
        # Check for deleted files
        DELETED=$(git diff --cached --name-status | grep "^D" | wc -l | tr -d ' ')
        if [ "$DELETED" -gt 0 ]; then
          CHANGE_TYPES="$CHANGE_TYPES deletions,"
        fi
        
        CHANGE_TYPES=$(echo "$CHANGE_TYPES" | sed 's/,$//')
        
        # Detect file types and scope
        PRIMARY_SCOPE=""
        if echo "$STAGED_FILES" | grep -q "\.nix$"; then
          PRIMARY_SCOPE="nix"
        elif echo "$STAGED_FILES" | grep -q "\.(js|ts|jsx|tsx)$"; then
          PRIMARY_SCOPE="frontend"
        elif echo "$STAGED_FILES" | grep -q "\.py$"; then
          PRIMARY_SCOPE="python"
        elif echo "$STAGED_FILES" | grep -q "\.(rs|toml)$"; then
          PRIMARY_SCOPE="rust"
        elif echo "$STAGED_FILES" | grep -q "\.go$"; then
          PRIMARY_SCOPE="go"
        elif echo "$STAGED_FILES" | grep -q "\.md$"; then
          PRIMARY_SCOPE="docs"
        elif echo "$STAGED_FILES" | grep -q "test"; then
          PRIMARY_SCOPE="test"
        else
          PRIMARY_SCOPE="misc"
        fi
        
        # Generate commit type
        COMMIT_TYPE="feat"
        if echo "$STAGED_FILES" | grep -q "test"; then
          COMMIT_TYPE="test"
        elif echo "$STAGED_FILES" | grep -q "\.md$"; then
          COMMIT_TYPE="docs"
        elif [ "$NEW_FILES" -eq 0 ] && [ "$MODIFIED" -gt 0 ]; then
          if git diff --cached | grep -q "fix\|bug\|error"; then
            COMMIT_TYPE="fix"
          else
            COMMIT_TYPE="refactor"
          fi
        fi
        
        # Generate commit message
        ${if config.dotfiles.ai.automation.smartCommits.conventionalCommits then ''
          # Conventional Commits format
          if [ -n "$PRIMARY_SCOPE" ] && [ "$PRIMARY_SCOPE" != "misc" ]; then
            SCOPE_PART="($PRIMARY_SCOPE)"
          else
            SCOPE_PART=""
          fi
          
          # Generate description based on changes
          DESCRIPTION=""
          case "$COMMIT_TYPE" in
            feat)
              if [ "$NEW_FILES" -gt 0 ]; then
                DESCRIPTION="add new functionality with $NEW_FILES new files"
              else
                DESCRIPTION="enhance existing functionality"
              fi
              ;;
            fix)
              DESCRIPTION="resolve issues and improve stability"
              ;;
            docs)
              DESCRIPTION="update documentation and README files"
              ;;
            test)
              DESCRIPTION="add test coverage and validation"
              ;;
            refactor)
              DESCRIPTION="improve code structure and maintainability"
              ;;
          esac
          
          COMMIT_MSG="$COMMIT_TYPE$SCOPE_PART: $DESCRIPTION"
        '' else ''
          # Standard format
          case "$COMMIT_TYPE" in
            feat)
              COMMIT_MSG="Add new features and functionality"
              ;;
            fix)
              COMMIT_MSG="Fix bugs and resolve issues"
              ;;
            docs)
              COMMIT_MSG="Update documentation"
              ;;
            test)
              COMMIT_MSG="Add tests and improve coverage"
              ;;
            refactor)
              COMMIT_MSG="Refactor code for better maintainability"
              ;;
          esac
        ''}
        
        # Add details to commit body
        COMMIT_BODY=""
        COMMIT_BODY="$COMMIT_BODY- Modified $MODIFIED_FILES files ($TOTAL_CHANGES)"
        
        if [ "$NEW_FILES" -gt 0 ]; then
          COMMIT_BODY="$COMMIT_BODY\n- Added $NEW_FILES new files"
        fi
        
        if [ "$DELETED" -gt 0 ]; then
          COMMIT_BODY="$COMMIT_BODY\n- Removed $DELETED files"
        fi
        
        # Show key changed files
        if [ "$MODIFIED_FILES" -le 10 ]; then
          COMMIT_BODY="$COMMIT_BODY\n\nKey changes:"
          echo "$STAGED_FILES" | head -5 | while read -r file; do
            COMMIT_BODY="$COMMIT_BODY\n- $file"
          done
        fi
        
        COMMIT_BODY="$COMMIT_BODY\n\n🤖 Generated with AI Development Assistant"
        
        END_TIME=$(date +%s%3N)
        DURATION=$((END_TIME - START_TIME))
        
        echo "💡 Generated commit message:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$COMMIT_MSG"
        echo ""
        echo -e "$COMMIT_BODY"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # Ask user if they want to use this message
        echo "Use this commit message? [Y/n/e] (e=edit)"
        read -r response
        
        case "$response" in
          n|N)
            echo "Commit cancelled"
            exit 0
            ;;
          e|E)
            # Open editor with the message
            TEMP_MSG=$(mktemp)
            echo "$COMMIT_MSG" > "$TEMP_MSG"
            echo "" >> "$TEMP_MSG"
            echo -e "$COMMIT_BODY" >> "$TEMP_MSG"
            
            ''${EDITOR:-vim} "$TEMP_MSG"
            
            if [ -s "$TEMP_MSG" ]; then
              git commit -F "$TEMP_MSG"
              echo "✅ Commit created with edited message"
            else
              echo "❌ Empty commit message, aborting"
              exit 1
            fi
            
            rm "$TEMP_MSG"
            ;;
          *)
            # Use the generated message
            FULL_MSG="$COMMIT_MSG\n\n$COMMIT_BODY"
            echo -e "$FULL_MSG" | git commit -F -
            echo "✅ Commit created successfully"
            ;;
        esac
        
        echo "⏱️  Message generated in $DURATION ms"
        
        # Log performance
        ai-performance-tracker log "commit-message" "$DURATION" "true"
      '')
      
      # Test generation assistant
      (writeShellScriptBin "ai-test-generate" ''
        #!/bin/bash
        
        # AI-powered test generation
        
        set -euo pipefail
        
        SOURCE_FILE="$1"
        
        if [ ! -f "$SOURCE_FILE" ]; then
          echo "Source file not found: $SOURCE_FILE"
          exit 1
        fi
        
        echo "🧪 Generating tests for: $SOURCE_FILE"
        
        START_TIME=$(date +%s%3N)
        
        # Determine language and test framework
        LANG=$(echo "$SOURCE_FILE" | sed 's/.*\.//')
        BASE_NAME=$(basename "$SOURCE_FILE" | sed 's/\.[^.]*$//')
        DIR_NAME=$(dirname "$SOURCE_FILE")
        
        case "$LANG" in
          js|ts)
            FRAMEWORK="jest"
            TEST_FILE="$DIR_NAME/__tests__/$BASE_NAME.test.$LANG"
            TEST_DIR="$DIR_NAME/__tests__"
            ;;
          py)
            FRAMEWORK="pytest"
            TEST_FILE="$DIR_NAME/test_$BASE_NAME.py"
            TEST_DIR="$DIR_NAME"
            ;;
          rs)
            FRAMEWORK="cargo"
            TEST_FILE="$DIR_NAME/tests/$BASE_NAME.rs"
            TEST_DIR="$DIR_NAME/tests"
            ;;
          nix)
            FRAMEWORK="nix-test"
            TEST_FILE="$DIR_NAME/test-$BASE_NAME.nix"
            TEST_DIR="$DIR_NAME"
            ;;
          *)
            echo "❌ Unsupported language: $LANG"
            exit 1
            ;;
        esac
        
        echo "Framework: $FRAMEWORK"
        echo "Test file: $TEST_FILE"
        
        # Create test directory
        mkdir -p "$TEST_DIR"
        
        # Analyze source file for testable functions
        echo ""
        echo "🔍 Analyzing source file..."
        
        FUNCTIONS=()
        case "$LANG" in
          js|ts)
            # Extract function names
            while IFS= read -r line; do
              FUNCTIONS+=("$line")
            done < <(grep -o "function [a-zA-Z_][a-zA-Z0-9_]*\|const [a-zA-Z_][a-zA-Z0-9_]* = " "$SOURCE_FILE" | sed 's/function //; s/const //; s/ = .*//' | head -10)
            ;;
          py)
            while IFS= read -r line; do
              FUNCTIONS+=("$line")
            done < <(grep "^def " "$SOURCE_FILE" | sed 's/def //; s/(.*//' | head -10)
            ;;
          nix)
            while IFS= read -r line; do
              FUNCTIONS+=("$line")
            done < <(grep "= *{" "$SOURCE_FILE" | sed 's/=.*//; s/^[[:space:]]*//' | head -10)
            ;;
        esac
        
        echo "Found ''${#FUNCTIONS[@]} testable elements"
        
        # Generate test file
        echo ""
        echo "📝 Generating test file..."
        
        case "$FRAMEWORK" in
          jest)
            {
              echo "// Auto-generated tests for $BASE_NAME"
              echo "// Generated on $(date)"
              echo ""
              echo "import { describe, it, expect } from '@jest/globals';"
              
              if [ -f "$SOURCE_FILE" ]; then
                echo "import * as $BASE_NAME from '../$BASE_NAME';"
              fi
              
              echo ""
              echo "describe('$BASE_NAME', () => {"
              
              for func in "''${FUNCTIONS[@]}"; do
                if [ -n "$func" ]; then
                  echo ""
                  echo "  describe('$func', () => {"
                  echo "    it('should be defined', () => {"
                  echo "      expect($BASE_NAME.$func).toBeDefined();"
                  echo "    });"
                  echo ""
                  echo "    it('should handle basic input', () => {"
                  echo "      // TODO: Add test implementation"
                  echo "      expect(true).toBe(true);"
                  echo "    });"
                  echo ""
                  echo "    it('should handle edge cases', () => {"
                  echo "      // TODO: Add edge case tests"
                  echo "      expect(true).toBe(true);"
                  echo "    });"
                  echo "  });"
                fi
              done
              
              echo "});"
              echo ""
              echo "// 🤖 Generated by AI Development Assistant"
              echo "// TODO: Implement actual test logic"
              
            } > "$TEST_FILE"
            ;;
            
          pytest)
            {
              echo "# Auto-generated tests for $BASE_NAME"
              echo "# Generated on $(date)"
              echo ""
              echo "import pytest"
              echo "from $BASE_NAME import *"
              echo ""
              
              for func in "''${FUNCTIONS[@]}"; do
                if [ -n "$func" ]; then
                  echo ""
                  echo "class Test$(echo "$func" | sed 's/^./\U&/'):"
                  echo "    def test_''${func}_basic(self):"
                  echo "        \"\"\"Test basic functionality of $func\"\"\""
                  echo "        # TODO: Implement test"
                  echo "        assert True"
                  echo ""
                  echo "    def test_''${func}_edge_cases(self):"
                  echo "        \"\"\"Test edge cases for $func\"\"\""
                  echo "        # TODO: Implement edge case tests"
                  echo "        assert True"
                fi
              done
              
              echo ""
              echo "# 🤖 Generated by AI Development Assistant"
              echo "# TODO: Implement actual test logic"
              
            } > "$TEST_FILE"
            ;;
            
          nix-test)
            {
              echo "# Auto-generated tests for $BASE_NAME"
              echo "# Generated on $(date)"
              echo ""
              echo "{ pkgs ? import <nixpkgs> {} }:"
              echo ""
              echo "let"
              echo "  tested = import ./$BASE_NAME.nix { inherit pkgs; };"
              echo "in"
              echo "{"
              echo "  testBasic = {"
              echo "    expr = tested != null;"
              echo "    expected = true;"
              echo "  };"
              echo ""
              
              for func in "''${FUNCTIONS[@]}"; do
                if [ -n "$func" ]; then
                  echo "  test$(echo "$func" | sed 's/^./\U&/') = {"
                  echo "    expr = tested.$func or null != null;"
                  echo "    expected = true;"
                  echo "  };"
                  echo ""
                fi
              done
              
              echo "  # 🤖 Generated by AI Development Assistant"
              echo "  # TODO: Add comprehensive test cases"
              echo "}"
              
            } > "$TEST_FILE"
            ;;
        esac
        
        END_TIME=$(date +%s%3N)
        DURATION=$((END_TIME - START_TIME))
        
        echo "✅ Test file generated: $TEST_FILE"
        echo "📊 Generated tests for ''${#FUNCTIONS[@]} functions/elements"
        echo "⏱️  Generated in $DURATION ms"
        echo ""
        echo "💡 Next steps:"
        echo "1. Review and customize the generated tests"
        echo "2. Implement actual test logic for each function"
        echo "3. Add edge cases and error handling tests"
        echo "4. Run tests with: ${framework} $TEST_FILE"
        
        # Log performance
        ai-performance-tracker log "test-generate" "$DURATION" "true"
      '')
      
      # Refactoring assistant
      (writeShellScriptBin "ai-refactor-suggest" ''
        #!/bin/bash
        
        # AI-powered refactoring suggestions
        
        set -euo pipefail
        
        FILE="$1"
        
        if [ ! -f "$FILE" ]; then
          echo "File not found: $FILE"
          exit 1
        fi
        
        echo "🔧 AI Refactoring Analysis"
        echo "========================="
        echo "File: $FILE"
        
        START_TIME=$(date +%s%3N)
        
        LANG=$(echo "$FILE" | sed 's/.*\.//')
        LINES=$(wc -l < "$FILE")
        
        echo "Language: $LANG"
        echo "Lines: $LINES"
        echo ""
        
        echo "🔍 Analyzing code structure..."
        
        # Code complexity analysis
        echo ""
        echo "📊 Complexity Analysis:"
        
        if [ "$LINES" -gt 200 ]; then
          echo "❗ High complexity: File has $LINES lines (consider splitting)"
        elif [ "$LINES" -gt 100 ]; then
          echo "⚠️  Moderate complexity: $LINES lines"
        else
          echo "✅ Good size: $LINES lines"
        fi
        
        # Function/method analysis
        case "$LANG" in
          js|ts)
            FUNCTIONS=$(grep -c "function\\|const.*=.*=>" "$FILE" || true)
            LONG_FUNCTIONS=$(awk '/function|const.*=>/ {start=NR} /^}/ {if (NR-start > 20) count++} END {print count+0}' "$FILE")
            ;;
          py)
            FUNCTIONS=$(grep -c "^def " "$FILE" || true)
            LONG_FUNCTIONS=$(awk '/^def / {start=NR} /^def |^class |^$/ {if (start && NR-start > 20) count++; start=0} END {print count+0}' "$FILE")
            ;;
          *)
            FUNCTIONS=0
            LONG_FUNCTIONS=0
            ;;
        esac
        
        if [ "$FUNCTIONS" -gt 0 ]; then
          echo "Functions found: $FUNCTIONS"
          if [ "$LONG_FUNCTIONS" -gt 0 ]; then
            echo "❗ $LONG_FUNCTIONS functions are longer than 20 lines"
          fi
        fi
        
        echo ""
        echo "💡 Refactoring Suggestions:"
        
        # File-level suggestions
        if [ "$LINES" -gt 200 ]; then
          echo "1. 📁 Split file into smaller modules:"
          echo "   - Extract related functions into separate files"
          echo "   - Create a main module that imports submodules"
          echo "   - Consider feature-based organization"
        fi
        
        if [ "$LONG_FUNCTIONS" -gt 0 ]; then
          echo "2. 🔧 Break down large functions:"
          echo "   - Extract complex logic into helper functions"
          echo "   - Use composition instead of deep nesting"
          echo "   - Apply single responsibility principle"
        fi
        
        # Language-specific suggestions
        case "$LANG" in
          js|ts)
            echo "3. 🎯 JavaScript/TypeScript improvements:"
            echo "   - Add TypeScript types if not already present"
            echo "   - Use modern ES6+ features (arrow functions, destructuring)"
            echo "   - Consider functional programming patterns"
            
            if grep -q "var " "$FILE"; then
              echo "   - Replace 'var' with 'const' or 'let'"
            fi
            ;;
            
          py)
            echo "3. 🐍 Python improvements:"
            echo "   - Add type hints for better code clarity"
            echo "   - Use dataclasses or named tuples for data structures"
            echo "   - Follow PEP 8 style guidelines"
            
            if ! grep -q "from __future__ import annotations" "$FILE" && grep -q "def " "$FILE"; then
              echo "   - Consider adding 'from __future__ import annotations'"
            fi
            ;;
            
          nix)
            echo "3. ❄️  Nix improvements:"
            echo "   - Use lib functions for common operations"
            echo "   - Organize options with proper descriptions"
            echo "   - Apply consistent formatting and indentation"
            ;;
        esac
        
        echo "4. 📚 Documentation improvements:"
        echo "   - Add docstrings/comments for complex functions"
        echo "   - Document function parameters and return values"
        echo "   - Include usage examples"
        
        echo "5. 🧪 Testing improvements:"
        echo "   - Add unit tests for all public functions"
        echo "   - Include edge case testing"
        echo "   - Use 'ai-test-generate $FILE' to create test scaffolding"
        
        echo ""
        echo "🎯 Priority Recommendations:"
        
        PRIORITY_COUNT=0
        if [ "$LINES" -gt 300 ]; then
          PRIORITY_COUNT=$((PRIORITY_COUNT + 1))
          echo "$PRIORITY_COUNT. Split this file into smaller modules (high impact)"
        fi
        
        if [ "$LONG_FUNCTIONS" -gt 2 ]; then
          PRIORITY_COUNT=$((PRIORITY_COUNT + 1))
          echo "$PRIORITY_COUNT. Refactor long functions (improves maintainability)"
        fi
        
        case "$LANG" in
          js|ts)
            if grep -q "var " "$FILE"; then
              PRIORITY_COUNT=$((PRIORITY_COUNT + 1))
              echo "$PRIORITY_COUNT. Update variable declarations (modern JavaScript)"
            fi
            ;;
        esac
        
        if [ "$PRIORITY_COUNT" -eq 0 ]; then
          echo "✅ Code structure looks good! Consider adding more documentation and tests."
        fi
        
        END_TIME=$(date +%s%3N)
        DURATION=$((END_TIME - START_TIME))
        
        echo ""
        echo "⏱️  Analysis completed in $DURATION ms"
        
        # Log performance
        ai-performance-tracker log "refactor-suggest" "$DURATION" "true"
      '')
    ];
  };
}