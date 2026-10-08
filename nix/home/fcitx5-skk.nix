{ config, ... }:
# The user half of SKK on the NixOS laptop (fcitx5-skk, on libskk); the IM framework, the addon
# and the input method group are system-side in hosts/nixos-laptop.nix. It is the Linux side of
# what macSKK does on the mac (configs/ime/skk/README.md): the same public dictionaries, and the
# same punctuation as skkeleton.
let
  skkDir = "${config.xdg.dataHome}/skk";
in
{
  # The dictionaries are the copies modules/home/editor.nix already puts in ~/.local/share/skk for
  # skkeleton, so the editor and the IM convert from one set. Without this file fcitx5-skk reads the
  # package's list, which has SKK-JISYO.L alone. The user dictionary stays under fcitx5's config
  # dir, where it learns; it is not shared with skkeleton-user-dict (a different format).
  xdg.dataFile = {
    "fcitx5/skk/dictionary_list".text = ''
      type=file,file=$FCITX_CONFIG_DIR/skk/user.dict,mode=readwrite
      type=file,file=${skkDir}/SKK-JISYO.L,mode=readonly
      type=file,file=${skkDir}/SKK-JISYO.jinmei,mode=readonly
      type=file,file=${skkDir}/SKK-JISYO.geo,mode=readonly
      type=file,file=${skkDir}/SKK-JISYO.propernoun,mode=readonly
      type=file,file=${skkDir}/SKK-JISYO.station,mode=readonly
    '';
  };

  # A libskk rule ("gapul") that is the default one plus a full-width ！, matching skkeleton and
  # configs/ime/skk/kana-rule.conf. libskk's default already widens ？ and ：, and leaves （） half
  # width, so ！ is the only difference. libskk wants every keymap of a rule present, so each one
  # only includes the default's. User rules are looked up under the config dir, not the data dir.
  xdg.configFile = (
    let
      rules = "libskk/rules/gapul";
      include = file: builtins.toJSON { include = [ "default/${file}" ]; };
    in
    {
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
    // builtins.listToAttrs (
      map
        (mode: {
          name = "${rules}/keymap/${mode}.json";
          value.text = include mode;
        })
        [
          "default"
          "hankaku-katakana"
          "hiragana"
          "katakana"
          "latin"
          "wide-latin"
        ]
    )
  );
}
