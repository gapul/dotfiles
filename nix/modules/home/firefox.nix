# Firefox component (ECS: profile), shared by the Mac and the NixOS laptop. Firefox Developer
# Edition, declared end to end: arkenfox hardening plus the overrides this setup needs, the
# extensions and policies, a keyboard-only chrome (nothing on screen but the page; Surfingkeys
# drives it, the url bar floats in on ⌘L / Ctrl+L), and the one WebRTC pref that lets Slack
# huddles connect.
#
# History: it came in on the Mac next to Zen (2026-09-17) because Zen has no Widevine licence,
# so DRM playback never worked there, and Helium (the Chromium) ships no CDM either. Since
# 2026-09-26 it has been the default browser and the daily driver: Zen's places.sqlite (history
# and bookmarks), cookies, form history and logins were moved into this profile by hand. Zen was
# removed from both machines on 2026-10-01.
#
# This file only owns the profile and the policies. Where the browser itself comes from is the
# platform's business: modules/home/darwin-firefox.nix (the cask, package = null) and
# home/linux-gui.nix (nixpkgs' firefox-devedition).
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
  # Install each style in Stylus from its updateUrl so Stylus keeps it current. They stay light
  # in both OS modes (2026-10-30: wanted in dark mode too, so the light-only export is gone).
  xdg.dataFile."firefox/light-site-themes.json".text = builtins.toJSON {
    mode = "always (both OS color schemes)";
    styles = [
      {
        domain = "open.spotify.com";
        name = "Light Theme Spotify";
        updateUrl = "https://raw.githubusercontent.com/ThatOneUnoriginal/Spotify-Light/main/LightThemeSpotify.user.css";
        preferScheme = "none";
        darkReaderExcluded = true;
      }
      {
        domain = "music.youtube.com";
        name = "YouTube Music — Google Light + Dark Player";
        updateUrl = "https://raw.githubusercontent.com/docrepath/youtube-music-google-light-dark-player/main/YouTubeMusic-Google-Light-Dark-Player.user.css";
        preferScheme = "none";
        darkReaderExcluded = true;
      }
    ];
  };

  programs.firefox = {
    enable = true;

    policies = {
      # Updates come from outside the app on both platforms (brew --greedy on the Mac, the flake
      # lock on Linux); saying so stops the nag.
      DisableAppUpdate = true;
      # This is the default browser (the Mac sets it once with `defaultbrowser
      # firefoxdeveloperedition`, Linux through xdg.mimeApps). Without this a profile that is not
      # yet the default parks a "make Firefox your primary browser" panel over the page.
      DontCheckDefaultBrowser = true;
      # No page translation (the offer bar and the feature itself).
      TranslateEnabled = false;
      # No Mozilla account: bookmarks ride floccus and there is nothing else to sync, so the
      # account button, the "Sign in" menu entries and the Sync settings all go away.
      DisableFirefoxAccounts = true;
      # Cut the rest of the traffic to Mozilla that arkenfox does not already cover (2026-09-26).
      # Still allowed on purpose: AMO (extension installs/updates), remote-settings (OneCRL
      # certificate revocations and the add-on blocklist), the GMP updater (Widevine, the reason
      # this browser exists) and the push service (Slack's web notifications ride it).
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisableFeedbackCommands = true;
      DisablePocket = true;
      CaptivePortal = false;
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        UrlbarInterventions = false;
        SkipOnboarding = true;
        MoreFromMozilla = false;
        WhatsNew = false;
        FirefoxLabs = false;
        Locked = true;
      };
      FirefoxSuggest = {
        WebSuggestions = false;
        SponsoredSuggestions = false;
        ImproveSuggest = false;
        Locked = true;
      };
      FirefoxHome = {
        SponsoredTopSites = false;
        Pocket = false;
        SponsoredPocket = false;
      };
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
          # Added 2026-09-26: strip tracking parameters from URLs (what ClearURLs does), and
          # the annoyance lists for cookie banners, newsletter/notification prompts.
          "adguard-spyware-url"
          "fanboy-cookiemonster"
          "ublock-cookies-easylist"
          "ublock-annoyances"
          "easylist-newsletters"
          "easylist-notifications"
        ];
      };
      # Surfingkeys reads no managed storage; its settings live in configs/apps/surfingkeys/config.js,
      # fetched by the extension from this repo's raw URL ("Load settings from" in advanced
      # mode; set once per profile, the file:// scheme is refused by Firefox extensions):
      #   https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/surfingkeys/config.js

      # Extensions come from AMO and keep updating there. The list is Zen's set as of
      # 2026-09-17 (Zen Internet is enabled on Linux for transparent pages; DuckDuckGo
      # Privacy Essentials is omitted because it duplicates
      # uBlock Origin; KeePassXC-Browser was disabled and is left out). Trimmed on 2026-09-22:
      # LINE, Web Archives, Search by Image, Global Speed (the one non-FOSS entry;
      # playback speed is a Surfingkeys binding instead).
      # so the two browsers feel the same. Each content script is a cost on every page, so trim
      # here rather than in the UI: force_installed means the UI cannot remove them.
      ExtensionSettings = {
        "{ef87d84c-2127-493f-b952-5b4e744245bc}" = amo "aw-watcher-web"; # ActivityWatch Web Watcher
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = amo "bitwarden-password-manager"; # Bitwarden Password Manager
        "{e58d3966-3d76-4cd9-8552-1582fbc800c1}" = amo "buster-captcha-solver"; # Buster: Captcha Solver for Humans
        "@testpilot-containers" = amo "multi-account-containers"; # Firefox Multi-Account Containers
        # Firenvim was dropped on 2026-10-18; blocked so the copies already installed are removed.
        "firenvim@lacamb.re".installation_mode = "blocked";
        "floccus@handmadeideas.org" = amo "floccus"; # floccus bookmarks sync
        "headereditor-amo@addon.firefoxcn.net" = amo "header-editor"; # Header Editor
        "sponsorBlocker@ajay.app" = amo "sponsorblock"; # SponsorBlock for YouTube - Skip Sponsorships
        "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" = amo "styl-us"; # Stylus
        "{a8332c60-5b6d-41ee-bfc8-e9bb331d34ad}" = amo "surfingkeys_ff"; # Surfingkeys
        "@ublacklist" = amo "ublacklist"; # uBlacklist
        "uBlock0@raymondhill.net" = amo "ublock-origin"; # uBlock Origin
        "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}" = amo "violentmonkey"; # Violentmonkey
        "{799c0914-748b-41df-a25c-22d008f9e83f}" = amo "web-scrobbler"; # Web Scrobbler
        # Added 2026-09-26 on request, both FOSS:
        # Allow temporarily disabling DeArrow without uninstalling its saved settings.
        "deArrow@ajay.app" = (amo "dearrow") // {
          installation_mode = "normal_installed";
        };
        "{c607c8df-14a7-4f28-894f-29e8722976af}" = amo "temporary-containers"; # Temporary Containers
        # Added 2026-10-11: NIP-07 (window.nostr) bridge to a NIP-46 remote signer, for sites that
        # only know extension login (events.kojira.io). Keys stay in the bunker; the extension holds
        # the session and per-site permissions. MIT, github.com/dsbaars/bunker46-extension.
        "@bunker46-extension" = amo "bunker46"; # Bunker46
        # Dropping an entry above leaves an already installed extension in place as an ordinary
        # one; only "blocked" makes Firefox uninstall it. These were in the list once.
        "LINEPorted@FoxRefire".installation_mode = "blocked"; # LINE
        "{d07ccf11-c0cd-4938-a265-2a4d6ad01189}".installation_mode = "blocked"; # Web Archives
        # Follow OS dark mode on sites without their own automatic theme. Configure
        # Dark Reader once per profile: automation System/Scheme, detect dark theme on.
        # Dark-only sites with a dedicated light UserCSS use Stylus instead, installed from
        # the updateUrls in ~/.local/share/firefox/light-site-themes.json; exclude those
        # domains in Dark Reader.
        # Prefer maintained site-specific styles over reversing Dark Reader's light palette.
        "addon@darkreader.org" =
          if pkgs.stdenv.hostPlatform.isLinux then amo "darkreader" else { installation_mode = "blocked"; };
        "{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}".installation_mode = "blocked"; # Search by Image
        "{f4961478-ac79-4a18-87e9-d2fb8c0442c4}".installation_mode = "blocked"; # Global Speed
        # Website backgrounds need site-specific CSS as well as the transparent window below.
        "{91aa3897-2634-4a8a-9092-279db23a7689}" =
          if pkgs.stdenv.hostPlatform.isLinux then amo "zen-internet" else { installation_mode = "blocked"; };
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
        # GTK/Wayland must allocate an alpha-capable window at startup. The tab pref lets
        # Zen Internet's transparent website backgrounds reach that window (Linux only).
        "widget.transparent-windows" = pkgs.stdenv.hostPlatform.isLinux;
        "browser.tabs.allow_transparent_browser" = pkgs.stdenv.hostPlatform.isLinux;
        # File pickers through the xdg portal (yazi via termfilechooser on the laptop) instead
        # of Firefox's own GTK dialog. 1 = always, 2 = Firefox's default auto-detect.
        "widget.use-xdg-desktop-portal.file-picker" = if pkgs.stdenv.hostPlatform.isLinux then 1 else 2;

        # Slack huddles on Firefox 155+: the DTLS ClientHello carries an X25519MLKEM768 key
        # share (1459 bytes, split over two records through TURN) and Slack's Chime media
        # server never answers it, so the call sits on "connecting" for 72 s and gives up.
        # Measured with tcpdump on 2026-09-17; without the PQ key share the handshake completes.
        "media.webrtc.send_mlkem_keyshare" = false;

        # Developer Edition ships with its dark theme switched on; follow the system appearance
        # instead (Firefox's "System theme — auto").
        "extensions.activeThemeID" = "default-theme@mozilla.org";
        # 0 = dark, 1 = light, 2 = follow the system. Firefox derives these from the active
        # theme; pinned so the chrome and content color scheme cannot drift from the System
        # theme above. (The dark UI seen on 2026-09-26 after switching themes was something
        # else: extensions.json had been edited by hand, so addonStartup.json.lz4 still
        # started the dark theme at boot. Switch themes through AddonManager, never by editing
        # the addon DB.)
        "browser.theme.toolbar-theme" = 2;
        "browser.theme.content-theme" = 2;

        # Vertical tabs on Firefox's own expand-on-hover; userChrome pushes the collapsed strip
        # off screen so nothing shows until the pointer reaches the left edge.
        "sidebar.verticalTabs" = true;
        "sidebar.visibility" = "expand-on-hover";
        # Ctrl+Tab goes to the tab used last (and on through recent ones while Ctrl is held),
        # like Alt+Tab between windows, instead of the next tab in the strip.
        "browser.ctrlTab.sortByRecentlyUsed" = true;
        # Minimal chrome, the pref half (the CSS half is in userChrome below). No bookmarks
        # toolbar. No tool buttons at the bottom of the tab strip: the pref lists the enabled
        # tools, but an empty list is treated as "first run" and refilled with the defaults, so
        # name something that is not a tool.
        "browser.toolbars.bookmarks.visibility" = "never";
        "sidebar.main.tools" = "none";

        # Minimal nav bar, the pref half (userChrome is off, see above): only what Firefox refuses
        # to remove (back, forward, the url bar, the app menu) plus the extensions button. This is
        # the whole Customize layout, so Customize edits revert on the next start. Added 2026-10-11.
        # Dropped from the defaults: all-tabs list, Smart Window tab grouping, AI window toggle,
        # the sidebar toggle (vertical tabs expand on hover) and the spacer. currentVersion must
        # track CustomizableUI's kVersion, otherwise Firefox migrates the layout and puts buttons
        # back; ids in "seen" are what keeps Firefox from re-inserting them as "new" widgets.
        "browser.uiCustomization.state" = builtins.toJSON {
          placements = {
            widget-overflow-fixed-list = [ ];
            unified-extensions-area = [
              "_ef87d84c-2127-493f-b952-5b4e744245bc_-browser-action"
              "_a8332c60-5b6d-41ee-bfc8-e9bb331d34ad_-browser-action"
              "sponsorblocker_ajay_app-browser-action"
              "_ublacklist-browser-action"
              "_aecec67f-0d10-4fa7-b7c7-609a2db280cf_-browser-action"
              "headereditor-amo_addon_firefoxcn_net-browser-action"
              "_799c0914-748b-41df-a25c-22d008f9e83f_-browser-action"
              "_c607c8df-14a7-4f28-894f-29e8722976af_-browser-action"
              "_testpilot-containers-browser-action"
              "dearrow_ajay_app-browser-action"
              "ublock0_raymondhill_net-browser-action"
              "_7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action"
              "_e58d3966-3d76-4cd9-8552-1582fbc800c1_-browser-action"
              "floccus_handmadeideas_org-browser-action"
              "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
            ];
            nav-bar = [
              "back-button"
              "forward-button"
              "urlbar-container"
              "unified-extensions-button"
            ];
            toolbar-menubar = [ "menubar-items" ];
            TabsToolbar = [ ];
            vertical-tabs = [ "tabbrowser-tabs" ];
            PersonalToolbar = [ "personal-bookmarks" ];
          };
          seen = [
            "reset-pbm-toolbar-button"
            "developer-button"
            "profiler-button"
            "smartwindow-group-tabs-button"
            "ai-window-toggle"
            "alltabs-button"
            "sidebar-button"
            "vertical-spacer"
            "screenshot-button"
            "_ef87d84c-2127-493f-b952-5b4e744245bc_-browser-action"
            "_a8332c60-5b6d-41ee-bfc8-e9bb331d34ad_-browser-action"
            "sponsorblocker_ajay_app-browser-action"
            "_ublacklist-browser-action"
            "_aecec67f-0d10-4fa7-b7c7-609a2db280cf_-browser-action"
            "headereditor-amo_addon_firefoxcn_net-browser-action"
            "_799c0914-748b-41df-a25c-22d008f9e83f_-browser-action"
            "_c607c8df-14a7-4f28-894f-29e8722976af_-browser-action"
            "_testpilot-containers-browser-action"
            "dearrow_ajay_app-browser-action"
            "ublock0_raymondhill_net-browser-action"
            "_7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action"
            "_e58d3966-3d76-4cd9-8552-1582fbc800c1_-browser-action"
            "floccus_handmadeideas_org-browser-action"
            "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
          ];
          dirtyAreaCache = [
            "nav-bar"
            "TabsToolbar"
            "vertical-tabs"
            "unified-extensions-area"
            "toolbar-menubar"
            "PersonalToolbar"
          ];
          currentVersion = 28;
          newElementCount = 0;
        };

        # Mozilla endpoints arkenfox leaves open: region lookup, AMO metadata for the add-ons
        # pane, Merino (urlbar suggestions) and the new-tab feeds.
        "browser.region.network.url" = "";
        "browser.region.update.enabled" = false;
        "extensions.getAddons.cache.enabled" = false;
        "browser.urlbar.quicksuggest.enabled" = false;
        "browser.newtabpage.activity-stream.feeds.system.topstories" = false;
        "browser.newtabpage.activity-stream.telemetry" = false;

        # Japanese default fonts. On the mac: Kyuji Mincho / Kyuji Gothic
        # (github.com/gapul/kyuji-font), which draw shinjitai text with kyujitai glyphs without
        # changing the text. They are copied into ~/Library/Fonts by hand while that repo is
        # private (a private flake input would break evaluation wherever no GitHub token is set),
        # so Linux has no copy and naming them there left Firefox's ja defaults pointing at a
        # missing family. Linux names Noto CJK JP instead.
        # Pages that name their own fonts are covered by the repo's Violentmonkey script.
        "font.name.serif.ja" =
          if pkgs.stdenv.hostPlatform.isDarwin then "Kyuji Mincho" else "Noto Serif CJK JP";
        "font.name.sans-serif.ja" =
          if pkgs.stdenv.hostPlatform.isDarwin then "Kyuji Gothic" else "Noto Sans CJK JP";
      };
      userContent =
        if pkgs.stdenv.hostPlatform.isLinux then
          ''
            @-moz-document url("about:newtab"), url("about:home"), url("about:blank") {
              html, body { background: transparent !important; }
            }
            /* Internal management pages cannot be styled by Zen Internet. Clear only their
               canvas; keep native cards, form fields and dialogs legible in both OS modes. */
            @-moz-document url-prefix("about:preferences"), url-prefix("about:addons"),
                           url-prefix("about:config"), url-prefix("about:logins"),
                           url-prefix("about:downloads"), url-prefix("about:profiles"),
                           url-prefix("about:support"), url-prefix("about:processes"),
                           url-prefix("about:protections") {
              :root {
                --rp-internal-panel: light-dark(rgb(250 244 237 / 72%), rgb(25 23 36 / 72%));
                background: transparent !important;
              }
              body, .main-content, .config-background-wrapper {
                background: transparent !important;
              }
              .sticky-container, #prefsStickyHeader, #search-container, login-list {
                background-color: var(--rp-internal-panel) !important;
                backdrop-filter: blur(24px) !important;
              }
            }
            /* Dark Reader's document fallback must not cover Zen Internet's transparent canvas.
               Restrict this to pages styled by both extensions; ordinary sites retain their background. */
            @-moz-document url-prefix("https://"), url-prefix("http://") {
              html[data-darkreader-scheme]:has(style#zeninternet-styles),
              html[data-darkreader-scheme]:has(style#zeninternet-styles) body {
                background-color: transparent !important;
              }
            }
            /* The upstream Spotify style predates Encore's current text classes.
               Keep this small compatibility layer separate so Stylus can update upstream. */
            @-moz-document domain("open.spotify.com") {
              html, body, #main { background-color: transparent !important; }
              #global-nav-bar, nav, aside {
                background-color: rgb(250 244 237 / 72%) !important;
              }
              [data-encore-id="text"], h1, h2, h3, a, button, input {
                color: #262626 !important;
              }
              [data-encore-id="icon"], [data-encore-id="logo"] { fill: currentColor !important; color: #262626 !important; }
              main > div > div { background-image: none !important; }
              [data-testid="main-view-container"] { background-color: #edede6 !important; }
            }
            /* Frost site navigation panels without fading their text or artwork. Both sites
               wear a light style in either OS mode, so the glass is always the light one. */
            @-moz-document domain("music.youtube.com"), domain("open.spotify.com") {
              #guide #contentContainer,
              .Root__nav-bar, .Root__right-sidebar {
                background: rgb(250 244 237 / 72%) !important;
                backdrop-filter: blur(24px) saturate(115%) !important;
              }
            }
          ''
        else
          "";
      userChrome = ''
        @import url("autohide_toolbox.css");
        /* autohide_toolbox.css paints the toolbox with --lwt-accent-color and falls back to
           black; the stock System theme sets no such variable, so the bar came up black (seen
           2026-10-11, once the desktop switched to light). Use the colour the toolbox has. */
        #navigator-toolbox {
          background-color: var(--toolbox-background-color, var(--toolbar-bgcolor, -moz-dialog)) !important;
        }

        /* Rosé Pine for the chrome, Linux only (2026-10-11): Dawn while the page prefers light,
           Main when it prefers dark, so it follows the System theme and darkman like the rest of
           the laptop. The Mac keeps its native vibrancy. Values are palettes.json copied by hand
           (userChrome cannot read it). These are Firefox's design tokens (toolkit design-system
           tokens-platform.css, browser/themes/shared/urlbar/*.tokens.css, tabs.css); user-sheet
           !important beats the token layers, and light-dark() resolves through the color-scheme
           Firefox already sets from browser.theme.toolbar-theme = 2. */
        @media (-moz-platform: linux) {
          :root, .tabbrowser-tab, #urlbar, .urlbarView {
            --rp-base: light-dark(#faf4ed, #191724);
            --rp-surface: light-dark(#fffaf3, #1f1d2e);
            --rp-overlay: light-dark(#f2e9e1, #26233a);
            --rp-muted: light-dark(#9893a5, #6e6a86);
            --rp-subtle: light-dark(#797593, #908caa);
            --rp-text: light-dark(#575279, #e0def4);
            --rp-love: light-dark(#b4637a, #eb6f92);
            --rp-gold: light-dark(#ea9d34, #f6c177);
            --rp-rose: light-dark(#d7827e, #ebbcba);
            --rp-pine: light-dark(#286983, #31748f);
            --rp-foam: light-dark(#56949f, #9ccfd8);
            --rp-iris: light-dark(#907aa9, #c4a7e7);
            --rp-hl: light-dark(#dfdad9, #403d52);
            --rp-iris-weak: color-mix(in srgb, var(--rp-iris) 16%, transparent);
          }
          :root {
            /* toolbox (window frame + the hidden toolbar), nav bar */
            --toolbox-background-color: var(--rp-base) !important;
            --toolbox-background-color-inactive: var(--rp-base) !important;
            --toolbox-background-gradient: image(transparent) !important;
            --toolbox-text-color: var(--rp-text) !important;
            --toolbox-text-color-inactive: var(--rp-subtle) !important;
            --toolbar-background-color: var(--rp-base) !important;
            --toolbar-text-color: var(--rp-text) !important;
            --toolbarbutton-icon-fill: var(--rp-subtle) !important;
            --toolbarbutton-icon-fill-attention: var(--rp-iris) !important;
            /* url bar */
            --toolbar-field-background-color: var(--rp-overlay) !important;
            --toolbar-field-background-color-focus: var(--rp-surface) !important;
            --toolbar-field-text-color: var(--rp-text) !important;
            --toolbar-field-text-color-focus: var(--rp-text) !important;
            --toolbar-field-border-color: transparent !important;
            --toolbar-field-border-color-focus: var(--rp-iris) !important;
            --urlbarview-background-color-hover: var(--rp-iris-weak) !important;
            --urlbarview-background-color-selected: var(--rp-overlay) !important;
            --urlbarview-text-color-selected: var(--rp-text) !important;
            --urlbarview-text-color-secondary: var(--rp-subtle) !important;
            --urlbarview-text-color-action: var(--rp-iris) !important;
            --urlbarview-separator-color: var(--rp-hl) !important;
            /* sidebar launcher and panels, popups, menus, inputs */
            --sidebar-background-color: var(--rp-base) !important;
            --sidebar-text-color: var(--rp-text) !important;
            --sidebar-border-color: var(--rp-hl) !important;
            --panel-background-color: var(--rp-surface) !important;
            --panel-text-color: var(--rp-text) !important;
            --arrowpanel-background: var(--rp-surface) !important;
            --arrowpanel-color: var(--rp-text) !important;
            --arrowpanel-border-color: var(--rp-hl) !important;
            --input-background-color: var(--rp-overlay) !important;
            --input-text-color: var(--rp-text) !important;
            --background-color-canvas: var(--rp-base) !important;
            --background-color-box: var(--rp-surface) !important;
            --background-color-list-item-hover: var(--rp-iris-weak) !important;
            --text-color-list-item-hover: var(--rp-text) !important;
            --chrome-content-separator-color: var(--rp-hl) !important;
            /* accent, focus, links */
            --color-accent-primary: var(--rp-iris) !important;
            --color-accent-primary-hover: color-mix(in srgb, var(--rp-iris) 85%, var(--rp-text)) !important;
            --color-accent-primary-active: color-mix(in srgb, var(--rp-iris) 70%, var(--rp-text)) !important;
            --color-accent-primary-selected: var(--rp-iris) !important;
            --focus-outline-color: var(--rp-iris) !important;
            --link-color: var(--rp-foam) !important;
            --link-color-hover: var(--rp-pine) !important;
            --link-color-active: var(--rp-pine) !important;
            --link-color-visited: var(--rp-iris) !important;
          }
          /* vertical tabs: the tokens are read on the tab, so set them there too */
          :root, .tabbrowser-tab {
            --tab-background-color: transparent !important;
            --tab-background-color-hover: var(--rp-iris-weak) !important;
            --tab-background-color-selected: var(--rp-overlay) !important;
            --tab-text-color: var(--rp-subtle) !important;
            --tab-text-color-hover: var(--rp-text) !important;
            --tab-text-color-selected: var(--rp-text) !important;
          }
        }
        /* Linux glass: retain opaque text/icons and tint only the window background.
           Site backgrounds are opt-in via Zen Internet; normal opaque pages stay opaque.
           Keep URL suggestions and popup menus on their existing solid Rosé Pine surfaces. */
        @media (-moz-platform: linux) {
          :root {
            --rp-glass: color-mix(in srgb, var(--rp-base) 76%, transparent);
            --toolbox-background-color: transparent !important;
            --toolbox-background-color-inactive: transparent !important;
            --toolbar-background-color: transparent !important;
            --sidebar-background-color: var(--rp-glass) !important;
            --tabpanel-background-color: transparent !important;
            --chrome-content-separator-color: transparent !important;
            background: var(--rp-glass) !important;
          }
          body, #browser, #appcontent, #tabbrowser-tabbox, #tabbrowser-tabpanels, #sidebar-container,
          .browserContainer, .browserStack, browser[type="content"],
          #nav-bar, #PersonalToolbar, #TabsToolbar, #titlebar, #toolbar-menubar {
            background: transparent !important;
          }
          sidebar-main, #sidebar-main, #sidebar-box {
            /* Preserve visible transparency even where Firefox cannot blur remote page pixels
               (Mozilla bug 1799334); an opaque fallback defeats the requested glass appearance. */
            background-color: color-mix(in srgb, var(--rp-surface) 72%, transparent) !important;
            backdrop-filter: blur(24px) saturate(115%) !important;
            box-shadow: inset -1px 0 color-mix(in srgb, var(--rp-hl) 45%, transparent) !important;
          }
        }
        /* nav bar: url bar and the extensions button only. The layout pref above already drops
           everything removable; these are the ones Firefox refuses to remove in Customize. */
        #back-button, #forward-button, #PanelUI-button, #star-button-box { display: none !important; }

        /* Vertical tabs launcher: fully off screen until the pointer reaches the left edge.
           Rewritten 2026-10-11 after the previous version (margin keyed on :has([expanded]) plus
           a CSS transition) made the launcher expand and collapse in a loop: Firefox now drives
           expand-on-hover with view transitions and, after each one, re-checks the pointer
           against the launcher's rect (browser-sidebar.js _reconcileHoverState). Animating the
           same element on our own clock left it mid-slide at each check. So: no transition
           (Firefox's own view transition animates the slide), and the collapsed state is keyed
           on the attribute Firefox sets synchronously, not on the Lit-reflected [expanded].
           While expanded the container is position:absolute over the page, so it needs nothing.
           Firefox subtracts a 4px splitter from the hover rect, so 8px visible = 4px hit area. */
        :root[sidebar-expand-on-hover] #sidebar-container:not([sidebar-launcher-expanded]) {
          margin-inline-start: calc(8px - var(--sidebar-launcher-collapsed-width));
        }
        /* The 8px that stay in the window are the launcher's own edge and paint in the toolbox
           colour, so they showed as a thin bar. Hover detection compares pointer coordinates
           with the launcher's rect and never asks what is drawn on top, so the page can simply
           cover the strip: pull the content area 8px left while collapsed (it is the later
           sibling, so it paints over the launcher). While expanded Firefox pads the content by
           the collapsed launcher width to keep the page still; ours sits off screen, so 0 keeps
           the page where it was instead of jumping right on every hover. */
        :root[sidebar-expand-on-hover] #tabbrowser-tabbox:not([sidebar-positionend]) {
          margin-inline-start: -8px !important;
        }
        :root[sidebar-expand-on-hover] #tabbrowser-tabbox[sidebar-launcher-expanded]:not([sidebar-panel-open]):not([sidebar-positionend]) {
          margin-inline-start: 0 !important;
        }
        /* With the launcher "shown" Firefox draws a 1px separator (--chrome-content-separator-color)
           and a rounded corner on the content's edges that face chrome (content-area.css). The
           left one is what was left of the strip; the top one meets the hidden toolbar. Both
           edges meet the window now, so square them off the way Firefox does in fullscreen. */
        :root[sidebar-expand-on-hover] #tabbrowser-tabbox:not([sidebar-positionend]) .browserContainer {
          --content-area-start-radius: 0;
          /* Without browser.nova.enabled the radius is set directly, not through the variable,
             and a 0.01px outline in the separator colour traces it: that was the light arc left
             at the top-left corner (seen 2026-10-11, Firefox 158). */
          border-start-start-radius: 0 !important;
          outline: none !important;
          box-shadow: none !important;
          border-inline-start: none !important;
          border-block-start: none !important;
        }
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
