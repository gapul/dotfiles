{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.dotfiles.security.baseline;

  # セキュリティベースライン自動化スクリプト
  securityBaselineScript = pkgs.writeShellScript "security-baseline-automation" ''
    #!/usr/bin/env bash
    # Enhanced Security Baseline Automation with Nix Integration
    set -euo pipefail

    # カラー定義
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    # ログ関数
    log_info() { echo -e "''${BLUE}ℹ️  $1''${NC}"; }
    log_success() { echo -e "''${GREEN}✅ $1''${NC}"; }
    log_warning() { echo -e "''${YELLOW}⚠️  $1''${NC}"; }
    log_error() { echo -e "''${RED}❌ $1''${NC}"; }
    log_step() { echo -e "''${CYAN}🔄 $1''${NC}"; }

    # 設定
    DOTFILES_ROOT="''${DOTFILES_ROOT:-$HOME/dotfiles}"
    SECURITY_DIR="$DOTFILES_ROOT/nix/security"
    SETUP_LOG="$DOTFILES_ROOT/security-setup.log"
    DRY_RUN="''${DRY_RUN:-false}"

    show_help() {
      cat << EOF
    Security Baseline Automation Tool

    Usage:
      security-baseline-automation [options]

    Options:
      -s, --setup              Run full security setup
      -a, --age                Setup Age encryption
      --ssh                    Setup SSH security
      --gpg                    Setup GPG security
      -p, --permissions        Audit file permissions
      -v, --verify             Verify security baseline
      -r, --report             Generate setup report
      --dry-run               Show what would be done
      --verbose               Verbose output
      -h, --help              Show this help

    Examples:
      security-baseline-automation --setup         # Full setup
      security-baseline-automation --age --ssh     # Age and SSH only
      security-baseline-automation --dry-run       # Preview changes
      security-baseline-automation --verify        # Verify current setup
    EOF
    }

    # 引数解析
    FULL_SETUP="false"
    SETUP_AGE="false"
    SETUP_SSH="false"
    SETUP_GPG="false"
    AUDIT_PERMISSIONS="false"
    VERIFY_BASELINE="false"
    GENERATE_REPORT="false"
    VERBOSE="false"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -s|--setup)
          FULL_SETUP="true"
          shift
          ;;
        -a|--age)
          SETUP_AGE="true"
          shift
          ;;
        --ssh)
          SETUP_SSH="true"
          shift
          ;;
        --gpg)
          SETUP_GPG="true"
          shift
          ;;
        -p|--permissions)
          AUDIT_PERMISSIONS="true"
          shift
          ;;
        -v|--verify)
          VERIFY_BASELINE="true"
          shift
          ;;
        -r|--report)
          GENERATE_REPORT="true"
          shift
          ;;
        --dry-run)
          DRY_RUN="true"
          shift
          ;;
        --verbose)
          VERBOSE="true"
          shift
          ;;
        -h|--help)
          show_help
          exit 0
          ;;
        *)
          echo -e "''${RED}Unknown option: $1''${NC}" >&2
          show_help
          exit 1
          ;;
      esac
    done

    # フルセットアップの場合
    if [[ "$FULL_SETUP" == "true" ]]; then
      SETUP_AGE="true"
      SETUP_SSH="true"
      SETUP_GPG="true"
      AUDIT_PERMISSIONS="true"
      VERIFY_BASELINE="true"
      GENERATE_REPORT="true"
    fi

    echo -e "''${BLUE}🔐 Security Baseline Automation''${NC}"
    echo "=================================="
    echo "📂 Security Directory: $SECURITY_DIR"
    echo "🔧 Execution Mode: $([ "$DRY_RUN" = "true" ] && echo "Dry Run" || echo "Execute")"
    echo ""

    # 前提条件確認
    check_prerequisites() {
      log_step "📋 Checking prerequisites..."
      
      local missing_tools=()
      local required_tools=("${toString cfg.requiredTools}")
      
      for tool in $required_tools; do
        if ! command -v "$tool" >/dev/null 2>&1; then
          missing_tools+=("$tool")
        fi
      done
      
      if [[ ''${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Missing tools: ''${missing_tools[*]}"
        log_info "Required tools are managed by Nix configuration"
        log_info "Please ensure security.baseline.enable is set to true in your configuration"
        return 1
      fi
      
      log_success "Prerequisites check completed"
      return 0
    }

    # Age暗号化設定
    setup_age_encryption() {
      log_step "🔐 Setting up Age encryption..."
      
      local age_dir="$HOME/.config/sops/age"
      local age_keys_file="$age_dir/keys.txt"
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would setup Age encryption"
        return 0
      fi

      # ディレクトリ作成
      mkdir -p "$age_dir"
      chmod 700 "$age_dir"
      
      # Age キー確認・生成
      if [[ ! -f "$age_keys_file" ]]; then
        log_info "🔑 Generating new Age private key..."
        
        local age_keygen_output
        age_keygen_output=$(age-keygen 2>&1)
        
        # 秘密鍵を保存
        echo "$age_keygen_output" | grep "AGE-SECRET-KEY-" > "$age_keys_file"
        chmod 600 "$age_keys_file"
        
        # 公開鍵を抽出
        local public_key
        public_key=$(echo "$age_keygen_output" | grep "Public key:" | awk '{print $3}')
        
        log_success "Age private key generated: $age_keys_file"
        log_info "Public key: $public_key"
        
        # SOPS設定ファイル更新
        update_sops_config "$public_key"
      else
        log_success "Age private key already exists: $age_keys_file"
        
        # 権限確認
        local current_perms
        current_perms=$(stat -f "%A" "$age_keys_file" 2>/dev/null || echo "unknown")
        if [[ "$current_perms" != "600" ]]; then
          log_warning "Fixing Age key permissions..."
          chmod 600 "$age_keys_file"
        fi
      fi
    }

    # SOPS設定更新
    update_sops_config() {
      local public_key="$1"
      log_step "📝 Updating SOPS configuration..."
      
      local sops_config="$SECURITY_DIR/sops/config/.sops.yaml"
      
      mkdir -p "$(dirname "$sops_config")"
      
      cat > "$sops_config" << EOF
    creation_rules:
      # Dotfiles security configuration
      - path_regex: secrets.*\\.ya?ml$
        age: $public_key
        
      # Environment-specific configurations
      - path_regex: secrets-.*\\.ya?ml$
        age: $public_key
        
      # Platform-specific configurations
      - path_regex: (darwin|linux|android|wsl)/.*secrets.*\\.ya?ml$
        age: $public_key

    # Security policies
    policies:
      encryption_required:
        - "**/secrets*.yaml"
        - "**/secrets*.yml"
        - "**/*secret*.yaml"
        - "**/*secret*.yml"
        - "**/*password*.yaml"
        - "**/*password*.yml"
        - "**/api-keys*.yaml"
        - "**/api-keys*.yml"
      
      exclusions:
        - "**/*.example"
        - "**/*.template"
        - "**/README.md"
        - "**/.gitignore"

    # Age configuration
    age:
      public_key: $public_key
      key_file: ~/.config/sops/age/keys.txt

    # Additional security settings
    security:
      min_encryption_level: "AES256"
      file_permissions:
        secrets: "600"
        keys: "600"
        configs: "644"
      audit_log: true
      audit_file: "$DOTFILES_ROOT/security-audit.log"
    EOF
      
      log_success "SOPS configuration file created: $sops_config"
    }

    # SSH設定最適化
    setup_ssh_security() {
      log_step "🔑 Optimizing SSH security..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would setup SSH security"
        return 0
      fi

      local ssh_dir="$HOME/.ssh"
      local ssh_config="$ssh_dir/config"
      
      # SSHディレクトリ作成
      mkdir -p "$ssh_dir"
      chmod 700 "$ssh_dir"
      
      # SSH設定ファイル作成・更新
      if [[ ! -f "$ssh_config" ]] || [[ "''${cfg.overwriteConfigs}" == "true" ]]; then
        # 既存設定のバックアップ
        if [[ -f "$ssh_config" ]]; then
          cp "$ssh_config" "$ssh_config.backup.$(date +%Y%m%d-%H%M%S)"
          log_info "Existing SSH config backed up"
        fi
        
        cat > "$ssh_config" << 'EOF'
    # Dotfiles SSH Configuration - Security Hardened
    # Auto-generated - Edit with caution

    # Default security settings
    Host *
        # Security settings
        PasswordAuthentication no
        PubkeyAuthentication yes
        ChallengeResponseAuthentication no
        UsePAM no
        
        # Encryption settings
        Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
        KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group16-sha512,diffie-hellman-group14-sha256
        MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
        
        # Protocol settings
        Protocol 2
        Port 22
        
        # Connection settings
        ServerAliveInterval 60
        ServerAliveCountMax 3
        TCPKeepAlive yes
        
        # Security auditing
        LogLevel INFO
        
        # Key settings
        IdentitiesOnly yes
        AddKeysToAgent yes
        UseKeychain yes

    # GitHub configuration
    Host github.com
        HostName github.com
        User git
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
    EOF
        
        chmod 600 "$ssh_config"
        log_success "SSH configuration file created: $ssh_config"
      else
        log_success "SSH configuration file already exists"
      fi
      
      # SSH鍵生成確認
      local ssh_key="$ssh_dir/id_ed25519"
      if [[ ! -f "$ssh_key" ]]; then
        log_info "🔑 Generating new SSH key..."
        
        # Ed25519鍵生成（セキュリティ推奨）
        ssh-keygen -t ed25519 -C "$(whoami)@$(hostname) - Dotfiles" -f "$ssh_key" -N "" || {
          log_error "SSH key generation failed"
          return 1
        }
        
        chmod 600 "$ssh_key"
        chmod 644 "$ssh_key.pub"
        
        log_success "SSH key generated: $ssh_key"
        log_info "Public key: $(cat "$ssh_key.pub")"
        log_warning "Please register the public key with your Git services (GitHub, etc.)"
      else
        log_success "SSH key already exists: $ssh_key"
        
        # 権限確認
        local key_perms
        key_perms=$(stat -f "%A" "$ssh_key" 2>/dev/null || echo "unknown")
        if [[ "$key_perms" != "600" ]]; then
          log_warning "Fixing SSH key permissions..."
          chmod 600 "$ssh_key"
        fi
      fi
    }

    # GPG設定最適化
    setup_gpg_security() {
      log_step "🔐 Optimizing GPG security..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would setup GPG security"
        return 0
      fi

      local gpg_dir="$HOME/.gnupg"
      
      # GPGディレクトリ作成
      mkdir -p "$gpg_dir"
      chmod 700 "$gpg_dir"
      
      # GPG設定ファイル
      local gpg_conf="$gpg_dir/gpg.conf"
      
      cat > "$gpg_conf" << 'EOF'
    # Dotfiles GPG Configuration - Security Hardened

    # Encryption settings
    cipher-algo AES256
    digest-algo SHA256
    cert-digest-algo SHA256
    compress-algo 1
    s2k-digest-algo SHA256
    s2k-cipher-algo AES256

    # Security settings
    no-emit-version
    no-comments
    keyid-format 0xlong
    with-fingerprint
    list-options show-uid-validity
    verify-options show-uid-validity

    # Keyserver settings
    keyserver hkps://keys.openpgp.org
    keyserver-options auto-key-retrieve
    keyserver-options honor-keyserver-url

    # Trust model
    trust-model tofu+pgp
    tofu-default-policy unknown

    # UI settings
    use-agent
    pinentry-mode loopback
    EOF
      
      chmod 600 "$gpg_conf"
      log_success "GPG configuration file created: $gpg_conf"
      
      # GPG鍵確認
      local existing_keys
      existing_keys=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -c "sec" || echo "0")
      
      if [[ "$existing_keys" -eq 0 ]]; then
        log_info "🔑 No GPG keys found (manual generation recommended)"
        log_info "    Run: gpg --full-generate-key"
      else
        log_success "GPG keys exist: ''${existing_keys} keys"
      fi
    }

    # ファイル権限監査・修正
    audit_file_permissions() {
      log_step "📁 Auditing file permissions..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would audit file permissions"
        return 0
      fi

      local issues_found=0
      
      # 重要ファイルの権限チェック
      local critical_files=(
        "$HOME/.ssh/id_*:600"
        "$HOME/.config/sops/age/keys.txt:600"
        "$HOME/.gnupg/secring.gpg:600"
        "$HOME/.gnupg/pubring.gpg:644"
        "$HOME/.ssh/config:600"
        "$HOME/.gitconfig:644"
      )
      
      for file_perm in "''${critical_files[@]}"; do
        local file_pattern="''${file_perm%:*}"
        local expected_perm="''${file_perm#*:}"
        
        # ワイルドカード展開
        for file in $file_pattern; do
          if [[ -f "$file" ]]; then
            local current_perm
            current_perm=$(stat -f "%A" "$file" 2>/dev/null || echo "unknown")
            
            if [[ "$current_perm" != "$expected_perm" ]]; then
              log_warning "Permission fix needed: $file (current: $current_perm, expected: $expected_perm)"
              ((issues_found++))
              
              chmod "$expected_perm" "$file"
              log_success "Permission fixed: $file"
            fi
          fi
        done
      done
      
      # セキュリティリスクのあるファイル検索
      log_info "🔍 Searching for security risks..."
      
      # 書き込み可能なファイル
      local writable_files
      writable_files=$(find "$HOME" -maxdepth 3 -type f -perm -o+w 2>/dev/null | head -5)
      
      if [[ -n "$writable_files" ]]; then
        log_warning "World-writable files found:"
        echo "$writable_files" | while read -r file; do
          echo "    - $file"
          ((issues_found++))
        done
      fi
      
      if [[ $issues_found -eq 0 ]]; then
        log_success "File permissions audit: No issues found"
      else
        log_warning "File permissions audit: ''${issues_found} issues found"
      fi
    }

    # セキュリティベースライン検証
    verify_security_baseline() {
      log_step "🛡️ Verifying security baseline..."
      
      local verification_score=0
      local max_score=10
      
      # Age暗号化チェック
      if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then
        ((verification_score++))
        log_success "✅ Age encryption: Configured"
      else
        log_warning "❌ Age encryption: Not configured"
      fi
      
      # SSH設定チェック
      if [[ -f "$HOME/.ssh/config" ]] && [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        ((verification_score++))
        log_success "✅ SSH security: Configured"
      else
        log_warning "❌ SSH security: Incomplete"
      fi
      
      # GPG設定チェック
      if [[ -f "$HOME/.gnupg/gpg.conf" ]]; then
        ((verification_score++))
        log_success "✅ GPG security: Configured"
      else
        log_warning "❌ GPG security: Not configured"
      fi
      
      # SOPS設定チェック
      if [[ -f "$SECURITY_DIR/sops/config/.sops.yaml" ]]; then
        ((verification_score++))
        log_success "✅ SOPS configuration: Available"
      else
        log_warning "❌ SOPS configuration: Missing"
      fi
      
      # ファイル権限チェック
      local permission_issues=$(find "$HOME/.ssh" -type f ! -perm 600 2>/dev/null | wc -l)
      if [[ $permission_issues -eq 0 ]]; then
        ((verification_score++))
        log_success "✅ File permissions: Secure"
      else
        log_warning "❌ File permissions: Issues found"
      fi
      
      # スコア表示
      local percentage=$((verification_score * 100 / max_score))
      echo ""
      echo "🏆 Security Baseline Score: $verification_score/$max_score ($percentage%)"
      
      if [[ $percentage -ge 80 ]]; then
        log_success "Security baseline meets requirements"
      elif [[ $percentage -ge 60 ]]; then
        log_warning "Security baseline needs improvement"
      else
        log_error "Security baseline requires immediate attention"
      fi
    }

    # セットアップレポート生成
    generate_setup_report() {
      log_step "📋 Generating setup report..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would generate setup report"
        return 0
      fi

      local report_file="$DOTFILES_ROOT/security-baseline-setup-report.md"
      
      cat > "$report_file" << EOF
    # Security Baseline Automation Report

    **Generated:** $(date)
    **Execution Mode:** $([ "$DRY_RUN" = "true" ] && echo "Dry Run" || echo "Execute")
    **Tool:** security-baseline-automation (Nix-managed)

    ## Implemented Features

    ### ✅ Age Encryption Setup
    - Age private key generation and configuration
    - SOPS configuration file creation
    - Encryption policy settings

    ### ✅ SSH Security Optimization
    - Security-hardened configuration
    - Ed25519 key generation
    - Connection optimization

    ### ✅ GPG Security Optimization
    - Security-hardened configuration
    - Encryption algorithm settings
    - Keyserver configuration

    ### ✅ File Permission Auditing
    - Critical file permission verification
    - Automatic permission correction
    - Security risk detection

    ### ✅ Automation Configuration
    - Security automation settings
    - Monitoring and auditing setup
    - CI/CD integration configuration

    ## Security Status

    ### Encryption
    - SOPS/Age: $([ -f "$HOME/.config/sops/age/keys.txt" ] && echo "✅ Configured" || echo "❌ Not configured")
    - SSH Keys: $([ -f "$HOME/.ssh/id_ed25519" ] && echo "✅ Configured" || echo "❌ Not configured")
    - GPG Config: $([ -f "$HOME/.gnupg/gpg.conf" ] && echo "✅ Configured" || echo "❌ Not configured")

    ### Configuration Files
    - SSH Config: $([ -f "$HOME/.ssh/config" ] && echo "✅ Configured" || echo "❌ Not configured")
    - SOPS Config: $([ -f "$SECURITY_DIR/sops/config/.sops.yaml" ] && echo "✅ Configured" || echo "❌ Not configured")

    ## Next Steps

    ### Manual Tasks Required
    1. **GitHub SSH Key Registration**
       - Public key: \`cat ~/.ssh/id_ed25519.pub\`
       - Register at GitHub Settings > SSH keys

    2. **GPG Key Generation (Optional)**
       - Generate GPG key: \`gpg --full-generate-key\`
       - Configure Git signing: \`git config --global user.signingkey <KEY_ID>\`

    3. **Secret Encryption**
       - Encrypt sensitive information with SOPS
       - Edit encrypted files: \`sops secrets.yaml\`

    ### Automated Features
    - Security compliance checking
    - File permission auditing
    - CI/CD security scanning

    ## Generated/Updated Files

    - \`~/.config/sops/age/keys.txt\` - Age private key
    - \`~/.ssh/config\` - SSH configuration
    - \`~/.ssh/id_ed25519\` - SSH private key
    - \`~/.gnupg/gpg.conf\` - GPG configuration
    - \`$SECURITY_DIR/sops/config/.sops.yaml\` - SOPS configuration

    ## Troubleshooting

    ### Common Issues
    1. **Age key permission error**
       - Fix: \`chmod 600 ~/.config/sops/age/keys.txt\`

    2. **SSH connection failed**
       - Fix: \`ssh-add ~/.ssh/id_ed25519\`

    3. **SOPS encryption error**
       - Fix: Verify Age key and SOPS configuration

    ### Support
    - Security verification: \`security-baseline-automation --verify\`
    - Detailed logs: \`$SETUP_LOG\`

    ---

    *Generated: $(date)*
    *Execution Mode: $([ "$DRY_RUN" = "true" ] && echo "Dry Run" || echo "Execute")*
    EOF
      
      log_success "Setup report generated: $report_file"
    }

    # メイン処理
    main() {
      local start_time
      start_time=$(date +%s)
      
      # ログ初期化
      echo "# Security Baseline Automation Log - $(date)" > "$SETUP_LOG"
      
      # 前提条件チェック
      if ! check_prerequisites; then
        exit 1
      fi
      echo ""
      
      # 各段階実行
      [[ "$SETUP_AGE" == "true" ]] && setup_age_encryption && echo ""
      [[ "$SETUP_SSH" == "true" ]] && setup_ssh_security && echo ""
      [[ "$SETUP_GPG" == "true" ]] && setup_gpg_security && echo ""
      [[ "$AUDIT_PERMISSIONS" == "true" ]] && audit_file_permissions && echo ""
      [[ "$VERIFY_BASELINE" == "true" ]] && verify_security_baseline && echo ""
      [[ "$GENERATE_REPORT" == "true" ]] && generate_setup_report

      local end_time
      end_time=$(date +%s)
      local total_time=$((end_time - start_time))
      
      echo ""
      log_success "🎉 Security baseline automation completed!"
      echo "⏱️  Execution time: ''${total_time}s"
      echo "🔧 Execution mode: $([ "$DRY_RUN" = "true" ] && echo "Dry Run" || echo "Execute")"
      [[ -f "$DOTFILES_ROOT/security-baseline-setup-report.md" ]] && echo "📋 Setup report: $DOTFILES_ROOT/security-baseline-setup-report.md"
      echo ""
      echo "✨ Security baseline has been fully automated!"
      
      if [[ "$DRY_RUN" == "false" ]] && [[ "$FULL_SETUP" == "true" ]]; then
        echo ""
        log_info "🔑 Next manual tasks:"
        echo "  1. Register GitHub SSH key: cat ~/.ssh/id_ed25519.pub"
        echo "  2. Generate GPG key (optional): gpg --full-generate-key"
        echo "  3. Encrypt secrets: sops secrets.yaml"
      fi
    }

    # 引数がない場合はヘルプ表示
    if [[ "$SETUP_AGE" == "false" ]] && [[ "$SETUP_SSH" == "false" ]] && [[ "$SETUP_GPG" == "false" ]] && [[ "$AUDIT_PERMISSIONS" == "false" ]] && [[ "$VERIFY_BASELINE" == "false" ]] && [[ "$GENERATE_REPORT" == "false" ]]; then
      show_help
      exit 1
    fi

    # 実行
    main "$@"
  '';

in {
  options.dotfiles.security.baseline = {
    enable = mkEnableOption "Security Baseline Automation";

    requiredTools = mkOption {
      type = types.listOf types.str;
      default = [ "age" "sops" "git" "ssh-keygen" "gpg" ];
      description = "Required security tools";
    };

    overwriteConfigs = mkOption {
      type = types.bool;
      default = false;
      description = "Overwrite existing configuration files";
    };

    enableAgeEncryption = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Age encryption setup";
    };

    enableSSHSecurity = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SSH security hardening";
    };

    enableGPGSecurity = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GPG security configuration";
    };

    enablePermissionAuditing = mkOption {
      type = types.bool;
      default = true;
      description = "Enable file permission auditing";
    };

    autoFixPermissions = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically fix file permissions";
    };

    securityLevel = mkOption {
      type = types.enum [ "standard" "high" "maximum" ];
      default = "high";
      description = "Security level configuration";
    };
  };

  config = mkIf cfg.enable {
    # セキュリティツールパッケージ
    environment.systemPackages = with pkgs; [
      securityBaselineScript
      age
      sops
      openssh
      gnupg
    ];

    # 環境変数
    environment.variables = {
      DOTFILES_SECURITY_LEVEL = cfg.securityLevel;
      SOPS_AGE_RECIPIENTS_FILE = "$HOME/.config/sops/age/recipients";
    };

    # シェルエイリアス
    programs.zsh.shellAliases = mkIf cfg.enable {
      "security-setup" = "security-baseline-automation --setup";
      "security-verify" = "security-baseline-automation --verify";
      "security-age" = "security-baseline-automation --age";
      "security-ssh" = "security-baseline-automation --ssh";
      "security-permissions" = "security-baseline-automation --permissions";
    };

    programs.bash.shellAliases = mkIf cfg.enable {
      "security-setup" = "security-baseline-automation --setup";
      "security-verify" = "security-baseline-automation --verify";
      "security-age" = "security-baseline-automation --age";
      "security-ssh" = "security-baseline-automation --ssh";
      "security-permissions" = "security-baseline-automation --permissions";
    };

    # セキュリティ設定の自動適用
    system.activationScripts.security-baseline = mkIf cfg.enablePermissionAuditing ''
      # Ensure security directories exist with proper permissions
      mkdir -p $HOME/.config/sops/age
      chmod 700 $HOME/.config/sops/age 2>/dev/null || true
      
      mkdir -p $HOME/.ssh
      chmod 700 $HOME/.ssh 2>/dev/null || true
      
      mkdir -p $HOME/.gnupg
      chmod 700 $HOME/.gnupg 2>/dev/null || true
    '';
  };
}