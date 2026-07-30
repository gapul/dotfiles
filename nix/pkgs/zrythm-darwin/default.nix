# Build zrythm 1.0.0 (DAW) ourselves for aarch64-darwin.
#
# nixpkgs marks zrythm as `broken = isDarwin`, and its required dependency carla
# is also `platforms = linux`. So plain pkgs cannot eval/build it. Here we
# re-instantiate the same nixpkgs with allowUnsupportedSystem/allowBroken and
# apply the overrides in zrythm.nix / carla.nix (backend-only darwin port of carla,
# removing Linux audio backends, install_name fixes, injecting GDK_BACKEND=macos default, etc.)
# to obtain a launchable zrythm. See the comments in zrythm.nix / carla.nix for details.
#
# Usage (home-manager, darwin): add to home.packages
#   (import ../pkgs/zrythm-darwin { inherit pkgs; })
{ pkgs }:
let
  # Some of carla's transitive deps are not darwin-supported (narrow meta.platforms),
  # so eval fails without allowUnsupportedSystem. Reconstruct the same nixpkgs to avoid it.
  pkgs' = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    overlays = pkgs.overlays or [ ];
    config = (pkgs.config or { }) // {
      allowUnsupportedSystem = true;
      allowBroken = true;
    };
  };
in
import ./zrythm.nix { pkgs = pkgs'; }
