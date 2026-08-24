# Git component (ECS: profile). git itself + delta (diff pager).
# The first component split out from common.nix. Each home config imports and composes this.
{
  config,
  pkgs,
  lib,
  user,
  ...
}:
{
  programs.git = {
    enable = true;
    lfs.enable = true; # Git LFS (large binary assets, e.g. Unreal *.uasset/*.umap)
    ignores = [
      # Metadata macOS scatters into every folder (noise; not needed in repos)
      ".DS_Store"
      ".DS_Store?"
      "._*" # AppleDouble (resource fork)
      ".AppleDouble"
      ".LSOverride"
      ".Spotlight-V100"
      ".Trashes"
      ".fseventsd"
      ".DocumentRevisions-V100"
      ".TemporaryItems"
      ".VolumeIcon.icns"
      ".com.apple.timemachine.donotpresent"
      ".apdisk"
      "Thumbs.db" # Windows
      ".idea/"
      ".vscode/"
      "*.swp"
      "*.swo"
      ".direnv/"
      "result"
      "result-*"
      ".envrc.local"
      ".claude/settings.local.json"
      # LaTeX build intermediates (latexmk / lualatex)
      "*.aux"
      "*.fdb_latexmk"
      "*.fls"
      "*.log"
      "*.out"
      "*.toc"
      "*.synctex.gz"
      "*.bbl"
      "*.bcf"
      "*.run.xml"
      "*.nav"
      "*.snm"
      "*.vrb"
    ];
    signing = {
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    # HM 26.05: userName/userEmail/extraConfig merged into settings.*
    settings = {
      user.name = user.gitUser;
      user.email = user.gitEmail;
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      ghq.root = "${config.home.homeDirectory}/Developer";
      wt.basedir = "../{gitroot}-worktrees";
      wt.remover = lib.getExe pkgs.trash-cli;
      merge.conflictstyle = "zdiff3";
      commit.verbose = true;
      diff.algorithm = "histogram";
      fetch.prune = true;
      fetch.writeCommitGraph = true;
      rebase.autoStash = true;
      rebase.autoSquash = true;
      rebase.updateRefs = true;
      rerere.enabled = true;
      rerere.autoupdate = true;
      # flake.lock auto-resolve driver (`nix/flake.lock merge=flakelock` in .gitattributes).
      # Unattended resolution of nix flake update conflicts between Mac/Lab PC by taking one side (always a valid lock).
      # When you want to align input diffs exactly, run `nix flake update` once after resolution.
      merge.flakelock.name = "flake.lock auto-resolve";
      merge.flakelock.driver = "cp -f %B %A";
      diff.colorMoved = "default";
      gpg.format = "ssh";
      "gpg \"ssh\"".allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
      "gpg \"ssh\"".program = "${config.home.homeDirectory}/.dotfiles/scripts/git-ssh-keygen-bitwarden";
    };
  };

  # HM 26.05: programs.git.delta → migrated to standalone programs.delta
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
      detect-dark-light = "auto"; # detect terminal light/dark and follow macOS appearance for diff colors
    };
  };
}
