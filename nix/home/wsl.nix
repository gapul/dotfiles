{
  config,
  pkgs,
  lib,
  user,
  ...
}:
let
  # wslu は nixpkgs から削除 (project discontinued / archived, 2026-04-08)。
  # 依存していたのは wslview(URL を Windows 既定ブラウザで開く) のみ。
  # wslpath は WSL 本体提供、WIN_USER 検出は cmd.exe 直叩きなので wslu 全体は不要。
  # → wslview を最小ラッパーで自作して置換する (cmd.exe /c start で既定ブラウザ起動)。
  wslview = pkgs.writeShellScriptBin "wslview" ''
    exec /mnt/c/Windows/System32/cmd.exe /c start "" "$@"
  '';
in
{
  # WSL2 専用の home-manager 設定
  # 前提: home/common.nix と home/linux.nix が先に評価されている
  # (flake.nix の modules = [ common linux wsl ] 順で合成)

  home.sessionVariables = {
    # nh が WSL 用 homeConfiguration を見るよう attr 名を明示
    NH_HOME_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix#homeConfigurations.${user.username}-wsl.activationPackage";
    # ブラウザ起動は Windows 側に投げる (自作 wslview ラッパー)
    BROWSER = "wslview";
  };

  # WSL 専用 packages
  home.packages = [
    wslview # 旧 wslu の代替 (URL を Windows 既定ブラウザで開く)
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
