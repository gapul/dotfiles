// ==UserScript==
// @name        fx-embed: embedded tweets via fxtwitter
// @namespace   https://github.com/gapul/dotfiles
// @version     0.11.1
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
  const request = (url, responseType, onprogress, timeout = 15000) =>
    new Promise((resolve, reject) => {
      GM_xmlhttpRequest({
        url,
        method: 'GET',
        anonymous: true,
        responseType,
        timeout,
        onprogress,
        onload: (r) =>
          r.status >= 200 && r.status < 300
            ? resolve(r.response)
            : reject(Object.assign(new Error(`HTTP ${r.status}`), { status: r.status })),
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
      'M16.697 5.5c-1.222-.06-2.679.51-3.89 2.16l-.805 1.09-.806-1.09C9.984 6.01 8.526 5.44 7.304 5.5c-1.243.07-2.349.78-2.91 1.91-.552 1.12-.633 2.78.479 4.82 1.074 1.97 3.257 4.27 7.129 6.61 3.87-2.34 6.052-4.64 7.126-6.61 1.111-2.04 1.03-3.7.477-4.82-.561-1.13-1.666-1.84-2.908-1.91zm4.187 7.69c-1.351 2.48-4.001 5.12-8.379 7.67l-.503.3-.504-.3c-4.379-2.55-7.029-5.19-8.382-7.67-1.36-2.5-1.41-4.86-.514-6.67.887-1.79 2.647-2.91 4.601-3.01 1.651-.09 3.368.56 4.798 2.01 1.429-1.45 3.146-2.1 4.796-2.01 1.954.1 3.714 1.22 4.601 3.01.896 1.81.846 4.17-.514 6.67z',
    reply:
      'M1.751 10c0-4.42 3.584-8 8.005-8h4.366c4.49 0 8.129 3.64 8.129 8.13 0 2.96-1.607 5.68-4.196 7.11l-8.054 4.46v-3.69h-.067c-4.49.1-8.183-3.51-8.183-8.01zm8.005-6c-3.317 0-6.005 2.69-6.005 6 0 3.37 2.77 6.08 6.138 6.01l.351-.01h1.761v2.3l5.087-2.81c1.951-1.08 3.163-3.13 3.163-5.36 0-3.39-2.744-6.13-6.129-6.13H9.756z',
    link: 'M18.36 5.64c-1.95-1.96-5.11-1.96-7.07 0L9.88 7.05 8.46 5.64l1.42-1.42c2.73-2.73 7.16-2.73 9.9 0 2.73 2.74 2.73 7.17 0 9.9l-1.42 1.42-1.41-1.42 1.41-1.41c1.96-1.96 1.96-5.12 0-7.07zm-2.12 3.53l-7.07 7.07-1.41-1.41 7.07-7.07 1.41 1.41zm-12.02.71l1.42-1.42 1.41 1.42-1.41 1.41c-1.96 1.96-1.96 5.12 0 7.07 1.95 1.96 5.11 1.96 7.07 0l1.41-1.41 1.42 1.41-1.42 1.42c-2.73 2.73-7.16 2.73-9.9 0-2.73-2.74-2.73-7.17 0-9.9z',
    play: 'M8 5v14l11-7z',
    repost:
      'M4.5 3.88l4.432 4.14-1.364 1.46L5.5 7.55V16c0 1.1.896 2 2 2H13v2H7.5c-2.209 0-4-1.79-4-4V7.55L1.432 9.48.068 8.02 4.5 3.88zM16.5 6H11V4h5.5c2.209 0 4 1.79 4 4v8.45l2.068-1.93 1.364 1.46-4.432 4.14-4.432-4.14 1.364-1.46 2.068 1.93V8c0-1.1-.896-2-2-2z',
    views: 'M8.75 21V3h2v18h-2zM18 21V8.5h2V21h-2zM4 21l.004-10h2L6 21H4zm9.248 0v-7h2v7h-2z',
    bookmark:
      'M4 4.5C4 3.12 5.119 2 6.5 2h11C18.881 2 20 3.12 20 4.5v18.44l-8-5.71-8 5.71V4.5zM6.5 4c-.276 0-.5.22-.5.5v14.56l6-4.29 6 4.29V4.5c0-.28-.224-.5-.5-.5h-11z',
  };
  const icon = (name, cls) => {
    const span = el('span', { class: `icon ${cls ?? name}` });
    span.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${PATHS[name]}"/></svg>`;
    return span;
  };

  const STYLE = `
    :host { all: initial; display: block; margin: 10px 0; max-width: 550px;
      --bg: #fff; --fg: #0f1419; --muted: #536471; --border: #cfd9de; --hover: #f7f9f9;
      --blue: #1d9bf0; --link: #006fd6; --red: #f91880; --poll: #cfd9de; --poll-win: #8ecdf8; }
    :host([data-theme="dark"]) { --bg: #000; --fg: #e7e9ea; --muted: #71767b; --border: #2f3336; --hover: #080808;
      --link: #1d9bf0; --poll: #333639; --poll-win: #1a5f8e; }
    * { box-sizing: border-box; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .icon { display: inline-flex; }
    .icon svg { width: 100%; height: 100%; fill: currentColor; }
    .card { position: relative; font: 15px/20px "TwitterChirp", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
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
    /* .who a would otherwise give the handle link the text colour; X shows it grey. */
    .handle, .muted, .who a.handle { color: var(--muted); }
    /* Pinned to the card's corner, as X does, so it sits on the first row whether that is the
       author or the parent tweet. */
    a.x { position: absolute; top: 12px; right: 16px; display: block; width: 24px; height: 24px; color: var(--fg); }
    .icon.x { width: 100%; height: 100%; }
    .card > .head, .pbody > .head { padding-right: 32px; }
    .date { font-weight: 400; color: var(--muted); margin-left: 4px; }
    .reply-to { color: var(--muted); margin-top: 4px; }
    .text { font-size: 20px; line-height: 24px; white-space: pre-wrap; overflow-wrap: anywhere; margin: 8px 0; }
    .media { display: grid; gap: 2px; border: 1px solid var(--border); border-radius: 16px; overflow: hidden; margin: 12px 0; }
    .media > * { position: relative; display: block; min-height: 0; }
    .media img { display: block; width: 100%; height: 100%; object-fit: cover; }
    .media.n1 img { height: auto; max-height: 510px; }
    .media.n2, .media.n3, .media.n4 { grid-template-columns: 1fr 1fr; height: 290px; }
    .media.n3 > :first-child { grid-row: span 2; }
    .media.n4 { grid-template-rows: 1fr 1fr; }
    .media .fallback { padding: 12px; }
    .playwrap { position: absolute; inset: 0; display: grid; place-items: center; pointer-events: none; }
    .play { width: 64px; height: 64px; padding: 12px; border-radius: 50%; color: #fff; background: var(--blue);
      border: 4px solid #fff; }
    .quote { border: 1px solid var(--border); border-radius: 16px; padding: 12px; margin: 12px 0; }
    .quote .head { gap: 4px; flex-wrap: wrap; }
    .quote .avatar { width: 20px; height: 20px; }
    .quote .who { flex-direction: row; gap: 4px; flex: initial; }
    .quote .text { font-size: 15px; line-height: 20px; margin: 4px 0 0; }
    .quote .media { margin-bottom: 0; }
    .note { border: 1px solid var(--border); border-radius: 16px; padding: 12px; margin: 12px 0; }
    .note b { display: block; margin-bottom: 4px; }
    .poll { margin: 12px 0; display: grid; gap: 4px; }
    .poll .bar { position: relative; min-height: 32px; padding: 0 12px; display: flex; align-items: center; justify-content: space-between; }
    .poll .fill { position: absolute; inset: 0 auto 0 0; background: var(--poll); border-radius: 4px; z-index: 0; }
    .poll .win .fill { background: var(--poll-win); }
    .poll .win span { font-weight: 700; }
    .poll .muted { margin-top: 8px; }
    .poll span { position: relative; }
    .time { color: var(--muted); display: block; padding-bottom: 12px; border-bottom: 1px solid var(--border); }
    .actions { display: flex; flex-wrap: wrap; column-gap: 18px; padding: 4px 0; color: var(--muted); font-size: 14px; font-weight: 700; }
    .actions .share { margin-left: auto; }
    /* Grey at rest; each count takes x.com's colour only on hover. */
    .actions .r:hover, .actions .vw:hover, .actions .bm:hover { color: var(--blue); }
    .actions .rp:hover { color: #00ba7c; }
    .actions .lk:hover { color: var(--red); }
    .actions a, .actions button { display: inline-flex; align-items: center; gap: 4px; color: inherit; padding: 6px 0;
      background: none; border: 0; font: inherit; cursor: pointer; }
    .actions .icon { width: 20px; height: 20px; }
    .more { display: block; text-align: center; font-weight: 700; border: 1px solid var(--border); border-radius: 999px;
      padding: 6px 16px; margin: 4px 0 12px; }
    .more:hover { background: var(--hover); text-decoration: none; }
    .err { font: 14px system-ui, sans-serif; color: #f4212e; }
    .show-more { font: inherit; color: var(--link); background: none; border: 0; padding: 0; cursor: pointer; }
    .show-more:hover { text-decoration: underline; }
    .parent { display: flex; gap: 8px; color: inherit; text-decoration: none !important; }
    .rail { display: flex; flex-direction: column; align-items: center; width: 48px; flex: none; }
    .rail .avatar { width: 48px; height: 48px; }
    .line { flex: 1; width: 2px; margin-top: 4px; background: var(--border); }
    .pbody { min-width: 0; flex: 1; padding-bottom: 8px; }
    .pbody .text { font-size: 15px; line-height: 20px; margin: 4px 0 0; }
    .pbody .media { margin-bottom: 0; }
    .ph { position: relative; }
    .alt { position: absolute; left: 8px; bottom: 8px; font: 700 12px/1 system-ui, sans-serif; color: #fff;
      background: rgba(0, 0, 0, 0.75); border-radius: 4px; padding: 3px 5px; cursor: help; }
    .video { cursor: pointer; background: #000; }
    .video .status:empty { display: none; }
    .photo { cursor: zoom-in; }
    .vframe { display: block; width: 100%; max-height: 510px; border: 0; background: #000; }
    .video .status { position: absolute; left: 8px; bottom: 8px; font: 700 12px system-ui, sans-serif; color: #fff;
      background: rgba(0, 0, 0, 0.75); border-radius: 4px; padding: 2px 6px; }
    .media video { display: block; width: 100%; height: 100%; max-height: 510px; background: #000; object-fit: contain; }
    .media.sensitive > :not(.reveal) { filter: blur(28px); }
    .reveal { position: absolute; inset: 0; z-index: 1; display: grid; place-content: center; gap: 8px; text-align: center;
      color: #fff; background: rgba(0, 0, 0, 0.35); border: 0; font: 700 15px system-ui, sans-serif; cursor: pointer; }
    .media { position: relative; }
    .gone { padding-bottom: 12px; }
    .gone .why { font-weight: 700; margin-bottom: 8px; }
    .gone ::slotted(*) { margin: 8px 0 !important; color: var(--fg) !important; }
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

  // UI language follows the reader, not the site: Japanese when the browser's language is
  // Japanese, English otherwise. (X's embed follows the page instead; a Japanese site read in
  // an English browser should still label things in English.)
  const STRINGS = {
    ja: {
      openImage: '画像を開く',
      video: '動画',
      play: '再生',
      loading: (pct) => `読み込み中 ${pct}%`,
      openVideo: '動画を開く',
      videoFailed: (msg) => `動画を開く（読み込み失敗: ${msg}）`,
      sensitive: 'センシティブな内容の可能性があります',
      show: '表示する',
      viewOnX: 'X で見る',
      votes: (n) => `${n}票`,
      finalResults: '最終結果',
      showMore: 'さらに表示',
      close: '閉じる',
      previous: '前へ',
      next: '次へ',
      copyLink: 'リンクをコピー',
      copied: 'コピーしました',
      replyingTo: '返信先: ',
      note: 'コミュニティノート',
      replies: '件の返信',
      reposts: (quotes) => `件のリポスト（うち引用 ${quotes}）`,
      likes: '件のいいね',
      views: '件の表示',
      bookmarks: '件のブックマーク',
      readReplies: (n) => `${n}件の返信を読む`,
      fetchFailed: (msg) => `fxtwitter から取得できませんでした: ${msg}`,
      deleted: 'このツイートは削除されたか、見つかりません',
      restricted: '非公開アカウントか、表示が制限されたツイートです',
      wayback: 'Wayback Machine で探す',
    },
    en: {
      openImage: 'Open image',
      video: 'Video',
      play: 'Play',
      loading: (pct) => `Loading ${pct}%`,
      openVideo: 'Open video',
      videoFailed: (msg) => `Open video (failed to load: ${msg})`,
      sensitive: 'This media may contain sensitive content',
      show: 'Show',
      viewOnX: 'View on X',
      votes: (n) => `${n} votes`,
      finalResults: 'Final results',
      showMore: 'Show more',
      close: 'Close',
      previous: 'Previous',
      next: 'Next',
      copyLink: 'Copy link',
      copied: 'Copied',
      replyingTo: 'Replying to ',
      note: 'Community Notes',
      replies: 'replies',
      reposts: (quotes) => `reposts (${quotes} quotes)`,
      likes: 'likes',
      views: 'views',
      bookmarks: 'bookmarks',
      readReplies: (n) => `Read ${n} replies`,
      fetchFailed: (msg) => `Couldn't load from fxtwitter: ${msg}`,
      deleted: "This post was deleted or can't be found",
      restricted: 'This post is from a protected account or is unavailable',
      wayback: 'Search the Wayback Machine',
    },
  };
  const lang = () => (/^ja\b/i.test(navigator.language) ? 'ja' : 'en');
  const S = () => STRINGS[lang()];
  const locale = () => (lang() === 'ja' ? 'ja-JP' : 'en-US');
  const formats = {};
  const compact = (n) =>
    (formats[locale()] ??= new Intl.NumberFormat(locale(), { notation: 'compact', maximumFractionDigits: 1 })).format(n);
  const number = (n) => n.toLocaleString(locale());
  // 2022年11月2日 in Japanese, Nov 2, 2022 in English, as X writes them.
  const shortDate = (sec) =>
    new Date(sec * 1000).toLocaleDateString(locale(), { year: 'numeric', month: lang() === 'ja' ? 'long' : 'short', day: 'numeric' });

  // The text without the leading @mentions of the accounts being replied to, which X keeps out
  // of the displayed range (raw_text.display_text_range, counted in code points).
  const displayText = (t) => {
    const text = t.text ?? '';
    const start = t.raw_text?.display_text_range?.[0];
    if (!start) return text;
    const prefix = Array.from(t.raw_text.text ?? '').slice(0, start).join('');
    return prefix && text.startsWith(prefix) ? text.slice(prefix.length) : text;
  };

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

  // Long posts are cut like X's embed cuts them: at the last word boundary within 280
  // characters, followed by "Show more". Here it expands in place instead of opening x.com.
  const LONG = 280;
  const tweetText = (t) => {
    const text = displayText(t);
    const full = richText(text, Boolean(t.media?.all?.length));
    const chars = Array.from(text);
    if (!t.is_note_tweet || chars.length <= LONG) return full;
    let cut = chars.slice(0, LONG).join('');
    const space = cut.search(/\s\S*$/);
    if (space > LONG / 2) cut = cut.slice(0, space);
    const short = richText(cut, false);
    short.append(' ', el('button', { type: 'button', class: 'show-more', text: S().showMore, onclick: () => short.replaceWith(full) }));
    return short;
  };

  const photo = (m) => {
    const img = image(m.url, 'photo', () => link(m.url, { class: 'fallback', text: S().openImage }));
    img.alt = m.altText ?? '';
    if (!m.altText) return img;
    return el('div', { class: 'ph' }, img, el('span', { class: 'alt', text: 'ALT', title: m.altText }));
  };

  // Full-screen viewer for a card's photos. It reuses the blob URLs the card already holds, so
  // opening it costs no request. Its own host on <body> keeps it clear of the page's stacking
  // and overflow rules. Click outside the image or press Esc to close; arrows step through.
  const LIGHTBOX_STYLE = `
    :host { all: initial; }
    .lb { position: fixed; inset: 0; z-index: 2147483647; display: grid; place-items: center;
      background: rgba(0, 0, 0, 0.9); font: 15px system-ui, sans-serif; color: #fff; }
    img { max-width: 94vw; max-height: 88vh; object-fit: contain; display: block; }
    .cap { position: fixed; left: 50%; bottom: 16px; transform: translateX(-50%); max-width: 80vw;
      background: rgba(0, 0, 0, 0.6); padding: 6px 10px; border-radius: 6px; text-align: center; }
    button { position: fixed; width: 44px; height: 44px; border: 0; border-radius: 50%; cursor: pointer;
      color: #fff; background: rgba(39, 44, 48, 0.75); font: 24px/1 system-ui, sans-serif; }
    button:hover { background: rgba(39, 44, 48, 0.95); }
    .x { top: 12px; left: 12px; }
    .prev { left: 12px; top: 50%; transform: translateY(-50%); }
    .next { right: 12px; top: 50%; transform: translateY(-50%); }
  `;
  const lightbox = (imgs, start) => {
    let i = start;
    const host = el('div');
    const root = host.attachShadow({ mode: 'closed' });
    const big = el('img', { alt: '' });
    const cap = el('div', { class: 'cap' });
    const show = () => {
      big.src = imgs[i].src;
      big.alt = imgs[i].alt;
      cap.textContent = imgs[i].alt;
      cap.hidden = !imgs[i].alt;
    };
    const step = (d) => ((i = (i + d + imgs.length) % imgs.length), show());
    const close = () => (host.remove(), document.removeEventListener('keydown', onKey, true));
    const onKey = (e) => {
      if (e.key === 'Escape') close();
      else if (e.key === 'ArrowLeft' && imgs.length > 1) step(-1);
      else if (e.key === 'ArrowRight' && imgs.length > 1) step(1);
      else return;
      e.preventDefault();
      e.stopPropagation();
    };
    const many = imgs.length > 1;
    const lb = el(
      'div',
      { class: 'lb', onclick: (e) => e.target === lb && close() },
      big,
      cap,
      el('button', { type: 'button', class: 'x', title: S().close, text: '×', onclick: close }),
      many ? el('button', { type: 'button', class: 'prev', title: S().previous, text: '‹', onclick: () => step(-1) }) : null,
      many ? el('button', { type: 'button', class: 'next', title: S().next, text: '›', onclick: () => step(1) }) : null,
    );
    root.append(el('style', { text: LIGHTBOX_STYLE }), lb);
    document.addEventListener('keydown', onKey, true);
    show();
    (document.body ?? document.documentElement).append(host);
  };

  // The largest MP4 up to 720p-ish bitrate: enough on a card, and it streams fine.
  const pickVideo = (m) => {
    const mp4 = (m.variants ?? []).filter((v) => v.content_type === 'video/mp4' && v.url);
    const fit = mp4.filter((v) => v.bitrate <= 2500000).sort((a, b) => b.bitrate - a.bitrate)[0];
    return fit?.url ?? mp4.sort((a, b) => a.bitrate - b.bitrate)[0]?.url ?? m.url;
  };

  // Videos and GIFs show their poster and start playing the moment they are clicked: the
  // browser streams the MP4 straight from video.twimg.com inside a srcdoc iframe whose
  // <meta name="referrer"> keeps the page's address out of the request (cookies for that host
  // are partitioned by the browser anyway). Where the page's CSP or tracking protection blocks
  // that, the file is fetched whole through GM_xmlhttpRequest instead, as images are.
  const video = (m) => {
    const gif = m.type === 'gif';
    const status = el('span', { class: 'status', text: gif ? 'GIF' : '' });
    const box = el(
      'div',
      { class: 'video', role: 'button', tabindex: '0', title: S().play },
      m.thumbnail_url ? image(m.thumbnail_url) : null,
      el('span', { class: 'playwrap' }, icon('play')),
      status,
    );
    const src = MEDIA_URL(pickVideo(m));

    const download = async (slot) => {
      try {
        const blob = await request(
          src,
          'blob',
          (e) => e.total && (status.textContent = S().loading(Math.round((e.loaded / e.total) * 100))),
          120000,
        );
        const v = el('video', { playsinline: '' });
        Object.assign(v, gif ? { loop: true, muted: true, autoplay: true } : { controls: true, autoplay: true });
        v.onerror = () => v.replaceWith(link(m.url, { class: 'fallback', text: S().openVideo }));
        v.src = URL.createObjectURL(blob);
        slot.replaceWith(v);
      } catch (e) {
        slot.replaceWith(link(m.url, { class: 'fallback', text: S().videoFailed(e.message) }));
      }
    };

    const stream = () => {
      const frame = el('iframe', { class: 'vframe', allow: 'autoplay; fullscreen', allowfullscreen: '' });
      if (m.width && m.height) frame.style.aspectRatio = `${m.width} / ${m.height}`;
      frame.srcdoc =
        '<!doctype html><meta name="referrer" content="no-referrer"><style>html,body{margin:0;height:100%;background:#000}' +
        'video{display:block;width:100%;height:100%;object-fit:contain}</style>' +
        `<video playsinline ${gif ? 'loop muted autoplay' : 'controls autoplay'}></video>`;
      let fellBack = false;
      const fallBack = () => {
        if (fellBack) return;
        fellBack = true;
        frame.replaceWith(box);
        download(box);
      };
      frame.addEventListener('load', () => {
        const v = frame.contentDocument?.querySelector('video');
        if (!v) return fallBack();
        v.addEventListener('error', fallBack);
        v.src = src;
        v.play?.().catch(() => {});
      });
      box.replaceWith(frame);
    };

    const play = () => {
      if (box.dataset.busy) return;
      box.dataset.busy = '1';
      stream();
    };
    box.addEventListener('click', play);
    box.addEventListener('keydown', (e) => (e.key === 'Enter' || e.key === ' ') && (e.preventDefault(), play()));
    return box;
  };

  const renderMedia = (media, sensitive) => {
    const items = (media?.all ?? []).slice(0, 4);
    if (!items.length) return null;
    const box = el('div', { class: `media n${items.length}` });
    for (const m of items) box.append(m.type === 'photo' ? photo(m) : video(m));
    box.addEventListener('click', (e) => {
      const img = e.target.closest('img.photo');
      if (!img?.src || box.classList.contains('sensitive')) return;
      const imgs = [...box.querySelectorAll('img.photo')].filter((p) => p.src).map((p) => ({ src: p.src, alt: p.alt }));
      lightbox(imgs, Math.max(0, imgs.findIndex((p) => p.src === img.src)));
    });
    if (sensitive) {
      box.classList.add('sensitive');
      const reveal = el(
        'button',
        { type: 'button', class: 'reveal', onclick: () => (box.classList.remove('sensitive'), reveal.remove()) },
        el('span', { text: S().sensitive }),
        el('span', { text: S().show }),
      );
      box.append(reveal);
    }
    return box;
  };

  // Blue for individuals, gold for businesses, grey for government accounts.
  const badge = (a) => (a.verification?.verified ? icon('verified', `verified ${a.verification.type ?? ''}`) : null);

  const author = (t, small) => {
    const a = t.author ?? {};
    const profile = a.url ?? `https://x.com/${a.screen_name}`;
    const v = badge(a);
    return el(
      'div',
      { class: 'head' },
      a.avatar_url ? link(profile, {}, image(a.avatar_url, 'avatar')) : null,
      el(
        'div',
        { class: 'who' },
        link(profile, { class: 'name' }, el('span', { text: a.name ?? '' }), v),
        link(profile, { class: 'handle', text: `@${a.screen_name ?? '?'}` }),
        small ? el('span', { class: 'muted', text: `· ${shortDate(t.created_timestamp)}` }) : null,
      ),
      small ? null : link(t.url, { class: 'x', title: S().viewOnX }, icon('x')),
    );
  };

  const renderPoll = (poll) => {
    if (!poll?.choices?.length) return null;
    const top = Math.max(...poll.choices.map((c) => Number(c.percentage) || 0));
    const ended = Date.parse(poll.ends_at) < Date.now();
    return el(
      'div',
      { class: 'poll' },
      ...poll.choices.map((c) =>
        el(
          'div',
          { class: (Number(c.percentage) || 0) === top ? 'bar win' : 'bar' },
          el('div', { class: 'fill', style: `width:${Number(c.percentage) || 0}%` }),
          el('span', { text: c.label }),
          el('span', { text: `${c.percentage}%` }),
        ),
      ),
      el('div', { class: 'muted', text: [S().votes(number(poll.total_votes ?? 0)), ended ? S().finalResults : null].filter(Boolean).join(' · ') }),
    );
  };

  // A block that opens `url` when clicked anywhere but on its own links and media controls.
  // (An <a> around it would swallow clicks on the video player and the reveal button.)
  const clickable = (url, props, ...children) => {
    const box = el('div', { ...props, style: 'cursor:pointer' }, ...children);
    box.addEventListener('click', (e) => {
      if (!e.target.closest('a, button, video, iframe, .video, .reveal, img.photo')) window.open(url, '_blank', 'noopener,noreferrer');
    });
    return box;
  };

  const renderQuote = (q) =>
    clickable(
      q.url,
      { class: 'quote' },
      author(q, true),
      tweetText(q),
      renderMedia(q.media, q.possibly_sensitive),
    );

  // The tweet being replied to, drawn above the main one with a thread line, as on x.com.
  const renderParent = (p) => {
    const a = p.author ?? {};
    return clickable(
      p.url,
      { class: 'parent' },
      el('div', { class: 'rail' }, a.avatar_url ? image(a.avatar_url, 'avatar') : null, el('div', { class: 'line' })),
      el(
        'div',
        { class: 'pbody' },
        el(
          'div',
          { class: 'head' },
          el(
            'div',
            { class: 'who' },
            el(
              'span',
              { class: 'name' },
              el('span', { text: a.name ?? '' }),
              badge(a),
              el('span', { class: 'date', text: `· ${shortDate(p.created_timestamp)}` }),
            ),
            el('span', { class: 'handle', text: `@${a.screen_name ?? '?'}` }),
          ),
        ),
        tweetText(p),
        renderMedia(p.media, p.possibly_sensitive),
      ),
    );
  };

  const renderTweet = (t) => {
    const d = new Date(t.created_timestamp * 1000);
    const when = `${d.toLocaleTimeString(locale(), { hour: 'numeric', minute: '2-digit', hour12: true })} · ${d.toLocaleDateString(locale(), { year: 'numeric', month: lang() === 'ja' ? 'long' : 'short', day: 'numeric' })}`;
    const note = typeof t.community_note?.text === 'string' ? t.community_note.text : null;
    const copy = el('button', {
      type: 'button',
      class: 'share',
      title: S().copyLink,
      onclick: () =>
        navigator.clipboard.writeText(t.url).then(() => {
          copy.lastChild.textContent = S().copied;
        }),
    });
    // Icon only, so the counts fit on one line; the label shows after copying.
    copy.append(icon('link', 'link'), el('span'));
    // x.com's order: replies, reposts, likes, views, bookmarks. A count fxtwitter does not
    // return (views on old tweets) is left out rather than shown as 0.
    const stat = (name, n, label, cls = '') =>
      typeof n === 'number' ? link(t.url, { class: cls, title: `${number(n)} ${label}` }, icon(name), el('span', { text: compact(n) })) : null;
    const reposts = (t.retweets ?? 0) + (t.quotes ?? 0);
    const parent = el('div');
    // X's embed shows the parent tweet and no "Replying to @x" line. The line appears only when
    // the parent cannot be fetched (deleted, protected), so the reply still says what it answers.
    const replyTo = el('div');
    const showReplyTo = () =>
      t.replying_to &&
      replyTo.replaceChildren(
        el('div', { class: 'reply-to' }, S().replyingTo, link(`https://x.com/${t.replying_to}`, { text: `@${t.replying_to}` })),
      );
    if (t.replying_to_status) {
      request(API + t.replying_to_status, 'json')
        .then((data) => (data?.tweet ? parent.replaceChildren(renderParent(data.tweet)) : showReplyTo()))
        .catch(showReplyTo);
    } else {
      showReplyTo();
    }
    return el(
      'div',
      { class: 'card' },
      parent,
      author(t, false),
      replyTo,
      tweetText(t),
      renderPoll(t.poll),
      renderMedia(t.media, t.possibly_sensitive),
      t.quote ? renderQuote(t.quote) : null,
      note ? el('div', { class: 'note' }, el('b', { text: S().note }), el('span', { text: note })) : null,
      link(t.url, { class: 'time', text: when }),
      el(
        'div',
        { class: 'actions' },
        stat('reply', t.replies, S().replies, 'r'),
        stat('repost', typeof t.retweets === 'number' ? reposts : undefined, S().reposts(number(t.quotes ?? 0)), 'rp'),
        stat('heart', t.likes, S().likes, 'lk'),
        stat('views', t.views, S().views, 'vw'),
        stat('bookmark', t.bookmarks, S().bookmarks, 'bm'),
        copy,
      ),
      link(t.url, {
        class: 'more',
        text: t.replies ? S().readReplies(compact(t.replies)) : S().viewOnX,
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
        applyTheme(host);
        if ([401, 403, 404].includes(e.status)) out.replaceChildren(renderGone(node, id, e.status));
        else if (iframe) host.replaceWith(node);
        else out.replaceChildren(el('div', { class: 'err', text: S().fetchFailed(e.message) }), el('slot'));
      }
    });
    observer.observe(host);
  };

  // Deleted, protected or suspended: say so, keep the page's own copy of the text visible, and
  // point at the Wayback Machine's captures of the tweet.
  const renderGone = (node, id, status) => {
    const href = [...(node.querySelectorAll?.('a[href]') ?? [])]
      .map((a) => a.href)
      .reverse()
      .find((h) => h.includes(`/status/${id}`) || h.includes(`/statuses/${id}`));
    const user = href?.match(/\.com\/([^/]+)\/status/)?.[1] ?? 'i';
    return el(
      'div',
      { class: 'card gone' },
      el('div', { class: 'why', text: status === 404 ? S().deleted : S().restricted }),
      el('slot'),
      link(`https://web.archive.org/web/*/https://twitter.com/${user}/status/${id}*`, { text: S().wayback }),
    );
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
