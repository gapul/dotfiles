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
  #   app data -> ~/.local/share/{anythingllm,open-webui,minecraft}/
  #   ComfyUI / GPT-SoVITS -> ~/Developer/github.com/<owner>/<repo> (ghq style)
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
  ];

  # brew shellenv (here because the headless mini doesn't load home/darwin.nix) +
  # machine-local secrets (HF_TOKEN etc.) are read from local.zsh outside nix management.
  programs.zsh.initContent = lib.mkAfter ''
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    [ -f "$HOME/.config/zsh/local.zsh" ] && source "$HOME/.config/zsh/local.zsh"
  '';

  # AI stack runtime assets (bodies in configs/macmini/{services,bin})
  home.file = lib.mkMerge (
    map aiService [
      "ai-stack.sh"
      "ai_panel.py"
      "container_proxy.sh"
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
