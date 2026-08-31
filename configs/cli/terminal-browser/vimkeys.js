// Surfingkeys の代わり。terminal-browser は拡張を読み込めない (Electron の loadExtension を
// 露出していない) ので、`--preload` でページ側に、`--main-script` でメインプロセス側に入る。
// Surfingkeys の content script / background script と同じ二層構成。
//
// ここはページ側。キー入力、ヒント、visual モード、yank、URL 操作を持つ。タブ操作のように
// ページから手が届かないものは ipcRenderer で main.js に投げる。
//
// 再現していないものと、その理由は docs/terminal-browser-vimkeys.md に書いた。要約すると
// Chrome という製品固有の面 (ブックマーク / 履歴 DB / ダウンロード / 拡張一覧 / chrome:// /
// プロキシ / セッション) は terminal-browser に対応物が無いので再現先が存在しない。

(() => {
  const KEYS = "asdfghjklqwertyuiopzxcvbnm";
  const SCROLL_STEP = 70;
  const MARKS_KEY = "vimkeys.marks";

  let ipc = null;
  try {
    // preload は Node 統合を持つ。無ければタブ操作だけ黙って落ちる。
    ipc = require("electron").ipcRenderer;
  } catch {
    ipc = null;
  }
  const send = (cmd, arg) => ipc && ipc.send("vimkeys", { cmd, arg });

  // ─── 状態 ───────────────────────────────────────────────────────────
  let mode = "normal"; // normal | hints | visual | prompt
  let hints = null;
  let visual = null;
  let prompt = null;
  let pending = ""; // 複数キーの途中 (g, y, z, ; など)
  let pendingTimer = null;
  let lastAction = null; // `.` 用
  let lastSearch = "";

  const scroller = () => document.scrollingElement || document.documentElement;

  const isTyping = () => {
    const el = document.activeElement;
    if (!el) return false;
    if (el.isContentEditable) return true;
    return ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName);
  };

  // ─── 通知 ───────────────────────────────────────────────────────────
  let toastEl = null;
  let toastTimer = null;
  const toast = (text) => {
    if (!toastEl) {
      toastEl = document.createElement("div");
      toastEl.style.cssText =
        "position:fixed;left:8px;bottom:8px;z-index:2147483647;max-width:60vw;" +
        "background:#111;color:#eee;font:12px ui-monospace,monospace;padding:4px 8px;" +
        "border-radius:4px;opacity:.94;pointer-events:none;white-space:pre-wrap";
    }
    toastEl.textContent = text;
    document.body.append(toastEl);
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.remove(), 1600);
  };

  const copy = (text) => {
    // navigator.clipboard は要権限。execCommand なら preload の隔離ワールドでも通る。
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.style.cssText = "position:fixed;opacity:0";
    document.body.append(ta);
    ta.select();
    try {
      document.execCommand("copy");
    } finally {
      ta.remove();
    }
    toast(text.length > 120 ? text.slice(0, 120) + "…" : text);
  };

  // ─── ヒント ─────────────────────────────────────────────────────────
  const CLICKABLE =
    'a[href], button, input:not([type=hidden]), select, textarea, summary, ' +
    '[role="button"], [role="link"], [role="tab"], [role="menuitem"], [role="checkbox"], ' +
    "[onclick], [tabindex]:not([tabindex='-1'])";
  const IMAGES = "img, [role=img], button, input[type=submit], input[type=button]";
  const EDITABLE = "input:not([type=hidden]):not([type=submit]):not([type=button]), textarea, [contenteditable=true]";

  const visibleIn = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return false;
    if (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) return false;
    const s = getComputedStyle(el);
    return s.visibility !== "hidden" && s.display !== "none" && s.opacity !== "0";
  };

  const scrollables = () =>
    [...document.querySelectorAll("*")].filter((el) => {
      if (!visibleIn(el)) return false;
      const s = getComputedStyle(el);
      const scrolls = /auto|scroll|overlay/.test(s.overflowY + s.overflowX);
      return scrolls && el.scrollHeight > el.clientHeight + 8;
    });

  const labelFor = (i, total) => {
    if (total <= KEYS.length) return KEYS[i];
    return KEYS[Math.floor(i / KEYS.length)] + KEYS[i % KEYS.length];
  };

  const clearHints = () => {
    if (!hints) return;
    hints.layer.remove();
    hints = null;
    if (mode === "hints") mode = "normal";
  };

  // action(el) を返す。multi が真なら選んでも閉じず、Esc まで拾い続ける (cf, yma, ymv)。
  const startHints = (selectorOrList, action, { multi = false, label = "" } = {}) => {
    clearHints();
    const targets = (
      Array.isArray(selectorOrList)
        ? selectorOrList
        : [...document.querySelectorAll(selectorOrList)]
    ).filter(visibleIn);
    if (!targets.length) {
      toast("no targets");
      return;
    }

    const layer = document.createElement("div");
    layer.style.cssText =
      "position:fixed;inset:0;z-index:2147483647;pointer-events:none;font:bold 11px ui-monospace,monospace";
    const map = new Map();
    targets.forEach((el, i) => {
      const key = labelFor(i, targets.length);
      map.set(key, el);
      const r = el.getBoundingClientRect();
      const tag = document.createElement("span");
      tag.textContent = key;
      tag.dataset.k = key;
      tag.style.cssText =
        `position:absolute;left:${Math.max(0, r.left)}px;top:${Math.max(0, r.top)}px;` +
        "background:#f2d14a;color:#111;border:1px solid #8a6d00;border-radius:3px;" +
        "padding:0 3px;line-height:14px;text-transform:uppercase;" +
        "box-shadow:0 1px 2px rgba(0,0,0,.4)";
      layer.append(tag);
    });
    document.body.append(layer);
    hints = { layer, map, buffer: "", action, multi };
    mode = "hints";
    if (label) toast(label);
  };

  const feedHint = (ch) => {
    hints.buffer += ch;
    const hit = hints.map.get(hints.buffer);
    if (hit) {
      const { action, multi } = hints;
      if (multi) {
        hints.buffer = "";
        const tag = hints.layer.querySelector(`[data-k="${CSS.escape(hints.buffer)}"]`);
        if (tag) tag.style.background = "#9ad";
        action(hit);
      } else {
        clearHints();
        action(hit);
      }
      return;
    }
    let alive = false;
    for (const k of hints.map.keys()) {
      if (k.startsWith(hints.buffer)) {
        alive = true;
        break;
      }
    }
    if (!alive) {
      if (hints.multi) hints.buffer = "";
      else clearHints();
    }
  };

  const click = (el) => {
    if (typeof el.focus === "function") el.focus();
    el.click();
  };

  // ─── visual モード ──────────────────────────────────────────────────
  const enterVisual = (selectWhole) => {
    const sel = getSelection();
    if (selectWhole) {
      const el = document.elementFromPoint(innerWidth / 2, innerHeight / 3);
      if (el) {
        const r = document.createRange();
        r.selectNodeContents(el);
        sel.removeAllRanges();
        sel.addRange(r);
      }
    } else if (sel.rangeCount === 0 || sel.isCollapsed) {
      // カーソルが無ければ画面先頭のテキストノードに置く。
      const el = document.elementFromPoint(8, 8);
      if (el) {
        const r = document.createRange();
        r.setStart(el, 0);
        r.collapse(true);
        sel.removeAllRanges();
        sel.addRange(r);
      }
    }
    visual = { anchor: true };
    mode = "visual";
    toast("visual");
  };

  const exitVisual = ({ keep = false } = {}) => {
    if (!keep) getSelection().removeAllRanges();
    visual = null;
    mode = "normal";
  };

  const extend = (unit, dir) => {
    const sel = getSelection();
    if (!sel.rangeCount) return;
    sel.modify("extend", dir, unit);
  };

  // ─── 検索 ───────────────────────────────────────────────────────────
  const runFind = (text, backwards = false) => {
    if (!text) return;
    lastSearch = text;
    // find() は非標準だが Chromium にある。Surfingkeys 同様、素の検索で足りる。
    const ok = window.find(text, false, backwards, true, false, true, false);
    if (!ok) toast(`not found: ${text}`);
  };

  // ─── プロンプト (: / t / 検索) ──────────────────────────────────────
  const openPrompt = (label, onSubmit, initial = "") => {
    closePrompt();
    const box = document.createElement("div");
    box.style.cssText =
      "position:fixed;left:0;right:0;bottom:0;z-index:2147483647;background:#111;color:#eee;" +
      "font:13px ui-monospace,monospace;display:flex;gap:6px;padding:6px 8px;align-items:center";
    const tag = document.createElement("span");
    tag.textContent = label;
    tag.style.cssText = "color:#f2d14a;flex:0 0 auto";
    const input = document.createElement("input");
    input.value = initial;
    input.style.cssText =
      "flex:1 1 auto;background:transparent;border:0;outline:0;color:inherit;font:inherit";
    box.append(tag, input);
    document.body.append(box);
    input.focus();
    prompt = { box, input, onSubmit };
    mode = "prompt";
  };

  const closePrompt = () => {
    if (!prompt) return;
    prompt.box.remove();
    prompt = null;
    if (mode === "prompt") mode = "normal";
  };

  // ─── マーク ─────────────────────────────────────────────────────────
  const marks = () => {
    try {
      return JSON.parse(localStorage.getItem(MARKS_KEY) || "{}");
    } catch {
      return {};
    }
  };
  const setMark = (ch) => {
    const m = marks();
    m[ch] = location.href;
    localStorage.setItem(MARKS_KEY, JSON.stringify(m));
    toast(`mark ${ch}`);
  };
  const jumpMark = (ch, newTab) => {
    const url = marks()[ch];
    if (!url) return toast(`no mark ${ch}`);
    if (newTab) send("newTab", url);
    else location.href = url;
  };

  // ─── URL 操作 ───────────────────────────────────────────────────────
  const goUp = () => {
    const u = new URL(location.href);
    const parts = u.pathname.split("/").filter(Boolean);
    parts.pop();
    u.pathname = "/" + parts.join("/");
    u.search = "";
    u.hash = "";
    location.href = u.href;
  };
  const goRoot = () => (location.href = location.origin);
  const stripQuery = () => (location.href = location.origin + location.pathname);
  const stripHash = () => (location.href = location.href.split("#")[0]);

  // 次/前のリンク。rel を優先し、無ければテキストで探す。
  const seqLink = (next) => {
    const rel = document.querySelector(next ? "[rel=next]" : "[rel=prev]");
    if (rel) return click(rel);
    const words = next ? ["next", "次", "»", ">"] : ["prev", "前", "«", "<"];
    const a = [...document.querySelectorAll("a")].find((x) => {
      const t = (x.textContent || "").trim().toLowerCase();
      return t && words.some((w) => t.includes(w)) && t.length < 24;
    });
    if (a) click(a);
    else toast(next ? "no next link" : "no prev link");
  };

  // ─── フォーム ───────────────────────────────────────────────────────
  const formData = () => {
    const out = {};
    for (const el of document.querySelectorAll("input[name], textarea[name], select[name]")) {
      out[el.name] = el.type === "checkbox" || el.type === "radio" ? el.checked : el.value;
    }
    return out;
  };
  const fillForm = (data) => {
    for (const [k, v] of Object.entries(data)) {
      const el = document.querySelector(`[name="${CSS.escape(k)}"]`);
      if (!el) continue;
      if (el.type === "checkbox" || el.type === "radio") el.checked = !!v;
      else el.value = v;
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    }
  };

  const zoomBy = (d) => {
    const cur = parseFloat(document.body.style.zoom || "1");
    document.body.style.zoom = String(d === 0 ? 1 : Math.max(0.25, Math.min(5, cur + d)));
  };

  // ─── コマンド表 ─────────────────────────────────────────────────────
  // キーは Surfingkeys の既定に合わせる。値は [説明, 実行, 記録するか]。
  const CMD = {
    // スクロール
    j: ["Scroll down", () => scrollBy(0, SCROLL_STEP)],
    k: ["Scroll up", () => scrollBy(0, -SCROLL_STEP)],
    h: ["Scroll left", () => scrollBy(-SCROLL_STEP, 0)],
    l: ["Scroll right", () => scrollBy(SCROLL_STEP, 0)],
    d: ["Scroll half page down", () => scrollBy(0, innerHeight / 2)],
    u: ["Scroll half page up", () => scrollBy(0, -innerHeight / 2)],
    gg: ["Scroll to top", () => scrollTo(0, 0)],
    G: ["Scroll to bottom", () => scrollTo(0, scroller().scrollHeight)],
    0: ["Scroll all the way left", () => scrollTo(0, scrollY)],
    $: ["Scroll all the way right", () => scrollTo(scroller().scrollWidth, scrollY)],
    ";fs": ["Focus scrollable element", () => startHints(scrollables(), (el) => el.focus())],

    // ヒント
    f: ["Open a link", () => startHints(CLICKABLE, click), true],
    af: ["Open a link in active new tab", () => startHints("a[href]", (el) => send("newTab", el.href))],
    gf: [
      "Open a link in non-active new tab",
      () => startHints("a[href]", (el) => send("newTabBackground", el.href)),
    ],
    cf: [
      "Open multiple links in a new tab",
      () => startHints("a[href]", (el) => send("newTabBackground", el.href), { multi: true, label: "multi: Esc to finish" }),
    ],
    q: ["Click on an image or a button", () => startHints(IMAGES, click)],
    ya: ["Copy a link URL", () => startHints("a[href]", (el) => copy(el.href))],
    yma: [
      "Copy multiple link URLs",
      () => {
        const acc = [];
        startHints("a[href]", (el) => acc.push(el.href), { multi: true, label: "multi: Esc to copy" });
        hints.onDone = () => acc.length && copy(acc.join("\n"));
      },
    ],
    yv: ["Yank text of an element", () => startHints(CLICKABLE, (el) => copy(el.textContent.trim()))],
    ymv: [
      "Yank text of multiple elements",
      () => {
        const acc = [];
        startHints(CLICKABLE, (el) => acc.push(el.textContent.trim()), { multi: true, label: "multi: Esc to copy" });
        hints.onDone = () => acc.length && copy(acc.join("\n"));
      },
    ],
    yc: [
      "Copy a column of a table",
      () =>
        startHints("td, th", (cell) => {
          const idx = [...cell.parentElement.children].indexOf(cell);
          const table = cell.closest("table");
          if (!table) return;
          const col = [...table.rows].map((r) => (r.cells[idx] ? r.cells[idx].textContent.trim() : ""));
          copy(col.join("\n"));
        }),
    ],
    yq: ["Copy pre text", () => startHints("pre, code", (el) => copy(el.textContent))],
    yi: ["Yank text of an input", () => startHints(EDITABLE, (el) => copy(el.value ?? el.textContent))],
    i: ["Go to edit box", () => startHints(EDITABLE, (el) => el.focus())],
    gi: ["Go to the first edit box", () => {
      const el = [...document.querySelectorAll(EDITABLE)].find(visibleIn);
      if (el) el.focus();
      else toast("no edit box");
    }],
    O: ["Open detected links from text", () => startHints("a[href]", click)],
    ";m": ["Mouse out last element", () => document.activeElement && document.activeElement.blur()],

    // 履歴 / リロード
    S: ["Go back in history", () => history.back()],
    D: ["Go forward in history", () => history.forward()],
    r: ["Reload the page", () => location.reload()],

    // URL
    gu: ["Go up one path in the URL", goUp],
    gU: ["Go to root of current URL hierarchy", goRoot],
    "g?": ["Reload without query string", stripQuery],
    "g#": ["Reload without hash fragment", stripHash],
    "[[": ["Click on the previous link", () => seqLink(false)],
    "]]": ["Click on the next link", () => seqLink(true)],

    // yank
    yy: ["Copy current page's URL", () => copy(location.href)],
    yh: ["Copy current page's host", () => copy(location.host)],
    yl: ["Copy current page's title", () => copy(document.title)],
    ys: ["Copy current page's source", () => copy(document.documentElement.outerHTML)],
    yf: ["Copy form data in JSON", () => copy(JSON.stringify(formData(), null, 2))],
    yp: ["Copy form data for POST", () => copy(new URLSearchParams(formData()).toString())],
    gs: ["View page source", () => copy(document.documentElement.outerHTML)],

    // zoom
    zi: ["Zoom in", () => zoomBy(0.1)],
    zo: ["Zoom out", () => zoomBy(-0.1)],
    zr: ["Zoom reset", () => zoomBy(0)],

    // visual / 検索
    v: ["Toggle visual mode", () => enterVisual(false)],
    zv: ["Enter visual mode, select whole element", () => enterVisual(true)],
    V: ["Restore visual mode", () => enterVisual(false)],
    n: ["Next found text", () => runFind(lastSearch, false)],
    N: ["Previous found text", () => runFind(lastSearch, true)],
    "*": ["Find selected text", () => runFind(String(getSelection()).trim())],
    "/": ["Find in page", () => openPrompt("/", (t) => runFind(t))],

    // タブ (main.js 経由)
    x: ["Close current tab", () => send("closeTab")],
    X: ["Restore closed tab", () => send("restoreTab")],
    on: ["Open newtab", () => send("newTab", "about:blank")],
    t: ["Open a URL", () => openPrompt("open", (t) => send("newTab", t))],
    go: ["Open a URL in current tab", () => openPrompt("goto", (t) => (location.href = t))],
    gt: ["Go to next tab", () => send("nextTab")],
    gT: ["Go to previous tab", () => send("prevTab")],
    "<<": ["Move current tab to left", () => send("moveTabLeft")],
    ">>": ["Move current tab to right", () => send("moveTabRight")],
    yt: ["Duplicate current tab", () => send("newTab", location.href)],
    yT: ["Duplicate current tab in background", () => send("newTabBackground", location.href)],
    gxx: ["Close all tabs except current one", () => send("closeOthers")],
    gxt: ["Close tab on left", () => send("closeLeft")],
    gxT: ["Close tab on right", () => send("closeRight")],
    T: ["Choose a tab", () => send("chooseTab")],

    // その他
    ".": ["Repeat last action", () => lastAction && lastAction()],
    "?": ["Show usage", () => showUsage()],
  };

  // マーク系はキーの後に 1 文字取るので表に載せず、別で捌く。
  const PREFIX_ONE_ARG = { m: setMark, "'": (c) => jumpMark(c, false) };

  // ─── ヘルプ ─────────────────────────────────────────────────────────
  let usageEl = null;
  const showUsage = () => {
    if (usageEl) {
      usageEl.remove();
      usageEl = null;
      return;
    }
    usageEl = document.createElement("div");
    usageEl.style.cssText =
      "position:fixed;inset:5% 10%;z-index:2147483647;overflow:auto;background:#111;color:#eee;" +
      "font:12px ui-monospace,monospace;padding:16px;border-radius:6px;column-width:22em;column-gap:2em";
    const rows = Object.entries(CMD)
      .map(([k, [desc]]) => `<div><b style="color:#f2d14a">${k.replace(/</g, "&lt;")}</b>  ${desc}</div>`)
      .join("");
    usageEl.innerHTML =
      rows + '<div style="margin-top:8px;color:#888">m&lt;c&gt; set mark · \'&lt;c&gt; jump · Esc close</div>';
    document.body.append(usageEl);
  };
  const closeUsage = () => {
    if (usageEl) {
      usageEl.remove();
      usageEl = null;
    }
  };

  // ─── キー処理 ───────────────────────────────────────────────────────
  const resetPending = () => {
    pending = "";
    clearTimeout(pendingTimer);
  };

  const armPending = () => {
    clearTimeout(pendingTimer);
    pendingTimer = setTimeout(resetPending, 900);
  };

  // pending + key が、まだ伸びる可能性のある接頭辞かどうか。
  const isPrefix = (s) =>
    Object.keys(CMD).some((k) => k.length > s.length && k.startsWith(s)) ||
    Object.keys(PREFIX_ONE_ARG).some((k) => k === s);

  const handleNormal = (e) => {
    const key = e.key;
    if (key.length !== 1 && key !== "Escape") return; // 修飾なしの 1 文字だけ見る

    // 直前が m / ' なら、次の 1 文字は引数。
    if (PREFIX_ONE_ARG[pending]) {
      const fn = PREFIX_ONE_ARG[pending];
      resetPending();
      e.preventDefault();
      fn(key);
      return;
    }

    const seq = pending + key;

    if (CMD[seq]) {
      e.preventDefault();
      resetPending();
      const [, run, record] = CMD[seq];
      if (record) lastAction = run;
      run();
      return;
    }

    if (isPrefix(seq)) {
      e.preventDefault();
      pending = seq;
      armPending();
      return;
    }

    resetPending();
  };

  document.addEventListener(
    "keydown",
    (e) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;

      if (e.key === "Escape") {
        e.preventDefault();
        closeUsage();
        if (hints) {
          if (hints.onDone) hints.onDone();
          clearHints();
          return;
        }
        if (prompt) return closePrompt();
        if (visual) return exitVisual();
        if (isTyping() && document.activeElement.blur) document.activeElement.blur();
        resetPending();
        return;
      }

      if (mode === "prompt") {
        if (e.key === "Enter") {
          e.preventDefault();
          const { onSubmit, input } = prompt;
          const value = input.value;
          closePrompt();
          onSubmit(value);
        }
        return; // それ以外は入力欄に渡す
      }

      if (mode === "hints") {
        if (KEYS.includes(e.key.toLowerCase())) {
          e.preventDefault();
          e.stopPropagation();
          feedHint(e.key.toLowerCase());
        }
        return;
      }

      if (mode === "visual") {
        const M = {
          h: ["character", "left"],
          l: ["character", "right"],
          j: ["line", "forward"],
          k: ["line", "backward"],
          w: ["word", "forward"],
          b: ["word", "backward"],
          0: ["lineboundary", "left"],
          $: ["lineboundary", "right"],
        };
        if (M[e.key]) {
          e.preventDefault();
          extend(M[e.key][0], M[e.key][1]);
          return;
        }
        if (e.key === "y") {
          e.preventDefault();
          copy(String(getSelection()));
          exitVisual();
          return;
        }
        if (e.key === "v") {
          e.preventDefault();
          exitVisual();
          return;
        }
        return;
      }

      if (isTyping()) return;
      handleNormal(e);
    },
    true, // capture: ページ側のハンドラより先に取る
  );

  addEventListener("scroll", () => hints && clearHints(), { passive: true, capture: true });
  addEventListener("resize", () => hints && clearHints(), { passive: true });

  // main.js からの応答 (タブ一覧など)
  if (ipc) {
    ipc.on("vimkeys:reply", (_e, payload) => {
      if (payload && payload.toast) toast(payload.toast);
    });
  }
})();
