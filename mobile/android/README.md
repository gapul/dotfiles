# Android

```
android/
├── apps.tsv            # which apps to install: packageId plus the route
├── apps.ts             # status | install | verify | obtainium
├── os-settings.conf    # global settings applied through settings put
├── os-apps.tsv         # per-app OS settings: default launcher, permissions, battery
├── os-debloat.txt      # preinstalled apps to remove from user 0
├── os.sh               # applies the three above over adb, showing the difference first
├── devices/<codename>/ # one device's own apps.tsv and os-* files, replacing the ones above
│   └── root/           # rooted devices only: KernelSU modules and ksud features
├── root.sh             # applies root/ over adb, showing the difference first
├── launcher-theme.ts   # generates Kvaesitso's theme from palettes.json
└── test.sh             # self-check for the scripts above, against a fake adb, no device needed
```

## Devices

Two Android devices are declared, and they differ enough that one list cannot serve both:

| Device | Declaration | OS |
|---|---|---|
| Phone (Pixel) | the files at the top of this directory | GrapheneOS, no root |
| Xiaomi Pad 5 (`nabu`) | `devices/nabu/` | crDroid, KernelSU Next built into its kernel, microG, no F-Droid client |

`apps.ts`, `os.sh` and `root.sh` read `getprop ro.product.device` from the connected device and
use `devices/<that codename>/` when it exists, and the top-level files otherwise. A device
directory replaces the top-level files rather than adding to them, so it carries its own
`apps.tsv`, `os-settings.conf`, `os-apps.tsv` and `os-debloat.txt`. `ANDROID_PROFILE=<codename>`
overrides the detection (`ANDROID_PROFILE=default` picks the top-level files), and with both
devices plugged in, `ANDROID_SERIAL` picks which one adb talks to. `apps.ts verify` checks every
device's `apps.tsv`.

## Apps

The declared Obtainium app list is `configs/android/obtainium.json`, synced with
`droid obtainium pull|push` (`configs/bin/droid`): `pull` copies Obtainium's auto-export back
into the repository, `push` drops an import file on the device. `apps.tsv` is the older, smaller
declaration that `apps.ts` and the weekly drift CI still read; it does not list everything the
device has.

Three stores are in use, so the `source` column in `apps.tsv` says which one handles each app.

| source | Distributed by | Installable from the Mac | Updated on the device by |
|---|---|---|---|
| `fdroid` | F-Droid | Yes, `apps.ts install` | Obtainium or F-Droid |
| `izzy` | IzzyOnDroid | Yes, the same | Obtainium |
| `github` | GitHub releases | No | Obtainium |
| `gitlab` | GitLab releases | No | Obtainium |
| `play` | The Play Store | No | Aurora Store, importing Favourites and installing them in one go |

```sh
./apps.ts status      # declaration against the device. Exits 1 if anything is MISSING
./apps.ts install     # installs the F-Droid ones through fdroidcl, and reports the route for the rest
./apps.ts verify      # checks every route still carries what is declared
./apps.ts obtainium   # prints the URL list to paste into Obtainium on the device
./apps.ts adopt       # prints tsv lines for what is on the device but not declared, working out the route
./apps.ts aurora      # turns the play rows into JSON that Aurora Store can import as Favourites
```

Apps added on the device first, through Aurora Store or otherwise, are collected with `adopt`.
Doing it by hand means reading package IDs off the screen and copying them, so the route
detection is left to the machine:

```sh
./apps.ts adopt >>apps.tsv   # append, then read through and tidy up
```

