{
  config,
  lib,
  pkgs,
  ...
}:
let
  c = import ../lib/theme.nix;
  colors = [
    "base"
    "surface"
    "overlay"
    "muted"
    "subtle"
    "text"
    "love"
    "gold"
    "rose"
    "pine"
    "foam"
    "iris"
    "hlMed"
  ];
  basePaths = [
    "wofi/style.css"
    "wlogout/style.css"
    "mako/config"
    "hypr/hyprlock.conf"
    "wlr-which-key/config.yaml"
    "gtk-3.0/gtk.css"
    "gtk-4.0/gtk.css"
    "gtk-3.0/settings.ini"
    "gtk-4.0/settings.ini"
  ];
  # Stylix installs these through one recursive directory entry, not separate files.
  qtPaths = [
    "Kvantum/Base16Kvantum/Base16Kvantum.kvconfig"
    "Kvantum/Base16Kvantum/Base16Kvantum.svg"
  ];
  paths = basePaths ++ qtPaths;
  sources = pkgs.writeText "desktop-appearance-sources.json" (
    builtins.toJSON (
      lib.genAttrs paths (
        path:
        if builtins.elem path qtPaths then
          "${config.xdg.configFile.Kvantum.source}/${lib.removePrefix "Kvantum/" path}"
        else
          toString config.xdg.configFile.${path}.source
      )
    )
  );
  wallpaper =
    name: palette:
    import ../lib/wallpaper.nix {
      inherit pkgs name;
      p = palette;
    };
  powerIcons =
    palette:
    pkgs.runCommand "power-menu-icons-${palette.variant}"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        mkdir -p "$out"
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList
            (
              name: cp:
              "magick -background none -fill '#${palette.text}' -font ${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf -pointsize 320 label:\"$(LC_ALL=C.UTF-8 printf '\\U000${cp}')\" -trim +repage -gravity center -extent 400x400 PNG32:$out/${name}.png"
            )
            {
              lock = "f033e";
              suspend = "f04b2";
              logout = "f0343";
              reboot = "f0709";
              shutdown = "f0425";
              hibernate = "f02ca";
            }
        )}
      '';
  bundle =
    mode: palette:
    pkgs.runCommand "desktop-appearance-${mode}"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        mapping = builtins.toJSON (
          lib.listToAttrs (
            map (name: {
              name = c.${name};
              value = palette.${name};
            }) colors
          )
        );
        inherit mode;
        icons = powerIcons palette;
        oldWallpaper = wallpaper "rose-pine" c.dark;
        newWallpaper = wallpaper (if mode == "light" then "rose-pine-dawn" else "rose-pine") palette;
      }
      ''
        python3 - ${sources} <<'PYTHON'
        import json, os, pathlib, re, sys
        sources = json.loads(pathlib.Path(sys.argv[1]).read_text())
        mapping = json.loads(os.environ["mapping"])
        pattern = re.compile(r"(?<=[#(])(?:" + "|".join(mapping) + r")(?=[0-9a-fA-F]{0,2}[^0-9a-fA-F]|$)", re.I)
        for name, source in sources.items():
            text = pathlib.Path(source).read_text()
            text = pattern.sub(lambda m: mapping[m.group().lower()], text)
            # Kvantum paints only the window background with alpha; glyphs stay opaque.
            if name == "Kvantum/Base16Kvantum/Base16Kvantum.kvconfig":
                for key, value in {"translucent_windows": "true", "reduce_window_opacity": "16", "blurring": "true"}.items():
                    text, count = re.subn(r"(?m)^" + key + r"=.*$", key + "=" + value, text)
                    assert count == 1, (name, key, count)
            if name == "wlogout/style.css":
                text = re.sub(r'/nix/store/[^"\s]+/(lock|suspend|logout|reboot|shutdown|hibernate)\.png', lambda m: os.environ["icons"] + "/" + m.group(1) + ".png", text)
            if name.endswith("settings.ini"):
                text = re.sub(r"gtk-icon-theme-name=.*", "gtk-icon-theme-name=" + ("Papirus" if os.environ["mode"] == "light" else "Papirus-Dark"), text)
                text = re.sub(r"gtk-theme-name=.*", "gtk-theme-name=" + ("adw-gtk3" if os.environ["mode"] == "light" else "adw-gtk3-dark"), text)
            if name == "hypr/hyprlock.conf":
                text = text.replace(os.environ["oldWallpaper"], os.environ["newWallpaper"])
                if os.environ["mode"] == "light":
                    text = text.replace("brightness=0.7", "brightness=1.0")
            target = pathlib.Path(os.environ["out"], name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        PYTHON
        cat > "$out/hypr-colors.conf" <<'EOF'
        general:col.active_border = rgb(${palette.iris}) rgb(${palette.foam}) 45deg
        general:col.inactive_border = rgb(${palette.overlay})
        misc:background_color = rgb(${palette.base})
        EOF
      '';
  stateDir = "${config.xdg.stateHome}/desktop-appearance";
  apply = pkgs.writeShellApplication {
    name = "desktop-appearance";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.darkman
      pkgs.dconf
      pkgs.systemd
    ];
    text = ''
      mode="''${1:-$(darkman get 2>/dev/null || echo dark)}"
      case "$mode" in
        light) theme=${bundle "light" c.light}; gtk=adw-gtk3; icons=Papirus ;;
        dark) theme=${bundle "dark" c.dark}; gtk=adw-gtk3-dark; icons=Papirus-Dark ;;
        *) echo "usage: desktop-appearance [light|dark]" >&2; exit 2 ;;
      esac
      mkdir -p ${lib.escapeShellArg stateDir}
      ln -sfn "$theme" ${lib.escapeShellArg "${stateDir}/current"}
      ${lib.concatMapStringsSep "\n" (path: ''
        mkdir -p ${lib.escapeShellArg "${config.xdg.configHome}/${builtins.dirOf path}"}
        ln -sfn "$theme/${path}" ${lib.escapeShellArg "${config.xdg.configHome}/${path}"}
      '') paths}
      dconf write /org/gnome/desktop/interface/gtk-theme "'$gtk'"
      dconf write /org/gnome/desktop/interface/icon-theme "'$icons'"
      if systemctl --user is-active --quiet mako.service; then
        ${pkgs.mako}/bin/makoctl reload
      fi
      if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        # The Lua config reads current/hypr-colors.conf (see extraConfig below).
        hyprctl reload >/dev/null
      fi
    '';
  };
