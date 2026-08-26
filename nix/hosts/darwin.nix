{
  lib,
  pkgs,
  brewNix,
  nixpkgsUnstable,
  user,
  ...
}:
let
  unstablePkgs = import ../lib/unstable-pkgs.nix {
    inherit nixpkgsUnstable;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
in
{
  # host-independent base (nix cache / firewall / security / login hardening, etc.)
  # is consolidated in darwin-common.nix. Only daily-driver workstation-specific
  # settings live here.
  imports = [
    ./darwin-common.nix
    ../modules/authorized-keys.nix
  ];

  # /etc/zshrc's last spawn. `brew shellenv` costs ~16ms per shell and everything it produced
  # is declared in home/darwin.nix instead: the PATH half was already redundant (PATH comes out
  # byte-identical in login and non-login shells without it), and the rest is sessionVariables
  # plus one fpath entry. Scoped to this host — the mini keeps its own call in home/macmini.nix.
  programs.zsh.interactiveShellInit = lib.mkForce "";

  # Expose brew-nix trial targets to nix-darwin's built-in Home Manager global pkgs too.
  nixpkgs.overlays = [ brewNix.overlays.default ];

  # Anything shipping an .app belongs here rather than in home.packages: home-manager can only
  # reach ~/Applications, while nix-darwin copies these into /Applications/Nix Apps, where Finder
  # lists them and Spotlight indexes them. Everything without a bundle stays in home.packages.
  environment.systemPackages = [
    pkgs.brewCasks.qview # brew-nix test target: lightweight image viewer distributed as a simple .app
    # ─── Creative: official is paid but nixpkgs source builds give a free full version ───
    # Unavailable/broken on 26.05-darwin, so from unstablePkgs (nixos-unstable, with allowUnfree).
    unstablePkgs.fritzing # PCB/circuit design CAD (official DL is paid. for the ESP32 project). cached, so instant
    unstablePkgs.ardour # DAW (official binary is pay-what-you-want. free via source build). cached, so instant
    unstablePkgs.aseprite # pixel-art editor (official $20. source-available/self-built is free full)
    # VRoid Studio (VRM character modelling): no nixpkgs package and no cask, so the official
    # macOS dmg is repackaged. See pkgs/vroid-studio.nix - the download URL carries a token
    # that has to be re-read from vroid.com on every version bump.
    (pkgs.callPackage ../pkgs/vroid-studio.nix { })
    # AivisSpeech Engine (headless TTS, VOICEVOX-compatible API): no nixpkgs
    # package and no cask. Engine only - the desktop app is not used, and voice
    # models are runtime data the engine fetches itself. See pkgs/aivisspeech-engine.nix.
    (pkgs.callPackage ../pkgs/aivisspeech-engine.nix { })
    # AivisSpeech desktop editor (GUI). Bundles its own engine copy, but scripts
    # keep using the newer headless engine above; both share the model dir.
    (pkgs.callPackage ../pkgs/aivisspeech.nix { })
  ];

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

    # Third-party app preferences that used to be `defaults write` loops in home.activation.
    # CustomUserPreferences is the same mechanism declared instead of scripted, and only the keys
    # listed here are touched — the apps' other settings are left alone, which is what the old
    # "surgically write only these keys" comments were asking for.
    # Skim: VimTeX integration. Inverse search (click PDF -> jump to line in Neovim) + reload on save.
    CustomUserPreferences."net.sourceforge.skim-app.skim" = {
      SKTeXEditorPreset = "Custom";
      SKTeXEditorCommand = "${pkgs.neovim}/bin/nvim";
      SKTeXEditorArguments = "--headless -c \"VimtexInverseSearch %line '%file'\"";
      SKAutoReloadFileUpdate = true;
      SKAutoCheckFileUpdate = true;
    };
    # Puddle (dynamic wallpaper; self-built MIT fork of Plash). Its websites and security-scoped
    # bookmarks live on the app side, so only these three behavior keys are enforced.
    # (extendPuddleBelowMenuBar keeps its key name in Puddle for compatibility.)
    CustomUserPreferences."net.gapul.Puddle" = {
      deactivateOnBattery = true;
      extendPuddleBelowMenuBar = true;
      showOnAllSpaces = true;
    };

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
      # Select next source in Input menu (ctrl+opt+space) — OmniWM's command palette owns this.
      # macOS documents this chord for input switching, so both fired together and OmniWM's own
      # health check flagged it. Only 61 is disabled: 60 (ctrl+space, "select the previous input
      # source") is untouched, so switching input sources still has a shortcut.
      "61" = {
        enabled = false;
        value = {
          parameters = [
            32
            49
            786432
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
    # sketchybar app icon font. Pinned to the release plugins/icon_map.sh came from — nixpkgs
    # is on an older one, and a font and a map that disagree draw the wrong glyphs.
    # Fetched rather than committed: the ttf is 280KB of someone else's build.
    (stdenvNoCC.mkDerivation {
      pname = "sketchybar-app-font";
      version = "2.0.76";
      src = fetchurl {
        url = "https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v2.0.76/sketchybar-app-font.ttf";
        hash = "sha256-KTkSC9ajasTtNJfuguN1IKXaAtR77k6x8I/J65YbLEI=";
      };
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
      "gapul/tap" # 雑多な自作物の cask 置き場 (いまは keebmouse。ソース repo は private なので成果物だけここ)
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
      "wifitui" # (a) wifi TUI. nixpkgs marks it Linux-only

      # ─── Network / Download / VPN ───
      # These are all daemons: brew wires up the launchd plist (`brew services`) and the mac
      # expects one system-wide instance, so a per-user nix copy would be the wrong shape.
      # No "tailscale" formula: the tailscale-app cask already ships both the daemon and a CLI at
      # /usr/local/bin/tailscale. The formula's brew service was never started, and its own CLI sits
      # earlier in PATH, so every `tailscale` call went through a binary built from a different
      # source than the running daemon ("client version != tailscaled server version").
      "tor" # (b) SOCKS daemon via brew services
      "wireguard-tools" # (b) wg-quick + wireguard-go run as a root VPN engine
      "cloudflared" # (b) Cloudflare tunnel daemon
      "nextdns" # (b) DNS-over-HTTPS daemon (installs its own resolver config)

      # ─── Documents / Fonts / Media ───
      "gstreamer" # (a) nixpkgs gst_all_1 doesn't support aarch64-darwin
      "mpv" # (a) nixpkgs mpv doesn't support aarch64-darwin
      # 3D model previews in yazi (configs/cli/yazi/plugins/model.yazi). nixpkgs f3d can't build on
      # aarch64-darwin: its openusd dependency fails, taking f3d down with it.
      "f3d" # (a) headless 3D renderer

      # ─── macOS specific CLI ───
      "media-control" # (a) media keys. not in nixpkgs
      "displayplacer" # (a) sketchybar multi-display. not in nixpkgs

      # (Xcode itself is managed by xcodes, which moved to nix — see home/darwin.nix. aria2, which
      #  xcodes uses for the parallel .xip download, was already declared in home/workstation.nix.)

      # ─── Status bar (felixkratz tap) ───
      # (borders/JankyBorders was dropped 2026-08: OmniWM draws its own active-window border, so the
      #  resident daemon was 174MB of duplicate decoration.)
      "felixkratz/formulae/sketchybar" # (a) tap-only. launched via launchd agent (home/darwin-chrome.nix)

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
      # Dropped proprietary Beeper (not in active use) for Element on the self-hosted Matrix
      # (@gapul:gapul.net; Discord/Telegram bridged in homelab/matrix.nix).
      "element"
      "kdeconnect"
      "localsend"
      "simplex"

      # ─── Window / Keyboard / Input ───
      # OmniWM: main tiling WM (replaced aerospace 2026-08, trial concluded). Hotkeys are
      # GUI-configured (settings.toml schema is undocumented), so ~/.config/omniwm is
      # app-managed, not nix-generated. Hotkeys mirror the old aerospace hyper band (Cmd+Ctrl+Alt).
      # PINNED BY HAND to v0.5.9 (2026-08-10): 0.5.10 regressed floating-panel focus, so OmniWM
      # yanks focus off Ghostty's quick terminal and quick-terminal-autohide closes it within
      # 100ms (upstream BarutSRB/OmniWM#559, fixed on main 08-09 but unreleased as of v0.6.0).
      # onActivation.upgrade = false keeps it, but a manual `brew upgrade --cask` undoes it.
      # Once v0.6.1 ships: `brew reinstall omniwm`, verify cmd+space, and drop this note.
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
      # blockblock was installed by hand before this list existed, so it was the one
      # Objective-See tool sitting outside the declaration (found 2026-08-14 while auditing
      # /Applications against brew and nix). The cask is on the same 2.5.0 that is already
      # installed, and like ransomwhere it is an Installer-artifact cask, so brew just runs
      # the same installer the manual install did.
      "blockblock" # persistence attempt blocker (alerts when something installs itself to run at login)
      "knockknock" # persistence scanner
      "lulu" # outbound firewall
      "ransomwhere" # ransomware (suspicious encryption behavior) detection
      # VPN / keys
      "mullvad-vpn" # no-log anonymous VPN (a separate layer from self-hosted WireGuard/Tailscale)
      "ente-auth"
      "keepassxc"
      "keyguard"
      "bitwarden" # Bitwarden official desktop app

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
      # native-access removed: replaced by the unofficial CLI (gapul/na-cli, on PATH via
      # home/darwin.nix). NTKDaemon runs headless via launchd; keep the cask out so a rebuild
      # doesn't reinstall the GUI and re-claim the native-access:// scheme.
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
      # self-made keyboard-driven pointer (Hyper+Shift+G). Was a hand-run scripts/bundle.sh into
      # /Applications — the last thing on this machine that was installed by hand. /Applications
      # rather than the nix store on purpose: it needs Accessibility, and TCC keys the grant to
      # the path and the signature, so a store path would mean re-approving it every rebuild.
      # The resident agent stays in launchd.agents.keebmouse.
      "gapul/tap/keebmouse"
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
      # Orca alone covers the Bambu A1 mini: it installs Bambu's network plugin
      # itself, so send / camera / temps / jog / firmware update all live here.
      # Reinstall bambu-studio temporarily if a cloud-side problem needs an
      # "authorized software" reference point.
      "orcaslicer"

      # ─── Games / Emulation ───
      "wine-stable" # WineHQ stable. Run Windows apps (used with winetricks)
      "heroic" # Epic/GOG/Amazon launcher (FOSS). Replaces the proprietary Epic Games launcher; pairs with legendary-gl (see workstation.nix)
      "prismlauncher"
      "retroarch-metal"
      "steam"
      # ispc の Sunshine につなぐクライアント (Windows 専用のものを母艦から触る)
      "moonlight"
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
