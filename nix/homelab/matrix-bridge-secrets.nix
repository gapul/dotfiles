# ブリッジの秘密のうち、Nix の settings に書けないもの (store は誰でも読める) を
# host 上で一度だけ生成して置く。今は暗号化の pickle_key だけ。
#
# nixpkgs の mautrix-* モジュールは environmentFile の変数を envsubst で config に
# 差し込むので、ここで KEY=value 形式のファイルを作って渡す。値は初回に作ったものを
# 使い続けること: 作り直すと、ブリッジが DB に保存した暗号鍵を復号できなくなる。
#
# LINE ブリッジ (matrix-line.nix) は自前の unit なので、自分の config oneshot で
# 同じことをしている。mautrix-meta は nixpkgs の既定の固定値を使う (理由は
# matrix-bridges.nix の encryption のコメント)。
{ pkgs, ... }:
let
  dir = "/var/lib/matrix-bridge-secrets";
  bridges = [ "signal" ];
in
{
  systemd.services.matrix-bridge-secrets = {
    description = "Generate per-host secrets for the Matrix bridges";
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
      done
    '';
  };

  # EnvironmentFile は systemd (root) が読むので、ファイルの所有者は root のままでよい。
  systemd.services.mautrix-signal = {
    requires = [ "matrix-bridge-secrets.service" ];
    after = [ "matrix-bridge-secrets.service" ];
  };
}
