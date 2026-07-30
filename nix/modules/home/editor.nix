# Editor component (ECS: profile). nvim/vim/firenvim + lazy2nix plugin bundle.
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

  # Plain Vim: vimrc read via native XDG. Purpose is to push .viminfo out to $XDG_STATE_HOME
  home.file.".config/vim/vimrc".source = ../../../configs/editors/vim/vimrc;
  # nvim uses mkOutOfStoreSymlink since we want to write back directly to dotfiles
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/editors/nvim";

  # The Native Messaging manifest requires the launcher's absolute path by spec, and
  # Firenvim's launcher itself embeds the HOME/XDG/PATH from install time. To avoid
  # keeping stale paths after migrating username or home, regenerate from the current
  # environment when HM applies.
  home.activation.firenvimNativeMessaging = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -d "${config.xdg.dataHome}/nvim/lazy/firenvim" ]; then
      run ${pkgs.neovim}/bin/nvim --headless \
        "+call firenvim#install(0)" \
        "+qa"
    fi
  '';
}
