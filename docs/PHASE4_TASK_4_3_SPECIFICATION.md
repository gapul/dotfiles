# Phase 4 Task 4.3: 高度なセキュリティ管理とシークレット管理

## 📋 Task Overview

**目標**: エンタープライズグレードのセキュリティ管理システムを構築し、機密情報を安全に管理・共有できる環境を整備する

**期間**: 2-3週間  
**優先度**: High  
**前提条件**: Task 4.1, 4.2完了 (マルチプラットフォーム対応 + CI/CD統合)

## 🎯 Success Criteria

### 必須要件
- [ ] SOPS-nix完全統合とシークレット暗号化
- [ ] Git-cryptによる選択的ファイル暗号化
- [ ] セキュリティベースライン設定
- [ ] CI/CD環境での安全なシークレット管理
- [ ] 全プラットフォーム対応のセキュリティ設定

### 拡張要件  
- [ ] HashiCorp Vault統合
- [ ] 動的シークレットローテーション
- [ ] セキュリティ監査ログ
- [ ] ゼロトラスト原則の実装

## 🏗️ Technical Architecture

### Directory Structure
```
nix/platforms/security/
├── sops/
│   ├── secrets.yaml              # メインシークレットファイル
│   ├── secrets-darwin.yaml       # macOS固有シークレット
│   ├── secrets-linux.yaml        # Linux固有シークレット
│   ├── secrets-wsl.yaml          # WSL固有シークレット
│   ├── secrets-android.yaml      # Android固有シークレット
│   ├── keys/
│   │   ├── age/                  # Age公開鍵
│   │   │   ├── personal.txt
│   │   │   ├── ci-cd.txt
│   │   │   └── team.txt
│   │   └── gpg/                  # GPG公開鍵
│   └── config/
│       ├── default.nix           # SOPS-nix基本設定
│       ├── creation-rules.nix    # 暗号化ルール定義
│       └── platform-specific.nix # プラットフォーム固有設定
├── git-crypt/
│   ├── .gitattributes           # Git-crypt設定
│   ├── keys/                    # Git-crypt鍵管理
│   └── config.nix              # Git-crypt Nix統合
├── vault/
│   ├── policies/                # Vault policy definitions
│   │   ├── dotfiles-read.hcl
│   │   ├── dotfiles-write.hcl
│   │   └── admin.hcl
│   ├── config/
│   │   ├── vault-agent.hcl      # Vault Agentコンフィグ
│   │   └── integration.nix      # Nix統合設定
│   └── scripts/
│       ├── setup-vault.sh       # Vault初期セットアップ
│       └── rotate-secrets.sh    # シークレットローテーション
├── baseline/
│   ├── security-baseline.nix    # セキュリティベースライン
│   ├── compliance-checks.nix    # コンプライアンス検証
│   └── hardening/
│       ├── darwin.nix           # macOSハードニング
│       ├── linux.nix            # Linuxハードニング
│       ├── wsl.nix             # WSLハードニング
│       └── android.nix         # Androidハードニング
└── templates/
    ├── sops-template.yaml       # SOPSファイルテンプレート
    ├── vault-policy.hcl.tmpl   # Vaultポリシーテンプレート
    └── secret-config.nix.tmpl  # シークレット設定テンプレート
```

### Integration Points

**flake.nix Integration:**
```nix
# nix/platforms/flake.nix
{
  inputs = {
    sops-nix.url = "github:Mic92/sops-nix";
    # ... existing inputs
  };
  
  outputs = { sops-nix, ... }: {
    darwinConfigurations = {
      default = nix-darwin.lib.darwinSystem {
        modules = [
          sops-nix.darwinModules.sops
          ./security/sops/config/default.nix
          ./security/baseline/darwin.nix
          # ... existing modules
        ];
      };
    };
    # ... other configurations
  };
}
```

## 🔐 Security Components

### 1. SOPS-nix Implementation

**Core Features:**
- Age + GPG dual encryption support
- Platform-specific secret management
- CI/CD integration with GitHub Actions
- Automatic secret distribution

