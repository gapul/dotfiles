{
  symlinkJoin,
  makeWrapper,
  cinny-desktop,
  gst_all_1,
}:
# WebKit aborts in createAudioSink when Cinny initializes notification sounds
# without autoaudiosink. The upstream wrapper only includes GStreamer core/base;
# good supplies autoaudiosink and the PulseAudio sink (also used by PipeWire).
symlinkJoin {
  name = "cinny-desktop-${cinny-desktop.version}-with-audio";
  paths = [ cinny-desktop ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/cinny" \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${gst_all_1.gst-plugins-good}/lib/gstreamer-1.0"
  '';
  inherit (cinny-desktop) meta;
}
