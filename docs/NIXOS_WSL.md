# Windows の中の NixOS (WSL2)

Adobe やテストのために Windows で起動している間も、再起動せずに普段のシェルと
道具を使うための箱。GUI は Windows に任せ、こちらは CLI に徹する。

## デュアルブートの NixOS とは何を共有するか

**インストールは共有しない。** WSL2 は物理パーティションを起動する仕組みではなく、
Microsoft のカーネルで VHDX の中の rootfs を動かすので、実機の NixOS パーティションを
そのまま WSL の root にすることはできない。`wsl --mount --partition` でマウントして
中を読むことはできるが、root にはならない。

**共有するのは設定のほう。** `nixosConfigurations.wsl` の home は `roles.wsl` を
読んでいて、これは Lab PC の standalone home-manager (`homeConfigurations.labpc-wsl`)
と同じ実体。つまりどちらから入っても zsh / neovim / tmux / yazi / fzf が同じになる。

`/nix/store` の共有はしない。デュアルブートなので同時には走らないが、nix の DB と
GC root を 2 つの環境で持ち回ることになって事故りやすい。ビルド済みのものは
Cachix / 自前 attic から降ってくるので、2 回ビルドしても実際の再ビルドはほぼ無い。

## tarball を作る

root と Linux が要る (母艦の mac では作れない)。homeserver で作って持ち帰る:

```sh
just wsl-tarball
```

中でやっているのはこれ:

```sh
sudo nix run <flake>#nixosConfigurations.wsl.config.system.build.tarballBuilder
# → カレントに nixos.wsl ができる
```

### sops の鍵を入れておく

`roles.wsl` は sops を読む。age 鍵が無いと初回の home-manager 適用で落ちるので、
tarball を作るときに一緒に詰めておくのが楽 (あとから手で置いてもよい)。

```sh
root=$(mktemp -d)
mkdir -p "$root/home/gapul/.config/sops/age"
cp keys.txt "$root/home/gapul/.config/sops/age/keys.txt"
sudo nix run <flake>#nixosConfigurations.wsl.config.system.build.tarballBuilder -- --extra-files "$root"
```

## Windows 側に入れる

```powershell
wsl --import nixos $env:LOCALAPPDATA\WSL\nixos nixos.wsl --version 2
wsl -d nixos
```

以降は中で普通の NixOS として更新する。import し直すのは rootfs を作り直したいときだけ:

```sh
sudo nixos-rebuild switch --flake github:gapul/dotfiles?dir=nix#wsl
```

## 既定の distro にするか

しない。`wsl --import` した distro は既定にしなくても `wsl -d nixos` で入れる。
Docker Desktop の WSL 統合を使う場合だけ、その distro を統合対象に入れる。

## Lab PC との使い分け

Lab PC は OS を入れ替えられないので、Ubuntu の上に standalone home-manager を
載せる形 (`homeConfigurations.labpc-wsl`) のまま。こちらは自分の機械なので
NixOS ごと入れる。どちらも home は `roles.wsl` で同じ。
