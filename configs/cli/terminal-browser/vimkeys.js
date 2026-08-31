// Surfingkeys の代わり。terminal-browser は拡張を読み込めない (Electron の loadExtension を
// 露出していない) ので、`--preload` で同じことをする。隔離ワールドで走るが DOM は共有なので
// キーハンドラも overlay も普通に置ける。
//
// 入力中は何も奪わない。input / textarea / contenteditable にフォーカスがあるときと、
// 修飾キーが付いているときは素通しする。terminal-browser 自身のショートカット
// (パレット等) と食い合わないように、単独キーだけを見る。

(() => {
  const KEYS = "asdfghjklqwertyuiopzxcvbnm";
  const SCROLL_LINE = 60;

  let hints = null; // { layer, map, buffer }
  let pendingG = false;

  const isTyping = () => {
    const el = document.activeElement;
    if (!el) return false;
    if (el.isContentEditable) return true;
    const tag = el.tagName;
    return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT";
  };

  // ヒントの宛先。href を辿るだけでは JS で動く UI を拾えないので、role と
  // tabindex も見る。クリックできるが画面外のものは除く。
  const CLICKABLE =
    'a[href], button, input, select, textarea, summary, [role="button"], [role="link"], [role="tab"], [role="menuitem"], [onclick], [tabindex]:not([tabindex="-1"])';

  const visible = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return false;
    if (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) return false;
    const style = getComputedStyle(el);
    if (style.visibility === "hidden" || style.display === "none" || style.opacity === "0") return false;
    return true;
  };

  // 26 個までは 1 文字、それ以上は 2 文字。よく使う手前から短い札を配る。
  const labelFor = (i, total) => {
    if (total <= KEYS.length) return KEYS[i];
    const a = Math.floor(i / KEYS.length);
    return KEYS[a] + KEYS[i % KEYS.length];
  };

  const clearHints = () => {
    if (!hints) return;
    hints.layer.remove();
    hints = null;
  };

  const showHints = (newTab) => {
    clearHints();
    const targets = [...document.querySelectorAll(CLICKABLE)].filter(visible);
    if (targets.length === 0) return;

    const layer = document.createElement("div");
    layer.style.cssText =
      "position:fixed;inset:0;z-index:2147483647;pointer-events:none;font:bold 11px ui-monospace,monospace";

    const map = new Map();
    targets.forEach((el, i) => {
      const label = labelFor(i, targets.length);
      map.set(label, el);
      const r = el.getBoundingClientRect();
      const tag = document.createElement("span");
      tag.textContent = label;
      tag.style.cssText =
        `position:absolute;left:${Math.max(0, r.left)}px;top:${Math.max(0, r.top)}px;` +
        "background:#f2d14a;color:#111;border:1px solid #8a6d00;border-radius:3px;" +
        "padding:0 3px;line-height:14px;text-transform:uppercase;box-shadow:0 1px 2px rgba(0,0,0,.4)";
      layer.append(tag);
    });

    document.body.append(layer);
    hints = { layer, map, buffer: "", newTab };
  };

  const activate = (el, newTab) => {
    const href = el.getAttribute && el.getAttribute("href");
    if (newTab && href) {
      // terminal-browser 側が新しいタブとして拾う。--open-tabs-in-popup-stack を
      // 付けて開いた場合はページ上のポップアップになる。
      window.open(el.href, "_blank");
      return;
    }
    if (typeof el.focus === "function") el.focus();
    el.click();
  };

  const feedHint = (ch) => {
    hints.buffer += ch;
    const hit = hints.map.get(hints.buffer);
    if (hit) {
      const newTab = hints.newTab;
      clearHints();
      activate(hit, newTab);
      return;
    }
    // まだ一致しない。前方一致が残っていなければ諦める。
    let alive = false;
    for (const label of hints.map.keys()) {
      if (label.startsWith(hints.buffer)) {
        alive = true;
        break;
      }
    }
    if (!alive) clearHints();
  };

  const scroller = () => document.scrollingElement || document.documentElement;

  const ACTIONS = {
    j: () => scrollBy(0, SCROLL_LINE),
    k: () => scrollBy(0, -SCROLL_LINE),
    h: () => scrollBy(-SCROLL_LINE, 0),
    l: () => scrollBy(SCROLL_LINE, 0),
    d: () => scrollBy(0, innerHeight / 2),
    u: () => scrollBy(0, -innerHeight / 2),
    G: () => scrollTo(0, scroller().scrollHeight),
    H: () => history.back(),
    L: () => history.forward(),
    r: () => location.reload(),
    f: () => showHints(false),
    F: () => showHints(true),
  };

  document.addEventListener(
    "keydown",
    (e) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;

      if (e.key === "Escape") {
        clearHints();
        if (isTyping() && document.activeElement.blur) document.activeElement.blur();
        return;
      }

      if (hints) {
        if (KEYS.includes(e.key.toLowerCase())) {
          e.preventDefault();
          e.stopPropagation();
          feedHint(e.key.toLowerCase());
        }
        return;
      }

      if (isTyping()) return;

      // gg で先頭へ。g を 1 回押した状態を覚えておく。
      if (pendingG) {
        pendingG = false;
        if (e.key === "g") {
          e.preventDefault();
          scrollTo(0, 0);
          return;
        }
      }
      if (e.key === "g") {
        pendingG = true;
        setTimeout(() => (pendingG = false), 700);
        return;
      }

      const action = ACTIONS[e.key];
      if (!action) return;
      e.preventDefault();
      action();
    },
    true, // capture: ページ側のハンドラより先に取る
  );

  // スクロールやリサイズで札の位置がずれるので、動いたら消す。追従させるより素直。
  addEventListener("scroll", clearHints, { passive: true, capture: true });
  addEventListener("resize", clearHints, { passive: true });
})();
