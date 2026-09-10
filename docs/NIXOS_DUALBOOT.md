# Dual-booting NixOS alongside Windows, with everything locked down

How to shrink a single SSD that already has a full Windows installation on it and put NixOS in
the free space. Assumes the Intel integrated GPU is the only graphics. Both systems end up
encrypted and signed:

- The NixOS root is fully encrypted with LUKS.
- Booting goes through lanzaboote with Secure Boot enabled, signed with our own keys, keeping
  the Microsoft keys so Windows still boots.
- Windows keeps BitLocker; it is only suspended, never decrypted.

The configuration is already part of this repository's flake, under `nix/`:

- `nix/hosts/nixos-laptop.nix` — the system: lanzaboote, LUKS with TPM2, zram, the Intel GPU,
  Hyprland, fcitx5-mozc, tlp, fprintd, podman, tailscale, fwupd.
- `nixosConfigurations."nixos-laptop"` in `nix/flake.nix` — wires up lanzaboote, disko and
  home-manager, pulling in `home/common.nix`, `home/linux.nix`, `home/hyprland.nix`,
  `home/dev.nix` and `home/restic-backup-linux.nix`.
- `nix/hosts/nixos-laptop-disk.nix` — the declarative disko layout, covering the LUKS root
  only, also exposed through `diskoConfigurations`.
- `scripts/install-nixos-laptop.sh` — a guarded install helper, the procedural alternative to
  disko.
- `nix/hosts/nixos-laptop-hardware.nix` — the machine-specific file, generated on the real
  hardware and added afterwards. The LUKS device UUID lives here.

Do not delete Windows, and do not format the EFI system partition — it gets reused. Check every
disk name (`nvme0n1`, `sda` and so on) against `lsblk` on the actual machine before running
anything.

---

## Phase 0. Preparing Windows

Skipping this before touching partitions is how Windows ends up unbootable.

1. Back up anything that matters.
2. Suspend BitLocker, without decrypting. In an administrator PowerShell:

   ```powershell
   manage-bde -status                                 # check the encryption state
   (Get-BitLockerVolume -MountPoint C:).KeyProtector  # write down the recovery key. Required.
   manage-bde -protectors -disable C: -RebootCount 0  # stay suspended until re-enabled
   ```

   The data stays encrypted. Switching Secure Boot and adding a boot loader changes the TPM
   measurements, so Windows may ask for the recovery key once on its next start. Have it to
   hand.

3. Turn off Fast Startup: Control Panel, Power Options, "Choose what the power buttons do",
   "Change settings that are currently unavailable", then untick "Turn on fast startup".
   Leaving it on means Windows hibernates with NTFS locked and unfinalised, and touching it
   from Linux corrupts it.

   This is temporary, for the installation. This setup never mounts the Windows NTFS from NixOS
   — `boot.supportedFilesystems` is commented out — so it can go back on afterwards, as
   described in 9-2. Leave it off only if you want to share C: read-write with NixOS.

4. Turn off hibernation, optional but recommended: `powercfg /h off` in an administrator
   PowerShell.
5. Shrink C:. In `diskmgmt.msc`, right-click C:, Shrink Volume, and give the amount you want
   for NixOS, for instance 150000 MB for about 150 GB. Leave the resulting unallocated space
   alone; the NixOS installer will carve it up.

## Phase 1. BIOS and UEFI

Reboot into the BIOS, usually with Del or F2.

- Leave Secure Boot off for now. NixOS cannot boot until our own keys are enrolled, which
  happens in phase 8.
- Stay in UEFI mode; do not switch to CSM or Legacy. Windows is already UEFI.
- If necessary, turn off Fast Boot temporarily so the machine will boot from USB.

## Phase 2. Making the installer USB, from the Mac

The whole installation is command line — cryptsetup, `nixos-install --flake`, sbctl — and the
desktop comes from the flake afterwards, so the minimal ISO is enough and is lighter.

1. Download the ISO and check the SHA256. The "latest" link on `channels.nixos.org` tracks the
   newest build.

   ```sh
   cd ~/Downloads
   curl -L -o nixos-minimal-26.05-x86_64.iso \
     "https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso"
   curl -sL "https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso.sha256"
   shasum -a 256 nixos-minimal-26.05-x86_64.iso   # must match
   ```

2. Insert the USB stick and write to it. macOS's `dd` has no `status=progress`; press Ctrl-T
   for progress.

   ```sh
   diskutil list external physical          # find the USB's diskN, by size and Removable
   diskutil unmountDisk /dev/diskN
   sudo dd if=~/Downloads/nixos-minimal-26.05-x86_64.iso of=/dev/rdiskN bs=4m
   sync && diskutil eject /dev/diskN
   ```

   `rdiskN`, the raw device, is much faster. Getting `diskN` wrong destroys another disk, so
   check. If macOS says "The disk you attached was not readable" afterwards, choose Ignore —
   never Initialize.

