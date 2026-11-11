{
  appimageTools,
  fetchurl,
  lib,
}:
let
  pname = "flare";
  version = "1.8.0";
  src = fetchurl {
    url = "https://github.com/flaresocialapp/Flare/releases/download/${version}/Flare-${version}.AppImage";
    hash = "sha256-1u/Acflnj6pZF/YtBygp45OgX48eK3GpaJxR7IWyzGo=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  # Compose Desktop with its own JRE; the in-app browser (login flows) is wry on WebKitGTK and
  # the media player goes through GStreamer, neither of which the AppImage bundles.
  extraPkgs = pkgs: [
    pkgs.webkitgtk_4_1
    pkgs.libsoup_3
    pkgs.gst_all_1.gstreamer
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
    pkgs.gst_all_1.gst-plugins-bad
    pkgs.gst_all_1.gst-libav
  ];
  extraInstallCommands = ''
    install -Dm444 ${contents}/Flare.desktop $out/share/applications/flare.desktop
    substituteInPlace $out/share/applications/flare.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox' 'Exec=flare --no-sandbox'
    cp -r ${contents}/usr/share/icons $out/share/
  '';
  meta = {
    description = "Mastodon, Misskey, Bluesky, X, Nostr and RSS in one timeline";
    homepage = "https://github.com/flaresocialapp/Flare";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "flare";
  };
}
