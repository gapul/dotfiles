{ pkgs }:
let
  # Official Windows releases; Wine prefixes are mutable user data, not Nix outputs.
  # Update the version and hash together, then launch once to upgrade the existing prefix.
  # Upstream exposes rolling download URLs: uncached old releases fail closed on hash
  # mismatch after replacement. Preserve the downloaded installers when updating.
  # Cavalry 2.8 links OpenCL.dll, which is absent from the base Wine package.
  wine = pkgs.wineWow64Packages.stableFull;
  affinityInstaller = pkgs.fetchurl {
    url = "https://downloads.affinity.studio/Affinity%20x64.exe";
    hash = "sha256:9e05d95a27d5e1249a9ba1e8b3ea5731988c2ab481f31aea1df13c88a025018b";
  };
  affinityMsi = pkgs.runCommand "affinity-3.3.1.4940.msi" { nativeBuildInputs = [ pkgs._7zz ]; } ''
    7zz e ${affinityInstaller} -tpe .rsrc/2057/BIN/135
    cp 135 "$out"
  '';
  webview2 = pkgs.fetchurl {
    url = "https://github.com/ryzendew/AffinityOnLinux/releases/download/10.4-Wine-Affinity/MicrosoftEdgeWebView2RuntimeInstallerX64.exe";
    hash = "sha256:e6d4f8887e57d9772cd301b2e1e1d46be67ac991bd194c84ab8f10fe850f8bb6";
  };
  mkApp =
    {
      name,
      title,
      version,
      installer,
      appDir,
      exe,
      verbs,
      overrides,
      extraSetup ? "",
    }:
    let
      dependencyKey = builtins.hashString "sha256" (
        "${wine}:${verbs}:${overrides}" + pkgs.lib.optionalString (extraSetup != "") ":${extraSetup}"
      );
      launcher = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [
          wine
          pkgs.winetricks
          pkgs.coreutils
          pkgs.util-linux
        ];
        text = ''
          export WINEPREFIX="''${XDG_DATA_HOME:-$HOME/.local/share}/creative-wine/${name}"
          export WINEARCH=win64
          # Winetricks probes ELF headers; stableFull's public wine is a shell wrapper.
          export WINE=${wine}/bin/.wine
          export WINESERVER=${wine}/bin/wineserver
          export WINEDEBUG="''${WINEDEBUG:--all}"
          export WINEDLLOVERRIDES="winemenubuilder.exe=d;${overrides}"
          export WINETRICKS_LATEST_VERSION_CHECK=disabled
          mkdir -p "$WINEPREFIX"
          exec 9>"$WINEPREFIX/.setup.lock"
          flock 9
          if [[ ! -f "$WINEPREFIX/.dependencies-${dependencyKey}" ]] ||
             [[ ! -f "$WINEPREFIX/.installer" ]] ||
             [[ "$(cat "$WINEPREFIX/.installer")" != "${installer}" ]]; then
            if ! timeout 3 wineserver -w; then
              echo 'Close ${title} before installing or updating it.' >&2
              exit 1
            fi
          fi
          if [[ ! -f "$WINEPREFIX/.dependencies-${dependencyKey}" ]]; then
            # Affinity uses native .NET below; do not prompt to download Wine Mono.
            WINEDLLOVERRIDES="$WINEDLLOVERRIDES;mscoree=d" wineboot --update
            wineserver -w
            winetricks -q ${verbs}
            wineserver -w
            ${extraSetup}
            touch "$WINEPREFIX/.dependencies-${dependencyKey}"
          fi
          if [[ ! -f "$WINEPREFIX/.installer" ]] || [[ "$(cat "$WINEPREFIX/.installer")" != "${installer}" ]]; then
            wine msiexec /i ${installer} /quiet /norestart
            wineserver -w
            test -f "$WINEPREFIX/drive_c/${appDir}/${exe}"
            printf '%s\n' '${installer}' > "$WINEPREFIX/.installer"
          fi
          flock -u 9
          exec 9>&-
          if [[ "''${1:-}" == --setup ]]; then exit 0; fi
          # Cavalry's browser sign-in callback must use the same working directory.
          cd "$WINEPREFIX/drive_c/${appDir}"
          exec wine ${pkgs.lib.escapeShellArg exe} "$@"
        '';
      };
    in
    pkgs.symlinkJoin {
      name = "${name}-${version}";
      paths = [
        launcher
        (pkgs.makeDesktopItem {
          inherit name;
          desktopName = title;
          exec = "${launcher}/bin/${name} %U";
          icon = "applications-graphics";
          categories = [ "Graphics" ];
          mimeTypes = [ "x-scheme-handler/${name}" ];
          startupWMClass = exe;
        })
      ];
      meta = {
        license = pkgs.lib.licenses.unfree;
        platforms = [ "x86_64-linux" ];
        mainProgram = name;
      };
    };
in
{
  cavalry = mkApp {
    name = "cavalry";
    title = "Cavalry";
    version = "2.8.0";
    installer = pkgs.fetchurl {
      url = "https://cavalry.studio/downloads/latest/Cavalry.msi";
      hash = "sha256:5409d19515665be1c3f27f247d5a31df36657048d1df448b1327a4eb8e04aaeb";
    };
    appDir = "Program Files/Cavalry";
    exe = "Cavalry.exe";
    verbs = "corefonts dxvk win11";
    overrides = "icuuc,icuin=n,b;mscoree=d";
  };
  affinity = mkApp {
    name = "affinity";
    title = "Affinity";
    version = "3.3.1.4940";
    installer = affinityMsi;
    appDir = "Program Files/Affinity/Affinity";
    exe = "Affinity.exe";
    verbs = "remove_mono vcrun2022 dotnet48 corefonts dxvk win11";
    overrides = "";
    extraSetup = ''
      # Pinned Microsoft runtime distributed by Linux-Affinity-Installer.
      # Install as Windows 11; only the WebView child process needs Windows 7 mode.
      wine winecfg -v win11
      if [[ ! -f "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/142.0.3595.94/msedgewebview2.exe" ]]; then
        wine ${webview2} /silent /install
      fi
      wine reg add 'HKLM\System\CurrentControlSet\Services\edgeupdate' /v Start /t REG_DWORD /d 4 /f
      wine reg add 'HKLM\System\CurrentControlSet\Services\edgeupdatem' /v Start /t REG_DWORD /d 4 /f
      wine taskkill /f /im MicrosoftEdgeUpdate.exe || true
      wine reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' /v Version /d win7 /f
      wine winecfg -v win11
      wineserver -w
      test -f "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/142.0.3595.94/msedgewebview2.exe"
    '';
  };
}
