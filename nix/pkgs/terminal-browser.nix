# terminal-browser (zenbu-labs): a real browser that runs inside the terminal.
#
# The point of it here is the agent side rather than the browsing: `terminal-browser action` is an
# agent-facing CLI over whatever browsers are open, so an agent gets the web without the Claude in
# Chrome extension and without a visible Chrome window. It also opens in a split pane beside the
# agent and works over ssh, which the extension path cannot do.
#
# Upstream ships `curl -fsSL https://terminal-browser.sh/install | bash`. That is the thing this
# package exists to avoid: the installer writes into $HOME and self-updates (`terminal-browser
# upgrade`), so the version would be whatever the last run left behind. Here it is whatever
# flake.lock says.
#
# The tarball bundles its own Electron, so it is 307MB unpacked and nothing is built from source —
# the shipped binaries are copied as-is, which also leaves their signatures untouched.
{
  lib,
  stdenvNoCC,
  fetchurl,
  plemoljp,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "terminal-browser";
  version = "0.7.5";

  src = fetchurl {
    url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${finalAttrs.version}/terminal-browser-darwin-arm64.tar.gz";
    hash = "sha256-Wnnrf3sl1BhpdfdYR0BAIw0ZnbqsNEXW8exTftrlWuc=";
  };

  # An Electron bundle: patching anything in it would only break code signatures, and the
  # shebangs it does have already point at /bin/sh.
  dontPatchShebangs = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    # stdenv の unpackPhase が tar の唯一の最上位ディレクトリ (terminal-browser/) に自動で
    # 降りるので、ここでの cwd は既にその中。`cp -R terminal-browser` は空振りする。
    # 同梱 Electron の署名を守るため、AppleDouble のサイドカーを落としてから運ぶ。
    # tar が ._default_app.asar のような実ファイルを書き出し、署名が封印していない
    # ファイルが増えるので `codesign -v` が落ちる (pkgs/keebmouse.nix と同じ罠)。
    # ここでは実害が分かりやすく、署名が壊れた Electron は起動せず --help すら返さない。
    find . -name '._*' -delete
    find . -name '.DS_Store' -delete
    mkdir -p $out/libexec/terminal-browser $out/bin
    cp -R . $out/libexec/terminal-browser/
    # bin/terminal-browser is a /bin/sh wrapper that resolves its own symlink to find the bundle,
    # so a plain symlink onto PATH is all that is needed — it follows the link back to $out.
    ln -s $out/libexec/terminal-browser/bin/terminal-browser $out/bin/terminal-browser

    # タブバーとツールバーは Chromium ではなく自作のネイティブ描画モジュール
    # (browser/native/pixel.node) が描いていて、そこに登録されるフォントは
    # assets/fonts/JetBrainsMono-Regular.ttf ただ 1 本。フォールバックの連鎖が無いので、
    # CJK を持たないこのフォントだと日本語のタイトルが全部豆腐になる (本文は Chromium が
    # CoreText 経由で描くので正しく出る、という分かりにくい壊れ方をする)。
    # パスが決め打ちなので、同じ名前で CJK を持つ等幅に差し替えれば直る。PlemolJP は
    # JetBrains Mono に IBM Plex Sans JP を合わせたものなので、欧文の見た目が変わらない。
    # assets/ は .app の外にあるため、ここを触っても同梱 Electron の署名には影響しない。
    install -m444 ${plemoljp}/share/fonts/truetype/plemoljp/PlemolJP-Regular.ttf \
      $out/libexec/terminal-browser/assets/fonts/JetBrainsMono-Regular.ttf

    runHook postInstall
  '';

  meta = {
    description = "A real browser that runs inside your terminal";
    homepage = "https://github.com/zenbu-labs/terminal-browser";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "terminal-browser";
  };
})
