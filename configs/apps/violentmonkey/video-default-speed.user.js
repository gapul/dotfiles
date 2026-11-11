// ==UserScript==
// @name        video-default-speed: per-site default playback speed
// @namespace   https://github.com/gapul/dotfiles
// @version     0.1.0
// @description Starts every video on listed sites at a default speed; changing it mid-video (site menu, Surfingkeys < > =) sticks until the next video.
// @match       *://*.youtube.com/*
// @match       *://*.youtube-nocookie.com/*
// @grant       none
// @run-at      document-start
// @downloadURL https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/video-default-speed.user.js
// @updateURL   https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/video-default-speed.user.js
// ==/UserScript==

// Plain DOM and @grant none, so it runs the same under Violentmonkey in Firefox and in Orion.
// A site added to the table also needs its own @match line above.
//
// The default is applied once per source: YouTube swaps in a new blob: URL for each video (SPA
// navigation and autoplay included) and puts the rate back to 1x itself, so a new currentSrc is
// what marks "next video". Both loadeddata and playing are watched because either can come first
// and a video that never starts playing still gets its default. Media events do not bubble, hence
// the capture listeners on document.

(() => {
  const defaultRates = {
    "youtube.com": 2,
    "youtube-nocookie.com": 2,
  };
  const host = location.hostname;
  const rate = Object.entries(defaultRates).find(([d]) => host === d || host.endsWith(`.${d}`))?.[1];
  if (!rate) return;

  const applied = new WeakMap();
  const applyDefault = (video) => {
    if (!(video instanceof HTMLVideoElement) || !video.currentSrc) return;
    if (applied.get(video) === video.currentSrc) return;
    applied.set(video, video.currentSrc);
    video.playbackRate = rate;
  };
  for (const type of ["loadeddata", "playing"]) {
    document.addEventListener(type, (e) => applyDefault(e.target), true);
  }
})();
