// ==UserScript==
// @name         f*cking e-Tax
// @namespace    https://github.com/gapul/dotfiles
// @version      1.0.0
// @description  Make e-Tax's web forms believe this is Chrome on Windows (pairs with configs/apps/header-editor/etax.json)
// @match        *://*.e-tax.nta.go.jp/*
// @run-at       document-start
// @grant        none
// @downloadURL  https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/etax.user.js
// @updateURL    https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/etax.user.js
// ==/UserScript==

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
const def = (key, value) =>
  Object.defineProperty(Navigator.prototype, key, { get: () => value, configurable: true });

def('userAgent', UA);
def('appVersion', UA.replace(/^Mozilla\//, ''));
def('platform', 'Win32');
def('vendor', 'Google Inc.');
def('language', 'ja');
def('languages', Object.freeze(['ja', 'ja-JP']));
