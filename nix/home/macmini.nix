{
  config,
  lib,
  pkgs,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  # Place the AI stack's runtime assets via out-of-store symlinks with dotfiles as the single source.
  # Editing directly on the mini is reflected straight into the repo (same mechanism as nvim).
  aiService = name: {
    ".local/share/ai-stack/${name}".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/services/${name}";
  };
  aiWrapper = name: {
    ".local/bin/${name}".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/bin/${name}";
  };
in
{
  # macmini-specific layer. The base CLI/zsh/XDG set inherits home/common.nix
  # composed on the flake side (no sops/age keys are brought in).
  # Layout follows XDG/ghq (the dedicated ~/ai was retired 2026-07-19):
  #   service bodies -> ~/.local/share/ai-stack/ (HM symlink)
  #   venvs -> ~/.local/share/venvs/, models -> ~/.local/share/models/
  #   (no app data here anymore: the web frontends moved to homeserver, minecraft to its own user)
  #   ComfyUI / GPT-SoVITS -> ~/Developer/github.com/<owner>/<repo> (ghq style)
  #   own projects with no upstream -> ~/Developer/projects/<name>
  #     (~/ai grew two of these back after the retirement; moved out 2026-08-12)
  # venvs/models/data are non-reproducible assets, so they're managed imperatively
  # (rebuild steps in configs/macmini/bootstrap.sh and README).

  home.packages = [
    # ccm: default Claude Code launch form on the mac mini. Permission prompts are kept.
    # Don't default --dangerously-skip-permissions even in non-interactive environments, because
    # prompt injection from external content would directly become arbitrary command execution rights.
    (pkgs.writeShellScriptBin "ccm" ''
      exec "$HOME/.local/bin/claude" \
        --remote-control dotfiles \
        --continue \
        --add-dir "$HOME/.dotfiles" \
        "$@"
    '')
    # chrome-automation: the same shape the workstation uses. Chrome here is only ever an
    # automation target (Playwright MCP attaches over CDP on 9222, and claude-login-broker
    # drives it), so it gets its own profile, comes up windowless in the background, and is
    # expected to be shut down when the job is done rather than left resident.
    #
    # Not `--headless`: the workstation proved on 2026-08-10 that the extension's native host
    # never starts in that mode. What was actually running on this machine were one-shot
    # `--print-to-pdf` / `--screenshot` invocations that failed to exit — one had been stuck
    # for three days holding 250M. `stop` matches on the profile path so it can only ever take
    # down the automation instance.
    (pkgs.writeShellScriptBin "chrome-automation" ''
      profile="$HOME/Library/Application Support/Google/Chrome-automation"
      case "''${1:-start}" in
        start)
          /usr/bin/open -gjn -a "Google Chrome" --args \
            --user-data-dir="$profile" \
            --no-startup-window \
            --remote-debugging-port=9222
          ;;
        stop)
          /usr/bin/pkill -f "Chrome-automation" || true
          ;;
        status)
          /usr/bin/pgrep -fl "Chrome-automation" || echo "not running"
          ;;
        *)
          echo "usage: chrome-automation [start|stop|status]" >&2
          exit 2
          ;;
      esac
    '')
  ];

  # brew shellenv (here because the headless mini doesn't load home/darwin.nix) +
  # machine-local secrets (HF_TOKEN etc.) are read from local.zsh outside nix management.
  programs.zsh.initContent = lib.mkAfter ''
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    [ -f "$HOME/.config/zsh/local.zsh" ] && source "$HOME/.config/zsh/local.zsh"
  '';

  # Which flake attribute this machine is. `just rebuild` otherwise falls back to the
  # username, which names the workstation config — and both Macs report the same
  # LocalHostName, so there is nothing else to tell them apart.
  xdg.configFile."dotfiles/host".text = "macmini\n";

  # AI stack runtime assets (bodies in configs/macmini/{services,bin})
  home.file = lib.mkMerge (
    map aiService [
      "ai-stack.sh"
      "ai_panel.py"
      "diarize_merge.py"
      "llm_ask.py"
      "rag_server.py"
      "sbv2_tts.py"
    ]
    ++ map aiWrapper [
      "ask"
      "describe"
      "ocr"
      "separate"
      "transcribe"
      "transcribe-diarize"
      "tts"
      "voice-clone"
    ]
  );

  # AI stack resident (replaces the old hand-written net.gapul.* plists. 2026-07-19)
  launchd.agents.ai-stack = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/bash"
        "${config.home.homeDirectory}/.local/share/ai-stack/ai-stack.sh"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/ai-stack.log";
      StandardErrorPath = "/tmp/ai-stack.log";
    };
  };
  # Rebuilds the study dashboard and deploys it to Cloudflare Pages every 15 minutes.
  # Replaces the last hand-written net.gapul.* plist (2026-08-12). The script stays out
  # of the store on purpose: its own directory is the wrangler deploy root, so it writes
  # the generated index.html and media/ next to its source.
  launchd.agents.manabi-dashboard-refresh = {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.homeDirectory}/Developer/projects/manabi-dashboard/update-dashboard.sh"
      ];
      StartInterval = 900;
      # The deploy pulls from a sandbox user over ssh; letting it fire during login while
      # the rest of the stack is still coming up just logs a failure.
      RunAtLoad = false;
      StandardOutPath = "${config.home.homeDirectory}/Developer/projects/manabi-dashboard/refresh.log";
      StandardErrorPath = "${config.home.homeDirectory}/Developer/projects/manabi-dashboard/refresh.log";
    };
  };
  launchd.agents.comfyui = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/bash"
        "${config.home.homeDirectory}/Developer/github.com/comfyanonymous/ComfyUI/run-comfy.sh"
      ];
      WorkingDirectory = "${config.home.homeDirectory}/Developer/github.com/comfyanonymous/ComfyUI";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/comfyui.log";
      StandardErrorPath = "/tmp/comfyui.log";
    };
  };
}
