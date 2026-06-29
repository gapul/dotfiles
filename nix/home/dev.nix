{ ... }:
# 開発環境 (nixos-laptop でのみ import)。
# podman 等のシステム機能は hosts/nixos-laptop.nix 側、ユーザー寄りはここ。
{
  # direnv + nix-direnv: ディレクトリ毎に自動で開発シェル (flake/shell.nix) を有効化。
  # zsh 連携は home/common.nix の zsh 設定が拾う (programs.direnv が hook を入れる)。
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # flake devShell を高速キャッシュ
  };
}
