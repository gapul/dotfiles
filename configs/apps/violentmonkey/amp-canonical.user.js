// ==UserScript==
// @name        amp-canonical: leave AMP pages for the normal page
// @namespace   https://github.com/gapul/dotfiles
// @version     0.1.0
// @description On a publisher's AMP page, go to the normal page it names as canonical.
// @match       *://*/*
// @grant       none
// @run-at      document-start
// @noframes
// @downloadURL https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/amp-canonical.user.js
// @updateURL   https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/amp-canonical.user.js
// ==/UserScript==

// AMP pages mark themselves with <html amp> (or <html ⚡>) and name the normal page in
// <link rel="canonical">. The AMP version is a stripped copy built around Google's AMP runtime
// (cdn.ampproject.org), so this goes to the canonical page as soon as the link is parsed. AMP
// pages served from Google's cache are skipped before they load by the urlskip rules in
// configs/apps/ublock/urlskip.txt; this handles the publisher's own AMP pages
// (amp.example.com/…, …/amp/, ?amp=1).

(() => {
  'use strict';

  const strip = (url) => url.split('#')[0];

  // true when there is nothing (more) to do, false to keep waiting for the parser.
  const go = () => {
    const html = document.documentElement;
    if (!html) return false;
    if (!html.hasAttribute('amp') && !html.hasAttribute('⚡')) return true;
    const link = document.querySelector('link[rel~="canonical"][href]');
    if (!link) return false;
    let url;
    try {
      url = new URL(link.getAttribute('href'), location.href);
    } catch {
      return true;
    }
    // AMP-only sites name the page itself.
    if (!/^https?:$/.test(url.protocol) || strip(url.href) === strip(location.href)) return true;
    // A canonical page that sends the browser back to AMP (some do, by user agent) would loop:
    // leave each AMP page at most once per tab.
    const key = `amp-canonical:${strip(location.href)}`;
    try {
      if (sessionStorage.getItem(key)) return true;
      sessionStorage.setItem(key, '1');
    } catch {
      // Without storage, still go: a loop is the exception, and the next AMP page stops it.
    }
    location.replace(url.href);
    return true;
  };

  if (go()) return;
  const observer = new MutationObserver(() => go() && observer.disconnect());
  observer.observe(document, { childList: true, subtree: true });
  document.addEventListener(
    'DOMContentLoaded',
    () => {
      go();
      observer.disconnect();
    },
    { once: true },
  );
})();
