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
      # Extensions come from AMO and keep updating there. Keep this list short: this browser
      # exists for DRM and calls, and every content script here is one more thing on every page.
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = amo "ublock-origin";
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = amo "bitwarden-password-manager";
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

        # Stock vertical tabs; the sidebar hack below hides them until hovered.
        "sidebar.verticalTabs" = true;
      };
      userChrome = ''
        @import url("autohide_toolbox.css");
        @import url("autohide_sidebar.css");
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
