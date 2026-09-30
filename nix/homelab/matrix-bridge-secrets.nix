# Bridge secrets that can't go in Nix settings (the store is world-readable) are generated once
# on the host and placed there: the encryption pickle_key and the double-puppet as_token.
#
# nixpkgs' mautrix-* modules envsubst environmentFile variables into the config, so this
# creates KEY=value files to pass in. Keep using the values generated the first time:
# regenerating them leaves the bridges unable to decrypt the keys they stored in their DB.
#
# The LINE bridge (matrix-line.nix) has its own unit, so its config oneshot does the same
# thing itself. mautrix-meta uses the nixpkgs default fixed value (see the encryption comment
# in matrix-bridges.nix for why).
{ lib, pkgs, ... }:
let
  dir = "/var/lib/matrix-bridge-secrets";
  # The nixpkgs-module bridges (googlechat has its own oneshot in matrix-googlechat.nix). The bridgev2 units in mk-matrix-bridgev2.nix and the LINE
  # bridge read the same secrets in their own config oneshots instead.
  bridges = [
    "signal"
    "whatsapp"
    "discord"
    "instagram"
    "messenger"
  ];
  # nixpkgs units that envsubst their config from the env file, so they must run after it.
  consumers = [
    "mautrix-signal"
    "mautrix-whatsapp"
    "mautrix-discord-registration"
    "mautrix-discord"
    "mautrix-meta-instagram-registration"
    "mautrix-meta-instagram"
    "mautrix-meta-messenger-registration"
    "mautrix-meta-messenger"
  ];
in
{
  # EnvironmentFile is read by systemd (root), so the files can stay owned by root.
  systemd.services =
    lib.genAttrs consumers (_: {
      requires = [ "matrix-bridge-secrets.service" ];
      after = [ "matrix-bridge-secrets.service" ];
    })
    // {
      matrix-bridge-secrets = {
        description = "Generate per-host secrets for the Matrix bridges";
        # The double puppet token is minted by matrix-doublepuppet.nix.
        requires = [ "matrix-doublepuppet-registration.service" ];
        after = [ "matrix-doublepuppet-registration.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = baseNameOf dir;
          StateDirectoryMode = "0700";
          UMask = "0077";
        };
        script = ''
          for bridge in ${toString bridges}; do
            file="${dir}/$bridge.env"
            if [ ! -s "$file" ]; then
              printf 'ENCRYPTION_PICKLE_KEY=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" > "$file.tmp"
              mv "$file.tmp" "$file"
            fi
            # Double puppeting (matrix-doublepuppet.nix): lets the bridge join rooms and send as
            # @gapul instead of inviting and relaying. Rewritten every run so a re-minted token
            # propagates; the pickle key line above is left untouched.
            {
              grep -v '^DOUBLE_PUPPET_SECRET=' "$file"
              printf 'DOUBLE_PUPPET_SECRET=as_token:%s\n' "$(cat /var/lib/matrix-doublepuppet/as_token)"
            } > "$file.tmp"
            mv "$file.tmp" "$file"
          done
        '';
      };
    };
}
