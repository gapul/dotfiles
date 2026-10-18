{ pkgs, ... }:
let
  palette = import ../lib/theme.nix;
  json = pkgs.formats.json { };
  colors = p: {
    name = "Rosé Pine ${p.variant}";
    primary = "#${p.iris}";
    primaryText = "#${p.base}";
    primaryContainer = "#${p.overlay}";
    secondary = "#${p.foam}";
    surface = "#${p.surface}";
    surfaceText = "#${p.text}";
    surfaceVariant = "#${p.overlay}";
    surfaceVariantText = "#${p.subtle}";
    surfaceTint = "#${p.iris}";
    background = "#${p.base}";
    backgroundText = "#${p.text}";
    outline = "#${p.muted}";
    surfaceContainer = "#${p.surface}";
    surfaceContainerHigh = "#${p.overlay}";
    error = "#${p.love}";
    warning = "#${p.gold}";
    info = "#${p.foam}";
  };
  theme = json.generate "dms-rose-pine.json" {
    dark = colors palette.dark;
    light = colors palette.light;
  };
  applyMode = pkgs.writeShellApplication {
    name = "dms-appearance";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.darkman
      pkgs.dms-shell
    ];
    text = ''
      for _attempt in $(seq 1 20); do
        mode="''${1:-$(darkman get 2>/dev/null || true)}"
        case "$mode" in
          light|dark)
            if dms ipc call theme "$mode"; then exit 0; fi
            ;;
          "") ;;
          *) echo "invalid appearance mode: $mode" >&2; exit 2 ;;
        esac
        sleep 0.5
      done
      echo "DMS/darkman did not become ready for appearance sync" >&2
      exit 1
    '';
  };
in
{
  # DMS's portal sync is bidirectional and ignores the initial portal value.
  # Initialize after DMS owns its bus name, then follow darkman's transitions.
  systemd.user.services.dms-appearance = {
    Unit = {
      Description = "Apply darkman's appearance to DMS";
      After = [
        "dms.service"
        "darkman.service"
      ];
      Requires = [ "dms.service" ];
      Wants = [ "darkman.service" ];
      PartOf = [ "dms.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${applyMode}/bin/dms-appearance";
    };
    Install.WantedBy = [ "dms.service" ];
  };
  services.darkman.lightModeScripts.dms = "${applyMode}/bin/dms-appearance light";
  services.darkman.darkModeScripts.dms = "${applyMode}/bin/dms-appearance dark";
  # The NixOS dms-shell module owns the package and notification-bus service.
  # DMS supports read-only settings. Runtime history/session data stays writable.
  xdg.configFile."DankMaterialShell/settings.json".source = json.generate "dms-settings.json" {
    currentThemeName = "custom";
    customThemeFile = toString theme;
    syncModeWithPortal = false;
    runDmsMatugenTemplates = false;
    runUserMatugenTemplates = false; # Stylix and the shared palette own app configs
    fontFamily = "DejaVu Sans";
    monoFontFamily = "JetBrainsMono Nerd Font";
    clockFormat = "24h";
    weatherEnabled = false;
    audioVisualizerEnabled = false;
    soundsEnabled = false;
    updaterHideWidget = true; # updates belong to the pinned flake
    updaterCheckOnStart = false;

    # Keep the existing wallpaper, auth agent, hyprlock and lid-aware hypridle.
    screenPreferences.wallpaper = [ ];
    loginctlLockIntegration = false;
    lockBeforeSuspend = false;
    lockAtStartup = false;
    acMonitorTimeout = 0;
    acLockTimeout = 0;
    acSuspendTimeout = 0;
    batteryMonitorTimeout = 0;
    batteryLockTimeout = 0;
    batterySuspendTimeout = 0;
    batteryAutoPowerSaver = false; # TLP remains the power policy owner
    customPowerActionLock = "${pkgs.systemd}/bin/loginctl lock-session";
    powerMenuActions = [
      "lock"
      "suspend"
      "logout"
      "reboot"
      "poweroff"
    ];
    controlCenterWidgets =
      map
        (id: {
          inherit id;
          enabled = true;
          width = 50;
        })
        [
          "volumeSlider"
          "brightnessSlider"
          "wifi"
          "bluetooth"
          "audioOutput"
          "audioInput"
        ];
    dashTabs =
      map
        (id: {
          inherit id;
          enabled = true;
        })
        [
          "overview"
          "media"
          "settings"
        ];
    barConfigs = [
      {
        id = "default";
        name = "Main Bar";
        enabled = true;
        position = 0;
        screenPreferences = [ "all" ];
        leftWidgets = [
          "launcherButton"
          "workspaceSwitcher"
          "focusedWindow"
        ];
        centerWidgets = [ "clock" ];
        rightWidgets = [
          "systemTray"
          "clipboard"
          "notificationButton"
          "battery"
          "controlCenterButton"
        ];
        spacing = 4;
        innerPadding = 4;
        transparency = 0.95;
        widgetTransparency = 1.0;
        attachToScreenEdge = false;
        autoHide = false;
        visible = true;
      }
    ];
  };
}
