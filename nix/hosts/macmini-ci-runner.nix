# darwin の CI をこの機械で走らせる。
#
# GitHub の macos-14 ランナーは毎回 nix store が空なので、carla や breeze-icons を
# ソースから建て直す。2026-08-31 の実測で 4〜31 分とばらつき、一度は時間切れで落ちた。
# そのたびに --admin で押し込むか、drvPath が main と同一であることを示して
# 「この PR では落ちようがない」と論証する羽目になっていた。
#
# ここなら store が温まったままなので、二度目以降は評価だけで終わる。M4 なので
# 素の速度も macos-14 (Intel 世代) より速い。
#
# ## services.github-runners を使わない理由
#
# あのモジュールは nix.enable を要求するが、この機械は Determinate Nix が
# /etc/nix/nix.conf を持っているので nix.enable = false (darwin-common.nix)。
# 前提が噛み合わない。
#
# しかも要求の中身はこの構成では不要。モジュールがそれを欲しがるのは
# trusted-users にランナーを入れるためだが、darwin-common.nix は
# 「trusted-user は root 相当になるので避け、substituter は root 所有の行で全ユーザーに
# 効かせる」という設計を既に採っている。ランナーはそのまま cachix を引ける。
#
# ## public リポジトリで self-hosted を使うことについて
#
# 他人が PR を開くとこの機械で任意のコードが走る、というのが既定の危険。塞いである:
#
#   - リポジトリ側で fork PR の承認を all_external_contributors にした (2026-08-31)。
#     既定の first_time_contributors は「一度通った人は以後フリー」なので足りない。
#   - 専用ユーザーで動かす。作業領域はこのユーザーの中に閉じる。
#
# 過去に他人の fork から来た PR は 0 件。塞ぐのは実績ではなく経路の話。
#
# ## ephemeral にしない理由
#
# ジョブごとに使い捨てにすると登録し直しが要り、登録トークンは 1 時間で失効するので
# PAT を置くことになる。承認を全外部に効かせた以上ここで走るのは自分のコードだけなので、
# 残留物の心配より、常駐で store を温めておく利点を取る。
{ pkgs, ... }:
let
  user = "gh-runner";
  home = "/Users/${user}";
  workDir = "${home}/actions-runner";
  repo = "https://github.com/gapul/dotfiles";

  # 未登録なら登録して、あとは走らせるだけ。config.sh は .runner を作るので、
  # それがあるかどうかで二回目以降を判別する。
  runScript = pkgs.writeShellScript "gh-runner-macmini" ''
    set -euo pipefail
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.git
        pkgs.curl
        pkgs.coreutils
        pkgs.gnutar
        pkgs.gzip
        pkgs.bash
      ]
    }:/usr/bin:/bin:/nix/var/nix/profiles/default/bin

    cd ${workDir}

    if [ ! -f .runner ]; then
      token=$(cat /var/lib/secrets/github-runner-token)
      ./config.sh \
        --unattended --replace \
        --url ${repo} \
        --token "$token" \
        --name macmini \
        --labels macmini \
        --work _work
    fi

    exec ./run.sh
  '';
in
{
  # CI 専用のユーザー。ここで走るのはワークフローのコードなので、他の役割と混ぜない。
  #
  # knownUsers に入れないと nix-darwin はユーザーを作らない。users.users を書いただけでは
  # 宣言が無視され、activation の install が "unknown user" で落ちる (2026-08-31 に踏んだ)。
  users.knownUsers = [ user ];
  users.users.${user} = {
    inherit home;
    createHome = true;
    description = "GitHub Actions self-hosted runner";
    uid = 505;
    gid = 20;
    shell = "${pkgs.bashInteractive}/bin/bash";
  };

  # ランナー本体を展開する。GitHub の配布物は自己更新しようとするので、
  # store から作業領域へ複製して使う (store は読み取り専用)。
  system.activationScripts.postActivation.text = ''
    if [ ! -x ${workDir}/run.sh ]; then
      /usr/bin/install -d -o ${user} -g staff -m 0700 ${workDir}
      /usr/bin/ditto ${pkgs.github-runner}/ ${workDir}/
      /usr/sbin/chown -R ${user}:staff ${workDir}
    fi
  '';

  launchd.daemons.gh-runner = {
    script = "exec ${runScript}";
    serviceConfig = {
      Label = "org.nixos.gh-runner";
      RunAtLoad = true;
      KeepAlive = true;
      UserName = user;
      WorkingDirectory = workDir;
      StandardOutPath = "/var/log/gh-runner.log";
      StandardErrorPath = "/var/log/gh-runner.log";
    };
  };
}