in
{
  # These are already HM-generated files. Runtime colour selection changes their
  # symlink targets, so let the next activation restore its source snapshots
  # before desktopAppearance selects the current mode again.
  xdg.configFile =
    lib.genAttrs basePaths (_: {
      force = true;
    })
    // {
      Kvantum.force = true;
    };
  home.packages = [ apply ];
  services.darkman.lightModeScripts.desktop = "${lib.getExe apply} light";
  services.darkman.darkModeScripts.desktop = "${lib.getExe apply} dark";
  home.activation.desktopAppearance = config.lib.dag.entryAfter [ "reloadSystemd" ] ''
    run ${lib.getExe apply}
  '';
  # Reloading Hyprland should retain the currently selected border colours. The Lua config
  # has no `source`, so the three "section:key = value" lines of hypr-colors.conf are read
  # here and applied with hl.config (a value of several colours and an "Ndeg" is a gradient).
  wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
    do
      local f = io.open("${stateDir}/current/hypr-colors.conf")
      if f then
        local function value(raw)
          local colors, angle = {}, nil
          for token in raw:gmatch("%S+") do
            local deg = token:match("^(%d+)deg$")
            if deg then angle = tonumber(deg) else colors[#colors + 1] = token end
          end
          if #colors == 1 and not angle then return colors[1] end
          return { colors = colors, angle = angle or 0 }
        end
        local general, misc = {}, {}
        for line in f:lines() do
          local k, v = line:match("^%s*([%w_:%.]+)%s*=%s*(.-)%s*$")
          if k == "general:col.active_border" then general.col = general.col or {}; general.col.active_border = value(v)
          elseif k == "general:col.inactive_border" then general.col = general.col or {}; general.col.inactive_border = value(v)
          elseif k == "misc:background_color" then misc.background_color = v
          end
        end
        f:close()
        hl.config({ general = general, misc = misc })
      end
    end
  '';
}
