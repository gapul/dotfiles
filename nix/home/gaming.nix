{
  lib,
  pkgs,
  osConfig,
  ...
}:
# Non-Steam game launchers and the overlay they share (nixos-laptop only, via home/linux-gui.nix).
# Steam itself is system-side (programs.steam in hosts/nixos-laptop.nix) because it needs the
# 32-bit graphics stack. Heroic stays a plain package in linux-gui.nix: home-manager has no module
# for it, and it rewrites its own config.json, Wine/Proton downloads included (~/.config/heroic/tools).
{
  # Minecraft. Instances, accounts and worlds stay mutable in ~/.local/share/PrismLauncher; only
  # the keys below are merged into prismlauncher.cfg on every switch (crudini --merge), so anything
  # set in the GUI that is not listed here survives.
  #
  # nixpkgs' wrapper already hands Prism its JDKs (8/17/21/25) through PRISMLAUNCHER_JAVA_PATHS, so
  # it switches between those per Minecraft version instead of downloading Mojang's/Azul's JREs,
  # which are dynamically linked and would only run through nix-ld. The two "asked"/"wizard" keys
  # keep the first-run wizard from offering the download anyway.
  programs.prismlauncher = {
    enable = true;
    settings = {
      AutomaticJavaSwitch = true;
      AutomaticJavaDownload = false;
      UserAskedAboutAutomaticJavaDownload = true;
      IgnoreJavaWizard = true;
      # 30 GB of RAM; leave plenty for the rest of the desktop while a modpack runs.
      MinMemAlloc = 512;
      MaxMemAlloc = 8192;
    };
  };

  # GOG / standalone installers / emulators. Runners declared here are not editable in Lutris'
  # GUI; game entries and their prefixes stay mutable. steamPackage has to be the system's Steam,
  # or Lutris starts a second instance that fights the first one.
  programs.lutris = {
    enable = true;
    # mkIf: the "safe" specialisation turns Steam off, and its package cannot be evaluated there.
    steamPackage = lib.mkIf osConfig.programs.steam.enable osConfig.programs.steam.package;
    winePackages = [ pkgs.wineWow64Packages.staging ];
    protonPackages = [ pkgs.proton-ge-bin ];
    defaultWinePackage = pkgs.proton-ge-bin;
    extraPackages = with pkgs; [
      winetricks
      mangohud
    ];
  };

  # FPS / frametime overlay. Not session-wide: enable it per game with `mangohud %command%` in
  # Steam's launch options, or Lutris' / Heroic's MangoHud toggle.
  programs.mangohud = {
    enable = true;
    settings = {
      position = "top-left";
      fps = true;
      frametime = true;
      cpu_temp = true;
      gpu_temp = true;
      ram = true;
      toggle_hud = "Shift_R+F12";
    };
  };
}
