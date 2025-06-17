# Theme Configuration - Single Source of Truth (SSOT)
# このファイルは全アプリケーションのテーマ設定の中央管理を行います

{ }:

{
  # カラーパレット設定 - Catppuccin Mocha ベース
  colors = {
    # Base colors
    base = "#1e1e2e";     # background
    mantle = "#181825";   # darker background
    crust = "#11111b";    # darkest background
    
    # Text colors
    text = "#cdd6f4";     # primary text
    subtext1 = "#bac2de"; # secondary text
    subtext0 = "#a6adc8"; # tertiary text
    
    # Surface colors
    surface0 = "#313244";
    surface1 = "#45475a"; 
    surface2 = "#585b70";
    overlay0 = "#6c7086";
    overlay1 = "#7f849c";
    overlay2 = "#9399b2";
    
    # Accent colors
    blue = "#ff6b9d";     # primary accent (TEST: changed to pink)
    lavender = "#b4befe"; # secondary accent
    sapphire = "#74c7ec";
    sky = "#89dceb";
    teal = "#94e2d5";
    green = "#a6e3a1";
    yellow = "#f9e2af";
    peach = "#fab387";
    maroon = "#eba0ac";
    red = "#f38ba8";
    mauve = "#cba6f7";
    pink = "#f5c2e7";
    flamingo = "#f2cdcd";
    rosewater = "#f5e0dc";
  };
  
  # フォント設定
  fonts = {
    # プライマリフォント（日本語対応）
    primary = "HackGen Console NF";
    # フォールバック
    fallback = ["SF Mono" "Menlo" "Monaco"];
    # サイズ設定
    size = {
      small = 12;
      medium = 14;
      large = 16;
      xlarge = 18;
    };
  };
}