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

  # Both layers count as "the nix side": GUI apps sit in environment.systemPackages so their
  # bundles land in /Applications, everything else in home.packages. A check that read only one
  # of them would let a package dodge the nix-vs-homebrew duplication rule by moving layers.
  packageNames = map lib.getName (home.home.packages ++ darwin.environment.systemPackages);
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

  # Claude Code: リモートへ配る管理キーの値は、母艦の settings.json が実際に持っている値と
  # 一致していなければならない (configs/cli/claude/README.md の「クライアント端末が正」)。
  # 母艦に無いキーを配ると「母艦は既定値・リモートだけ明示値」という食い違いが生まれる。
  # 2026-08-13 に tui / inputNeededNotifEnabled / agentPushNotifEnabled をリモート側の値から
  # 起こして一度破っているので、目視ではなくここで縛る。
  claudeWorkstation = builtins.fromJSON (builtins.readFile ../../configs/cli/claude/settings.json);
  claudeManaged = builtins.fromJSON (builtins.readFile ../../configs/cli/claude/settings.remote.json);
  # 管理ファイルの構造をなぞり、母艦と食い違う葉のパスを集める。両側が attrset の
  # ときだけ潜るのは merge-claude-settings.py の deep_merge と同じ約束
  # (permissions は defaultMode だけを管理し、allow は母艦にもリモートにも触らせない)。
  claudeDrift =
    managed: source: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: value:
        let
          path = prefix + name;
        in
        if name == "$schema" then
          [ ]
        else if !(source ? ${name}) then
          [ "${path} (母艦の settings.json に無い)" ]
        else if builtins.isAttrs value && builtins.isAttrs source.${name} then
          claudeDrift value source.${name} "${path}."
        else if value != source.${name} then
          [ path ]
        else
          [ ]
      ) managed
    );
  claudeDrifted = claudeDrift claudeManaged claudeWorkstation "";
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
assert lib.assertMsg (claudeDrifted == [ ])
  "claude: settings.remote.json の管理キーは母艦の settings.json と一致していること (README の「クライアント端末が正」) — ${lib.concatStringsSep ", " claudeDrifted}";
pkgs.runCommand "dotfiles-config-invariants" { } ''
  touch "$out"
''
