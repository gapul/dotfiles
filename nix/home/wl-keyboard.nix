{
  config,
  lib,
  pkgs,
  ...
}:
let
  pointer = "${pkgs.wl-kbptr}/bin/wl-kbptr";
  control = "${pkgs.wlrctl}/bin/wlrctl";
  # A layer-shell overlay does not suppress Hyprland's global shortcuts by
  # itself: a still-held Hyper+L would lock the session while selecting labels.
  grid = pkgs.writeShellScript "wl-grid" ''
    set -eu
    exec 9>"''${XDG_RUNTIME_DIR:?}/wl-grid.lock"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0
    cleanup() {
      if [ "$(hyprctl submap)" = wl-pointer ]; then
        hyprctl dispatch submap reset >/dev/null
      fi
    }
    trap cleanup EXIT
    hyprctl dispatch submap wl-pointer >/dev/null
    ${pointer} -o modes=tile,bisect
  '';
  yaml = pkgs.formats.yaml { };
  menu = yaml.generate "wl-keyboard.yaml" {
    font = "JetBrainsMono Nerd Font 12";
    background = "#191724ee";
    color = "#e0def4";
    border = "#c4a7e7";
    anchor = "center";
    inhibit_compositor_keyboard_shortcuts = true;
    menu = [
      {
        key = "g";
        desc = "Grid / precise position";
        cmd = grid;
      }
      {
        key = "m";
        desc = "Mouse mode: hjkl move, s/d/f click, u/n scroll, Esc exit";
        cmd = "hyprctl dispatch submap wl-mouse";
      }
      {
        key = "w";
        desc = "Window";
        submenu = [
          {
            key = "h";
            desc = "Move left";
            cmd = "hyprctl dispatch movewindow l";
            keep_open = true;
          }
          {
            key = "j";
            desc = "Move down";
            cmd = "hyprctl dispatch movewindow d";
            keep_open = true;
          }
          {
            key = "k";
            desc = "Move up";
            cmd = "hyprctl dispatch movewindow u";
            keep_open = true;
          }
          {
            key = "l";
            desc = "Move right";
            cmd = "hyprctl dispatch movewindow r";
            keep_open = true;
          }
          {
            key = "Left";
            desc = "Narrower";
            cmd = "hyprctl dispatch resizeactive -40 0";
            keep_open = true;
          }
          {
            key = "Right";
            desc = "Wider";
            cmd = "hyprctl dispatch resizeactive 40 0";
            keep_open = true;
          }
          {
            key = "Up";
            desc = "Shorter";
            cmd = "hyprctl dispatch resizeactive 0 -40";
            keep_open = true;
          }
          {
            key = "Down";
            desc = "Taller";
            cmd = "hyprctl dispatch resizeactive 0 40";
            keep_open = true;
          }
        ];
      }
    ];
  };
in
{
  home.packages = with pkgs; [
    wl-kbptr
    wlrctl
    wlr-which-key
  ];
  # wl-kbptr 0.4.1 crashes in floating_mode_key while its synchronous screen
  # capture is initializing on this Hyprland session. Keep detect mode unbound
  # until it is fixed and verified; tile/bisect works without screen capture.
  xdg.configFile."wl-kbptr/config".text = ''
    [general]
    modes=tile,bisect
  '';
  xdg.configFile."wlr-which-key/config.yaml".source = menu;
  wayland.windowManager.hyprland.settings.bind =
    let
      inherit (lib.generators) mkLuaInline;
    in
    [
      {
        _args = [
          (mkLuaInline ''mod .. " + I"'')
          (mkLuaInline ''hl.dsp.exec_cmd("${grid}")'')
        ];
      }
      {
        _args = [
          (mkLuaInline ''mod .. " + K"'')
          (mkLuaInline ''hl.dsp.exec_cmd("${pkgs.wlr-which-key}/bin/wlr-which-key")'')
        ];
      }
    ];
  # Keep unmodified mouse keys in a dedicated mode so normal typing is unaffected.
  wayland.windowManager.hyprland.submaps =
    let
      inherit (lib.generators) mkLuaInline;
      exec = cmd: mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON cmd})";
      bind = k: dsp: {
        _args = [
          k
          dsp
        ];
      };
      repeating = k: dsp: {
        _args = [
          k
          dsp
          { repeating = true; }
        ];
      };
    in
    {
      wl-pointer.settings.bind = [
        (bind (mkLuaInline ''mod .. " + Escape"'') (
          exec "${pkgs.procps}/bin/pkill -u ${config.home.username} -x wl-kbptr"
        ))
      ];
      wl-mouse.settings.bind = [
        (repeating "h" (exec "${control} pointer move -15 0"))
        (repeating "j" (exec "${control} pointer move 0 15"))
        (repeating "k" (exec "${control} pointer move 0 -15"))
        (repeating "l" (exec "${control} pointer move 15 0"))
        (bind "s" (exec "${control} pointer click left"))
        (bind "d" (exec "${control} pointer click middle"))
        (bind "f" (exec "${control} pointer click right"))
        (repeating "u" (exec "${control} pointer scroll -30 0"))
        (repeating "n" (exec "${control} pointer scroll 30 0"))
        (bind "Escape" (mkLuaInline ''hl.dsp.submap("reset")''))
      ];
    };
}
