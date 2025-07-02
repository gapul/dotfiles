# AI Code Analysis and Optimization System
# Advanced AI-powered code analysis, optimization suggestions, and automated improvements
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.ai.analysis = {
    enable = mkEnableOption "AI code analysis and optimization system";
    
    staticAnalysis = {
      enable = mkEnableOption "Advanced static code analysis";
      
      securityAnalysis = mkOption {
        type = types.bool;
        default = true;
        description = "Enable security vulnerability analysis";
      };
      
      performanceAnalysis = mkOption {
        type = types.bool;
        default = true;
        description = "Enable performance bottleneck detection";
      };
      
      complexityAnalysis = mkOption {
        type = types.bool;
        default = true;
        description = "Enable code complexity analysis";
      };
      
      dependencyAnalysis = mkOption {
        type = types.bool;
        default = true;
        description = "Enable dependency vulnerability scanning";
      };
    };
    
    codeOptimization = {
      enable = mkEnableOption "AI-powered code optimization";
      
      autoRefactoring = mkOption {
        type = types.bool;
        default = false;
        description = "Enable automatic code refactoring suggestions";
      };
      
      performanceOptimization = mkOption {
        type = types.bool;
        default = true;
        description = "Enable performance optimization suggestions";
      };
      
      memoryOptimization = mkOption {
        type = types.bool;
        default = true;
        description = "Enable memory usage optimization";
      };
      
      algorithmOptimization = mkOption {
        type = types.bool;
        default = false;
        description = "Enable algorithm efficiency suggestions";
      };
    };
    
    qualityMetrics = {
      enable = mkEnableOption "Code quality metrics and scoring";
      
      maintainabilityScore = mkOption {
        type = types.bool;
        default = true;
        description = "Calculate maintainability scores";
      };
      
      technicalDebtTracking = mkOption {
        type = types.bool;
        default = true;
        description = "Track and quantify technical debt";
      };
      
      codeHealthDashboard = mkOption {
        type = types.bool;
        default = false;
        description = "Generate code health dashboard";
      };
    };
    
    continuousAnalysis = {
      enable = mkEnableOption "Continuous code analysis";
      
      analysisInterval = mkOption {
        type = types.int;
        default = 3600; # 1 hour
        description = "Analysis interval in seconds";
      };
      
      alertThresholds = {
        securityIssues = mkOption {
          type = types.int;
          default = 1;
          description = "Alert threshold for security issues";
        };
        
        performanceIssues = mkOption {
          type = types.int;
          default = 5;
          description = "Alert threshold for performance issues";
        };
        
        complexityScore = mkOption {
          type = types.int;
          default = 80;
          description = "Alert threshold for complexity score";
        };
      };
    };
  };

  config = mkIf (config.dotfiles.ai.enable && config.dotfiles.ai.analysis.enable) {
    # AI analysis tools
    environment.systemPackages = with pkgs; [
      # Comprehensive code analyzer
      (writeShellScriptBin "ai-analyze-code" ''
        #!/bin/bash
        
        # AI-powered comprehensive code analysis
        
        set -euo pipefail
        
        FILE_OR_DIR="''${1:-$(pwd)}"
        ANALYSIS_TYPE="''${2:-comprehensive}"
        
        if [ ! -e "$FILE_OR_DIR" ]; then
          echo "❌ File or directory not found: $FILE_OR_DIR"
          exit 1
        fi
        
        echo "🔍 AI Code Analysis"
        echo "=================="
        echo "Target: $FILE_OR_DIR"
        echo "Type: $ANALYSIS_TYPE"
        echo ""
        
        START_TIME=$(date +%s%3N)
        
        ANALYSIS_DIR="$HOME/.local/share/dotfiles-ai/analysis"
        mkdir -p "$ANALYSIS_DIR"
        
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        REPORT_FILE="$ANALYSIS_DIR/analysis-$TIMESTAMP.json"
        
        echo "📊 Running analysis..."
        
        # Initialize report structure
        {
          echo "{"
          echo "  \"metadata\": {"
          echo "    \"timestamp\": \"$(date -Iseconds)\","
          echo "    \"target\": \"$FILE_OR_DIR\","
          echo "    \"analysis_type\": \"$ANALYSIS_TYPE\","
          echo "    \"analyzer_version\": \"1.0\""
          echo "  },"
        } > "$REPORT_FILE"
        
        # Security Analysis
        ${if config.dotfiles.ai.analysis.staticAnalysis.securityAnalysis then ''
          echo "🔒 Security Analysis..."
          
          SECURITY_ISSUES=0
          SECURITY_DETAILS=""
          
          if [ -d "$FILE_OR_DIR" ]; then
            # Directory analysis
            # Check for hardcoded secrets
            SECRET_PATTERNS="password|api[_-]?key|secret|token|credential"
            SECRET_FILES=$(find "$FILE_OR_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \) -exec grep -l -i "$SECRET_PATTERNS" {} \; 2>/dev/null | head -10)
            
            if [ -n "$SECRET_FILES" ]; then
              SECURITY_ISSUES=$((SECURITY_ISSUES + $(echo "$SECRET_FILES" | wc -l)))
              SECURITY_DETAILS="$SECURITY_DETAILS\"potential_secrets\": $(echo "$SECRET_FILES" | wc -l),"
            fi
            
            # Check for SQL injection patterns
            SQL_PATTERNS="SELECT.*\\+|INSERT.*\\+|UPDATE.*\\+|DELETE.*\\+"
            SQL_FILES=$(find "$FILE_OR_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" \) -exec grep -l "$SQL_PATTERNS" {} \; 2>/dev/null | head -5)
            
            if [ -n "$SQL_FILES" ]; then
              SECURITY_ISSUES=$((SECURITY_ISSUES + $(echo "$SQL_FILES" | wc -l)))
              SECURITY_DETAILS="$SECURITY_DETAILS\"sql_injection_risk\": $(echo "$SQL_FILES" | wc -l),"
            fi
            
          else
            # Single file analysis
            if grep -qi "password\|api[_-]\?key\|secret\|token" "$FILE_OR_DIR" 2>/dev/null; then
              SECURITY_ISSUES=$((SECURITY_ISSUES + 1))
              SECURITY_DETAILS="$SECURITY_DETAILS\"potential_secrets\": 1,"
            fi
          fi
          
          {
            echo "  \"security\": {"
            echo "    \"issues_found\": $SECURITY_ISSUES,"
            echo "    \"severity\": \"$([ $SECURITY_ISSUES -gt 5 ] && echo "high" || [ $SECURITY_ISSUES -gt 2 ] && echo "medium" || echo "low")\","
            echo "    $SECURITY_DETAILS"
            echo "    \"analyzed\": true"
            echo "  },"
          } >> "$REPORT_FILE"
        '' else ''
          echo "  \"security\": { \"analyzed\": false }," >> "$REPORT_FILE"
        ''}
        
        # Performance Analysis
        ${if config.dotfiles.ai.analysis.staticAnalysis.performanceAnalysis then ''
          echo "⚡ Performance Analysis..."
          
          PERFORMANCE_ISSUES=0
          PERFORMANCE_DETAILS=""
          
          if [ -d "$FILE_OR_DIR" ]; then
            # Look for performance anti-patterns
            # Inefficient loops
            LOOP_FILES=$(find "$FILE_OR_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" \) -exec grep -l "for.*for\|while.*while" {} \; 2>/dev/null | head -5)
            if [ -n "$LOOP_FILES" ]; then
              PERFORMANCE_ISSUES=$((PERFORMANCE_ISSUES + $(echo "$LOOP_FILES" | wc -l)))
              PERFORMANCE_DETAILS="$PERFORMANCE_DETAILS\"nested_loops\": $(echo "$LOOP_FILES" | wc -l),"
            fi
            
            # Large file operations
            LARGE_FILES=$(find "$FILE_OR_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" \) -exec wc -l {} \; 2>/dev/null | awk '$1 > 500 {print $2}' | wc -l)
            if [ "$LARGE_FILES" -gt 0 ]; then
              PERFORMANCE_ISSUES=$((PERFORMANCE_ISSUES + LARGE_FILES))
              PERFORMANCE_DETAILS="$PERFORMANCE_DETAILS\"large_files\": $LARGE_FILES,"
            fi
            
          else
            # Single file analysis
            LINES=$(wc -l < "$FILE_OR_DIR" 2>/dev/null || echo 0)
            if [ "$LINES" -gt 500 ]; then
              PERFORMANCE_ISSUES=$((PERFORMANCE_ISSUES + 1))
              PERFORMANCE_DETAILS="$PERFORMANCE_DETAILS\"large_file\": true,"
            fi
          fi
          
          {
            echo "  \"performance\": {"
            echo "    \"issues_found\": $PERFORMANCE_ISSUES,"
            echo "    \"optimization_potential\": \"$([ $PERFORMANCE_ISSUES -gt 10 ] && echo "high" || [ $PERFORMANCE_ISSUES -gt 5 ] && echo "medium" || echo "low")\","
            echo "    $PERFORMANCE_DETAILS"
            echo "    \"analyzed\": true"
            echo "  },"
          } >> "$REPORT_FILE"
        '' else ''
          echo "  \"performance\": { \"analyzed\": false }," >> "$REPORT_FILE"
        ''}
        
        # Complexity Analysis
        ${if config.dotfiles.ai.analysis.staticAnalysis.complexityAnalysis then ''
          echo "📈 Complexity Analysis..."
          
          COMPLEXITY_SCORE=0
          TOTAL_FILES=0
          
          if [ -d "$FILE_OR_DIR" ]; then
            # Calculate cyclomatic complexity approximation
            while IFS= read -r file; do
              if [ -f "$file" ]; then
                TOTAL_FILES=$((TOTAL_FILES + 1))
                
                # Count decision points (if, while, for, case, etc.)
                DECISIONS=$(grep -c "if\|while\|for\|case\|catch\|except" "$file" 2>/dev/null || echo 0)
                LINES=$(wc -l < "$file" 2>/dev/null || echo 0)
                
                # Simple complexity calculation
                FILE_COMPLEXITY=$(( DECISIONS + (LINES / 50) ))
                COMPLEXITY_SCORE=$((COMPLEXITY_SCORE + FILE_COMPLEXITY))
              fi
            done < <(find "$FILE_OR_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \))
            
            if [ "$TOTAL_FILES" -gt 0 ]; then
              AVERAGE_COMPLEXITY=$((COMPLEXITY_SCORE / TOTAL_FILES))
            else
              AVERAGE_COMPLEXITY=0
            fi
          else
            # Single file
            TOTAL_FILES=1
            DECISIONS=$(grep -c "if\|while\|for\|case\|catch\|except" "$FILE_OR_DIR" 2>/dev/null || echo 0)
            LINES=$(wc -l < "$FILE_OR_DIR" 2>/dev/null || echo 0)
            AVERAGE_COMPLEXITY=$(( DECISIONS + (LINES / 50) ))
          fi
          
          {
            echo "  \"complexity\": {"
            echo "    \"average_score\": $AVERAGE_COMPLEXITY,"
            echo "    \"total_files\": $TOTAL_FILES,"
            echo "    \"rating\": \"$([ $AVERAGE_COMPLEXITY -gt 20 ] && echo "high" || [ $AVERAGE_COMPLEXITY -gt 10 ] && echo "medium" || echo "low")\","
            echo "    \"analyzed\": true"
            echo "  },"
          } >> "$REPORT_FILE"
        '' else ''
          echo "  \"complexity\": { \"analyzed\": false }," >> "$REPORT_FILE"
        ''}
        
        # Quality Metrics
        ${if config.dotfiles.ai.analysis.qualityMetrics.enable then ''
          echo "📊 Quality Metrics..."
          
          # Calculate maintainability index (simplified)
          QUALITY_SCORE=100
          
          # Reduce score based on issues found
          SECURITY_PENALTY=$((SECURITY_ISSUES * 5))
          PERFORMANCE_PENALTY=$((PERFORMANCE_ISSUES * 3))
          COMPLEXITY_PENALTY=$((AVERAGE_COMPLEXITY > 15 ? (AVERAGE_COMPLEXITY - 15) * 2 : 0))
          
          QUALITY_SCORE=$((QUALITY_SCORE - SECURITY_PENALTY - PERFORMANCE_PENALTY - COMPLEXITY_PENALTY))
          
          # Ensure minimum score
          [ "$QUALITY_SCORE" -lt 0 ] && QUALITY_SCORE=0
          
          TECHNICAL_DEBT=$((SECURITY_ISSUES + PERFORMANCE_ISSUES + (AVERAGE_COMPLEXITY > 15 ? 1 : 0)))
          
          {
            echo "  \"quality\": {"
            echo "    \"maintainability_score\": $QUALITY_SCORE,"
            echo "    \"technical_debt_points\": $TECHNICAL_DEBT,"
            echo "    \"grade\": \"$([ $QUALITY_SCORE -gt 80 ] && echo "A" || [ $QUALITY_SCORE -gt 60 ] && echo "B" || [ $QUALITY_SCORE -gt 40 ] && echo "C" || echo "D")\","
            echo "    \"analyzed\": true"
            echo "  },"
          } >> "$REPORT_FILE"
        '' else ''
          echo "  \"quality\": { \"analyzed\": false }," >> "$REPORT_FILE"
        ''}
        
        # Recommendations
        echo "💡 Generating Recommendations..."
        
        {
          echo "  \"recommendations\": ["
          
          RECOMMENDATIONS=""
          
          if [ "$SECURITY_ISSUES" -gt 0 ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS    {\"type\": \"security\", \"priority\": \"high\", \"message\": \"Address $SECURITY_ISSUES security issues found\"},"
          fi
          
          if [ "$PERFORMANCE_ISSUES" -gt 5 ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS    {\"type\": \"performance\", \"priority\": \"medium\", \"message\": \"Optimize $PERFORMANCE_ISSUES performance bottlenecks\"},"
          fi
          
          if [ "$AVERAGE_COMPLEXITY" -gt 15 ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS    {\"type\": \"complexity\", \"priority\": \"medium\", \"message\": \"Reduce code complexity (current: $AVERAGE_COMPLEXITY)\"},"
          fi
          
          if [ "$QUALITY_SCORE" -lt 60 ]; then
            RECOMMENDATIONS="$RECOMMENDATIONS    {\"type\": \"quality\", \"priority\": \"high\", \"message\": \"Improve overall code quality (score: $QUALITY_SCORE/100)\"},"
          fi
          
          # Remove trailing comma
          echo "$RECOMMENDATIONS" | sed 's/,$//g'
          
          echo "  ],"
        } >> "$REPORT_FILE"
        
        # Summary
        {
          echo "  \"summary\": {"
          echo "    \"total_issues\": $((SECURITY_ISSUES + PERFORMANCE_ISSUES)),"
          echo "    \"critical_issues\": $SECURITY_ISSUES,"
          echo "    \"overall_health\": \"$([ $QUALITY_SCORE -gt 80 ] && echo "excellent" || [ $QUALITY_SCORE -gt 60 ] && echo "good" || [ $QUALITY_SCORE -gt 40 ] && echo "fair" || echo "poor")\","
          echo "    \"analysis_duration_ms\": $(($(date +%s%3N) - START_TIME))"
          echo "  }"
          echo "}"
        } >> "$REPORT_FILE"
        
        END_TIME=$(date +%s%3N)
        DURATION=$((END_TIME - START_TIME))
        
        echo ""
        echo "✅ Analysis completed in $DURATION ms"
        echo "📄 Report saved: $REPORT_FILE"
        echo ""
        
        # Display summary
        echo "📊 Analysis Summary:"
        echo "==================="
        echo "Security Issues: $SECURITY_ISSUES"
        echo "Performance Issues: $PERFORMANCE_ISSUES"
        echo "Complexity Score: $AVERAGE_COMPLEXITY"
        echo "Quality Score: $QUALITY_SCORE/100"
        echo "Overall Health: $([ $QUALITY_SCORE -gt 80 ] && echo "excellent" || [ $QUALITY_SCORE -gt 60 ] && echo "good" || [ $QUALITY_SCORE -gt 40 ] && echo "fair" || echo "poor")"
        
        # Create symlink to latest
        ln -sf "$REPORT_FILE" "$ANALYSIS_DIR/latest-analysis.json"
        
        # Log performance
        ai-performance-tracker log "code-analysis" "$DURATION" "true"
        
        # Alert if critical issues found
        if [ "$SECURITY_ISSUES" -ge ${toString config.dotfiles.ai.analysis.continuousAnalysis.alertThresholds.securityIssues} ]; then
          echo ""
          echo "🚨 SECURITY ALERT: $SECURITY_ISSUES critical security issues found!"
        fi
      '')
      
      # Code optimization suggestions
      (writeShellScriptBin "ai-optimize-code" ''
        #!/bin/bash
        
        # AI-powered code optimization suggestions
        
        set -euo pipefail
        
        FILE="$1"
        
        if [ ! -f "$FILE" ]; then
          echo "❌ File not found: $FILE"
          exit 1
        fi
        
        echo "⚡ AI Code Optimization Analysis"
        echo "==============================="
        echo "File: $FILE"
        
        START_TIME=$(date +%s%3N)
        
        LANG=$(echo "$FILE" | sed 's/.*\\.//')
        LINES=$(wc -l < "$FILE")
        
        echo "Language: $LANG"
        echo "Lines: $LINES"
        echo ""
        
        echo "🔍 Analyzing optimization opportunities..."
        
        # Performance optimizations
        ${if config.dotfiles.ai.analysis.codeOptimization.performanceOptimization then ''
          echo ""
          echo "⚡ Performance Optimizations:"
          
          case "$LANG" in
            js|ts)
              echo "• JavaScript/TypeScript optimizations:"
              
              # Check for inefficient patterns
              if grep -q "\.forEach" "$FILE"; then
                echo "  - Consider using for..of loops instead of forEach for better performance"
              fi
              
              if grep -q "new RegExp" "$FILE"; then
                echo "  - Use regex literals instead of RegExp constructor where possible"
              fi
              
              if grep -q "document\.getElementById" "$FILE"; then
                echo "  - Cache DOM queries instead of repeated lookups"
              fi
              ;;
              
            py)
              echo "• Python optimizations:"
              
              if grep -q "range(len(" "$FILE"; then
                echo "  - Use enumerate() instead of range(len()) for cleaner iteration"
              fi
              
              if grep -q "list(" "$FILE" && grep -q "for " "$FILE"; then
                echo "  - Consider list comprehensions for better performance"
              fi
              
              if grep -q "\".*\" + " "$FILE"; then
                echo "  - Use f-strings or .join() instead of string concatenation"
              fi
              ;;
              
            nix)
              echo "• Nix optimizations:"
              
              if grep -q "with pkgs;" "$FILE"; then
                echo "  - Consider explicit package references for better clarity"
              fi
              
              if grep -q "\\[.*\\] ++" "$FILE"; then
                echo "  - Use lib.flatten or lib.concatLists for list operations"
              fi
              ;;
          esac
        '' else ""}
        
        # Memory optimizations
        ${if config.dotfiles.ai.analysis.codeOptimization.memoryOptimization then ''
          echo ""
          echo "💾 Memory Optimizations:"
          
          case "$LANG" in
            js|ts)
              if grep -q "new Array" "$FILE"; then
                echo "  - Use array literals [] instead of new Array() for better memory allocation"
              fi
              
              if grep -q "setInterval\|setTimeout" "$FILE" && ! grep -q "clear" "$FILE"; then
                echo "  - Ensure timers are cleared to prevent memory leaks"
              fi
              ;;
              
            py)
              if grep -q "__del__" "$FILE"; then
                echo "  - Avoid __del__ methods; use context managers or weak references"
              fi
              
              if grep -q "global " "$FILE"; then
                echo "  - Minimize global variables to reduce memory overhead"
              fi
              ;;
          esac
        '' else ""}
        
        # Algorithm optimizations
        ${if config.dotfiles.ai.analysis.codeOptimization.algorithmOptimization then ''
          echo ""
          echo "🧮 Algorithm Optimizations:"
          
          # Detect potential O(n²) patterns
          NESTED_LOOPS=$(grep -c "for.*for\|while.*while" "$FILE" || echo 0)
          if [ "$NESTED_LOOPS" -gt 0 ]; then
            echo "  - Found $NESTED_LOOPS nested loop patterns - consider optimizing to O(n log n) or O(n)"
          fi
          
          # Detect linear search patterns
          if grep -q "\.find\|\.indexOf" "$FILE"; then
            echo "  - Consider using hash maps/sets for O(1) lookups instead of linear search"
          fi
          
          # Detect sorting patterns
          if grep -q "\.sort" "$FILE"; then
            echo "  - Verify if sorting is necessary; consider partial sorting or selection algorithms"
          fi
        '' else ""}
        
        echo ""
        echo "🎯 Priority Recommendations:"
        
        PRIORITY_COUNT=0
        
        # Check file size
        if [ "$LINES" -gt 300 ]; then
          PRIORITY_COUNT=$((PRIORITY_COUNT + 1))
          echo "$PRIORITY_COUNT. Break down large file ($LINES lines) into smaller modules"
        fi
        
        # Check complexity indicators
        FUNCTIONS=$(grep -c "function\|def \|fn " "$FILE" || echo 0)
        if [ "$FUNCTIONS" -gt 20 ]; then
          PRIORITY_COUNT=$((PRIORITY_COUNT + 1))
          echo "$PRIORITY_COUNT. Refactor high function density ($FUNCTIONS functions)"
        fi
        
        # Check for TODO/FIXME
        TODOS=$(grep -c "TODO\|FIXME\|XXX" "$FILE" || echo 0)
        if [ "$TODOS" -gt 5 ]; then
          PRIORITY_COUNT=$((PRIORITY_COUNT + 1))
          echo "$PRIORITY_COUNT. Address $TODOS TODO/FIXME items"
        fi
        
        if [ "$PRIORITY_COUNT" -eq 0 ]; then
          echo "✅ Code structure looks well-optimized!"
        fi
        
        echo ""
        echo "💡 Next Steps:"
        echo "1. Run 'ai-analyze-code $FILE' for comprehensive analysis"
        echo "2. Use 'ai-refactor-suggest $FILE' for detailed refactoring suggestions"
        echo "3. Add performance tests to measure improvements"
        
        END_TIME=$(date +%s%3N)
        DURATION=$((END_TIME - START_TIME))
        
        echo ""
        echo "⏱️  Analysis completed in $DURATION ms"
        
        # Log performance
        ai-performance-tracker log "code-optimize" "$DURATION" "true"
      '')
      
      # Quality dashboard generator
      (writeShellScriptBin "ai-quality-dashboard" ''
        #!/bin/bash
        
        # Generate AI code quality dashboard
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        OUTPUT_FILE="''${2:-$HOME/.local/share/dotfiles-ai/dashboard.html}"
        
        echo "📊 Generating AI Quality Dashboard"
        echo "================================="
        echo "Project: $PROJECT_DIR"
        echo "Output: $OUTPUT_FILE"
        
        ${if config.dotfiles.ai.analysis.qualityMetrics.codeHealthDashboard then ''
          # Run comprehensive analysis
          echo ""
          echo "🔍 Running comprehensive analysis..."
          
          ANALYSIS_FILE="$HOME/.local/share/dotfiles-ai/analysis/latest-analysis.json"
          
          if [ ! -f "$ANALYSIS_FILE" ]; then
            echo "Running initial analysis..."
            ai-analyze-code "$PROJECT_DIR" comprehensive
          fi
          
          # Generate HTML dashboard
          {
            echo "<!DOCTYPE html>"
            echo "<html>"
            echo "<head>"
            echo "  <title>AI Code Quality Dashboard</title>"
            echo "  <style>"
            echo "    body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }"
            echo "    .container { max-width: 1200px; margin: 0 auto; }"
            echo "    .card { background: white; padding: 20px; margin: 10px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }"
            echo "    .metric { display: inline-block; margin: 10px; padding: 15px; border-radius: 4px; min-width: 150px; text-align: center; }"
            echo "    .excellent { background-color: #d4edda; color: #155724; }"
            echo "    .good { background-color: #d1ecf1; color: #0c5460; }"
            echo "    .fair { background-color: #fff3cd; color: #856404; }"
            echo "    .poor { background-color: #f8d7da; color: #721c24; }"
            echo "    .high { background-color: #f8d7da; color: #721c24; }"
            echo "    .medium { background-color: #fff3cd; color: #856404; }"
            echo "    .low { background-color: #d4edda; color: #155724; }"
            echo "    h1, h2 { color: #333; }"
            echo "    .timestamp { color: #666; font-size: 0.9em; }"
            echo "  </style>"
            echo "</head>"
            echo "<body>"
            echo "  <div class=\"container\">"
            echo "    <h1>🤖 AI Code Quality Dashboard</h1>"
            echo "    <p class=\"timestamp\">Generated: $(date)</p>"
            
            if [ -f "$ANALYSIS_FILE" ]; then
              # Extract metrics from JSON
              QUALITY_SCORE=$(jq -r '.quality.maintainability_score // 0' "$ANALYSIS_FILE")
              SECURITY_ISSUES=$(jq -r '.security.issues_found // 0' "$ANALYSIS_FILE")
              PERFORMANCE_ISSUES=$(jq -r '.performance.issues_found // 0' "$ANALYSIS_FILE")
              COMPLEXITY_SCORE=$(jq -r '.complexity.average_score // 0' "$ANALYSIS_FILE")
              TOTAL_ISSUES=$(jq -r '.summary.total_issues // 0' "$ANALYSIS_FILE")
              OVERALL_HEALTH=$(jq -r '.summary.overall_health // "unknown"' "$ANALYSIS_FILE")
              
              echo "    <div class=\"card\">"
              echo "      <h2>📊 Overall Metrics</h2>"
              echo "      <div class=\"metric $OVERALL_HEALTH\">"
              echo "        <h3>$QUALITY_SCORE/100</h3>"
              echo "        <p>Quality Score</p>"
              echo "      </div>"
              echo "      <div class=\"metric $([ $TOTAL_ISSUES -eq 0 ] && echo "low" || [ $TOTAL_ISSUES -lt 5 ] && echo "medium" || echo "high")\">"
              echo "        <h3>$TOTAL_ISSUES</h3>"
              echo "        <p>Total Issues</p>"
              echo "      </div>"
              echo "      <div class=\"metric $([ $COMPLEXITY_SCORE -lt 10 ] && echo "low" || [ $COMPLEXITY_SCORE -lt 20 ] && echo "medium" || echo "high")\">"
              echo "        <h3>$COMPLEXITY_SCORE</h3>"
              echo "        <p>Complexity</p>"
              echo "      </div>"
              echo "    </div>"
              
              echo "    <div class=\"card\">"
              echo "      <h2>🔒 Security Analysis</h2>"
              echo "      <div class=\"metric $([ $SECURITY_ISSUES -eq 0 ] && echo "excellent" || [ $SECURITY_ISSUES -lt 3 ] && echo "good" || echo "poor")\">"
              echo "        <h3>$SECURITY_ISSUES</h3>"
              echo "        <p>Security Issues</p>"
              echo "      </div>"
              echo "      <p>$(jq -r '.security.severity // "unknown"' "$ANALYSIS_FILE") severity level</p>"
              echo "    </div>"
              
              echo "    <div class=\"card\">"
              echo "      <h2>⚡ Performance Analysis</h2>"
              echo "      <div class=\"metric $([ $PERFORMANCE_ISSUES -eq 0 ] && echo "excellent" || [ $PERFORMANCE_ISSUES -lt 5 ] && echo "good" || echo "poor")\">"
              echo "        <h3>$PERFORMANCE_ISSUES</h3>"
              echo "        <p>Performance Issues</p>"
              echo "      </div>"
              echo "      <p>$(jq -r '.performance.optimization_potential // "unknown"' "$ANALYSIS_FILE") optimization potential</p>"
              echo "    </div>"
              
              # Recommendations
              echo "    <div class=\"card\">"
              echo "      <h2>💡 Recommendations</h2>"
              echo "      <ul>"
              jq -r '.recommendations[]? | "        <li><strong>" + .type + "</strong> (" + .priority + " priority): " + .message + "</li>"' "$ANALYSIS_FILE"
              echo "      </ul>"
              echo "    </div>"
            else
              echo "    <div class=\"card\">"
              echo "      <p>No analysis data available. Run 'ai-analyze-code' first.</p>"
              echo "    </div>"
            fi
            
            echo "    <div class=\"card\">"
            echo "      <h2>🔧 Actions</h2>"
            echo "      <p>To improve your code quality:</p>"
            echo "      <ul>"
            echo "        <li>Run <code>ai-analyze-code .</code> for detailed analysis</li>"
            echo "        <li>Use <code>ai-optimize-code &lt;file&gt;</code> for specific optimizations</li>"
            echo "        <li>Apply <code>ai-refactor-suggest &lt;file&gt;</code> for refactoring</li>"
            echo "        <li>Set up <code>ai-pre-commit-review</code> for continuous quality</li>"
            echo "      </ul>"
            echo "    </div>"
            
            echo "    <div class=\"card\">"
            echo "      <p class=\"timestamp\">Dashboard generated by AI Development Assistant</p>"
            echo "    </div>"
            echo "  </div>"
            echo "</body>"
            echo "</html>"
          } > "$OUTPUT_FILE"
          
          echo "✅ Dashboard generated: $OUTPUT_FILE"
          
          # Open dashboard if on macOS
          if [ "$(uname -s)" = "Darwin" ] && command -v open >/dev/null; then
            echo "🌐 Opening dashboard in browser..."
            open "$OUTPUT_FILE"
          fi
        '' else ''
          echo "Code health dashboard disabled"
        ''}
      '')
      
      # Continuous analysis service
      (writeShellScriptBin "ai-continuous-analysis" ''
        #!/bin/bash
        
        # Continuous code analysis background service
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        
        echo "🔄 Starting continuous analysis for: $PROJECT_DIR"
        
        ${if config.dotfiles.ai.analysis.continuousAnalysis.enable then ''
          INTERVAL=${toString config.dotfiles.ai.analysis.continuousAnalysis.analysisInterval}
          
          echo "Analysis interval: $INTERVAL seconds"
          
          while true; do
            echo "$(date): Running analysis..."
            
            # Run analysis
            ai-analyze-code "$PROJECT_DIR" comprehensive > /dev/null 2>&1 || true
            
            # Check for alerts
            ANALYSIS_FILE="$HOME/.local/share/dotfiles-ai/analysis/latest-analysis.json"
            
            if [ -f "$ANALYSIS_FILE" ]; then
              SECURITY_ISSUES=$(jq -r '.security.issues_found // 0' "$ANALYSIS_FILE")
              PERFORMANCE_ISSUES=$(jq -r '.performance.issues_found // 0' "$ANALYSIS_FILE")
              COMPLEXITY_SCORE=$(jq -r '.complexity.average_score // 0' "$ANALYSIS_FILE")
              
              # Check alert thresholds
              if [ "$SECURITY_ISSUES" -ge ${toString config.dotfiles.ai.analysis.continuousAnalysis.alertThresholds.securityIssues} ]; then
                echo "🚨 SECURITY ALERT: $SECURITY_ISSUES issues found"
                # Could send notification here
              fi
              
              if [ "$PERFORMANCE_ISSUES" -ge ${toString config.dotfiles.ai.analysis.continuousAnalysis.alertThresholds.performanceIssues} ]; then
                echo "⚠️  PERFORMANCE ALERT: $PERFORMANCE_ISSUES issues found"
              fi
              
              if [ "$COMPLEXITY_SCORE" -ge ${toString config.dotfiles.ai.analysis.continuousAnalysis.alertThresholds.complexityScore} ]; then
                echo "📈 COMPLEXITY ALERT: Score $COMPLEXITY_SCORE"
              fi
            fi
            
            echo "$(date): Analysis completed, sleeping for $INTERVAL seconds..."
            sleep "$INTERVAL"
          done
        '' else ''
          echo "Continuous analysis disabled"
        ''}
      '')
    ];
    
    # Continuous analysis service (if enabled)
    launchd.user.agents = mkIf (config.dotfiles.ai.analysis.continuousAnalysis.enable && (platformInfo.isDarwin or false)) {
      dotfiles-ai-continuous-analysis = {
        serviceConfig = {
          Label = "org.dotfiles.ai-continuous-analysis";
          ProgramArguments = [
            "${pkgs.writeShellScript "ai-continuous-analysis-service" ''
              #!/bin/bash
              # Find git repositories and run analysis
              find "$HOME" -name ".git" -type d -maxdepth 3 2>/dev/null | while read -r git_dir; do
                project_dir=$(dirname "$git_dir")
                echo "Analyzing: $project_dir"
                cd "$project_dir"
                ai-analyze-code . quick >/dev/null 2>&1 || true
              done
            ''}"
          ];
          StartInterval = config.dotfiles.ai.analysis.continuousAnalysis.analysisInterval;
          StandardErrorPath = "/Users/yuki/.local/share/dotfiles-ai/logs/analysis-error.log";
          StandardOutPath = "/Users/yuki/.local/share/dotfiles-ai/logs/analysis-output.log";
        };
      };
    };
  };
}