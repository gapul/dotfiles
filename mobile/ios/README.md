# iOS

iOS has no equivalent of adb, and without supervised mode, meaning supervising the device with
Apple Configurator, nothing can be pushed in from outside. Installing cannot be automated, but
checking what is installed and generating what gets installed can be, so those are what lives
here.

```
ios/
├── apps.tsv          # which apps to install: bundleId, how to get it, how it syncs
├── sources.tsv       # the URLs of the AltStore sources, Classic and PAL
├── apps.sh           # status | verify
├── test.sh           # self-check for apps.sh, against a fake ideviceinstaller, no device needed
└── profiles/serve.sh # serves the .mobileconfig files nix generated over the LAN
```

The contents of the profiles are in `nix/mobile/ios-profiles.nix`.

## Apps

```sh
./apps.sh status   # the declaration against a USB-connected iPhone. Exits 1 if anything is MISSING
./apps.sh verify   # checks each declared bundleId still exists on its route, across all three
```

Three routes are in use, so the `source` column in `apps.tsv` says which one handles each app.

| source | Where it comes from | What verify queries |
|---|---|---|
| `appstore` | The App Store | The iTunes Search API |
| `altstore-classic` | Self-built, re-signed on the Mac | The JSON of the classic source in `sources.tsv` |
| `altstore-pal` | AltStore PAL, the alternative marketplace | The pal source in the same file |

`status` queries the device through `ideviceinstaller`, so it needs USB and "Trust this
Computer" on the phone. There is no way to query it over the network.

Installing cannot be automated. Both the App Store and PAL want a signed ipa, so it is done by
hand, which makes `status` a way of counting what is left to reinstall.

**Re-signing a self-built app changes its bundleId.** The App Store's `com.keepassium.ios` and
the self-built `net.gapul.keepassium` are different apps as far as the device is concerned, so
declare whichever is actually installed. `verify` compares against the source's JSON, so getting
this wrong makes it fail.

The signed self-builds are distributed through
[gapul/altstore-source](https://github.com/gapul/altstore-source), which is `gapul-selfbuild` in
`sources.tsv`. How they are built is in `docs/self-build-software.md`.

## Configuration profiles

A `.mobileconfig` is only an XML plist, so the payloads are written as a nix attrset and run
through `pkgs.formats.plist`, in `nix/mobile/ios-profiles.nix`.

```sh
nix build ./nix#ios-profiles   # generate them
./profiles/serve.sh            # serve them on the LAN; this builds them too
```

Open the printed URL in Safari on an iPhone on the same LAN, and after it downloads it appears
in Settings under "Profile Downloaded". No other browser leads anywhere.

The PayloadUUID is derived deterministically from a hash of the name. If it changed each time,
every update would pile up on the device as a separate profile.

Anything a vendor distributes ready-signed is not written here. NextDNS's DNS profile and
Tailscale's VPN profile both come from upstream and install as trusted, which is better. Only
the things nobody distributes get declared.

| Purpose | Where it comes from |
|---|---|
| CalDAV and CardDAV for the Radicale at home | `nix/mobile/ios-profiles.nix`, because nobody distributes one. The target is the `dav` vhost created by the `sites` table in `hosts/homeserver.nix` |
| DNS, through NextDNS | Open `https://apple.nextdns.io/<profile-id>` in Safari |
| The tailnet at home | The Tailscale app installs its own VPN profile |

## Shortcuts

Shortcuts move between the phone and the Mac through iCloud, so reading the Mac's
`~/Library/Shortcuts/Shortcuts.sqlite` gets at their contents without connecting a device. They
are plain bplist and are not encrypted.

```sh
./shortcuts.sh export   # writes the Mac's Shortcuts out into shortcuts/*.plist
./shortcuts.sh status   # what has been exported against what the Mac has
./shortcuts.sh build    # turns shortcuts/*.cherri into signed .shortcut files
```

Exporting is for backup and review. A shortcut exists only in iCloud, and if it goes there is
nothing to restore from. Written out as XML plist, the diffs are readable too.

New ones are written with [Cherri](https://github.com/electrikmilk/cherri), a compiler in Go
that turns text straight into a signed `.shortcut`, an AEA1 container. It has a flake, so
`nix run` is enough.

**A hand-built plist will not pass `shortcuts sign`.** XML or binary, minimal or with every
currently required key present, it was rejected either way. So unlike the mobileconfig files
these cannot be assembled in nix, and Cherri does it instead.

A `.shortcut` from `build` goes into the Mac's Shortcuts with `open`, and iCloud carries it to
the phone. No cable involved.

## The CLI on the device

**No environment is built on iOS.** iSH emulates i386 and is slow, and a-Shell's sandbox means
it never quite becomes a normal Unix. Either would mean maintaining a second set of
configuration to carry the Mac's setup across.

Instead, [Blink Shell](https://blink.sh) connects to the Mac over the tailnet:

```sh
ssh macmini    # or homeserver
nssh <host>    # nvim, yazi and tmux through rootless nix, with the usual configuration
```

The configuration `nssh` leaves behind is `configs/shell/zshrc.remote`, and the parts shared
with the Mac come from reading `configs/shell/zshrc.common` directly. So the shell is the same
one whether you arrive from the phone or not.

Blink's own settings — key mappings, host definitions — are locked inside the app and cannot be
extracted, so they are outside declarative management. SSH keys are generated per device in
Blink and only the public key is distributed; the Mac's key never leaves the Mac.
