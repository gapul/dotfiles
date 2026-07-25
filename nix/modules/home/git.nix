# Git component (ECS: profile)。git 本体 + delta(diff pager)。
# common.nix から切り出した最初のコンポーネント。home 各構成はこれを import して合成する。
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
    ignores = [
      # macOS が各フォルダに撒くメタデータ (ノイズ。リポジトリに不要)
      ".DS_Store"
      ".DS_Store?"
      "._*" # AppleDouble (リソースフォーク)
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
      # LaTeX ビルド中間生成物 (latexmk / lualatex)
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
    # HM 26.05: userName/userEmail/extraConfig は settings.* に統合
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
      # flake.lock 自動解決 driver (.gitattributes の `nix/flake.lock merge=flakelock`)。
      # Mac/Lab PC 両機の nix flake update 競合を、片側採用(常に valid な lock)で無人解決。
      # 入力差を厳密に揃えたい時は解決後 `nix flake update` を一度回す。
      merge.flakelock.name = "flake.lock auto-resolve";
      merge.flakelock.driver = "cp -f %B %A";
      diff.colorMoved = "default";
      gpg.format = "ssh";
      "gpg \"ssh\"".allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
      "gpg \"ssh\"".program = "${config.home.homeDirectory}/.dotfiles/scripts/git-ssh-keygen-bitwarden";
    };
  };

  # HM 26.05: programs.git.delta → 独立した programs.delta へ移行
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
      detect-dark-light = "auto"; # 端末の明暗を検出し diff 配色を macOS 外観に追従
    };
  };
}
