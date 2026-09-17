# Darwin Helium component (ECS: profile). Helium is the Chromium of record here (hosts/darwin.nix)
# and, being ungoogled-chromium underneath, keeps Chromium's policy engine: on macOS that reads
# the app's own preferences domain, so home-manager's targets.darwin.defaults is the whole
# declaration. helium://policy lists what arrived (source "Platform"). Not sandboxed, so there
# is no container to trap the plist (see the CustomUserPreferences note in hosts/darwin.nix).
#
# Only policies can be declared this way. UI preferences that are not policies (theme, zoom,
# Helium's own toggles) live in the profile's Preferences JSON, which Chromium rewrites while
# running, so they stay out of nix.
{ ... }:
{
  targets.darwin.defaults."net.imput.helium" = {
    # Sparkle self-update off: the cask owns the version and `just maintain` (brew --greedy)
    # moves it, the same as the other auto_updates casks. Found on 2026-09-17 with both on.
    SUEnableAutomaticChecks = false;
    SUAutomaticallyUpdate = false;

    # Bitwarden, force-installed. Helium proxies Web Store traffic, and the copy installed by
    # hand already updates from this URL, so the standard update endpoint works. uBlock Origin
    # ships inside Helium as a component, so it is not listed.
    ExtensionInstallForcelist = [
      "nngceckbapebfimnlniiiahkandclblb;https://clients2.google.com/service/update2/crx"
    ];
    PasswordManagerEnabled = false; # Bitwarden holds the passwords
    DefaultBrowserSettingEnabled = false; # Zen stays the default; no prompt
  };
}
