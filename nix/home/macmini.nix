{
  config,
  lib,
  pkgs,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  # AI スタックの実行資産は dotfiles を単一ソースに out-of-store symlink で配置。
  # mini 上での直編集がそのまま repo に反映される (nvim と同じ機構)。
  aiService = name: {
    "ai/bin/${name}".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/services/${name}";
  };
  aiWrapper = name: {
    ".local/bin/${name}".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/bin/${name}";
  };
in
{
  # macmini 固有レイヤー。ベースの CLI/zsh/XDG 一式は home/common.nix を
  # flake 側で合成して継承する (sops/age 鍵は持ち込まない)。
  # venv / モデル / データ (~/ai/{venvs,models,data,apps}) は再現不可能資産のため
  # imperative 管理 (再構築手順は configs/macmini/bootstrap.sh と README)。

  home.packages = [
    # ccm: mac mini での Claude Code 既定起動形。
    # Remote Control(名前 dotfiles) + 直前会話の継続 + 全許可スキップ(YOLO) +
    # ~/.dotfiles へのアクセス許可。claude 本体は上書きしない (auth/update/agents を壊さない)。
    # 注意: --dangerously-skip-permissions は NOPASSWD sudo と併用で root まで無 gate。
    (pkgs.writeShellScriptBin "ccm" ''
      exec "$HOME/.local/bin/claude" \
        --remote-control dotfiles \
        --continue \
        --dangerously-skip-permissions \
        --add-dir "$HOME/.dotfiles" \
        "$@"
    '')
  ];

  # brew shellenv (headless mini は home/darwin.nix を積まないためここで) +
  # 機械ローカル秘密 (HF_TOKEN 等) は nix 管理外の local.zsh から読む。
  programs.zsh.initContent = lib.mkAfter ''
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    [ -f "$HOME/.config/zsh/local.zsh" ] && source "$HOME/.config/zsh/local.zsh"
  '';

  # AI スタック実行資産 (実体は configs/macmini/{services,bin})
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

  # AI スタック常駐 (旧 net.gapul.* の手書き plist を置換。2026-07-19)
  launchd.agents.ai-stack = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/bash"
        "${config.home.homeDirectory}/ai/bin/ai-stack.sh"
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
        "${config.home.homeDirectory}/ai/apps/ComfyUI/run-comfy.sh"
      ];
      WorkingDirectory = "${config.home.homeDirectory}/ai/apps/ComfyUI";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/comfyui.log";
      StandardErrorPath = "/tmp/comfyui.log";
    };
  };
}
