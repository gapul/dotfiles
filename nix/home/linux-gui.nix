{
  config,
  lib,
  pkgs,
  nixpkgsStable,
  user,
  ...
}:
# GUI apps for the NixOS laptop. Imported only on nixos-laptop.
#
# The mac declares the same set as Homebrew casks (hosts/darwin.nix): on darwin nixpkgs GUI
# builds are unbundled and miss Spotlight / TCC / Launch Services, so casks win there. On
# Linux there is no such split, so the packages go straight into the closure and stay
# declarative.
#
# The browser is the exception to "just a package": Firefox Developer Edition is the daily
# driver on both machines and its profile/policies live in modules/home/firefox.nix (shared with
# the Mac), so it is wired through programs.firefox below instead of the list. It replaced Zen
# here on 2026-10-01; Zen's old profile (~/.zen) is left on disk for manual deletion.
let
  browser = "firefox-devedition.desktop"; # nixpkgs' wrapper names it after the binary
  creativeWineApps = import ../pkgs/creative-wine-apps.nix { inherit pkgs; };
  niji = pkgs.callPackage ../pkgs/nijigenerate.nix { };
  # adb ignores ANDROID_USER_HOME and always keeps its key and server state in $HOME/.android,
  # so it runs with HOME pointed into the XDG data dir; the state lands in
  # ~/.local/share/android/.android. scrcpy puts its own android-tools first on PATH, so it is
  # given this one instead of reading the variable.
  androidTools = pkgs.symlinkJoin {
    name = "android-tools-xdg";
    paths = [ pkgs.android-tools ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/adb --set HOME ${config.xdg.dataHome}/android
    '';
  };
  # Tor Browser 15 and Zotero are built on Firefox ESR 140, which predates Firefox 147's XDG
  # support: Tor keeps its profile in ~/.tor project, Zotero in ~/.zotero and ~/Zotero, and
  # Zotero also leaves an empty ~/.mozilla/extensions. Both run with HOME pointed into the XDG
  # data dir instead, the same way as adb above. The GTK file dialogs start at that HOME, so
  # the real folders the app is used with are linked into it: Downloads and Documents for
  # Zotero (attaching PDFs), none for Tor, whose downloads stay out of the real home.
  withXdgHome =
    pkg: bin: dir: links:
    pkgs.symlinkJoin {
      name = "${pkg.pname or bin}-xdg-home";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/${bin} \
          --set HOME ${config.xdg.dataHome}/${dir} \
          --run ${
            pkgs.lib.escapeShellArg (
              "mkdir -p ${config.xdg.dataHome}/${dir}"
              + pkgs.lib.concatMapStrings (
                d:
                "; [ -e ${config.xdg.dataHome}/${dir}/${d} ] || ln -s ${config.home.homeDirectory}/${d} ${config.xdg.dataHome}/${dir}/${d}"
              ) links
            )
          }
      '';
    };
in
{
  imports = [
    ./ios-integration.nix
    ../modules/home/firefox.nix
    ./linux-resident.nix
    ./keystats-linux.nix
    ./t3code-desktop.nix # T3 Code nightly (AppImage + CLI, self-updating)
    ./fcitx5-skk.nix # SKK dictionaries and kana rule for fcitx5-skk
    ./xremap.nix # mac-style Cmd / Ctrl / Hyper
    ./opensnitch-ui.nix # which app connects where, LuLu-style; the daemon is in hosts/nixos-laptop.nix
    ./gaming.nix # Prism Launcher, MangoHud, the Cartridges library
  ];

  # Keep the English UI locale while preferring Japanese CJK fallback glyphs.
  xdg.configFile."fontconfig/conf.d/51-japanese-cjk.conf".text = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <!-- Preserve Latin faces; prefer Japanese glyphs for shared CJK code points. -->
      <alias binding="strong">
        <family>sans-serif</family>
        <prefer>
          <family>DejaVu Sans</family>
          <family>Noto Sans CJK JP</family>
        </prefer>
      </alias>
      <alias binding="strong">
        <family>serif</family>
        <prefer>
          <family>DejaVu Serif</family>
          <family>Noto Serif CJK JP</family>
        </prefer>
      </alias>
      <alias binding="strong">
        <family>monospace</family>
        <prefer>
          <family>DejaVu Sans Mono</family>
          <family>Noto Sans Mono CJK JP</family>
        </prefer>
      </alias>
    </fontconfig>
  '';

  # Syncthing as a systemd user service, like the Mac's LaunchAgent (modules/home/darwin-services.nix).
  # Paired with homelab/syncthing.nix, where this machine is device "nixos-laptop". Both overrides
  # are false so devices and folders accepted in the GUI survive a rebuild. The identity lives in
  # ~/.local/state/syncthing (cert.pem / key.pem); recreating it means a new device ID to re-pair.
  services.syncthing = {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
    settings = {
      devices."homeserver".id = "Y72TVZZ-IE3MUPY-3YI6D63-HON47QT-2UYVWHN-5C5N5RY-T2H4ID7-T776ZQF";
      folders."synchub" = {
        label = "SyncHub";
        path = "${config.home.homeDirectory}/Sync/syncthing";
        devices = [ "homeserver" ];
        type = "sendreceive";
      };
      # ROMs and decrypted dumps, homeserver's /srv/games/library (homelab/syncthing.nix).
      # Receive-only: homeserver holds the originals, and nothing here is meant to be edited.
      # Saves are written outside it (home/gaming.nix).
      folders."games-library" = {
        label = "Games Library";
        path = "${config.home.homeDirectory}/Games/library";
        devices = [ "homeserver" ];
        type = "receiveonly";
      };
      # Drop a PDF here and Paperless on the homeserver consumes it (same as the Mac).
      folders."paperless-inbox" = {
        label = "Paperless Inbox";
        path = "${config.home.homeDirectory}/Sync/paperless-inbox";
        devices = [ "homeserver" ];
        type = "sendreceive";
      };
    };
  };

  # Use Qt's built-in styles: the session's Kvantum theme lacks its QML module.
  # Lan Mouse's daemon, so the Mac can cross over without the GUI open. The GUI talks to it and
  # writes the peers and authorised fingerprints to ~/.config/lan-mouse/config.toml.
  systemd.user.services.lan-mouse = {
    Unit = {
      Description = "Lan Mouse input sharing";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.lan-mouse}/bin/lan-mouse daemon";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.librepods = {
    Unit = {
      Description = "LibrePods AirPods controls";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.librepods}/bin/librepods --hide";
      Environment = [
        "QT_QUICK_CONTROLS_STYLE=Basic"
        "QT_STYLE_OVERRIDE=Fusion"
        "QT_QPA_PLATFORMTHEME="
        # Qt writes qDebug straight to journald when it sees JOURNAL_STREAM, bypassing the
        # null stdout below: the AirPods' MagicAccIRK / MagicAccEncKey ended up in the journal.
        "QT_FORCE_STDERR_LOGGING=1"
        "QT_LOGGING_RULES=*.debug=false;*.info=false"
      ];
      Restart = "on-failure";
      RestartSec = 3;
      # Upstream logs device pairing keys; do not persist its output to the journal.
      StandardOutput = "null";
      StandardError = "null";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  xdg.desktopEntries."me.kavishdevar.librepods" = {
    name = "LibrePods";
    comment = "AirPods battery and noise controls (system tray)";
    exec = "${pkgs.systemd}/bin/systemctl --user start librepods.service";
    icon = "me.kavishdevar.librepods";
    categories = [ "Utility" ];
    terminal = false;
  };
  xdg.configFile."wireplumber/wireplumber.conf.d/51-airpods.conf".text = ''
    wireplumber.settings = {
      bluetooth.autoswitch-to-headset-profile = false
    }
  '';

  # Fusuma runs in the graphical session and dispatches directly to Hyprland.
  # Four fingers leave two-finger application gestures and three-finger drag free.
  # Hyprland only: niri has these gestures built in (three fingers sideways scroll the columns,
  # up/down switch workspaces, four fingers open the overview), and fusuma's four-finger swipes
  # would fire on top of them.
  xdg.configFile."fusuma/config.yml".text = ''
    swipe:
      4:
        left:
          command: "${pkgs.hyprland}/bin/hyprctl dispatch workspace r+1"
        right:
          command: "${pkgs.hyprland}/bin/hyprctl dispatch workspace r-1"
        up:
          command: "${config.xdg.configHome}/wofi/launcher open"
        down:
          command: "${config.xdg.configHome}/wofi/launcher close"
    plugin:
      inputs:
        libinput_command_input:
          device: "/dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event-mouse"
      filters:
        libinput_device_filter:
          keep_device_names:
            - "SYNA312F:00 06CB:CFE2 Touchpad"
  '';
  systemd.user.services.fusuma = {
    Unit = {
      Description = "Fusuma touchpad gestures";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecCondition = "${import ../lib/wm-session.nix { inherit pkgs; }}/bin/wm-session is hyprland";
      ExecStart = "${pkgs.fusuma}/bin/fusuma --config ${config.xdg.configHome}/fusuma/config.yml";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Always start on the declared profile. Developer Edition ignores profiles.ini's Default=1 and
  # creates a "dev-edition-default" profile of its own, which it then has to write into
  # profiles.ini; home-manager links that file read-only from the store, so the write fails and
  # Firefox stops at "Profile Missing" (2026-10-08, Firefox 156). The wrapper already sets
  # MOZ_LEGACY_PROFILES=1, which no longer prevents it. --profile skips the lookup entirely, and
  # links opened later still reach the running window because they name the same profile.
  # overrideAttrs keeps .override working, which home-manager uses to inject the policies.
  # The profile lives under XDG_CONFIG_HOME (Firefox 147+ uses it when ~/.mozilla/firefox is
  # absent). Set explicitly: home-manager only defaults to it from stateVersion 26.05. Moved from
  # ~/.mozilla/firefox by hand on 2026-10-18.
  programs.firefox.configPath = "${pkgs.lib.removePrefix "${config.home.homeDirectory}/" config.xdg.configHome}/mozilla/firefox";
  # home-manager always lists the Firefox package itself as a native-messaging host, so it links
  # ~/.mozilla/native-messaging-hosts (only a .keep: the package ships no hosts) and ~/.mozilla
  # outlives the profile's move to XDG_CONFIG_HOME. With Firenvim gone there are no hosts at all.
  mozilla.firefoxNativeMessagingHosts = pkgs.lib.mkForce [ ];
  programs.firefox.package = pkgs.firefox-devedition.overrideAttrs (old: {
    makeWrapperArgs = old.makeWrapperArgs ++ [
      "--add-flags"
      "--profile ${config.home.homeDirectory}/${config.programs.firefox.profilesPath}/dev"
      # A link opened from T3 Code starts Firefox with T3's environment (home/t3code-desktop.nix),
      # and GDK_BACKEND=x11 there put the whole browser on XWayland: no kinetic touchpad
      # scrolling, so pages stuck to the fingers (2026-10-28). The session sets none of these.
      "--unset"
      "GDK_BACKEND"
      "--unset"
      "GTK_IM_MODULE"
      "--unset"
      "GTK_IM_MODULE_FILE"
    ];
  });

  # Without user-dirs.dirs every XDG_*_DIR resolves to $HOME, so hyprshot and friends dropped
  # their output straight into ~ (2026-10-11). Only the folders actually in use are declared;
  # the rest stay null rather than seeding empty Desktop/Music/Public/Templates.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = false; # xdg-user-dir reads user-dirs.dirs directly
    documents = "${config.home.homeDirectory}/Documents";
    download = "${config.home.homeDirectory}/Downloads";
    pictures = "${config.home.homeDirectory}/Pictures";
    videos = "${config.home.homeDirectory}/Videos";
    desktop = null;
    music = null;
    publicShare = null;
    templates = null;
    projects = null;
  };

  # Code lives under ghq.root (modules/home/git.nix), not loose in ~/src. Seed the root and
  # the own-account level so `ghq get` / `ghq create` have a place to land on a fresh install.
  systemd.user.tmpfiles.rules = [
    "d ${config.programs.git.settings.ghq.root}/github.com/${user.gitUser} 0755 - - -"
  ];

  # Keep the rest of the clutter out of ~ as well: GTK 2's rc file, the Android SDK tools' state
  # dir (adb itself needs the wrapper above), and the PulseAudio cookie that clients with an old
  # bundled libpulse (Steam's runtime) write to ~/.pulse-cookie.
  gtk.gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
  home.sessionVariables.ANDROID_USER_HOME = "${config.xdg.dataHome}/android";
  home.sessionVariables.PULSE_COOKIE = "${config.xdg.configHome}/pulse/cookie";

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "application/pdf" = "org.pwmt.zathura.desktop";
      "application/epub+zip" = "com.github.johnfactotum.Foliate.desktop";
      "image/png" = "swayimg.desktop";
      "image/jpeg" = "swayimg.desktop";
      "image/webp" = "swayimg.desktop";
      "image/gif" = "swayimg.desktop";
      "image/svg+xml" = "swayimg.desktop";
      "text/html" = browser;
      "application/xhtml+xml" = browser;
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      "x-scheme-handler/about" = browser;
      "x-scheme-handler/unknown" = browser;
      "x-scheme-handler/cavalry" = "cavalry.desktop";
      "x-scheme-handler/affinity" = "affinity.desktop";
      # claude-cli:// deep links. Claude Code writes this association (and its own .desktop
      # under ~/.local/share/applications) into an unmanaged mimeapps.list on its own; once
      # the file became home-manager's, that copy blocked activation ("would be clobbered")
      # and replacing it would have dropped the handler, so it is declared here instead.
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };
  # Claude Code re-registers its handler with a plain write, which can turn the symlink back
  # into a regular file and fail the next rebuild the same way. Everything it writes is
  # declared above, so overwriting that copy loses nothing.
  xdg.configFile."mimeapps.list".force = true;

  # File pickers (the portal's FileChooser, set to termfilechooser in hosts/nixos-laptop.nix)
  # open yazi in ghostty. The class gives the window its own app id, which niri floats
  # (home/niri.nix). It also keeps ghostty out of a running instance, because the portal waits
  # for this process to exit before reading the selection.
  # Opening: Enter picks the file under the cursor, Space selects several, q cancels.
  # Saving: the portal creates the suggested file (with help text, hence create_help_file=1)
  # and yazi starts on it; pick it with Enter, or rename it first. With 0 the file does not
  # exist and there is nothing to pick, so every save ends as a cancel.
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=${pkgs.xdg-desktop-portal-termfilechooser}/share/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh
    default_dir=$HOME
    create_help_file=1
    env=TERMCMD=${pkgs.ghostty}/bin/ghostty --class=net.gapul.termfilechooser --title=termfilechooser -e
    open_mode=suggested
    save_mode=suggested
  '';

  # The input preset for calls (RNNoise only), made in EasyEffects' GUI on 2026-10-13. It is a
  # read-only symlink, so changing it means editing it here; "Save as" a new name still works.
  # Which preset is loaded is runtime state in ~/.config/easyeffects/db and stays mutable.
  xdg.dataFile."easyeffects/input/Calls - Noise Reduction.json".text = builtins.toJSON {
    input = {
      blocklist = [ ];
      plugins_order = [ "rnnoise#0" ];
      "rnnoise#0" = {
        bypass = false;
        input-gain = 0.0;
        output-gain = 0.0;
        model-name = "";
        use-standard-model = true;
        enable-vad = false;
        vad-thres = 50.0;
        wet = 0.0;
        release = 20.0;
      };
    };
  };

  # claude-cli:// handler. Claude Code's native installer wrote this pointing at its own
  # ~/.local/bin/claude; the CLI now comes only from nixpkgs (hosts/nixos-laptop.nix), so the
  # entry calls whatever `claude` is on PATH. force: Claude Code may rewrite it on its own.
  # RQuickShare listens on a random port unless .settings.json names one, and the firewall only
  # opens a fixed one (networking.firewall.interfaces.wlp0s20f3 in hosts/nixos-laptop.nix).
  # The app rewrites the file itself and fills missing keys with defaults, so only "port" is set.
  home.activation.rquickshare-port =
    let
      jq = lib.getExe pkgs.jq;
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cfg="${config.xdg.dataHome}/dev.mandre.rquickshare/.settings.json"
      run mkdir -p "$(dirname "$cfg")"
      if [ -f "$cfg" ]; then
        new=$(${jq} '.port = 41200' "$cfg")
      else
        new='{"port":41200}'
      fi
      if [[ ! -v DRY_RUN ]]; then printf '%s\n' "$new" >"$cfg"; fi
    '';

  # xtool keeps the App Store Connect key and the signing certificate's private key under
  # ~/.config/xtool/data, written world-readable (0644, 2026-10-28). Keep the directory private.
  home.activation.xtool-private = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${config.xdg.configHome}/xtool/data"
    run chmod 700 "${config.xdg.configHome}/xtool" "${config.xdg.configHome}/xtool/data"
  '';

  xdg.dataFile."applications/claude-code-url-handler.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Name=Claude Code URL Handler
      Comment=Handle claude-cli:// deep links for Claude Code
      Exec=claude --handle-uri %u
      Type=Application
      NoDisplay=true
      MimeType=x-scheme-handler/claude-cli;
    '';
  };

  # These synth packages ship standalone binaries without desktop entries.
  xdg.desktopEntries.cardinal = {
    name = "Cardinal";
    exec = "Cardinal";
    terminal = false;
    categories = [
      "AudioVideo"
      "Audio"
    ];
  };
  xdg.desktopEntries.surge-xt = {
    name = "Surge XT";
    exec = ''"Surge XT"'';
    terminal = false;
    categories = [
      "AudioVideo"
      "Audio"
    ];
  };

  home.packages = with pkgs; [
    fusuma
    librepods
    # Screen of the Mac mini over the tailnet. Was a hand-written ~/.local/bin script calling
    # `nix run nixpkgs#tigervnc`; the password stays a mutable file (vncpasswd output).
    (writeShellApplication {
      name = "vnc-macmini";
      runtimeInputs = [ tigervnc ];
      text = ''exec vncviewer -passwd "${config.xdg.configHome}/tigervnc/macmini.passwd" 100.105.135.49 "$@"'';
    })
    # ─── Browsers ───
    (withXdgHome tor-browser "tor-browser" "tor-browser" [ ])

    # ─── Passwords / 2FA ───
    keepassxc # offline vault (the same kdbx the iOS KeePassium build reads)

    # ─── Notes / Documents ───
    obsidian # vault syncs over the self-hosted CouchDB LiveSync
    libreoffice
    thunderbird

    # ─── Messaging ───
    simplex-chat-desktop

    # ─── Devices / Remote ───
    # pymobiledevice3 7.7 needs qh3 < 2; unstable currently supplies qh3 2.x.
    (nixpkgsStable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.callPackage
      ../pkgs/pymobiledevice3.nix
      { }
    )
    libimobiledevice
    uxplay # iPhone AirPlay receiver
    # iOS apps from Linux: build, sign and install with an SDK made from the mac's Xcode.
    (callPackage ../pkgs/xtool.nix { })
    # ... and run them in iOS 16.5 under QEMU (`hackios setup`, `hackios run`, `hackios push`)
    (callPackage ../pkgs/hackios { })
    androidTools # adb; USB permissions are provided by systemd
    rquickshare # Quick Share with Android phones; port pinned below
    (scrcpy.override { android-tools = androidTools; }) # Android display and control
    (callPackage ../pkgs/syncclipboard.nix { })
    kdePackages.kdeconnect-kde

    # ─── Network ───
    mullvad-vpn

    # ─── Creative / CAD / DTM ───
    blender
    # From stable: unstable's freecad 1.1.4 is uncached and its vtk fails to configure (PEGTL
    # not found, 2026-10-12). Drop back to `freecad` once Hydra builds it again.
    nixpkgsStable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.freecad
    bitwig-studio
    reaper
    # Interactive audio/video sequencing and show control. From stable: unstable's 3.8.2 does
    # not compile against fmt 12 (is_container_adaptor_like, 2026-10-13). Drop back to
    # `ossia-score` once Hydra builds it again.
    nixpkgsStable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.ossia-score
    easyeffects # PipeWire audio processing; launch manually when needed.
    qpwgraph # PipeWire routing and patchbay.
    yabridge
    yabridgectl
    wineWow64Packages.yabridge # Wine version matched to yabridge; keep separate from game runners.
    obs-studio
    davinci-resolve
    creativeWineApps.cavalry
    creativeWineApps.affinity
    krita
    openutau
    niji.nijigenerate # Inochi2D rigging editor
    niji.nijiexpose # Inochi2D streaming runtime
    (import ../pkgs/touchdesigner.nix { inherit pkgs; })
    # musescore: dropped 2026-10-22 while 4.7.5 fails with Qt 6.12 (NixOS/nixpkgs#576580); re-add once that is fixed
    cardinal
    surge-xt
    vcv-rack
    puredata
    supercollider
    sonic-pi
    kicad
    godot
    calibre
    # Zotero 10 fails to build against the current Firefox ESR; use the stable input.
    (withXdgHome nixpkgsStable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.zotero "zotero"
      "zotero"
      [
        "Downloads"
        "Documents"
      ]
    )
    anki
    retroarch
    moonlight-qt
    (pkgs.callPackage ../pkgs/helium.nix { })
    orca-slicer # Bambu A1 mini, same profile set as the mac
    voicevox # same as the mac (hosts/darwin.nix); bundles voicevox-engine

    # ─── Utilities ───
    # Dictionary lookup. Reads the StarDict (and slob) sets kept in the assets annex under
    # references/dictionaries/; point it at a checkout from Edit > Dictionaries > Sources.
    goldendict-ng
    zathura # Keyboard-driven PDF viewer, also used by Yazi.
    xournalpp # handwriting on PDFs: fill in, sign, annotate (pressure-aware with Weylus)
    pdfarranger # reorder, merge and split PDF pages
    lan-mouse # one mouse and keyboard with the Mac; daemon below, GUI for pairing
    foliate # EPUB reader; its OPDS catalog pulls books from Kavita for offline reading.
    swayimg # Wayland image viewer, also used by Yazi.

    # ─── Wayland extras that have no macOS counterpart ───
    swappy # annotate what hyprshot captured
    wl-mirror # mirror a region into a window (for screen sharing a slice)

    # ─── Non-Steam game launchers ───
    # Prism Launcher is a home-manager module (home/gaming.nix).
    heroic # Epic / GOG / Amazon — the libraries the homelab free-games claimer fills up
    # One library window for all of them: Cartridges reads Steam and Heroic on its own
    # and needs no login. It only finds launchers installed the same way it is (nix here, not
    # Flatpak). The emulators below and Minecraft are declared into it in home/gaming.nix.
    cartridges
    azahar # 3DS (dumps on homeserver /srv/games/3ds)
    melonds # DS
    mgba # GBA
  ];

}
