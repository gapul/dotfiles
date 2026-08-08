{
  pkgs,
  lib,
  self,
  user,
}:
let
  home = self.homeConfigurations.${user.username}.config;
  wslHome = self.homeConfigurations."${user.username}-wsl".config;
  linuxHome = self.homeConfigurations."${user.username}-linux".config;
  darwin = self.darwinConfigurations.${user.username}.config;

  packageNames = map lib.getName home.home.packages;
  caskNames = map (cask: if builtins.isString cask then cask else cask.name) darwin.homebrew.casks;

  # Package manager priority (nix > homebrew): the same tool must not be declared on both sides.
  # /opt/homebrew/bin sits ahead of the nix profile outside zsh, so a duplicate silently resolves
  # to the brew copy and the nix declaration becomes a lie.
  # "felixkratz/formulae/sketchybar" -> "sketchybar"
  brewNames =
    darwinCfg:
    map (
      brew: lib.last (lib.splitString "/" (if builtins.isString brew then brew else brew.name))
    ) darwinCfg.homebrew.brews;
  duplicated = darwinCfg: pkgNames: lib.intersectLists (brewNames darwinCfg) pkgNames;
  # macmini has no standalone homeConfiguration: its home is embedded in the darwin config.
  macminiDarwin = self.darwinConfigurations.macmini.config;
  macminiPackageNames =
    map lib.getName
      macminiDarwin.home-manager.users.${user.username}.home.packages;
in
assert lib.assertMsg (duplicated darwin packageNames == [ ])
  "nix > homebrew: declared on both sides for the workstation — ${lib.concatStringsSep ", " (duplicated darwin packageNames)}";
assert lib.assertMsg (duplicated macminiDarwin macminiPackageNames == [ ])
  "nix > homebrew: declared on both sides for macmini — ${lib.concatStringsSep ", " (duplicated macminiDarwin macminiPackageNames)}";
assert lib.assertMsg (
  home.programs.git.settings.wt.basedir == "../{gitroot}-worktrees"
) "git-wt worktrees must live outside the repository";
assert lib.assertMsg (
  home.programs.git.settings.wt.remover == lib.getExe pkgs.trash-cli
) "git-wt must use trash-cli as its remover";
assert lib.assertMsg (builtins.elem "tirith" packageNames)
  "tirith must be installed in the workstation Home Manager profile";
assert lib.assertMsg (lib.hasInfix "tirith init --shell zsh" home.programs.zsh.initContent)
  "tirith must have an active zsh preexec hook";
assert lib.assertMsg (
  home.programs.bat.config.theme == "auto:system"
  && home.programs.bat.config.theme-dark == "rose-pine"
  && home.programs.bat.config.theme-light == "rose-pine-dawn"
) "bat must retain automatic dark/light theme selection";
assert lib.assertMsg (
  home.programs.agent-skills.enable
  && wslHome.programs.agent-skills.enable
  && linuxHome.programs.agent-skills.enable
) "agent-skills must remain enabled across Darwin, WSL, and Linux";
assert lib.assertMsg (
  builtins.elem "qview" packageNames && !(builtins.elem "qview" caskNames)
) "qView must be managed only by brew-nix, not duplicated in Homebrew";
assert lib.assertMsg
  (
    let
      inherit ((builtins.fromJSON (builtins.readFile ../../configs/theme/fonts.json))) mono;
      ghosttyCfg = builtins.readFile ../../configs/terminals/ghostty/config;
    in
    lib.hasInfix ''font-family = "${mono}"'' ghosttyCfg
  )
  "ghostty font-family must match configs/theme/fonts.json (mono) — static-copy consistency of the font SSO";
pkgs.runCommand "dotfiles-config-invariants" { } ''
  touch "$out"
''
