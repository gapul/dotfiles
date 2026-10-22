#!/system/bin/sh
# Keeps the battery between RESUME and STOP while the tablet lives on the charger.
# battery_charging_enabled=0 stops charging the cell but still powers the device
# from USB; input_suspend would cut USB power too, which is not wanted here.
STOP=80
RESUME=75
NODE=/sys/class/power_supply/battery/battery_charging_enabled
CAP=/sys/class/power_supply/battery/capacity

[ -w "$NODE" ] || exit 0
while true; do
  cap=$(cat "$CAP")
  if [ "$cap" -ge "$STOP" ]; then
    echo 0 >"$NODE"
  elif [ "$cap" -le "$RESUME" ]; then
    echo 1 >"$NODE"
  fi
  sleep 60
done
