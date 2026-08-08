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
  environment.systemPackages = [
    pkgs.ollama
    pkgs.nodejs_22
    pkgs.bitwarden-cli
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
        # Don't expose the API directly to the LAN. For external use, explicitly configure a
        # reverse proxy with auth/ACLs or Tailscale Serve.
        OLLAMA_HOST = "127.0.0.1:11434";
        # Unload the model after 30 min idle (frees 24GB). Use "-1" to keep it resident.
        OLLAMA_KEEP_ALIVE = "30m";
      };
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
  '';
}
