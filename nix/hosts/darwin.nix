{
  lib,
  pkgs,
  brewNix,
  cherri,
  mocopiMac,
  nixpkgsAgents,
  nixpkgsUnstable,
  user,
  includeManualSources ? true,
  ...
}:
let
  agentPkgs = import ../lib/unstable-pkgs.nix {
    nixpkgsUnstable = nixpkgsAgents;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  unstablePkgs = import ../lib/unstable-pkgs.nix {
    inherit nixpkgsUnstable;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  terminalBrowser = pkgs.callPackage ../pkgs/terminal-browser.nix { };
  tahoma2d = pkgs.callPackage ../pkgs/tahoma2d.nix {
    stuffDir = "/Users/${user.username}/Library/Application Support/Tahoma2D/Tahoma2D_stuff";
  };
in
{
  # host-independent base (nix cache / firewall / security / login hardening, etc.)
  # is consolidated in darwin-common.nix. Only daily-driver workstation-specific
  # settings live here.
  imports = [
    ./darwin-common.nix
    ../modules/authorized-keys.nix
    ../modules/darwin-chrome-policy.nix
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
    # brew-nix: Homebrew casks as nix derivations, so the version is decided by flake.lock
    # instead of by whenever `just maintain` last ran `brew upgrade --cask --greedy`.
    # Casks live here rather than in homebrew.casks only when all of the following hold, because
    # each one is a way this breaks:
    #   - the artifact is a plain .app. A .pkg has to land in /Library (input methods, audio
    #    drivers, VPN daemons), which a store copy cannot do.
    #   - the cask is in homebrew/cask. brew-api mirrors the official API only, so nothing from
    #     a third-party tap (omniwm, puddle, neru, keystats, … — 14 of them here) can come from it.
    #   - upstream ships a hash. Six casks here are `no_check`, and those are the self-updating
    #     ones (chrome, steam) where a pinned hash would go stale anyway.
    #   - the app does not update itself, does not want TCC permissions, and is not a login item.
    #     A login item is registered by /Applications path, and this moves the bundle to
    #     /Applications/Nix Apps.
    pkgs.brewCasks.qview # lightweight image viewer, the original trial target
    # keebmouse: self-made. Dropped the cask and made it a nix package that pulls in the signed release.
    # What breaks TCC is not "placing it via nix" but ad-hoc signing whose cdhash changes on every
    # build; this ships the Developer ID-signed bundle as is, so permissions survive version bumps.
    # The resident agent is launchd.agents.keebmouse (modules/home/darwin-chrome.nix).
    # OmniWM: the main tiling WM. Dropped the cask and pulls in the signed release (history in
    # pkgs/omniwm.nix). It is in systemPackages for where omniwmctl lands — /run/current-system/sw/bin,
    # a fixed path independent of version and username, so scripts in configs can hardcode it.
    (pkgs.callPackage ../pkgs/omniwm.nix { })
    # KDE Connect: phone integration. Dropped the cask from my own tap and pulls in the signed dmg
    # (history in pkgs/kdeconnect.nix). The cask used `sha256 :no_check` and so verified nothing, and
    # the pinned CI build had vanished from the CDN, so a new machine got a 404.
    (pkgs.callPackage ../pkgs/kdeconnect.nix { })
    # terminal-browser: a real browser that runs inside the terminal. The point is the agent side more
    # than browsing: `terminal-browser action` is an agent-facing CLI against the open browser.
    # It lets an agent touch the web without the Claude in Chrome extension and without a real window.
    # Upstream self-updates via a curl | bash installer, so it lives on the declarative side to pin the version.
    terminalBrowser
    # agent-browser: the agent-facing browser CLI bundled with terminal-browser. It sits inside libexec
    # and is not on PATH, so expose it here. Standalone, headless, and runs without opening a pane.
    # This is the agent's default path — it represents a page in 200-400 tokens, an order of magnitude
    # cheaper than piling the accessibility tree into context every turn over MCP (upstream measured
    # 114k vs 27k). Its version always matches terminal-browser itself.
    (pkgs.writeShellScriptBin "agent-browser" ''
      exec ${terminalBrowser}/libexec/terminal-browser/agent-browser/bin/agent-browser "$@"
    '')
    # playwright-test: a wrapper started only when cross-browser checks are needed. Only Playwright can
    # test on Firefox and WebKit, which agent-browser cannot, so it stays. But it no longer runs
    # resident (history in modules/home/darwin-services.nix). The old resident one hung off an existing
    # Chromium via --cdp-endpoint, so it never reached Firefox or WebKit in the first place.
    (pkgs.writeShellScriptBin "playwright-test" ''
      browser="''${1:-chromium}"
      port="''${2:-8932}"
      echo "playwright-mcp: $browser on http://localhost:$port/mcp (Ctrl-C to stop)" >&2
      export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
      exec ${lib.getExe agentPkgs.playwright-mcp} \
        --browser "$browser" --port "$port" \
        --output-dir "$HOME/tmp/playwright-test"
    '')
    # node: needed to run playwright-mcp. The node held by pnpm's global store had become a broken
    # link (~/Library/pnpm/bin/node → a store path that was gone), which is why the former playwright
    # agent died with "exec: node: not found". The runtime is taken out of pnpm's hands and held
    # declaratively.
    pkgs.nodejs
    # codex: moves what its own installer put in ~/.local/bin to the declaration. It is in systemPackages
    # rather than home.packages because of PATH order: /run/current-system/sw/bin comes before
    # ~/.local/bin. On the profile side the manually installed copy would win.
    agentPkgs.codex
    agentPkgs.claude-code
    agentPkgs.opencode
    # ─── moved off Homebrew (2026-09-15): same app, same data dirs, nothing to re-set up ───
    # Upstream's signed release carried over as-is, so TCC grants and entitlements survive:
    pkgs.upscayl
    # Not obsidian / monitorcontrol: nixpkgs' repack breaks the bundle seal and drops the Team ID
    # (`codesign -v`: "code has no resources but signature indicates they must be present"), so
    # MonitorControl would lose Accessibility and Obsidian its Keychain ACLs. Not maccy either:
    # nixpkgs trails the cask (2.7.0 vs 2.7.1) and the gap is freeze/crash fixes. They stay casks.
    # Built from source (ad-hoc signed), which is fine for apps that ask for no TCC permission:
    pkgs.prismlauncher # instances stay in ~/Library/Application Support/PrismLauncher
    agentPkgs.zotero # 10.x like the cask was; stable is still on 9.x
    # CLI. unstable for the fast-moving ones so they don't fall behind what brew had.
    agentPkgs.deno # denops runtime for nvim skkeleton
    agentPkgs.cloudflared
    pkgs.tor
    pkgs.wireguard-tools
    (pkgs.callPackage ../pkgs/keebmouse.nix { })
    # Puddle / keystats: self-made. Like keebmouse, dropped the cask and pulls in the signed release.
    # This lets both taps for self-made things (gapul/puddle, gapul/keystats) be folded.
    (pkgs.callPackage ../pkgs/puddle.nix { })
    (pkgs.callPackage ../pkgs/keystats.nix { })
    # mocopi: self-made. The source stays a private repo, so the flake input is fetched via git+ssh
    # (mocopi-mac in flake.nix). Putting it here lands it in /Applications/Nix Apps, so the manual
    # `nix build && cp -R result/Applications/mocopi.app ~/Applications/` from the README is not needed.
    # Being a .app matters: a standalone bundle can hold its own Bluetooth permission, so it does not
    # borrow the permissions of the terminal that launched it (see the comment in mocopi-mac's flake.nix).
    mocopiMac.packages.${pkgs.stdenv.hostPlatform.system}.default
    # Compiles Shortcuts from code (see cherri in flake.nix). The source is
    # personal-tools/shortcuts; the output is signed and imported onto the device.
    cherri.packages.${pkgs.stdenv.hostPlatform.system}.default
    # VOICEVOX: was the reason a fork of the upstream Homebrew tap existed at all — upstream is
    # stuck at 0.25.1 with a dead autobump, so the fork carried 0.25.2 by hand. nixpkgs packages
    # the same 0.25.2 and builds on aarch64-darwin, so the fork, the tap and the "switch back once
    # upstream catches up" note all go away together. The editor alone would be useless; the
    # engine comes with it (voicevox-engine is a runtime reference, wired by nixpkgs'
    # hardcode-paths patch) where the cask bundled it inside the .app.
    pkgs.voicevox
    pkgs.brewCasks.audacity
    pkgs.brewCasks.fontgoggles
    pkgs.brewCasks.goxel
    pkgs.brewCasks.gyroflow
    pkgs.imhex
    pkgs.librecad
    pkgs.brewCasks.material-maker
    pkgs.brewCasks.milkytracker
    pkgs.brewCasks.mixxx
    pkgs.brewCasks.anki
    pkgs.brewCasks.keyguard
    pkgs.brewCasks.knockknock # persistence scanner (Objective-See). Needs Full Disk Access re-granted on first run
    pkgs.brewCasks.localsend
    # Scribus carries two broken symlinks to PrivateHeaders in its bundled Python.framework, and
    # nixpkgs' noBrokenSymlinks fixup fails the build over them. The contents are upstream's
    # distribution as is and only unused header references are broken, so the check is disabled instead.
    (pkgs.brewCasks.scribus.overrideAttrs (_: {
      dontCheckForBrokenSymlinks = true;
    }))
    pkgs.brewCasks.supercollider
    # Sonic Pi: live-coded instrument (Ruby DSL, OSC in, MIDI out to the IAC bus -> Bitwig).
    # The agent-side counterpart to SuperCollider: a few lines make sound, and code can be
    # pushed into the running app. nixpkgs' sonic-pi is linux-only, hence the cask.
    pkgs.brewCasks.sonic-pi
    # MeshLab: mesh cleanup/decimation for the scan and VRM work. meshlabserver is gone since
    # 2020.x; scripting is pymeshlab (pymeshlab-python in home/workstation.nix). Ships meshlab.app.
    pkgs.meshlab
    # OpenSCAD: code-first CAD, the agent-written side of FreeCAD. -unstable is the maintained
    # branch (2021.01 stable predates manifold/lazy-union); ships OpenSCAD.app and a CLI named
    # openscad-unstable, so `openscad` below is the name everything else expects. From
    # nixos-unstable: 26.05's snapshot wants manifold built from source, unstable's is cached.
    unstablePkgs.openscad-unstable
    # (not lib.getExe: nixpkgs' meta.mainProgram says "openscad" but the file is openscad-unstable)
    (pkgs.writeShellScriptBin "openscad" ''exec ${unstablePkgs.openscad-unstable}/bin/openscad-unstable "$@"'')
    pkgs.brewCasks.trex # Screen OCR. Screen Recording TCC must be re-granted
    # ─── Emulation ───
    # The Pokémon RNG/breeding work runs here rather than on hardware: frame-level control and a
    # debugger are what the manipulation needs, and neither exists on a real console. The 3DS side
    # still requires system files and AES keys dumped from an own CFW'd console — none of these
    # ship Nintendo code. All FOSS.
    # GB/GBC/GBA/DS run inside RetroArch (retroarch-metal in homebrew.casks below) with the
    # nixpkgs libretro cores declared in home/darwin.nix - same engines as the standalone
    # SameBoy / mGBA / melonDS apps, one frontend, and a CLI + network command interface that
    # the standalone apps never had. The standalone DeSmuME / mGBA / SameBoy apps went 2026-09-17;
    # nothing had been saved in any of them. melonDS stays as a standalone only for Pal Park
    # (Slot-2 GBA cart, which the libretro core makes awkward) and can go once that is done.
    # Azahar and melonDS come from nixpkgs (Azahar has no cask; melonDS builds natively and cached).
    # 3DS. Citra successor (Citra and Lime3DS are both discontinued). No usable libretro core yet.
    #
    # nixpkgs' 2125.1.2 segfaults the moment a game boots on macOS 26+: with MoltenVK it enables
    # VK_EXT_tooling_info and then calls getToolPropertiesEXT, a function pointer MoltenVK does
    # not expose. Upstream fixed it in #2149 (in 2126.1.2), but 2126.1.2 does not build on darwin
    # in nixpkgs yet (it looks for a bundled libMoltenVK.dylib). So carry #2149 on 2125.1.2, minus
    # its MoltenVK version bump, which only affects the upstream-bundled copy. The Metal layer
    # helper it adds references CAMetalLayer, which upstream links through that bundled
    # MoltenVK; here QuartzCore has to be linked explicitly. Once nixpkgs ships a darwin build of
    # 2126.1.2 or later the patch no longer applies and the build fails - drop this override then.
    (pkgs.azahar.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (pkgs.fetchpatch {
          url = "https://github.com/azahar-emu/azahar/commit/04f3a93854bf2602f2fa18123d9e47cfc77ba708.patch";
          hash = "sha256-V+2XdYkSBJeaCd1YzTbBefsyT7BbfRaL/oJ2LEknSCM=";
          excludes = [ "CMakeModules/DownloadExternals.cmake" ];
        })
      ];
      env = (old.env or { }) // {
        NIX_LDFLAGS = "-framework QuartzCore";
      };
    }))
    pkgs.melonds # DS standalone. Slot-2 GBA cart support, so Pal Park (gen3 -> gen4) works
    # Cinny: a Matrix client that renders custom image reactions (MSC4027) and emoji packs, which
    # Element Desktop still shows as raw mxc URLs. Used to view LINE reaction icons / stickers that
    # Element can't. Ships Cinny.app, so nix-darwin surfaces it under /Applications/Nix Apps.
    pkgs.cinny-desktop
    # ─── Creative: official is paid but nixpkgs source builds give a free full version ───
    # Unavailable/broken on 26.05-darwin, so from unstablePkgs (nixos-unstable, with allowUnfree).
    unstablePkgs.fritzing # PCB/circuit design CAD (official DL is paid. for the ESP32 project). cached, so instant
    # DAW (official binary is pay-what-you-want. free via source build). cached, so instant.
    # Wrapped: the nixpkgs bundle links libvamp-*.so by bare name and nothing in it starts
    # (GUI or the ardour9-lua/export CLIs) until the load commands are repaired. See pkgs/.
    (unstablePkgs.callPackage ../pkgs/ardour-darwin-vamp-fix.nix { })
    unstablePkgs.aseprite # pixel-art editor (official $20. source-available/self-built is free full)
    # AivisSpeech's engine and models live on the always-on Mac mini.  This
    # workstation calls its VOICEVOX-compatible API over Tailscale instead of
    # carrying a second engine/model cache locally.
    # OrcaSlicer: the fork that can still start a print on a Bambu printer. Stock Orca
    # only exports, since Bambu's Authorization Control ignores the print command from
    # anything but Bambu Connect, so the stock cask was dropped (2026-10-01) and this is
    # the only Orca. See pkgs/orcaslicer-bambulab.nix.
    (pkgs.callPackage ../pkgs/orcaslicer-bambulab.nix { })
    # Headitude: AirPods head orientation -> OSC. A head-rotation source that keeps
    # working while the face is out of the camera frame. No nixpkgs package and no
    # cask, so the official release zip is repackaged. See pkgs/headitude.nix.
    (pkgs.callPackage ../pkgs/headitude.nix { })
    # SlimeVR Server: full-body tracking receiver, used here with mocopi's SlimeVR
    # mode rather than SlimeVR's own trackers. nixpkgs' slimevr-server is
    # `broken = isDarwin` and headless-only, so the official dmg is repackaged.
    # See pkgs/slimevr-server.nix.
    (pkgs.callPackage ../pkgs/slimevr-server.nix { })
  ]
  ++ lib.optionals includeManualSources [
    # AquesTalkPlayer: the yukkuri voices, with a headless wav-out CLI. The download is
    # Turnstile-gated, so the DMG has to be added to the store by hand.
    (pkgs.callPackage ../pkgs/aquestalkplayer.nix { })
    # Touch ID helper for the ask broker. Its signed artifact comes from a private release
    # and is likewise added to the store by hand.
    (pkgs.callPackage ../pkgs/askapprove.nix { })
  ]
  ++ [
    # Manual-source packages are inserted immediately before this package when
    # includeManualSources is true. CI cannot fetch them, so the PR-only Darwin
    # configuration disables them without changing the deployed workstation.
    # Open JTalk for the yukkuri engine's reading/accent analysis, under its own
    # name so it does not become the default python. See pkgs/yukkuri-python.nix.
    (pkgs.callPackage ../pkgs/yukkuri-python.nix { })
    # sioyek: the cask was an unsigned x86_64 build that needed Rosetta and no_quarantine.
    # nixpkgs builds it natively and it reads the same ~/Library/Application Support/sioyek
    # (config from darwin-chrome.nix, plus the highlight/bookmark DBs).
    pkgs.sioyek
    # Tahoma2D replaces the x86_64-only opentoonz cask. See pkgs/tahoma2d.nix.
    tahoma2d
  ];

  # Tahoma2D writes its profiles and config into the stuff folder, so it has to live outside the
  # store. Seed it once; after that it belongs to the app (copying over it would reset settings).
  system.activationScripts.postActivation.text = lib.mkAfter ''
    stuff="/Users/${user.username}/Library/Application Support/Tahoma2D/Tahoma2D_stuff"
    if [ ! -d "$stuff" ]; then
      /usr/bin/sudo -u ${user.username} /bin/mkdir -p "$stuff"
      /usr/bin/sudo -u ${user.username} /bin/cp -R ${tahoma2d}/share/tahoma2d/stuff/. "$stuff/"
      /bin/chmod -R u+w "$stuff"
    fi
  '';

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
    # Puddle's three behavior keys moved to configs/puddle/install.toml, which Puddle reads directly.
    # They were declared here from 2026-08-08 and never reached the running app: CustomUserPreferences
    # is `defaults write`, and that resolved to the sandbox container a retired build left behind,
    # while the Nix Apps build reads the standard domain. Declaring them in the file the app opens
    # itself means there is no second place for the value to land.

    # Screenshots land in ~/Downloads. The Desktop is the macOS default, but desktop icons are
    # hidden here (finder.CreateDesktop = false), so shots would pile up somewhere invisible.
    screencapture.location = "/Users/${user.username}/Downloads";

    # Default keyboard shortcuts that are deliberately off. These were set by hand in System
    # Settings and never declared, which mattered most for 64/65: Tinycast (the launcher) takes
    # cmd+space, so Spotlight has to release it or the two fight.
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

  # NextDNS (profile 43b9d5, localhost:53, never the system resolver) was removed on
  # 2026-09-26: DNS filtering moved to the two blocky hosts, handed out by the tailnet
  # (nix/lib/blocky-settings.nix). nix-darwin drops the org.nixos.nextdns daemon on switch.

  fonts.packages = with pkgs; [
    nerd-fonts.hack
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    hackgen-nf-font # HackGen NF (Japanese + Nerd Fonts), not the same thing as Hack
    # sketchybar app icon font. Pinned to the release plugins/icon_map.sh came from — nixpkgs
    # is on an older one, and a font and a map that disagree draw the wrong glyphs.
    # Fetched rather than committed: the ttf is 280KB of someone else's build.
    (stdenvNoCC.mkDerivation {
      pname = "sketchybar-app-font";
      version = "3.0.5";
      src = fetchurl {
        url = "https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v3.0.5/sketchybar-app-font.ttf";
        hash = "sha256-Srq4jhiG9pi+Q1CGzgzTD6UjIRHFQHnX0kR8Z8oRrss=";
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
    };

    # Every tap here is ours to vouch for, so each gets `trusted: true` in the Brewfile. Homebrew 6
    # refuses formulae/casks from untrusted non-official taps (HOMEBREW_REQUIRE_TAP_TRUST), and
    # `brew bundle` records a trusted tap in trust.json before loading anything. A trusted tap
    # covers every formula in it, including dependencies the Brewfile never names
    # (osx-cross/avr/avr-binutils, qmk/qmk/hid_bootloader_cli). This replaces the deprecated
    # HOMEBREW_NO_REQUIRE_TAP_TRUST=1 that used to switch the check off during activation.
    taps =
      map
        (name: {
          inherit name;
          trusted = true;
        })
        [
          "abue-ammar/tinycast" # Tinycast (native Spotlight-like launcher, AGPL-3.0). Not in homebrew/cask.
          "chojs23/tap" # Concord (Discord TUI)
          "deskflow/tap"
          "felixkratz/formulae"
          "finnvoor/tools"
          "frankea/whisky" # Whisky, community fork (upstream Whisky-App/Whisky archived 2025-05)
          "gerlero/openfoam"
          "lihaoyun6/tap" # QuickRecorder (screen recorder. Required since not in homebrew/cask)
          "osx-cross/arm" # QMK toolchain dependency tap
          "osx-cross/avr" # QMK / Keyball AVR toolchain tap
          "qmk/qmk" # QMK CLI
          "stablyai/orca" # Orca ADE (Claude Code/Codex chat UI and remote client)
          "y3owk1n/tap" # cask distribution source for neru (full-screen keyboard navigation)

          # ─── Personal forks (gapul) — delete if you forked and don't need them ───
          "gapul/tap" # gapul's general-purpose cask tap (things not in homebrew/cask)
          "gapul/openutau"
          "gapul/azoo-key-skkserv"
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
      # ─── Keyboard firmware ───
      "qmk/qmk/qmk" # (b) has to match the keg-only avr toolchain below; nixpkgs qmk pulls its own
      "osx-cross/avr/avr-gcc@12" # (b) keg-only AVR toolchain for Keyball

      # ─── TUI utilities ───
      # The 2.4.8 hold is gone (2026-08-29, unpinned and upgraded to 2.5.13). It was held because
      # the cargo-dist-generated formula listed alsa-lib/pipewire (Linux-only, no macOS bottle)
      # unconditionally, so 2.5.0+ could not install here. The 2.5.13 formula wraps them in
      # `on_linux do`, which is the fix that was being waited on. Nothing to re-pin on a fresh
      # machine any more — the pin was imperative (`brew pin`), so it only ever existed on this one.
      # The `just maintain` hardening from PR #119 stays useful regardless: it is what keeps one
      # broken formula from aborting the whole upgrade and rolling back the flake update.
      "chojs23/tap/concord" # (a) Discord TUI. tap-only, not in nixpkgs
      "wifitui" # (a) wifi TUI. nixpkgs marks it Linux-only

      # ─── Network / Download / VPN ───
      # tor / wireguard-tools / cloudflared moved to nix (2026-09-15): none of the brew services
      # was ever started. nextdns went the same way and was then retired (2026-09-26, blocky).
      # No "tailscale" formula: the tailscale-app cask already ships both the daemon and a CLI at
      # /usr/local/bin/tailscale. The formula's brew service was never started, and its own CLI sits
      # earlier in PATH, so every `tailscale` call went through a binary built from a different
      # source than the running daemon ("client version != tailscaled server version").

      # ─── Documents / Fonts / Media ───
      "gstreamer" # (a) nixpkgs gst_all_1 doesn't support aarch64-darwin
      # 3D model previews in yazi (configs/cli/yazi/plugins/model.yazi). nixpkgs-unstable f3d builds
      # now, but its offscreen render of a .glb comes out blank (checked 2026-09-15, 3.5.0) where
      # brew's draws the model.
      "f3d" # (a) headless 3D renderer

      # ─── macOS specific CLI ───
      "media-control" # (a) media keys. not in nixpkgs
      "displayplacer" # (a) sketchybar multi-display. not in nixpkgs

      # (Xcode itself is managed by xcodes, which moved to nix — see home/darwin.nix. aria2, which
      #  xcodes uses for the parallel .xip download, was already declared in home/workstation.nix.)

      # ─── Status bar (felixkratz tap) ───
      # (borders/JankyBorders was dropped 2026-08: OmniWM draws its own active-window border, so the
      #  resident daemon was 174MB of duplicate decoration.)
      # nixpkgs also has sketchybar, but it was moved there and back (#485 → this revert). The reason is
      # signing: nix builds the nixpkgs version from source, so it is ad-hoc signed and TCC keeps showing
      # the prompt '"sketchybar" would like to access data from other apps' endlessly.
      # The binary felixkratz distributes is signed, so it stays quiet. Same story as keystats losing its
      # permissions twice: the cause is not "placing it in nix" but "the cdhash changing on every build".
      # Conversely, keebmouse / Puddle / keystats, which just ship signed distributions, are in nix.
      "felixkratz/formulae/sketchybar" # (a) needs the signed binary. The launchd agent is in home/darwin-chrome.nix

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
      # These could move to brewCasks too, but these 7 stay casks. The reason is size: the macos-14
      # runner of om ci (aarch64-darwin) has only about 14GB free, and materializing about 5GB total
      # into the store dies silently while unpacking anki.
      # They build fine on the main Mac, so this is a CI ceiling, not a reason they can't be declared.
      "bitwig-studio"
      "cycling74-max"
      "freecad"
      "krita"
      "simplex"
      "touchdesigner"
      # ─── Browsers ───
      # google-chrome: back on 2026-09-23 as the stock Chromium for sites whose tracking or
      # affiliate flows break under Helium's defaults (third-party cookies blocked, fingerprint
      # noise, bundled uBlock Origin) — first case was a point-site card application. Not for
      # automation: that was why it was dropped on 2026-08-30 (Lightpanda for background work,
      # terminal-browser for visible runs, Helium below as the everyday Chromium), and the Claude
      # in Chrome extension stays out — Playwright covers it without a debugging port on localhost.
      "google-chrome"
      # Not the "helium" cask: that one is koush's unrelated Android desktop app, deprecated for
      # failing Gatekeeper and disabled on 2026-09-01.
      "helium-browser" # ungoogled-chromium based, now the Chromium of record here
      "tor-browser"
      # Firefox Developer Edition: the daily browser, and the DRM and video-call one (2026-09-17;
      # it replaced Zen, which had no Widevine licence and was removed 2026-10-01). Helium has no
      # CDM at all, so it cannot play Netflix, Prime Video or Spotify web; Mozilla's build carries
      # the licence. The cask rather than nixpkgs'
      # firefox-devedition-bin: on darwin nixpkgs re-signs the bundle ad hoc (TeamIdentifier not
      # set, resources missing), and the nix-vs-brew signing rule wants the Developer ID signature
      # kept so the microphone/camera TCC grants survive a rebuild. Everything else about it
      # (profile, arkenfox hardening, extensions, policies) is declared in
      # modules/home/darwin-firefox.nix; the app's own updater is disabled there, so the version
      # moves with `just maintain` (brew --greedy) like the other auto_updates casks.
      "firefox@developer-edition"

      # ─── PDF viewers ───
      # sioyek (daily driver) comes from nixpkgs, see environment.systemPackages.
      "skim" # native SyncTeX viewer. Backup for TeX writing (integration later)

      # ─── Image viewers ───
      # qView is ad-hoc signed only (not notarized). With quarantine it gets rejected by
      # Gatekeeper and won't launch, so no_quarantine is required.

      # ─── Communication & Sync ───
      # Dropped proprietary Beeper (not in active use) for Element on the self-hosted Matrix
      # (@gapul:gapul.net; Discord/Telegram bridged in homelab/matrix.nix).
      "element"

      # ─── Window / Keyboard / Input ───
      "karabiner-elements"
      "macskk"
      "gapul/azoo-key-skkserv/azoo-key-skkserv" # skkserv for the azooKey conversion engine (gapul self-made tap)
      "y3owk1n/tap/neru" # mouse-free full-screen navigation (grid/hints/scroll. System-wide version of Vimium. shortcat superset)

      # ─── macOS utilities ───
      "hammerspoon"
      "espanso"
      "maccy"
      "monitorcontrol"
      "qlmarkdown"
      "abue-ammar/tinycast/tinycast" # Spotlight-like launcher (SwiftUI/AppKit, no Electron, AGPL-3.0)

      # ─── Creative / VTuber ───
      # nijigenerate/nijiexpose: 2D VTuber puppet rigging + streaming runtime (Live2D alternative,
      # free/OSS). Community successor forks of Inochi Creator/Session on the nijilive puppet format;
      # active development moved here. Distribute the official mac builds via a self-made cask tap
      # (not in homebrew/cask, and nixpkgs only has the older Inochi2D). Currently v1.0.0-beta2.
      "gapul/inochi/nijigenerate" # rigging editor (Inochi Creator successor)
      "gapul/inochi/nijiexpose" # streaming runtime (Inochi Session successor)
      # VCam: 3D (VRM) avatar out of a CoreMediaIO virtual camera, so OBS / Zoom / Meet see the
      # avatar as a webcam. MIT and mac-native — the only maintained FOSS VRM runtime for macOS.
      # Face tracking is the built-in camera by default and iFacialMocap (iPhone TrueDepth) for
      # perfect sync. Stays a cask rather than brewCasks above: it wants Camera/Microphone TCC and
      # registers a virtual camera, and both key on the bundle living at /Applications/VCam.app.
      "vcamapp"

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
      # lulu (outbound firewall) was removed 2026-09-30: its network extension repeatedly
      # stalled inbound ssh to the MacBook (banner exchange timeout; "No current verdict
      # available" in the LuLu log, 2026-09-27 and 2026-09-30), and restarting LuLu was the
      # only fix. An outbound-only firewall that takes the inbound path down is not worth
      # keeping; Tailscale + ALF cover what we need.
      "ransomwhere" # ransomware (suspicious encryption behavior) detection
      # VPN / keys
      "mullvad-vpn" # no-log anonymous VPN (a separate layer from self-hosted WireGuard/Tailscale)
      "keepassxc"
      "bitwarden" # Bitwarden official desktop app

      # ─── Network / Remote ───
      "tailscale-app"
      "rustdesk"

      # ─── Dev IDEs / Editors / SDK ───
      "stablyai/orca/orca" # unified chat UI for Claude Code/Codex; custom tap avoids the unrelated disabled Plotly cask
      "t3-code@nightly" # T3 Code client for the macmini t3code host; nightly to match its server protocol
      "ghostty"
      "deskflow"
      "codexbar" # show usage/limits of various AI coding vendors in the menu bar (bundles codexbar CLI, auto-linked into /opt/homebrew/bin)

      # ─── Creative — Design / 2D ───
      "affinity"
      "gimp"
      # Inkscape stays a cask: inkstitch declares `depends_on cask: "inkscape"`, and with the nixpkgs
      # build instead brew refuses to uninstall it, which aborts the whole bundle cleanup.
      "inkscape"
      "darktable"
      "rawtherapee"
      "digikam" # photo management (RAW development, tag management)
      # Ink/Stitch: machine-embroidery extension for Inkscape. Was hand-installed from its .pkg
      # (3.2.2); the cask is the same installer, one release newer.
      "inkstitch"
      "pika"
      "adobe-creative-cloud"
      "sf-symbols" # Apple SF Symbols catalog

      # ─── Creative — Audio / Music ───
      "cardinal"
      "musescore"
      # native-access removed: replaced by the unofficial CLI (gapul/na-cli, on PATH via
      # home/darwin.nix). NTKDaemon runs headless via launchd; keep the cask out so a rebuild
      # doesn't reinstall the GUI and re-claim the native-access:// scheme.
      "openutau"
      "pd"
      "reaper"
      "surge-xt" # synth standalone/plugin (.pkg cask)
      # zrythm was removed since it was a trial version (x64/Rosetta/can't save). Consolidated onto the
      # self-made full nix version (pkgs/zrythm-darwin, arm64-native, -O2). Installed via home.packages.
      "vcv-rack"
      "blackhole-2ch" # virtual audio device to route system audio into OBS / DAW

      # ─── Creative — Video / Animation / Stream ───
      "obs"
      "lihaoyun6/tap/quickrecorder" # screen recorder (native ScreenCaptureKit, Tahoe-compatible). Switched from the old kap, which is Electron-based and stalled for ~1.7 years
      "cavalry" # 2D motion graphics

      # ─── 3D / CAD ───
      "blender"
      "kicad"
      "godot"
      "openfoam"

      # ─── 3D Printing ───
      # OrcaSlicer-bambulab (environment.systemPackages above) covers the Bambu A1 mini,
      # including starting prints, with its own network implementation in place of
      # Bambu's plugin (see pkgs/orcaslicer-bambulab.nix).
      # Reinstall bambu-studio temporarily if a cloud-side problem needs an
      # "authorized software" reference point.

      # ─── Games / Emulation ───
      # Whisky: SwiftUI bottle manager with its own bundled Wine + DXMT/DXVK/GPTK. It replaces the
      # wine-stable + winetricks pair, which never had a prefix created (x86_64-only, too). The frankea fork
      # is the maintained one (signed + notarized). Tap-qualified on purpose: plain "whisky" in
      # homebrew/cask is still the archived original.
      "frankea/whisky/whisky"
      "heroic" # Epic/GOG/Amazon launcher (FOSS). Replaces the proprietary Epic Games launcher; pairs with legendary-gl (see workstation.nix)
      "retroarch-metal"
      "steam"
      # Client for ispc's Sunshine (the Windows-only machine, driven from the main Mac)
      "moonlight"
      "playcover-community"

      # ─── Productivity / Notes / Reading ───
      "calibre"
      "obsidian"
      "libreoffice"

      # ─── Fonts ───
      "font-sf-mono"

      # ─── Tracking / Misc ───
      # The stable cask (0.13.2) is x86_64-only and stopped launching when the macOS 27 upgrade
      # dropped Rosetta. The beta is the arm64 Tauri build with aw-server-rust.
      "activitywatch@beta"
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
