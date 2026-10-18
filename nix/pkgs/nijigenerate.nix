# nijigenerate (rigging editor, Inochi Creator's successor) and nijiexpose (its streaming
# runtime, Inochi Session's successor) for nixos-laptop. The mac gets the same pair from the
# gapul/inochi tap as casks.
#
# Not in nixpkgs (only the inochi-* predecessors are), so the official x86_64 Linux zips are
# repackaged. Both are D programs that link SDL2/freetype/openssl/dbus directly, which
# autoPatchelf resolves, and dlopen() GL/EGL, curl and (nijiexpose) Lua 5.1 by soname at
# runtime, which it cannot see, so those go on LD_LIBRARY_PATH. The binary finds its .mo files
# next to itself, so the whole zip is kept together under libexec and only a wrapper goes in
# bin. nijiexpose also dlopen()s "cimgui.so" by bare name; upstream relies on $ORIGIN in the
# RPATH, which autoPatchelf replaces, so its own directory goes on LD_LIBRARY_PATH as well.
#
# bindbc-opengl picks EGL over GLX only when XDG_SESSION_TYPE is "wayland". On this laptop niri
# is started from greetd with XDG_SESSION_TYPE=tty, and whatever niri spawns inherits that, so
# nijiexpose saw the EGL context SDL had made as "No valid OpenGL context" and crashed. niri now
# sets it for what it spawns (home/niri.nix); the wrapper also sets it whenever a Wayland display
# is present, for launches that do not come through niri (Hyprland, ssh).
# Upstream is in beta; bump version + hash here.
{
  lib,
  stdenv,
  fetchzip,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  SDL2,
  freetype,
  openssl,
  dbus,
  zlib,
  libGL,
  curl,
  lua5_1,
}:
let
  runtimeLibs = [
    libGL
    SDL2
    curl
    lua5_1
  ];

  mkNiji =
    {
      pname,
      version,
      hash,
      desktopName,
      comment,
    }:
    stdenv.mkDerivation {
      inherit pname version;

      src = fetchzip {
        url = "https://github.com/nijigenerate/${pname}/releases/download/v${version}/${pname}-linux-x86_64.zip";
        stripRoot = false;
        inherit hash;
      };

      nativeBuildInputs = [
        autoPatchelfHook
        makeWrapper
        copyDesktopItems
      ];
      buildInputs = [
        stdenv.cc.cc.lib
        SDL2
        freetype
        openssl
        dbus
        zlib
      ];

      desktopItems = [
        (makeDesktopItem {
          name = pname;
          exec = pname;
          inherit desktopName comment;
          categories = [ "Graphics" ];
        })
      ];

      installPhase = ''
        runHook preInstall
        mkdir -p $out/libexec $out/bin
        cp -R . $out/libexec/${pname}
        makeWrapper $out/libexec/${pname}/${pname} $out/bin/${pname} \
          --prefix LD_LIBRARY_PATH : $out/libexec/${pname}:${lib.makeLibraryPath runtimeLibs} \
          --run 'if [ -n "''${WAYLAND_DISPLAY-}" ]; then export XDG_SESSION_TYPE=wayland; fi'
        runHook postInstall
      '';

      meta = {
        description = "${desktopName}: ${comment}";
        homepage = "https://github.com/nijigenerate/${pname}";
        license = lib.licenses.bsd2;
        platforms = [ "x86_64-linux" ];
        mainProgram = pname;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    };
in
{
  nijigenerate = mkNiji {
    pname = "nijigenerate";
    version = "1.0.0-beta4";
    hash = "sha256-Afm7dz+6h3td3N5G37p41PPUYwChn1KSwNiScsq3IsU=";
    desktopName = "nijigenerate";
    comment = "Rigging editor for Inochi2D puppets";
  };
  nijiexpose = mkNiji {
    pname = "nijiexpose";
    version = "1.0.0-beta3";
    hash = "sha256-ArJnmgkvHoyK8ck7fWk8R7C522p2xsb6sUKOs5PtMxg=";
    desktopName = "nijiexpose";
    comment = "Streaming runtime for Inochi2D puppets";
  };
}
