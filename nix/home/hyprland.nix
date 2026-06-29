{ pkgs, ... }:
# Hyprland のユーザー設定 (リック)。nixos-laptop でのみ import する。
# システム側 (hosts/nixos-laptop.nix) が programs.hyprland / hyprlock の
# PAM・session を用意し、こちらは見た目とキーバインドを管理する。
# 色は configs/theme/palettes.json (rose-pine) を SSO として共有 ([[theme]])。
let
  c = import ../lib/theme.nix; # c.base / c.text / c.iris ... (# は付かない hex)
in
{
  # package = null: システムの Hyprland を使い、HM は設定だけ管理する。
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    # settings は hyprlang 形式で生成 (将来既定が lua に変わるため明示固定)。
    configType = "hyprlang";
    settings = {
      "$mod" = "SUPER";
      "$terminal" = "ghostty";
      "$menu" = "wofi --show drun";

      monitor = ",preferred,auto,1";

      exec-once = [
        "hypridle"
        "hyprpolkitagent"
        "waybar"
        "hyprpaper"
        "mako"
        "wl-paste --watch cliphist store" # クリップボード履歴を蓄積
      ];

      input = {
        kb_layout = "us"; # JIS 配列なら "jp"
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgb(${c.iris}) rgb(${c.foam}) 45deg";
        "col.inactive_border" = "rgb(${c.overlay})";
        layout = "dwindle";
      };

      decoration = {
        rounding = 8;
        blur = {
          enabled = true;
          size = 6;
          passes = 2;
        };
      };

      animations.enabled = true;

      bind = [
        "$mod, Return, exec, $terminal"
        "$mod, Q, killactive"
        "$mod SHIFT, M, exit" # Hyprland 終了
        "$mod, E, exec, $terminal -e yazi" # ファイラ (yazi)
        "$mod, R, exec, $menu"
        "$mod, V, togglefloating"
        "$mod, F, fullscreen"
        "$mod, L, exec, hyprlock" # 手動ロック
        "$mod, C, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy" # 履歴貼付
        # 範囲スクショ → クリップボード
        ''$mod, P, exec, grim -g "$(slurp)" - | wl-copy''
        # フォーカス移動
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
      ]
      ++ builtins.concatLists (
        builtins.genList (
          i:
          let
            n = toString (i + 1);
            key = toString (if i + 1 == 10 then 0 else i + 1); # 10 番は 0 キー
          in
          [
            "$mod, ${key}, workspace, ${n}"
            "$mod SHIFT, ${key}, movetoworkspace, ${n}"
          ]
        ) 10
      );

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # 音量・輝度 (押しっぱなし対応)
      bindel = [
        ",XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86MonBrightnessUp, exec, brightnessctl set 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];
      bindl = [
        ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioPlay, exec, playerctl play-pause"
        ",XF86AudioNext, exec, playerctl next"
        ",XF86AudioPrev, exec, playerctl previous"
      ];
    };
  };

  # ロック画面の見た目
  programs.hyprlock = {
    enable = true;
    settings = {
      background = [ { color = "rgb(${c.base})"; } ];
      input-field = [
        {
          size = "260, 50";
          outline_thickness = 2;
          outer_color = "rgb(${c.iris})";
          inner_color = "rgb(${c.surface})";
          font_color = "rgb(${c.text})";
          placeholder_text = "password";
        }
      ];
    };
  };

  # アイドル制御 (HM のユーザーサービスとして起動。システム側 services.hypridle は無効化済み)
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300; # 5 分でロック
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 360; # 6 分で画面オフ
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 900; # 15 分でサスペンド (バッテリー保護)
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  # 通知デーモン
  services.mako = {
    enable = true;
    settings = {
      background-color = "#${c.surface}";
      text-color = "#${c.text}";
      border-color = "#${c.iris}";
      border-radius = 8;
      default-timeout = 5000;
    };
  };

  # ステータスバー
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      modules-left = [
        "hyprland/workspaces"
        "hyprland/window"
      ];
      modules-center = [ "clock" ];
      modules-right = [
        "pulseaudio"
        "backlight"
        "battery"
        "network"
        "tray"
      ];
      clock.format = "{:%Y-%m-%d %H:%M}";
      battery = {
        format = "{capacity}% {icon}";
        format-icons = [
          "󰁻"
          "󰁽"
          "󰁿"
          "󰂁"
          "󰁹"
        ];
      };
      network.format-wifi = "{essid} ";
      pulseaudio.format = "{volume}% {icon}";
      backlight.format = "{percent}% ";
    };
    style = ''
      * { font-family: "JetBrainsMono Nerd Font"; font-size: 13px; }
      window#waybar { background: #${c.base}; color: #${c.text}; }
      #workspaces button.active { color: #${c.iris}; }
      #battery, #network, #pulseaudio, #backlight, #clock { padding: 0 8px; }
    '';
  };

  # ghostty 設定を dotfiles から (darwin と同じ configs/terminals/ghostty を流用)。
  home.file.".config/ghostty".source = ../../configs/terminals/ghostty;
}
