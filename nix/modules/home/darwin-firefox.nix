# Darwin Firefox component (ECS: profile). Firefox Developer Edition, declared end to end:
# arkenfox hardening plus the overrides this machine needs, the extensions and policies, the
# Zen-like auto-hiding chrome, and the one WebRTC pref that lets Slack huddles connect.
#
# Why a second Gecko browser next to Zen (2026-09-17): Zen has no Widevine licence, so DRM
# playback never works there, and Helium (the Chromium here) ships no CDM either. Mozilla's
# build carries the licence, so this is the browser for Netflix / Prime Video / Spotify web
# and for calls. Zen stays the daily driver for its workspaces.
#
# The .app is the cask (hosts/darwin.nix, see the note there on signing). home-manager runs
# with package = null and only owns the profile and the policies; on darwin the policies go
# to the app's managed-preferences domain instead of a policies.json inside the bundle.
{
  config,
  pkgs,
  ...
}:
let
  profile = "dev";
  chromeDir = "${config.programs.firefox.profilesPath}/${profile}/chrome";

  # MrOtherGuy's autohide hacks, pinned by commit. Together they are Zen's compact mode on
  # stock Firefox: toolbar and sidebar stay out of the way until the pointer reaches the edge.
  csshacksRev = "c887ca5fa6ea0915f00be339cb9910aed9586121";
  csshack =
    name: sha256:
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/MrOtherGuy/firefox-csshacks/${csshacksRev}/chrome/${name}";
      inherit sha256;
    };

  amo = slug: {
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
    installation_mode = "force_installed";
    # Land in the extensions panel, not on the nav bar: the puzzle button is the one icon.
    # Applies on install; an already pinned button is unpinned by hand once.
    default_area = "menupanel";
  };
