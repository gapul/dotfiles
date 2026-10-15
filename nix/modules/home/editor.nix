# Editor component (ECS: profile). nvim/vim/firenvim + lazy2nix plugin bundle.
{
  config,
  pkgs,
  lib,
  nixpkgsAgents,
  ...
}:
let
  # Neovim and its plugins follow nixos-unstable: the 26.05-darwin channel lagged a patch
  # release behind (0.12.4 vs 0.12.5) and VimTeX a minor one.
  editorPkgs = import ../../lib/unstable-pkgs.nix {
    nixpkgsUnstable = nixpkgsAgents;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  lazyNixPlugins =
    pkgs.linkFarm "lazy-nix-plugins"
      (import ../../../configs/editors/nvim/lazy2nix {
        pkgs = editorPkgs;
        inherit lib;
      }).plugins;
in
{
  home.packages = [ editorPkgs.neovim ];
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
  #
  # Runs on every switch from the Nix-built plugin (not a lazy.nvim clone), so a new machine
  # gets the manifests on its first switch. --clean keeps LazyVim out of it: without
  # LAZY_NIX_PLUGINS in this environment it would fall back to cloning every plugin.
  # The prologue puts that variable into the launcher, because the browser starts nvim with
  # its own environment and lazy.lua would otherwise not find the Nix plugin bundle there.
  # firenvim only writes a browser's manifest when that browser's config dir exists; on
  # macOS Firefox's is ~/Library/Application Support/Mozilla, which Firefox itself may never
  # create (home-manager's profile lives under .../Firefox), so make sure it is there.
  home.activation.firenvimNativeMessaging = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ${lib.optionalString (pkgs.stdenv.isDarwin && config.programs.firefox.enable) ''
      run mkdir -p "$HOME/Library/Application Support/Mozilla"
    ''}
    run ${editorPkgs.neovim}/bin/nvim --headless --clean \
      --cmd "set rtp^=${lazyNixPlugins}/firenvim" \
      "+call firenvim#install(0, 'export LAZY_NIX_PLUGINS=${lazyNixPlugins}')" \
      "+qa"
  '';
}
