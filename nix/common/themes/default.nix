# Theme Configuration Module for home-manager
# Applies theme settings to various programs

{ config, lib, pkgs, ... }:

let
  themeConfig = import ./colors.nix;
  colors = themeConfig.colors.str.dark;  # Default to dark theme
in {
  # Programs that need theme configuration
  programs = {
    # Terminal theme (if using Alacritty)
    alacritty = lib.mkIf (config.programs.alacritty.enable or false) {
      settings = {
        colors = {
          primary = {
            background = colors.base;
            foreground = colors.text;
          };
          cursor = {
            text = colors.base;
            cursor = colors.cursor;
          };
          selection = {
            text = colors.text;
            background = colors.selection;
          };
          normal = {
            black = colors.surface0;
            red = colors.red;
            green = colors.green;
            yellow = colors.yellow;
            blue = colors.blue;
            magenta = colors.peach;
            cyan = colors.blue;
            white = colors.text;
          };
        };
        font = {
          normal.family = themeConfig.typography.monospace.name;
          size = themeConfig.typography.monospace.size;
        };
      };
    };
    
    # Starship prompt theme
    starship = lib.mkIf (config.programs.starship.enable or false) {
      settings = {
        palette = "catppuccin_mocha";
        palettes.catppuccin_mocha = {
          rosewater = "#f5e0dc";
          flamingo = "#f2cdcd";
          pink = "#f5c2e7";
          mauve = "#cba6f7";
          red = colors.red;
          maroon = "#eba0ac";
          peach = colors.peach;
          yellow = colors.yellow;
          green = colors.green;
          teal = "#94e2d5";
          sky = "#89dceb";
          sapphire = "#74c7ec";
          blue = colors.blue;
          lavender = "#b4befe";
          text = colors.text;
          subtext1 = "#bac2de";
          subtext0 = "#a6adc8";
          overlay2 = "#9399b2";
          overlay1 = "#7f849c";
          overlay0 = "#6c7086";
          surface2 = "#585b70";
          surface1 = "#45475a";
          surface0 = colors.surface0;
          base = colors.base;
          mantle = colors.mantle;
          crust = "#11111b";
        };
      };
    };
  };

  # Export theme configuration for other modules
  home.sessionVariables = {
    THEME_MODE = "dark";
    THEME_BACKGROUND = colors.base;
    THEME_FOREGROUND = colors.text;
    THEME_ACCENT = colors.blue;
  };
}