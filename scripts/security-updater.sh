#!/bin/bash

# Automated Security Updates Script
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$HOME/Library/Logs/dotfiles-security-updates.log"

log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Update flake.lock
update_flake_lock() {
    log_with_timestamp "Updating flake.lock..."
    cd "$DOTFILES_DIR/nix"
    
    if nix flake update; then
        log_with_timestamp "Successfully updated flake.lock"
        
        # Check if there are any changes
        if git diff --quiet flake.lock; then
            log_with_timestamp "No updates available"
        else
            log_with_timestamp "Changes detected in flake.lock"
            
            # Commit changes
            git add flake.lock
            git commit -m "chore: automated security update of flake.lock

🤖 Automated security update
$(date '+%Y-%m-%d %H:%M:%S')

Co-Authored-By: Security Automation <security@dotfiles.local>"
            
            log_with_timestamp "Committed flake.lock updates"
        fi
    else
        log_with_timestamp "ERROR: Failed to update flake.lock"
        return 1
    fi
}

# Run security checks
run_security_checks() {
    log_with_timestamp "Running security analysis..."
    
    if "$DOTFILES_DIR/scripts/enhanced-dependency-check.sh" security > /tmp/security-check.log 2>&1; then
        log_with_timestamp "Security check completed successfully"
    else
        log_with_timestamp "WARNING: Security check found issues - see /tmp/security-check.log"
    fi
}

# Main execution
main() {
    log_with_timestamp "=== Starting automated security update ==="
    
    update_flake_lock
    run_security_checks
    
    log_with_timestamp "=== Security update completed ==="
}

main "$@"
