# SSO for the nixos-unstable instantiation used by the darwin hosts.
#
# A handful of creative tools (ardour / aseprite / fritzing) are unavailable or broken on
# 26.05-darwin, so they come from nixos-unstable instead. aseprite is unfree, and the
# unstable tree is imported fresh rather than inherited, so allowUnfree has to be set again
# here - the host's own nixpkgs.config (hosts/darwin-common.nix) does not reach it.
#
# The same literal used to live in home/darwin.nix only. It is shared now that the .app
# bundles are declared at the system layer (hosts/darwin.nix) while the rest stays in
# home.packages, and both halves must resolve to the same store paths.
{ nixpkgsUnstable, system }:
import nixpkgsUnstable.legacyPackages.${system}.path {
  inherit system;
  config.allowUnfree = true;
}
