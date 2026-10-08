{
  config,
  lib,
  pkgs,
  ...
}:
# The user half of SKK on the NixOS laptop (fcitx5-skk, on libskk); the IM framework, the addon and
# its options (taken from macSKK's) are system-side in hosts/nixos-laptop.nix. It is the Linux side
# of what macSKK does on the mac (configs/ime/skk/README.md): the same public dictionaries, and the
# same punctuation as skkeleton.
let
  skkDir = "${config.xdg.dataHome}/skk";
  rules = "libskk/rules/gapul";
in
{
  # SKK is the only input method, as macSKK is on the mac: it is always on, and its own modes do
  # the switching (C-j hiragana, l latin, q katakana, L wide latin), the same keys as skkeleton.
  # Item 0 is what fcitx5 uses when "inactive", so with SKK there it never falls back to a plain
  # keyboard, and there is no separate on/off toggle to keep track of.
  #
  # This lives here rather than in i18n.inputMethod.fcitx5.settings (/etc/xdg) because fcitx5
  # writes its in-memory profile back to ~/.config/fcitx5/profile on every exit, and that copy
  # shadows the system one from then on, which is how a changed group never took effect. force
  # takes the file back on each switch (fcitx5's save replaces the link with a plain file), and
  # the running daemon reloads it, so what it saves on its next exit is this profile again.
  # (ignoreUserConfig would avoid all this, but it also stops SKK's user dictionary from saving.)
  xdg.configFile = {
    "fcitx5/profile" = {
      force = true;
      text = lib.generators.toINI { } {
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "skk";
        };
        "Groups/0/Items/0".Name = "skk";
        GroupOrder."0" = "Default";
      };
      onChange = ''
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
          ${pkgs.fcitx5}/bin/fcitx5-remote -r 2>/dev/null || true
      '';
    };

    # A libskk rule ("gapul") that is the default one plus a full-width ！, matching skkeleton and
    # configs/ime/skk/kana-rule.conf. libskk's default already widens ？ and ：, and leaves （） half
    # width, so ！ is the only difference. libskk wants every keymap of a rule present, so each one
    # only includes the default's. User rules are looked up under the config dir, not the data dir.
    "${rules}/metadata.json".text = builtins.toJSON {
      name = "gapul";
      description = "Default, with a full-width ！ (as skkeleton / macSKK)";
    };
    "${rules}/rom-kana/default.json".text = builtins.toJSON {
      include = [ "default/default" ];
      define.rom-kana."!" = [
        ""
        "！"
      ];
    };
  }
  // lib.listToAttrs (
    map
      (
        mode:
        lib.nameValuePair "${rules}/keymap/${mode}.json" {
          text = builtins.toJSON { include = [ "default/${mode}" ]; };
        }
      )
      [
        "default"
        "hankaku-katakana"
        "hiragana"
        "katakana"
        "latin"
        "wide-latin"
      ]
  );

  # The dictionaries are the copies modules/home/editor.nix already puts in ~/.local/share/skk for
  # skkeleton, so the editor and the IM convert from one set, in the order of macSKK's
  # dictionaries[]. Without this file fcitx5-skk reads the package's list, which has SKK-JISYO.L
  # alone. $FCITX_CONFIG_DIR is fcitx5's data dir, so the user dictionary, where conversions are
  # learned, ends up at ~/.local/share/fcitx5/skk/user.dict; it is not shared with skkeleton-user-dict.
  xdg.dataFile."fcitx5/skk/dictionary_list".text = ''
    type=file,file=$FCITX_CONFIG_DIR/skk/user.dict,mode=readwrite
    type=file,file=${skkDir}/SKK-JISYO.L,mode=readonly
    type=file,file=${skkDir}/SKK-JISYO.geo,mode=readonly
    type=file,file=${skkDir}/SKK-JISYO.jinmei,mode=readonly
    type=file,file=${skkDir}/SKK-JISYO.propernoun,mode=readonly
    type=file,file=${skkDir}/SKK-JISYO.station,mode=readonly
  '';
}
