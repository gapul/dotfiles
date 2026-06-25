{
  config,
  pkgs,
  lib,
  user,
  ...
}:
{
  # WSL2 専用の home-manager 設定
  # 前提: home/common.nix と home/linux.nix が先に評価されている
  # (flake.nix の modules = [ common linux wsl ] 順で合成)

  home.sessionVariables = {
    # nh が WSL 用 homeConfiguration を見るよう attr 名を明示
    NH_HOME_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix#homeConfigurations.${user.username}-wsl.activationPackage";
    # ブラウザ起動は Windows 側に投げる (wslu の wslview)
    BROWSER = "wslview";
  };

  # WSL 専用 packages
  # wslu = wsl-open / wslview / wslvar 等 Windows ↔ Linux ブリッジ群
  home.packages = with pkgs; [
    wslu
  ];

  # WSL interop の zsh エイリアス・関数 (common の initContent の後に append)
  programs.zsh.initContent = lib.mkAfter ''
    # クリップボード: Mac の pbcopy/pbpaste と互換に
    if command -v clip.exe >/dev/null 2>&1; then
      alias pbcopy='clip.exe'
    fi
    if command -v powershell.exe >/dev/null 2>&1; then
      alias pbpaste='powershell.exe -NoProfile -Command "Get-Clipboard" 2>/dev/null | sed "s/\r$//"'
    fi

    # Windows ユーザーホームへのショートカット
    if [[ -d /mnt/c/Users ]]; then
      WIN_USER=$(/mnt/c/Windows/System32/cmd.exe /C 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')
      [[ -n "$WIN_USER" && -d "/mnt/c/Users/$WIN_USER" ]] && export WIN_HOME="/mnt/c/Users/$WIN_USER"
    fi

    # explorer.exe で現在ディレクトリを開く
    function explorer() {
      local target="''${1:-.}"
      /mnt/c/Windows/explorer.exe "$(wslpath -w "$target")" 2>/dev/null
    }

    # code.exe (VS Code on Windows) を WSL 経由で呼ぶラッパー (既に PATH に居れば不要)
    if ! command -v code >/dev/null 2>&1 && [ -x "/mnt/c/Program Files/Microsoft VS Code/bin/code" ]; then
      alias code='/mnt/c/Program\ Files/Microsoft\ VS\ Code/bin/code'
    fi
  '';
}
