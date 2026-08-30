# homeserver が自分で main を取りに行って切り替える。
#
# 押し込む向きをやめる理由は資格情報の側にある。母艦から押す形だと、その経路は
# 母艦の ssh 鍵に依存する。常用鍵を Secure Enclave に移してから鍵は Touch ID の
# 承認を要求するようになり、無人のときは署名できない (2026-08-30 に窓が切れて
# 実際に止まった)。鍵を足して回避するより、押す側の資格情報が要らない形にする。
#
# homeserver は公開 flake を読むだけなので、誰の鍵も要らない。母艦が壊れていても
# 出かけていても、マージされた設定は反映される。
{ pkgs, ... }:
{
  systemd.services.self-deploy = {
    description = "main が進んでいたら自分で切り替える";
    # 自分自身を再起動させない。switch-to-configuration は定義が変わったユニットを
    # 再起動するので、このユニット自身が対象になると切り替えの途中で殺される。
    # (switch 本体は nixos-rebuild が systemd-run で別ユニットに逃がしているが、
    #  再起動の対象になる側の話はそれとは別。)
    restartIfChanged = false;
    path = with pkgs; [
      git
      nixos-rebuild
      nix
      curl
      coreutils
      gawk
      systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/self-deploy.sh}";
      # 切り替えは root でしかできない。
      User = "root";
      StateDirectory = "self-deploy";
    };
  };

  systemd.timers.self-deploy = {
    description = "自動更新を 1 時間おきに走らせる";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15min";
      OnUnitActiveSec = "1h";
      Persistent = true;
      # 毎時ちょうどに GitHub を叩きに行かない。
      RandomizedDelaySec = "10min";
    };
  };
}
