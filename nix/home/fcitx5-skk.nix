{
  config,
  lib,
  pkgs,
  ...
}:
# The user half of SKK on the NixOS laptop (fcitx5-skk, on libskk); the IM framework, the addon and
# its options (taken from macSKK's) are system-side in hosts/nixos-laptop.nix. It is the Linux side
# of what macSKK does on the mac (configs/ime/skk/README.md): the same public dictionaries, and the
# same punctuation as skkeleton, and the azooKey skkserv on 127.0.0.1:1178 (see below).
let
  skkDir = "${config.xdg.dataHome}/skk";
  azooKeySkkserv = pkgs.callPackage ../pkgs/azoo-key-skkserv.nix { };
  skkservPort = 1178;
  rules = "libskk/rules/gapul";
  kanaModes = [
    "hiragana"
    "katakana"
    "hankaku-katakana"
  ];
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
    # width, so ！ is the only punctuation that differs. libskk wants every keymap of a rule present, so each one
    # only includes the default's. User rules are looked up under the config dir, not the data dir.
    "${rules}/metadata.json".text = builtins.toJSON {
      name = "gapul";
      description = "Default, with a full-width ！ and ; as sticky shift";
    };
    # ; is a sticky shift: ;kanzi starts ▽かんじ, and inside ▽ it marks where the okurigana begins
    # (;ka;ku → ▽か*く), so no chord with Shift is needed. macSKK and skkeleton both do this out of
    # the box; libskk does not, but its start-preedit-no-delete is exactly that. Its rom-kana entry
    # (; → ；) is dropped so the keymap gets the key.
    "${rules}/rom-kana/default.json".text = builtins.toJSON {
      include = [ "default/default" ];
      define.rom-kana = {
        "!" = [
          ""
          "！"
        ];
        ";" = null;
        # libskk's default turns \ into its kuten (JIS code point) prompt, "Kuten([MM]KKTT)". On this
        # board the ¥ key is backslash (home/xremap.nix), so a stray ¥ dropped the user into a mode
        # nothing else uses; without the entry the key is just a backslash.
        "\\" = null;
      };
    };
  }
  // lib.listToAttrs (
    map
      (
        mode:
        lib.nameValuePair "${rules}/keymap/${mode}.json" {
          text = builtins.toJSON (
            {
              include = [ "default/${mode}" ];
            }
            // lib.optionalAttrs (lib.elem mode kanaModes) {
              # Not start-preedit-kana: from the plain state that one takes the app's surrounding
              # text, cuts everything after the cursor, and appends it again on commit (libskk
              # state.vala). Over Wayland's text-input the app (Obsidian, Chromium) never deletes
              # that text, so each commit after a ; duplicated the rest of the note, starting with
              # the line break after the cursor, which looked like C-j inserting a newline. Inside
              # ▽ both commands mark the okurigana the same way.
              define.keymap.";" = "start-preedit-no-delete";
            }
          );
        }
      )
      (
        [
          "default"
          "latin"
          "wide-latin"
        ]
        ++ kanaModes
      )
  );

  # The dictionaries are the copies modules/home/editor.nix already puts in ~/.local/share/skk for
  # skkeleton, so the editor and the IM convert from one set, in the order of macSKK's
  # dictionaries[], except that the skkserv comes first (see below).
  # Without this file fcitx5-skk reads the package's list, which has SKK-JISYO.L
  # alone. $FCITX_CONFIG_DIR is fcitx5's data dir, so the user dictionary, where conversions are
  # learned, ends up at ~/.local/share/fcitx5/skk/user.dict; it is not shared with skkeleton-user-dict.
  xdg.dataFile."fcitx5/skk/dictionary_list".text = ''
    type=server,host=127.0.0.1,port=${toString skkservPort},encoding=UTF-8,context=true
    type=file,file=$FCITX_CONFIG_DIR/skk/user.dict,mode=readwrite
    type=file,file=${skkDir}/SKK-JISYO.L,mode=readonly
    type=file,file=${skkDir}/SKK-JISYO.geo,mode=readonly
    type=file,file=${skkDir}/SKK-JISYO.jinmei,mode=readonly
    type=file,file=${skkDir}/SKK-JISYO.propernoun,mode=readonly
    type=file,file=${skkDir}/SKK-JISYO.station,mode=readonly
  '';

  # azoo-key-skkserv, the skkserv macSKK and skkeleton use on the mac (azooKey skkserv.app there):
  # AzooKeyKanaKanjiConverter with the Zenzai model, so compounds and whole phrases the SKK-JISYO
  # files lack still convert (はいたつぎょうしゃ → 配達業者). libskk lists the candidates of each
  # dictionary in turn and drops the later duplicates, so the server comes first: after the
  # SKK-JISYO files its context order (below) would show only for readings they lack, as they have
  # most homophones (いこう: 以降 移行 意向 行こう), and after the user dictionary, which holds some
  # 2300 learned readings (かがく /科学/), only for readings never picked before. The cost is that
  # what was picked last no longer leads for readings the server knows, which is nearly all of
  # them; the user dictionary still records picks. The server always answers in UTF-8, and libskk
  # uses one encoding for both directions, so requests are UTF-8 too; the Linux build does not
  # answer EUC-JP requests at all (nix/pkgs/azoo-key-skkserv.nix). skkeleton on Linux sends UTF-8
  # for the same reason (configs/editors/nvim/lua/plugins/skkeleton.lua).
  #
  # context=true makes this entry the fork's FcitxSkkContextServ (pkgs/fcitx5-skk-context.nix),
  # not libskk's SkkServ: each lookup also sends up to 30 characters around the cursor, which
  # Zenzai uses to order the candidates. It connects on the first lookup and opens the connection
  # again after the server restarts, so neither fcitx5's start nor a restart of this server needs
  # to be coordinated with the other. (libskk's SkkServ connected once, at fcitx5's start, and
  # never again, which took a wait in this unit, a restart of fcitx5 after it, and a watchdog.)
  systemd.user.services.azoo-key-skkserv = {
    Unit.Description = "azoo-key-skkserv (skkserv on 127.0.0.1:${toString skkservPort})";
    Service = {
      ExecStart = lib.escapeShellArgs [
        (lib.getExe azooKeySkkserv)
        "--port"
        (toString skkservPort)
        "--incoming-charset"
        "UTF-8"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      Nice = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # fcitx5 itself, as a unit rather than an exec-once in Hyprland. It wants the skkserv, so
  # conversion through Zenzai is there in the session; their order no longer matters (see above).
  # The session's Wayland variables reach it through graphical-session.target. --replace: takes
  # over any instance that something else started.
  systemd.user.services.fcitx5 = {
    Unit = {
      Description = "fcitx5 input method (SKK)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      Wants = [ "azoo-key-skkserv.service" ];
    };
    Service = {
      ExecStart = "/run/current-system/sw/bin/fcitx5 --replace";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

}
