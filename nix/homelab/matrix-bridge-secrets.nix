# ブリッジの秘密のうち、Nix の settings に書けないもの (store は誰でも読める) を
# host 上で一度だけ生成して置く。暗号化の pickle_key と、ダブルパペットの as_token。
#
# nixpkgs の mautrix-* モジュールは environmentFile の変数を envsubst で config に
# 差し込むので、ここで KEY=value 形式のファイルを作って渡す。値は初回に作ったものを
# 使い続けること: 作り直すと、ブリッジが DB に保存した暗号鍵を復号できなくなる。
#
# LINE ブリッジ (matrix-line.nix) は自前の unit なので、自分の config oneshot で
# 同じことをしている。mautrix-meta は nixpkgs の既定の固定値を使う (理由は
# matrix-bridges.nix の encryption のコメント)。
{ lib, pkgs, ... }:
let
  dir = "/var/lib/matrix-bridge-secrets";
  # The nixpkgs-module bridges. The bridgev2 units in mk-matrix-bridgev2.nix and the LINE
  # bridge read the same secrets in their own config oneshots instead.
  bridges = [
    "signal"
    "discord"
    "instagram"
    "messenger"
  ];
  # nixpkgs units that envsubst their config from the env file, so they must run after it.
  consumers = [
    "mautrix-signal"
    "mautrix-discord-registration"
    "mautrix-discord"
    "mautrix-meta-instagram-registration"
    "mautrix-meta-instagram"
    "mautrix-meta-messenger-registration"
    "mautrix-meta-messenger"
  ];
in
{
  # EnvironmentFile は systemd (root) が読むので、ファイルの所有者は root のままでよい。
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
