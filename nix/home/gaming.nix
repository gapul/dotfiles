{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
  # ROM / decrypted-dump library, a receive-only Syncthing copy of homeserver's /srv/games/library
  # (homelab/syncthing.nix, folder "games-library"). Saves stay out of it: a receive-only folder
  # treats every file written locally as a deviation, and the next pull from homeserver is the
  # place a save would be lost.
  library = "${home}/Games/library";
  saves = "${home}/Games/saves";

  # Games Cartridges cannot find on its own: the emulators and Minecraft. Steam and Heroic it
  # imports by itself. Each entry becomes ~/.local/share/cartridges/games/imported_<id>.json,
  # the format of a game added by hand in its GUI. The id has to stay a number: Cartridges numbers
  # the next hand-added game as max(imported_N) + 1 and parses every imported_ id as an int.
  # Ids are fixed per game so play time and hidden state survive reordering the list.
  azahar = lib.getExe pkgs.azahar;
  melonds = lib.getExe pkgs.melonds;
  prism = lib.getExe config.programs.prismlauncher.package;
  # Reached over the tailnet (hosts/macmini.nix minecraftServers).
  minecraftHost = "100.105.135.49";
  # The servers carry server-side mods only, so a plain client of the same game version joins them.
  # The version is the servers' own pin, so this instance follows them when they update.
  minecraftVersion = (pkgs.callPackage ../pkgs/fabric-server.nix { }).mcVersion;
  minecraftInstance = "server";
  cartridgesGames = [
    {
      id = 9001;
      name = "ポケットモンスター X";
      exec = [
        azahar
        "${library}/3ds/pokemon-x.cci"
      ];
    }
    {
      id = 9002;
      name = "ポケットモンスター ムーン";
      exec = [
        azahar
        "${library}/3ds/pokemon-moon.cci"
      ];
    }
    {
      id = 9003;
      name = "ポケットモンスター ウルトラサン";
      exec = [
        azahar
        "${library}/3ds/pokemon-ultra-sun.cci"
      ];
    }
    {
      id = 9004;
      name = "ポケットモンスター クリスタル (VC)";
      exec = [
        azahar
        "${library}/3ds/pokemon-crystal-vc.cxi"
      ];
    }
    {
      id = 9005;
      name = "妖怪ウォッチ3 テンプラ";
      developer = "Level-5";
      exec = [
        azahar
        "${library}/3ds/yokai-watch-3-tempura.cci"
      ];
    }
    {
      id = 9101;
      name = "ポケットモンスター ブラック2";
      exec = [
        melonds
        "${library}/nds/pokemon-black-2.nds"
      ];
    }
    {
      id = 9102;
      name = "ポケットモンスター ハートゴールド";
      exec = [
        melonds
        "${library}/nds/pokemon-heartgold.nds"
      ];
    }
    {
      id = 9103;
      name = "ポケットモンスター プラチナ";
      exec = [
        melonds
        "${library}/nds/pokemon-platinum.nds"
      ];
    }
    # Prism instance "server" (declared below). Signing in to the Microsoft account once in Prism's
    # own window is what makes --launch work unattended.
    {
      id = 9202;
      name = "Minecraft 本館";
      developer = "Mojang";
      exec = [
        prism
        "--launch"
        minecraftInstance
        "--server"
        "${minecraftHost}:25565"
      ];
    }
    {
      id = 9203;
      name = "Minecraft solo";
      developer = "Mojang";
      exec = [
        prism
        "--launch"
        minecraftInstance
        "--server"
        "${minecraftHost}:25566"
      ];
    }
  ];
  cartridgesGamesJson = pkgs.writeText "cartridges-games.json" (
    builtins.toJSON (
      map (g: {
        game_id = "imported_${toString g.id}";
        source = "imported";
        inherit (g) name;
        developer = g.developer or (if lib.hasPrefix "ポケットモンスター" g.name then "Game Freak" else null);
        # Cartridges runs this through /bin/sh -c.
        executable = lib.escapeShellArgs g.exec;
        # Undo a "Remove" from the GUI: Cartridges deletes a removed game's file on its next start,
        # and this list is what decides which games exist.
        removed = false;
        # SPEC_VERSION in cartridges/shared.py; a file from a newer spec is ignored.
        version = 1.5;
      }) cartridgesGames
    )
  );
in
# Non-Steam game launchers, the Minecraft client and the overlay they share (nixos-laptop only, via home/linux-gui.nix).
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

  # The client instance for the macmini servers: vanilla at the servers' game version. Only the
  # game version is declared; Prism resolves LWJGL and the rest on first launch. When the servers
  # move to a new version the whole mmc-pack.json is rewritten, so no component resolved for the
  # old version is left behind. Worlds, options and anything else in the instance stay mutable.
  home.activation.prismServerInstance =
    let
      dir = "${config.xdg.dataHome}/PrismLauncher/instances/${minecraftInstance}";
      instanceCfg = pkgs.writeText "instance.cfg" ''
        [General]
        ConfigVersion=1.3
        InstanceType=OneSix
        iconKey=grass
        name=Minecraft (macmini)
      '';
      mmcPack = pkgs.writeText "mmc-pack.json" (
        builtins.toJSON {
          formatVersion = 1;
          components = [
            {
              uid = "net.minecraft";
              version = minecraftVersion;
              important = true;
            }
          ];
        }
      );
      jq = lib.getExe pkgs.jq;
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${dir}"
      if [ ! -f "${dir}/instance.cfg" ]; then
        run install -m 644 ${instanceCfg} "${dir}/instance.cfg"
      fi
      current=$(${jq} -r '.components[]? | select(.uid == "net.minecraft") | .version' "${dir}/mmc-pack.json" 2>/dev/null || true)
      if [ "$current" != ${lib.escapeShellArg minecraftVersion} ]; then
        run install -m 644 ${mmcPack} "${dir}/mmc-pack.json"
      fi
    '';

  # Write the declared games into Cartridges' library. Declared keys overwrite; what Cartridges
  # keeps for itself (added, last_played, hidden) is left alone. Games dropped from the list are
  # deleted, but only ones this activation wrote, recorded in nix-managed.
  home.activation.cartridgesGames = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dir="${home}/.local/share/cartridges/games"
    manifest="${home}/.local/share/cartridges/nix-managed"
    jq=${lib.getExe pkgs.jq}
    run mkdir -p "$dir"
    if [ -f "$manifest" ]; then
      while read -r id; do
        if ! "$jq" -e --arg id "$id" 'any(.[]; .game_id == $id)' ${cartridgesGamesJson} >/dev/null; then
          run rm -f "$dir/$id.json"
        fi
      done <"$manifest"
    fi
    now=$(date +%s)
    "$jq" -c '.[]' ${cartridgesGamesJson} | while read -r game; do
      f="$dir/$("$jq" -r .game_id <<<"$game").json"
      if [ -f "$f" ] && "$jq" -e . "$f" >/dev/null 2>&1; then
        new=$("$jq" --argjson d "$game" '. + $d' "$f")
      else
        new=$("$jq" -n --argjson d "$game" --argjson now "$now" \
          '{added: $now, last_played: 0, hidden: false, blacklisted: false} + $d')
      fi
      if [[ ! -v DRY_RUN ]]; then printf '%s\n' "$new" >"$f"; fi
    done
    if [[ ! -v DRY_RUN ]]; then "$jq" -r '.[].game_id' ${cartridgesGamesJson} >"$manifest"; fi
  '';

  # melonDS writes a game's save next to the ROM by default, which would be inside the receive-only
  # library. Point it at ~/Games/saves/nds instead; only this key is merged into melonDS.toml, the
  # rest of the file is melonDS' own.
  home.activation.melondsSavePath =
    let
      python = pkgs.python3.withPackages (p: [ p.tomli-w ]);
      merge = pkgs.writeText "melonds-merge.py" ''
        import os, sys, tomllib, tomli_w
        path, saves = sys.argv[1], sys.argv[2]
        cfg = {}
        if os.path.exists(path):
            with open(path, "rb") as f:
                cfg = tomllib.load(f)
        if cfg.get("Instance0", {}).get("SaveFilePath") != saves:
            cfg.setdefault("Instance0", {})["SaveFilePath"] = saves
            with open(path, "wb") as f:
                tomli_w.dump(cfg, f)
      '';
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${saves}/nds" "${config.xdg.configHome}/melonDS"
      run ${python}/bin/python3 -I ${merge} "${config.xdg.configHome}/melonDS/melonDS.toml" "${saves}/nds"
    '';

  # FPS / frametime overlay. Not session-wide: enable it per game with `mangohud %command%` in
  # Steam's launch options, or Heroic's MangoHud toggle.
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
