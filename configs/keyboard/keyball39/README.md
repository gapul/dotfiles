# Keyball39 QMK keymap (gapul)

Remap/VIA で運用していた Keyball39 の設定を、コード管理の QMK キーマップに移行したもの。
`keymap-export.json` が実機（Remap 経由でライブ読み込み）から吸い出した現行設定、
`keymap.c` はそれを `gen_keymap.py` で機械変換したもの。VIA は有効のままなので、
このコードをベースにしつつ Remap/VIA でキーマップ・ライトの微調整も引き続き可能。

## ファイル

- `keymap.c` … 生成物（手編集も可）。編集して自分好みにしてよい。
- `keymap-export.json` … 移行元データ（バックアップ。実機から吸い出した全レイヤーのキーコード＋ライト設定）。
- `gen_keymap.py` … `keymap-export.json` → `keymap.c` を再生成するスクリプト。
- `config.h` / `rules.mk` … 純正 keyball39 `via` と同等（VIA_ENABLE / RGBLIGHT / OLED）。

## レイヤー構成（移行時点）

- L0: QWERTY + ホームロー・モッド（左 A=Shift S=Ctrl D=Alt F=Gui G=Ctrl+Alt+Gui / 右対称）+ 親指 Tab=LT3 Space=LT1 Esc=LT2
- L1: 数字・記号・矢印・マウスボタン・画面輝度
- L2: ファンクションキー・数字・記号・音量
- L3: RGB/アンダーグロウ操作・トラックボール(CPI/スクロール/オートマウス)・Bootloader

ライト（アンダーグロウ）は移行時 Effect Mode = All Off（実質オフ）。

## ビルド方法（実際に通った手順）

Keyball は QMK **0.22.14** で検証されている。本物の qmk_firmware(0.22.14) に
keyball をシンボリックリンクで重ねてビルドする。brew版qmkはpython環境が壊れやすいので、
`avr-gcc@12`(brew, keg-only) ＋ uv venv(Python 3.11) ＋ pip版qmkランチャーを使う。

```sh
# 0) 前提: brew で avr-gcc@12 を導入済み（keg-only）
brew install qmk/qmk/qmk        # avr-gcc@12 等が入る。qmk本体は使わずavr-gccだけ使う

# 1) keyball リポジトリ
git clone https://github.com/Yowkees/keyball.git ~/repos/keyball

# 2) qmk_firmware 0.22.14（submodule込み）
git clone https://github.com/qmk/qmk_firmware.git \
  --depth 1 --recurse-submodules --shallow-submodules -b 0.22.14 ~/repos/qmk

# 3) keyball を重ねる ＋ この keymap を gapul として結合
ln -sfn ../../keyball/qmk_firmware/keyboards/keyball ~/repos/qmk/keyboards/keyball
ln -sfn ~/.dotfiles/configs/keyboard/keyball39 \
  ~/repos/keyball/qmk_firmware/keyboards/keyball/keyball39/keymaps/gapul

# 4) uv venv(3.11) に依存 ＋ qmk ランチャー
cd ~/repos/qmk
uv venv .venv --python 3.11
uv pip install --python .venv/bin/python -r requirements.txt qmk

# 5) ビルド
export PATH="$PWD/.venv/bin:/opt/homebrew/opt/avr-gcc@12/bin:$PATH"
export QMK_HOME=$PWD
qmk config user.qmk_home=$PWD
qmk compile -kb keyball/keyball39 -km gapul
# => ~/repos/qmk/keyball_keyball39_gapul.hex  (約26.8KB / 28KB, 余裕あり)
```

keymap を編集したら 5) だけ再実行。`keymap-export.json` から作り直したいときは
`python3 gen_keymap.py`（このフォルダ）で `keymap.c` を再生成。

### 別解: Remap の Firmware Workbench（クラウドビルド, ローカル環境不要）

ソースをブラウザ上でビルド → hex 取得 → そのまま書き込みも可能。

## 書き込み

分割キーボードなので**左右それぞれに同じ hex を書き込む**（片方ずつ）。

```sh
cd ~/repos/qmk
export PATH="$PWD/.venv/bin:/opt/homebrew/opt/avr-gcc@12/bin:$PATH"
export QMK_HOME=$PWD
# 書き込む側の半分だけ USB 接続 → 実行 → プロンプトが出たらリセットボタンを2回押す
qmk flash -kb keyball/keyball39 -km gapul
# 終わったらもう片方を USB 接続して、同じコマンドをもう一度
```

QMK Toolbox や Remap の Flash 機能で `keyball_keyball39_gapul.hex` を書いてもよい
（ProMicro / ATmega32U4 / Caterina を選択）。書き込みで EEPROM は初期化され、
キーマップは keymap.c の内容が既定になる。ライトは All Off に戻るので必要なら Remap で再設定。
VIA は有効なので Remap での微調整は引き続き可能。
