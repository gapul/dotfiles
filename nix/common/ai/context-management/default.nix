# AI Context Management System
# Intelligent project analysis and context awareness for better AI assistance
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.ai.contextManagement = {
    enable = mkEnableOption "AI context management system";
    
    projectIndexing = {
      enable = mkEnableOption "Automatic project indexing";
      
      indexInterval = mkOption {
        type = types.int;
        default = 3600; # 1 hour
        description = "Project indexing interval in seconds";
      };
      
      maxFileSize = mkOption {
        type = types.int;
        default = 1048576; # 1MB
        description = "Maximum file size to index in bytes";
      };
      
      excludePatterns = mkOption {
        type = types.listOf types.str;
        default = [ "node_modules" ".git" "target" "dist" "build" "__pycache__" ".nix-build" ];
        description = "Patterns to exclude from indexing";
      };
    };
    
    semanticAnalysis = {
      enable = mkEnableOption "Semantic code analysis";
      
      relationshipMapping = mkOption {
        type = types.bool;
        default = true;
        description = "Map relationships between code elements";
      };
      
      dependencyTracking = mkOption {
        type = types.bool;
        default = true;
        description = "Track internal and external dependencies";
      };
    };
    
    contextStorage = {
      compressionEnabled = mkOption {
        type = types.bool;
        default = true;
        description = "Enable context data compression";
      };
      
      retentionDays = mkOption {
        type = types.int;
        default = 30;
        description = "Context data retention period in days";
      };
    };
  };

  config = mkIf (config.dotfiles.ai.enable && config.dotfiles.ai.contextManagement.enable) {
    # Context management tools
    environment.systemPackages = with pkgs; [
      # Project indexer
      (writeShellScriptBin "ai-index-project" ''
        #!/bin/bash
        
        # Intelligent project indexing for AI context
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        FORCE_REINDEX="''${2:-false}"
        
        CONTEXT_DIR="$HOME/.local/share/dotfiles-ai/context"
        INDEX_DIR="$CONTEXT_DIR/index"
        
        mkdir -p "$INDEX_DIR"
        
        PROJECT_HASH=$(echo "$PROJECT_DIR" | sha256sum | cut -d' ' -f1)
        INDEX_FILE="$INDEX_DIR/$PROJECT_HASH.json"
        
        echo "🔍 Indexing project: $PROJECT_DIR"
        
        # Check if recent index exists
        if [ "$FORCE_REINDEX" != "true" ] && [ -f "$INDEX_FILE" ]; then
          LAST_MODIFIED=$(stat -c %Y "$INDEX_FILE" 2>/dev/null || stat -f %m "$INDEX_FILE" 2>/dev/null || echo 0)
          CURRENT_TIME=$(date +%s)
          AGE=$((CURRENT_TIME - LAST_MODIFIED))
          
          if [ "$AGE" -lt ${toString config.dotfiles.ai.contextManagement.projectIndexing.indexInterval} ]; then
            echo "ℹ️  Recent index found (''${AGE}s old), skipping. Use --force to reindex."
            exit 0
          fi
        fi
        
        START_TIME=$(date +%s%3N)
        
        echo "📊 Analyzing project structure..."
        
        # File discovery with exclusions
        EXCLUDE_ARGS=""
        ${concatMapStrings (pattern: ''
          EXCLUDE_ARGS="$EXCLUDE_ARGS -not -path '*/${pattern}/*'"
        '') config.dotfiles.ai.contextManagement.projectIndexing.excludePatterns}
        
        # Find all relevant files
        TEMP_FILE_LIST=$(mktemp)
        eval "find \"$PROJECT_DIR\" -type f $EXCLUDE_ARGS -size -${toString config.dotfiles.ai.contextManagement.projectIndexing.maxFileSize}c" > "$TEMP_FILE_LIST"
        
        TOTAL_FILES=$(wc -l < "$TEMP_FILE_LIST")
        echo "Found $TOTAL_FILES files to analyze"
        
        # Language detection and categorization
        declare -A LANG_STATS
        declare -A FILE_TYPES
        
        while IFS= read -r file; do
          if [ -f "$file" ]; then
            EXT=$(echo "$file" | sed 's/.*\.//')
            
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
              md) LANG="markdown" ;;
              json) LANG="json" ;;
              yaml|yml) LANG="yaml" ;;
              toml) LANG="toml" ;;
              *) LANG="other" ;;
            esac
            
            LANG_STATS["$LANG"]=$((''${LANG_STATS["$LANG"]:-0} + 1))
            FILE_TYPES["$EXT"]=$((''${FILE_TYPES["$EXT"]:-0} + 1))
          fi
        done < "$TEMP_FILE_LIST"
        
        # Project metadata analysis
        PROJECT_NAME=$(basename "$PROJECT_DIR")
        
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
        
        # Dependency analysis
        echo "🔗 Analyzing dependencies..."
        
        DEPENDENCIES=""
        case "$PROJECT_TYPE" in
          nodejs)
            if [ -f "$PROJECT_DIR/package.json" ]; then
              DEPENDENCIES=$(jq -r '.dependencies // {} | keys[]' "$PROJECT_DIR/package.json" 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
            fi
            ;;
          rust)
            if [ -f "$PROJECT_DIR/Cargo.toml" ]; then
              DEPENDENCIES=$(grep "^\[dependencies\]" -A 50 "$PROJECT_DIR/Cargo.toml" | grep "^[a-zA-Z]" | cut -d'=' -f1 | tr -d ' ' | head -20 | tr '\n' ',' | sed 's/,$//')
            fi
            ;;
          python)
            if [ -f "$PROJECT_DIR/requirements.txt" ]; then
              DEPENDENCIES=$(head -20 "$PROJECT_DIR/requirements.txt" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1 | tr '\n' ',' | sed 's/,$//')
            fi
            ;;
        esac
        
        # Code structure analysis
        echo "🏗️  Analyzing code structure..."
        
        FUNCTION_COUNT=0
        CLASS_COUNT=0
        MODULE_COUNT=0
        
        while IFS= read -r file; do
          if [ -f "$file" ]; then
            case "$(echo "$file" | sed 's/.*\.//')" in
              js|ts|jsx|tsx)
                FUNCTION_COUNT=$((FUNCTION_COUNT + $(grep -c "function\|const.*=.*=>\|class " "$file" 2>/dev/null || echo 0)))
                CLASS_COUNT=$((CLASS_COUNT + $(grep -c "class " "$file" 2>/dev/null || echo 0)))
                ;;
              py)
                FUNCTION_COUNT=$((FUNCTION_COUNT + $(grep -c "^def " "$file" 2>/dev/null || echo 0)))
                CLASS_COUNT=$((CLASS_COUNT + $(grep -c "^class " "$file" 2>/dev/null || echo 0)))
                ;;
              rs)
                FUNCTION_COUNT=$((FUNCTION_COUNT + $(grep -c "fn " "$file" 2>/dev/null || echo 0)))
                MODULE_COUNT=$((MODULE_COUNT + $(grep -c "mod " "$file" 2>/dev/null || echo 0)))
                ;;
            esac
          fi
        done < "$TEMP_FILE_LIST"
        
        # Generate comprehensive index
        {
          echo "{"
          echo "  \"metadata\": {"
          echo "    \"project_name\": \"$PROJECT_NAME\","
          echo "    \"project_path\": \"$PROJECT_DIR\","
          echo "    \"project_type\": \"$PROJECT_TYPE\","
          echo "    \"indexed_at\": \"$(date -Iseconds)\","
          echo "    \"total_files\": $TOTAL_FILES,"
          echo "    \"indexer_version\": \"1.0\""
          echo "  },"
          
          echo "  \"languages\": {"
          for lang in "''${!LANG_STATS[@]}"; do
            echo "    \"$lang\": ''${LANG_STATS[$lang]},"
          done | sed '$ s/,$//'
          echo "  },"
          
          echo "  \"structure\": {"
          echo "    \"functions\": $FUNCTION_COUNT,"
          echo "    \"classes\": $CLASS_COUNT,"
          echo "    \"modules\": $MODULE_COUNT"
          echo "  },"
          
          echo "  \"dependencies\": ["
          if [ -n "$DEPENDENCIES" ]; then
            echo "$DEPENDENCIES" | tr ',' '\n' | while read -r dep; do
              if [ -n "$dep" ]; then
                echo "    \"$dep\","
              fi
            done | sed '$ s/,$//'
          fi
          echo "  ],"
          
          echo "  \"file_types\": {"
          for ext in "''${!FILE_TYPES[@]}"; do
            echo "    \"$ext\": ''${FILE_TYPES[$ext]},"
          done | sed '$ s/,$//'
          echo "  },"
          
          echo "  \"ai_context\": {"
          echo "    \"complexity\": \"$([ $TOTAL_FILES -gt 100 ] && echo "high" || [ $TOTAL_FILES -gt 50 ] && echo "medium" || echo "low")\","
          echo "    \"primary_language\": \"$(for lang in "''${!LANG_STATS[@]}"; do echo "''${LANG_STATS[$lang]} $lang"; done | sort -nr | head -1 | cut -d' ' -f2)\","
          echo "    \"suggested_focus\": ["
          
          # Generate AI suggestions based on project structure
          SUGGESTIONS=""
          if [ "$FUNCTION_COUNT" -gt 50 ]; then
            SUGGESTIONS="$SUGGESTIONS\"code organization\","
          fi
          if [ "$CLASS_COUNT" -gt 20 ]; then
            SUGGESTIONS="$SUGGESTIONS\"object-oriented design\","
          fi
          if [ "$PROJECT_TYPE" != "unknown" ]; then
            SUGGESTIONS="$SUGGESTIONS\"$PROJECT_TYPE best practices\","
          fi
          if [ "$(echo \"''${!LANG_STATS[@]}\" | wc -w)" -gt 3 ]; then
            SUGGESTIONS="$SUGGESTIONS\"multi-language integration\","
          fi
          
          echo "$SUGGESTIONS" | sed 's/,$//'
          
          echo "    ]"
          echo "  }"
          echo "}"
        } > "$INDEX_FILE"
        
        END_TIME=$(date +%s%3N)
        DURATION=$((END_TIME - START_TIME))
        
        echo "✅ Project indexed successfully"
        echo "📁 Index file: $INDEX_FILE"
        echo "📊 Languages: $(echo "''${!LANG_STATS[@]}" | wc -w) detected"
        echo "🔧 Functions: $FUNCTION_COUNT, Classes: $CLASS_COUNT"
        echo "⏱️  Indexing completed in $DURATION ms"
        
        # Create symlink to latest for this project
        ln -sf "$INDEX_FILE" "$INDEX_DIR/$(basename "$PROJECT_DIR")-latest.json"
        
        rm "$TEMP_FILE_LIST"
        
        # Log performance
        ai-performance-tracker log "project-index" "$DURATION" "true"
      '')
      
      # Context query system
      (writeShellScriptBin "ai-query-context" ''
        #!/bin/bash
        
        # Query AI context for intelligent assistance
        
        set -euo pipefail
        
        QUERY_TYPE="''${1:-summary}"
        PROJECT_DIR="''${2:-$(pwd)}"
        
        CONTEXT_DIR="$HOME/.local/share/dotfiles-ai/context"
        INDEX_DIR="$CONTEXT_DIR/index"
        
        PROJECT_HASH=$(echo "$PROJECT_DIR" | sha256sum | cut -d' ' -f1)
        INDEX_FILE="$INDEX_DIR/$PROJECT_HASH.json"
        
        if [ ! -f "$INDEX_FILE" ]; then
          echo "❌ No index found for project: $PROJECT_DIR"
          echo "Run 'ai-index-project' first to create an index"
          exit 1
        fi
        
        case "$QUERY_TYPE" in
          summary)
            echo "📊 Project Context Summary"
            echo "========================="
            echo ""
            
            PROJECT_NAME=$(jq -r '.metadata.project_name' "$INDEX_FILE")
            PROJECT_TYPE=$(jq -r '.metadata.project_type' "$INDEX_FILE")
            TOTAL_FILES=$(jq -r '.metadata.total_files' "$INDEX_FILE")
            PRIMARY_LANG=$(jq -r '.ai_context.primary_language' "$INDEX_FILE")
            COMPLEXITY=$(jq -r '.ai_context.complexity' "$INDEX_FILE")
            
            echo "Project: $PROJECT_NAME"
            echo "Type: $PROJECT_TYPE"
            echo "Files: $TOTAL_FILES"
            echo "Primary Language: $PRIMARY_LANG"
            echo "Complexity: $COMPLEXITY"
            echo ""
            
            echo "📋 Language Distribution:"
            jq -r '.languages | to_entries[] | "  \(.key): \(.value) files"' "$INDEX_FILE"
            echo ""
            
            echo "🏗️  Code Structure:"
            FUNCTIONS=$(jq -r '.structure.functions' "$INDEX_FILE")
            CLASSES=$(jq -r '.structure.classes' "$INDEX_FILE")
            echo "  Functions: $FUNCTIONS"
            echo "  Classes: $CLASSES"
            echo ""
            
            echo "💡 AI Suggestions:"
            jq -r '.ai_context.suggested_focus[]' "$INDEX_FILE" | sed 's/^/  - /'
            ;;
            
          languages)
            echo "🌐 Language Analysis"
            echo "=================="
            echo ""
            
            jq -r '.languages | to_entries[] | "\(.key): \(.value) files (\(.value * 100 / ([.] | add))%)"' "$INDEX_FILE" --argjson total "$(jq '.metadata.total_files' "$INDEX_FILE")" | \
              awk -v total="$(jq '.metadata.total_files' "$INDEX_FILE")" '{
                split($0, parts, ": ");
                lang = parts[1];
                rest = parts[2];
                split(rest, counts, " ");
                count = counts[1];
                percent = int(count * 100 / total);
                printf "%-15s %3d files (%2d%%)\n", lang, count, percent;
              }' | sort -k3 -nr
            ;;
            
          dependencies)
            echo "🔗 Project Dependencies"
            echo "======================"
            echo ""
            
            DEPS=$(jq -r '.dependencies[]' "$INDEX_FILE" 2>/dev/null)
            if [ -n "$DEPS" ]; then
              echo "$DEPS" | nl -w3 -s'. '
            else
              echo "No dependencies detected or analyzed"
            fi
            ;;
            
          structure)
            echo "🏗️  Code Structure Analysis"
            echo "=========================="
            echo ""
            
            jq -r '"Functions: " + (.structure.functions | tostring)' "$INDEX_FILE"
            jq -r '"Classes: " + (.structure.classes | tostring)' "$INDEX_FILE"
            jq -r '"Modules: " + (.structure.modules | tostring)' "$INDEX_FILE"
            echo ""
            
            echo "📁 File Type Distribution:"
            jq -r '.file_types | to_entries[] | "  \(.key): \(.value) files"' "$INDEX_FILE" | sort -k2 -nr
            ;;
            
          ai-context)
            echo "🤖 AI Context Information"
            echo "========================"
            echo ""
            
            COMPLEXITY=$(jq -r '.ai_context.complexity' "$INDEX_FILE")
            PRIMARY_LANG=$(jq -r '.ai_context.primary_language' "$INDEX_FILE")
            
            echo "Complexity Level: $COMPLEXITY"
            echo "Primary Language: $PRIMARY_LANG"
            echo ""
            
            echo "Recommended AI Focus Areas:"
            jq -r '.ai_context.suggested_focus[]' "$INDEX_FILE" | sed 's/^/  • /'
            echo ""
            
            echo "Context Freshness:"
            INDEXED_AT=$(jq -r '.metadata.indexed_at' "$INDEX_FILE")
            echo "  Last indexed: $INDEXED_AT"
            
            CURRENT_TIME=$(date +%s)
            INDEX_TIME=$(date -d "$INDEXED_AT" +%s 2>/dev/null || echo "$CURRENT_TIME")
            AGE_HOURS=$(( (CURRENT_TIME - INDEX_TIME) / 3600 ))
            
            if [ "$AGE_HOURS" -gt 24 ]; then
              echo "  ⚠️  Index is $AGE_HOURS hours old - consider reindexing"
            else
              echo "  ✅ Index is current ($AGE_HOURS hours old)"
            fi
            ;;
            
          *)
            echo "Unknown query type: $QUERY_TYPE"
            echo ""
            echo "Available query types:"
            echo "  summary     - Project overview"
            echo "  languages   - Language distribution"
            echo "  dependencies - Project dependencies"
            echo "  structure   - Code structure analysis"
            echo "  ai-context  - AI-specific context information"
            exit 1
            ;;
        esac
      '')
      
      # Context maintenance
      (writeShellScriptBin "ai-maintain-context" ''
        #!/bin/bash
        
        # Maintain AI context storage
        
        set -euo pipefail
        
        CONTEXT_DIR="$HOME/.local/share/dotfiles-ai/context"
        INDEX_DIR="$CONTEXT_DIR/index"
        
        COMMAND="''${1:-clean}"
        
        case "$COMMAND" in
          clean)
            echo "🧹 Cleaning old context data..."
            
            RETENTION_DAYS=${toString config.dotfiles.ai.contextManagement.contextStorage.retentionDays}
            CUTOFF_TIME=$(($(date +%s) - (RETENTION_DAYS * 24 * 3600)))
            
            CLEANED=0
            
            if [ -d "$INDEX_DIR" ]; then
              for index_file in "$INDEX_DIR"/*.json; do
                if [ -f "$index_file" ] && [ ! -L "$index_file" ]; then
                  FILE_TIME=$(stat -c %Y "$index_file" 2>/dev/null || stat -f %m "$index_file" 2>/dev/null || echo 0)
                  
                  if [ "$FILE_TIME" -lt "$CUTOFF_TIME" ]; then
                    rm "$index_file"
                    CLEANED=$((CLEANED + 1))
                  fi
                fi
              done
            fi
            
            echo "Cleaned $CLEANED old index files (older than $RETENTION_DAYS days)"
            ;;
            
          status)
            echo "📊 Context Storage Status"
            echo "========================"
            echo ""
            
            if [ -d "$INDEX_DIR" ]; then
              TOTAL_INDEXES=$(find "$INDEX_DIR" -name "*.json" -not -type l | wc -l)
              TOTAL_SIZE=$(du -sh "$CONTEXT_DIR" 2>/dev/null | cut -f1)
              
              echo "Indexed projects: $TOTAL_INDEXES"
              echo "Total storage: $TOTAL_SIZE"
              echo ""
              
              echo "Recent indexes:"
              find "$INDEX_DIR" -name "*.json" -not -type l -printf "%T@ %p\n" 2>/dev/null | \
                sort -nr | head -5 | while read -r timestamp file; do
                PROJECT_NAME=$(jq -r '.metadata.project_name' "$file" 2>/dev/null || echo "unknown")
                DATE=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
                echo "  $PROJECT_NAME ($DATE)"
              done
            else
              echo "No context data found"
            fi
            ;;
            
          reindex-all)
            echo "🔄 Reindexing all known projects..."
            
            if [ -d "$INDEX_DIR" ]; then
              find "$INDEX_DIR" -name "*-latest.json" -type l | while read -r symlink; do
                TARGET=$(readlink "$symlink")
                if [ -f "$TARGET" ]; then
                  PROJECT_PATH=$(jq -r '.metadata.project_path' "$TARGET" 2>/dev/null)
                  if [ -d "$PROJECT_PATH" ]; then
                    echo "Reindexing: $PROJECT_PATH"
                    ai-index-project "$PROJECT_PATH" true
                  fi
                fi
              done
            fi
            ;;
            
          *)
            echo "Unknown command: $COMMAND"
            echo ""
            echo "Available commands:"
            echo "  clean       - Remove old context data"
            echo "  status      - Show context storage status"
            echo "  reindex-all - Reindex all known projects"
            exit 1
            ;;
        esac
      '')
    ];
    
    # Automated context maintenance
    launchd.user.agents = mkIf (config.dotfiles.ai.contextManagement.projectIndexing.enable && (platformInfo.isDarwin or false)) {
      dotfiles-ai-context-maintenance = {
        serviceConfig = {
          Label = "org.dotfiles.ai-context-maintenance";
          ProgramArguments = [
            "${pkgs.writeShellScript "ai-context-maintenance" ''
              #!/bin/bash
              ai-maintain-context clean
            ''}"
          ];
          StartCalendarInterval = {
            Hour = 2;
            Minute = 30;
          };
          StandardErrorPath = "/Users/yuki/.local/share/dotfiles-ai/logs/context-error.log";
          StandardOutPath = "/Users/yuki/.local/share/dotfiles-ai/logs/context-output.log";
        };
      };
    };
  };
}