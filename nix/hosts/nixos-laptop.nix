{
  config,
  pkgs,
  lib,
  user,
  nixpkgsAgents,
  hardwareConfig ? ./nixos-laptop-hardware.nix,
  ...
}:
let
  # Hold off suspend for a long job (Vivado install/synthesis) while on battery, where
  # hypridle would otherwise suspend after 15 idle minutes and drop the machine off the
  # tailnet. The inhibitor is taken by a root transient unit because an ssh session is not
  # an active seat: polkit refuses a user's block-sleep inhibitor there ("requires
  # interactive authentication"). An idle inhibitor also pauses hypridle's listeners.
  # Closing the lid still suspends on battery (logind's LidSwitchIgnoreInhibited defaults
  # to yes), which is the behaviour wanted for a laptop going into a bag.
  keepAwake = pkgs.writeShellApplication {
    name = "keep-awake";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      unit=keep-awake
      case "''${1:-on}" in
        on)
          duration=''${2:-infinity}
          sudo systemctl reset-failed "$unit" 2>/dev/null || true
          sudo systemd-run --unit="$unit" --description="keep-awake: block sleep/idle" \
            ${pkgs.systemd}/bin/systemd-inhibit --what=sleep:idle --who=keep-awake \
            --why="keep-awake ($duration)" --mode=block ${pkgs.coreutils}/bin/sleep "$duration"
          ;;
        off) sudo systemctl stop "$unit" ;;
        status) systemd-inhibit --list --no-pager ;;
        *)
          echo "usage: keep-awake [on [DURATION]|off|status]  (DURATION as for sleep(1), default infinity)" >&2
          exit 2
          ;;
      esac
    '';
  };
  # Fast-moving agent CLIs come from the dedicated nixpkgs-agents lineage, same as on
  # darwin (hosts/darwin.nix). systemPackages rather than home.packages for the PATH
  # order: /run/current-system/sw/bin sits ahead of ~/.local/bin, so a stray
  # self-installed copy cannot win.
  agentPkgs = import ../lib/unstable-pkgs.nix {
    nixpkgsUnstable = nixpkgsAgents;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
in
{
  # HP laptop dual-booting with Windows (x86_64, Intel integrated GPU).
  # Place the hardware-configuration.nix emitted by `nixos-generate-config` on the
  # real machine into this same hosts/ dir and enable the import below (it need not be committed to the repo).
  imports = [
    hardwareConfig
    ./nixos-laptop-vivado.nix # FPGA coursework (Vivado 2020.2, installed by hand into /opt/Xilinx)
    ./nixos-laptop-wifi.nix # eduroam (UTokyo) + iPhone hotspot, credentials from secrets/nixos-laptop.yaml
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
  # The menu is systemd-boot's text menu (lanzaboote keeps that; a graphical loader such as
  # rEFInd would have to be signed by hand to keep Secure Boot). "max" draws it at the panel's
  # native resolution instead of the firmware's 80x25 text mode, so it is small and sharp.
  boot.loader.systemd-boot.consoleMode = "max";
  boot.lanzaboote = {
    enable = true;
    # Where sbctl places keys. Match the `sbctl create-keys` default.
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 8; # If the ESP is only 100MB, lower to 3-5
  };
  # --- Boot screen ---
  # Plymouth draws the boot (and the LUKS PIN prompt) instead of the kernel log: a themed
  # animation from adi1090x's set, picked by name below (the package has ~70 of them; only the
  # chosen one is built, the full set is ~500 MB). The console is kept quiet so nothing scrolls
  # under it; the log is still in `journalctl -b`, and Esc shows it during boot.
  boot.plymouth = {
    enable = true;
    theme = "rings";
    themePackages = [ (pkgs.adi1090x-plymouth-themes.override { selected_themes = [ "rings" ]; }) ];
  };
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "udev.log_level=3"
    "rd.systemd.show_status=auto"
    "systemd.show_status=auto"
  ];

  # --- OS menu: rEFInd in front of systemd-boot ---
  # systemd-boot's menu is text only, and lanzaboote keeps it that way. rEFInd gives the
  # choice between NixOS and Windows a graphical menu (icons on the same ASCII wallpaper as
  # the desktop, the rEFInd-minimal theme's flat icons). Nothing in nixpkgs' refind module is
  # used, because that module lays out its own unsigned kernels, which Secure Boot would
  # refuse. Instead the activation script below copies rEFInd's binary to the ESP, signs it
  # with the sbctl keys (the same db key that signs the UKIs, so PCR 7 and the LUKS TPM
  # binding are unchanged), writes a refind.conf whose NixOS entry points at the newest
  # lanzaboote UKI (with the safe specialisation and older generations in its submenu, and
  # systemd-boot itself as the last resort), and puts rEFInd first in the firmware's boot
  # order. systemd-boot stays installed and second in the order: if the firmware ever
  # refuses rEFInd, the next entry is the old menu.
  system.activationScripts.refind =
    let
      theme = pkgs.fetchFromGitHub {
        owner = "EvanPurkhiser";
        repo = "rEFInd-minimal";
        rev = "56a06a4bd9ed76c05523a22017056dbecca4145d";
        hash = "sha256-ALDa8bhgiHyIRmyGh8/1P56TvEG/gqC0qOqAWbtURyg=";
      };
      palettes = (builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json)).palettes;
      wallpaper = import ../lib/wallpaper.nix {
        inherit pkgs;
        p = palettes.rose-pine;
        name = "rose-pine";
      };
      # The panel's size; rEFInd scales the banner to the screen anyway, this keeps the file small.
      background = pkgs.runCommand "refind-background.png" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
        magick ${wallpaper} -resize 1920x1200 $out
      '';
      conf = pkgs.writeText "refind.conf" ''
        timeout 5
        resolution max
        use_graphics_for linux,windows
        hideui singleuser,hints,arrows,badges
        icons_dir theme/icons
        banner theme/background.png
        banner_scale fillscreen
        selection_big theme/selection_big.png
        selection_small theme/selection_small.png
        showtools shutdown,reboot,firmware
        # Windows is found by scanning the ESP; the UKIs, systemd-boot and the fallback copy
        # of it are hidden, since the stanza written below covers them in one entry.
        scanfor manual,internal
        dont_scan_dirs ESP:/EFI/Linux,ESP:/EFI/systemd,ESP:/EFI/BOOT,ESP:/EFI/nixos
        default_selection NixOS
      '';
      install = pkgs.writeShellScript "refind-install" ''
        set -eu
        PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.util-linux pkgs.sbctl pkgs.efibootmgr ]}
        esp=/boot
        d=$esp/EFI/refind
        mkdir -p "$d/theme/icons"

        # The binary, signed. Re-signed only when rEFInd's package changes or the signature
        # is missing, so a normal switch does not touch it.
        if ! cmp -s ${pkgs.refind}/share/refind/refind_x64.efi "$d/refind_x64.efi.unsigned" 2>/dev/null; then
          cp ${pkgs.refind}/share/refind/refind_x64.efi "$d/refind_x64.efi.unsigned"
          cp "$d/refind_x64.efi.unsigned" "$d/refind_x64.efi"
        fi
        # (sbctl verify exits 0 either way; its check mark is the answer.)
        if ! sbctl verify "$d/refind_x64.efi" 2>&1 | grep -q '✓'; then
          sbctl sign "$d/refind_x64.efi" >/dev/null
        fi

        # Theme and background.
        cp ${theme}/selection_big.png ${theme}/selection_small.png "$d/theme/"
        cp ${theme}/icons/*.png "$d/theme/icons/"
        cp ${background} "$d/theme/background.png"

        # The NixOS entry: the newest generation's UKI, its safe specialisation, the three
        # generations before it, and systemd-boot (every generation, the old text menu).
        gen_of() { basename "$1" | sed -n 's/^nixos-generation-\([0-9]*\)-.*/\1/p'; }
        date_of() { date -d "@$(stat -c %Y "/nix/var/nix/profiles/system-$1-link" 2>/dev/null || echo 0)" '+%Y-%m-%d %H:%M'; }
        latest=""; latest_n=0
        for f in "$esp"/EFI/Linux/nixos-generation-*.efi; do
          case "$f" in *specialisation*) continue ;; esac
          n=$(gen_of "$f"); [ "$n" -gt "$latest_n" ] && { latest_n=$n; latest=$f; }
        done
        [ -n "$latest" ] || { echo "refind: no UKI in $esp/EFI/Linux" >&2; exit 0; }
        {
          cat ${conf}
          echo
          echo "menuentry \"NixOS\" {"
          echo "    icon theme/icons/os_nixos.png"
          echo "    loader /EFI/Linux/$(basename "$latest")"
          safe=$(ls "$esp"/EFI/Linux/nixos-generation-$latest_n-specialisation-safe-*.efi 2>/dev/null | head -n 1)
          [ -n "$safe" ] && {
            echo "    submenuentry \"Generation $latest_n, safe mode (no Hyprland, no GPU)\" {"
            echo "        loader /EFI/Linux/$(basename "$safe")"
            echo "    }"
          }
          for f in $(ls "$esp"/EFI/Linux/nixos-generation-*.efi | grep -v specialisation | sort -t- -k3,3nr); do
            n=$(gen_of "$f"); [ "$n" -lt "$latest_n" ] || continue
            echo "    submenuentry \"Generation $n, $(date_of "$n")\" {"
            echo "        loader /EFI/Linux/$(basename "$f")"
            echo "    }"
          done | head -n 12
          echo "    submenuentry \"systemd-boot (every generation)\" {"
          echo "        loader /EFI/systemd/systemd-bootx64.efi"
          echo "    }"
          echo "}"
        } > "$d/refind.conf.new"
        mv "$d/refind.conf.new" "$d/refind.conf"

        # Firmware entry, first in the order. systemd-boot's entry stays as the fallback.
        dev=$(findmnt -no SOURCE "$esp")
        disk=/dev/$(lsblk -no PKNAME "$dev")
        part=$(cat "/sys/class/block/$(basename "$dev")/partition")
        # (efibootmgr prints "Boot0005* rEFInd<tab>HD(...)": the label ends at a tab.)
        if ! efibootmgr | grep -q "^Boot[0-9A-F]*\* rEFInd$(printf '\t')"; then
          efibootmgr -q -c -d "$disk" -p "$part" -L rEFInd -l '\EFI\refind\refind_x64.efi'
        fi
        num=$(efibootmgr | sed -n "s/^Boot\([0-9A-F]*\)\* rEFInd$(printf '\t').*/\1/p" | head -n 1)
        [ -n "$num" ] || { echo "refind: no firmware entry" >&2; exit 0; }
        order=$(efibootmgr | sed -n 's/^BootOrder: //p')
        case "$order" in
          "$num"|"$num,"*) ;;
          *) efibootmgr -q -o "$num,$(echo "$order" | sed "s/\b$num\b//; s/,,/,/; s/^,//; s/,$//")" ;;
        esac
      '';
    in
    {
      deps = [ ];
      text = "${install}";
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
  # Unlock cryptroot with TPM2 + PIN. After enabling Secure Boot, enroll the key into
  #   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes <LUKS partition>
  # for PCR 7 (Secure Boot state) (docs Appendix A). If not enrolled, it falls back to the
  # passphrase, so it's safe. The device itself is defined by cryptroot in hardware-configuration.nix.
  #
  # The PIN is what makes this worth anything on a machine that leaves the house. PCR 7 alone binds
  # the key to an untampered boot chain, not to a person: whoever powers the laptop on gets a
  # decrypted disk. The TPM rate-limits PIN attempts in hardware, so a short PIN is enough — this is
  # not a passphrase, and brute force is not on the table.
  # userspace TPM access (tpm2-tss + udev rules + the tss group). The LUKS slot above does not
  # need this — that runs in initrd as root — but ssh-tpm-agent talks to the TPM as the user.
  security.tpm2.enable = true;

  # tpm2-pin must match how the slot was enrolled; enrolling without --tpm2-with-pin and setting this
  # (or the reverse) just falls through to the passphrase prompt.
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [
    "tpm2-device=auto"
    "tpm2-pin=yes"
  ];

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
    # The weekly GC alone let the disk fill between runs (79% used on 2026-10-08, 12 GiB of dead
    # paths waiting for Monday). When a build sees less than min-free, nix collects dead paths
    # until max-free is free. It never touches live generations, so rollback is unaffected.
    min-free = 20 * 1024 * 1024 * 1024;
    max-free = 50 * 1024 * 1024 * 1024;
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
      "gapul-dotfiles.cachix.org-1:tGNGJ7SGHrLAjswSIz673st0AepuNjQombMJO0VUq98="
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
  i18n.defaultLocale = "en_US.UTF-8";
  # The console takes its keymap from the xkb settings so Caps Lock is Ctrl there too (the
  # greeter and TTYs). Nothing here enables X; Hyprland has its own kb_options.
  services.xserver.xkb = {
    layout = "us"; # "jp" for a JIS layout
    options = "ctrl:nocaps";
  };
  console.useXkbConfig = true;
  # xremap (home/xremap.nix) runs as the user, reads the keyboards and writes to /dev/uinput.
  # uinput already carries systemd's uaccess tag; the keyboards get it here, so the logged-in user
  # on the active seat can read them. That is narrower than the input group, which would give every
  # process of the user every input device even from an ssh session, and it applies without a
  # re-login. The file name has to sort before 73-seat-late.rules (see nixos-laptop-vivado.nix).
  hardware.uinput.enable = true;
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "fusuma-touchpad-uaccess";
      destination = "/lib/udev/rules.d/70-fusuma-touchpad.rules";
      text = ''
        SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", TAG+="uaccess"
      '';
    })
    (pkgs.writeTextFile {
      name = "xremap-keyboard-uaccess";
      destination = "/lib/udev/rules.d/70-xremap-keyboard.rules";
      text = ''
        SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
      '';
    })
  ];

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
  # Obsidian / Bitwarden / Beeper all ship on Electron 39, which nixpkgs marks insecure
  # because upstream Electron dropped it from support. The same three run on the mac against
  # the same Electron, so refusing them only here would be theatre rather than a decision.
  # This pin is maintenance: the version string goes stale on every nixpkgs bump, and the
  # right time to delete the line is when a bump stops needing it.
  nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

  # --- Laptop power/thermal/input (HP laptop) ---
  services.tlp.enable = true; # battery optimization (charge thresholds etc. tunable later)
  services.thermald.enable = true; # Intel CPU thermal control (proper thermal throttling)
  services.libinput.enable = true; # touchpad (tap, natural scroll, etc.)
  # Lid close: suspend on battery, stay up on AC. The machine is administered over SSH,
  # so closing it on the desk should not take it off the tailnet; on battery the default
  # suspend still applies so a closed laptop in a bag does not cook itself.
  # Power button: a press locks the session (logind sends Lock to the session, hypridle runs
  # hyprlock), a long press (5 s) powers off. logind's default is poweroff on a plain press, which
  # on a laptop is one stray touch from losing the session.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "lock";
    HandlePowerKeyLongPress = "poweroff";
  };

  # Suspend on lid close (default behavior; override with logind if needed).
  # Battery level / brightness are handled by brightnessctl + waybar.

  # Proprietary firmware for wireless/BT etc. (required for the laptop's Intel WiFi/Bluetooth).
  hardware.enableRedistributableFirmware = true;
  # Periodic SSD TRIM (lifespan / performance maintenance).
  services.fstrim.enable = true;

  # --- Desktop: Hyprland (Wayland tiling compositor) ---
  # Enable Hyprland itself + xdg-desktop-portal-hyprland + XWayland together.
  programs.hyprland.enable = true;

  # Electron clients such as T3 need Secret Service to encrypt saved connection tokens.
  # Password login unlocks the keyring via PAM; fingerprint login still needs a keyring prompt.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Login: greetd + ReGreet (GTK greeter under cage) on the same generated wallpaper the
  # desktop uses (home/stylix.nix), in the palette's colours. It lists the Wayland sessions
  # NixOS knows about (Hyprland, from programs.hyprland) and remembers the last user/session.
  # The module sets greetd's default_session itself. Fingerprint works as before: pam_fprintd
  # is in the greetd stack and ReGreet shows its "place your finger" prompt.
  services.greetd = {
    enable = true;
    settings.default_session.user = "greeter";
  };
  services.displayManager.regreet =
    let
      data = builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json);
      c = data.palettes.${data.active};
      wallpaper = import ../lib/wallpaper.nix {
        inherit pkgs;
        p = c;
        name = data.active;
      };
    in
    {
      enable = true;
      cageArgs = [ "-s" "-d" "-m" "last" ];
      font = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
        size = 14;
      };
      iconTheme = {
        package = pkgs.papirus-icon-theme;
        name = "Papirus-Dark";
      };
      settings = {
        background = {
          path = "${wallpaper}";
          fit = "Cover";
        };
        GTK.application_prefer_dark_theme = c.variant == "dark";
        widget.clock = {
          format = "%Y-%m-%d %H:%M";
          resolution = "60s";
          timezone = "Asia/Tokyo";
        };
      };
      # Translucent card in the palette's surface colour, so the form sits on the wallpaper
      # like the bar and hyprlock do rather than as a stock grey Adwaita box.
      extraCss = ''
        window { background: transparent; }
        box.horizontal > box, box.vertical > box.login {
          background: alpha(#${c.surface}, 0.85);
          border-radius: 16px;
          padding: 24px;
        }
        * { color: #${c.text}; }
        entry, combobox, button {
          background: alpha(#${c.overlay}, 0.9);
          border-radius: 10px;
        }
        button.suggested-action { background: #${c.iris}; color: #${c.base}; }
        entry:focus { outline: 2px solid #${c.iris}; }
      '';
    };

  # Recovery profile for when changes around Hyprland/GPU/greetd prevent a normal boot.
  # Enter a TTY from the "safe" specialisation in systemd-boot, then roll back to the
  # previous generation or fix the config. Does not affect the normal configuration.
  specialisation.safe.configuration = {
    programs.hyprland.enable = lib.mkForce false;
    services.greetd.enable = lib.mkForce false;
    services.displayManager.regreet.enable = lib.mkForce false; # reads greetd's session user
    hardware.graphics.enable = lib.mkForce false;
    # Anything that pulls in the graphics stack has to go too. With graphics off,
    # hardware.graphics.package has no value, so a module that merely reads it (steam and
    # gamescope both do) fails evaluation of the whole specialisation.
    programs.steam.enable = lib.mkForce false;
    programs.gamescope.enable = lib.mkForce false;
    hardware.graphics.enable32Bit = lib.mkForce false;
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
  # Claude Code starts in bypassPermissions here, i.e. what --dangerously-skip-permissions does:
  # this machine is driven remotely (herdr, ssh), so a permission prompt has nobody in front of
  # it and the session simply stalls.
  #
  # It has to be a managed-settings file rather than the usual settings.json, because that one is
  # a symlink into the ai-agent-state repo and therefore shared with the Mac — editing it would
  # put the Mac into bypass too. /etc/claude-code/managed-settings.json is the only layer that is
  # machine-local, and being NixOS it can still be declared rather than dropped by hand.
  #
  # defaultMode is a starting mode, not a lock: /permissions still switches the running session.
  # skipDangerousModePermissionPrompt stops the first bypass session asking for confirmation,
  # which would be the same stall this is meant to avoid.
  environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
    permissions.defaultMode = "bypassPermissions";
    skipDangerousModePermissionPrompt = true;
  };

  # dconf, where GTK app settings are stored (required by some GUI apps).
  programs.dconf.enable = true;
  # Also use the GTK portal for file-picker dialogs etc. (the hyprland portal is already bundled).
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # The keyboard layout is set via Hyprland's input{kb_layout}. The console uses services.xserver.xkb.
  # fcitx5 Japanese input is handled by i18n.inputMethod below, including the IM env vars.

  # Japanese input: fcitx5 with SKK, set up after macSKK on the mac (configs/ime/skk/README.md).
  # Mozc stays installed but out of the group; add it back from fcitx5-configtool if it is ever wanted.
  # macSKK's skkserv (azooKey skkserv on localhost:1178) has no counterpart here: it is a mac app.
  # The dictionaries and the kana rule are user-side, in home/fcitx5-skk.nix.
  # Hyprland runs no XDG autostart, so the daemon is started from its exec-once (home/hyprland.nix);
  # before that, nothing ever started fcitx5 and neither IM worked.
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-skk
        fcitx5-mozc
      ];
      # Apps talk to fcitx5 over Wayland's text-input protocol instead of the GTK/Qt IM modules
      # (GTK_IM_MODULE / QT_IM_MODULE are no longer set; XMODIFIERS stays, for XWayland apps).
      # Through the GTK module Ghostty dropped every candidate picked from the window (a/s/d...),
      # committing nothing; over text-input it takes them. fcitx5 itself warns about the GTK
      # module on startup, as upstream advises against it under Hyprland.
      waylandFrontend = true;
      # Written to /etc/xdg/fcitx5. A ~/.config/fcitx5 that fcitx5-configtool saves takes precedence.
      settings = {
        # The input method group (SKK alone) is user-side in home/fcitx5-skk.nix: fcitx5 rewrites
        # ~/.config/fcitx5/profile on every exit, and that copy would shadow one written here.
        # Taken from macSKK's settings (configs/ime/skk/macSKK.plist), option by option:
        addons.skk.globalSection = {
          Rule = "gapul"; # kanaRule: default + full-width ！ (home/fcitx5-skk.nix)
          PunctuationStyle = "Japanese"; # punctuation = 0: 、。
          # Starts in latin, so a new window (a terminal, nvim) takes ASCII until C-j.
          InitialInputMode = "Latin";
          "Candidate Layout" = "Horizontal"; # candidateListDirection = 1
          # selectCandidateKeys = "ASDFGHJKL": the home row picks, nine to a page.
          CandidateChooseKey = "Qwerty Center Row (a,s,d,...)";
          PageSize = 9;
          # inlineCandidateCount = 5: five candidates cycle in place before the window opens.
          NTriggersToShowCandWin = 5;
          # enterNewLine = false (macSKK's default): Enter only commits, it does not also send a newline.
          EggLikeNewLine = "True";
          ShowAnnotation = "True";
        };
      };
    };
  };

  services.printing.enable = true;
  # USB transport for iPhone tools. Android USB access uses systemd uaccess rules.
  services.usbmuxd.enable = true;
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
  # LibrePods 0.2.5 ranks SBC above PipeWire's default A2DP (AAC on AirPods).
  nixpkgs.overlays = [
    (_final: prev: {
      librepods = prev.librepods.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace media/mediacontroller.cpp \
            --replace-fail 'QStringList profiles = {"a2dp-sink-sbc_xq", "a2dp-sink-sbc", "a2dp-sink"};' \
              'QStringList profiles = {"a2dp-sink", "a2dp-sink-sbc_xq", "a2dp-sink-sbc"};'
        '';
      });
    })
  ];


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
      # Talking to /dev/tpmrm0 needs the tss group. Required by home/ssh-tpm-agent.nix, which
      # asserts on this rather than failing at runtime with a permission error.
      config.security.tpm2.tssGroup
    ];
    shell = pkgs.zsh;
    # Public keys, so they live in the repo rather than being curl'd onto the box
    # by hand on every reinstall. Private keys stay in Bitwarden.
    # Mirrors github.com/gapul.keys (plus macmini, below). A flake cannot fetch that list at build time, so
    # this is a snapshot: rotating a key means editing here too. The previous snapshot
    # went stale and locked this machine out entirely — the only way back in was typing
    # a curl line on its physical keyboard.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBLeOb9XOJPsmuTRf708qYoNckWk+/fhuWkpTWtTSu41"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFc0vERDgqbotas7YjbabpVPWjtficFNWSW+8Hu/WL8x"
      "sk-ecdsa-sha2-nistp256@openssh.com AAAAInNrLWVjZHNhLXNoYTItbmlzdHAyNTZAb3BlbnNzaC5jb20AAAAIbmlzdHAyNTYAAABBBP5Y2DQbhcGpmOGDewcxUuVZ+/XO1I/Zm4M4nZhBMPwygadJY9//NxbVAZs98vMIp1Yy+9wgkQcEuc1CNQdCY2cAAAAEc3NoOg=="
      # macmini's outbound key (same line as in keys/authorized_keys). Not on github.com/gapul.keys:
      # it lets agents running on macmini reach this box directly instead of hopping through the
      # Mac, which drops the session whenever the Mac sleeps.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILZva+I0ui3AGOMb2V7BTLOXXtCJYvCJg9PGmzWOD8Am macmini-outbound"
    ];
  };
  programs.zsh.enable = true;

  # SSH is public-key only (password auth disabled). Keys follow the Bitwarden-managed policy.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # sudo without a password for wheel. This box is administered remotely over SSH
  # (key-only, PasswordAuthentication = false), and prompting for a password there
  # means someone has to be sitting at the machine for every rebuild. The trade-off
  # is explicit: whoever holds the SSH private key gets root. That is already close
  # to true, since `nixos-rebuild` is root-equivalent by construction.
  security.sudo.wheelNeedsPassword = false;

  # Fingerprint auth (the HP laptop's fingerprint reader).
  # Enabling fprintd makes NixOS insert pam_fprintd ahead of pam_unix in the PAM stacks, so
  # greetd and the ttys accept a finger and fall back to the password on their own.
  # Two things are deliberately not what they look like:
  #   * sudo does NOT use it. wheelNeedsPassword = false above means the sudo auth stack is
  #     never run, so pam_fprintd is never reached. Keeping NOPASSWD is the deliberate
  #     choice: requiring a finger would make every SSH-driven `sudo` hang until someone
  #     touches the machine.
  #   * hyprlock does not go through PAM for this. It talks to fprintd over D-Bus itself and
  #     needs its own `auth:fingerprint:enabled` switch (see home/hyprland.nix).
  # Enroll a fingerprint with `fprintd-enroll` on first run only.
  # * LUKS unlock happens at boot (initrd), so fingerprints can't be used there; it stays passphrase/TPM.
  services.fprintd.enable = true;
  # hyprlock talks to fprintd itself (auth.fingerprint in home/hyprland.nix), so its PAM stack must
  # not also run pam_fprintd: with both, the password prompt would wait behind a second fingerprint
  # request, and the two would fight over the sensor.
  security.pam.services.hyprlock.fprintAuth = false;

  # --- Gaming ---
  # Steam has to be system-side: it needs the 32-bit graphics stack (driSupport32Bit) and
  # its own firewall holes, neither of which home-manager can provide. gamescope is the
  # micro-compositor games run inside — under Hyprland it is what keeps resolution and
  # frame pacing sane instead of fighting the tiling WM. gamemode flips the CPU governor
  # for the duration of a game and puts it back afterwards.
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };
  programs.gamescope.enable = true;
  programs.gamemode.enable = true;
  # 32-bit userspace GL for older titles and for Proton's 32-bit prefixes.
  hardware.graphics.enable32Bit = true;

  # --- Android apps (waydroid) ---
  # Runs Android in a LXC container against the Wayland compositor, so Android apps appear
  # as ordinary Hyprland windows. The image itself is not declarative: it is fetched once
  # with `sudo waydroid init -s GAPPS` (or -s VANILLA) after the first rebuild.
  virtualisation.waydroid.enable = true;

  # --- Containers (podman: rootless + docker-compatible) ---
  # The `docker` command can be used as an alias for podman (dockerCompat).
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true; # name resolution between containers
  };

  environment.systemPackages =
    with pkgs;
    [
      git
      vim
      curl
      wget
      sbctl # generate/enroll/verify Secure Boot keys (used for lanzaboote operation)
      keepAwake # `keep-awake [on [DURATION]|off|status]`, see the let block

      # Minimal set to make Hyprland usable from the start.
      # A full rice (keybinds/waybar config/wallpaper) is meant to be moved to home-manager's
      # wayland.windowManager.hyprland and gradually removed from here.
      ghostty # main terminal (config symlinked in home/hyprland.nix)
      kitty # fallback opened by Hyprland's stock SUPER+Q (home's $terminal is ghostty)
      wofi # app launcher (bound to SUPER+R etc.)
      wl-clipboard # clipboard (wl-copy / wl-paste)
      cliphist # clipboard history (integrates with wofi)
      hyprpolkitagent # polkit auth dialog (autostart in the hyprland config)
      grim # screenshot capture
      slurp # region selection (used with grim)
      brightnessctl # screen brightness
      playerctl # media keys

      # Agent CLIs (see the agentPkgs note at the top of the file)
      agentPkgs.claude-code
      agentPkgs.codex

      # Geek-oriented CLI
      comma # run an uninstalled command with `, <cmd>` (integrates with nix-index)
      distrobox # run another distro's userland on podman (mix of Arch/Ubuntu tools)
      lazydocker # TUI for podman/docker
      btop # system monitor
      nvtopPackages.intel # GPU monitor (Intel)

      # Hyprland QoL
      hyprpicker # color picker
      hyprshot # screenshot (window/region/screen)
      wlogout # power menu
      wl-gammarelay-rs # control color temperature (night light) via dbus
    ]
    # ArtCraft's pure-Rust Adobe-suite counterparts, same set as darwin. See pkgs/artcraft-apps.nix.
    ++ pkgs.callPackage ../pkgs/artcraft-apps.nix { };

  # Enable if you want to read/write the NTFS Windows partition (optional)
  # boot.supportedFilesystems = [ "ntfs" ];

  # The NixOS version at initial install. Once set, do not change it.
  system.stateVersion = "26.05";
}
