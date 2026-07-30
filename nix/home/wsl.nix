{
  config,
  pkgs,
  lib,
  user,
  ...
}:
let
  # wslu was removed from nixpkgs (project discontinued / archived, 2026-04-08).
  # The only thing that depended on it was wslview (opens URLs in the Windows default browser).
  # wslpath is provided by WSL itself, and WIN_USER detection hits cmd.exe directly, so all of wslu is unnecessary.
  # -> Replace wslview with a minimal self-made wrapper (cmd.exe /c start launches the default browser).
  wslview = pkgs.writeShellScriptBin "wslview" ''
    exec /mnt/c/Windows/System32/cmd.exe /c start "" "$@"
  '';
in
{
  # WSL2-only home-manager config
  # Prerequisite: home/common.nix and home/linux.nix are evaluated first
  # (composed in flake.nix's modules = [ common linux wsl ] order)

  home.sessionVariables = {
    # Specify the attr name explicitly so nh looks at the WSL homeConfiguration
    NH_HOME_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix#homeConfigurations.${user.username}-wsl.activationPackage";
    # Delegate browser launching to the Windows side (self-made wslview wrapper)
    BROWSER = "wslview";
  };

  # WSL-only packages
  home.packages = [
    wslview # replacement for the old wslu (opens URLs in the Windows default browser)
    pkgs.socat # UNIX<->Named Pipe bridge to share the Windows ssh-agent service from WSL
    pkgs.claude-code # Claude Code CLI (Mac uses brew cask management, so declare via nix only on WSL)
    pkgs.codex # OpenAI Codex CLI
    pkgs.nodejs_22 # for building/testing the control-plane (Next.js) (engines: node>=20.11)
  ];

  # WSL interop zsh aliases/functions (appended after common's initContent)
  programs.zsh.initContent = lib.mkAfter ''
    # clipboard: make compatible with Mac's pbcopy/pbpaste
    if command -v clip.exe >/dev/null 2>&1; then
      alias pbcopy='clip.exe'
    fi
    if command -v powershell.exe >/dev/null 2>&1; then
      alias pbpaste='powershell.exe -NoProfile -Command "Get-Clipboard" 2>/dev/null | sed "s/\r$//"'
    fi

    # shortcut to the Windows user home
    if [[ -d /mnt/c/Users ]]; then
      WIN_USER=$(/mnt/c/Windows/System32/cmd.exe /C 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')
      [[ -n "$WIN_USER" && -d "/mnt/c/Users/$WIN_USER" ]] && export WIN_HOME="/mnt/c/Users/$WIN_USER"
    fi

    # open the current directory with explorer.exe
    function explorer() {
      local target="''${1:-.}"
      /mnt/c/Windows/explorer.exe "$(wslpath -w "$target")" 2>/dev/null
    }

    # wrapper to call code.exe (VS Code on Windows) via WSL (unnecessary if already on PATH)
    if ! command -v code >/dev/null 2>&1 && [ -x "/mnt/c/Program Files/Microsoft VS Code/bin/code" ]; then
      alias code='/mnt/c/Program\ Files/Microsoft\ VS\ Code/bin/code'
    fi

    # Share the Windows OpenSSH Authentication Agent from WSL (P2-11).
    # Prerequisite: on the Windows side, bootstrap.ps1 sets ssh-agent to Auto+Running and
    #       albertony.npiperelay (winget) is installed.
    # Use socat to relay WSL's UNIX domain socket -> npiperelay -> the Named pipe
    # //./pipe/openssh-ssh-agent. Idempotent per terminal.
    #
    # winget does not expose npiperelay's exe under Links/ (unlike yazi etc., the package
    # itself has no shortcut hint), so add the path under Packages/ to PATH.
    if [[ -n "''${WIN_USER:-}" ]]; then
      npr_root="/mnt/c/Users/$WIN_USER/AppData/Local/Microsoft/WinGet/Packages"
      npr_dir=$(ls -d "$npr_root"/albertony.npiperelay_* 2>/dev/null | head -1)
      [[ -n "$npr_dir" ]] && export PATH="$PATH:$npr_dir"
    fi
    if command -v npiperelay.exe >/dev/null 2>&1 && command -v socat >/dev/null 2>&1; then
      export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
      if ! ss -lnx 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
        rm -f "$SSH_AUTH_SOCK"
        (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK,fork" \
           EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork \
           >/dev/null 2>&1 &) >/dev/null 2>&1
      fi
    fi
  '';
}
