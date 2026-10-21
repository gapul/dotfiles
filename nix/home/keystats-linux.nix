_:
let
  # Source of truth is gapul/keystats (linux/), checked out via ghq; this only pins a rev.
  # Bump the rev in the URL + sha256 together when the Linux port changes.
  # builtins.fetchTarball, not pkgs.fetchFromGitHub: imports cannot depend on pkgs.
  src = builtins.fetchTarball {
    # hm-module.nix, read-only linux.json
    url = "https://github.com/gapul/keystats/archive/4e6ab0b34eea5607a61a751311eaefcaad84cad3.tar.gz";
    sha256 = "sha256-smeOr7KUN/yXLr/cUnzUlYp+a+B7km3DdxkwEegM92w=";
  };
in
{
  # The package, the collector's user service and linux.json all come from the repo's module.
  imports = [ "${src}/linux/hm-module.nix" ];

  services.keystats = {
    enable = true;
    # linux.json becomes a store symlink; the GUI then shows these without saving them.
    # Unset options keep the module's defaults (password managers excluded, espanso's
    # virtual keyboard ignored, xremap's output picked automatically).
    settings = {
      language = "en";
      layout = "ansi";
    };
  };
}
