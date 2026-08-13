# ESPHome

ESP チップに載る設定。ESPHome サーバ自体は `nix/hosts/homeserver.nix` の
`sites` 表 (`esphome.gapul.net`) で宣言しているが、デバイスの YAML は
そのコンテナの中にしか無く、repo の外に取り残されていた。ESPHome は
YAML そのものが本体なので、置かない理由が無い。

```
esphome/
├── plant-watering.yaml   # 鉢植え 4 つの自動水やり機 (ESP32 DevKitC)
├── common/pot.yaml       # 鉢 1 つ分。GPIO と閾値だけ変えて 4 鉢に複製する
├── secrets.example.yaml  # secrets.yaml の雛形 (実物は gitignore)
└── validate.sh           # 実機なしで構文検証する
```

## 検証

```sh
just esphome        # nix shell nixpkgs#esphome -c ./validate.sh
```

実物の `secrets.yaml` が無ければ雛形を使って一時ディレクトリで検証するので、
鍵を持っていない環境でも通る。CI もこれを回している。

`esphome config` は検証エラーを stdout に出す。`>/dev/null` すると黙って
失敗するので、`validate.sh` は一度受けてから失敗時だけ見せている。

## 書き込み

```sh
nix shell nixpkgs#esphome -c esphome run esphome/plant-watering.yaml
```

初回は USB、以降は OTA。`secrets.yaml` を先に作る (雛形をコピーして埋める)。

## 水やり機について

設計は [gapul/esp32-plant-watering](https://github.com/gapul/esp32-plant-watering)
の `docs/design.md`。ここはその設計をそのまま YAML にしたもので、**部品が届く前に
書いてある**。閾値と給水秒数は実測で詰める前提の仮置きなので、キャリブレーション後に
直す。

設計から持ってきている制約:

- ADC は必ず ADC1 系 (GPIO32-35)。ADC2 系は Wi-Fi 使用中に読めない
- ポンプは strapping pin (0, 2, 12, 15) を避ける。起動時に HIGH になる
- センサーは常時通電しない。GPIO25 から給電し、測るときだけ ON にする (電蝕対策)
- ポンプは必ず script 経由で回す。switch を直接 on にすると止める人がいなくなる
- 再起動でポンプが回り出さないよう `restore_mode: ALWAYS_OFF`
- 4 鉢は順番に回す。同時だと突入電流が USB 5V 2A を超える
- センサーは給水するかしないかの判定にのみ使う。水量は秒数 × 実測流量の決め打ち
