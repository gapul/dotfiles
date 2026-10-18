import * as k from "karabiner.ts";

const inputModeSwitch = {
  ...k
    .rule("Input Mode Switch (Ctrl+Shift)")
    .manipulators([
      k.map("j", ["control", "shift"]).to("japanese_kana"),
      k.map("semicolon", ["control", "shift"]).to("japanese_eisuu"),
      k.map("r", ["control", "shift"]).to("japanese_kana"),
    ])
    .build(),
  enabled: false,
};

const characterConversion = {
  ...k
    .rule("Character Conversion (Ctrl)")
    .manipulators([
      k.map("j", "control").to$("osascript -e 'tell application \"System Events\" to key code 103'"),
      k.map("k", "control").to$("osascript -e 'tell application \"System Events\" to key code 98'"),
      k.map("l", "control").to$("osascript -e 'tell application \"System Events\" to key code 101'"),
      k
        .map("semicolon", "control")
        .to$("osascript -e 'tell application \"System Events\" to key code 109'"),
    ])
    .build(),
  enabled: false,
};

k.writeToProfile("Default profile", [
  inputModeSwitch,
  characterConversion,
  k.rule("Cmd+Q を長押し(1秒)で終了 (slowquitapps代替)").manipulators([
    k
      .map("q", "left_command")
      .toNone()
      .toIfHeldDown("q", "left_command")
      .parameters({ "basic.to_if_held_down_threshold_milliseconds": 1000 }),
  ]),
  k.rule("Discord-Enter-Modification", k.ifApp(/^com\.hnc\.Discord/)).manipulators([
    k.map("return_or_enter").to("return_or_enter", "left_shift"),
    k.map("return_or_enter", "command").to("return_or_enter"),
  ]),
]);
