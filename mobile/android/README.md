# Android

```
android/
├── apps.tsv            # which apps to install: packageId plus the route
├── apps.sh             # status | install | verify | obtainium
├── os-settings.conf    # global settings applied through settings put
├── os-apps.tsv         # per-app OS settings: default launcher, permissions, battery
├── os-debloat.txt      # preinstalled apps to remove from user 0
├── os.sh               # applies the three above over adb, showing the difference first
├── launcher-theme.py   # generates Kvaesitso's theme from palettes.json
└── test.sh             # self-check for the scripts above, against a fake adb, no device needed
```

## Apps

Three stores are in use, so the `source` column in `apps.tsv` says which one handles each app.

| source | Distributed by | Installable from the Mac | Updated on the device by |
|---|---|---|---|
| `fdroid` | F-Droid | Yes, `apps.sh install` | Obtainium or F-Droid |
| `izzy` | IzzyOnDroid | Yes, the same | Obtainium |
| `github` | GitHub releases | No | Obtainium |
| `play` | The Play Store | No | Aurora Store, importing Favourites and installing them in one go |

```sh
./apps.sh status      # declaration against the device. Exits 1 if anything is MISSING
./apps.sh install     # installs the F-Droid ones through fdroidcl, and reports the route for the rest
./apps.sh verify      # checks all four routes still carry what is declared
./apps.sh obtainium   # prints the URL list to paste into Obtainium on the device
./apps.sh adopt       # prints tsv lines for what is on the device but not declared, working out the route
./apps.sh aurora      # turns the play rows into JSON that Aurora Store can import as Favourites
```

Apps added on the device first, through Aurora Store or otherwise, are collected with `adopt`.
Doing it by hand means reading package IDs off the screen and copying them, so the route
detection is left to the machine:

```sh
./apps.sh adopt >>apps.tsv   # append, then read through and tidy up
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

**Updates on the device are Obtainium's job.** Paste the URL list from `apps.sh obtainium` into
the app under Import/Export, Import from URL List. The URLs follow mechanically from the package
ID and ref, so there is no separate file listing them.

Anything distributed only through Play goes to Aurora Store, which since 4.6 can import and
export Favourites and install them in bulk, so it is also a matter of handing over a file:

```sh
./apps.sh aurora >/tmp/aurora-favourites.json
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

## The launcher, Kvaesitso

Home screen layout and widget placement are not declared. Kvaesitso's backup is a binary with no
compatibility guarantee between versions, so putting it in the repository would show no
meaningful diff.

Two things are declared:

- **That it is the default launcher**, through the `home` row in `os-apps.tsv`, which runs
  `cmd package set-home-activity`.
- **The theme.** `launcher-theme.py` generates a ThemeBundle v2 JSON from
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
