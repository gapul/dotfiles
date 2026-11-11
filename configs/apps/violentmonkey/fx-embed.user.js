// ==UserScript==
// @name        fx-embed: embedded tweets via fxtwitter
// @namespace   https://github.com/gapul/dotfiles
// @version     0.2.0
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
    @media (prefers-color-scheme: dark) {
      .card { color: #e7e9ea; background: #16181c; border-color: #2f3336; }
      .muted { color: #8b98a5 !important; }
    }
    .head { display: flex; gap: 0.4em; flex-wrap: wrap; align-items: baseline; }
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

  const loadImage = async (url, box) => {
    const blob = await request(MEDIA_URL(url), 'blob');
    // A blob: URL keeps the image off the network from the page's side; some page CSPs refuse
    // blob: in img-src, so fall back to a link.
    const img = el('img', { alt: '' });
    img.onerror = () => img.replaceWith(link(url, url));
    img.src = URL.createObjectURL(blob);
    box.append(img);
  };

  const renderMedia = (media) => {
    const items = media?.all ?? [];
    if (!items.length) return null;
    const box = el('div', { class: 'media' });
    const photos = items.filter((m) => m.type === 'photo');
    const others = items.filter((m) => m.type !== 'photo');
    for (const p of photos) {
      loadImage(p.url, box).catch(() => box.append(link(p.url, '画像を開く')));
    }
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
