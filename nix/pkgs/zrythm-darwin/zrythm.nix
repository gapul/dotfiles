# zrythm 1.0.0 を aarch64-darwin 向けに backend-only carla と結合してビルドする試み。
{ pkgs }:
let
  lib = pkgs.lib;
  portedCarla = import ./carla.nix { inherit pkgs; };
  # Linux 専用の音声バックエンドを buildInputs から除去
  dropNames = [ "alsa-lib" "libpulseaudio" "libjack2" ];
  keep = drv: !(lib.any (n: lib.hasInfix n (drv.pname or drv.name or "")) dropNames);
  # libcyaml/vamp-plugin-sdk は Makefile ビルドで darwin 向けの install_name 修正が
  # 一切行われず、dylib の LC_ID_DYLIB がベア名("libcyaml.1.dylib" 等、.so 拡張子含む)の
  # ままになる。dyld はベア名では LC_RPATH を辿らないため、リンクした zrythm 本体が
  # 実行時に "Library not loaded" で落ちる。dylib 自身の ID をフルパスに固定して回避する。
  fixDylibIds = drv: drv.overrideAttrs (oa: {
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
  buildInputs = builtins.map
    (d:
      if (d.pname or d.name or "") == (pkgs.libcyaml.pname or pkgs.libcyaml.name)
      then patchedLibcyaml
      else if (d.pname or d.name or "") == (pkgs.vamp-plugin-sdk.pname or pkgs.vamp-plugin-sdk.name)
      then patchedVampPluginSdk
      else d)
    (builtins.filter keep o.buildInputs);

  mesonFlags = o.mesonFlags ++ [
    "-Djack=disabled"
    "-Dalsa=disabled"
    "-Dpulse=disabled"
    "-Dx11=disabled"
    "-Dmanpage=false"
  ];

  postPatch = o.postPatch + ''
    substituteInPlace meson.build --replace-fail "  find_program (open_dir_cmd)" "  # patched out"
  '';

  # darwin: GTK4 のネイティブ表示バックエンドは "macos"(GTK3 の "quartz" から改名)。
  # 既定だと zrythm/GDK が "quartz" を要求して "No such backend" で即死するため、
  # ラッパーで GDK_BACKEND=macos を既定注入する（ユーザーは上書き可能）。
  preFixup = (o.preFixup or "") + ''
    gappsWrapperArgs+=( --set-default GDK_BACKEND macos )
  '';

  meta = o.meta // {
    broken = false;
  };
})
