# Darwin Helium component (ECS: profile). Helium is the Chromium of record here (hosts/darwin.nix)
# and, being ungoogled-chromium underneath, keeps Chromium's policy engine: on macOS that reads
# the app's own preferences domain, so home-manager's targets.darwin.defaults is the whole
# declaration. helium://policy lists what arrived as source "Platform", level "Recommended":
# a user-level plist is never "managed", so these are defaults the UI can still change, not
# locks (a lock would need a root-owned file under /Library/Managed Preferences). Not
# sandboxed, so there is no container to trap the plist (see the CustomUserPreferences note
# in hosts/darwin.nix).
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

    # Bitwarden, force-installed. The update URL is the Web Store one after ungoogled-chromium's
    # domain substitution: with the plain google.com form helium://policy reports the entry as
    # "[BLOCKED] ... Invalid extension ID" (checked on 2026-09-17), with this form it is OK. The
    # download itself goes through Helium's services, so they have to be enabled in the
    # profile (they are here; a profile started with --no-first-run has them off and the
    # update request dies at helium-services-are-disabled). uBlock Origin ships inside Helium
    # as a component and the password manager is already off by a mandatory Helium default,
    # so neither is declared.
    ExtensionInstallForcelist = [
      "nngceckbapebfimnlniiiahkandclblb;https://clients2.9oo91e.qjz9zk/service/update2/crx"
    ];
    DefaultBrowserSettingEnabled = false; # Zen stays the default; no prompt
  };
}
