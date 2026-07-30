{
  pkgs,
  lib,
  user,
  hardwareConfig ? ./nixos-laptop-hardware.nix,
  ...
}:
{
  # HP laptop dual-booting with Windows (x86_64, Intel integrated GPU).
  # Place the hardware-configuration.nix emitted by `nixos-generate-config` on the
  # real machine into this same hosts/ dir and enable the import below (it need not be committed to the repo).
  imports = [
    hardwareConfig
  ];

  # --- Bootloader: lanzaboote (Secure Boot support) ---
  # Disable the usual systemd-boot and replace it with lanzaboote, which uses signed UKIs.
  # The menu itself is systemd-boot based, so Windows Boot Manager is also auto-detected
  # (detects EFI/Microsoft/Boot on the ESP; no os-prober needed).
  #
  # ⚠️ From initial install until key enrollment, keep Secure Boot OFF for now.
  #    For the `sbctl create-keys` → `sbctl enroll-keys --microsoft` → Secure Boot ON in BIOS
  #    procedure, see Phase 8 of docs/NIXOS_DUALBOOT.md.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  # Menu display seconds. Since both Windows and NixOS are used, allow enough time to not miss the menu.
  boot.loader.timeout = 5;
  boot.lanzaboote = {
    enable = true;
    # Where sbctl places keys. Match the `sbctl create-keys` default.
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 8; # If the ESP is only 100MB, lower to 3-5
  };
  # The ESP itself cannot be encrypted (firmware reads it in plaintext), but Secure Boot
  # verifies the signature of kernel/initrd (UKI), so tampering with the boot chain on the ESP is detected.
  # Since the existing Windows ESP is reused, confirm that the generated hardware-configuration.nix's
  # fileSystems."/boot" points to the ESP (vfat, e.g. /dev/nvme0n1p1).

  # --- Disk encryption (LUKS) ---
  # The actual cryptroot device (UUID) is written by nixos-generate-config into
  # hardware-configuration.nix's boot.initrd.luks.devices. For the procedure, see
  # Phase 4-5 of docs/NIXOS_DUALBOOT.md.
  # For swap, avoid a plaintext partition and use zram (in-memory, on encrypted RAM).
  zramSwap.enable = true;

  # systemd-based initrd (needed for TPM2 auto-unlock + a modern initrd). Works with lanzaboote.
  boot.initrd.systemd.enable = true;
  # Auto-unlock cryptroot with TPM2. After enabling Secure Boot, enroll the key into
  #   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 <LUKS partition>
  # for PCR 7 (Secure Boot state) (docs Appendix A). If not enrolled, it falls back to the
  # passphrase, so it's safe. The device itself is defined by cryptroot in hardware-configuration.nix.
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];

  # --- Operational maintenance (don't exhaust the fixed dual-boot partition capacity) ---
  # Auto-GC + dedup the Nix store. Since capacity is shared with Windows, keep store bloat in check.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings = {
    # ⚠️ Required: without this, `nixos-rebuild switch --flake` won't work.
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true; # store dedup
    # General safeguard against unreachable substituters breaking builds: give up early
    # (connect-timeout), and on substitute failure fall through to a source build (fallback).
    # Even if some cache is down, local builds still succeed.
    connect-timeout = 5;
    fallback = true;
    # Fetch Hyprland from the official binary cache instead of building from source (saves tens of minutes).
    # nix-community is added with the same least-privilege policy as the darwin side (hosts/darwin.nix).
    substituters = [
      "https://cache.nixos.org"
      "https://hyprland.cachix.org"
      "https://nix-community.cachix.org"
      # Own dotfiles build cache (cachix, filled by CI, pull without auth). Pulls this config's outputs.
      "https://gapul-dotfiles.cachix.org"
    ];
    trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "gapul-dotfiles.cachix.org-1:tGNGJ7SGHrLAjsw5Iz673st0AepuNjQombMJOOVUq98="
    ];
  };

  # nh (nix helper): same workflow as darwin. Rebuild with `nh os switch`.
  # GC is delegated to nix.gc above, so nh.clean stays disabled (avoids double GC).
  programs.nh = {
    enable = true;
    flake = "/home/${user.username}/.dotfiles/nix";
  };

  # nix-ld: lets "ordinary Linux binaries" (langserver / VSCode extensions / prebuilt CLI)
  # run as-is on NixOS. The single most effective trick for the NixOS dev experience.
  programs.nix-ld.enable = true;
  # nix-index: run an uninstalled command temporarily with `,` (comma); also provides command-not-found.
  programs.nix-index.enable = true;

  # Kill heavy processes before the system freezes from memory exhaustion (low-RAM safeguard for the laptop).
  services.earlyoom.enable = true;

  # Do firmware updates from the Linux side at intended times. Reduces incidents where an unexpected BIOS
  # update changes Secure Boot keys / TPM measurements and demands the recovery key.
  services.fwupd.enable = true;

  networking.hostName = "nixos-laptop";
  networking.networkmanager.enable = true;

  # The home homelab is on Tailscale (*.gapul.net). Join this machine too.
  # Authenticate with `sudo tailscale up` on first run only.
  services.tailscale.enable = true;

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";
  console.keyMap = "us"; # "jp" for a JIS layout

  # Countermeasure for clock drift when dual-booting with Windows.
  # NixOS treats the RTC as UTC. Align Windows to UTC as well with
  #   reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
  # so the time matches on both OSes (see docs/NIXOS_DUALBOOT.md for the procedure).

  # --- Intel integrated GPU ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # Gen8+ (recommended)
      intel-vaapi-driver # fallback for older generations (formerly vaapiIntel)
    ];
  };

  nixpkgs.config.allowUnfree = true;

  # --- Laptop power/thermal/input (HP laptop) ---
  services.tlp.enable = true; # battery optimization (charge thresholds etc. tunable later)
  services.thermald.enable = true; # Intel CPU thermal control (proper thermal throttling)
  services.libinput.enable = true; # touchpad (tap, natural scroll, etc.)
  # Suspend on lid close (default behavior; override with logind if needed).
  # Battery level / brightness are handled by brightnessctl + waybar.

  # Proprietary firmware for wireless/BT etc. (required for the laptop's Intel WiFi/Bluetooth).
  hardware.enableRedistributableFirmware = true;
  # Periodic SSD TRIM (lifespan / performance maintenance).
  services.fstrim.enable = true;

  # --- Desktop: Hyprland (Wayland tiling compositor) ---
  # Enable Hyprland itself + xdg-desktop-portal-hyprland + XWayland together.
  programs.hyprland.enable = true;

  # Login: greetd + tuigreet (lightweight, Wayland support; launches Hyprland from a TTY).
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
      user = "greeter";
    };
  };

  # Recovery profile for when changes around Hyprland/GPU/greetd prevent a normal boot.
  # Enter a TTY from the "safe" specialisation in systemd-boot, then roll back to the
  # previous generation or fix the config. Does not affect the normal configuration.
  specialisation.safe.configuration = {
    programs.hyprland.enable = lib.mkForce false;
    services.greetd.enable = lib.mkForce false;
    hardware.graphics.enable = lib.mkForce false;
  };

  # polkit agent for GUI privilege-escalation dialogs (specified explicitly since Hyprland ships no DE).
  security.polkit.enable = true;

  # Screen lock: provide hyprlock's PAM/security wrapper on the system side
  # (visual config and the hypridle daemon go in home/hyprland.nix on the home-manager side).
  programs.hyprlock.enable = true;

  # Run Electron/Chromium and Firefox natively on Wayland (avoids HiDPI blurriness).
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };
  # dconf, where GTK app settings are stored (required by some GUI apps).
  programs.dconf.enable = true;
  # Also use the GTK portal for file-picker dialogs etc. (the hyprland portal is already bundled).
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # The keyboard layout is set via Hyprland's input{kb_layout}. The console uses console.keyMap.
  # fcitx5 Japanese input is handled by i18n.inputMethod below, including the Wayland env vars.

  # Japanese input (fcitx5 + Mozc)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [ fcitx5-mozc ];
  };

  services.printing.enable = true;
  # mDNS (.local name resolution / network printer auto-discovery).
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Bluetooth (keyboard/earphones etc.).
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Fonts (Nerd Font glyphs for ghostty/waybar + Japanese/emoji).
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    hackgen-nf-font # HackGen Console NF, assumed by the ghostty config
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # --- User (home-manager is wired up on the flake side) ---
  users.users.${user.username} = {
    isNormalUser = true;
    description = user.username;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # SSH is public-key only (password auth disabled). Keys follow the Bitwarden-managed policy.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Fingerprint auth (the HP laptop's fingerprint reader). Usable for sudo / login / unlocking hyprlock.
  # Enroll a fingerprint with `sudo fprintd-enroll $USER` on first run only.
  # * LUKS unlock happens at boot (initrd), so fingerprints can't be used there; it stays passphrase/TPM.
  services.fprintd.enable = true;

  # --- Containers (podman: rootless + docker-compatible) ---
  # The `docker` command can be used as an alias for podman (dockerCompat).
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true; # name resolution between containers
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    sbctl # generate/enroll/verify Secure Boot keys (used for lanzaboote operation)

    # Minimal set to make Hyprland usable from the start.
    # A full rice (keybinds/waybar config/wallpaper) is meant to be moved to home-manager's
    # wayland.windowManager.hyprland and gradually removed from here.
    ghostty # main terminal (config symlinked in home/hyprland.nix)
    kitty # fallback opened by Hyprland's stock SUPER+Q (home's $terminal is ghostty)
    wofi # app launcher (bound to SUPER+R etc.)
    hyprpaper # wallpaper (waybar/mako moved to home-manager management)
    wl-clipboard # clipboard (wl-copy / wl-paste)
    cliphist # clipboard history (integrates with wofi)
    hyprpolkitagent # polkit auth dialog (autostart in the hyprland config)
    grim # screenshot capture
    slurp # region selection (used with grim)
    brightnessctl # screen brightness
    playerctl # media keys

    # Geek-oriented CLI
    comma # run an uninstalled command with `, <cmd>` (integrates with nix-index)
    distrobox # run another distro's userland on podman (mix of Arch/Ubuntu tools)
    lazydocker # TUI for podman/docker
    btop # system monitor
    fastfetch # system info display
    nvtopPackages.intel # GPU monitor (Intel)

    # Hyprland QoL
    hyprpicker # color picker
    hyprshot # screenshot (window/region/screen)
    wlogout # power menu
    wl-gammarelay-rs # control color temperature (night light) via dbus
  ];

  # Enable if you want to read/write the NTFS Windows partition (optional)
  # boot.supportedFilesystems = [ "ntfs" ];

  # The NixOS version at initial install. Once set, do not change it.
  system.stateVersion = "26.05";
}
