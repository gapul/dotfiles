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
      # Secure Enclave key: non-extractable, Touch ID per signature. Signing now costs a
      # deliberate physical gesture, which is the point — a commit cannot be signed in your name
      # by anything running unattended on this machine.
      key = "${config.home.homeDirectory}/.ssh/id_enclave_key.pub";
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

      "gpg \"ssh\"".program = "${config.home.homeDirectory}/.dotfiles/scripts/git-ssh-keygen-enclave";
    };
  };

  # The allowed signers list was hand-placed at ~/.ssh/allowed_signers, i.e. the one input to
  # signature verification lived outside the declaration. Both the old Bitwarden key and the new
  # Secure Enclave key are listed so commits from either era still verify.
  home.file.".ssh/allowed_signers".source = ../../keys/allowed_signers;

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
