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
#   - ci.yml は action を SHA で固定してある。
#
# 専用ユーザーでの隔離は諦めた (下の let を参照)。macOS が SSH 越しのユーザー作成を
# 拒み、通すには SSH 全体に Full Disk Access を与えることになるため。
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
  # 専用ユーザーにはできなかった。macOS は SSH 経由の rebuild でユーザーを作らせない
  # (「users cannot be create over SSH without Full Disk Access」)。この機械は headless で
  # 運用しているので、そこを通すにはリモートログインに Full Disk Access を与えることに
  # なる。SSH 越しの全プログラムに効く設定なので、専用ユーザーで得られる隔離と釣り合わない。
  #
  # 隔離を落としても成り立つのは、GitHub 側で fork PR の承認を all_external_contributors に
  # したので、ここで走るのが自分のコードだけになっているため。加えて ci.yml は action を
  # SHA で固定してある。
  #
  # 隔離を戻したくなったら、System Settings > General > Sharing > Remote Login の
  # 「Allow full disk access for remote users」を入れてから専用ユーザーに戻す。
  user = "gapul";
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

    # node20 を要求する action (actions/cache など) を node24 で走らせる。
    #
    # nixpkgs の github-runner は node24 しか同梱しない (上流が node20 を落としたため)。
    # GitHub の hosted runner は node20 の action を黙って node24 に振り替えるが、
    # self-hosted は素直に node20 を探しに行って
    # 「externals/node20/bin/node ... No such file or directory」で止まる。
    # hosted と同じ挙動にする。
    export ACTIONS_RUNNER_FORCE_ACTIONS_NODE_VERSION=node24

    cd ${workDir}

    # nixpkgs の github-runner は GitHub の配布物と構造が違い、config.sh も run.sh も
    # bin/ の下にある。トップに置かれているつもりで叩くと何も起きずに終わる。
    #
    # さらに、状態 (.runner / .credentials / _work) は実体のある場所ではなく
    # ~/.github-runner に書かれる。作業領域を見て「未設定」と判断すると、既に
    # 登録済みなのに config.sh を叩いて「already configured」で止まる。
    if [ ! -f ${home}/.github-runner/.runner ]; then
      token=$(cat /var/lib/secrets/github-runner-token)
      ./bin/config.sh \
        --unattended --replace \
        --url ${repo} \
        --token "$token" \
        --name macmini \
        --labels macmini \
        --work _work
    fi

    exec ./bin/run.sh
  '';
in
{
  # ランナー本体を展開する。GitHub の配布物は自己更新しようとするので、
  # store から作業領域へ複製して使う (store は読み取り専用)。
  #
  # 登録トークンの権限もここで合わせる。手で置くと 0400 root になりがちだが、
  # ランナーは gapul として走るので読めない。読めないと config.sh に空文字が渡り、
  # 「Permission denied」だけがログに出て延々やり直す (2026-09-01 に踏んだ)。
  system.activationScripts.postActivation.text = ''
    if [ -f /var/lib/secrets/github-runner-token ]; then
      /usr/sbin/chown ${user} /var/lib/secrets/github-runner-token
      /bin/chmod 0400 /var/lib/secrets/github-runner-token
    fi

    if [ ! -x ${workDir}/bin/run.sh ]; then
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
      # gapul として走るので /var/log には書けない。書けない場所を指すと launchd は
      # プロセスを起こす前に EX_CONFIG で諦め、ログも残らないので原因が見えない
      # (2026-08-31 に踏んだ。exit 78 が延々出るだけだった)。
      StandardOutPath = "${workDir}/runner.log";
      StandardErrorPath = "${workDir}/runner.log";
    };
  };
}