**Example Configuration:**
```nix
# security/sops/config/default.nix
{ config, lib, ... }:
{
  sops = {
    defaultSopsFile = ../secrets.yaml;
    defaultSopsFormat = "yaml";
    
    age = {
      # Age private key location
      keyFile = "/var/lib/sops-nix/key.txt";
      # Generate key if missing
      generateKey = true;
    };
    
    secrets = {
      # GitHub token for CI/CD
      "github/token" = {
        owner = config.users.users.yuki.name;
        group = config.users.users.yuki.group;
        mode = "0400";
      };
      
      # SSH keys
      "ssh/personal_key" = {
        path = "/home/yuki/.ssh/id_rsa";
        owner = config.users.users.yuki.name;
        mode = "0600";
      };
      
      # API credentials
      "api/openai_key" = {};
      "api/anthropic_key" = {};
    };
  };
}
```

**Secret Creation Workflow:**
```bash
# Initialize SOPS with age key
age-keygen -o ~/.config/sops/age/keys.txt

# Create new secret file
sops nix/platforms/security/sops/secrets.yaml

# Edit existing secrets
sops nix/platforms/security/sops/secrets.yaml

# Platform-specific secrets
sops nix/platforms/security/sops/secrets-darwin.yaml
```

### 2. Git-crypt Implementation

**Selective Encryption:**
```bash
# .gitattributes (in project root)
secrets/** filter=git-crypt diff=git-crypt
nix/platforms/security/sops/keys/gpg/** filter=git-crypt diff=git-crypt
*.key filter=git-crypt diff=git-crypt
vault-token filter=git-crypt diff=git-crypt
```

**Setup Process:**
```bash
# Initialize git-crypt
git-crypt init

# Add GPG user
git-crypt add-gpg-user USER_ID

# Export key for team sharing
git-crypt export-key /path/to/shared/key

# Unlock repository
git-crypt unlock /path/to/key
```

### 3. Security Baseline Configuration

**System Hardening:**
```nix
# security/baseline/security-baseline.nix
{ lib, config, platformInfo, ... }:
{
  # Firewall configuration
  firewall = lib.mkIf platformInfo.capabilities.hasFirewall {
    enable = true;
    allowedTCPPorts = [ 22 ]; # SSH only
    allowedUDPPorts = [ ];
    logRefusedConnections = true;
  };
  
  # SSH hardening
  openssh = lib.mkIf config.services.openssh.enable {
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      MaxAuthTries = 3;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };
  };
  
  # Audit logging
  auditd.enable = lib.mkDefault true;
  
  # Automatic security updates
  auto-upgrade = {
    enable = true;
    allowReboot = false;
  };
}
```

### 4. HashiCorp Vault Integration (Optional)

**Vault Agent Configuration:**
```hcl
# security/vault/config/vault-agent.hcl
vault {
  address = "https://vault.example.com:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/etc/vault/role-id"
      secret_id_file_path = "/etc/vault/secret-id"
    }
  }
  
  sink "file" {
    config = {
      path = "/etc/vault/token"
    }
  }
}

template {
  source      = "/etc/vault/templates/secrets.yaml.tpl"
  destination = "/etc/secrets/secrets.yaml"
  perms       = 0600
}
```

## 🧪 Testing Strategy

### Security Tests

**SOPS Integration Tests:**
```bash
# Test secret decryption
sops exec-file nix/platforms/security/sops/secrets.yaml 'echo "Secret loaded: $GITHUB_TOKEN"'

# Test platform-specific secrets
nix eval .#darwinConfigurations.default.config.sops.secrets

# Verify secret permissions
ls -la /run/secrets/
```

**Git-crypt Tests:**
```bash
# Verify encryption status
git-crypt status

# Test lock/unlock cycle
git-crypt lock
git status  # Should show encrypted files as modified
git-crypt unlock
git status  # Should show clean working directory
```

**Security Baseline Tests:**
```bash
# Test firewall rules
sudo iptables -L

# Verify SSH configuration
ssh-audit localhost

# Check audit logs
sudo ausearch -m USER_LOGIN
```

### CI/CD Security Integration

**GitHub Actions Secrets Management:**
```yaml
# .github/workflows/security-tests.yml
name: Security Tests
on: [push, pull_request]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Age key
        run: |
          mkdir -p ~/.config/sops/age
          echo "${{ secrets.SOPS_AGE_KEY }}" > ~/.config/sops/age/keys.txt
          chmod 600 ~/.config/sops/age/keys.txt
      
      - name: Test secret decryption
        run: |
          sops exec-file nix/platforms/security/sops/secrets.yaml 'echo "Secrets accessible"'
      
      - name: Security baseline check
        run: |
          # Run security compliance checks
          nix eval .#securityBaseline.complianceReport
      
      - name: Secrets scanning
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: main
          head: HEAD
```

## 📝 Implementation Plan

### Week 1: Core Security Infrastructure

**Day 1-2: SOPS-nix Setup**
- [ ] Install and configure SOPS-nix
- [ ] Generate age and GPG keys
- [ ] Create initial secrets.yaml structure
- [ ] Test basic secret encryption/decryption

**Day 3-4: Multi-platform Integration**
- [ ] Platform-specific secret files
- [ ] SOPS configuration per platform
- [ ] Test secret access in each environment

**Day 5-7: Git-crypt Integration**
- [ ] Setup Git-crypt in repository
- [ ] Configure .gitattributes for selective encryption
- [ ] Test encryption/decryption workflow

### Week 2: Security Baseline & Hardening

**Day 8-10: Security Baseline**
- [ ] Implement security-baseline.nix
- [ ] Platform-specific hardening configurations
- [ ] Firewall and SSH security

**Day 11-12: Compliance & Monitoring**
- [ ] Audit logging configuration
- [ ] Security compliance checks
- [ ] Monitoring and alerting setup

**Day 13-14: CI/CD Security Integration**
- [ ] GitHub Actions secrets management
- [ ] Automated security scanning
- [ ] Secret rotation workflows

### Week 3: Advanced Features & Documentation

**Day 15-17: Vault Integration (Optional)**
- [ ] HashiCorp Vault setup
- [ ] Dynamic secret management
- [ ] API key rotation

**Day 18-19: Testing & Validation**
- [ ] Comprehensive security testing
- [ ] Penetration testing simulation
- [ ] Performance impact assessment

**Day 20-21: Documentation & Training**
- [ ] Security procedures documentation
- [ ] Team training materials
- [ ] Incident response procedures

## 🔍 Security Considerations

### Threat Model

**Assets to Protect:**
- SSH private keys
- API tokens (GitHub, OpenAI, Anthropic)
- Database credentials
- Personal certificates
- Development environment secrets

**Threat Vectors:**
- Repository compromise
- CI/CD pipeline attacks
- Local system compromise
- Supply chain attacks
- Insider threats

**Mitigation Strategies:**
- Defense in depth
- Principle of least privilege
- Regular secret rotation
- Audit logging
- Encrypted storage

### Compliance Requirements

**Security Standards:**
- SOC 2 Type II principles
- NIST Cybersecurity Framework
- ISO 27001 controls
- GDPR privacy requirements

**Monitoring & Alerting:**
- Failed authentication attempts
- Unusual access patterns
- Secret access auditing
- Configuration changes

## 🚀 Success Metrics

### Security KPIs
- Secret rotation frequency: Monthly
- Failed access attempts: < 1% of total
- Security scan coverage: 100%
- Compliance score: 95%+

### Performance Metrics
- Secret access latency: < 100ms
- Build time impact: < 10%
- Setup time for new developers: < 30 minutes

## 📚 References

### Documentation
- [SOPS-nix Documentation](https://github.com/Mic92/sops-nix)
- [Git-crypt Manual](https://github.com/AGWA/git-crypt)
- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

### Tools & Libraries
- [Age encryption](https://age-encryption.org/)
- [GNU Privacy Guard](https://gnupg.org/)
- [Vault Agent](https://developer.hashicorp.com/vault/docs/agent)
- [TruffleHog secrets scanner](https://github.com/trufflesecurity/trufflehog)

---

**Document Version**: 1.0  
**Last Updated**: 2025年6月17日 15:30  
**Author**: Claude Code AI Assistant  
**Approval Required**: Project Lead Review