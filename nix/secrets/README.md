# Secrets Management with sops-nix

This directory contains encrypted secrets managed by [sops-nix](https://github.com/Mic92/sops-nix).

## ⚠️ Security Notice

**This directory is set up for secret management but contains only example files.** Actual implementation should be done carefully following security best practices.

## 🔧 Setup (When Ready to Use)

### 1. Install Required Tools

```bash
# Install age for encryption
nix-shell -p age sops

# Or via Homebrew
brew install age sops
```

### 2. Generate Age Key

```bash
# Create sops directory
mkdir -p ~/.config/sops/age

# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Note the public key from the output
cat ~/.config/sops/age/keys.txt
```

### 3. Configure SOPS

```bash
# Copy example configuration
cp .sops.yaml.example .sops.yaml

# Edit and replace YOUR_AGE_PUBLIC_KEY_HERE with your actual public key
$EDITOR .sops.yaml
```

### 4. Create Encrypted Secrets

```bash
# Copy example secrets file
cp nix/secrets/secrets.yaml.example nix/secrets/secrets.yaml

# Edit and encrypt the file
sops nix/secrets/secrets.yaml
```

### 5. Enable sops-nix in Configuration

The sops-nix modules are already imported in `flake.nix`. To use them:

1. Enable the example configuration:
   ```nix
   # In your configuration
   dotfiles.security.sops-example.enable = true;
   ```

2. Or create your own sops configuration following the example in:
   `nix/common/security/sops-example.nix`

## 📁 Directory Structure

```
nix/secrets/
├── README.md                 # This file
├── secrets.yaml.example      # Example secrets structure
├── development/              # Development-specific secrets
└── system/                   # System-level secrets
```

## 🔑 Secret Categories

### Development Secrets
- API keys
- Database passwords
- JWT secrets
- Development tokens

### AI Platform Secrets
- OpenAI API keys
- Anthropic API keys
- GitHub tokens

### System Secrets
- WiFi passwords
- Backup encryption keys
- SSH keys

### Cloud Provider Secrets
- AWS credentials
- GCP service accounts
- Azure credentials

## 📖 Usage Examples

### In Nix Configuration

```nix
# Access decrypted secrets
sops.secrets."ai_platform/openai_api_key" = {
  path = "/run/secrets/openai_key";
  owner = "yuki";
  mode = "0400";
};

# Use in programs
programs.zsh.initExtra = ''
  export OPENAI_API_KEY="$(cat /run/secrets/openai_key)"
'';
```

### In Home Manager

```nix
# User-specific secrets
home-manager.users.yuki.sops.secrets."development/api_key" = {
  path = "${config.home.homeDirectory}/.config/dev/api_key";
};
```

## 🔒 Security Best Practices

1. **Never commit unencrypted secrets**
2. **Use different keys for different environments**
3. **Regularly rotate secrets**
4. **Limit access permissions (mode 0400 or 0600)**
5. **Use specific paths for each secret**
6. **Validate sops files in CI/CD**

## 🚀 Integration with Development Workflow

### Environment Variables
```bash
# Load secrets into environment
source <(sops -d nix/secrets/development/env.yaml | yq eval-all '.[] | to_entries | .[] | "export " + .key + "=" + .value' -)
```

### Git Hooks
```bash
# Prevent committing unencrypted secrets
echo "*.yaml filter=sops diff=sops" >> .gitattributes
```

## 🔍 Verification

After setup, verify your configuration:

```bash
# Check if sops can decrypt your files
sops -d nix/secrets/secrets.yaml

# Test Nix configuration
nix flake check

# Verify secret deployment (after system rebuild)
sudo ls -la /run/secrets/
ls -la ~/.config/dev/
```

## 🆘 Troubleshooting

### Common Issues

1. **"no key found"** - Check age key file location
2. **"permission denied"** - Verify file permissions and ownership  
3. **"file not found"** - Ensure secret files exist and paths are correct

### Debug Commands

```bash
# Check sops configuration
sops --config .sops.yaml

# Verify age key
age -d -i ~/.config/sops/age/keys.txt

# Test decryption
sops -d --extract '["development"]["api_key"]' nix/secrets/secrets.yaml
```

---

**Note**: This setup follows the constraint of preparing the configuration without implementing actual secrets. When ready to use, follow the setup steps above.