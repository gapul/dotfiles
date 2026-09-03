# Keyball39 QMK keymap

The Keyball39 configuration, moved out of Remap and VIA and into a QMK keymap kept in code.
`keymap-export.json` is the configuration as it was on the keyboard, read out live through
Remap, and `keymap.c` is that converted mechanically by `gen_keymap.py`. VIA stays enabled, so
this code is the base but the keymap and lighting can still be tweaked through Remap and VIA.

## The files

- `keymap.c` — the generated result, and fine to edit by hand however you like.
- `keymap-export.json` — the source data and a backup: every layer's keycodes plus the lighting
  settings, read off the keyboard.
- `gen_keymap.py` — regenerates `keymap.c` from `keymap-export.json`.
- `config.h` and `rules.mk` — equivalent to the stock keyball39 `via` keymap, with VIA_ENABLE,
  RGBLIGHT and OLED.

## The layers, as of the migration

- L0: QWERTY with home row mods — on the left, A is Shift, S is Ctrl, D is Alt, F is Gui and G
  is Ctrl+Alt+Gui, mirrored on the right — and on the thumbs, Tab is LT3, Space is LT1 and Esc
  is LT2.
- L1: numbers, symbols, arrows, mouse buttons and screen brightness.
- L2: function keys, numbers, symbols and volume.
- L3: RGB and underglow, the trackball (CPI, scroll, auto mouse), and the bootloader.

The underglow was at effect mode All Off at migration time, which is effectively off.

## Building it, the way that actually worked

Keyball is verified against QMK 0.22.14. The build overlays keyball onto a real qmk_firmware
0.22.14 checkout through symlinks. Homebrew's qmk breaks its Python environment easily, so this
uses `avr-gcc@12` from brew, which is keg-only, plus a uv venv on Python 3.11 and the pip
version of the qmk launcher.

```sh
# 0) install avr-gcc@12 through brew first; it is keg-only
brew install qmk/qmk/qmk        # brings in avr-gcc@12 and friends. Only avr-gcc gets used.

# 1) the keyball repository
git clone https://github.com/Yowkees/keyball.git ~/repos/keyball

# 2) qmk_firmware 0.22.14, with submodules
git clone https://github.com/qmk/qmk_firmware.git \
  --depth 1 --recurse-submodules --shallow-submodules -b 0.22.14 ~/repos/qmk

# 3) overlay keyball, and link this keymap in as "gapul"
ln -sfn ../../keyball/qmk_firmware/keyboards/keyball ~/repos/qmk/keyboards/keyball
ln -sfn ~/.dotfiles/configs/keyboard/keyball39 \
  ~/repos/keyball/qmk_firmware/keyboards/keyball/keyball39/keymaps/gapul

# 4) dependencies in a 3.11 uv venv, plus the qmk launcher
cd ~/repos/qmk
uv venv .venv --python 3.11
uv pip install --python .venv/bin/python -r requirements.txt qmk

# 5) build
export PATH="$PWD/.venv/bin:/opt/homebrew/opt/avr-gcc@12/bin:$PATH"
export QMK_HOME=$PWD
qmk config user.qmk_home=$PWD
qmk compile -kb keyball/keyball39 -km gapul
# produces ~/repos/qmk/keyball_keyball39_gapul.hex, about 26.8 KB of 28 KB
```

After editing the keymap, only step 5 needs repeating. To rebuild from
`keymap-export.json` instead, run `python3 gen_keymap.py` in this directory.

There is also Remap's Firmware Workbench, which builds in the cloud: it compiles the source in
the browser, gives you a hex, and can flash it, with no local toolchain at all.

## Flashing

It is a split keyboard, so the same hex goes onto both halves, one at a time.

```sh
cd ~/repos/qmk
export PATH="$PWD/.venv/bin:/opt/homebrew/opt/avr-gcc@12/bin:$PATH"
export QMK_HOME=$PWD
# connect only the half you are flashing, run this, and press reset twice when prompted
qmk flash -kb keyball/keyball39 -km gapul
# then connect the other half and run the same command again
```

QMK Toolbox or Remap's flash feature work equally well with
`keyball_keyball39_gapul.hex`; choose ProMicro, ATmega32U4 and Caterina. Flashing clears the
EEPROM, so the keymap falls back to whatever `keymap.c` says. The lighting returns to All Off,
so set it again through Remap if you want it. VIA is still enabled, so adjusting things in Remap
keeps working.
