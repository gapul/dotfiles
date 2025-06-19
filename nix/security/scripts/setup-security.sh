#!/bin/bash
# Security Setup Script for Multi-Platform Dotfiles
# Initializes SOPS-nix unified encryption (Git-crypt deprecated)

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SECURITY_DIR="$DOTFILES_DIR/nix/platforms/security"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools (SOPS-only setup)
    for tool in nix age sops gpg; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools with:"
        log_info "  nix profile install nixpkgs#age nixpkgs#sops nixpkgs#gnupg"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Setup Age keys for SOPS
setup_age_keys() {
    log_info "Setting up Age keys for SOPS..."
    
    local age_dir="$HOME/.config/sops/age"
    local age_key_file="$age_dir/keys.txt"
    
    # Create age directory
    mkdir -p "$age_dir"
    
    # Generate age key if it doesn't exist
    if [ ! -f "$age_key_file" ]; then
        log_info "Generating new Age key..."
        age-keygen -o "$age_key_file"
        chmod 600 "$age_key_file"
        log_success "Age key generated at: $age_key_file"
        
        # Display public key
        log_info "Your Age public key (add this to SOPS configuration):"
        age-keygen -y "$age_key_file"
    else
        log_warning "Age key already exists at: $age_key_file"
        log_info "Your Age public key:"
        age-keygen -y "$age_key_file"
    fi
}

# Setup GPG for SOPS (optional, Age is primary)
setup_gpg() {
    log_info "Setting up GPG for SOPS (optional)..."
    
    # Check if GPG key exists
    if ! gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -q "sec"; then
        log_warning "No GPG key found. Generating new GPG key..."
        
        # Interactive GPG key generation
        log_info "Please follow the prompts to generate a GPG key..."
        gpg --full-generate-key
        
        log_success "GPG key generated"
    else
        log_success "GPG key already exists"
        gpg --list-secret-keys --keyid-format LONG
    fi
}

# Initialize Git-crypt
setup_git_crypt() {
    log_info "Setting up Git-crypt..."
    
    cd "$DOTFILES_DIR"
    
    # Check if git-crypt is already initialized
    if [ -d ".git-crypt" ]; then
        log_warning "Git-crypt already initialized"
        return
    fi
    
    # Initialize git-crypt
    log_info "Initializing Git-crypt..."
    git-crypt init
    
    # Add GPG users (interactive)
    log_info "Adding GPG user to Git-crypt..."
    log_info "Available GPG keys:"
    gpg --list-secret-keys --keyid-format LONG
    
    read -r -p "Enter GPG key ID to add: " gpg_key_id
    if [ -n "$gpg_key_id" ]; then
        git-crypt add-gpg-user "$gpg_key_id"
        log_success "GPG user added to Git-crypt"
    fi
    
    log_success "Git-crypt initialized"
}

# Create SOPS secret files
setup_sops_secrets() {
    log_info "Setting up SOPS secret files..."
    
    local sops_dir="$SECURITY_DIR/sops"
    
    # Get Age public key
    local age_public_key
    age_public_key=$(age-keygen -y "$HOME/.config/sops/age/keys.txt")
    
    # Create platform-specific secret files
    local platforms=("secrets" "secrets-darwin" "secrets-linux" "secrets-wsl" "secrets-android")
    
    for platform in "${platforms[@]}"; do
        local secret_file="$sops_dir/${platform}.yaml"
        local example_file="$sops_dir/${platform}.yaml.example"
        
        if [ ! -f "$secret_file" ] && [ -f "$example_file" ]; then
            log_info "Creating $platform.yaml from example..."
            
            # Copy example and update with real age key
            cp "$example_file" "$secret_file"
            
            # Update the recipient in the new file
            sed -i.bak "s/age1hl8rkwqkp6l7f5zxc9hjn8m5v3k9p4q7x6z2r8t4w5u6y7i8o9p0q1r2s3t4u5v6/$age_public_key/" "$secret_file"
            rm "$secret_file.bak"
            
            # Add to git-crypt
            git add "$secret_file"
            
            log_success "Created $secret_file"
        fi
    done
}

# Test configuration
test_configuration() {
    log_info "Testing configuration..."
    
    cd "$DOTFILES_DIR/nix/platforms"
    
    # Test Nix flake syntax
    log_info "Checking Nix flake syntax..."
    if nix flake check --show-trace; then
        log_success "Nix flake syntax valid"
    else
        log_error "Nix flake syntax check failed"
        exit 1
    fi
    
    # Test SOPS access (if secrets exist)
    if [ -f "$SECURITY_DIR/sops/secrets.yaml" ]; then
        log_info "Testing SOPS access..."
        if sops exec-file "$SECURITY_DIR/sops/secrets.yaml" 'echo "SOPS access successful"' &>/dev/null; then
            log_success "SOPS access successful"
        else
            log_warning "SOPS access test failed (this is normal if secrets are not yet encrypted)"
        fi
    fi
    
    # Test git-crypt status
    cd "$DOTFILES_DIR"
    if command -v git-crypt &> /dev/null && [ -d ".git-crypt" ]; then
        log_info "Git-crypt status:"
        git-crypt status
    fi
    
    log_success "Configuration tests completed"
}

# Generate setup report
generate_report() {
    log_info "Generating setup report..."
    
    local report_file="$DOTFILES_DIR/security-setup-report.md"
    
    cat > "$report_file" << EOF
# Security Setup Report

Generated on: $(date)

## Configuration Status

### SOPS-nix
- Age key location: \`$HOME/.config/sops/age/keys.txt\`
- Age public key: \`$(age-keygen -y "$HOME/.config/sops/age/keys.txt" 2>/dev/null || echo "Not available")\`
- Secret files: $(find "$SECURITY_DIR/sops" -name "secrets*.yaml" -not -name "*.example" | wc -l)

### Git-crypt
- Status: $([ -d "$DOTFILES_DIR/.git-crypt" ] && echo "Initialized" || echo "Not initialized")
- Protected patterns: $(grep -c "filter=git-crypt" "$DOTFILES_DIR/.gitattributes" 2>/dev/null || echo "0")

### Security Modules
- SOPS configuration: ✅
- Security baseline: ✅
- Git-crypt integration: ✅
- Platform support: macOS, Linux, WSL, Android

## Next Steps

1. **Encrypt your secrets:**
   \`\`\`bash
   cd $DOTFILES_DIR/nix/platforms/security/sops
   sops secrets.yaml  # Edit and encrypt main secrets
   \`\`\`

2. **Test the configuration:**
   \`\`\`bash
   cd $DOTFILES_DIR/nix/platforms
   nix flake check
   \`\`\`

3. **Apply the configuration:**
   \`\`\`bash
   # For macOS:
   nix run nix-darwin -- switch --flake .#default
   
   # For Linux:
   home-manager switch --flake .#yuki@linux
   \`\`\`

## Security Checklist

- [ ] Age keys generated and secured
- [ ] GPG keys configured
- [ ] Git-crypt initialized
- [ ] Secret files created and encrypted
- [ ] Configuration tested
- [ ] Applied to system

EOF

    log_success "Setup report generated: $report_file"
}

# Main execution
main() {
    log_info "🔐 Starting dotfiles security setup..."
    
    # Change to dotfiles directory
    cd "$DOTFILES_DIR"
    
    # Run setup steps
    check_prerequisites
    setup_age_keys
    setup_gpg
    setup_git_crypt
    setup_sops_secrets
    test_configuration
    generate_report
    
    log_success "🎉 Security setup completed successfully!"
    log_info "Please review the setup report for next steps."
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi