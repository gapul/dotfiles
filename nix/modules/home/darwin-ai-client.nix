# AI client component (ECS: profile, darwin workstation only).
# Client wrappers that ship work off to the mac mini AI node over ssh (transcribe / tts / ocr ...).
# The mini-side bodies live in configs/macmini/bin and are declared in home/macmini.nix; these are
# the 母艦 side of the same pair, and used to sit in ~/.local/bin as untracked files.
# Out-of-store symlinks, so editing them in place lands straight in the repo (same as nvim).
{
  config,
  lib,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  client = name: {
    ".local/bin/${name}".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/client/${name}";
  };
in
{
  home.file = lib.mkMerge (
    map client [
      "ask"
      "describe"
      "ocr"
      "separate"
      "transcribe"
      "transcribe-diarize"
      "tts"
      "voice-clone"
    ]
    ++ [
      # Generic agent notifier: Claude Code / Codex hooks call it by absolute path, so it is not
      # macmini-specific and keeps its ~/.local/bin location.
      {
        ".local/bin/agent-notify".source =
          config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/cli/bin/agent-notify";
      }
    ]
  );
}