in
{
  programs.firefox = {
    enable = true;
    package = null; # the cask owns the bundle
    darwinDefaultsId = "org.mozilla.firefoxdeveloperedition";

    policies = {
      # The store copy cannot update itself anyway; saying so stops the nag and leaves the
      # version to `just maintain` (brew --greedy), the same path the other auto_updates casks take.
      DisableAppUpdate = true;
      # Zen stays the default browser; without this the first run parks a "make Firefox your
      # primary browser" panel over the page.
      DontCheckDefaultBrowser = true;
      # Extensions come from AMO and keep updating there. The list is Zen's set as of
      # 2026-09-17 (everything enabled there except Zen Internet, which only makes sense with
      # Zen's transparent content area, and DuckDuckGo Privacy Essentials, which duplicates
      # uBlock Origin; KeePassXC-Browser was disabled and is left out),
      # so the two browsers feel the same. Each content script is a cost on every page, so trim
      # here rather than in the UI: force_installed means the UI cannot remove them.
      ExtensionSettings = {
        "{ef87d84c-2127-493f-b952-5b4e744245bc}" = amo "aw-watcher-web"; # ActivityWatch Web Watcher
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = amo "bitwarden-password-manager"; # Bitwarden Password Manager
        "{e58d3966-3d76-4cd9-8552-1582fbc800c1}" = amo "buster-captcha-solver"; # Buster: Captcha Solver for Humans
        "addon@darkreader.org" = amo "darkreader"; # Dark Reader
        "@testpilot-containers" = amo "multi-account-containers"; # Firefox Multi-Account Containers
        "firenvim@lacamb.re" = amo "firenvim"; # Firenvim
        "floccus@handmadeideas.org" = amo "floccus"; # floccus bookmarks sync
        "{f4961478-ac79-4a18-87e9-d2fb8c0442c4}" = amo "global-speed"; # Global Speed - Video Speed Control
        "headereditor-amo@addon.firefoxcn.net" = amo "header-editor"; # Header Editor
        "LINEPorted@FoxRefire" = amo "line-firefox-ported"; # LINE
        "{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}" = amo "search_by_image"; # Search by Image
        "sponsorBlocker@ajay.app" = amo "sponsorblock"; # SponsorBlock for YouTube - Skip Sponsorships
        "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" = amo "styl-us"; # Stylus
        "{a8332c60-5b6d-41ee-bfc8-e9bb331d34ad}" = amo "surfingkeys_ff"; # Surfingkeys
        "@ublacklist" = amo "ublacklist"; # uBlacklist
        "uBlock0@raymondhill.net" = amo "ublock-origin"; # uBlock Origin
        "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}" = amo "violentmonkey"; # Violentmonkey
        "{d07ccf11-c0cd-4938-a265-2a4d6ad01189}" = amo "view-page-archive"; # Web Archives
        "{799c0914-748b-41df-a25c-22d008f9e83f}" = amo "web-scrobbler"; # Web Scrobbler
      };
    };

    arkenfox = {
      enable = true;
      # master, pinned by the flake lock: the last tagged release (144.0, 2026-04) predates the
      # Firefox this runs on, and master is where arkenfox tracks current releases.
      version = "master";
      profiles.${profile} = {
        enableAllSections = true;
        settings = {
          # 2800 clears cookies and site data on every exit. The logins for the DRM services
          # and Slack are the whole point of this browser, so they have to survive a restart.
          "2800".enable = false;
          # Brave sends Global Privacy Control by default; arkenfox leaves it inactive. Turn it on.
          "7000"."7021"."privacy.globalprivacycontrol.enabled".enable = true;
        };
      };
    };

    profiles.${profile} = {
      id = 0;
      isDefault = true;
      search = {
        default = "ddg";
        force = true; # search.json.mozlz4 is regenerated on every switch, Firefox's copy loses
      };
      settings = {
        # Toolbar layout, declared. Firefox rewrites this pref while running; user.js puts it
        # back on every start, so a toolbar dragged around in the UI lasts until the restart.
        # The nav bar is the url bar and the extensions button, nothing else. Extensions sit
        # in the extensions panel; new ones land there through the default_area policy above.
        # (Vertical-tabs mode re-adds back/forward on start; the CSS below hides those.)
        "browser.uiCustomization.state" = builtins.toJSON {
          placements = {
            "widget-overflow-fixed-list" = [ ];
            "unified-extensions-area" = [
              "ublock0_raymondhill_net-browser-action"
              "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
            ];
            "nav-bar" = [
              "urlbar-container"
              "unified-extensions-button"
            ];
            "toolbar-menubar" = [ "menubar-items" ];
            TabsToolbar = [ ];
            "vertical-tabs" = [ "tabbrowser-tabs" ];
            PersonalToolbar = [ "personal-bookmarks" ];
          };
          seen = [
            "reset-pbm-toolbar-button"
            "developer-button"
            "profiler-button"
            "smartwindow-group-tabs-button"
            "ai-window-toggle"
            "screenshot-button"
            "ublock0_raymondhill_net-browser-action"
            "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
          ];
          dirtyAreaCache = [
            "nav-bar"
            "TabsToolbar"
            "vertical-tabs"
            "unified-extensions-area"
            "PersonalToolbar"
          ];
          currentVersion = 26; # Firefox 157's CustomizableUI kVersion; a lower value replays migrations
          newElementCount = 1;
        };
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # load userChrome.css

        # Slack huddles on Firefox 155+: the DTLS ClientHello carries an X25519MLKEM768 key
        # share (1459 bytes, split over two records through TURN) and Slack's Chime media
        # server never answers it, so the call sits on "connecting" for 72 s and gives up.
        # Measured with tcpdump on 2026-09-17; without the PQ key share the handshake completes.
        "media.webrtc.send_mlkem_keyshare" = false;

        # Native macOS vibrancy behind the toolbar and the tab strip. Cheap, unlike making the
        # content area transparent (browser.tabs.allow_transparent_browser), which repaints the
        # whole window and is what made Zen feel slow here — left off on purpose.
        "browser.theme.macos.native-theme" = true;
        "widget.macos.titlebar-blend-mode.behind-window" = true;

        # Stock vertical tabs; the sidebar hack below hides them until hovered.
        "sidebar.verticalTabs" = true;
        # Minimal chrome, the pref half (the CSS half is in userChrome below). No bookmarks
        # toolbar. No tool buttons at the bottom of the tab strip: the pref lists the enabled
        # tools, but an empty list is treated as "first run" and refilled with the defaults, so
        # name something that is not a tool. The customize gear that remains is clipped away
        # in userChrome.
        "browser.toolbars.bookmarks.visibility" = "never";
        "sidebar.main.tools" = "none";
      };
      userChrome = ''
        @import url("autohide_toolbox.css");
        @import url("autohide_sidebar.css");

        /* Vertical tab strip (#sidebar-container, Firefox 157) slides off the left edge and comes
           back when the pointer reaches it. autohide_sidebar.css only covers the classic panel.
           10px stay inside the window as the hit area; the strip is invisible (opacity 0) while
           hidden, so that overhang does not show. */
        #browser { position: relative; }
        #sidebar-container {
          position: absolute;
          inset-block: 0;
          inset-inline-start: 0;
          z-index: 3;
          transform: translateX(calc(-100% + 10px));
          transition: transform 150ms ease 350ms;
          background-color: transparent;
        }
        #sidebar-container > sidebar-main {
          /* Overlaid on page content, so it needs a colour of its own: the launcher's usual one is
             the native (vibrancy) window background, which is transparent here. -moz-Dialog follows
             the chrome colour scheme. */
          background-color: -moz-Dialog;
          opacity: 0;
          transition: opacity 150ms ease 350ms;
        }
        #sidebar-container:is(:hover, :focus-within) { transform: none; transition-delay: 0ms; }
        #sidebar-container:is(:hover, :focus-within) > sidebar-main { opacity: 1; transition-delay: 0ms; }
        #sidebar-launcher-splitter { display: none !important; }

        /* Minimal chrome: the nav bar keeps back, forward, the url bar and the extensions button.
           Everything else is reachable from the macOS menu bar or a shortcut. */
        #alltabs-button, #smartwindow-group-tabs-button, #ai-window-toggle, #sidebar-button,
        #home-button, #PanelUI-button, #fxa-toolbar-menu-button,
        #star-button-box, #reader-mode-button, #picture-in-picture-button { display: none !important; }
        /* Vertical-tabs mode puts back/forward (and a spacer) back on the nav bar on every start
           regardless of the declared placements, so they are hidden here. ⌘[ / ⌘] and the
           trackpad swipe remain. */
        #back-button, #forward-button, #vertical-spacer { display: none !important; }

        /* The tab strip's bottom row holds only the "customize sidebar" gear once the tools
           are off. It lives in sidebar-main's shadow DOM, out of reach of selectors, so the
           host is pulled past the container's clip edge by the row's height instead. */
        #sidebar-container > sidebar-main { margin-block-end: -52px; }
      '';
    };
  };

  home.file = {
    "${chromeDir}/autohide_toolbox.css".source =
      csshack "autohide_toolbox.css" "02xycvjiwk7qzji7llhxwhqyysgg26fbg39p9hl18lfjykjnjldr";
    "${chromeDir}/autohide_sidebar.css".source =
      csshack "autohide_sidebar.css" "103a8hamkz0218x4q6xfny5qrasdh1cwdkfcjn82ilfcf4cv1647";
  };
}
