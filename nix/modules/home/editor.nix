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

  # SKK dictionaries, for skkeleton (and the source macSKK's container copy is made from).
  # They were nine megabytes of files someone had put in ~/.local/share/skk by hand — nothing
  # declared them, so a new machine came up with skkeleton unable to convert anything.
  # `skkeleton-user-dict` deliberately stays out of this: it is written to.
  xdg.dataFile."skk/SKK-JISYO.L".source = "${pkgs.skkDictionaries.l}/share/skk/SKK-JISYO.L";
  xdg.dataFile."skk/SKK-JISYO.geo".source = "${pkgs.skkDictionaries.geo}/share/skk/SKK-JISYO.geo";
  xdg.dataFile."skk/SKK-JISYO.jinmei".source =
    "${pkgs.skkDictionaries.jinmei}/share/skk/SKK-JISYO.jinmei";
  xdg.dataFile."skk/SKK-JISYO.propernoun".source =
    "${pkgs.skkDictionaries.propernoun}/share/skk/SKK-JISYO.propernoun";
  xdg.dataFile."skk/SKK-JISYO.station".source =
    "${pkgs.skkDictionaries.station}/share/skk/SKK-JISYO.station";

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
