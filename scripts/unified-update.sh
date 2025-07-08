#!/bin/bash
# Unified update strategy for all package managers

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Update strategy flags
UPDATE_NIX=true
UPDATE_HOMEBREW=true
UPDATE_NVIM=true
REBUILD_SYSTEM=true

# Parse command line options
while [[ $# -gt 0 ]]; do
  case $1 in
    --nix-only)
      UPDATE_HOMEBREW=false
      UPDATE_NVIM=false
      shift
      ;;
    --homebrew-only)
      UPDATE_NIX=false
      UPDATE_NVIM=false
      REBUILD_SYSTEM=false
      shift
      ;;
    --no-rebuild)
      REBUILD_SYSTEM=false
      shift
      ;;
    --dry-run)
      log_info "Dry run mode - no actual updates will be performed"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--nix-only|--homebrew-only|--no-rebuild|--dry-run]"
      exit 1
      ;;
  esac
done

cd "$(dirname "$0")/../nix"

log_info "Starting unified package update process..."

# 1. Update Nix flake inputs
if [[ "$UPDATE_NIX" == "true" ]]; then
  log_info "Updating Nix flake inputs..."
  if nix flake update; then
    log_success "Nix flake inputs updated"
  else
    log_error "Failed to update Nix flake inputs"
    exit 1
  fi
  
  # Check for breaking changes
  log_info "Checking for breaking changes..."
  if nix flake check; then
    log_success "Flake check passed"
  else
    log_warning "Flake check failed - manual intervention may be required"
  fi
fi

# 2. Update Homebrew
if [[ "$UPDATE_HOMEBREW" == "true" ]] && command -v brew >/dev/null 2>&1; then
  log_info "Updating Homebrew..."
  brew update
  
  log_info "Upgrading Homebrew packages..."
  if brew upgrade; then
    log_success "Homebrew packages upgraded"
  else
    log_warning "Some Homebrew packages failed to upgrade"
  fi
  
  log_info "Cleaning up Homebrew..."
  brew cleanup
  brew autoremove
fi

# 3. Update Neovim plugins
if [[ "$UPDATE_NVIM" == "true" ]] && command -v nvim >/dev/null 2>&1; then
  log_info "Updating Neovim plugins..."
  nvim --headless "+Lazy! sync" +qa
  log_success "Neovim plugins updated"
fi

# 4. Rebuild system configuration
if [[ "$REBUILD_SYSTEM" == "true" ]]; then
  log_info "Rebuilding system configuration..."
  
  # Detect platform and rebuild accordingly
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if nix run nix-darwin -- switch --flake .; then
      log_success "macOS system configuration rebuilt"
    else
      log_error "Failed to rebuild macOS configuration"
      exit 1
    fi
  elif [[ -f "/etc/nixos/configuration.nix" ]]; then
    if sudo nixos-rebuild switch --flake .; then
      log_success "NixOS system configuration rebuilt"
    else
      log_error "Failed to rebuild NixOS configuration"
      exit 1
    fi
  else
    if home-manager switch --flake .#yuki@linux; then
      log_success "Home Manager configuration rebuilt"
    else
      log_error "Failed to rebuild Home Manager configuration"
      exit 1
    fi
  fi
fi

# 5. Clean up old generations
log_info "Cleaning up old generations..."
nix-collect-garbage -d
if command -v darwin-rebuild >/dev/null 2>&1; then
  sudo nix-collect-garbage -d
fi

log_success "Unified update process completed successfully!"
log_info "Summary of updates:"
echo "  • Nix flake inputs: $([[ "$UPDATE_NIX" == "true" ]] && echo "Updated" || echo "Skipped")"
echo "  • Homebrew packages: $([[ "$UPDATE_HOMEBREW" == "true" ]] && echo "Updated" || echo "Skipped")"
echo "  • Neovim plugins: $([[ "$UPDATE_NVIM" == "true" ]] && echo "Updated" || echo "Skipped")"
echo "  • System rebuild: $([[ "$REBUILD_SYSTEM" == "true" ]] && echo "Completed" || echo "Skipped")"