// Surfingkeys settings for Firefox Developer Edition. Loaded by the extension from this
// file's raw.githubusercontent.com URL ("Load settings from" in advanced mode), so edits
// here reach the browser on its next start; nothing is set in the extension's own UI.
// Path: configs/apps/surfingkeys/config.js. Declared next to the browser in nix/modules/home/darwin-firefox.nix.

const { mapkey, Front } = api;

// Video playback speed. Replaces the Global Speed extension (non-FOSS).
const rate = (delta) => {
  const v = document.querySelector("video");
  if (!v) { Front.showBanner("no <video> here"); return; }
  v.playbackRate = Math.max(0.25, Math.round((v.playbackRate + delta) * 4) / 4);
  Front.showBanner(`speed ${v.playbackRate}x`);
};
mapkey(">", "Video: speed up", () => rate(0.25));
mapkey("<", "Video: slow down", () => rate(-0.25));
mapkey("=", "Video: reset speed", () => rate(1 - document.querySelector("video")?.playbackRate));
