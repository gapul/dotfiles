{ pkgs }:
let
  version = "2025.33230";
  # Wine and DXVK follow TouchDesigner-Linux's pins (td_lib/wine.py, docs/runners.md,
  # docs/compatibility.md), not the newest releases: Soda 11 (Wine 11) loops forever in DWrite
  # at the splash screen, and DXVK 3.x crashes the Spout/Syphon Out TOP under Wine 9.0.
  # Re-check those docs before bumping either.
  wine = pkgs.runCommand "soda-9.0-1" { } ''
    mkdir -p "$out"
    tar -xf ${
      pkgs.fetchurl {
        url = "https://github.com/bottlesdevs/wine/releases/download/soda-9.0-1/soda-9.0-1-x86_64.tar.xz";
        hash = "sha256:c38fe0ad3c12a49b61ec1fcaea5c5d8da4a3d1afc5991befe2af6b125f014c28";
      }
    } -C "$out" --strip-components=1
  '';
  dxvk = pkgs.runCommand "touchdesigner-dxvk-2.7.1" { } ''
    mkdir -p "$out"
    tar -xf ${
      pkgs.fetchurl {
        url = "https://github.com/doitsujin/dxvk/releases/download/v2.7.1/dxvk-2.7.1.tar.gz";
        hash = "sha256:d85ce7c79f57ecd765aaa1b9e7007cb875e6fde9f6d331df799bce73d513ce87";
      }
    } -C "$out" --strip-components=1
  '';
  installer = pkgs.fetchurl {
    url = "https://download.derivative.ca/TouchDesigner.${version}.exe";
    hash = "sha256:ab6e8f72848dfa3bba7ddb7b2cece546fe668474d13ab8c82c326ae551bdae64";
  };
  # Wine compatibility assets; application licensing still uses Derivative's login.
  fixes = pkgs.fetchFromGitHub {
    owner = "ismail-bahloul";
    repo = "TouchDesigner-Linux";
    rev = "4b6249b28db6e45ad50422ab9ac0fec53cfe91f4";
    hash = "sha256-42Gb5EuGHd5kKhDKruJJ4IPUJlc/0ThxrCPC0yhGHM0=";
  };
  app =
    pkgs.runCommand "touchdesigner-files-${version}"
      {
        nativeBuildInputs = [
          pkgs._7zz
          pkgs.innoextract
          pkgs.python3
        ];
      }
      ''
        7zz x ${installer} -oinner >/dev/null
        innoextract -d extracted -e inner/TouchDesigner.${version}.exe >/dev/null
        mkdir -p "$out"
        cp -r 'extracted/$/app' "$out/app"
        if [ -d extracted/commonappdata ]; then cp -r extracted/commonappdata "$out/"; fi
        # IDS camera SDK initialization crashes under Wine. Disable these optional
        # camera DLL entry points, following TouchDesigner-Linux's documented fix.
        python3 - "$out/app/bin" <<'PY'
        import pathlib, struct, sys
        for name in ('ids_peak_ipl.dll', 'ids_peak_afl.dll', 'ids_peak_ifl.dll', 'ids_peak_comfort_c.dll'):
            p = pathlib.Path(sys.argv[1]) / name
            if not p.exists():
                continue
            data = bytearray(p.read_bytes())
            offset = struct.unpack_from('<I', data, 0x3c)[0]
            assert data[offset:offset+4] == b'PE\0\0'
            struct.pack_into('<I', data, offset+40, 0)
            p.write_bytes(data)
        PY
        test -f "$out/app/bin/TouchDesigner.exe"
      '';
  inner = pkgs.writeShellApplication {
    name = "touchdesigner-inner";
    runtimeInputs = [
      wine
      pkgs.winetricks
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      export WINEPREFIX="''${XDG_DATA_HOME:-$HOME/.local/share}/creative-wine/touchdesigner-soda"
      export WINEARCH=win64
      export WINE=${wine}/bin/wine64
      export WINESERVER=${wine}/bin/wineserver
      export WINEDEBUG="''${WINEDEBUG:--all}"
      export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;d3d10core,d3d11,dxgi=n,b"
      export WINETRICKS_LATEST_VERSION_CHECK=disabled
      export MIMALLOC_DISABLE_REDIRECT=1
      export KMP_AFFINITY=disabled
      mkdir -p "$WINEPREFIX"
      exec 9>"$WINEPREFIX/.setup.lock"
      flock 9
      if [[ ! -f "$WINEPREFIX/.setup-v1" ]]; then
        "$WINE" wineboot --update
        wineserver -w
        winetricks -q corefonts d3dx11_43 vcrun2022 win10
        cp ${dxvk}/x64/*.dll "$WINEPREFIX/drive_c/windows/system32/"
        cp ${dxvk}/x32/*.dll "$WINEPREFIX/drive_c/windows/syswow64/"
        cp ${fixes}/Assets/lucon.ttf "$WINEPREFIX/drive_c/windows/Fonts/lucon.ttf"
        "$WINE" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v 'Lucida Console (TrueType)' /d lucon.ttf /f
        "$WINE" reg add 'HKCU\Software\Wine\Drivers' /v Graphics /d 'x11' /f
        wineserver -w
        touch "$WINEPREFIX/.setup-v1"
      fi
      target="$WINEPREFIX/drive_c/Program Files/TouchDesigner ${version}"
      if [[ ! -f "$target/.nix-install" ]]; then
        if ! timeout 3 wineserver -w; then
          echo 'Close TouchDesigner before updating it.' >&2
          exit 1
        fi
        mkdir -p "$target"
        cp -r --no-preserve=mode ${app}/app/. "$target/"
        if [[ -d ${app}/commonappdata ]]; then
          mkdir -p "$WINEPREFIX/drive_c/ProgramData"
          cp -rn --no-preserve=mode ${app}/commonappdata/. "$WINEPREFIX/drive_c/ProgramData/"
        fi
        cp ${fixes}/Assets/wine_ui_fixes.tox "$target/wine_ui_fixes.tox"
        touch "$target/.nix-install"
      fi
      flock -u 9
      exec 9>&-
      if [[ "''${1:-}" == --setup ]]; then exit 0; fi
      cd "$target/bin"
      exec "$WINE" TouchDesigner.exe "$@"
    '';
  };
  fhs =
    (pkgs.steam.override {
      extraLibraries =
        p: with p; [
          freetype
          fontconfig
          libx11
          libxcursor
          libxrandr
          libxi
          libxrender
          libxext
          libxinerama
          libxcomposite
          libice
          libsm
          alsa-lib
          libpulseaudio
          gnutls
          libunwind
        ];
    }).run;
  launcher = pkgs.writeShellApplication {
    name = "touchdesigner";
    bashOptions = [ ];
    text = ''
      exec ${fhs}/bin/steam-run ${inner}/bin/touchdesigner-inner "$@"
    '';
  };
in
pkgs.symlinkJoin {
  name = "touchdesigner-${version}";
  paths = [
    launcher
    (pkgs.makeDesktopItem {
      name = "touchdesigner";
      desktopName = "TouchDesigner";
      exec = "${launcher}/bin/touchdesigner %f";
      icon = "applications-graphics";
      categories = [
        "Graphics"
        "AudioVideo"
      ];
      startupWMClass = "TouchDesigner.exe";
    })
  ];
  meta = {
    license = pkgs.lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "touchdesigner";
  };
}