## Phase 3. Booting the installer

Plug the stick in and boot, choosing "UEFI: USB..." from the boot menu, usually F12, F8, Esc or
F11. The minimal image gives a text login. Become root with `sudo -i` and get networking up,
wired or wireless, with `nmtui`.

## Phase 4. Partitioning and LUKS

Before starting, the NixOS files in this repository must be committed and pushed, because the
installer clones from GitHub. Local changes that are not pushed never reach the machine.

There are three ways to do this. All of them start the same way: create one Linux partition in
the free space with `cfdisk`.

**(a) disko, declarative, recommended.** The disk layout lives in the repository. It manages the
LUKS root partition alone and never touches the GPT, Windows or the ESP, which is what makes it
safe.

```sh
nix-shell -p git --run 'git clone https://github.com/gapul/dotfiles.git /tmp/df'
# replace the device in nix/hosts/nixos-laptop-disk.nix with the real Linux partition
#   check with lsblk -o NAME,SIZE,FSTYPE,PATH. Never the whole disk, Windows, or the ESP.
sudo disko --mode destroy,format,mount --flake /tmp/df/nix#nixos-laptop  # LUKS and ext4 onto /mnt
mount /dev/nvme0n1p1 /mnt/boot          # the ESP is outside disko. Mount by hand, never format.
```

Then continue at phase 6, with `nixos-generate-config --root /mnt`.

**(b) The helper script**, a guarded procedure without disko, which automates phases 4 through 6
while mechanically refusing to touch the wrong device or wipe NTFS or the ESP:

```sh
bash /tmp/df/scripts/install-nixos-laptop.sh /dev/nvme0n1p5 /dev/nvme0n1p1
```

**(c) By hand**, following the steps below one at a time, if you want to understand what is
happening.

```sh
sudo -i
lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME,MOUNTPOINT
```

A typical existing layout on NVMe:

| Partition | Purpose | What to do |
|---|---|---|
| `nvme0n1p1` | ESP, vfat, 100-300 MB | Reuse. Never format |
| `nvme0n1p2` | Microsoft Reserved | Leave alone |
| `nvme0n1p3` | Windows C:, ntfs | Leave alone |
| `nvme0n1p4` | Recovery, ntfs | Leave alone |
| free space at the end | what phase 0 freed | The NixOS root goes here |

Create the new partition in the free space, with type `Linux filesystem`:

```sh
cfdisk /dev/nvme0n1      # New, all free space, Type: Linux filesystem, Write, yes, Quit
```

Check the resulting number with `lsblk` — assume `nvme0n1p5` here — then encrypt it with LUKS
before making the filesystem:

```sh
cryptsetup luksFormat /dev/nvme0n1p5         # set a passphrase; it asks for an uppercase YES
cryptsetup open /dev/nvme0n1p5 cryptroot     # opens as /dev/mapper/cryptroot
mkfs.ext4 -L nixos /dev/mapper/cryptroot
```

Do not create a plaintext swap partition. The host configuration already has
`zramSwap.enable = true`, which is in RAM and encrypted. If real swap turns out to be needed,
set up an encrypted swap separately.

## Phase 5. Mounting, reusing the ESP

```sh
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot        # the existing Windows ESP. Do not format it.
```

If the ESP is only 100 MB it fills up quickly with signed UKIs. Lowering
`boot.lanzaboote.configurationLimit` in `nix/hosts/nixos-laptop.nix` to 3 to 5 is the safe move;
with 260 MB or more, 8 is fine.

## Phase 6. Generating the hardware configuration and pulling in the flake

```sh
nixos-generate-config --root /mnt
```

This writes `/mnt/etc/nixos/hardware-configuration.nix`. Because `cryptroot` is open, it
automatically contains
`boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/…";`. Check that
`fileSystems."/boot"` points at the vfat ESP and `fileSystems."/"` at `/dev/mapper/cryptroot`.

Then pull in dotfiles and copy the generated hardware configuration to the name the repository
expects:

```sh
nix-shell -p git
git clone https://github.com/gapul/dotfiles.git /mnt/etc/nixos/dotfiles
cp /mnt/etc/nixos/hardware-configuration.nix \
   /mnt/etc/nixos/dotfiles/nix/hosts/nixos-laptop-hardware.nix
git -C /mnt/etc/nixos/dotfiles add -A      # required: a flake only sees git-tracked files
```

