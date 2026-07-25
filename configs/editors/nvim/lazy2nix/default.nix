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
in
{
  plugins = fromNixpkgs ++ pinned;
}
