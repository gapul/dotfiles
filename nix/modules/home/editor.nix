# Editor component (ECS: profile)。nvim/vim/firenvim + lazy2nix プラグイン束。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  lazyNixPlugins =
    pkgs.linkFarm "lazy-nix-plugins"
      (import ../../../configs/editors/nvim/lazy2nix { inherit pkgs lib; }).plugins;
in
{
  home.sessionVariables.LAZY_NIX_PLUGINS = lazyNixPlugins;

  # 素の Vim: native XDG で読まれる vimrc。.viminfo を $XDG_STATE_HOME へ追い出す目的
  home.file.".config/vim/vimrc".source = ../../../configs/editors/vim/vimrc;
  # nvim は dotfiles に直接書き戻したいので mkOutOfStoreSymlink
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/editors/nvim";

  # Native Messaging manifest は仕様上 launcher の絶対パスを要求し、Firenvim の
  # launcher 自体も install 時の HOME/XDG/PATH を埋め込む。ユーザー名や home を
  # 移行しても古いパスを保持しないよう、HM 適用時に現在の環境から再生成する。
  home.activation.firenvimNativeMessaging = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -d "${config.xdg.dataHome}/nvim/lazy/firenvim" ]; then
      run ${pkgs.neovim}/bin/nvim --headless \
        "+call firenvim#install(0)" \
        "+qa"
    fi
  '';
}
