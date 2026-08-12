{ pkgs, user, ... }:
{
  # Headless LLM worker (M4 Mac mini / 24GB).
  # Unlike the everyday workstation (darwin.nix), it loads no GUI casks at all;
  # it just keeps Ollama resident via launchd to serve an inference API over Tailscale / LAN.
  imports = [ ./darwin-common.nix ];

  networking = {
    hostName = "macmini";
    computerName = "macmini";
    localHostName = "macmini";
  };

  # Headless operation, so brew is minimal (only Tailscale's daemon).
  # Not loading GUI casks keeps rebuilds fast and the attack surface small.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall"; # undeclared brews are auto-uninstalled
      upgrade = false;
    };
    # Same priority rule as hosts/darwin.nix: nix > homebrew > everything else, and each formula
    # states why brew owns it. (uv was dropped here — modules/home/packages.nix already installs it,
    # and brew winning the PATH meant the duplicate was invisible.)
    brews = [
      "tailscale" # (b) tailnet daemon (auth only on first run via `sudo tailscale up`)
      # --- Local AI stack (added 2026-07. Kept from removal by cleanup=uninstall) ---
      # ffmpeg / aria2 / socat are all in nixpkgs for aarch64-darwin, so by the rule above they are
      # migration candidates. They stay on brew until someone can run a rebuild on the mini and
      # confirm the AI stack still comes up — moving them blind would break a headless machine.
      "ffmpeg" # audio/video conversion (preprocessing for transcribe/tts/voice-clone/audio-separation)
      "aria2" # self-healing multi-connection DL for large models (macmini direct hf-mirror/GitHub)
      "socat" # work around apple container's host-port publishing bug (host->containerIP forwarding)
      "container" # (a) Apple's first-party container runtime. not in nixpkgs (Open WebUI/AnythingLLM/Minecraft).
      # First run only needs runtime start + kernel setup: `container system start` /
      # `container system kernel set --recommended` (can't be declared; manual or ai-stack.sh).
    ];
    casks = [
      # Remote GUI for headless maintenance. Used only for GUI work SSH can't cover
      # (permission-approval dialogs, first-time auto-login setup, etc.). Enabling unattended
      # access and granting Screen Recording permission (TCC) can't be declared, so do them once via GUI.
      "rustdesk"
      # For Claude browser automation (Playwright MCP + claude-login-broker).
      # Headless operation, so launch without a GUI via --headless=new (chrome-launch.sh).
      "google-chrome"
    ];
  };

  # Ollama itself (nix package). The GUI ollama-app cask is not used.
  # nodejs: runtime for Playwright MCP (pnpm dlx) and claude-login-broker (inject-creds.js).
  # bitwarden-cli: after approval the broker pulls credentials via bw get. BW_SESSION is unlocked manually.
  # cloudflared: publishes the study agent's OpenAI-compatible API (127.0.0.1:8791) so the
  # dashboard on Cloudflare Pages can reach it. Only the tunnel egresses; nothing is exposed
  # on the LAN. The tunnel credentials can't be declared, so create them once with
  # `cloudflared tunnel login && cloudflared tunnel create manabi` (see launchd.daemons below).
  environment.systemPackages = [
    pkgs.ollama
    pkgs.nodejs_22
    pkgs.bitwarden-cli
    pkgs.cloudflared
  ];

  # Keep Ollama resident via a LaunchAgent.
  # Using an agent (login user) rather than a daemon (root) is to reliably grab Apple Silicon's
  # Metal GPU. It runs in a GUI session, so enabling auto-login is a prerequisite.
  launchd.agents.ollama = {
    # The launch spec is SSO'd in nix/lib/ollama-agent.nix (shared with workstation). Add only the diff.
    serviceConfig = (import ../lib/ollama-agent.nix { inherit pkgs; }) // {
      StandardOutPath = "/Users/${user.username}/Library/Logs/ollama.log";
      StandardErrorPath = "/Users/${user.username}/Library/Logs/ollama.log";
      EnvironmentVariables = {
        # nix-darwin bootstraps this agent into the system domain, which has no HOME.
        # Without it ollama aborts at startup with `panic: $HOME is not defined`, and
        # KeepAlive turns that into a crash loop that quietly fills the log file
        # (26 MB of panics before this was noticed). Unlike the workstation, where
        # home-manager runs the same spec inside the user's GUI session, here it has
        # to be spelled out.
        HOME = "/Users/${user.username}";
        # Don't expose the API directly to the LAN. For external use, explicitly configure a
        # reverse proxy with auth/ACLs or Tailscale Serve.
        OLLAMA_HOST = "127.0.0.1:11434";
        # Unload the model after 30 min idle (frees 24GB). Use "-1" to keep it resident.
        OLLAMA_KEEP_ALIVE = "30m";
      };
    };
  };

  # auto-fix パイプライン (GitHub issue → macmini の Claude Code → PR → CI → 自動マージ) が
  # 生きているかを1時間ごとに確かめる。監視対象と同じ GitHub Actions では回さない、という
  # 判断はスクリプト側の冒頭に書いてある。
  #
  # 元は手書きの plist と $HOME/autofix-monitor のスクリプトだった。中身は変えずに store へ
  # 移し、状態(ログと Claude の出力)だけ XDG の state 配下に分けている。
  launchd.agents.autofix-monitor = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "${../../configs/macmini/autofix-monitor/monitor.sh}"
      ];
      RunAtLoad = true;
      StartInterval = 3600;
      StandardOutPath = "/Users/${user.username}/.local/state/autofix-monitor/stdout.log";
      StandardErrorPath = "/Users/${user.username}/.local/state/autofix-monitor/stderr.log";
      EnvironmentVariables = {
        # launchd から起動されるとシェルの環境が入らないので、スクリプトが要る分だけ渡す。
        HOME = "/Users/${user.username}";
        XDG_STATE_HOME = "/Users/${user.username}/.local/state";
      };
    };
  };

  # Keep the tunnel up as a daemon (root) so it survives logout, unlike the Ollama agent which
  # needs a GUI session for Metal. Reads /usr/local/etc/manabi-tunnel.env for TUNNEL_TOKEN, which
  # is issued per-tunnel in the Cloudflare dashboard and can't live in the nix store.
  launchd.daemons.manabi-tunnel = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          . /usr/local/etc/manabi-tunnel.env 2>/dev/null || exit 0
          exec ${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/manabi-tunnel.log";
      StandardErrorPath = "/var/log/manabi-tunnel.log";
    };
  };

  # Prep for headless operation (nix-darwin has no typed option, so an idempotent script).
  # postActivation is used by darwin-common, so put this in preActivation to avoid a collision.
  system.activationScripts.preActivation.text = ''
    # Prevent sleep: don't let it sleep so it can serve inference unattended.
    /usr/bin/pmset -a sleep 0          >/dev/null 2>&1 || true
    /usr/bin/pmset -a disablesleep 1   >/dev/null 2>&1 || true
    # Enable Remote Login (SSH). Key auth reuses the existing setup (Bitwarden agent etc.) as-is.
    /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1 || true
    # The Hermes agent's inference adapter (see configs/macmini/hermes/README.md). It lives in
    # another user's home, which home-manager can't reach, and hermes never rewrites it — so the
    # declaration is the source of truth and gets laid down on every activation.
    if [ -d /Users/hermes ]; then
      /usr/bin/install -d -o hermes -g staff -m 755 /Users/hermes/.local/bin
      /usr/bin/install -o hermes -g staff -m 755 \
        ${../../configs/macmini/hermes/claude-acp} /Users/hermes/.local/bin/claude-acp
    fi
  '';
}
