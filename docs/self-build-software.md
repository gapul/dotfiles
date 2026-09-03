# Building paid or unlisted software yourself

Field notes on taking software that is free in source but paid or App Store-absent as a binary,
building it from source to get the full version at no cost, and then declaring it in this Mac's
dotfiles. Written up from doing it to Zrythm, ArmorPaint, Fritzing, Ardour, Aseprite, Inochi
Creator and a couple of iOS apps in July 2026.

## The short version

- If the official binary costs money but the source is free (GPL, zlib and so on), building it
  yourself gives you the full thing for nothing. This is the Ardour model. Source-available
  projects like Aseprite, where building it yourself is explicitly free, work the same way.
- On macOS the nature of the dependencies decides how to install it, with almost no room for
  preference. iOS is sideloading.
- Once it is in, declare it through nix or homebrew, or make the build reproducible in a script.

## Choosing an approach

| Situation | Approach | Examples |
|---|---|---|
| In nixpkgs and darwin works; paid upstream, free through nix | **A: plain nix, add to `home.packages`** | Fritzing, Ardour, Aseprite |
| In nixpkgs but darwin is broken | **B: port it into your own nix package** | Zrythm |
| The build is tied to Apple, Metal or Xcode | **C: your own Homebrew source-build tap** | ArmorPaint |
| A free official binary exists but nixpkgs darwin does not work | **D: your own cask tap** | Inochi Creator |
| Server software | Self-host it in the homelab | Nakama, Weblate, Penpot |
| Paid or unlisted on iOS | **E: build in Xcode, distribute through AltStore PAL** | Blink Shell, KeePassium |

The rule underneath: GTK and Qt software with self-contained dependencies belongs in nix, which
is declarative and reproducible. Anything bound to the Apple toolchain — `xcodebuild`,
`metallib` — belongs in Homebrew, which assumes the system Xcode and works with it.

---

## The approaches in detail

### A: plain nix, when darwin already works

Add it to `home.packages` in `nix/home/darwin.nix`. Unfree packages such as Aseprite need
`allowUnfree`.

```nix
# Things that cost money upstream but are a free full build through nixpkgs.
# If 26.05-darwin does not ship it or it is broken, take it from nixos-unstable
# (reusing the input added for zrythm). aseprite is unfree, so the tree is
# re-instantiated with allowUnfree.
let
  unstablePkgs = import nixpkgsUnstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  home.packages = with pkgs; [
    unstablePkgs.fritzing  # cached, installs immediately
    unstablePkgs.ardour    # cached, installs immediately
    unstablePkgs.aseprite  # unfree, built from source
  ];
}
```

`allowUnfree` is already on for this Mac through `nixpkgs.config.allowUnfree = true` in
`hosts/darwin-common.nix`, but `nixpkgsUnstable.legacyPackages` is a separate instance, which is
why it is rebuilt above.

To find out whether something is cached or will really be built, run
`nix build --dry-run nixpkgs#<pkg>`: "fetched" means cache, "built" means a real build.

### B: porting it yourself, when nixpkgs marks darwin broken

Zrythm, in `nix/pkgs/zrythm-darwin/`, fixes the nixpkgs derivation for darwin through
`overrideAttrs`. The problems hit along the way are the usual ones for a GTK app on darwin:

1. The nixpkgs default `--buildtype=plain` means no optimisation. Set
   `mesonBuildType = "debugoptimized"`, which is `-O2`.
2. `broken = isDarwin`. Set `meta.broken = false`.
3. Linux-only dependencies (alsa, pulse, jack) have to come out of `buildInputs`, with
   `-Djack=disabled` and friends passed to meson.
4. dylibs whose `install_name` is a bare filename produce `dyld: Library not loaded` at
   startup. Fix with `install_name_tool -id <abs>`. On Apple Silicon that edit breaks the
   ad-hoc signature, so follow it with `codesign --force --sign -`, which needs
   `pkgs.darwin.sigtool` in `nativeBuildInputs`.
5. Missing SVG icons mean the wrapper needs `GDK_PIXBUF_MODULE_FILE`, pointing at a
   loaders.cache that includes librsvg.
6. Settings that never persist means there is no machine-id. Put `GSETTINGS_BACKEND=keyfile` in
   the wrapper.
7. The GTK4 macOS backend is called `macos`, not `quartz`. Inject `GDK_BACKEND=macos`.
8. Build against nixos-unstable rather than 26.05-darwin, which had a gtk4 ld64 crash and a
   broken appstream.

To check the result: `nix build`, then `result/bin/xxx --version` should run without dyld
errors.

### C: your own Homebrew source-build tap, for Apple-bound builds

ArmorPaint needs xcodebuild and Metal, which fits Homebrew and fights nix.

```bash
# 1. create the tap
mkdir -p ~/tmp/homebrew-armorpaint/Formula && cd ~/tmp/homebrew-armorpaint
# write Formula/armorpaint.rb, see below
git init && git add -A && git commit -m init
gh repo create gapul/homebrew-armorpaint --public --source=. --push

# 2. test locally. The Mac's brew stops on tap trust, so work around it here.
HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install --build-from-source gapul/armorpaint/armorpaint
```

The formula:

```ruby
class Armorpaint < Formula
  desc "..."; homepage "https://armorpaint.org"
  url "https://github.com/armory3d/armorpaint.git", revision: "<sha>"
  version "23.09-2477"; license "Zlib"
  depends_on xcode: :build   # Xcode is required to compile the Metal shaders
  def install
    cd "paint" do
      system "../base/make", "--compile"   # the bundled amake drives xcodebuild headlessly
      prefix.install "build/build/Release/ArmorPaint.app"
    end
  end
end
```

