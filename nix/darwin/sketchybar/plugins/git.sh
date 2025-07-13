#!/bin/bash
# Git Plugin for SketchyBar NG
# Shows git repository status with AI-powered insights

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    sketchybar --set $NAME drawing=off
    exit 0
fi

# Get git status information
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
STATUS=$(git status --porcelain 2>/dev/null)
AHEAD=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
BEHIND=$(git rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")

# Count changes
STAGED=$(echo "$STATUS" | grep -c "^[MADRC]" 2>/dev/null || echo "0")
MODIFIED=$(echo "$STATUS" | grep -c "^.[MD]" 2>/dev/null || echo "0")
UNTRACKED=$(echo "$STATUS" | grep -c "^??" 2>/dev/null || echo "0")

# Determine repository state
if [[ $STAGED -gt 0 ]]; then
    STATE="staged"
    ICON=$GIT_COMMIT
    COLOR=$SUCCESS_COLOR
elif [[ $MODIFIED -gt 0 ]]; then
    STATE="modified"
    ICON=$GIT_INDICATOR
    COLOR=$WARNING_COLOR
elif [[ $UNTRACKED -gt 0 ]]; then
    STATE="untracked"
    ICON=$GIT_INDICATOR
    COLOR=$SECONDARY_COLOR
elif [[ $AHEAD -gt 0 ]]; then
    STATE="ahead"
    ICON=$GIT_PULL_REQUEST
    COLOR=$PRIMARY_COLOR
elif [[ $BEHIND -gt 0 ]]; then
    STATE="behind"
    ICON=$GIT_PULL_REQUEST
    COLOR=$ERROR_COLOR
else
    STATE="clean"
    ICON=$GIT_INDICATOR
    COLOR=$SUCCESS_COLOR
fi

# Build status string
STATUS_TEXT="$BRANCH"

# Add change indicators
CHANGES=""
if [[ $STAGED -gt 0 ]]; then
    CHANGES="${CHANGES}+$STAGED"
fi
if [[ $MODIFIED -gt 0 ]]; then
    [[ -n $CHANGES ]] && CHANGES="${CHANGES} "
    CHANGES="${CHANGES}~$MODIFIED"
fi
if [[ $UNTRACKED -gt 0 ]]; then
    [[ -n $CHANGES ]] && CHANGES="${CHANGES} "
    CHANGES="${CHANGES}?$UNTRACKED"
fi

# Add sync indicators
SYNC=""
if [[ $AHEAD -gt 0 ]]; then
    SYNC="↑$AHEAD"
fi
if [[ $BEHIND -gt 0 ]]; then
    [[ -n $SYNC ]] && SYNC="${SYNC} "
    SYNC="${SYNC}↓$BEHIND"
fi

# Combine all status information
if [[ -n $CHANGES ]]; then
    STATUS_TEXT="$STATUS_TEXT ($CHANGES)"
fi
if [[ -n $SYNC ]]; then
    STATUS_TEXT="$STATUS_TEXT $SYNC"
fi

# AI-powered git insights (run in background to avoid blocking UI)
AI_INSIGHTS() {
    # Only run if Ollama is available and there are recent commits
    if command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
        # Get recent commit info
        RECENT_COMMITS=$(git log --oneline -5 2>/dev/null || echo "")
        
        if [[ -n "$RECENT_COMMITS" ]]; then
            # Check if we should show AI insights (only for interesting states)
            SHOW_INSIGHTS=false
            
            case $STATE in
                "staged"|"modified")
                    SHOW_INSIGHTS=true
                    ;;
                "ahead")
                    if [[ $AHEAD -gt 3 ]]; then
                        SHOW_INSIGHTS=true
                    fi
                    ;;
            esac
            
            if [[ $SHOW_INSIGHTS == true ]]; then
                # Get current diff for context
                CURRENT_DIFF=$(git diff --stat 2>/dev/null | head -10)
                
                # Create context for AI
                CONTEXT="Git status: $STATE, branch: $BRANCH, changes: $CHANGES, recent commits: $RECENT_COMMITS"
                if [[ -n "$CURRENT_DIFF" ]]; then
                    CONTEXT="$CONTEXT, current diff: $CURRENT_DIFF"
                fi
                
                # Ask AI for brief insight (async)
                (
                    AI_INSIGHT=$(echo "Git context: $CONTEXT. Provide one brief development tip (8 words max):" | ollama-manager chat phi:2.7b | tail -1 2>/dev/null)
                    
                    if [[ -n "$AI_INSIGHT" && "$AI_INSIGHT" != *"error"* ]]; then
                        # Store AI insight for next update
                        echo "$AI_INSIGHT" > "/tmp/sketchybar_git_insight"
                    fi
                ) &
            fi
        fi
    fi
}

