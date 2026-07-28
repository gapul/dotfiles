# 有料/非公開ソフトを「自己ビルドで無料フル」にする — 個人ガイド

FOSS だが「公式バイナリは有料 or App Store 非公開」なソフトを、ソースから自分でビルドして
無料フル版を手に入れ、**このMacの dotfiles で宣言管理**するための実戦ノート。
2026-07 に Zrythm / ArmorPaint / Fritzing / Ardour / Aseprite / Inochi Creator / (iOS) を
実際にやった手順をパターン化したもの。

## 0. 要するに

- **公式バイナリは有料でも、ソースが自由(GPL/zlib 等)なら自分でビルドすれば無料でフル機能**
  (Ardour モデル)。Aseprite のように source-available で「自分でビルドは無料」も同じ。
- macOS では **「そのソフトの依存の性質」で入れ方が一意に決まる**。iOS は sideload。
- 入れたら **dotfiles(nix / homebrew)で宣言管理**、または再現スクリプト化する。

## 1. 判断フレーム(どの手法を選ぶか)

| 状況 | 手法 | 例 |
|---|---|---|
| nixpkgs にあり **darwin OK**(有料→nixは無料フル) | **型A: 純nix(home.packages に足す)** | Fritzing / Ardour / Aseprite |
| nixpkgs にあるが **darwin broken** | **型B: nix 自作パッケージ移植** | Zrythm |
| **Apple/Metal/Xcode 縛り**のビルド | **型C: Homebrew source-build tap 自作** | ArmorPaint |
| 無料の公式バイナリ有・nixpkgs darwin 不可 | **型D: cask tap 自作** | Inochi Creator |
| サーバ型 | homelab(Proxmox CT に自己ホスト) | Nakama / Weblate / Penpot |
| **iOS で有料 or 非公開** | **型E: Xcode ビルド + AltStore PAL** | Blink Shell / KeePassium |

**原則**: 依存が自己完結する GTK/Qt 系 → nix が最適(宣言的・再現的)。
Apple ツールチェーン(xcodebuild / metallib)に縛られる → Homebrew が最適(system Xcode 前提で動く)。

---

## 2. 型ごとの再現手順

### 型A: 純nix で足すだけ(nixpkgs darwin OK)

`nix/home/darwin.nix` の `home.packages` に足すだけ。unfree(Aseprite 等)は `allowUnfree`。

```nix
# 有料だが nixpkgs のソースビルド=無料フルになるものを足す。
# 26.05-darwin で未提供/broken なら nixos-unstable を使う(zrythm 用に足した input を流用)。
# aseprite は unfree のため allowUnfree 付きで再インスタンス化。
let
  unstablePkgs = import nixpkgsUnstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  home.packages = with pkgs; [
    unstablePkgs.fritzing  # cache済で即
    unstablePkgs.ardour    # cache済で即
    unstablePkgs.aseprite  # unfree=source build
  ];
}
```

- `allowUnfree` はこの Mac では `hosts/darwin-common.nix` に `nixpkgs.config.allowUnfree = true` で
  既に有効。ただし `nixpkgsUnstable.legacyPackages` は別インスタンスなので上記の再構成が要る。
- cache 済みか実ビルドかは `nix build --dry-run nixpkgs#<pkg>` で確認(fetched=cache / built=実ビルド)。

### 型B: nix 自作パッケージ移植(nixpkgs で darwin broken)

**例: Zrythm**(→ `nix/pkgs/zrythm-darwin/`)。nixpkgs の派生を `overrideAttrs` で darwin 向けに直す。

踏んだ罠と対処(darwin GTK アプリの定番):
1. `--buildtype=plain` の nixpkgs 既定は **最適化なし** → `mesonBuildType = "debugoptimized"`(=-O2)。
2. `broken = isDarwin` → `meta.broken = false`。
3. Linux 専用依存(alsa/pulse/jack)を `buildInputs` から除去 + meson で `-Djack=disabled` 等。
4. **install_name がバラ名の dylib** → 起動時 `dyld: Library not loaded` → `install_name_tool -id <abs>`。
   Apple Silicon は改変で **ad-hoc 署名が壊れる** → `codesign --force --sign -`(要 `nativeBuildInputs += pkgs.darwin.sigtool`)。
5. **SVG アイコンが出ない** → `GDK_PIXBUF_MODULE_FILE`(librsvg 込みの loaders.cache)を wrapper に。
6. **設定が保存されない**(machine-id 不在) → `GSETTINGS_BACKEND=keyfile` を wrapper に。
7. GTK4 macos backend は `quartz` でなく `macos` → `GDK_BACKEND=macos` を既定注入。
8. 土台の nixpkgs は **nixos-unstable pin**(26.05-darwin は gtk4 の ld64 クラッシュ/appstream 破損があった)。

検証: `nix build` → `result/bin/xxx --version` が dyld エラー無しで走ること。

### 型C: Homebrew source-build tap 自作(Apple/Metal 縛り)

**例: ArmorPaint**(xcodebuild + Metal 依存 → nix と相性×、Homebrew と◎)。

```bash
# 1) tap repo を作る
mkdir -p ~/tmp/homebrew-armorpaint/Formula && cd ~/tmp/homebrew-armorpaint
# Formula/armorpaint.rb を書く(下記テンプレ)
git init && git add -A && git commit -m init
gh repo create gapul/homebrew-armorpaint --public --source=. --push

# 2) ローカルテスト(母艦の brew は tap 信頼で止まるので env で回避)
HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install --build-from-source gapul/armorpaint/armorpaint
```