`nixosConfigurations."nixos-laptop"` only appears in the flake once
`nixos-laptop-hardware.nix` exists, which is deliberate — otherwise `nix flake check` on the Mac
would break.

## Phase 7. Installing

Secure Boot is still off at this point, since the lanzaboote keys are not enrolled yet.

Create the signing keys first. lanzaboote signs the UKI with the keys in `/var/lib/sbctl` when it
installs the boot loader, and without them `nixos-install` fails at the very end with
`Failed to read public key from /var/lib/sbctl/keys/db/db.pem` — only the boot loader
installation fails; the system itself is already built, so creating the keys and re-running
picks up where it stopped. Creating keys does not require the BIOS to be in Setup Mode; that is
only needed to enrol them, in phase 8.

```sh
nixos-install --no-bootloader --flake /mnt/etc/nixos/dotfiles/nix#nixos-laptop
nixos-enter --root /mnt -c 'sbctl create-keys'
```

Then:

```sh
nixos-install --flake /mnt/etc/nixos/dotfiles/nix#nixos-laptop
```

It asks for a root password along the way. Set the normal user's password too:

```sh
nixos-enter --root /mnt -c 'passwd gapul'
```

Then `reboot`, removing the USB stick.

## Phase 8. After the first boot: enabling Secure Boot

The systemd-boot menu lists NixOS and Windows Boot Manager. Booting asks for the LUKS
passphrase, then logs into NixOS.

### 8-1. Create, sign with and enrol the Secure Boot keys

```sh
# generate the keys, matching pkiBundle = /var/lib/sbctl in the host configuration
sudo sbctl create-keys

# lanzaboote is already enabled, so a rebuild signs the UKI with our keys
sudo nixos-rebuild switch --flake ~/.dotfiles/nix#nixos-laptop
sudo sbctl verify        # every signed file should be ticked
```

### 8-2. Put the BIOS in Setup Mode and enrol

1. Reboot into the BIOS and clear the Secure Boot keys, or put it in Setup Mode. Depending on
   the vendor this is "Erase all Secure Boot keys", "Clear keys" or "Setup Mode".
2. Back in NixOS, enrol our keys while keeping the Microsoft ones:

   ```sh
   sudo sbctl enroll-keys --microsoft   # keeps the MS keys so Windows still boots
   ```

### 8-3. Turn Secure Boot on

Reboot into the BIOS and set Secure Boot to Enabled. Once NixOS is up, `bootctl status` should
say `Secure Boot: enabled (user)`. Check that Windows still boots from the boot manager; it will,
because the Microsoft keys are still there.

### 8-4. Loose ends

The clocks will disagree, since NixOS keeps the RTC in UTC and Windows defaults to local time.
In an administrator PowerShell on Windows:

```powershell
reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
```

Re-enable BitLocker, suspended back in phase 0, with `manage-bde -protectors -enable C:`.

Place the age key. home-manager includes `sops-nix`, so using encrypted secrets needs a key at
`~/.config/sops/age/keys.txt`, or wherever `SOPS_AGE_KEY_FILE` points. If there is no key yet
and decryption blocks you, temporarily removing `sops-nix.homeManagerModules.sops` from the
relevant `imports` in `nix/flake.nix` is a reasonable stopgap.

## Phase 9. Living with it

Configuration changes go through the flake, the same as on the Mac. lanzaboote re-signs every
time, so Secure Boot stays intact:

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles/nix#nixos-laptop
```

Commit `nix/hosts/nixos-laptop-hardware.nix` and the machine can be rebuilt from the repository
from then on. It contains only the LUKS device UUID and device paths, no key material, so a
public repository is a small risk; if that still bothers you, gitignore it and keep it locally.

### 9-1. Making both systems pleasant to use daily

Since both get used, it is worth lowering the cost of switching.

Reboot straight into Windows without waiting for the systemd-boot menu:

```sh
# boot Windows next time only, then reboot
sudo bootctl set-oneshot auto-windows && systemctl reboot
# or
sudo systemctl reboot --boot-loader-entry=auto-windows
```

`bootctl list` shows the entry names; `auto-windows` is the standard one.

The menu timeout is already `boot.loader.timeout = 5`. If you miss it, just reboot again.

Back up the Secure Boot keys, so a BIOS update that loses them is quick to recover from:

```sh
sudo tar czf ~/sbctl-keys-backup.tar.gz -C /var/lib sbctl   # keep it somewhere safe, or on a USB stick
```

For files shared between the two, a single exFAT partition both systems can safely read and
write beats writing NTFS from Linux: no corruption risk, and hibernation does not affect it.
Create one with `mkfs.exfat` in free space when the need comes up.

### 9-2. Turning Fast Startup back on, optional

The Fast Startup turned off in phase 0 can go back on, as long as NixOS never touches the
Windows C: NTFS. The dangerous case is writing to a hibernated Windows NTFS from Linux, and this
setup avoids it. In an administrator PowerShell:

```powershell
powercfg /h on
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 1 /f
```

If you later want to share C: read-write with NixOS, turn it off again.

### 9-3. One-time setup after installing

Manual steps needed to switch on the features the flake already contains.

```sh
# enrol a fingerprint (fprintd). sudo and hyprlock accept it afterwards
sudo fprintd-enroll $USER