# Run AI insights (non-blocking)
AI_INSIGHTS

# Check for stored AI insight
AI_INSIGHT=""
if [[ -f "/tmp/sketchybar_git_insight" ]]; then
    AI_INSIGHT=$(cat "/tmp/sketchybar_git_insight" 2>/dev/null || echo "")
    # Clean up old insights (older than 2 minutes)
    find /tmp -name "sketchybar_git_insight" -mmin +2 -delete 2>/dev/null
fi

# Add AI insight if available and relevant
if [[ -n "$AI_INSIGHT" && ($STATE == "staged" || $STATE == "modified" || $AHEAD -gt 1) ]]; then
    STATUS_TEXT="$STATUS_TEXT • $AI_INSIGHT"
fi

# Git repository health monitoring
HEALTH_CHECK() {
    # Check for large files in repository
    LARGE_FILES=$(git ls-files | xargs ls -la 2>/dev/null | awk '$5 > 10485760 {print $9}' | wc -l)
    
    if [[ $LARGE_FILES -gt 0 ]]; then
        # Store warning about large files
        echo "Large files detected" > "/tmp/sketchybar_git_warning"
    fi
    
    # Check for very old branches (older than 30 days)
    OLD_BRANCHES=$(git for-each-ref --format='%(refname:short) %(committerdate)' refs/heads | \
                   awk '$2 < "'$(date -d '30 days ago' '+%Y-%m-%d')'"' | wc -l 2>/dev/null || echo "0")
    
    if [[ $OLD_BRANCHES -gt 3 ]]; then
        echo "Old branches need cleanup" > "/tmp/sketchybar_git_cleanup"
    fi
}

# Run health check occasionally (background)
if [[ $(( $(date +%s) % 300 )) -eq 0 ]]; then
    HEALTH_CHECK &
fi

# Check for warnings
WARNING=""
if [[ -f "/tmp/sketchybar_git_warning" ]]; then
    WARNING="⚠️"
    # Clean up old warnings
    find /tmp -name "sketchybar_git_warning" -mmin +30 -delete 2>/dev/null
fi

if [[ -f "/tmp/sketchybar_git_cleanup" ]]; then
    WARNING="${WARNING}🧹"
    # Clean up old cleanup notices
    find /tmp -name "sketchybar_git_cleanup" -mmin +60 -delete 2>/dev/null
fi

# Add warning to status if present
if [[ -n "$WARNING" ]]; then
    STATUS_TEXT="$WARNING $STATUS_TEXT"
fi

# Update SketchyBar
sketchybar --set $NAME icon="$ICON" \
                   icon.color="$COLOR" \
                   label="$STATUS_TEXT" \
                   label.color="$LABEL_COLOR" \
                   drawing=on

# Special handling for different states
case $STATE in
    "staged")
        # Subtle pulse animation for staged changes
        sketchybar --animate sin 20 --set $NAME icon.color="$SUCCESS_COLOR"
        ;;
    "behind")
        # Gentle blink for behind commits
        if [[ $BEHIND -gt 5 ]]; then
            sketchybar --animate sin 15 --set $NAME icon.color="$ERROR_COLOR"
        fi
        ;;
esac