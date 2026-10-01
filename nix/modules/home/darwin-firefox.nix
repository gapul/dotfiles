# Darwin side of the Firefox component (modules/home/firefox.nix holds the profile and policies).
#
# The .app is the cask (hosts/darwin.nix, see the note there on signing). home-manager runs
# with package = null and only owns the profile and the policies; on darwin the policies go
# to the app's managed-preferences domain instead of a policies.json inside the bundle.
{ ... }:
{
  imports = [ ./firefox.nix ];

  programs.firefox = {
    package = null; # the cask owns the bundle
    darwinDefaultsId = "org.mozilla.firefoxdeveloperedition";

    profiles.dev.settings = {
      # Native macOS vibrancy behind the toolbar and the tab strip. Cheap, unlike making the
      # content area transparent (browser.tabs.allow_transparent_browser), which repaints the
      # whole window and is what made Zen feel slow here — left off on purpose.
      "browser.theme.macos.native-theme" = true;
      "widget.macos.titlebar-blend-mode.behind-window" = true;
    };
  };
}
