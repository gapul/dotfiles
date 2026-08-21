{ config, ... }:
{
  # Mac-only secrets, split out of secrets.nix (2026-08-20).
  #
  # These used to sit in the one shared secrets file, which meant the laptop and WSL wrote an Apple
  # ID and a macOS code-signing identity to disk on every rebuild — credentials neither of them can
  # use. secrets/darwin.yaml is encrypted to the mac host key on top of the human keys, so the split
  # is enforced by the recipients in .sops.yaml, not just by which module is imported.
  sops.secrets = {
    # Apple ID for xcodes' Xcode downloads. `just upgrade` reads these files into
    # XCODES_USERNAME / XCODES_PASSWORD so username+password auth is non-interactive;
    # 2FA is still prompted the first time and when Apple's cached session expires.
    "xcodes/apple_id" = {
      sopsFile = ../../secrets/darwin.yaml;
      path = "${config.home.homeDirectory}/.config/xcodes/apple_id";
    };
    "xcodes/password" = {
      sopsFile = ../../secrets/darwin.yaml;
      path = "${config.home.homeDirectory}/.config/xcodes/password";
    };

    # keystats: passphrase for signing its own release builds (self-made app, gapul/keystats)
    "keystats_signing_pw" = {
      sopsFile = ../../secrets/darwin.yaml;
      path = "${config.home.homeDirectory}/.config/keystats/signing.pw";
    };
    # The signing identity itself (base64 PKCS#12, cert + private key, valid to 2036).
    # codesign/setup-signing.sh mints a *new* self-signed cert when the keychain is missing, so a
    # rebuild on fresh hardware would change the Designated Requirement: already-installed copies
    # would lose their Input Monitoring grant and reject the update. Restore instead of re-mint:
    #   base64 -d < ~/.config/keystats/signing.p12.b64 > /tmp/id.p12
    #   security import /tmp/id.p12 -k ~/Library/Keychains/keystats-signing.keychain-db \
    #     -P "$(cat ~/.config/keystats/signing.pw)" -T /usr/bin/codesign -A
    "keystats_signing_p12" = {
      sopsFile = ../../secrets/darwin.yaml;
      path = "${config.home.homeDirectory}/.config/keystats/signing.p12.b64";
    };
  };
}
