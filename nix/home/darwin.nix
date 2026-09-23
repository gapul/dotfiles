{
  config,
  pkgs,
  lib,
  user,
  nixpkgsUnstable,
  secureEnclaveKey,
  ...
}:
let
  # Bound here rather than inline in home.packages because the LaunchAgent below
  # needs the path too, and both must point at the same store path.
  mechvibes-dx = pkgs.callPackage ../pkgs/mechvibes-dx.nix { };

  # The bundle actually launched: a signed copy of the one in the store, see
  # home.activation.mechvibesSign below.
  mechvibesApp = "/Applications/MechvibesDX.app";

  # Native Access's daemon, where its installer puts it (proprietary, not nix-built).
  # Bound here because both the `na` wrapper and the LaunchAgent below refer to it.
  ntkDaemon = "/Library/Application Support/Native Instruments/NTK/NTKDaemon.app/Contents/MacOS/NTKDaemon";
in
{
  imports = [
    ../modules/home/darwin-agent-state-sync.nix
    ../modules/home/darwin-chrome.nix
    ../modules/home/darwin-firefox.nix
    ../modules/home/darwin-helium.nix
    ../modules/home/darwin-services.nix
    ../modules/home/darwin-apps.nix
    ../modules/home/darwin-ai-client.nix
    ../modules/home/agy.nix
  ];

  # Nothing puts an .app under ~/Applications any more: bundles come from environment.systemPackages
  # (hosts/darwin.nix) into /Applications/Nix Apps, and the two written by hand - MechvibesDX's
  # signed copy and the mpv droplet - go straight to /Applications. Left enabled this would keep
  # generating an empty "Home Manager Apps" alongside them. mac-app-util's trampolines went with it
  # (the input is gone), since it existed only to make the ~/Applications symlinks indexable.
  #
  # The catch: a package added to home.packages that does ship an .app now lands nowhere visible,
  # silently. Put GUI packages in environment.systemPackages.
  targets.darwin.linkApps.enable = false;

  # macOS-specific home-manager config
  # Common parts are split into home/common.nix

  home.homeDirectory = "/Users/${user.username}";

  home.sessionVariables = {
    HOMEBREW_NO_ANALYTICS = "1";
    # What `brew shellenv` used to export, declared instead of spawning brew every shell.
    # See the interactiveShellInit override in hosts/darwin.nix for why it is gone.
    # Its PATH work was already redundant (home.sessionPath + /etc/zprofile's path_helper
    # produce a byte-identical PATH), so only these are left.
    # ponytail: pinned to the /opt/homebrew prefix this machine has. If brew ever moves or
    #           starts exporting something new, `brew shellenv` is the thing to diff against.
    HOMEBREW_PREFIX = "/opt/homebrew";
    HOMEBREW_CELLAR = "/opt/homebrew/Cellar";
    HOMEBREW_REPOSITORY = "/opt/homebrew/Library/.homebrew-is-managed-by-nix";
    INFOPATH = "/opt/homebrew/share/info:";
    # NOTE: brew's trust.json can't be XDG-ified. The activation brew bundle
    # strips XDG_CONFIG_HOME via `sudo --preserve-env=PATH --set-home` and always reads ~/.homebrew.
    # Also, brew prefers XDG_CONFIG_HOME over HOMEBREW_USER_CONFIG_HOME, so the interactive shell's
    # plain trust drifted to ~/.config/homebrew and got duplicated. The
    # `.config/homebrew → ~/.homebrew` symlink below converges both paths onto the same entity
    # (Justfile rebuild's `env -u XDG_CONFIG_HOME` is harmless, so kept).
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
    # ActivityWatch (Tauri build) checks GitHub for updates on every start and, by default,
    # installs them into its own bundle. The app comes from the activitywatch@beta cask, so updates
    # belong to brew; this skips the check entirely (`auto_download = false` would still prompt).
    # It reaches the login-item launch through the session-env agent in darwin-services.nix.
    AW_DISABLE_AUTO_UPDATE = "1";
    # aw-tauri already autostarts `aw-sync daemon` (its config.toml autostart list), which pushes every
    # bucket to a sync directory every 5 minutes. Pointing that directory into the Syncthing share
    # puts the whole ActivityWatch record on homeserver within minutes instead of the daily snapshot.
    # aw-sync keeps its own per-device subdirectory, so this sits beside the <host>/ dirs of
    # personal-history without colliding.
    AW_SYNC_DIR = "${config.home.homeDirectory}/Sync/syncthing/personal-history/aw-sync";
    # nh: darwin works with the darwinConfigurations.<user> form. For home on nh 4.3.2,
    # neither #name nor #...activationPackage works → flake only (no #) so it auto-detects
    # homeConfigurations.<user> by user name is the only form that works.
    NH_DARWIN_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix#darwinConfigurations.${user.username}";
    NH_HOME_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix";

    # Give cargo and cmake the ceiling nix already has.
    #
    # hosts/darwin-common.nix caps the nix daemon at max-jobs = 4 / cores = 2 for this
    # machine's 8 logical cores (4P + 4E). Builds that do not go through nix inherit no
    # such limit: cargo defaults to one job per logical core (8) and ninja to cores + 2
    # (10), each job free to spawn its own threads.
    #
    # That gap is not theoretical. On 2026-08-29 a servo `cargo build --release` and a
    # ladybird cmake build ran together on top of the usual resident agent sessions, on
    # 16 GB: eight clang processes plus rustc, load average 200 with the CPU 40% idle
    # (everything blocked on memory), 4.8 GB of the 5.1 GB swap consumed, and coreaudiod
    # leaking real-time IO threads until it held 3 GB and two cores. The machine was not
    # short of CPU, it was short of RAM, and the parallelism is what spent it.
    #
    # 4 matches nix's max-jobs, so a local build looks the same to the scheduler whichever
    # path it came through. Heavy builds belong on the mac mini (10 cores, 24 GB, headless)
    # anyway; this is the guard for when one runs here regardless.
    CARGO_BUILD_JOBS = "4";
    CMAKE_BUILD_PARALLEL_LEVEL = "4";
  };

  # Resolve brew trust.json duplication: converge the interactive shell (reads
  # ~/.config/homebrew via XDG_CONFIG_HOME priority) and the sudo/rebuild path (~/.homebrew)
  # onto the same entity via symlink. Canonical is ~/.homebrew (the sudo side doesn't see XDG).
  home.file.".config/homebrew".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.homebrew";
  # aw-sync writes to ~/ActivityWatchSync unless AW_SYNC_DIR reaches it. When aw-tauri is started
  # before the session-env agent (or by hand from the Dock) the variable is missing and a second
  # 240 MB copy of the record silently grows in $HOME. The symlink makes both paths the same place,
  # so the sync directory no longer depends on launch order. AW_SYNC_DIR stays declared above.
  home.file."ActivityWatchSync".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Sync/syncthing/personal-history/aw-sync";

  # Move real data of non-XDG tools under XDG, keep default paths via symlink
  # (same approach as terminfo). Classification: credentials/long-term data=data, telemetry state=state.
  home.file.".appstoreconnect".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/appstoreconnect";
  home.file.".cloudflared".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/cloudflared";
  home.file.".dart-tool".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/dart-tool";
  # Ensure the entity exists first, else tool writes fail with ENOENT when the symlink target is missing
  home.activation.xdgSymlinkTargets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.xdg.dataHome}/appstoreconnect" \
      "${config.xdg.dataHome}/cloudflared" \
      "${config.xdg.stateHome}/dart-tool"
  '';

  home.sessionPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "${config.home.homeDirectory}/Library/pnpm"
    "${config.home.homeDirectory}/Library/pnpm/bin"
  ];

  # The other half of what `brew shellenv` did: its zsh completions (_deno, _ghostty, _mpv,
  # _yt-dlp …). mkBefore puts it ahead of the compinit in modules/home/shell.nix,
  # which is the only ordering that matters here.
  programs.zsh.completionInit = lib.mkBefore ''
    fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
  '';

  # Append Mac-specific zsh init (added after common's initContent)
  programs.zsh.initContent = lib.mkAfter ''
    # (No brew shellenv here: /etc/zshrc runs one before this file is read, and by then
    #  /opt/homebrew/bin leads PATH, so a second call always returned an empty string.
    #  It was one process spawn per shell for nothing.)

    # Package manager priority (nix > homebrew) applied to PATH itself: brew shellenv prepends
    # /opt/homebrew/bin, which used to put brew ahead of the nix profile, so anything present on both
    # sides silently resolved to brew. Re-prepend the nix profiles after it. typeset -U keeps the
    # first occurrence and drops the later duplicates, so brew stays available, just behind nix.
    # (Only zsh is covered. Non-shell contexts — launchd agents / GUI apps — still follow
    #  home.sessionPath, where brew comes first. The invariant test in tests/config-invariants.nix
    #  is what actually keeps duplicates from existing in the first place.)
    typeset -U path PATH
    path=(
      "$HOME/.local/state/nix/profile/bin"
      /run/current-system/sw/bin
      /nix/var/nix/profiles/default/bin
      $path
    )

    # SSH keys come from the Secure Enclave now, not the Bitwarden vault, so leave SSH_AUTH_SOCK
    # pointing at launchd's own agent. Overriding it to the Bitwarden socket meant that closing
    # Bitwarden emptied the agent: direct logins still worked (ssh_config offers the enclave key as
    # an IdentityFile), but the five hosts with ForwardAgent forwarded nothing, so git on the far
    # side broke with no obvious cause.
    #
    # SSH_SK_PROVIDER is what lets the agent hold the enclave identity at all: it is an sk-ecdsa key
    # behind macOS' CryptoTokenKit middleware, and ssh-add/ssh-agent need to be told which library
    # to load. With AddKeysToAgent=yes in ssh_config, the first connection loads it by itself —
    # and since ForwardAgent only applies to connections made from this Mac, making that connection
    # is precisely what fills the agent. No login-time ssh-add job is needed.
    export SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib

    # The Bitwarden vault is kept as the recovery path — its keys are still in every
    # authorized_keys, including the work host that only this Mac's enclave can otherwise reach.
    # Opt into it for a session when the enclave is unavailable:
    function use-bitwarden-agent() {
      if [[ -S "$HOME/.bitwarden-ssh-agent.sock" ]]; then
        export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
        echo "SSH_AUTH_SOCK -> Bitwarden (このシェルのみ)"
      else
        echo "Bitwarden Desktop が起動・アンロックされていません" >&2
        return 1
      fi
    }

    # CocoaPods (avoid conflict with nix ruby)
    unset GEM_HOME GEM_PATH

    # sketchybar reconfigure wrapper (call after plugging/unplugging displays)
    function sketchybar-refresh() {
      bash ~/.config/sketchybar/helpers/refresh-displays.sh "$@"
    }

    # Toggle to temporarily disable clamshell sleep.
    # Use when you want processing to keep running with the lid closed.
    # Temporary setting reset on reboot. Use off to return to normal.
    function nosleep() {
      case "$1" in
        off)
          sudo pmset -a disablesleep 0 && echo "Sleep disable removed (back to normal sleep)"
          ;;
        status|"")
          if pmset -g | grep -q "SleepDisabled.*1"; then
            echo "Current: sleep disabled (keeps running with the lid closed)"
          else
            echo "Current: normal (sleeps when the lid is closed)"
          fi
          ;;
        on)
          sudo pmset -a disablesleep 1 && echo "Sleep disabled (keeps running with the lid closed / power connection recommended)"
          ;;
        *)
          echo "Usage: nosleep [on|off|status]"
          ;;
      esac
    }
  '';

  # mac-specific packages
  home.packages = with pkgs; [
    bun # generate/type-check karabiner.ts config
    pngpaste # needed for macOS image paste in obsidian.nvim / img-clip
    syncthing # Syncthing CLI (the resident is the LaunchAgent in services.syncthing)
    xcodegen # generate .xcodeproj from project.yml (Mac-only, since meta.platforms = darwin in Linux nixpkgs)
    # na: unofficial Native Access CLI. The tool lives in a private checkout
    # (~/Developer/github.com/gapul/na-cli); this wrapper bundles pyzmq and calls it,
    # so the RE'd source stays out of this public repo. Talks to NTKDaemon (agent below).
    # The daemon is not resident: this wrapper starts it, so nothing Native Instruments
    # related runs until Native Access is actually used. `kickstart` on an already-running
    # label is a no-op, so the common case costs one launchctl call.
    (writeShellScriptBin "na" ''
      if [ -x "${ntkDaemon}" ]; then
        /bin/launchctl kickstart "gui/$(/usr/bin/id -u)/org.nix-community.home.ntkdaemon" >/dev/null 2>&1 || true
        # The daemon binds its ZeroMQ ports a moment after exec. A REQ socket would queue the
        # request and still make the 5 s receive timeout, but waiting here keeps the failure
        # mode honest: if the port never opens, na says so instead of timing out mid-command.
        for _ in {1..50}; do
          (exec 3<>/dev/tcp/127.0.0.1/5146) 2>/dev/null && break
          /bin/sleep 0.1
        done
      else
        echo "na: NTKDaemon is not installed (${ntkDaemon})." >&2
        echo "na: install it from Native Access, then run na again." >&2
        exit 1
      fi
      exec ${
        python3.withPackages (p: [ p.pyzmq ])
      }/bin/python3 "$HOME/Developer/github.com/gapul/na-cli/na" "$@"
    '')
    # Replaces the secretive cask: same Secure Enclave guarantee (the private key is generated in
    # the enclave and never leaves it), but a CLI handing the identity to macOS' own CryptoTokenKit
    # provider instead of a GUI app plus a resident agent process.
    # The flake also ships a darwinModules.default, deliberately not used: it runs
    # `git config --global gpg.ssh.program …` on activation, which fights modules/home/git.nix
    # (signing goes through scripts/git-ssh-keygen-bitwarden) and would flip commit.gpgsign off.
    # Auth only here; wiring ssh_config to the enclave key is a manual migration (see PR).
    secureEnclaveKey.packages.${pkgs.stdenv.hostPlatform.system}.default
    (callPackage ../pkgs/slk.nix { }) # Slack TUI (pinned to the official GitHub Release)
    # sketchybar's event helper. `sketchybarrc` used to compile it on every bar start from
    # sources kept in the config directory; the launchd agents put the profile first on PATH.
    (callPackage ../pkgs/sketchybar-helper { })
    # Premiere Pro MCP server (registered with `claude mcp add -s user premiere-pro -- premiere-pro-mcp`).
    # Was a hand build in ~/Developer; see the pin note in the package.
    (callPackage ../pkgs/premiere-pro-mcp.nix { })
    # Laya typed-decision models on MLX (`laya-mlx predict`, `laya-snake`). Weights land in
    # ~/.cache/huggingface on first use. mlx comes from Apple's Metal wheels, see the package.
    (callPackage ../pkgs/laya-mlx.nix { })
    # zrythm (DAW): broken=isDarwin in nixpkgs. Self-built for darwin with carla included.
    # See pkgs/zrythm-darwin/ for details. GUI must be launched in a foreground GUI session.
    # On 26.05-darwin appstream/libadwaita can't build on darwin, so this one package alone
    # uses nixos-unstable pkgs (nixpkgsUnstable, via commonSpecialArgs in flake.nix).
    (import ../pkgs/zrythm-darwin {
      pkgs = nixpkgsUnstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    })
    # ardour / aseprite / fritzing / qview / vroid-studio used to sit here. They ship .app
    # bundles, and home-manager can only surface those under ~/Applications, so they moved to
    # environment.systemPackages in hosts/darwin.nix where nix-darwin puts them in
    # /Applications/Nix Apps. mechvibes-dx and zrythm stay: the former needs the per-user
    # signed copy below, the latter ships no bundle.

    # ─── CLI migrated from Homebrew (stage 4: mac CLI that had no reason to stay on brew) ───
    # All of these exist in nixpkgs for aarch64-darwin and substitute from the cache, and none of
    # them needs a brew service / tap / keg. See hosts/darwin.nix's brews for what stays on brew and why.
    sox # audio processing (rec / play / sox / soxi)
    # OpenSeeFace: webcam face/landmark tracking on the CPU, the FOSS half of what VSeeFace is
    # usually credited with (VSeeFace itself is closed). Ships no .app — it is a python tracker
    # that sends over UDP, which nijiexpose reads directly as a tracking source. Useful as the
    # camera-side input when the iPhone is not in play.
    openseeface
    # Talk to the iPhone over USB without Finder. Voice Memos keeps its recordings inside the app
    # sandbox, which AFC cannot reach, so the only way off the device is a device backup
    # (idevicebackup2) and pulling the AppDomainGroup-group.com.apple.VoiceMemos.shared files out
    # of its Manifest.db.
    libimobiledevice
    exiftool # strip metadata (GPS/device info) from images/PDFs before sharing
    blueutil # Bluetooth CLI
    duti # file associations
    scrcpy # Android screen mirroring
    android-tools # adb (droid command, mobile/android scripts)
    swi-prolog # Prolog (functional/logic programming lab. nvim ftplugin expects swipl on PATH)
    tcpdump # packet capture (live capture needs /dev/bpf perms, which is a permission thing, not a package thing)
    # Moved Xcode off masApps to xcodes (2026-08-02). mas's App Store delivery is a single
    # connection and can't be parallelized; xcodes + aria2 downloads the .xip in up to 16
    # parallel chunks (the .xip is a full ~7-10GB redownload every update, monthly-ish), and
    # xcodes gives explicit version control if a pinned build is ever needed. Latest-only for
    # now: `xcodes install --latest` from `just upgrade` keeps it current. Apple ID login is
    # required to download; credentials come from sops (xcodes/apple_id, xcodes/password) and
    # 2FA is prompted interactively on first auth / when the cached Apple session expires.
    # aria2 (which xcodes picks up from PATH) is declared in home/workstation.nix.
    xcodes # Xcode version manager (download/select/switch, replaces mas for Xcode)
  ];

  # OpenPGP for mail (aerc picks gpg up from PATH via pgp-provider=auto). Git signing stays
  # SSH-based (modules/home/git.nix), so gpg is only for mail and ad-hoc verify/decrypt.
  # The key's passphrase lives in sops (darwin.yaml pgp/passphrase); pinentry-mac can cache
  # it in the login keychain after the first prompt.
  programs.gpg = {
    enable = true;
    homedir = "${config.xdg.dataHome}/gnupg"; # matches GNUPGHOME in home/common.nix
  };
  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry_mac;
  };

  # Puddle: catalogs it may browse, sources it may install from, and the wallpapers this
  # machine should have. `puddle apply` reconciles the last of those.
  xdg.configFile."puddle/install.toml".source = ../../configs/puddle/install.toml;

  # The `puddle` CLI ships inside the app. Symlinked rather than copied so it follows updates.
  # /Applications/Nix Apps is where nix-darwin copies systemPackages' bundles; it is a stable
  # path (not a store path), so this keeps pointing at the current version by itself.
  home.file.".local/bin/puddle".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/Nix Apps/Puddle.app/Contents/Resources/puddle";

  # Same for Whisky's CLI (bottles, `run`, `shellenv` for driving its Wine by hand). The cask only
  # installs the app, so nothing else puts it on PATH.
  home.file.".local/bin/whisky".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/Whisky.app/Contents/Resources/WhiskyCmd";

  # tenbin: shell client for Tenbin AI for UTokyo (reads the session cookie from Zen, so mac-only).
  # Was a hand-placed ~/.local/bin/tenbin until 2026-09-15.
  home.file.".local/bin/tenbin" = {
    source = ../../configs/bin/tenbin;
    executable = true;
  };

  # macmini の管理者認証ダイアログにパスワードを入れる。人が叩くもので、Claude は実行しない
  # (アカウントのパスワードを代わりに入力しない線は、保管場所が sops になっても変わらない)。
  # TCC のトグルは authorizationdb を緩めても認証を要求するので、この手数は消せない。
  home.file.".local/bin/macmini-auth" = {
    source = ../../configs/bin/macmini-auth;
    executable = true;
  };

  # Bitwig driven from scripts: DrivenByMoss's "Open Sound Control" controller is the receive/send
  # end inside Bitwig; `bitwig` is the stdlib-only OSC client on this side. DrivenByMoss is neither in
  # nixpkgs nor brew (mossgrabers.de zip), so it is fetched and linked into Bitwig's library dir.
  # Bitwig only picks up .bwextension files from <library>/Extensions; the controller itself still
  # has to be added once in Settings > Controllers (that state lives in Bitwig's binary prefs) and
  # needs a MIDI input to activate: the IAC Driver, set online once via CoreMIDI (see `bitwig` help).
  home.file."Documents/Bitwig Studio/Extensions/DrivenByMoss.bwextension".source = "${
    pkgs.fetchzip {
      url = "https://www.mossgrabers.de/Software/Bitwig/DrivenByMoss-26.6.5-Bitwig.zip";
      hash = "sha256-DIFJBY9SX4QklKeSaazG/DJ+0psKKO+hfsO51+OQQC4=";
      stripRoot = false;
    }
  }/DrivenByMoss.bwextension";
  home.file.".local/bin/bitwig" = {
    source = ../../configs/bin/bitwig;
    executable = true;
  };

  # RetroArch cores for the GB/GBC/GBA/DS emulation that used to be four standalone apps
  # (hosts/darwin.nix, Emulation). Not declared as store paths on purpose: nixpkgs' libretro
  # cores pull in retroarch-bare, which is marked broken on aarch64-darwin, and libretro's
  # buildbot only publishes an unpinned nightly "latest" (no versioned URL to hash). So this
  # is a declared procedure instead - fetch each missing core from the same buildbot the app's
  # own Core Updater uses, into the directory retroarch.cfg points at. Delete a .dylib to get
  # a fresh one on the next switch; RetroArch's updater can also refresh them in place.
  # ponytail: "missing" is the only trigger, no staleness check - the updater covers that.
  home.activation.retroarchCores = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dir="${config.home.homeDirectory}/Library/Application Support/RetroArch/cores"
    /bin/mkdir -p "$dir"
    for core in sameboy mgba melonds; do
      [ -e "$dir/''${core}_libretro.dylib" ] && continue
      echo "retroarch: fetching $core core"
      tmp=$(/usr/bin/mktemp -d)
      $DRY_RUN_CMD /usr/bin/curl -fsSL -o "$tmp/core.zip" \
        "https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/''${core}_libretro.dylib.zip" \
        && $DRY_RUN_CMD /usr/bin/unzip -q -o "$tmp/core.zip" -d "$dir" \
        || echo "retroarch: $core core download failed (offline?), skipping" >&2
      /bin/rm -rf "$tmp"
    done
  '';

  # voicevox-engine: the engine that VOICEVOX.app bundles, started by hand for the REST API
  # (talk + singing: /sing_frame_audio_query -> /frame_synthesis). On macOS 27 it aborts on
  # every synthesis in nixpkgs' Apple libffi; the shim swaps in upstream libffi at load time
  # (see pkgs/libffi-mit-shim.nix). VOICEVOX.app launches the unshimmed engine itself, so the
  # editor stays affected until nixpkgs fixes libffi; only this CLI is covered.
  home.file.".local/bin/voicevox-engine" = {
    executable = true;
    text = ''
      #!/bin/sh
      export DYLD_LIBRARY_PATH=${
        pkgs.callPackage ../pkgs/libffi-mit-shim.nix { }
      }/lib''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}
      exec ${lib.getExe pkgs.voicevox-engine} --host 127.0.0.1 --port 50021 "$@"
    '';
  };

  home.file.".config/ghostty" = {
    source = ../../configs/terminals/ghostty;
    recursive = true;
  };

  # OmniWM / CodexBar: both apps write their own config back on every UI change, so a store
  # symlink (read-only) breaks saving. Out-of-store symlinks instead — the app writes straight
  # into the repo, which replaces the old `just app-snapshot` one-way mirror (removed 2026-08-13).
  # CodexBar's config carries the Codex account UUID; this repo is public, but a bare account
  # identifier is not a credential, so it is tracked as-is.
  home.file.".config/omniwm/settings.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/wm/omniwm/settings.toml";
  home.file.".config/codexbar/config.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/apps/codexbar/config.json";
  # Ghostty: resolution-variable font size. Computes font-size from the main display's logical
  # vertical resolution and writes it to ~/.config/ghostty.local/font-size.conf (config includes it with ?).
  # Recomputed on every nh home switch. If you change resolution, switch again, or
  # run scripts/ghostty-fontsize.sh by hand → config reload in Ghostty to apply.
  home.activation.ghosttyFontSize = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.bash}/bin/bash ${../../scripts/ghostty-fontsize.sh}
  '';

  # lazygit: this Mac sets XDG_CONFIG_HOME=~/.config, so lazygit
  # prefers reading ~/.config/lazygit/config.yml. Meanwhile programs.lazygit on Darwin
  # writes to ~/Library/Application Support/lazygit/, so common.nix's theme settings
  # aren't actually applied (the empty file on the ~/.config side takes precedence).
  # So also generate programs.lazygit.settings at the XDG path to make it reliably effective.
  # (This definition is Darwin-only. On Linux, HM's lazygit module itself defines the same path,
  #  so putting it in common.nix would conflict.)
  #
  # builtins.toFile で書く。pkgs.formats.yaml の generate はビルダーを要する派生に
  # なり、CI (x86_64-linux) が darwin 用のそれを掴むと platform mismatch で落ちる。
  # キャッシュに在るうちは代替で済むので表に出ないが、nixpkgs を上げた途端に落ちた。
  # JSON は YAML 1.2 の部分集合なので lazygit はそのまま読める。
  xdg.configFile."lazygit/config.yml".text = builtins.toJSON config.programs.lazygit.settings;

  # Element Desktop reads config.json from its profile directory on top of the bundled
  # one. Point it at the self-hosted homeserver so a fresh sign-in needs no server entry.
  # Account-level settings live on the server (account data) and are not declared here.
  home.file."Library/Application Support/Element/config.json".text = builtins.toJSON {
    default_server_config."m.homeserver" = {
      base_url = "https://matrix.gapul.net";
      server_name = "gapul.net";
    };
    disable_guests = true;
    default_country_code = "JP";
  };

  # MechvibesDX at login, in place of a System Settings login item. Lives here
  # rather than in darwin-services.nix because it needs the package path from
  # the let block above.
  #
  # Started through the signed copy's executable, not $out/bin, so macOS still
  # sees a real .app - the tray icon and the Accessibility entry both depend on
  # that.
  # --minimized keeps it in the tray at login: the config-driven start_minimized
  # only applies when auto_start is set, which is the Windows registry path.
  launchd.agents.mechvibes-dx = {
    enable = true;
    config = {
      ProgramArguments = [
        "${mechvibesApp}/Contents/MacOS/mechvibes-dx"
        "--minimized"
      ];
      RunAtLoad = true;
      # No KeepAlive on purpose: quitting from the tray should stay quit, and a
      # crash loop on an app this experimental would be worse than silence.
      ProcessType = "Interactive"; # keystroke->sound latency, same as mopidy's agent
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/MechvibesDX/mechvibes-dx.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/MechvibesDX/mechvibes-dx.log";
    };
  };

  home.activation.mechvibesLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p "${config.home.homeDirectory}/Library/Logs/MechvibesDX"
  '';

  # NTKDaemon: Native Access's local daemon (ZeroMQ 5146/5563) that `na` drives.
  # NA launches it on demand as an app (launchctl label `application.…NTKDaemon…`),
  # so removing the GUI would leave nothing to start it. This agent is that starter,
  # and the binary stays where NA's installer put it (proprietary, not nix-built);
  # nix only owns the agent. Note: if the GUI is still installed, launching it spawns
  # a second NTKDaemon that collides on the ports — remove /Applications/Native Access.app.
  #
  # Deliberately not resident. It used to be RunAtLoad + KeepAlive, which meant a NI
  # daemon ran from login for the sake of a CLI used a few times a year — and once the
  # binary disappeared (NTK uninstalled, 2026-08) launchd sat in a throttled respawn loop
  # logging "No such file or directory" forever. The `na` wrapper in home.packages
  # kickstarts this label instead, so the daemon's lifetime matches Native Access use.
  launchd.agents.ntkdaemon = {
    enable = true;
    config = {
      ProgramArguments = [ ntkDaemon ];
      RunAtLoad = false;
      # KeepAlive off as well: with nothing to restart it, a daemon that exits stays
      # exited until the next `na`, which is what "on demand" has to mean here.
      KeepAlive = false;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/NTKDaemon/ntkdaemon.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/NTKDaemon/ntkdaemon.log";
    };
  };
  # keystats' three agents (net.gapul.keystats{,.gui,.update}) are installed by the app itself,
  # and it keeps them correct: launched from the nix package it rewrote all three to point at
  # /Applications/Nix Apps within minutes. Declaring them here as well was tried and reverted —
  # the nix labels differ from the app's, so both sets loaded and two keystatsd ran side by side.
  # Leave agent ownership with the app; nix owns the bundle.
  #
  # The consequence to know about: net.gapul.keystats.update still runs keystats-update daily,
  # and it can no longer replace a read-only store copy. Silencing it belongs upstream in
  # keystats (skip self-update when the bundle is not writable), not in a plist this repo deletes
  # and the app immediately writes back.

  home.activation.ntkdaemonLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p "${config.home.homeDirectory}/Library/Logs/NTKDaemon"
  '';

  # TCC pins its rows to the code signature, and what nix builds is ad-hoc
  # signed: the requirement is a bare cdhash, so every rebuild of the package
  # silently revokes Accessibility and the app goes quiet (twice so far,
  # 2026-08-09 and 2026-08-13). Signing with the Developer ID that keystats
  # uses turns the requirement into a certificate check, which survives.
  #
  # codesign cannot write into the store, hence the copy. The copy still links its dylibs by
  # absolute store path, so the source has to stay alive: interpolating ${mechvibes-dx} into this
  # script puts it in the generation's references, which is what roots it. It is deliberately not
  # in home.packages - that would also link the bundle into ~/Applications/Home Manager Apps and
  # leave a second, unsigned MechvibesDX.app next to this one.
  #
  # Before setupLaunchAgents so the bundle exists when launchd is told to start
  # it. Deliberately not fatal: an unsignable bundle should cost the keystroke
  # sounds, not the whole activation.
  home.activation.mechvibesSign =
    lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
      ''
        src=${mechvibes-dx}/Applications/MechvibesDX.app
        stamp="${config.xdg.stateHome}/mechvibes-dx-store-path"
        if [ "$(cat "$stamp" 2>/dev/null)" != "$src" ] || ! /usr/bin/codesign -v "${mechvibesApp}" 2>/dev/null; then
          $DRY_RUN_CMD /bin/mkdir -p "${config.xdg.stateHome}"
          $DRY_RUN_CMD /bin/rm -rf "${mechvibesApp}" "$stamp"
          $DRY_RUN_CMD /bin/cp -R "$src" "${mechvibesApp}"
          $DRY_RUN_CMD /bin/chmod -R u+w "${mechvibesApp}"
          # No --options runtime: the hardened runtime blocks the WebView's JIT.
          if $DRY_RUN_CMD /usr/bin/codesign --force \
            --sign "Developer ID Application: Yuki Kawashima (S3H296G6Q5)" "${mechvibesApp}"; then
            $DRY_RUN_CMD echo "$src" > "$stamp"
          else
            echo "mechvibes-dx: codesign failed, Accessibility will need re-granting" >&2
          fi
        fi
      '';
}
