{
  lib,
  pkgs,
  brewNix,
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
    # keebmouse: 自作。cask をやめて署名済みリリースを取り込む nix パッケージにした。
    # TCC を壊すのは「nix で置くこと」ではなく「ビルドのたび cdhash が変わる ad-hoc 署名」の
    # ほうで、ここは Developer ID 署名の bundle をそのまま運ぶので版が上がっても剥がれない。
    # 常駐は launchd.agents.keebmouse (modules/home/darwin-chrome.nix) が持つ。
    # OmniWM: 主力のタイル型 WM。cask をやめて署名済みリリースを取り込む(pkgs/omniwm.nix に
    # 経緯)。systemPackages なのは omniwmctl の置き場所のため — /run/current-system/sw/bin という
    # 版にもユーザー名にも依存しない固定パスに出るので、configs 側のスクリプトが直に書ける。
    (pkgs.callPackage ../pkgs/omniwm.nix { })
    # KDE Connect: スマホ連携。自作 tap の cask をやめて署名済みの dmg を取り込む
    # (経緯は pkgs/kdeconnect.nix)。cask は `sha256 :no_check` で検証していなかったうえ、
    # 固定していた CI ビルドが CDN から消えていて、新しい機械では 404 になる状態だった。
    (pkgs.callPackage ../pkgs/kdeconnect.nix { })
    # terminal-browser: 端末の中で動く実ブラウザ。狙いは閲覧より agent 側で、
    # `terminal-browser action` が開いているブラウザに対する agent 向け CLI になっている。
    # Claude in Chrome の拡張を使わず、実ウィンドウも出さずに web を触らせられる。
    # 上流は curl | bash のインストーラで自己更新するので、版を握るために宣言側に置く。
    terminalBrowser
    # agent-browser: terminal-browser が同梱している agent 向けブラウザ CLI。libexec の中に
    # あって PATH に出ないので、ここで出す。単体で、ヘッドレスで、ペインを出さずに動く。
    # これが agent の既定の経路 — 1 ページを 200〜400 token で表現するので、MCP 越しに
    # アクセシビリティツリーを毎ターン文脈へ積むより桁で安い (上流の実測で 114k 対 27k)。
    # 版は terminal-browser 本体と常に一致する。
    (pkgs.writeShellScriptBin "agent-browser" ''
      exec ${terminalBrowser}/libexec/terminal-browser/agent-browser/bin/agent-browser "$@"
    '')
    # playwright-test: クロスブラウザ検証を要るときだけ起こすラッパー。Firefox と WebKit で
    # 試せるのは Playwright だけで、そこは agent-browser に無い能力なので残す。ただし常駐は
    # やめた (経緯は modules/home/darwin-services.nix)。前の常駐は --cdp-endpoint で既存の
    # Chromium にぶら下がる形だったので、そもそも Firefox にも WebKit にも届いていなかった。
    (pkgs.writeShellScriptBin "playwright-test" ''
      browser="''${1:-chromium}"
      port="''${2:-8932}"
      echo "playwright-mcp: $browser on http://localhost:$port/mcp (Ctrl-C to stop)" >&2
      export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
      exec ${lib.getExe agentPkgs.playwright-mcp} \
        --browser "$browser" --port "$port" \
        --output-dir "$HOME/tmp/playwright-test"
    '')
    # node: playwright-mcp の実行に要る。pnpm の global store が持っていた node は
    # リンク切れになっていて (~/Library/pnpm/bin/node → 消えた store パス)、そのせいで
    # かつての playwright agent が "exec: node: not found" で死んでいた。ランタイムは
    # pnpm の管理から外して宣言側で持つ。
    pkgs.nodejs
    # codex: 自前インストーラで ~/.local/bin に入っていたものを宣言に移す。home.packages
    # ではなく systemPackages なのは PATH の順で、/run/current-system/sw/bin が
    # ~/.local/bin より前に来る。profile 側だと手動インストール版が勝ってしまう。
    agentPkgs.codex
    agentPkgs.claude-code
    agentPkgs.opencode
    # ─── moved off Homebrew (2026-09-15): same app, same data dirs, nothing to re-set up ───
    # Upstream's signed release carried over as-is, so TCC grants and entitlements survive:
    pkgs.utm # VMs stay in ~/Library/Containers/com.utmapp.UTM (same bundle id)
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
    # Puddle / keystats: 自作物。keebmouse と同じく cask をやめて署名済みリリースを取り込む。
    # これで自作物のための tap (gapul/puddle, gapul/keystats) が両方畳める。
    (pkgs.callPackage ../pkgs/puddle.nix { })
    (pkgs.callPackage ../pkgs/keystats.nix { })
    # mocopi: 自作。ソースは private repo のままなので flake input は git+ssh で引いている
    # (flake.nix の mocopi-mac)。ここに置くと /Applications/Nix Apps に入るので、README に
    # あった `nix build && cp -R result/Applications/mocopi.app ~/Applications/` の手作業が要らない。
    # .app であることに意味がある: 独立した bundle は自前の Bluetooth 権限を持てるので、
    # 起動したターミナルの権限を借りずに済む(mocopi-mac の flake.nix のコメント参照)。
    mocopiMac.packages.${pkgs.stdenv.hostPlatform.system}.default
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
    pkgs.brewCasks.ente-auth
    pkgs.brewCasks.keyguard
    pkgs.brewCasks.knockknock # persistence scanner (Objective-See). 初回に Full Disk Access の再付与が要る
    pkgs.brewCasks.localsend
    pkgs.brewCasks.orcaslicer
    # Scribus は同梱の Python.framework に PrivateHeaders への壊れた symlink を2本抱えていて、
    # nixpkgs の noBrokenSymlinks fixup がそれを理由にビルドを落とす。中身は上流の配布物その
    # ままで、壊れているのは使われないヘッダの参照だけなので、チェックのほうを外す。
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
    pkgs.brewCasks.trex # 画面 OCR。Screen Recording の TCC を再付与する必要がある
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
    pkgs.azahar # 3DS. Citra successor (Citra and Lime3DS are both discontinued). No usable libretro core yet
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
    # VRoid Studio (VRM character modelling): no nixpkgs package and no cask, so the official
    # macOS dmg is repackaged. See pkgs/vroid-studio.nix - the download URL carries a token
    # that has to be re-read from vroid.com on every version bump.
    (pkgs.callPackage ../pkgs/vroid-studio.nix { })
    # AivisSpeech's engine and models live on the always-on Mac mini.  This
    # workstation calls its VOICEVOX-compatible API over Tailscale instead of
    # carrying a second engine/model cache locally.
    # Orca fork that can still start a print on a Bambu printer - the stock cask
    # above only exports, since Bambu's Authorization Control ignores the print
    # command from anything but Bambu Connect. Kept beside the cask, with its own
    # bundle name and datadir. See pkgs/orcaslicer-bambulab.nix.
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
      version = "3.0.1";
      src = fetchurl {
        url = "https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v3.0.1/sketchybar-app-font.ttf";
        hash = "sha256-vOE5GnDgQRdYfeJuTwBMT6bElbmHQKTcIKsIXThSZtU=";
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
      "gapul/tap" # gapul の汎用 cask タップ (homebrew/cask に無いもの)
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
      # nixpkgs にも sketchybar はあるが、移して戻した(#485 → この revert)。理由は署名で、
      # nixpkgs 版は nix がソースからビルドするので ad-hoc 署名になり、TCC が
      # 「"sketchybar" would like to access data from other apps」を延々出し続けて収まらない。
      # felixkratz が配るバイナリは署名済みなので黙る。keystats で2回権限が飛んだのと同じ話で、
      # 「nix に置くこと」ではなく「ビルドのたび cdhash が変わること」が原因。逆に言えば、
      # 署名済みの配布物を運ぶだけの keebmouse / Puddle / keystats は nix 化できている。
      "felixkratz/formulae/sketchybar" # (a) 署名済みバイナリが要る。launchd agent は home/darwin-chrome.nix

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
      # brewCasks に移せた仲間だが、この7本だけ cask のまま。理由はサイズで、
      # om ci(aarch64-darwin) の macos-14 ランナーは空きが約14GBしかなく、
      # 合計約5GB を store に実体化しようとすると anki の展開中に無言で死ぬ。
      # 母艦では問題なくビルドできるので、宣言できない理由ではなく CI の天井。
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
      "zen"
      # Firefox Developer Edition: the DRM and video-call browser next to Zen (2026-09-17). Zen
      # has no Widevine licence and Helium has no CDM at all, so neither plays Netflix, Prime
      # Video or Spotify web; Mozilla's build carries the licence. The cask rather than nixpkgs'
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
      "lulu" # outbound firewall
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
      "ghostty"
      "android-studio"
      "flutter"
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
      # Unity Hub は「常用する GUI」ではなくインストーラの CLI として置いている。
      #   Unity Hub.app/Contents/MacOS/Unity\ Hub -- --headless install --version <版> --changeset <hash>
      # で GUI を開かずにエディタを入れられる。Hub 抜きでも公式の単体インストーラは取れるが、
      # Personal ライセンスの認証が -createManualActivationFile → ポータル → -manualLicenseFile
      # の遠回りになるので、手元で入れるぶんには Hub を通すほうが早い。nixpkgs の unityhub は
      # Linux 専用なので cask で宣言する。
      "unity-hub"
      "blender"
      "kicad"
      "godot"
      "openfoam"

      # ─── 3D Printing ───
      # Orca alone covers the Bambu A1 mini: it installs Bambu's network plugin
      # itself, so send / camera / temps / jog / firmware update all live here.
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
      # ispc の Sunshine につなぐクライアント (Windows 専用のものを母艦から触る)
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
