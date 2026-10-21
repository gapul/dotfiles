# Overlay (SSO) that absorbs temporary breakage in upstream nixpkgs.
# flake.nix's mkPkgs (standalone home), the nix-darwin systems (hosts/darwin-common.nix) and
# every NixOS host import this one file, so a fix lands everywhere at once.
#
# Every entry here is temporary: each says what would make it unnecessary, and is guarded
# (on a version or hash) where it can be, so an upstream bump turns it into a no-op rather
# than a stale override. Delete entries once the guard stops matching.
_final: prev: {
  # Determinate Nix 3.23 emits activity type 10113 (EvaluateFlakeDerivationOutput etc.), and
  # nom 2.2.0 rejects any type it does not know, so every nh rebuild printed
  # "ParseNixJSONMessageError ... invalid activity type: 10113". The patch is
  # maralorn/nix-output-monitor#321 (fixes #320; merged 2026-10-19, unreleased): unknown types become
  # Unknown instead of a parse error. Guarded on the version so a nom bump drops it; delete
  # it once #321 has landed in a release.
  nix-output-monitor =
    if prev.nix-output-monitor.version == "2.2.0" then
      prev.nix-output-monitor.overrideAttrs (o: {
        patches = (o.patches or [ ]) ++ [ ./nom-unknown-activity-type.patch ];
      })
    else
      prev.nix-output-monitor;

  # Qt 6.12's uic rejects the leading "::" in dictionary_tool.ui's custom widget class, so
  # mozc 2.30.5544.102 stopped building on nixos-unstable, and fcitx5-mozc and the laptop's
  # whole system with it (NixOS/nixpkgs#576522). This is upstream's fix
  # (google/mozc@29c082a). Guarded on the version so a mozc bump drops it.
  # It goes in postPatch, not patches: buildBazelPackage's deps fetch keeps its own copy of
  # the source attrs, so this leaves that fixed-output derivation and its hash alone.
  mozc =
    if prev.mozc.version == "2.30.5544.102" then
      prev.mozc.overrideAttrs (o: {
        postPatch = (o.postPatch or "") + ''
          substituteInPlace src/gui/dictionary_tool/dictionary_tool.ui \
            --replace-fail '::mozc::gui::DictionaryContentTableWidget' 'mozc::gui::DictionaryContentTableWidget'
        '';
      })
    else
      prev.mozc;

  # pyopenjtalk-plus 0.4.1-post9's test_run_njd_from_mecab_invalid_input_should_not_break_next_call
  # matches the TypeError text "must be str", which Python 3.14 words as "Expected str, got int".
  # Only the assertion's regex is stale; the behaviour it tests still holds. It took piper-tts and
  # calibre, and with them nixos-laptop, down on nixos-unstable (NixOS/nixpkgs#576442, open as of
  # 2026-10-21). Guarded on the version and on Python 3.14, so either moving drops it.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_pyFinal: pyPrev: {
      pyopenjtalk-plus =
        if
          pyPrev.pyopenjtalk-plus.version == "0.4.1-post9"
          && prev.lib.versionAtLeast pyPrev.python.version "3.14"
        then
          pyPrev.pyopenjtalk-plus.overridePythonAttrs (o: {
            disabledTests = (o.disabledTests or [ ]) ++ [
              "test_run_njd_from_mecab_invalid_input_should_not_break_next_call"
            ];
          })
        else
          pyPrev.pyopenjtalk-plus;
    })
  ];
}
