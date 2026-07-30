# Attempt to build only the backend of carla (git master ≈2.6-dev) for aarch64-darwin.
# zrythm requires carla-host-plugin(>=2.6) and carla-discovery-native.
{ pkgs }:
let
  inherit (pkgs) lib;
  # Remove Linux-only audio backends from buildInputs
  dropNames = [
    "alsa-lib"
    "libpulseaudio"
    "jack2"
    "libjack2"
  ];
  keep = drv: !(lib.any (n: lib.hasInfix n (drv.pname or drv.name or "")) dropNames);
in
(pkgs.carla.override {
  withFrontend = false; # Qt frontend not needed (zrythm uses backend only)
  withQt = false;
  withGtk3 = false;
}).overrideAttrs
  (o: {
    # Swap in a git master build satisfying zrythm's >=2.6.0 requirement (same rev as zrythm's pin)
    version = "unstable-2024-04-26";
    src = pkgs.fetchFromGitHub {
      owner = "falkTX";
      repo = "carla";
      rev = "948991d7b5104280c03960925908e589c77b169a";
      hash = "sha256-uGAuKheoMfP9hZXsw29ec+58dJM8wMuowe95QutzKBY=";
    };
    buildInputs = builtins.filter keep o.buildInputs;
    # nixpkgs' postFixup assumes withFrontend=true (wrapPythonPrograms /
    # patching carla_settings.py / wrapQtApp). In a backend-only build none of
    # those files are generated, so disable it entirely.
    # (standard fixupPhase steps like patchShebangs/strip run separately from postFixup, so they are preserved)
    # Instead, carla's macOS Makefile pins each dylib's install name to a
    # relative path like "../../bin/foo.dylib" (assuming the original Carla.app-style
    # co-located layout), which cannot be resolved inside the nix store. Override
    # the dylib's own install_name_tool -id to the full path (dependencies stay as
    # the other buildInputs' absolute paths, so they need no touching).
    postFixup = ''
      for f in $(find "$out" -name '*.dylib'); do
        install_name_tool -id "$f" "$f"
      done
    '';
    meta = o.meta // {
      broken = false;
      platforms = o.meta.platforms ++ lib.platforms.darwin;
    };
  })
