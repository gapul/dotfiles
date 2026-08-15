# Windows の中で動く NixOS (WSL2)。
#
# デュアルブートの実機 NixOS とはインストールを共有しない (WSL2 は物理パーティションを
# 起動せず、VHDX の中の rootfs を Microsoft のカーネルで動かす仕組みなので、そもそも
# できない)。共有するのは設定のほうで、home は実機や Lab PC と同じ roles.wsl を読む。
#
# 狙いは「Adobe を触るために Windows で起動している最中も、再起動せずに普段の
# シェルと道具が使えること」。GUI は Windows 側に任せ、ここは CLI に徹する。
#
# tarball の作り方と入れ方は docs/NIXOS_WSL.md。
{
  pkgs,
  lib,
  user,
  ...
}:
{
  wsl = {
    enable = true;
    defaultUser = user.username;
    # Windows 側の PATH を丸ごと引き継ぐと which/command -v が Windows の実行ファイルを
    # 拾って紛らわしい。相互運用は残しつつ PATH 汚染だけ止める。
    interop.includePath = false;
    # /mnt/c 越しに Windows のコマンドを呼べるのは残す (wslview が cmd.exe を叩く)。
    wslConf.interop.enabled = true;
    wslConf.automount.enabled = true;
  };

  # 実機の NixOS と同じ選択的 unfree。standalone HM 側の mkWslPkgs と揃える
  # (揃えないと同じ roles.wsl が NixOS 統合のときだけ eval で落ちる)。
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
      "unity-cli"
    ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ user.username ];
  };

  # WSL は Windows 側の時計に追従するが、ログの時刻を母艦と揃えておく。
  time.timeZone = "Asia/Tokyo";

  users.users.${user.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };
  # home-manager が zsh の設定を置くので、システム側は shell を有効にするだけ。
  programs.zsh.enable = true;

  # ブートローダも fileSystems も要らない (WSL がカーネルと rootfs を用意する)。
  system.stateVersion = "26.05";
}
