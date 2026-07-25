# NixOS recovery

This ISO is a non-destructive recovery environment. It never partitions or
formats a disk automatically.

## Inspect first

```console
lsblk -o NAME,SIZE,FSTYPE,FSVER,LABEL,UUID,PARTUUID,MOUNTPOINTS
sudo fdisk -l
```

Confirm the Windows partitions, the existing EFI System Partition, and the
single Linux root partition before continuing. Never pass the whole disk or a
Windows/EFI partition to disko.

## Restore the configuration

```console
git clone https://github.com/gapul/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
less docs/NIXOS_DUALBOOT.md
```

Edit `nix/hosts/nixos-laptop-disk.nix` so `device` points to the intended
Linux root partition by its stable `/dev/disk/by-id/...` path.

The destructive command is intentionally not wrapped by a helper:

```console
sudo disko --mode destroy,format,mount --flake ./nix#nixos-laptop
```

Mount the existing EFI System Partition at `/mnt/boot` without formatting it,
then follow `docs/NIXOS_DUALBOOT.md` to generate the hardware configuration and
install NixOS.

## Restore state

Restore these separately after the base system boots:

- the SOPS age private key from the password manager;
- user files and restic/rclone credentials;
- Secure Boot keys, or create and enroll new keys;
- Tailscale, Wi-Fi, Bluetooth, and fingerprint enrollment state.

The repository and public recovery ISO contain no decrypted secrets or private
keys.
