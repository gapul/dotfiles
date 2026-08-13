{
  pkgs,
  user,
  claudeAcp,
  ...
}:
let
  # まなびはサービスなので、実体は gapul/manabi (private) にあり、この機械にはそのクローンが
  # 置いてある。ここが持つのは「この機械がまなびを動かす」という宣言だけで、中身は向こうの
  # 更新に追従する (dotfiles の rebuild は要らない)。private なので flake input にはできない
  # ——CI が fetch できない——から、パスで参照する。
  manabi = "/Users/Shared/manabi";
in
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
    # and brew winning the PATH meant the duplicate was invisible. ffmpeg and aria2 followed on
    # 2026-08-13, which also sweeps the twenty dependency formulae they had dragged in.)
    brews = [
      # The tailnet daemon. Stays on brew: the running daemon holds this node's identity, and
      # swapping the implementation under it buys nothing. Auth happened once via `sudo tailscale up`.
      "tailscale"
    ];
    casks = [
      # (RustDesk was here for remote GUI. It never got its unattended access or its Screen
      #  Recording grant, so it had never once been used, while macOS Screen Sharing on :5900
      #  already covers the same job over the tailnet with nothing to install.)
      # For Claude browser automation (Playwright MCP + claude-login-broker). Driven through the
      # `chrome-automation` wrapper (home/macmini.nix): own profile, windowless, CDP on 9222, and
      # stopped when the job ends. The chrome-launch.sh this comment used to point at never existed.
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
  # ffmpeg / aria2 moved off homebrew (2026-08-13). They were kept there because nobody could
  # verify the AI stack still came up on this headless machine after a swap; that check has now
  # been done. systemPackages rather than home.packages on purpose: ai-stack.sh builds its own
  # PATH from /opt/homebrew and /run/current-system/sw, and the per-user profile is not on it.
  environment.systemPackages = [
    pkgs.ollama
    pkgs.nodejs_22
    pkgs.bitwarden-cli
    pkgs.cloudflared
    pkgs.ffmpeg
    pkgs.aria2
    # marp: popo's setup wizard shells out to `npm install -g @marp-team/marp-cli` when it cannot
    # find marp on PATH. Declaring it here means that step never runs — and npm stays what it is
    # on this machine, a thing that comes along with node rather than a package manager anyone uses.
    pkgs.marp-cli
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
        # Unload the model after 5 min idle. 30m was the old value and it meant one question
        # left ~9G of a 12B model sitting there for half an hour, competing with whatever else
        # this machine is doing. Reloading costs a few seconds; holding the memory costs more.
        OLLAMA_KEEP_ALIVE = "5m";
        # One model at a time. Two resident models is how 24G turns into swap.
        OLLAMA_MAX_LOADED_MODELS = "1";
      };
      # Tier 1: somebody is watching a cursor blink while this answers.
      ProcessType = "Interactive";
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

  # Paper, run straight on macOS as its own user rather than in a container.
  #
  # It used to be an Apple container, which bought the itzg image's conveniences and cost far more:
  # published ports never actually forwarded (the host side accepts then resets, TCP included, so
  # nobody could ever join), ENABLE_AUTOPAUSE could not start knockd on the guest interface, and the
  # guest kernel meant ~3.2G resident no matter how small the JVM heap was. Native, the same world
  # sits at ~1.2G and binds the port itself. With this the mini has no containers left at all.
  #
  # The jar is pinned on purpose: a server that upgrades itself locks every player out until they
  # all update their client. Bumping it means dropping the new jar in and editing this line.
  launchd.daemons.minecraft = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.temurin-bin-25}/bin/java"
        # Aikar's flags, minus -XX:+AlwaysPreTouch and with a small -Xms. Pre-touching commits the
        # whole heap at boot, which is the right trade for a dedicated box and the wrong one here:
        # this server is empty most of the time and shares 24G with the AI stack.
        "-Xms512M"
        "-Xmx2G"
        "-XX:+UseG1GC"
        "-XX:+ParallelRefProcEnabled"
        "-XX:MaxGCPauseMillis=200"
        "-XX:+UnlockExperimentalVMOptions"
        "-XX:+DisableExplicitGC"
        "-XX:G1NewSizePercent=30"
        "-XX:G1MaxNewSizePercent=40"
        "-XX:G1HeapRegionSize=8M"
        "-XX:G1ReservePercent=20"
        "-XX:G1HeapWastePercent=5"
        "-XX:G1MixedGCCountTarget=4"
        "-XX:InitiatingHeapOccupancyPercent=15"
        "-XX:G1MixedGCLiveThresholdPercent=90"
        "-XX:G1RSetUpdatingPauseTimePercent=5"
        "-XX:SurvivorRatio=32"
        "-XX:+PerfDisableSharedMem"
        "-XX:MaxTenuringThreshold=1"
        "-jar"
        "paper-26.1.2-74.jar"
        "--nogui"
      ];
      UserName = "mcsrv";
      WorkingDirectory = "/Users/mcsrv/server";
      # Tier 1: tick latency is the thing players feel. Idle most of the time anyway.
      ProcessType = "Interactive";
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/mcsrv/server/logs/launchd.log";
      StandardErrorPath = "/Users/mcsrv/server/logs/launchd.log";
    };
  };

  # --- Hermes, brought under nix -------------------------------------------------------------
  #
  # These six were hand-written plists in /Library/LaunchDaemons, i.e. daemons nothing declared.
  # Migrating them is also the chance to give this machine a scheduling policy, because until now
  # everything ran at the same priority: a long agent turn competed with Minecraft ticks and with
  # inference somebody was waiting on.
  #
  # The tiers are: Interactive for what a human is waiting on (ollama, ComfyUI, the game server),
  # Standard for the cheap supervisors, Background for the agents and every batch job. Background
  # on Apple Silicon means the E cores, which is right for these: they spend their time waiting on
  # the network, not on the CPU.
  #
  # The labels change (net.gapul.* -> org.nixos.*), so the old plists are booted out below.
  #
  # The runner scripts come from the store too (configs/macmini/hermes/). They used to sit loose in
  # /Users/hermes/.hermes/bin and /usr/local/libexec, which is how the watchdog ended up still
  # polling claude-bridge on :9180 four hours after that daemon was deleted — its state file said
  # `down: bridge` and it had paged once. Reading it to move it is what found that.

  # Hermes proper — the Discord side. Talks to Claude through the claude-acp adapter.
  launchd.daemons.hermes-gateway = {
    serviceConfig = {
      ProgramArguments = [ "${../../configs/macmini/hermes/hermes-gateway-run.sh}" ];
      UserName = "hermes";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/Users/hermes/.hermes/logs/gateway.log";
      StandardErrorPath = "/Users/hermes/.hermes/logs/gateway.log";
    };
  };

  # The second instance ("まなび"), which runs out of its own HOME so it can hold its own
  # api_server port. Same binary, different profile.
  #
  # It used to be called imouto everywhere on this side while the outside world — the Telegram
  # bot, the dashboard, the other daemons — called it manabi. One name now, and the outward one
  # won. Session keys are unaffected: this instance has its own HOME, so its keys are
  # `agent:main:discord:...` and never carried the old name.
  launchd.daemons.hermes-gateway-manabi = {
    serviceConfig = {
      ProgramArguments = [ "${manabi}/bin/manabi-gateway-run.sh" ];
      UserName = "hermes";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/Users/hermes/manabi-home/gateway.log";
      StandardErrorPath = "/Users/hermes/manabi-home/gateway.log";
    };
  };

  launchd.daemons.hermes-watchdog = {
    serviceConfig = {
      ProgramArguments = [ "${../../configs/macmini/hermes/hermes-watchdog.sh}" ];
      StartInterval = 300;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "/var/log/hermes-watchdog.log";
      StandardErrorPath = "/var/log/hermes-watchdog.log";
    };
  };

  launchd.daemons.hermes-logrotate = {
    serviceConfig = {
      ProgramArguments = [ "${../../configs/macmini/hermes/hermes-logrotate.sh}" ];
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 15;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/var/log/hermes-logrotate.log";
      StandardErrorPath = "/var/log/hermes-logrotate.log";
    };
  };

  launchd.daemons.hermes-brain-backup = {
    serviceConfig = {
      ProgramArguments = [ "${../../configs/macmini/hermes/hermes-brain-backup.sh}" ];
      UserName = "hermes";
      StartCalendarInterval = [
        {
          Hour = 3;
          Minute = 30;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/Users/hermes/.hermes/logs/brain-backup.log";
      StandardErrorPath = "/Users/hermes/.hermes/logs/brain-backup.log";
    };
  };

  # The nightly study review. Its old plist still pointed at ~/ai/manabi-dashboard, which the
  # 2026-08-12 cleanup moved to Developer/projects — so it had been failing at 22:30 with nothing
  # to say so. Declaring it is what surfaced that.
  launchd.daemons.manabi-daily-review = {
    serviceConfig = {
      ProgramArguments = [ "${manabi}/dashboard/daily_review.sh" ];
      UserName = user.username;
      StartCalendarInterval = [
        {
          Hour = 22;
          Minute = 30;
        }
      ];
      ProcessType = "Background";
      Nice = 10;
      # launchd creates the parent of these paths at every start, whether or not the program runs.
      # That is what kept resurrecting ~/ai/manabi-dashboard (the old hand-written plist pointed
      # there long after ~/ai was retired) and then ~/Developer/projects/manabi-dashboard, which
      # this unit recreated the same night the service moved to /Users/Shared/manabi. Logs live in
      # XDG state now, next to the dashboard refresh log, so nothing is resurrected anywhere.
      StandardOutPath = "/Users/${user.username}/.local/state/manabi/daily_review.log";
      StandardErrorPath = "/Users/${user.username}/.local/state/manabi/daily_review.log";
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
    # Power Nap wakes the machine for background work it does not need to do; this one never
    # sleeps in the first place.
    /usr/bin/pmset -a powernap 0 >/dev/null 2>&1 || true
    # Wi-Fi off. The mini is wired (en0 is the default route) and was sitting on both networks at
    # once, which buys nothing and keeps the radio, its driver extension and wifianalyticsd busy.
    # If the cable ever dies this machine needs hands anyway — it is three metres away.
    /usr/sbin/networksetup -setairportpower en1 off >/dev/null 2>&1 || true
    # The hand-written plists the daemons above replace. nix-darwin names its units org.nixos.*,
    # so without this both copies would be loaded and Hermes would come up twice.
    for label in net.gapul.hermes-gateway net.gapul.hermes-gateway-imouto net.gapul.hermes-watchdog \
                 net.gapul.hermes-logrotate net.gapul.hermes-brain-backup net.gapul.manabi-daily-review \
                 org.nixos.hermes-gateway-imouto; do
      if [ -f "/Library/LaunchDaemons/$label.plist" ]; then
        /bin/launchctl bootout "system/$label" >/dev/null 2>&1 || true
        /bin/rm -f "/Library/LaunchDaemons/$label.plist" || true
      fi
    done
    # /opt/ai/bin, the pre-XDG copies of the AI wrappers. Root-owned, dated 2026-07-16, and put on
    # the system PATH by /etc/paths.d/ai — so they shadowed the declared ~/.local/bin ones in every
    # interactive shell. They still pointed at ~/models and ~/sbv2-venv, paths the XDG move retired,
    # which is why `transcribe` answered "モデル未導入" while the AI panel (which builds its own PATH)
    # worked fine. The declaration was right; something older was winning.
    /bin/rm -f /etc/paths.d/ai || true
    /bin/rm -rf /opt/ai || true
    # Google's updater, removed. Chrome here is an automation target that gets upgraded by hand
    # with the rest of the declaration, so a resident agent waking up to check for versions is
    # noise. Chrome re-installs Keystone whenever it is launched, so this runs every activation
    # rather than once; checkInterval 0 keeps it quiet in between.
    guiuid=$(/usr/bin/id -u ${user.username})
    /usr/bin/sudo -u ${user.username} /usr/bin/defaults write com.google.Keystone.Agent checkInterval 0 >/dev/null 2>&1 || true
    for label in com.google.GoogleUpdater.wake com.google.keystone.agent com.google.keystone.xpcservice; do
      /bin/launchctl bootout "gui/$guiuid/$label" >/dev/null 2>&1 || true
      /bin/rm -f "/Users/${user.username}/Library/LaunchAgents/$label.plist" || true
    done
    /bin/rm -rf "/Users/${user.username}/Library/Google" \
      "/Users/${user.username}/Library/Application Support/Google/GoogleUpdater" || true
    # No Spotlight on a machine nobody searches from. mds_stores alone held ~100M and the indexer
    # keeps walking the disk; the agents here search with grep/ripgrep, not mdfind.
    /usr/bin/mdutil -a -i off >/dev/null 2>&1 || true
    # The desktop still needs a login session (Metal wants one), but not a moving picture in it:
    # the default aerial wallpaper burned ~17% CPU between the extension, its video decoder and
    # WindowServer, on a screen no one looks at. Nothing declarative sets this — it is done once
    # with NSWorkspace.setDesktopImageURL as the logged-in user and persists.
    # The Hermes agent's inference adapter (see configs/macmini/hermes/README.md). It lives in
    # another user's home, which home-manager can't reach, and hermes never rewrites it — so the
    # declaration is the source of truth and gets laid down on every activation.
    if [ -d /Users/hermes ]; then
      /usr/bin/install -d -o hermes -g staff -m 755 /Users/hermes/.local/bin
      /usr/bin/install -o hermes -g staff -m 755 \
        ${claudeAcp}/bin/claude-acp /Users/hermes/.local/bin/claude-acp
    fi
  '';
}
