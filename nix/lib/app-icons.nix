{
  pkgs,
  desktopDirs,
  overrides,
  span,
}:
# Which app gets which sketchybar-app-font icon, worked out at build time instead of by hand.
# A window names its app by its Wayland app_id (or X11 class), which by convention is its
# .desktop file's name or StartupWMClass; the font carries its own map from app names to
# icons (the APPM table, the same data as upstream's icon_map.json). So for every installed
# .desktop file: its Name= (then its file name, the last part of a reverse-DNS file name, its
# StartupWMClass) is looked up in the font's map, and the icon is recorded under the file
# name and the StartupWMClass. Installing an app gives it its icon, and a font update brings
# new icons, with nothing to edit here.
#
# `overrides` (key -> icon) is for what the names cannot settle: a key is a .desktop file name
# (its icon then goes to all of that file's keys) or a bare app_id with no .desktop file.
# Two .desktop files giving one key different icons fails the build until an override
# decides it, so every key has exactly one icon.
#
# Out: icons.json, {"exact": {key: icon}, "lower": {lowercased key: icon}} for niri's
# workspace script, and waybar.json, the same as hyprland/workspaces' window-rewrite (for the
# bars' `include`), each icon wrapped in `span` ("{}" is the ligature).
let
  generate =
    pkgs.writers.writePython3 "app-icons"
      {
        libraries = [ pkgs.python3Packages.fonttools ];
        flakeIgnore = [ "E501" ];
      }
      ''
        import fnmatch
        import json
        import os
        import sys

        from fontTools.ttLib import TTFont

        font, overrides_file, span, out = sys.argv[1:5]
        dirs = sys.argv[5:]
        overrides = json.load(open(overrides_file))

        # The font's own map: [ligature, codepoint, [app names]]; names may be globs ("Adobe Bridge*").
        appm = json.loads(TTFont(font)["meta"].data["APPM"])
        exact, globs = {}, []
        for ligature, _, names in appm["icons"]:
            for name in names or []:
                if "*" in name:
                    globs.append((name.lower(), ligature))
                else:
                    exact.setdefault(name.lower(), ligature)


        def font_icon(name):
            name = name.lower()
            if name in exact:
                return exact[name]
            return next((lig for pattern, lig in globs if fnmatch.fnmatchcase(name, pattern)), None)


        def entry(path):
            fields, section = {}, None
            for line in open(path, encoding="utf-8", errors="replace"):
                line = line.strip()
                if line.startswith("["):
                    section = line
                elif section == "[Desktop Entry]" and "=" in line:
                    key, value = line.split("=", 1)
                    fields.setdefault(key.strip(), value.strip())
            return fields


        claims = {}  # key -> {icon: [.desktop files]}
        for d in dirs:
            if not os.path.isdir(d):
                continue
            for file in sorted(os.listdir(d)):
                if not file.endswith(".desktop"):
                    continue
                desktop_id = file.removesuffix(".desktop")
                fields = entry(os.path.join(d, file))
                wm_class = fields.get("StartupWMClass")
                icon = overrides.get(desktop_id)
                if icon is None:
                    candidates = [fields.get("Name"), desktop_id, desktop_id.rsplit(".", 1)[-1], wm_class]
                    icon = next((i for i in map(font_icon, filter(None, candidates)) if i), None)
                if icon is None:
                    continue
                for key in filter(None, {desktop_id, wm_class}):
                    claims.setdefault(key, {}).setdefault(icon, []).append(file)

        icons = dict(overrides)
        conflicts = []
        for key, by_icon in sorted(claims.items()):
            if key in overrides:
                continue
            if len(by_icon) > 1:
                conflicts.append(f"  {key}: " + ", ".join(f"{i} ({', '.join(f)})" for i, f in sorted(by_icon.items())))
                continue
            icons[key] = next(iter(by_icon))
        if conflicts:
            sys.exit("app-icons: keys with more than one icon; settle them in the overrides:\n" + "\n".join(conflicts))

        # Lowercased keys, for apps whose app_id differs from their .desktop name only in case
        # (zotero / Zotero); a lowercased key that would mean two icons is left out.
        lower = {}
        for key, icon in icons.items():
            lower.setdefault(key.lower(), set()).add(icon)
        lower = {k: v.pop() for k, v in lower.items() if len(v) == 1}


        def case_insensitive(key):
            # waybar's regexes (std::regex) take no flags: [zZ]otero, with the metacharacters escaped.
            return "".join(f"[{c.lower()}{c.upper()}]" if c.isalpha() else ("\\" + c if c in ".^$|?*+()[]{}\\" else c) for c in key)


        os.makedirs(out)
        with open(os.path.join(out, "icons.json"), "w") as f:
            json.dump({"exact": dict(sorted(icons.items())), "lower": dict(sorted(lower.items()))}, f, indent=2)
        rewrite = {f"class<^{case_insensitive(k)}$>": span.replace("{}", v) for k, v in sorted(lower.items())}
        with open(os.path.join(out, "waybar.json"), "w") as f:
            json.dump({"hyprland/workspaces": {"window-rewrite": rewrite}}, f, indent=2)
      '';
in
pkgs.runCommand "app-icons"
  {
    overrides = builtins.toJSON overrides;
    passAsFile = [ "overrides" ];
  }
  ''
    ${generate} ${pkgs.sketchybar-app-font}/share/fonts/truetype/sketchybar-app-font.ttf \
      "$overridesPath" ${pkgs.lib.escapeShellArg span} "$out" ${pkgs.lib.escapeShellArgs desktopDirs}
  ''