Fetching the APK and running `adb install` is [fdroidcl](https://github.com/mvdan/fdroidcl)'s
job. What lives here is the declaration of what should be installed and the comparison against
what is.

`status` plays the same role as `windows/winget/status.ps1` and is called from
`just android-apps`. EXTRA, meaning something present but undeclared, does not fail: anything
tried out is going to be there, and whether to remove it is a person's decision. Only failing
to satisfy the declaration counts as a failure.

`verify` queries the F-Droid index, the GitHub API and the Play store page, catching typos and
sources that have moved. That is how `Catfriend1/syncthing-android` was found to have been
renamed to `researchxxl/`. GitHub is queried through `gh` if it is available, because the
unauthenticated API allows 60 requests an hour and hits the rate limit as the declaration grows.

**Updates on the device are Obtainium's job.** Its app list is `configs/android/obtainium.json`:
`droid obtainium push` puts it on the device for Obtainium's own import, and `droid obtainium
pull` brings changes made on the device back. `apps.ts obtainium` still prints a URL list
derived from `apps.tsv` for Import from URL List, but that covers only the `apps.tsv` rows.

Anything distributed only through Play goes to Aurora Store, which since 4.6 can import and
export Favourites and install them in bulk, so it is also a matter of handing over a file:

```sh
./apps.ts aurora >/tmp/aurora-favourites.json
adb push /tmp/aurora-favourites.json /sdcard/Download/
# on the device: Aurora Store, Favourites, Import, then install them all
```

The format matches Aurora Store's `data/room/favourite/{ImportExport,Favourite}.kt`.
`displayName` is just the package ID, since it is only a label and getting the real name would
mean one Play lookup per app, which is not worth it.

There are currently no `play` rows, which means every declared app arrives on the device through
a single Obtainium import. Even the `github` rows, which cannot be installed from the Mac, are
tracked and updated the same way once Obtainium has them. Only something available exclusively
on Play needs manual work, so when a GitHub distribution exists, prefer `github` over `play` —
Bitwarden was moved for exactly that reason, since its APK is on GitHub releases.

## OS settings

```sh
./os.sh --dry-run   # see what would change
./os.sh             # apply
```

The same file runs both over adb from the Mac and from inside the device, in Termux. Run it with
USB debugging on and exactly one device connected.

### Applying settings without a cable

Grant Termux `WRITE_SECURE_SETTINGS` once and it can write `settings` from the device
afterwards. That removes the Mac from the loop, so this part can be automated on the device,
from Termux:Boot or cron.

```sh
# once from the Mac. This is the only time a cable is needed.
adb shell pm grant com.termux.nix android.permission.WRITE_SECURE_SETTINGS

# afterwards, in Termux on the device
cd ~/.dotfiles/mobile/android && ./os.sh
```

It detects that it is on the device by `uname -o` returning `Android`, and runs without adb.

**Debloating and the per-app settings cannot work from the device.** `pm uninstall` needs
`DELETE_PACKAGES` and `pm grant` needs `GRANT_RUNTIME_PERMISSIONS`, both signature-level. They
work over adb because of the shell uid, and cannot be granted to an app's uid. Rather than
skipping them silently, the script says why, and those two are run from the Mac. Rows that
already match the current value are skipped, so running it repeatedly gives the same result.

- `os-settings.conf` — the global settings that live in the `settings` tables. Many toggles are
  not there and cannot be reached over adb at all, so those are set by hand.
- `os-apps.tsv` — per app: the default launcher, granting and revoking permissions, AppOps, and
  battery optimisation exemptions. Settings *inside* an app, such as accounts and sync targets,
  cannot be touched from outside by any means, so they are left to the app's own sync; see the
  table in `../README.md`.
- `os-debloat.txt` — this is `pm uninstall -k --user 0`, so the system partition is untouched
  and `adb shell cmd package install-existing <pkg>` brings anything back.

## Root (KernelSU)

`devices/<codename>/root/` declares the root layer of a rooted device, and `root.sh`
(`just android-root`, `--dry-run` to only show the difference) applies it. Only nabu has one.

| File | What it holds |
|---|---|
| `sources.json` | Upstream module zips (and what goes into them), pinned by URL and hash. `scripts/update-custom-packages.ts` moves the pins with the other custom packages |
| `modules/<id>/` | Modules written here, zipped as they are |
| `*.patch` | Changes to an upstream module |
| `features.conf` | `ksud feature` values, set and then saved so they survive a reboot |

`nix build ./nix#android-root-nabu` (`nix/mobile/android-root.nix`) assembles them into
`NN-<id>.zip` plus a `manifest.tsv`, numbered in install order. `root.sh` compares each
module's `versionCode` from its own `module.prop` with `ksud module list` on the device, then
pushes and `ksud module install`s whatever is missing or different. It does not reboot, which is
when the modules take effect, and it reports modules the declaration lacks without removing
them. A module written here is only reinstalled when its `versionCode` changes, so bump it with
every edit.

It runs `su` over adb, so the device needs KernelSU Next's ADB Root, or Shell allowed root in
its Superuser list.

Things learnt on nabu that the declaration encodes:

- **KernelSU 3.x (and KernelSU Next 3.x) mounts nothing by itself.** A module's `system/`
  directory is mounted only by a metamodule, so `meta-mm` (Magic Mount) is declared first.
- **The metamodule mounts read-only**, and AdAway's root mode has to write `/system/etc/hosts`.
  The hosts module therefore opts out with `skip_mount` and bind-mounts its file read-write
  from `post-fs-data.sh`. The upstream module overlays `/system/etc` instead, which overlayfs
  refuses here because the upper directory would sit on f2fs.
- **The audio HAL that loads effects is 32-bit**, so JamesDSP's library must be the 32-bit
  build. Its installer asks for that, and for the UI flavour, with the volume keys, which
  nobody presses during `ksud module install` from adb; `ainur_jamesdsp.patch` answers both.
  The UI slot gets the root-full JamesDSP build, which the module installs when the app is
  missing. The module also sets `global hidden_api_policy 1`, declared in nabu's
  `os-settings.conf`.

- **The boot animation is generated** from the active palette in `configs/theme/palettes.json`
  (`rosepine-bootanimation`, three dots in rose, iris and foam on the base colour). Its frames
  must be 8-bit PNGs: bootanimation silently draws nothing from the 16-bit ones ImageMagick
  writes by default. Its `versionCode` comes from the content, so a palette change reinstalls it.

The partition images taken before any of this (boot, vendor_boot, dtbo, vbmeta, persist and the
modem partitions) live outside the repository, in `~/Backups/xiaomi-pad5-nabu/`: they are large
and carry data unique to the device.

## Theming

Both devices take the Material You seed from the palette: `theme_customization_overlay_packages`
in `os-settings.conf` fixes it to rose-pine's iris instead of the wallpaper, and `test.sh` fails
when it drifts from `palettes.json`. Material You derives every tone from that one colour, so the
result leans towards iris rather than reproducing rose-pine; Kvaesitso's theme
(`launcher-theme.ts`) is the place where the palette is used colour for colour. The icon pack is
Arcticons' dayNight variant on both, applied from the launcher's own settings. On nabu the system
font, crDroid's bundled San Francisco, sits in the same setting: SystemUI's theme controller owns
the font overlays and, on every boot, disables any that the setting does not name, so enabling
one with `cmd overlay` does not survive a reboot. The status bar and quick settings are left to
crDroid's own settings rather than Iconify, which would overlap them and build a ROM-specific
module on the device that the declaration cannot hold.

## The launcher, Kvaesitso

Home screen layout and widget placement are not declared. Kvaesitso's backup is a binary with no
compatibility guarantee between versions, so putting it in the repository would show no
meaningful diff.

Two things are declared:

- **That it is the default launcher**, through the `home` row in `os-apps.tsv`, which runs
  `cmd package set-home-activity`.
- **The theme.** `launcher-theme.ts` generates a ThemeBundle v2 JSON from
  `configs/theme/palettes.json`, which is the same single source the Mac, tmux and Windows use,
  so replacing rose-pine changes the launcher along with everything else. Light and dark are
  both in the one theme, so it follows the device's appearance setting.

```sh
just android-launcher-theme   # generates it and pushes it to /sdcard/Download/
# on the device: Kvaesitso, Settings, Appearance, Theme, Import
```

## The CLI on the device, through nix-on-droid

The same zsh, git, tmux and CLI tools as the Mac, running on top of Termux. The configuration is
`nix/hosts/droid.nix`, sharing the git, cli, shell and terminal components in
`nix/modules/home/` unchanged. Components that assume a GUI, and components that depend on
modules from flake inputs such as nix-index and agent-skills, are not loaded.

The first time, install [Termux:Nix](https://f-droid.org/packages/com.termux.nix/) — the
nix-capable build, not ordinary Termux — and inside it run:

```sh
nix-on-droid switch --flake github:gapul/dotfiles?dir=nix#default
```

Updates use the same command. In CI, `nix run .#ci-nixondroid` on aarch64-linux builds the
activation package and no more.
