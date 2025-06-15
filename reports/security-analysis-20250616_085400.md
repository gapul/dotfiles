# Security Analysis Report
Generated: #午後

## Potential Security Issues

### Secret Scanning
❌ Potential secrets found in configuration files

### .gitignore Coverage
- ⚠️  *.key not in .gitignore
- ⚠️  *.pem not in .gitignore
- ⚠️  *.p12 not in .gitignore
- ⚠️  *.p8 not in .gitignore
- ⚠️  *.env not in .gitignore
- ⚠️  secrets.* not in .gitignore
- ⚠️  private.* not in .gitignore

### File Permissions
- ✅ setup.sh (executable)
- ✅ install.sh (executable)
- ✅ scripts/setup.sh (executable)
- ✅ scripts/nix-maintenance.sh (executable)
- ✅ scripts/utils.sh (executable)
- ✅ scripts/check-ci.sh (executable)
- ✅ scripts/phase3-migration.sh (executable)
- ✅ scripts/nix-shortcuts.sh (executable)
- ✅ scripts/install.sh (executable)
- ✅ scripts/software.sh (executable)
- ✅ scripts/restore.sh (executable)
- ✅ scripts/check-dependencies.sh (executable)
- ✅ scripts/backup.sh (executable)
- ✅ scripts/nix-channel-setup.sh (executable)
- ✅ scripts/enhanced-dependency-check.sh (executable)
- ✅ scripts/nix-package-optimizer.sh (executable)
- ✅ .github/scripts/validate_toml.py (executable)
- ⚠️  test-project/test.py (not executable)