# join Tailscale, for the homelab's *.gapul.net
sudo tailscale up

# enrol TPM2 with a PIN, only after Secure Boot is on. See appendix A.
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/nvme0n1p5

# restic needs rclone's google-drive re-authorised, with the token in sops
rclone authorize "drive"   # put the printed token into rclone_conf in secrets.yaml
# then either wait for the daily systemd timer at 13:00 or run it now:
systemctl --user start restic-backup.service

# place the age key for sops at ~/.config/sops/age/keys.txt, or restic and friends will stop
```

The main Hyprland bindings, from `home/hyprland.nix`: `SUPER+Return` for ghostty, `SUPER+R` for
wofi, `SUPER+Q` to close, `SUPER+F` for fullscreen, `SUPER+L` to lock, `SUPER+E` for yazi,
`SUPER+P` for a region screenshot, `SUPER+C` for clipboard history, and `SUPER+1` through `0`
for workspaces. hypridle locks after 5 minutes and suspends after 15.

---

## Appendix A: TPM2 with a PIN, replacing a long passphrase with a short one

The configuration is already in place: `nixos-laptop.nix` sets
`boot.initrd.systemd.enable = true` and
`boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" "tpm2-pin=yes" ]`.
All that is left is enrolling the key into the TPM, after Secure Boot is on, meaning after phase
8:

```sh
# enrol TPM2 against the LUKS partition, bound to PCR 7, the Secure Boot state.
# Find the partition with lsblk, for example nvme0n1p5. It asks for the current
# passphrase and for a new PIN.
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/nvme0n1p5
```

From the next boot, the PIN unlocks the disk instead of the long passphrase. If the boot chain
is tampered with, PCR 7 changes and the TPM refuses to release the key. Before enrolment, or
after tampering, it falls back to the passphrase.

### Why bother with the PIN

Enrolling against PCR 7 alone means "release the key if the boot chain is untampered", which
binds the disk to the machine rather than to a person. On a laptop that leaves the house, that
means whoever steals it gets a decrypted disk simply by pressing the power button. Everything
Secure Boot was locked down for is undone by possession alone.

A PIN gets hardware-enforced retry limiting from the TPM, which locks out after enough failures,
so it does not need a passphrase's length. Brute force never gets going, which makes even a few
digits a real barrier.

Setting `tpm2-pin=yes` against a slot enrolled without `--tpm2-with-pin=yes`, or the reverse,
does not fail loudly — it simply does not match and falls back to the passphrase. To change an
existing slot, wipe it first with
`sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p5` and enrol again.

Do not enrol before Secure Boot is on. PCR 7 would be fixed at its Secure-Boot-off value, and
turning Secure Boot on afterwards would leave the disk unopenable. Always enrol after phase 8.

## Appendix B: Troubleshooting

| Symptom | What to do |
|---|---|
| Windows asks for the BitLocker recovery key | Unlock with the key from phase 0. Expected once, from the changed TPM measurements |
| `bootctl status` says "Secure Boot: disabled" | Either the enrolment in 8-2 and 8-3 did not happen or it was not enabled in the BIOS. Check signatures with `sbctl verify` |
| NixOS will not boot with Secure Boot on | Put the BIOS back into Setup Mode and redo `sbctl enroll-keys -m`. Worst case, turning Secure Boot off gets you booting again |
| Windows will not boot with Secure Boot on | `--microsoft` was left off `enroll-keys`. Enrol again |
| Windows is missing from the menu | Check that the ESP really is mounted at `/mnt/boot`, and that it did not end up on a different ESP |
| A switch fails because the ESP is full | Lower `boot.lanzaboote.configurationLimit`, or delete old generations with `nix-collect-garbage -d` |
| Tired of typing the LUKS passphrase | Set up the TPM2 unlock in appendix A |
| Nothing on screen with the Intel GPU | Check `hardware.graphics` in `nixos-laptop.nix`. Worst case, boot with `nomodeset` and investigate |
