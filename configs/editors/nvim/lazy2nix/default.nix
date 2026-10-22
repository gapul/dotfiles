{ pkgs, lib }:
let
  fromNixpkgs = lib.mapAttrsToList (name: attr: {
    inherit name;
    path = pkgs.vimPlugins.${attr};
  }) (import ./nixpkgs-plugins.nix);

  buildPinned = name: pin: {
    inherit name;
    path = pkgs.vimUtils.buildVimPlugin (
      {
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
      }
      // (patches.${name} or { })
    );
  };

  # skkeleton loads its dictionary sources through import-map-importer, which fetch()es remote
  # imports on every load with no cache. On a slow or offline network that fetch blocks the
  # synchronous enable request and freezes Neovim, then every source fails ("Invalid source
  # name"). Vendor the one remote import so loading needs no network.
  jisyoSchema = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/skk-dict/jisyo/a6a597a0eadfecdcf2a1e2f3b46795f31aaeab47/schema/jisyo.schema.v0.0.0.json";
    hash = "sha256-M51z5Tnjg3Z3vTSKi46Ine6kTZRrEc0HXWKcGJs5BqE=";
  };
  patches.skkeleton.postPatch = ''
    cp ${jisyoSchema} denops/skkeleton/jisyo.schema.v0.0.0.json
    substituteInPlace denops/skkeleton/deno.json \
      --replace-fail "https://cdn.jsdelivr.net/gh/skk-dict/jisyo/schema/jisyo.schema.v0.0.0.json" \
                     "./jisyo.schema.v0.0.0.json"
  '';
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
    "tokyonight.nvim"
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