Formula テンプレ(ソースビルド):
```ruby
class Armorpaint < Formula
  desc "..."; homepage "https://armorpaint.org"
  url "https://github.com/armory3d/armorpaint.git", revision: "<sha>"
  version "23.09-2477"; license "Zlib"
  depends_on xcode: :build   # Metal shader コンパイルに Xcode 必須
  def install
    cd "paint" do
      system "../base/make", "--compile"          # 内蔵 amake が xcodebuild をヘッドレス起動
      prefix.install "build/build/Release/ArmorPaint.app"
    end
  end
end
```
- `darwin.nix` の `taps` に `"gapul/armorpaint"`、`brews` に `"gapul/armorpaint/armorpaint"` を追加。
- 成果物は cask と違い `$(brew --prefix)/opt/armorpaint/ArmorPaint.app`(/Applications ではない)。

### 型D: cask tap 自作(無料の公式バイナリ有)

**例: Inochi Creator**(無料だが homebrew/cask 未収録・nixpkgs darwin broken → 公式 .dmg を cask 化)。

```ruby
cask "inochi-creator" do
  version "0.8.6"
  sha256 "<shasum -a 256 の値>"
  url "https://github.com/Inochi2D/inochi-creator/releases/download/v#{version}/Install_Inochi_Creator.dmg"
  name "Inochi Creator"; homepage "https://inochi2d.com/"
  app "Inochi Creator.app"   # dmg 内の .app 名。違えば brew install がエラーで教える
end
```
- sha256 は `curl -L -o x.dmg <url> && shasum -a 256 x.dmg`。
- `gh repo create gapul/homebrew-inochi --public --source=. --push` → `darwin.nix` の taps + casks に追加。
- cask なので `/Applications` に入る。

### 型E: iOS(有料 or 非公開)

**例: Blink Shell($20 GPL)/ KeePassium(premium は自己ビルドで無料)**。

前提(この環境): **AltStore PAL(日本の代替マーケット)+ Apple Developer Program**。
→ **1年署名**(無料 Apple ID の7日再署名が不要)、マーケット経由で**自動更新**可。

段取り:
1. **ビルド検証**(署名不要): Simulator で動くか。
   ```bash
   git clone https://github.com/keepassium/KeePassium && cd KeePassium
   xcodebuild -workspace KeePassium.xcworkspace -scheme KeePassium \
     -sdk iphonesimulator -configuration Release \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
     CODE_SIGNING_ALLOWED=NO build
   ```
   KeePassium は依存同梱・Xcode で開くだけ。README に「build your personal premium version for free」明記。
2. **署名して .ipa 化**: ローカル証明書が失効していたら再生成(Xcode > Settings > Accounts、or
   App Store Connect API キー `~/.appstoreconnect/private_keys` で自動署名)。Team = KQZ7J45NTN。
3. **AltStore ソース化(自動更新の肝)**: .ipa を CF Pages/R2 か homelab にホストし、
   AltSource の JSON(版・URL・sha)を作る → iPhone の **AltStore PAL に「ソース追加」**。
   以降 AltStore PAL がそこから自動更新+署名管理。
4. **上流追従の完全自動化**(stretch): 上流リリース→CI(GitHub Actions の macOS runner)で再ビルド→
   AltSource JSON を更新、まで組むと手放しで最新化。

注意: AltStore PAL のマーケット配布アプリは Apple の**公証(notarization)**が要る場合がある。
無料 Apple ID + AltStore(非PAL)なら7日再署名・3アプリ制限(LiveContainer で回避)。

---

## 3. 共通の罠と対処

- **CI lint は push 前にローカルで**: `cd nix && nix fmt -- <file>` と
  `nix run nixpkgs#statix -- check -c ../.statix.toml .`(rc=0)を必ず通す。
  自分/agent が書いた nix は未整形・inherit 指摘で CI が落ちがち(実際 zrythm で2回落ちた)。
- **Homebrew tap trust**(Homebrew 6.0 で既定 true 化):
  - 宣言 rebuild: `homebrew.onActivation.extraEnv.HOMEBREW_NO_REQUIRE_TAP_TRUST = "1"`(darwin.nix に設定済)。
  - 手動 install: `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install ...`(qmk 等の未信頼 tap で止まるのを回避)。
- **taps conflict**: 複数 PR が同じ taps 位置に足すと merge 時 conflict → 両方残して解消
  (`git merge origin/main` → 手で両行残す → commit)。
- **重いビルドは macmini 自走**: `CLAUDE_CODE_OAUTH_TOKEN`(`claude setup-token` → sops)を env で渡し
  headless claude をループさせて反復ビルドを回せる(ssh 越し keychain は不可、env 必須)。詳細は
  memory `macmini-headless-claude-auth`。
- **nixpkgs は 26.05 より nixos-unstable**: darwin の GTK/appstream スタックは unstable の方が成熟。

## 4. 成果物の場所(このリポ/tap/PR)

| ソフト | 手法 | 場所 |
|---|---|---|
| Zrythm | 型B 純nix移植 | `nix/pkgs/zrythm-darwin/`(PR #66) |
| ArmorPaint | 型C Homebrew source-build | tap `gapul/homebrew-armorpaint`(PR #74) |
| Fritzing / Ardour / Aseprite | 型A 純nix | `nix/home/darwin.nix`(PR #77) |
| Inochi Creator | 型D cask | tap `gapul/homebrew-inochi`(PR #77) |
| Blink / KeePassium (iOS) | 型E Xcode + AltStore | `~/tmp/ios-selfbuild/`(作業中) |

関連 memory: `zrythm-darwin-nix-port`, `armorpaint-selfbuild`, `macmini-headless-claude-auth`,
`nix-darwin-homebrew-declarative`。
