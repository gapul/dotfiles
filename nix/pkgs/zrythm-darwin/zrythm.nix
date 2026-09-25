# Attempt to build zrythm 1.0.0 for aarch64-darwin linked against a backend-only carla.
{ pkgs }:
let
  inherit (pkgs) lib;
  portedCarla = import ./carla.nix { inherit pkgs; };
  # Drop Linux-only audio backends from buildInputs
  dropNames = [
    "alsa-lib"
    "libpulseaudio"
    "libjack2"
  ];
  keep = drv: !(lib.any (n: lib.hasInfix n (drv.pname or drv.name or "")) dropNames);
  # libcyaml/vamp-plugin-sdk do no darwin install_name fixups in their Makefile
  # build, so their dylib LC_ID_DYLIB stays a bare name ("libcyaml.1.dylib" etc.,
  # including the .so extension). dyld does not follow LC_RPATH for bare names, so
  # the linked zrythm binary dies at runtime with "Library not loaded". Work around
  # it by pinning each dylib's own ID to a full path.
  fixDylibIds =
    drv:
    drv.overrideAttrs (oa: {
      postFixup = (oa.postFixup or "") + ''
        for f in $(find "$out" -name '*.dylib' -o -name '*.so'); do
          install_name_tool -id "$f" "$f" 2>/dev/null || true
        done
      '';
    });
  patchedLibcyaml = fixDylibIds pkgs.libcyaml;
  patchedVampPluginSdk = fixDylibIds pkgs.vamp-plugin-sdk;
in
(pkgs.zrythm.override { carla = portedCarla; }).overrideAttrs (o: {
  # Override the nixpkgs default --buildtype=plain (no optimization = effectively -O0).
  # debugoptimized = -Ddebug=true -Doptimization=2, equivalent to Zrythm's official standard build.
  # (-Doptimization=2 alone gets overridden back to plain, so change the whole buildtype)
  mesonBuildType = "debugoptimized";

  # Silence the build log. Every warning here comes from zrythm's own upstream
  # sources (deprecated GTK4 tree/list APIs, sprintf, sign-compare, macro
  # redefines), not from our packaging, and there is nothing for us to fix.
  # NIX_CFLAGS_COMPILE is appended last on the compiler command line, so a
  # trailing -w wins over the -W flags meson and zrythm's meson.build add earlier.
  env = (o.env or { }) // {
    NIX_CFLAGS_COMPILE = lib.concatStringsSep " " (
      lib.filter (s: s != "") [
        (o.env.NIX_CFLAGS_COMPILE or "")
        "-w"
      ]
    );
  };

  # preFixup uses codesign (ad-hoc re-signing), so add sigtool explicitly.
  nativeBuildInputs = (o.nativeBuildInputs or [ ]) ++ [ pkgs.darwin.sigtool ];

  buildInputs = builtins.map (
    d:
    if (d.pname or d.name or "") == (pkgs.libcyaml.pname or pkgs.libcyaml.name) then
      patchedLibcyaml
    else if (d.pname or d.name or "") == (pkgs.vamp-plugin-sdk.pname or pkgs.vamp-plugin-sdk.name) then
      patchedVampPluginSdk
    else
      d
  ) (builtins.filter keep o.buildInputs);

  mesonFlags = o.mesonFlags ++ [
    "-Djack=disabled"
    "-Dalsa=disabled"
    "-Dpulse=disabled"
    "-Dx11=disabled"
    "-Dmanpage=false"
    # nixpkgs uses --buildtype=plain (no optimization = effectively -O0). The official
    # build uses -Ddebug=true -Doptimization=2 (standard). This matters for DAW CPU/latency
    # performance, so bump it up to match the official build.
    # (extra_optimizations defaults to true, so -ffast-math etc. are enabled)
    "-Doptimization=2"
  ];

  postPatch = o.postPatch + ''
    substituteInPlace meson.build --replace-fail "  find_program (open_dir_cmd)" "  # patched out"
  '';

  # Fill in the darwin GUI runtime environment. nixpkgs zrythm is not meant for darwin,
  # so wrapGAppsHook4 does not wire these up, and it dies with exit 255 as-is.
  preFixup = (o.preFixup or "") + ''
    gappsWrapperArgs+=(
      # GTK4's native display backend is "macos" (renamed from GTK3's "quartz").
      # By default it requests "quartz" and dies instantly with "No such backend", so inject the default.
      --set-default GDK_BACKEND macos
      # Fix for font config ("Fontconfig error: Cannot load default config file").
      --set-default FONTCONFIG_FILE ${pkgs.fontconfig.out}/etc/fonts/fonts.conf
      # gsettings/dconf writes fail without machine-id/dbus, producing
      # "Could not set 'first-run' to 'false'. ... problem with your GSettings backend"
      # so settings never persist (welcome shows every time). Switch off dconf to the keyfile
      # backend and persist to ~/.config/glib-2.0/settings/keyfile.
      --set-default GSETTINGS_BACKEND keyfile
      # librsvg ships a merged cache containing the standard gdk-pixbuf loaders and
      # its SVG loader. Point directly at it; current nixpkgs also gives the Darwin
      # loader an absolute librsvg install name, so no local copy/re-sign is needed.
      --set GDK_PIXBUF_MODULE_FILE ${pkgs.librsvg}/${pkgs.gdk-pixbuf.binaryDir}/loaders.cache
    )
  '';

  meta = o.meta // {
    broken = false;
  };
})
