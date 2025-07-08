# Package Management Policy

## Package Source Priority Matrix

### 1. **Nix (Highest Priority)**
**Use for:**
- CLI tools and utilities
- Development runtimes (Python, Node.js, Go, Rust)
- Language servers and development tools
- System libraries and dependencies
- Cross-platform packages

**Examples:**
```nix
# Preferred in Nix
git curl wget unzip gzip
nodejs python3 go rustc
eza bat fd ripgrep fzf
nil gopls rust-analyzer
```

### 2. **Homebrew (Secondary - macOS GUI only)**
**Use for:**
- macOS-native GUI applications
- Apps requiring native system integration
- Software not available in nixpkgs for macOS
- Window managers and system utilities

**Examples:**
```ruby
# Appropriate for Homebrew
cask "visual-studio-code"
cask "aerospace"
cask "raycast"
```

### 3. **Language-Specific Managers (Project-Scoped)**
**Use for:**
- Project-specific dependencies
- Development libraries within projects
- Tools that need specific versions per project

**Examples:**
```bash
# npm (via direnv in project)
npm install typescript@5.0.0

# pip (in virtual environments)
pip install requests flask

# cargo (in Rust projects)
cargo add serde tokio
```

### 4. **Editor Plugin Managers (Editor-Scoped)**
**Use for:**
- Editor-specific plugins and themes
- IDE extensions
- Editor configuration packages

## Migration Strategy

### Phase 1: Core Tool Consolidation ✅
- [x] CLI tools migrated to Nix
- [x] Development runtimes in Nix
- [x] Modern replacements (eza, bat, etc.) in Nix

### Phase 2: Homebrew Optimization (Current)
- [ ] Remove formulae available in Nix
- [ ] Keep only GUI apps and macOS-specific tools
- [ ] Optimize cask selections

### Phase 3: Project Environment Isolation
- [ ] Implement project-specific shells
- [ ] Use direnv for project dependencies
- [ ] Document project setup patterns

### Phase 4: Update Automation
- [ ] Unified update script
- [ ] Version monitoring
- [ ] Breaking change detection

## Package Conflict Resolution

### Common Conflicts and Solutions:

1. **Python packages**
   ```bash
   # Problem: System vs. project Python packages
   # Solution: Nix for runtime, project-specific for libraries
   
   # Nix: Python runtime
   python3
   
   # Project: Dependencies
   python3.withPackages (ps: with ps; [ requests flask ])
   ```

2. **Node.js tools**
   ```bash
   # Problem: Global vs. local npm packages
   # Solution: Nix for global tools, npm for project deps
   
   # Nix: Global utilities
   nodejs typescript-language-server
   
   # Project: Framework and libraries
   npm install react next.js
   ```

3. **GUI applications**
   ```bash
   # Problem: Nix vs. Homebrew for apps
   # Solution: Homebrew for GUI, Nix for CLI
   
   # Homebrew: GUI applications
   cask "visual-studio-code"
   
   # Nix: CLI version control
   git lazygit
   ```

## Maintenance Guidelines

### Daily Operations:
- Use `just rebuild` for Nix updates
- Use `brew upgrade` only for urgent security updates

### Weekly Maintenance:
- Run unified update script: `./scripts/unified-update.sh`
- Check for package conflicts
- Review and clean unused packages

### Monthly Reviews:
- Audit Homebrew casks for Nix alternatives
- Update project environment templates
- Review and update version pins

## Quality Assurance

### Before Adding New Packages:
1. Check if available in Nix first
2. Verify platform compatibility
3. Consider maintenance overhead
4. Document rationale for package manager choice

### Package Removal Checklist:
1. Check for dependent configurations
2. Update documentation
3. Test system rebuild
4. Clean up related configurations

## Troubleshooting

### Common Issues:

1. **Command not found after rebuild**
   ```bash
   # Check PATH in shell configuration
   echo $PATH
   # Verify package installation
   nix-env -q --installed
   ```

2. **Version conflicts**
   ```bash
   # Check package sources
   which <command>
   # Review Nix configuration
   nix search nixpkgs <package>
   ```

3. **Homebrew/Nix conflicts**
   ```bash
   # Prefer Nix paths
   export PATH="/run/current-system/sw/bin:$PATH"
   # Remove conflicting Homebrew packages
   brew uninstall <package>
   ```