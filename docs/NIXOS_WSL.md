# NixOS inside Windows (WSL2)

A box for keeping the usual shell and tools while Windows is booted for Adobe work or testing,
without rebooting. Windows handles the GUI; this side stays on the command line.

## What it shares with the dual-boot NixOS

**Not the installation.** WSL2 does not boot a physical partition. It runs a rootfs inside a
VHDX under Microsoft's kernel, so the real NixOS partition cannot become the WSL root.
`wsl --mount --partition` can mount it and read its contents, but it will not serve as root.

**The configuration, though, is shared.** The home for `nixosConfigurations.wsl` comes from
`roles.wsl`, the same thing the Lab PC's standalone home-manager
(`homeConfigurations.labpc-wsl`) reads. Either way in, zsh, neovim, tmux, yazi and fzf are
identical.

`/nix/store` is not shared. Dual boot means they never run at once, but carrying one nix
database and one set of GC roots across two environments invites accidents. Anything already
built comes down from Cachix or the self-hosted attic, so building twice rarely means
rebuilding twice.

## Building the tarball

Needs root and Linux, so the Mac cannot do it. Build it on homeserver and bring it back:

```sh
just wsl-tarball
```

Which runs:

```sh
sudo nix run <flake>#nixosConfigurations.wsl.config.system.build.tarballBuilder
# leaves nixos.wsl in the current directory
```

### Include the sops key

`roles.wsl` reads sops. Without an age key the first home-manager activation fails, so it is
easiest to pack the key into the tarball. Placing it by hand afterwards works too.

```sh
root=$(mktemp -d)
mkdir -p "$root/home/gapul/.config/sops/age"
cp keys.txt "$root/home/gapul/.config/sops/age/keys.txt"
sudo nix run <flake>#nixosConfigurations.wsl.config.system.build.tarballBuilder -- --extra-files "$root"
```

## Installing it on Windows

```powershell
wsl --import nixos $env:LOCALAPPDATA\WSL\nixos nixos.wsl --version 2
wsl -d nixos
```

After that it updates from the inside like any NixOS. Re-importing is only for rebuilding the
rootfs itself:

```sh
sudo nixos-rebuild switch --flake github:gapul/dotfiles?dir=nix#wsl
```

## Making it the default distro

No. An imported distro is reachable with `wsl -d nixos` without being the default. The only
reason to touch this is Docker Desktop's WSL integration, which needs the distro added to its
integration list.

## How this differs from the Lab PC

The Lab PC's OS cannot be replaced, so it stays on Ubuntu with standalone home-manager on top
(`homeConfigurations.labpc-wsl`). This machine is mine, so it gets NixOS itself. Both share the
same home through `roles.wsl`.
