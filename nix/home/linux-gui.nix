{
  config,
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

  # Use Qt's built-in styles: the session's Kvantum theme lacks its QML module.
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
  # The profile stays at ~/.mozilla/firefox (home-manager's new default is under
  # ~/.config; moving it is a manual migration, not worth a profile scare).
  programs.firefox.configPath = ".mozilla/firefox";
  programs.firefox.package = pkgs.firefox-devedition.overrideAttrs (old: {
    makeWrapperArgs = old.makeWrapperArgs ++ [
      "--add-flags"
      "--profile ${config.home.homeDirectory}/${config.programs.firefox.profilesPath}/dev"
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

  # Keep the rest of the clutter out of ~ as well: GTK 2's rc file and adb's state dir.
  gtk.gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
  home.sessionVariables.ANDROID_USER_HOME = "${config.xdg.dataHome}/android";

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
    google-chrome # for sites that only test against Chrome, and for the automation profile
    tor-browser

    # ─── Passwords / 2FA ───
    bitwarden-desktop # the vault the SSH agent policy is built around
    keepassxc # offline vault (the same kdbx the iOS KeePassium build reads)

    # ─── Notes / Documents ───
    obsidian # vault syncs over the self-hosted CouchDB LiveSync
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
    android-tools # adb; USB permissions are provided by systemd
    scrcpy # Android display and control
    (callPackage ../pkgs/syncclipboard.nix { })
    localsend # AirDrop-shaped transfer to the phone
    kdePackages.kdeconnect-kde
    rustdesk

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
    (import ../pkgs/touchdesigner.nix { inherit pkgs; })
    musescore
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
    nixpkgsStable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.zotero
    anki
    retroarch
    moonlight-qt
    brave-origin
    (callPackage ../pkgs/slimbrave-neo.nix { }) # Brave enterprise-policy editor
    (pkgs.callPackage ../pkgs/helium.nix { })
    orca-slicer # Bambu A1 mini, same profile set as the mac

    # ─── Utilities ───
    # Dictionary lookup. Reads the StarDict (and slob) sets kept in the assets annex under
    # references/dictionaries/; point it at a checkout from Edit > Dictionaries > Sources.
    goldendict-ng
    zathura # Keyboard-driven PDF viewer, also used by Yazi.
    foliate # EPUB reader; its OPDS catalog pulls books from Kavita for offline reading.
    swayimg # Wayland image viewer, also used by Yazi.
    imhex # hex editor

    # ─── Wayland extras that have no macOS counterpart ───
    swappy # annotate what hyprshot captured
    wl-mirror # mirror a region into a window (for screen sharing a slice)

    # ─── Non-Steam game launchers ───
    # Steam itself is system-side (programs.steam in hosts/nixos-laptop.nix) because it
    # needs the 32-bit graphics stack. These two only manage their own prefixes.
    lutris # GOG / standalone installers / emulators
    heroic # Epic / GOG / Amazon — the libraries the homelab free-games claimer fills up
  ];

}
