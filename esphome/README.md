# ESPHome

The configuration that runs on the ESP chips. The ESPHome server itself is declared through the
`sites` table in `nix/hosts/homeserver.nix`, as `esphome.gapul.net`, but the device YAML existed
only inside that container and was left outside the repository. With ESPHome the YAML is the
thing itself, so there is no reason not to keep it here.

```
esphome/
├── plant-watering.yaml   # automatic watering for four pots, on an ESP32 DevKitC
├── common/pot.yaml       # one pot; copied four times with different GPIOs and thresholds
├── secrets.example.yaml  # a template for secrets.yaml, which is gitignored
└── validate.sh           # checks the syntax without any hardware
```

## Validating

```sh
just esphome        # nix shell nixpkgs#esphome -c ./validate.sh
```

If there is no real `secrets.yaml`, it validates in a temporary directory using the template, so
it passes on a machine without the keys. CI runs the same thing.

`esphome config` writes validation errors to stdout, so redirecting to `/dev/null` makes it fail
silently. `validate.sh` captures the output and shows it only on failure.

## Flashing

```sh
nix shell nixpkgs#esphome -c esphome run esphome/plant-watering.yaml
```

Over USB the first time and OTA afterwards. Create `secrets.yaml` first, by copying the
template and filling it in.

## About the watering machine

The design is in `docs/design.md` in
[gapul/esp32-plant-watering](https://github.com/gapul/esp32-plant-watering). What is here is
that design turned straight into YAML, written before the parts arrived. The thresholds and
watering durations are placeholders meant to be pinned down by measurement, so revise them after
calibration.

Constraints carried over from the design:

- The ADC must be on ADC1, GPIO32-35. ADC2 cannot be read while Wi-Fi is in use.
- Keep the pumps off the strapping pins, 0, 2, 12 and 15, which go high at boot.
- The sensors are not permanently powered. They are fed from GPIO25 and switched on only while
  measuring, to avoid electrolytic corrosion.
- Pumps are always driven through a script. Turning the switch on directly leaves nobody to turn
  it off.
- `restore_mode: ALWAYS_OFF`, so a reboot does not start a pump.
- The four pots are watered in turn. Simultaneously, the inrush current exceeds what 5 V 2 A
  over USB can supply.
- The sensors decide only whether to water, not how much. The volume is a fixed duration
  multiplied by the measured flow rate.
