{
  pkgs,
  brewNix,
  user,
  ...
}:
{
  # host-independent base (nix cache / firewall / security / login hardening, etc.)
  # is consolidated in darwin-common.nix. Only daily-driver workstation-specific
  # settings live here.
  imports = [ ./darwin-common.nix ];

  # Expose brew-nix trial targets to nix-darwin's built-in Home Manager global pkgs too.
  nixpkgs.overlays = [ brewNix.overlays.default ];

  # macOS settings (GUI/peripheral-oriented. Only values verified via `defaults read` on the machine are declared)
  system.defaults = {
    dock = {
      # Keep the Dock as close to empty as it gets: no pinned apps, no pinned folders/stacks.
      # Combined with static-only below, only what is actually running shows up (Finder and Trash
      # are permanent fixtures macOS does not let you remove).
      persistent-apps = [ ];
      persistent-others = [ ];
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
    # "Displays have separate Spaces" ON (false = displays don't span). Gives the
    # external display its own menu bar so OmniWM reserves the top strip and SketchyBar
    # stops overlapping tiled windows there. Takes effect on next logout.
    spaces.spans-displays = false;

    # Screenshots land in ~/Downloads. The Desktop is the macOS default, but desktop icons are
    # hidden here (finder.CreateDesktop = false), so shots would pile up somewhere invisible.
    screencapture.location = "/Users/${user.username}/Downloads";

    # Default keyboard shortcuts that are deliberately off. These were set by hand in System
    # Settings and never declared, which mattered most for 64/65: Ghostty's Quick Terminal binds
    # cmd+space, so Spotlight has to release it or the two fight and Ghostty loses.
    # Writing a hotkey id replaces its whole entry, so the original parameters are reproduced
    # verbatim — an entry with no parameters is disabled but also unrecoverable from the GUI.
    CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
      # Spotlight search / Finder search window (cmd+space, cmd+alt+space)
      "64" = {
        enabled = false;
        value = {
          parameters = [
            32
            49
            1048576
          ];
          type = "standard";
        };
      };
      "65" = {
        enabled = false;
        value = {
          parameters = [
            32
            49
            1572864
          ];
          type = "standard";
        };
      };
      # Mission Control / Application windows (ctrl+up, ctrl+down) — OmniWM owns this
      "32" = {
        enabled = false;
        value = {
          parameters = [
            65535
            126
            8650752
          ];
          type = "standard";
        };
      };
      "33" = {
        enabled = false;
        value = {
          parameters = [
            65535
            125
            8650752
          ];
          type = "standard";
        };
      };
      # Switch to Desktop 1 / 2 (ctrl+1, ctrl+2) — OmniWM owns workspace switching
      "118" = {
        enabled = false;
        value = {
          parameters = [
            49
            18
            524288
          ];
          type = "standard";
        };
      };
      "119" = {
        enabled = false;
        value = {
          parameters = [
            50
            19
            524288
          ];
          type = "standard";
        };
      };
    };
  };

  # Machine identity. macmini declares its own; this one had only whatever the migration left
  # behind, so the current values are written down as-is rather than renamed.
  networking = {
    computerName = "MacBook Mini";
    hostName = "MacBook-Mini";
    localHostName = "MacBook-Mini";
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
      version = "2.0.71";
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
      "barutsrb/tap" # OmniWM (Niri/Hyprland-inspired tiling WM, main WM since 2026-08)
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
    #
    # ─── Package manager priority: nix > homebrew > anything else ───
    # Nix is the default. A formula only belongs here if it has one of these reasons, and the reason
    # must be written on its line — an entry with no reason is a migration candidate, not a decision:
    #   (a) not in nixpkgs at all, or nixpkgs marks it unsupported/broken on aarch64-darwin
    #   (b) it needs a brew service / root launchd daemon, or a keg-only toolchain
    #   (c) it's the pair of a cask (same version has to come from the same source)
    # GUI apps stay in casks: nixpkgs darwin builds are mostly unbundled/unsigned and don't get
    # Spotlight, TCC prompts or Launch Services registration.
    # Caveat: /opt/homebrew/bin sits ahead of the nix profile in PATH (brew shellenv), so if the same
    # binary exists on both sides brew wins. Don't leave duplicates around.
    brews = [
      # ─── Languages / Package managers ───
      # (b) already pulled in as an mpv/yt-dlp dependency, so a nix deno would just be a second copy.
      # Declared explicitly so removing mpv doesn't orphan it and break nvim skkeleton (denops runtime).
      "deno"

      # ─── Keyboard firmware ───
      "qmk/qmk/qmk" # (b) has to match the keg-only avr toolchain below; nixpkgs qmk pulls its own
      "osx-cross/avr/avr-gcc@12" # (b) keg-only AVR toolchain for Keyball

      # ─── wine helpers ───
      "winetricks" # (c) drives the wine-stable cask's prefix; nix winetricks would pull nix wine

      # ─── TUI utilities ───
      # TODO(concord): held at 2.4.8 via `brew pin chojs23/tap/concord`. 2.5.0+ can't install on
      # macOS — the cargo-dist-generated formula requires alsa-lib/pipewire (Linux-only, no macOS
      # bottle) unconditionally. Root cause is upstream `dist` not gating Homebrew run-deps per
      # target (concord's dist config already restricts them to Linux, but dist ignores it in the
      # formula; not fixed as of dist 0.32.0). The pin is imperative, so a fresh machine needs
      # `brew pin chojs23/tap/concord` re-run. Retry `brew unpin ... && brew upgrade concord` after
      # new releases; real fix is a bug report to axodotdev/cargo-dist. See PR #119 for the
      # `just maintain` hardening that keeps this pin from aborting upgrades.
      "chojs23/tap/concord" # (a) Discord TUI. tap-only, not in nixpkgs
      "herdr" # (a) AI coding agent multiplexer. not in nixpkgs
      "wifitui" # (a) wifi TUI. nixpkgs marks it Linux-only

      # ─── Network / Download / VPN ───
      # These are all daemons: brew wires up the launchd plist (`brew services`) and the mac
      # expects one system-wide instance, so a per-user nix copy would be the wrong shape.
      "tailscale" # (b,c) tailnet daemon, paired with the tailscale-app cask
      "tor" # (b) SOCKS daemon via brew services
      "wireguard-tools" # (b) wg-quick + wireguard-go run as a root VPN engine
      "cloudflared" # (b) Cloudflare tunnel daemon
      "nextdns" # (b) DNS-over-HTTPS daemon (installs its own resolver config)

      # ─── Documents / Fonts / Media ───
      "gstreamer" # (a) nixpkgs gst_all_1 doesn't support aarch64-darwin
      "mpv" # (a) nixpkgs mpv doesn't support aarch64-darwin

      # ─── macOS specific CLI ───
      "media-control" # (a) media keys. not in nixpkgs
      "displayplacer" # (a) sketchybar multi-display. not in nixpkgs

      # (Xcode itself is managed by xcodes, which moved to nix — see home/darwin.nix. aria2, which
      #  xcodes uses for the parallel .xip download, was already declared in home/workstation.nix.)

      # ─── Status bar / Window decoration (felixkratz tap) ───
      "felixkratz/formulae/sketchybar" # (b) runs as a brew service (homebrew.mxcl.sketchybar)
      "felixkratz/formulae/borders" # (a) tap-only. launched via launchd agent (home/darwin-chrome.nix); OmniWM has no exec action

      # ─── Transcription / other 3rd-party tap brews ───
      "finnvoor/tools/yap" # (a) Japanese transcription. tap-only, not in nixpkgs

      # ─── Creative / graphics (source-build formula) ───
      # ArmorPaint (3D PBR texture painting / Substance Painter alternative). Official binary is paid €16
      # but self-build from zlib source for free full version. Current main is the iron/Kore self-contained
      # toolchain (no V8/haxe/node, Xcode only). It's a GUI app but a formula (source build), so it's on the brews side.
      # The .app lands in $(brew --prefix)/opt/armorpaint/ArmorPaint.app (not /Applications, unlike a cask).
      "gapul/armorpaint/armorpaint" # (a) self-made tap, not in nixpkgs
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
      # OmniWM: main tiling WM (replaced aerospace 2026-08, trial concluded). Hotkeys are
      # GUI-configured (settings.toml schema is undocumented), so ~/.config/omniwm is
      # app-managed, not nix-generated. Hotkeys mirror the old aerospace hyper band (Cmd+Ctrl+Alt).
      "omniwm"
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

      # ─── iOS sideloading ───
      # Pairs the iPhone for SideStore (self-hosted anisette; see the ios-selfbuild notes).
      # Was a hand-installed /Applications/AltServer.app until 2026-08 — the cask ships the same
      # version, so declaring it just puts it back under management.
      "altserver"

      # ─── Dev IDEs / Editors / SDK ───
      "claude-code"
      "ghostty"
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
      # Nothing is managed via mas anymore.
      # - Xcode moved to xcodes (see the "Xcode toolchain" brews above).
      # - DaVinci Resolve is intentionally NOT managed here: the Mac App Store build is
      #   sandboxed (no external scripting/Python, limited 3rd-party OpenFX/VST, no hardware
      #   control panels). Install it manually from the Blackmagic support page instead.
    };
  };
}
