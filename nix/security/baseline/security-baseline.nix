# Security Baseline Configuration
# Implements enterprise-grade security hardening across all platforms
{ config, lib, pkgs, platformInfo, ... }:

let
  # Platform capabilities check
  hasFirewall = platformInfo.capabilities.hasFirewall or false;
  hasSystemD = platformInfo.capabilities.hasSystemD or false;
  isLinux = platformInfo.platform == "linux" || platformInfo.platform == "wsl";
  isDarwin = platformInfo.platform == "darwin";
  
  # Security settings by platform
  securitySettings = {
    # SSH hardening (universal)
    ssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
        MaxAuthTries = 3;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
        Protocol = 2;
        X11Forwarding = false;
        UseDNS = false;
        PermitEmptyPasswords = false;
        ChallengeResponseAuthentication = false;
        KerberosAuthentication = false;
        GSSAPIAuthentication = false;
        AllowUsers = [ "yuki" ];
        # Key-based authentication only
        PubkeyAuthentication = true;
        AuthorizedKeysFile = "%h/.ssh/authorized_keys";
      };
    };
    
    # Firewall configuration
    firewall = lib.mkIf hasFirewall {
      enable = true;
      allowedTCPPorts = [ 22 ]; # SSH only
      allowedUDPPorts = [ ];
      logRefusedConnections = true;
      logRefusedPackets = false; # Reduce log noise
      rejectPackets = true;
      allowPing = false;
    };
    
    # System hardening
    kernel = lib.mkIf isLinux {
      sysctl = {
        # Network security
        "net.ipv4.ip_forward" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.secure_redirects" = 0;
        "net.ipv4.conf.default.secure_redirects" = 0;
        "net.ipv6.conf.all.accept_redirects" = 0;
        "net.ipv6.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.log_martians" = 1;
        "net.ipv4.conf.default.log_martians" = 1;
        "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
        "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
        "net.ipv4.tcp_syncookies" = 1;
        
        # Memory protection
        "kernel.exec-shield" = 1;
        "kernel.randomize_va_space" = 2;
        
        # Process restrictions
        "kernel.dmesg_restrict" = 1;
        "kernel.kptr_restrict" = 2;
        "kernel.yama.ptrace_scope" = 1;
        
        # File system security
        "fs.suid_dumpable" = 0;
        "fs.protected_hardlinks" = 1;
        "fs.protected_symlinks" = 1;
      };
    };
  };

in
{
  # Apply security configurations based on platform capabilities
  config = lib.mkMerge [
    # Universal security settings
    {
      # Secure defaults for all platforms
      environment.systemPackages = with pkgs; [
        # Security tools
        gnupg
        openssh
        age
        sops
        
        # Monitoring tools
        htop
        netstat-nat
        lsof
        
        # Network security
        nmap
        tcpdump
      ] ++ lib.optionals isLinux [
        # Linux-specific security tools
        iptables
        ufw
        fail2ban
        rkhunter
        chkrootkit
      ] ++ lib.optionals isDarwin [
        # macOS-specific security tools
        mas
      ];
      
      # Secure shell configuration
      programs.ssh = {
        enable = true;
        forwardX11 = false;
        setXAuthLocation = false;
        extraConfig = ''
          # Security hardening
          HashKnownHosts yes
          VerifyHostKeyDNS yes
          StrictHostKeyChecking ask
          Compression no
          
          # Use secure ciphers only
          Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
          MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
          KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256
          
          # Host key algorithms
          HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,ssh-rsa
          PubkeyAcceptedKeyTypes ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,ssh-rsa
        '';
      };
      
      # GnuPG configuration
      programs.gnupg = {
        enable = true;
        agent = {
          enable = true;
          enableSSHSupport = true;
          enableExtraSocket = true;
          pinentryFlavor = if isDarwin then "mac" else "gtk2";
        };
      };
    }
    
    # Linux-specific security configurations
    (lib.mkIf isLinux {
      # SSH daemon configuration
      services.openssh = securitySettings.ssh;
      
      # Firewall configuration
      networking.firewall = securitySettings.firewall;
      
      # Kernel security parameters
      boot.kernel.sysctl = securitySettings.kernel.sysctl;
      
      # Audit logging
      security.auditd.enable = lib.mkDefault true;
      security.audit.enable = lib.mkDefault true;
      security.audit.rules = [
        # Monitor authentication
        "-w /etc/passwd -p wa -k identity"
        "-w /etc/group -p wa -k identity"
        "-w /etc/gshadow -p wa -k identity"
        "-w /etc/shadow -p wa -k identity"
        "-w /etc/security/opasswd -p wa -k identity"
        
        # Monitor system configuration
        "-w /etc/hosts -p wa -k hosts"
        "-w /etc/network/ -p wa -k network"
        
        # Monitor privilege escalation
        "-a always,exit -F arch=b64 -S adjtimex,settimeofday -k time-change"
        "-a always,exit -F arch=b32 -S adjtimex,settimeofday,stime -k time-change"
        "-a always,exit -F arch=b64 -S clock_settime -k time-change"
        "-a always,exit -F arch=b32 -S clock_settime -k time-change"
        "-w /etc/localtime -p wa -k time-change"
      ];
      
      # Fail2ban configuration
      services.fail2ban = {
        enable = true;
        maxretry = 3;
        findtime = 600;
        bantime = 3600;
        jails = {
          ssh = ''
            enabled = true
            port = 22
            filter = sshd
            logpath = /var/log/auth.log
            maxretry = 3
            findtime = 600
            bantime = 3600
          '';
        };
      };
      
      # System resource limits
      security.pam.limits = [
        { domain = "*"; type = "soft"; item = "core"; value = "0"; }
        { domain = "*"; type = "hard"; item = "core"; value = "0"; }
        { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
        { domain = "*"; type = "hard"; item = "nofile"; value = "65536"; }
      ];
      
      # Disable unnecessary services
      services.avahi.enable = lib.mkDefault false;
      services.printing.enable = lib.mkDefault false;
      
      # Secure boot (where supported)
      boot.loader.systemd-boot.enable = lib.mkDefault true;
      boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
    })
    
    # macOS-specific security configurations
    (lib.mkIf isDarwin {
      # macOS security settings
      system.defaults = {
        loginwindow = {
          GuestEnabled = false;
          DisableConsoleAccess = true;
        };
        
        screensaver = {
          askForPassword = true;
          askForPasswordDelay = 5;
        };
        
        finder = {
          AppleShowAllExtensions = true;
          FXEnableExtensionChangeWarning = true;
        };
        
        NSGlobalDomain = {
          AppleShowAllExtensions = true;
          AppleShowScrollBars = "Always";
        };
      };
      
      # Security tools for macOS
      homebrew = {
        enable = true;
        casks = [
          "little-snitch"      # Network monitor
          "lulu"               # Firewall
          "blockblock"         # Persistence detection
          "knockknock"         # Process monitor
        ];
      };
    })
  ];
}