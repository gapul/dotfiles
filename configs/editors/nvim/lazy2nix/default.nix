{ pkgs, lib }:
let
  fromNixpkgs = lib.mapAttrsToList (name: attr: {
    inherit name;
    path = pkgs.vimPlugins.${attr};
  }) (import ./nixpkgs-plugins.nix);

  buildPinned = name: pin: {
    inherit name;
    path = pkgs.vimUtils.buildVimPlugin {
      pname = name;
      version = builtins.substring 0 8 pin.rev;
      src = pkgs.fetchFromGitHub {
        inherit (pin)
          owner
          repo
          rev
          hash
          ;
      };
      doCheck = false;
    };
  };
  pinned = lib.mapAttrsToList buildPinned (
    builtins.fromJSON (builtins.readFile ./pinned-plugins.json)
  );

  # Built on the macmini between 2026-10-05 and 2026-10-11 from APFS-compressed sources, which
  # came out as empty files, and pushed by CI to gapul-dotfiles, where a path cannot be deleted
  # or overwritten. The extra attribute only moves them to new store paths; drop an entry once
  # its plugin's own derivation has changed.
  poisonedInCachix = [
    "catppuccin"
    "denops.vim"
    "harpoon"
    "skkeleton"
    "typewriter.nvim"
    "vim-tidal"
  ];
  rehash =
    plugin:
    if builtins.elem plugin.name poisonedInCachix then
      plugin // { path = plugin.path.overrideAttrs { rebuiltAfterCachixPoisoning = "2026-10-11"; }; }
    else
      plugin;
in
{
  plugins = map rehash (fromNixpkgs ++ pinned);
}
