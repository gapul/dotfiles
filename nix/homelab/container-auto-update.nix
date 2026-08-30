# コンテナの更新を podman 自身に任せる。
#
# podman は :latest でも勝手に取り直さない。宣言に latest と書いてあっても実体は
# 初回に引いたまま止まるので、2026-08-30 に見たとき 20 個が数ヶ月から 1 年古かった。
# 宣言が「常に最新」と言っているのに実体がそうでないなら、直すのは実体の側。
#
# digest 固定 + Renovate は採らない。固定は「最新に居続ける」の逆だし、CI が検証
# できるのは nix の構成であってコンテナが起動するかではないので、40 個ぶんの PR が
# 毎週流れる割に得られる安全が小さい。
#
# podman auto-update を選んだ理由は rollback が既定で入っていること。更新後に
# ユニットが起動できなければ前の image に戻して再起動する。自作のタイマーだと
# ここを作り込むことになる。
#
# 弱点も書いておく: 巻き戻しの判定は本来 SDNOTIFY で「準備完了」を受け取って
# 行うもので、それが無い今は「起動はしたが直後に落ちる」型を取り逃がす。そこは
# journal-alert の再起動ループ検知 (PR #490) が 15 分以内に拾う。即死は
# auto-update が巻き戻し、遅れて死ぬものは通知が拾う、という分担にしている。
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # 全コンテナに auto-update のラベルを付ける。宣言は 28 ファイルに散っている
  # ので個別には触らず、submodule の既定値として一度だけ入れる。mkDefault なので
  # 外したいコンテナがあれば、そのコンテナ自身の宣言で上書きできる。
  #
  # DB の tag は postgres:16-alpine / mariadb:11 / couchdb:3 のようにメジャーで
  # 縛ってあるので、16 が 17 に飛ぶような壊れ方は tag の時点で塞がっている。
  # 除外すべきコンテナは今のところ無い。
  options.virtualisation.oci-containers.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.labels."io.containers.autoupdate" = lib.mkDefault "registry";
      }
    );
  };

  config = {
    # image 名が完全修飾でないと auto-update は起動時にこう言って死ぬ:
    #   Error: short name: auto updates require fully-qualified image reference
    #
    # これを 2026-08-30 に本番で踏んだ。宣言 14 箇所が `postgres:16-alpine` の
    # ような短縮名で、ラベルを足した途端に ntfy・vaultwarden・DB を含む 12 個が
    # 起動できなくなった。nix の評価も CI も通っていた。CI が見るのは構成であって
    # コンテナが起動するかではない、と PR に書いた直後にその穴に落ちた。
    #
    # なので、この一点だけは nix が見られる形にする。実行時の失敗を評価時のエラーに
    # 移すだけだが、少なくとも同じ踏み方は二度としない。
    assertions = lib.mapAttrsToList (name: c: {
      assertion = lib.hasInfix "." (builtins.head (lib.splitString "/" c.image));
      message = ''
        コンテナ ${name} の image "${c.image}" が完全修飾ではない。
        auto-update のラベルが付いていると podman が起動を拒否する。
        レジストリを明示すること (例: postgres:16-alpine → docker.io/library/postgres:16-alpine)。
      '';
    }) config.virtualisation.oci-containers.containers;

    systemd.services.container-auto-update = {
      description = "コンテナの image を引き直して載せ替える";
      path = with pkgs; [
        podman
        curl
        jq
        gnugrep
        gnused
        coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/container-auto-update.sh}";
      };
    };

    systemd.timers.container-auto-update = {
      description = "コンテナの更新を週 1 回走らせる";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # 毎日は変化が多すぎ、月 1 では数ヶ月の滞留が戻ってくる。
        # backup (03:13) と restore-drill を避けて日曜の朝に置く。
        OnCalendar = "Sun 05:00";
        Persistent = true;
        RandomizedDelaySec = "20min";
      };
    };
  };
}
