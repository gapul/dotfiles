// ==UserScript==
// @name        fx-embed: embedded tweets via fxtwitter
// @namespace   https://github.com/gapul/dotfiles
// @version     0.3.0
// @description Renders embedded tweets (blockquote.twitter-tweet) from api.fxtwitter.com instead of X, without cookies or Referer.
// @match       *://*/*
// @exclude     *://x.com/*
// @exclude     *://twitter.com/*
// @grant       GM_xmlhttpRequest
// @connect     api.fxtwitter.com
// @connect     pbs.twimg.com
// @connect     video.twimg.com
// @connect     *
// @run-at      document-idle
// @noframes
// @downloadURL https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/fx-embed.user.js
// @updateURL   https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/fx-embed.user.js
// ==/UserScript==

// Needs X's widget script to stay blocked (Firefox's click-to-load placeholder, or these uBlock
// Origin filters); once widgets.js runs it swaps the blockquote for its own iframe:
//   ||platform.twitter.com^$3p
//   ||syndication.twitter.com^$3p
//   ||cdn.syndication.twimg.com^$3p

(() => {
  'use strict';

  // Rewrites a media URL before it is fetched. Point it at a relay you run (a Cloudflare Worker,
  // the homeserver) so X sees the relay's IP instead of yours, e.g.
  //   (url) => 'https://img-relay.example.net/?u=' + encodeURIComponent(url)
  // Add the relay's host to @connect above if you narrow the wildcard.
  const MEDIA_URL = (url) => url;

  const API = 'https://api.fxtwitter.com/x/status/';
  const DONE = 'data-fx-embed';

  // GM_xmlhttpRequest runs outside the page: no page Referer, no page CSP, and `anonymous`
  // drops cookies.
  const request = (url, responseType) =>
    new Promise((resolve, reject) => {
      GM_xmlhttpRequest({
        url,
        method: 'GET',
        anonymous: true,
        responseType,
        timeout: 15000,
        onload: (r) => (r.status >= 200 && r.status < 300 ? resolve(r.response) : reject(new Error(`HTTP ${r.status}`))),
        onerror: () => reject(new Error('network error')),
        ontimeout: () => reject(new Error('timeout')),
      });
    });

  const statusId = (root) => {
    for (const a of [...root.querySelectorAll('a[href]')].reverse()) {
      const m = a.href.match(/(?:twitter|x)\.com\/[^/]+\/status(?:es)?\/(\d+)/);
      if (m) return m[1];
    }
    return null;
  };

  const el = (tag, props = {}, ...children) => {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === 'class') node.className = v;
      else if (k === 'text') node.textContent = v;
      else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v);
    }
    node.append(...children.filter(Boolean));
    return node;
  };

  const link = (href, text) => el('a', { href, text, target: '_blank', rel: 'noopener noreferrer', referrerpolicy: 'no-referrer' });

  const STYLE = `
    :host { all: initial; display: block; margin: 0.5em 0; }
    * { box-sizing: border-box; }
    .card { font: 14px/1.5 system-ui, sans-serif; color: #0f1419; background: #fff;
      border: 1px solid #cfd9de; border-radius: 12px; padding: 12px 14px; max-width: 550px; }
    :host([data-theme="dark"]) .card { color: #e7e9ea; background: #16181c; border-color: #2f3336; }
    :host([data-theme="dark"]) .muted { color: #8b98a5; }
    .head { display: flex; gap: 0.4em; flex-wrap: wrap; align-items: center; }
    .avatar { width: 36px; height: 36px; border-radius: 50%; object-fit: cover; flex: none; }
    .quote .avatar { width: 20px; height: 20px; }
    .avatar:not([src]) { visibility: hidden; }
    .name { font-weight: 700; }
    .muted { color: #536471; font-size: 13px; }
    .text { white-space: pre-wrap; overflow-wrap: anywhere; margin: 6px 0; }
    .quote { margin-top: 8px; }
    .quote .card { padding: 8px 10px; }
    .note { border-left: 3px solid #1d9bf0; padding-left: 8px; margin: 6px 0; }
    .media { display: grid; gap: 4px; margin-top: 6px; }
    .media img { max-width: 100%; border-radius: 8px; display: block; }
    a { color: #1d9bf0; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .err { color: #f4212e; }
  `;

  // Returns the <img> at once and fills it when the fetch lands. A blob: URL keeps the image off
  // the network from the page's side; some page CSPs refuse blob: in img-src, and then (or when
  // the fetch fails) `fallback` replaces the image, or the image is dropped.
  const image = (url, cls, fallback) => {
    const img = el('img', { alt: '', class: cls });
    const fail = () => (fallback ? img.replaceWith(fallback()) : img.remove());
    img.onerror = fail;
    request(MEDIA_URL(url), 'blob').then((blob) => (img.src = URL.createObjectURL(blob)), fail);
    return img;
  };

  const renderMedia = (media) => {
    const items = media?.all ?? [];
    if (!items.length) return null;
    const box = el('div', { class: 'media' });
    const photos = items.filter((m) => m.type === 'photo');
    const others = items.filter((m) => m.type !== 'photo');
    for (const p of photos) box.append(image(p.url, '', () => link(p.url, '画像を開く')));
    // Videos and GIFs stay as links: opening one is an explicit request to video.twimg.com.
    for (const v of others) box.append(link(v.url, v.type === 'gif' ? 'GIF を開く' : '動画を開く'));
    return box;
  };

  const renderTweet = (t, nested = false) => {
    const date = new Date(t.created_timestamp * 1000).toLocaleString('ja-JP');
    const note = typeof t.community_note?.text === 'string' ? t.community_note.text : null;
    const poll = t.poll?.choices?.length
      ? el('div', { class: 'muted' }, ...t.poll.choices.map((c) => el('div', { text: `${c.label}: ${c.percentage}%` })))
      : null;
    return el(
      'div',
      { class: 'card' },
      el(
        'div',
        { class: 'head' },
        t.author?.avatar_url ? image(t.author.avatar_url, 'avatar') : null,
        el('span', { class: 'name', text: t.author?.name ?? '' }),
        el('span', { class: 'muted', text: `@${t.author?.screen_name ?? '?'}` }),
        el('span', { class: 'muted', text: `· ${date}` }),
      ),
      t.replying_to ? el('div', { class: 'muted', text: `返信先: @${t.replying_to}` }) : null,
      el('div', { class: 'text', text: t.text ?? '' }),
      poll,
      note ? el('div', { class: 'note muted', text: `コミュニティノート: ${note}` }) : null,
      renderMedia(t.media),
      t.quote ? el('div', { class: 'quote' }, renderTweet(t.quote, true)) : null,
      nested
        ? null
        : el(
            'div',
            { class: 'muted' },
            `♥ ${t.likes ?? 0}  ↻ ${t.retweets ?? 0}  · `,
            link(t.url, 'X で開く'),
          ),
    );
  };

  const attach = (bq) => {
    if (bq.hasAttribute(DONE)) return;
    bq.setAttribute(DONE, '');
    const id = statusId(bq);
    if (!id) return;

    const host = el('div');
    const shadow = host.attachShadow({ mode: 'closed' });
    const out = el('div');
    shadow.append(el('style', { text: STYLE }), out);
    bq.after(host);
    themed.add(host);
    applyTheme(host);
    // Fetch only once the tweet is about to scroll into view, so unread embeds cost no request.
    visible.set(host, async () => {
      try {
        const data = await request(API + id, 'json');
        if (!data?.tweet) throw new Error(data?.message ?? 'no tweet');
        out.replaceChildren(renderTweet(data.tweet));
        bq.hidden = true;
      } catch (e) {
        out.replaceChildren(el('div', { class: 'err', text: `fxtwitter から取得できませんでした: ${e.message}` }));
      }
    });
    observer.observe(host);
  };

  // Follow the page's own light/dark look rather than the OS setting: take the first opaque
  // background behind the card and judge it by luminance. The OS setting decides only when
  // nothing behind it paints a background.
  const pageIsDark = (node) => {
    for (let n = node.parentElement; n; n = n.parentElement) {
      const m = getComputedStyle(n).backgroundColor.match(/[\d.]+/g);
      if (!m || (m.length > 3 && Number(m[3]) < 0.5)) continue;
      const [r, g, b] = m.slice(0, 3).map((c) => (Number(c) / 255) ** 2.2);
      return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.18;
    }
    return matchMedia('(prefers-color-scheme: dark)').matches;
  };
  const themed = new Set();
  const applyTheme = (host) => host.setAttribute('data-theme', pageIsDark(host) ? 'dark' : 'light');
  const reapplyThemes = () => {
    for (const host of themed) host.isConnected ? applyTheme(host) : themed.delete(host);
  };
  // Sites switch themes by flipping a class or attribute on <html> or <body>, or by following
  // the OS setting through CSS.
  const themeWatch = new MutationObserver(reapplyThemes);
  for (const n of [document.documentElement, document.body]) {
    themeWatch.observe(n, { attributes: true, attributeFilter: ['class', 'style', 'data-theme', 'data-color-mode', 'data-mode'] });
  }
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => requestAnimationFrame(reapplyThemes));

  const visible = new WeakMap();
  const observer = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        observer.unobserve(e.target);
        visible.get(e.target)?.();
      }
    },
    { rootMargin: '400px' },
  );

  const scan = (root) => {
    if (root.nodeType !== Node.ELEMENT_NODE) return;
    if (root.matches('blockquote.twitter-tweet')) attach(root);
    root.querySelectorAll('blockquote.twitter-tweet').forEach(attach);
  };

  scan(document.body);
  new MutationObserver((records) => {
    for (const r of records) r.addedNodes.forEach(scan);
  }).observe(document.body, { childList: true, subtree: true });
})();
