# minecraft

macmini で動かしているマイクラのサーバーの起動まわり。どのインスタンスを立てるかは
`nix/hosts/macmini.nix` の `minecraftServers` が持ち、ここに置いてあるのは
その表から呼ばれるスクリプトだけ。

- `run.sh` — Paper と Fabric を起動する。版が変わっていれば世界を退避し、宣言された
  jar を `plugins/` `mods/` に張り直してから上げる
- `run-modded.sh` — NeoForge を起動する。libraries が無ければインストーラを1回走らせる
- `backup.sh` — 毎晩 4:40、全インスタンスを1本ずつ止めて固める

📖 **構成・世界の増やし方・復元手順は [`docs/minecraft.md`](../../../docs/minecraft.md) を参照。**
