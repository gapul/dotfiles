{ pkgs, brewNix, ... }: {
  # host-independent base (nix cache / firewall / security / login hardening, etc.)
  # is consolidated in darwin-common.nix. Only daily-driver workstation-specific
  # settings live here.
  imports = [ ./darwin-common.nix ];

  # Expose brew-nix trial targets to nix-darwin's built-in Home Manager global pkgs too.
  nixpkgs.overlays = [ brewNix.overlays.default ];

  # macOS settings (GUI/peripheral-oriented. Only values verified via `defaults read` on the machine are declared)
  system.defaults = {
    dock = {
      autohide = true;
      show-recents = false;
      static-only = true;
      tilesize = 52;
      launchanim = false;
      minimize-to-application = true;
    };
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = false;
      FXPreferredViewStyle = "Nlsv";
      FXDefaultSearchScope = "SCcf";
      CreateDesktop = false;
    };
    trackpad = {
      Clicking = false;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };
  };

  # Only provide via Nix the Nerd Fonts that have no matching cask
  # (font-hackgen-nerd is HackGen, a different thing from Hack)
  # (font-jetbrains-mono-nerd-font is managed on the cask side)
  fonts.packages = with pkgs; [
    nerd-fonts.hack
    nerd-fonts.fira-code
    # sketchybar app icon font. Vendor v2.0.62 with Ghostty/Zen support.
    # Use the bundled ttf rather than the nixpkgs version to keep the version
    # in strict lockstep with plugins/icon_map.sh.
    (stdenvNoCC.mkDerivation {
      pname = "sketchybar-app-font";
      version = "2.0.68";
      src = ../../configs/fonts/sketchybar-app-font.ttf;
      dontUnpack = true;
      installPhase = ''
        install -Dm444 $src $out/share/fonts/truetype/sketchybar-app-font.ttf
      '';
    })
  ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall"; # auto-uninstall brews not declared (avoid zap since it deletes data)
      upgrade = false;
      # Disable REQUIRE_TAP_TRUST (defaulted to true in Homebrew 6.0) only during activation.
      # Prevents dependency formulae of unofficial taps (qmk/hid_bootloader_cli, etc.) from being
      # rejected and stalling the bundle.
      # All taps are declared and version-managed above, so the runtime trust check is redundant.
      extraEnv = {
        HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
      };
    };

    # Tap trust is handled in bulk via onActivation.extraEnv's HOMEBREW_NO_REQUIRE_TAP_TRUST=1.
    # (REQUIRE_TAP_TRUST defaulted to true in Homebrew 6.0. `trusted: true` on tap lines does not
    #  affect loading of dependency formulae, and manual `brew trust` is unusable since the bundle
    #  overwrites it every time. All taps are declared and version-managed below, so the activation-time
    #  check is turned off.)
    taps = [
      "chojs23/tap" # Concord (Discord TUI)
      "deskflow/tap"
      "felixkratz/formulae"
      "finnvoor/tools"
      "gerlero/openfoam"
      "gapul/kdeconnect" # fork of imshuhao/kdeconnect. Fixed the deprecated depends_on macos
      "lihaoyun6/tap" # QuickRecorder (screen recorder. Required since not in homebrew/cask)
      "nikitabobko/tap"
      "osx-cross/arm" # QMK toolchain dependency tap
      "osx-cross/avr" # QMK / Keyball AVR toolchain tap
      "qmk/qmk" # QMK CLI
      "voicevox/voicevox" # VOICEVOX official tap (required since not in homebrew/cask)
      "y3owk1n/tap" # cask distribution source for neru (full-screen keyboard navigation)

      # ─── Personal forks (gapul) — delete if you forked and don't need them ───
      "gapul/openutau"
      "gapul/azoo-key-skkserv"
      "gapul/keystats" # self-made keystroke analytics (cask)
      "gapul/puddle" # cask distribution tap for Puddle (self-built MIT fork of Plash)
      "gapul/armorpaint" # ArmorPaint source-build formula distribution tap (official is paid €16 → self-build for free full version)
      "gapul/inochi" # cask distribution tap for Inochi Creator (2D VTuber rigging) (not in homebrew/cask)
    ];

    # brew leaves
    # (starship / fzf / atuin / pipx excluded, migrated to home-manager / uv management)
    brews = [
      # ─── Languages / Package managers ───
      # deno: used as the runtime for nvim skkeleton(denops) + for decoding yt-dlp's JS challenge.
      # Currently a dependency of mpv/yt-dlp, but removing those would orphan and break skkeleton, so declare it explicitly.
      "deno"
      "swi-prolog" # Prolog (functional/logic programming lab, sessions 10-12)

      # ─── Keyboard firmware ───
      "qmk/qmk/qmk" # QMK CLI (Keyball firmware build/flash)
      "osx-cross/avr/avr-gcc@12" # AVR toolchain for Keyball (keg-only)

      # ─── wine helpers ───
      "winetricks" # helper for installing DLLs/components into wine prefix

      # ─── TUI utilities ───
      "chojs23/tap/concord" # Discord TUI (images/threads/voice support)
      "herdr" # AI coding agent multiplexer
      "wifitui" # wifi (kept on brew since nixpkgs is Linux-only)

      # ─── Network / Download / VPN ───
      "tailscale"
      "tor"
      "wireguard-tools" # wg-quick + wireguard-go (pulled in automatically) are the VPN engine
      "cloudflared" # Cloudflare tunnel
      "nextdns"
      "scrcpy" # Android mirror
      "tcpdump"
      "gnupg" # GPG (git commit signing / encrypted mail. sops uses age but GPG is separate)

      # ─── Documents / Fonts / Media ───
      "gstreamer"
      "mpv"
      "sox" # audio processing (rec / play / sox / soxi)
      "exiftool" # strip metadata (GPS/device info) from images/PDFs before sharing

      # ─── macOS specific CLI ───
      "mas" # App Store
      "blueutil" # Bluetooth
      "media-control" # media keys
      "terminal-notifier"
      "duti" # file associations
      "displayplacer" # sketchybar multi-display (promoted to homebrew/core, same v1.4.0)

      # ─── Status bar / Window decoration (felixkratz tap) ───
      "felixkratz/formulae/sketchybar"
      "felixkratz/formulae/borders" # launched from aerospace via exec-and-forget

      # ─── Transcription / other 3rd-party tap brews ───
      "finnvoor/tools/yap" # Japanese transcription

      # ─── Creative / graphics (source-build formula) ───
      # ArmorPaint (3D PBR texture painting / Substance Painter alternative). Official binary is paid €16
      # but self-build from zlib source for free full version. Current main is the iron/Kore self-contained
      # toolchain (no V8/haxe/node, Xcode only). It's a GUI app but a formula (source build), so it's on the brews side.
      # The .app lands in $(brew --prefix)/opt/armorpaint/ArmorPaint.app (not /Applications, unlike a cask).
      "gapul/armorpaint/armorpaint"
    ];

    # GUI applications (~100)
    casks = [
      # ─── Browsers ───
      "google-chrome"
      "tor-browser"
      "zen"

      # ─── PDF viewers ───
      # sioyek is an unsigned x86_64 cask (runs under Rosetta). If brew's default quarantine
      # is applied, Gatekeeper flags it as "damaged/malware" and it won't launch, so no_quarantine is required.
      {
        name = "sioyek";
        args = {
          no_quarantine = true;
        };
      } # lightweight PDF viewer with vim keybindings (zathura alternative, daily driver)
      "skim" # native SyncTeX viewer. Backup for TeX writing (integration later)

      # ─── Image viewers ───
      # qView is ad-hoc signed only (not notarized). With quarantine it gets rejected by
      # Gatekeeper and won't launch, so no_quarantine is required (same as sioyek).

      # ─── Communication & Sync ───
      "beeper"
      "kdeconnect"
      "localsend"
      "simplex"

      # ─── Window / Keyboard / Input ───
      "aerospace"
      "thaw" # menu bar management (maintenance fork of Ice. Upstream jordanbaird-ice stalled at 0.11.12/2024-10 and won't launch on macOS Tahoe → migrated to Tahoe-compatible Thaw on 2026-07-27. Ice settings are importable)
      "karabiner-elements"
      "macskk"
      "gapul/azoo-key-skkserv/azoo-key-skkserv" # skkserv for the azooKey conversion engine (gapul self-made tap)
      "y3owk1n/tap/neru" # mouse-free full-screen navigation (grid/hints/scroll. System-wide version of Vimium. shortcat superset)

      # ─── macOS utilities ───
      "gapul/puddle/puddle" # set any web page as desktop wallpaper (self-built MIT fork of Plash, Developer ID signed + notarized)
      "hammerspoon"
      "espanso"
      "maccy"
      "monitorcontrol"
      "qlmarkdown"
      "corelocationcli"

      # ─── Creative / VTuber ───
      # nijigenerate/nijiexpose: 2D VTuber puppet rigging + streaming runtime (Live2D alternative,
      # free/OSS). Community successor forks of Inochi Creator/Session on the nijilive puppet format;
      # active development moved here. Distribute the official mac builds via a self-made cask tap
      # (not in homebrew/cask, and nixpkgs only has the older Inochi2D). Currently v1.0.0-beta2.
      "gapul/inochi/nijigenerate" # rigging editor (Inochi Creator successor)
      "gapul/inochi/nijiexpose" # streaming runtime (Inochi Session successor)

      # ─── Privacy / Security ───
      # Objective-See (Patrick Wardle) suite — all free and notarized
      # blockblock overlaps with macOS Ventura+'s Background Task Management notifications, and
      # oversight overlaps with macOS's mic/camera-in-use indicators (menu bar dot +
      # Control Center), so both were removed (2026-07-28).
      # reikey gets muddied with false positives from our own event tap tools (Karabiner/Espanso/keebmouse/Hammerspoon)
      # and can be checked statically in the standard input-monitoring list, and taskexplorer can be
      # replaced with codesign / otool / vmmap / lsof, so both were removed (2026-07-28).
      # netiquette can be fully replaced with lsof -nP -i / nettop, and whatsyoursign with codesign -dvv /
      # spctl -a -vv, so both were removed (2026-07-28).
      "knockknock" # persistence scanner
      "lulu" # outbound firewall
      "ransomwhere" # ransomware (suspicious encryption behavior) detection
      # VPN / keys
      "mullvad-vpn" # no-log anonymous VPN (a separate layer from self-hosted WireGuard/Tailscale)
      "ente-auth"
      "keepassxc"
      "keyguard"
      "bitwarden" # Bitwarden official desktop app
      "secretive" # isolate SSH keys in the Secure Enclave with Touch ID approval per use (MIT/OSS). Moved the SSH agent off Bitwarden

      # ─── Network / Remote ───
      "tailscale-app"
      "rustdesk"

      # ─── Dev IDEs / Editors / SDK ───
      "claude-code"
      "ghostty"
      "zed"
      "android-studio"
      "flutter"
      "imhex"
      "trex"
      "deskflow"
      "codexbar" # show usage/limits of various AI coding vendors in the menu bar (bundles codexbar CLI, auto-linked into /opt/homebrew/bin)

      # ─── Creative — Design / 2D ───
      "affinity"
      "gimp"
      "krita"
      "inkscape"
      "scribus"
      "darktable"
      "rawtherapee"
      "digikam" # photo management (RAW development, tag management)
      "upscayl"
      "fontforge-app"
      "fontgoggles"
      "pika"
      "adobe-creative-cloud"
      "sf-symbols" # Apple SF Symbols catalog

      # ─── Creative — Audio / Music ───
      "audacity"
      "bitwig-studio"
      "cardinal"
      "cycling74-max"
      "mixxx"
      "musescore"
      "milkytracker"
      "native-access"
      "openutau"
      "pd"
      "reaper"
      "supercollider"
      "surge-xt" # synth standalone/plugin (.pkg cask)
      # zrythm was removed since it was a trial version (x64/Rosetta/can't save). Consolidated onto the
      # self-made full nix version (pkgs/zrythm-darwin, arm64-native, -O2). Installed via home.packages.
      "vcv-rack"
      "voicevox/voicevox/voicevox" # official tap only (not in homebrew/cask). Tap declaration required
      # self-made keystroke analytics. Developer ID signed + notarized, so it passes
      # Gatekeeper even with quarantine (no_quarantine not needed).
      "gapul/keystats/keystats"
      "blackhole-2ch" # virtual audio device to route system audio into OBS / DAW

      # ─── Creative — Video / Animation / Stream ───
      "obs"
      "lihaoyun6/tap/quickrecorder" # screen recorder (native ScreenCaptureKit, Tahoe-compatible). Switched from the old kap, which is Electron-based and stalled for ~1.7 years
      "gyroflow"
      "touchdesigner"
      "cavalry" # 2D motion graphics
      "opentoonz" # 2D animation (.pkg cask)

      # ─── 3D / CAD ───
      "blender"
      "freecad"
      "kicad"
      "librecad"
      "godot"
      "goxel"
      "material-maker"
      "openfoam"

      # ─── 3D Printing ───
      "bambu-studio"
      "orcaslicer"

      # ─── Games / Emulation ───
      "wine-stable" # WineHQ stable. Run Windows apps (used with winetricks)
      "epic-games"
      "heroic"
      "prismlauncher"
      "retroarch-metal"
      "steam"
      "playcover-community"

      # ─── Productivity / Notes / Reading ───
      "anki"
      "calibre"
      "obsidian"
      "libreoffice"
      "zotero"

      # ─── VM ───
      "utm"

      # ─── Fonts ───
      "font-hackgen-nerd"
      "font-jetbrains-mono-nerd-font"
      "font-sf-mono"

      # ─── Tracking / Misc ───
      "activitywatch"
      "gstreamer-runtime"
    ];

    masApps = {
      "DaVinci Resolve" = 571213070;
      "Xcode" = 497799835;
    };
  };
}
