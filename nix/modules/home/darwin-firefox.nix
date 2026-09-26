# Darwin Firefox component (ECS: profile). Firefox Developer Edition, declared end to end:
# arkenfox hardening plus the overrides this machine needs, the extensions and policies, a
# keyboard-only chrome (nothing on screen but the page; Surfingkeys drives it, the url bar
# floats in on ⌘L), and the one WebRTC pref that lets Slack huddles connect.
#
# Why a second Gecko browser next to Zen (2026-09-17): Zen has no Widevine licence, so DRM
# playback never works there, and Helium (the Chromium here) ships no CDM either. Mozilla's
# build carries the licence, so this is the browser for Netflix / Prime Video / Spotify web
# and for calls. Since 2026-09-26 it is also the default browser and the daily driver: Zen's
# places.sqlite (history and bookmarks), cookies, form history and logins were moved into
# this profile by hand; Zen stays installed but is not a login item any more.
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
      # This is the default browser (set once with `defaultbrowser firefoxdeveloperedition`;
      # macOS asks for confirmation, so it is not declared). Without this a profile that is
      # not yet the default parks a "make Firefox your primary browser" panel over the page.
      DontCheckDefaultBrowser = true;
      # No page translation (the offer bar and the feature itself).
      TranslateEnabled = false;
      # Per-extension settings, for the extensions that read browser.storage.managed. This is a
      # lock, not a seed: re-asserted on every start, so dashboard edits revert. uBlock Origin
      # caches it and applies one restart late (uAssets discussion 16939).
      "3rdparty".Extensions."uBlock0@raymondhill.net".toOverwrite = {
        # uBO's default lists plus the Japanese one. Ids are the keys of assets/assets.json.
        filterLists = [
          "user-filters"
          "ublock-filters"
          "ublock-badware"
          "ublock-privacy"
          "ublock-unbreak"
          "ublock-quick-fixes"
          "easylist"
          "easyprivacy"
          "urlhaus-1"
          "plowe-0"
          "JPN-1"
        ];
      };
      # Surfingkeys reads no managed storage; its settings live in configs/apps/surfingkeys/config.js,
      # fetched by the extension from this repo's raw URL ("Load settings from" in advanced
      # mode; set once per profile, the file:// scheme is refused by Firefox extensions):
      #   https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/surfingkeys/config.js

      # Extensions come from AMO and keep updating there. The list is Zen's set as of
      # 2026-09-17 (everything enabled there except Zen Internet, which only makes sense with
      # Zen's transparent content area, and DuckDuckGo Privacy Essentials, which duplicates
      # uBlock Origin; KeePassXC-Browser was disabled and is left out). Trimmed on 2026-09-22:
      # LINE, Web Archives, Dark Reader, Search by Image, Global Speed (the one non-FOSS entry;
      # playback speed is a Surfingkeys binding instead).
      # so the two browsers feel the same. Each content script is a cost on every page, so trim
      # here rather than in the UI: force_installed means the UI cannot remove them.
      ExtensionSettings = {
        "{ef87d84c-2127-493f-b952-5b4e744245bc}" = amo "aw-watcher-web"; # ActivityWatch Web Watcher
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = amo "bitwarden-password-manager"; # Bitwarden Password Manager
        "{e58d3966-3d76-4cd9-8552-1582fbc800c1}" = amo "buster-captcha-solver"; # Buster: Captcha Solver for Humans
        "@testpilot-containers" = amo "multi-account-containers"; # Firefox Multi-Account Containers
        "firenvim@lacamb.re" = amo "firenvim"; # Firenvim
        "floccus@handmadeideas.org" = amo "floccus"; # floccus bookmarks sync
        "headereditor-amo@addon.firefoxcn.net" = amo "header-editor"; # Header Editor
        "sponsorBlocker@ajay.app" = amo "sponsorblock"; # SponsorBlock for YouTube - Skip Sponsorships
        "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" = amo "styl-us"; # Stylus
        "{a8332c60-5b6d-41ee-bfc8-e9bb331d34ad}" = amo "surfingkeys_ff"; # Surfingkeys
        "@ublacklist" = amo "ublacklist"; # uBlacklist
        "uBlock0@raymondhill.net" = amo "ublock-origin"; # uBlock Origin
        "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}" = amo "violentmonkey"; # Violentmonkey
        "{799c0914-748b-41df-a25c-22d008f9e83f}" = amo "web-scrobbler"; # Web Scrobbler
        # Dropping an entry above leaves an already installed extension in place as an ordinary
        # one; only "blocked" makes Firefox uninstall it. These were in the list once.
        "LINEPorted@FoxRefire".installation_mode = "blocked"; # LINE
        "{d07ccf11-c0cd-4938-a265-2a4d6ad01189}".installation_mode = "blocked"; # Web Archives
        "addon@darkreader.org".installation_mode = "blocked"; # Dark Reader
        "{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}".installation_mode = "blocked"; # Search by Image
        "{f4961478-ac79-4a18-87e9-d2fb8c0442c4}".installation_mode = "blocked"; # Global Speed
        "{91aa3897-2634-4a8a-9092-279db23a7689}".installation_mode = "blocked"; # Zen Internet
        "jid1-ZAdIEUB7XOzOJw@jetpack".installation_mode = "blocked"; # DuckDuckGo Privacy Essentials
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
      # Zen's containers, same ids so a profile copied over keeps its per-container cookies.
      # Which site opens in which container is Multi-Account Containers' own storage and is
      # set in its UI. Firefox's stock Work/Banking/Shopping keep their built-in names.
      containersForce = true;
      containers = {
        personal = {
          id = 1;
          name = "Personal";
          icon = "fingerprint";
          color = "blue";
        };
        work = {
          id = 2;
          name = "Work";
          icon = "briefcase";
          color = "orange";
        };
        banking = {
          id = 3;
          name = "Banking";
          icon = "dollar";
          color = "green";
        };
        shopping = {
          id = 4;
          name = "Shopping";
          icon = "cart";
          color = "pink";
        };
        univ = {
          id = 6;
          name = "Univ";
          icon = "fence";
          color = "yellow";
        };
      };
      search = {
        # The self-hosted SearXNG (nix/homelab/searx.nix). It sits behind Authelia, so the first
        # search of a session lands on the login page and comes back to the results.
        default = "searx";
        privateDefault = "searx";
        force = true; # search.json.mozlz4 is regenerated on every switch, Firefox's copy loses
        engines.searx = {
          name = "search.gapul.net";
          urls = [ { template = "https://search.gapul.net/search?q={searchTerms}"; } ];
          definedAliases = [ "@s" ];
        };
      };
      settings = {
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
        # Developer Edition ships with its dark theme switched on; follow the macOS appearance
        # instead (Firefox's "System theme — auto"). Page content still renders light: arkenfox's
        # resistFingerprinting reports prefers-color-scheme: light to every site by design.
        "extensions.activeThemeID" = "default-theme@mozilla.org";

        # Vertical tabs on Firefox's own expand-on-hover; userChrome pushes the collapsed strip
        # off screen so nothing shows until the pointer reaches the left edge.
        "sidebar.verticalTabs" = true;
        "sidebar.visibility" = "expand-on-hover";
        # Minimal chrome, the pref half (the CSS half is in userChrome below). No bookmarks
        # toolbar. No tool buttons at the bottom of the tab strip: the pref lists the enabled
        # tools, but an empty list is treated as "first run" and refilled with the defaults, so
        # name something that is not a tool.
        "browser.toolbars.bookmarks.visibility" = "never";
        "sidebar.main.tools" = "none";
      };
      userChrome = ''
        @import url("autohide_toolbox.css");
        /* nav bar: url bar and the extensions button only (the rest was removed in Customize;
           these five Firefox keeps putting back) */
        #back-button, #forward-button, #vertical-spacer, #PanelUI-button, #star-button-box { display: none !important; }
        /* fully off screen until hovered (expand-on-hover leaves an icon column otherwise);
           6px stay inside the window as the hit area */
        #sidebar-container { margin-inline-start: calc(6px - var(--sidebar-launcher-collapsed-width)); transition: margin-inline-start 150ms; }
        #sidebar-container:has([expanded]) { margin-inline-start: 0; }
      '';
    };
  };

  # MrOtherGuy's toolbar autohide, pinned by commit: the toolbar stays off screen until the
  # pointer reaches the top edge (or ⌘L focuses the url bar).
  home.file."${chromeDir}/autohide_toolbox.css".source = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/MrOtherGuy/firefox-csshacks/c887ca5fa6ea0915f00be339cb9910aed9586121/chrome/autohide_toolbox.css";
    sha256 = "02xycvjiwk7qzji7llhxwhqyysgg26fbg39p9hl18lfjykjnjldr";
  };
}