Add `"gapul/armorpaint"` to `taps` and `"gapul/armorpaint/armorpaint"` to `brews` in
`darwin.nix`. Unlike a cask, the result lands in
`$(brew --prefix)/opt/armorpaint/ArmorPaint.app`, not `/Applications`.

### D: your own cask tap, when a free official binary exists

Inochi Creator is free but is not in homebrew/cask and is broken in nixpkgs on darwin, so the
official .dmg gets wrapped in a cask.

```ruby
cask "inochi-creator" do
  version "0.8.6"
  sha256 "<from shasum -a 256>"
  url "https://github.com/Inochi2D/inochi-creator/releases/download/v#{version}/Install_Inochi_Creator.dmg"
  name "Inochi Creator"; homepage "https://inochi2d.com/"
  app "Inochi Creator.app"   # the .app name inside the dmg. Get it wrong and brew install says so.
end
```

Get the sha256 with `curl -L -o x.dmg <url> && shasum -a 256 x.dmg`, then
`gh repo create gapul/homebrew-inochi --public --source=. --push` and add it to `taps` and
`casks` in `darwin.nix`. Being a cask, it installs into `/Applications`.

### E: iOS, for paid or unlisted apps

Blink Shell costs $20 and is GPL; KeePassium's premium features are free if you build it
yourself.

The setup here is AltStore PAL, the alternative marketplace available in Japan, plus an Apple
Developer Program membership. That gives year-long signing instead of the seven-day re-signing
a free Apple ID forces, and automatic updates through the marketplace.

1. **Check it builds**, without signing, by running it in the Simulator.

   ```bash
   git clone https://github.com/keepassium/KeePassium && cd KeePassium
   xcodebuild -workspace KeePassium.xcworkspace -scheme KeePassium \
     -sdk iphonesimulator -configuration Release \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
     CODE_SIGNING_ALLOWED=NO build
   ```

   KeePassium vendors its dependencies and opens in Xcode as-is. Its README says outright that
   you may build your personal premium version for free.

2. **Sign it and produce an .ipa.** If the local certificate has expired, regenerate it through
   Xcode > Settings > Accounts, or automate signing with an App Store Connect API key in
   `~/.appstoreconnect/private_keys`. Team is KQZ7J45NTN.

3. **Turn it into an AltStore source**, which is what makes updates automatic. Host the .ipa on
   Cloudflare Pages, R2 or the homelab, write an AltSource JSON with version, URL and hash, and
   add that source in AltStore PAL on the phone. From then on AltStore PAL handles updates and
   signing.

4. **Follow upstream automatically**, if you want to go further: an upstream release triggers a
   rebuild on a GitHub Actions macOS runner, which updates the AltSource JSON.

One caveat: apps distributed through AltStore PAL may need Apple notarization. With a free
Apple ID and non-PAL AltStore you get seven-day re-signing and a three-app limit, which
LiveContainer can work around.

---

## Problems that come up regardless

- **Run the CI lint locally before pushing.** `cd nix && nix fmt -- <file>` and
  `nix run nixpkgs#statix -- check -c ../.statix.toml .` should both return 0. Hand-written nix
  tends to fail CI on formatting or an `inherit` suggestion — zrythm failed twice this way.
- **Homebrew tap trust**, which became the default in Homebrew 6.0. For declarative rebuilds,
  `homebrew.onActivation.extraEnv.HOMEBREW_NO_REQUIRE_TAP_TRUST = "1"` is already set in
  darwin.nix. For manual installs, `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install ...`
  gets past untrusted taps such as qmk's.
- **Conflicting taps.** Two pull requests adding to the same place in `taps` conflict on merge.
  Resolve by keeping both lines: `git merge origin/main`, edit, commit.
- **Heavy builds go to the mac mini.** Pass `CLAUDE_CODE_OAUTH_TOKEN` (from
  `claude setup-token`, stored in sops) through the environment and loop a headless claude for
  iterative builds. Keychain access over ssh does not work, so the environment variable is
  required.
- **Prefer nixos-unstable over 26.05.** The GTK and appstream stack on darwin is more mature
  there.

## Where the results live

| Software | Approach | Location |
|---|---|---|
| Zrythm | B, ported into nix | `nix/pkgs/zrythm-darwin/`, PR #66 |
| ArmorPaint | C, Homebrew source build | tap `gapul/homebrew-armorpaint`, PR #74 |
| Fritzing, Ardour, Aseprite | A, plain nix | `nix/home/darwin.nix`, PR #77 |
| Inochi Creator | D, cask | tap `gapul/homebrew-inochi`, PR #77 |
| Blink, KeePassium (iOS) | E, Xcode and AltStore | `~/tmp/ios-selfbuild/`, in progress |
| keebmouse (mine) | D, cask | tap `gapul/homebrew-tap`; the source repo is private, so only the build output goes in the tap |

keebmouse goes to `/Applications` rather than the nix store because its TCC grant, for
accessibility, is tied to the path and the code signature. `scripts/dist.sh` builds from HEAD
outside the working tree, signs with a Developer ID, notarizes, attaches a zip to a release in
the tap, rewrites the cask's version and sha256, and pushes. As long as the signing identity
does not change, the permission survives. The resident agent is declared in
`nix/modules/home/darwin-chrome.nix`.
