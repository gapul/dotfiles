{
  config,
  lib,
  pkgs,
  ...
}:
let
  pointer = "${pkgs.wl-kbptr}/bin/wl-kbptr";
  control = "${pkgs.wlrctl}/bin/wlrctl";
  # Hyprland or niri, whichever is running (lib/wm-session.nix). niri has no submaps, so the
  # mouse mode (m) and the Escape-to-cancel bind of the grid are Hyprland-only; under niri the
  # grid is cancelled with wl-kbptr's own Escape.
  wm = "${import ../lib/wm-session.nix { inherit pkgs; }}/bin/wm-session";
  whichKey = "${pkgs.wlr-which-key}/bin/wlr-which-key";
  # A layer-shell overlay does not suppress Hyprland's global shortcuts by
  # itself: a still-held Super+L would lock the session while selecting labels.
  grid = pkgs.writeShellScript "wl-grid" ''
    set -eu
    exec 9>"''${XDG_RUNTIME_DIR:?}/wl-grid.lock"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0
    trap '${wm} submap reset' EXIT
    ${wm} submap wl-pointer
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
        cmd = "${wm} submap wl-mouse";
      }
      {
        key = "w";
        desc = "Window";
        submenu = [
          {
            key = "h";
            desc = "Move left";
            cmd = "${wm} move l";
            keep_open = true;
          }
          {
            key = "j";
            desc = "Move down";
            cmd = "${wm} move d";
            keep_open = true;
          }
          {
            key = "k";
            desc = "Move up";
            cmd = "${wm} move u";
            keep_open = true;
          }
          {
            key = "l";
            desc = "Move right";
            cmd = "${wm} move r";
            keep_open = true;
          }
          {
            key = "Left";
            desc = "Narrower";
            cmd = "${wm} resize -40 0";
            keep_open = true;
          }
          {
            key = "Right";
            desc = "Wider";
            cmd = "${wm} resize 40 0";
            keep_open = true;
          }
          {
            key = "Up";
            desc = "Shorter";
            cmd = "${wm} resize 0 -40";
            keep_open = true;
          }
          {
            key = "Down";
            desc = "Taller";
            cmd = "${wm} resize 0 40";
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
  # For home/niri.nix, which binds the same two keys.
  _module.args.wlKeyboard = {
    inherit grid;
    menu = whichKey;
  };
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
          (mkLuaInline ''hl.dsp.exec_cmd("${whichKey}")'')
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
