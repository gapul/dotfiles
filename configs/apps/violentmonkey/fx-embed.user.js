// ==UserScript==
// @name        fx-embed: embedded tweets via fxtwitter
// @namespace   https://github.com/gapul/dotfiles
// @version     0.4.0
// @description Renders embedded tweets from api.fxtwitter.com instead of X, laid out like X's own embed, without cookies or Referer.
// @match       *://*/*
// @exclude     *://x.com/*
// @exclude     *://twitter.com/*
// @grant       GM_xmlhttpRequest
// @connect     api.fxtwitter.com
// @connect     pbs.twimg.com
// @connect     video.twimg.com
// @connect     *
// @run-at      document-start
// @noframes
// @downloadURL https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/fx-embed.user.js
// @updateURL   https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/fx-embed.user.js
// ==/UserScript==

// Embeds are claimed as soon as the parser inserts them: their marker classes are swapped for
// our own, so neither X's widgets.js nor Firefox's SmartBlock click-to-load placeholder (which
// replaces every `.twitter-tweet` it finds, browser/extensions/webcompat/shims/twitter-embed.js)
// gets to them. Embeds that widgets.js has already turned into iframes are replaced too.

(() => {
  'use strict';

  // Rewrites a media URL before it is fetched. Point it at a relay you run (a Cloudflare Worker,
  // the homeserver) so X sees the relay's IP instead of yours, e.g.
  //   (url) => 'https://img-relay.example.net/?u=' + encodeURIComponent(url)
  // Add the relay's host to @connect above if you narrow the wildcard.
  const MEDIA_URL = (url) => url;

  const API = 'https://api.fxtwitter.com/x/status/';
  const MARKERS = ['twitter-tweet', 'twitter-video', 'tweet-embed'];
  const SELECTOR = [
    ...MARKERS.map((c) => `.${c}`),
    'iframe[src*="platform.twitter.com/embed/"]',
    'iframe[src*="platform.x.com/embed/"]',
  ].join(', ');
  const STATE = 'data-fx-embed'; // pending → done | skip

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

  const statusId = (node) => {
    const direct = node.dataset?.tweetId ?? node.getAttribute('data-tweetid');
    if (/^\d+$/.test(direct ?? '')) return direct;
    if (node.tagName === 'IFRAME') return node.src.match(/[?&]id=(\d+)/)?.[1] ?? null;
    for (const a of [...node.querySelectorAll('a[href]')].reverse()) {
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

  const link = (href, props = {}, ...children) =>
    el('a', { href, target: '_blank', rel: 'noopener noreferrer', referrerpolicy: 'no-referrer', ...props }, ...children);

  // Constant markup only; nothing fetched ever goes through innerHTML.
  const PATHS = {
    x: 'M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z',
    verified:
      'M22.25 12c0-1.43-.88-2.67-2.19-3.34.46-1.39.2-2.9-.81-3.91s-2.52-1.27-3.91-.81c-.66-1.31-1.91-2.19-3.34-2.19s-2.67.88-3.33 2.19c-1.4-.46-2.91-.2-3.92.81s-1.26 2.52-.8 3.91c-1.31.67-2.2 1.91-2.2 3.34s.89 2.67 2.2 3.34c-.46 1.39-.21 2.9.8 3.91s2.52 1.26 3.91.81c.67 1.31 1.91 2.19 3.34 2.19s2.68-.88 3.34-2.19c1.39.45 2.9.2 3.91-.81s1.27-2.52.81-3.91c1.31-.67 2.19-1.91 2.19-3.34zm-11.71 4.2L6.8 12.46l1.41-1.42 2.26 2.26 4.8-5.23 1.47 1.36-6.2 6.77z',
    heart:
      'M20.884 13.19c-1.351 2.48-4.001 5.12-8.379 7.67l-.503.3-.504-.3c-4.379-2.55-7.029-5.19-8.382-7.67-1.36-2.5-1.41-4.86-.514-6.67.887-1.79 2.647-2.91 4.601-3.01 1.651-.09 3.368.56 4.798 2.01 1.429-1.45 3.146-2.1 4.796-2.01 1.954.1 3.714 1.22 4.601 3.01.896 1.81.846 4.17-.514 6.67z',
    reply:
      'M1.751 10c0-4.42 3.584-8 8.005-8h4.366c4.49 0 8.129 3.64 8.129 8.13 0 2.96-1.607 5.68-4.196 7.11l-8.054 4.46v-3.69h-.067c-4.49.1-8.183-3.51-8.183-8.01zm8.005-6c-3.317 0-6.005 2.69-6.005 6 0 3.37 2.77 6.08 6.138 6.01l.351-.01h1.761v2.3l5.087-2.81c1.951-1.08 3.163-3.13 3.163-5.36 0-3.39-2.744-6.13-6.129-6.13H9.756z',
    link: 'M18.36 5.64c-1.95-1.96-5.11-1.96-7.07 0L9.88 7.05 8.46 5.64l1.42-1.42c2.73-2.73 7.16-2.73 9.9 0 2.73 2.74 2.73 7.17 0 9.9l-1.42 1.42-1.41-1.42 1.41-1.41c1.96-1.96 1.96-5.12 0-7.07zm-2.12 3.53l-7.07 7.07-1.41-1.41 7.07-7.07 1.41 1.41zm-12.02.71l1.42-1.42 1.41 1.42-1.41 1.41c-1.96 1.96-1.96 5.12 0 7.07 1.95 1.96 5.11 1.96 7.07 0l1.41-1.41 1.42 1.41-1.42 1.42c-2.73 2.73-7.16 2.73-9.9 0-2.73-2.74-2.73-7.17 0-9.9z',
    play: 'M8 5v14l11-7z',
  };
  const icon = (name, cls) => {
    const span = el('span', { class: `icon ${cls ?? name}` });
    span.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${PATHS[name]}"/></svg>`;
    return span;
  };

  const STYLE = `
    :host { all: initial; display: block; margin: 10px 0; max-width: 550px;
      --bg: #fff; --fg: #0f1419; --muted: #536471; --border: #cfd9de; --hover: #f7f9f9;
      --blue: #1d9bf0; --red: #f91880; }
    :host([data-theme="dark"]) { --bg: #000; --fg: #e7e9ea; --muted: #71767b; --border: #2f3336; --hover: #080808; }
    * { box-sizing: border-box; }
    a { color: var(--blue); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .icon { display: inline-flex; }
    .icon svg { width: 100%; height: 100%; fill: currentColor; }
    .card { font: 15px/20px "TwitterChirp", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
        "Hiragino Sans", "Noto Sans CJK JP", sans-serif;
      color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 12px;
      padding: 12px 16px 4px; }
    .head { display: flex; align-items: center; gap: 8px; }
    .avatar { width: 48px; height: 48px; border-radius: 50%; object-fit: cover; flex: none; background: var(--border); }
    .who { min-width: 0; flex: 1; display: flex; flex-direction: column; }
    .who a { color: inherit; }
    .name { font-weight: 700; display: inline-flex; align-items: center; gap: 2px; overflow: hidden;
      white-space: nowrap; text-overflow: ellipsis; }
    .verified { width: 18px; height: 18px; color: var(--blue); flex: none; }
    .verified.business { color: #e2b719; }
    .verified.government { color: #829aab; }
    .handle, .muted { color: var(--muted); }
    .x { width: 24px; height: 24px; color: var(--fg); align-self: flex-start; }
    .reply-to { color: var(--muted); margin-top: 4px; }
    .text { font-size: 17px; line-height: 24px; white-space: pre-wrap; overflow-wrap: anywhere; margin: 12px 0; }
    .media { display: grid; gap: 2px; border: 1px solid var(--border); border-radius: 16px; overflow: hidden; margin: 12px 0; }
    .media > * { position: relative; display: block; min-height: 0; }
    .media img { display: block; width: 100%; height: 100%; object-fit: cover; }
    .media.n1 img { height: auto; max-height: 510px; }
    .media.n2, .media.n3, .media.n4 { grid-template-columns: 1fr 1fr; height: 290px; }
    .media.n3 > :first-child { grid-row: span 2; }
    .media.n4 { grid-template-rows: 1fr 1fr; }
    .media .fallback { padding: 12px; }
    .playwrap { position: absolute; inset: 0; display: grid; place-items: center; pointer-events: none; }
    .play { width: 56px; height: 56px; padding: 12px; border-radius: 50%; color: #fff; background: var(--blue);
      border: 4px solid #fff; }
    .quote { border: 1px solid var(--border); border-radius: 16px; padding: 12px; margin: 12px 0; }
    .quote .head { gap: 4px; flex-wrap: wrap; }
    .quote .avatar { width: 20px; height: 20px; }
    .quote .who { flex-direction: row; gap: 4px; flex: initial; }
    .quote .text { font-size: 15px; line-height: 20px; margin: 4px 0 0; }
    .quote .media { margin-bottom: 0; }
    .note { border: 1px solid var(--border); border-radius: 16px; padding: 12px; margin: 12px 0; }
    .note b { display: block; margin-bottom: 4px; }
    .poll { margin: 12px 0; display: grid; gap: 6px; }
    .poll .bar { position: relative; padding: 4px 8px; border-radius: 4px; display: flex; justify-content: space-between; }
    .poll .fill { position: absolute; inset: 0 auto 0 0; background: var(--border); border-radius: 4px; z-index: 0; }
    .poll span { position: relative; }
    .time { color: var(--muted); display: block; padding-bottom: 12px; border-bottom: 1px solid var(--border); }
    .actions { display: flex; gap: 20px; padding: 4px 0; color: var(--muted); font-size: 14px; font-weight: 700; }
    .actions a, .actions button { display: inline-flex; align-items: center; gap: 4px; color: inherit; padding: 6px 0;
      background: none; border: 0; font: inherit; cursor: pointer; }
    .actions .icon { width: 20px; height: 20px; }
    .actions .heart { color: var(--red); }
    .more { display: block; text-align: center; font-weight: 700; border: 1px solid var(--border); border-radius: 999px;
      padding: 6px 16px; margin: 4px 0 12px; }
    .more:hover { background: var(--hover); text-decoration: none; }
    .err { font: 14px system-ui, sans-serif; color: #f4212e; }
  `;

  // Returns the <img> at once and fills it when the fetch lands. A blob: URL keeps the image off
  // the network from the page's side; some page CSPs refuse blob: in img-src, and then (or when
  // the fetch fails) `fallback` replaces the image, or the image is dropped.
  const image = (url, cls, fallback) => {
    const img = el('img', { alt: '', class: cls ?? '' });
    const fail = () => (fallback ? img.replaceWith(fallback()) : img.remove());
    img.onerror = fail;
    request(MEDIA_URL(url), 'blob').then((blob) => (img.src = URL.createObjectURL(blob)), fail);
    return img;
  };

  const compact = new Intl.NumberFormat('ja-JP', { notation: 'compact', maximumFractionDigits: 1 });

  // URLs, @mentions and #hashtags become links; everything else stays text.
  const richText = (text, hasMedia) => {
    // Old tweets still carry the t.co link of their own attached media at the end.
    const body = hasMedia ? text.replace(/\s*https?:\/\/t\.co\/\w+\s*$/, '') : text;
    const out = el('div', { class: 'text' });
    let last = 0;
    for (const m of body.matchAll(/https?:\/\/[^\s]+|@\w{1,15}|#[\p{L}\p{N}_]+/gu)) {
      out.append(body.slice(last, m.index));
      const t = m[0];
      const href = t.startsWith('@')
        ? `https://x.com/${t.slice(1)}`
        : t.startsWith('#')
          ? `https://x.com/hashtag/${encodeURIComponent(t.slice(1))}`
          : t;
      out.append(link(href, { text: t.startsWith('http') ? t.replace(/^https?:\/\/(www\.)?/, '') : t }));
      last = m.index + t.length;
    }
    out.append(body.slice(last));
    return out;
  };

  const renderMedia = (media) => {
    const items = (media?.all ?? []).slice(0, 4);
    if (!items.length) return null;
    const box = el('div', { class: `media n${items.length}` });
    for (const m of items) {
      if (m.type === 'photo') {
        box.append(image(m.url, '', () => link(m.url, { class: 'fallback', text: '画像を開く' })));
      } else {
        // Videos and GIFs show their poster; playing one is an explicit visit to video.twimg.com.
        const label = m.type === 'gif' ? 'GIF を開く' : '動画を開く';
        box.append(
          link(
            m.url,
            { title: label },
            m.thumbnail_url ? image(m.thumbnail_url) : el('span', { class: 'fallback', text: label }),
            el('span', { class: 'playwrap' }, icon('play')),
          ),
        );
      }
    }
    return box;
  };

  const author = (t, small) => {
    const a = t.author ?? {};
    const profile = a.url ?? `https://x.com/${a.screen_name}`;
    const v = a.verification?.verified ? icon('verified', `verified ${a.verification.type ?? ''}`) : null;
    return el(
      'div',
      { class: 'head' },
      a.avatar_url ? link(profile, {}, image(a.avatar_url, 'avatar')) : null,
      el(
        'div',
        { class: 'who' },
        link(profile, { class: 'name' }, el('span', { text: a.name ?? '' }), v),
        link(profile, { class: 'handle', text: `@${a.screen_name ?? '?'}` }),
        small ? el('span', { class: 'muted', text: `· ${new Date(t.created_timestamp * 1000).toLocaleDateString('ja-JP')}` }) : null,
      ),
      small ? null : link(t.url, { class: 'x', title: 'X で見る' }, icon('x')),
    );
  };

  const renderPoll = (poll) =>
    poll?.choices?.length
      ? el(
          'div',
          { class: 'poll' },
          ...poll.choices.map((c) =>
            el(
              'div',
              { class: 'bar' },
              el('div', { class: 'fill', style: `width:${Number(c.percentage) || 0}%` }),
              el('span', { text: c.label }),
              el('span', { text: `${c.percentage}%` }),
            ),
          ),
          el('div', { class: 'muted', text: `${compact.format(poll.total_votes ?? 0)}票` }),
        )
      : null;

  const renderQuote = (q) =>
    link(
      q.url,
      { class: 'quote', style: 'display:block;color:inherit;text-decoration:none' },
      author(q, true),
      richText(q.text ?? '', Boolean(q.media?.all?.length)),
      renderMedia(q.media),
    );

  const renderTweet = (t) => {
    const d = new Date(t.created_timestamp * 1000);
    const when = `${d.toLocaleTimeString('ja-JP', { hour: 'numeric', minute: '2-digit', hour12: true })} · ${d.toLocaleDateString('ja-JP', { year: 'numeric', month: 'long', day: 'numeric' })}`;
    const note = typeof t.community_note?.text === 'string' ? t.community_note.text : null;
    const copy = el('button', {
      type: 'button',
      onclick: () =>
        navigator.clipboard.writeText(t.url).then(() => {
          copy.lastChild.textContent = 'コピーしました';
        }),
    });
    copy.append(icon('link', 'link'), el('span', { text: 'リンクをコピー' }));
    return el(
      'div',
      { class: 'card' },
      author(t, false),
      t.replying_to ? el('div', { class: 'reply-to' }, '返信先: ', link(`https://x.com/${t.replying_to}`, { text: `@${t.replying_to}` })) : null,
      richText(t.text ?? '', Boolean(t.media?.all?.length)),
      renderPoll(t.poll),
      renderMedia(t.media),
      t.quote ? renderQuote(t.quote) : null,
      note ? el('div', { class: 'note' }, el('b', { text: 'コミュニティノート' }), el('span', { text: note })) : null,
      link(t.url, { class: 'time', text: when }),
      el(
        'div',
        { class: 'actions' },
        link(t.url, {}, icon('heart'), el('span', { text: compact.format(t.likes ?? 0) })),
        link(t.url, {}, icon('reply'), el('span', { text: '返信' })),
        copy,
      ),
      link(t.url, {
        class: 'more',
        text: t.replies ? `X で${compact.format(t.replies)}件の返信を読む` : 'X で見る',
      }),
    );
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

  // Takes the embed out of reach of widgets.js and SmartBlock right away; the tweet id is read
  // later, once the parser has filled the element in.
  const claim = (node) => {
    if (node.hasAttribute(STATE)) return;
    node.setAttribute(STATE, 'pending');
    node.classList.remove(...MARKERS);
  };

  const attach = (node) => {
    const id = statusId(node);
    if (!id) {
      node.setAttribute(STATE, 'skip');
      return;
    }
    node.setAttribute(STATE, 'done');
    const host = el('div');
    const shadow = host.attachShadow({ mode: 'closed' });
    const out = el('div', {}, el('slot'));
    shadow.append(el('style', { text: STYLE }), out);
    // The original blockquote stays inside the host as light DOM and shows through the slot
    // until the card replaces it, and again if fetching fails. An iframe has nothing to show.
    const iframe = node.tagName === 'IFRAME';
    node.replaceWith(host);
    if (!iframe) host.append(node);
    themed.add(host);
    applyTheme(host);
    // Fetch only once the tweet is about to scroll into view, so unread embeds cost no request.
    visible.set(host, async () => {
      try {
        const data = await request(API + id, 'json');
        if (!data?.tweet) throw new Error(data?.message ?? 'no tweet');
        applyTheme(host);
        out.replaceChildren(renderTweet(data.tweet));
      } catch (e) {
        if (iframe) host.replaceWith(node);
        else out.replaceChildren(el('div', { class: 'err', text: `fxtwitter から取得できませんでした: ${e.message}` }), el('slot'));
      }
    });
    observer.observe(host);
  };

  const parsing = () => document.readyState === 'loading';
  const attachPending = () => document.querySelectorAll(`[${STATE}="pending"]`).forEach(attach);

  const scan = (root) => {
    if (root.nodeType !== Node.ELEMENT_NODE) return;
    if (root.matches(SELECTOR)) claim(root);
    root.querySelectorAll(SELECTOR).forEach(claim);
  };

  // At document-start even <html> may not exist yet, so watch the document itself.
  if (document.documentElement) scan(document.documentElement);
  new MutationObserver((records) => {
    for (const r of records) r.addedNodes.forEach(scan);
    if (!parsing()) attachPending();
  }).observe(document, { childList: true, subtree: true });

  const ready = () => {
    attachPending();
    // Sites switch themes by flipping a class or attribute on <html> or <body>, or by following
    // the OS setting through CSS.
    const themeWatch = new MutationObserver(reapplyThemes);
    for (const n of [document.documentElement, document.body]) {
      themeWatch.observe(n, { attributes: true, attributeFilter: ['class', 'style', 'data-theme', 'data-color-mode', 'data-mode'] });
    }
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => requestAnimationFrame(reapplyThemes));
  };
  if (parsing()) document.addEventListener('DOMContentLoaded', ready, { once: true });
  else ready();
})();
