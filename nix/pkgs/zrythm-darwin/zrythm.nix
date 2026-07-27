# zrythm 1.0.0 を aarch64-darwin 向けに backend-only carla と結合してビルドする試み。
{ pkgs }:
let
  inherit (pkgs) lib;
  portedCarla = import ./carla.nix { inherit pkgs; };
  # Linux 専用の音声バックエンドを buildInputs から除去
  dropNames = [
    "alsa-lib"
    "libpulseaudio"
    "libjack2"
  ];
  keep = drv: !(lib.any (n: lib.hasInfix n (drv.pname or drv.name or "")) dropNames);
  # libcyaml/vamp-plugin-sdk は Makefile ビルドで darwin 向けの install_name 修正が
  # 一切行われず、dylib の LC_ID_DYLIB がベア名("libcyaml.1.dylib" 等、.so 拡張子含む)の
  # ままになる。dyld はベア名では LC_RPATH を辿らないため、リンクした zrythm 本体が
  # 実行時に "Library not loaded" で落ちる。dylib 自身の ID をフルパスに固定して回避する。
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
  # nixpkgs 既定の --buildtype=plain(最適化なし=実質 -O0)を上書き。
  # debugoptimized = -Ddebug=true -Doptimization=2 で、Zrythm 公式標準ビルドと等価。
  # (-Doptimization=2 単体だと plain に上書きされ効かないため buildtype ごと変える)
  mesonBuildType = "debugoptimized";

  # preFixup で codesign(ad-hoc 再署名)を使うため、sigtool を明示的に足す。
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
    # nixpkgs は --buildtype=plain(最適化なし=実質 -O0)。公式は -Ddebug=true
    # -Doptimization=2(標準)を使う。DAW の CPU/レイテンシ性能に効くので公式相当へ上げる。
    # (extra_optimizations は既定 true で -ffast-math 等は有効)
    "-Doptimization=2"
  ];

  postPatch = o.postPatch + ''
    substituteInPlace meson.build --replace-fail "  find_program (open_dir_cmd)" "  # patched out"
  '';

  # darwin GUI ランタイム環境の補完。nixpkgs zrythm は darwin 想定でないため
  # wrapGAppsHook4 がこれらを張れておらず、素のままだと exit 255 で落ちる。
  preFixup = (o.preFixup or "") + ''
    # librsvg(SVG)込みの gdk-pixbuf loaders.cache を生成。これが無いと zrythm は
    # "SVG loader was not found" で起動を中止する(UI が SVG ベースの必須依存)。
    # ただし librsvg の svg loader は @rpath/librsvg-2.2.dylib を参照するが対応する
    # LC_RPATH が無く dlopen に失敗する。librsvg 本体(Rust・重い)は再ビルドせず、
    # loader だけ $out にコピーして参照を絶対パスへ書き換える。
    loaderdir="$out/lib/gdk-pixbuf-2.0/2.10.0/loaders"
    mkdir -p "$loaderdir"
    cp ${pkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader_svg.dylib "$loaderdir/"
    chmod +w "$loaderdir/libpixbufloader_svg.dylib"
    install_name_tool -change @rpath/librsvg-2.2.dylib \
      ${pkgs.librsvg}/lib/librsvg-2.2.dylib \
      "$loaderdir/libpixbufloader_svg.dylib"
    # Apple Silicon: install_name_tool 改変で ad-hoc 署名が無効化され dyld が
    # "no such file" で拒否する。再署名して有効化する。
    codesign --force --sign - "$loaderdir/libpixbufloader_svg.dylib"

    ${pkgs.gdk-pixbuf.dev}/bin/gdk-pixbuf-query-loaders \
      ${pkgs.gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.so \
      "$loaderdir/libpixbufloader_svg.dylib" \
      > "$out/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"

    gappsWrapperArgs+=(
      # GTK4 のネイティブ表示バックエンドは "macos"(GTK3 の "quartz" から改名)。
      # 既定だと "quartz" を要求して "No such backend" で即死するため既定注入。
      --set-default GDK_BACKEND macos
      # フォント設定("Fontconfig error: Cannot load default config file")対策。
      --set-default FONTCONFIG_FILE ${pkgs.fontconfig.out}/etc/fonts/fonts.conf
      # gsettings/dconf の書き込みが machine-id/dbus 不在で失敗し
      # "Could not set 'first-run' to 'false'. ... problem with your GSettings backend"
      # が出て設定が永続化されない(毎回 welcome が出る)。dconf を使わず keyfile
      # バックエンドに切替えて ~/.config/glib-2.0/settings/keyfile に永続化する。
      --set-default GSETTINGS_BACKEND keyfile
      # 上で生成した SVG 込み loaders.cache を指す。
      --set GDK_PIXBUF_MODULE_FILE "$out/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    )
  '';

  meta = o.meta // {
    broken = false;
  };
})
