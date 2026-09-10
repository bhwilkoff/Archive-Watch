/* Exercise the REAL tv.js focus engine in a minimal DOM shim.
   (The project's documented web verification pattern: run the real script in a
   Node DOM shim rather than trusting a headless browser's timer behavior.) */
import fs from 'fs';

let idc = 0;
class El {
  constructor(tag, rect, attrs = {}) {
    this.tagName = tag.toUpperCase();
    this.rect = rect;                 // {left, top, width, height}
    this.attrs = attrs;
    this.children = [];
    this.parent = null;
    this.classList = { add() {}, contains() { return false; } };
    this.style = {};
    this.name = attrs.name || `${tag}#${idc++}`;
    this.focusCount = 0;
  }
  getBoundingClientRect() {
    const r = this.rect;
    return { left: r.left, top: r.top, width: r.width, height: r.height,
             right: r.left + r.width, bottom: r.top + r.height };
  }
  focus() {
    this.focusCount++; doc.activeElement = this;
    // tv.js records the last focused element per route from focusin;
    // without dispatching it the shim cannot exercise Back at all.
    focusinHandlers.forEach(h => h({ target: this }));
  }
  scrollIntoView() {}
  getAttribute(k) { return this.attrs[k] ?? null; }
  hasAttribute(k) { return k in this.attrs; }
  closest(sel) { return sel === '[hidden]' ? null : (matches(this, sel) ? this : null); }
  click() { this.clicked = true; }
  addEventListener() {}
}

function matches(el, sel) {
  return sel.split(',').some(s => {
    s = s.trim();
    if (s === 'a[href]') return el.tagName === 'A' && 'href' in el.attrs;
    if (s.startsWith('button')) return el.tagName === 'BUTTON';
    if (s.startsWith('input')) return el.tagName === 'INPUT';
    if (s.startsWith('select')) return el.tagName === 'SELECT';
    if (s.startsWith('[tabindex]')) return 'tabindex' in el.attrs && el.attrs.tabindex !== '-1';
    return false;
  });
}

const nodes = [];
const focusinHandlers = [];
const hashHandlers = [];
const doc = {
  activeElement: null,
  hidden: false,
  readyState: 'complete',
  documentElement: { classList: { add: (...c) => { doc._cls = (doc._cls||[]).concat(c); } } },
  body: { },
  querySelectorAll: (sel) => nodes.filter(n => matches(n, sel)),
  querySelector: (sel) => nodes.find(n => matches(n, sel)) || null,
  addEventListener: (type, fn) => { if (type === 'focusin') focusinHandlers.push(fn); },
  createElement: () => new El('div', {left:0,top:0,width:0,height:0}),
};

const handlers = [];
global.document = doc;
global.window = {
  addEventListener: (type, fn) => {
    if (type === 'keydown') handlers.push(fn);
    if (type === 'hashchange') hashHandlers.push(fn);
  },
  close: () => {},
};
Object.defineProperty(global, 'navigator', { value: { userAgent: 'Mozilla/5.0 (SMART-TV; LINUX; Tizen 7.0) AppleWebKit' }, configurable: true });
global.location = { search: '', hash: '#/home' };
global.history = { back: () => { global._wentBack = true; } };
global.getComputedStyle = () => ({ visibility: 'visible', display: 'block' });
global.MutationObserver = class { observe() {} };
global.setTimeout = setTimeout;
global.clearTimeout = clearTimeout;
global.URLSearchParams = URLSearchParams;

// Build a realistic layout: a top nav, then two shelf rails of cards.
function card(name, left, top) {
  const e = new El('a', { left, top, width: 200, height: 340 },
                 { href: '#/item/' + name, name });
  nodes.push(e); return e;
}
const nav = [];
['Home','Browse','Search'].forEach((n, i) => {
  const e = new El('a', { left: 96 + i * 200, top: 54, width: 160, height: 50 }, { href: '#', name: 'nav-' + n });
  nodes.push(e); nav.push(e);
});
// Row A at y=200, Row B at y=600 — 5 cards each, 220px pitch.
const rowA = [], rowB = [];
for (let i = 0; i < 5; i++) rowA.push(card(`A${i}`, 96 + i * 220, 200));
for (let i = 0; i < 5; i++) rowB.push(card(`B${i}`, 96 + i * 220, 600));

// Load the real tv.js
const src = fs.readFileSync('tv.js', 'utf8');
new Function(src)();

function press(keyCode) {
  const ev = { keyCode, preventDefault() {} };
  handlers.forEach(h => h(ev));
}
const K = { LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, BACK_WEBOS: 461, BACK_TIZEN: 10009 };

let pass = 0, fail = 0;
function check(label, got, want) {
  const ok = got === want;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}  (got ${got}, want ${want})`);
  ok ? pass++ : fail++;
}

// §3.1 — something is always focused after boot.
check('boot claims focus', doc.activeElement?.attrs.name, 'nav-Home');

// §3.5 — Right moves within the row.
doc.activeElement = rowA[0];
press(K.RIGHT);
check('right within rail', doc.activeElement.attrs.name, 'A1');

press(K.RIGHT);
check('right again', doc.activeElement.attrs.name, 'A2');

// §3.5 — Left comes back.
press(K.LEFT);
check('left within rail', doc.activeElement.attrs.name, 'A1');

// The critical grid property: Down from A1 must land on B1 (directly below),
// NOT B0 even though B0's centre is geometrically closer to some candidates.
doc.activeElement = rowA[1];
press(K.DOWN);
check('down keeps column', doc.activeElement.attrs.name, 'B1');

// Up returns to the same column.
press(K.UP);
check('up keeps column', doc.activeElement.attrs.name, 'A1');

// Up from the top row reaches the nav (nearest aligned item above).
doc.activeElement = rowA[0];
press(K.UP);
check('up from first row reaches nav', doc.activeElement.attrs.name, 'nav-Home');

// §3.4 — no dead ends: left from the leftmost card stays put, never strands.
doc.activeElement = rowA[0];
press(K.LEFT);
check('left at edge stays put', doc.activeElement.attrs.name, 'A0');

// §1.7 — Back navigates back on both platforms' key codes.
global._wentBack = false;
global.location.hash = '#/browse';
press(K.BACK_WEBOS);
check('webOS back (461) navigates', global._wentBack, true);

global._wentBack = false;
press(K.BACK_TIZEN);
check('Tizen back (10009) navigates', global._wentBack, true);


/* A FOCUSED <select> MUST OWN UP/DOWN. onKeyDown ran spatial navigation on
   every arrow without checking what had focus, so the arrows walked off the
   control and its value could never change — Browse's decade, keyword, studio
   and sort filters were reachable, looked right, and were dead on every TV.
   Left/Right must still navigate, or the viewer is trapped in a control they
   cannot leave, which is the bug a naive exemption introduces instead. */
{
  // Placed IN row A, to the right of the cards: at the left edge there is
  // nothing to navigate to, so a passing LEFT check would prove nothing.
  const sel = new El('select', { left: 96 + 5 * 220, top: 200, width: 180, height: 44 },
                     { name: 'decade-select' });
  nodes.push(sel);
  sel.focus();
  press(K.DOWN);
  check('DOWN on a focused select does not move focus',
        doc.activeElement?.attrs.name, 'decade-select');
  press(K.UP);
  check('UP likewise stays on the control',
        doc.activeElement?.attrs.name, 'decade-select');
  sel.focus();
  press(K.LEFT);
  check('LEFT still navigates away, so nobody is trapped',
        doc.activeElement?.attrs.name !== 'decade-select', true);
  // The exemption must be keyed on the ELEMENT, not on the key: a card must
  // still move on Down, or the whole grid stops working.
  rowA[0].focus();
  press(K.DOWN);
  check('...and a normal card still moves on DOWN',
        doc.activeElement?.attrs.name, 'B0');
  nodes.pop();
}

/* ── The remote can only reach a[href] / button / input / select / [tabindex].
   Anything else with a click handler is MOUSE-ONLY, and on a TV that means
   invisible. The Home hero was exactly that for five weeks: an <article> with
   slide.onclick and a <span> CTA, so the marquee — the first thing on screen —
   could not be reached or opened by a remote, and desktop keyboard users were
   equally stranded. Measured live at archivewatch.org/?tv=1: 0 focusable
   elements inside every one of the six hero slides.

   Assert the SHAPE in the shipped source, since that is what a package
   contains. `slide.onclick` may stay — it serves a mouse — but it must never
   be the only way in. */
{
  const watch = fs.readFileSync('watch.js', 'utf8');
  const heroBlock = watch.slice(watch.indexOf("slide.className = 'hero-slide'"),
                                watch.indexOf("dots.replaceChildren"));
  check('the hero CTA is an anchor, not a span',
        /const cta = document\.createElement\('a'\)/.test(heroBlock), true);
  check('...and it carries an href a remote can activate',
        /cta\.href\s*=/.test(heroBlock), true);
  check('...still classed hero-cta so it keeps its styling',
        /cta\.className\s*=\s*'hero-cta'/.test(heroBlock), true);
}

/* The hero's fluid type is sized in container-query units, which do not exist
   before Chromium 105 — i.e. on every Samsung TV of 2022 and earlier, where an
   unsupported unit drops the WHOLE declaration and the property falls back to
   nothing. Same for dvh (Chromium 108), including `height: 100dvh` on <body>,
   whose loss collapses the entire flex layout.

   The rule: within a rule block, any declaration using a modern unit must be
   PRECEDED by one for the same property that does not. Parse declarations
   rather than lines — the first version of this check read one line back and
   reported four false positives, because the fallbacks it wanted were on
   multi-declaration lines and in three-layer cascades. */
{
  const css = fs.readFileSync('watch.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const MODERN = /\d(?:cq[iwh]|dvh|dvw|svh|lvh)\b/;
  const unfallbacked = [];
  for (const m of css.matchAll(/\{([^{}]*)\}/g)) {
    const seen = new Set();
    for (const decl of m[1].split(';')) {
      const i = decl.indexOf(':');
      if (i < 0) continue;
      const prop = decl.slice(0, i).trim();
      if (!prop) continue;
      if (!MODERN.test(decl)) { seen.add(prop); continue; }
      if (!seen.has(prop)) unfallbacked.push(`${prop}: ${decl.slice(i + 1).trim().slice(0, 34)}`);
    }
  }
  check('every container-query / dvh declaration has an older-unit fallback',
        unfallbacked.length ? unfallbacked.join(' | ') : 0, 0);
}

/* A series' seasons must be reachable by a REMOTE. Alfred Hitchcock Presents
   carries 8 seasons of one episode each, and the web rendered season 1 behind a
   native <select> — a desktop control that on a TV opens a platform picker over
   the page. Both Google TV and Roku rebuilt exactly this into chips. Assert the
   shape in the shipped source: real buttons, focus-selects on a TV, and no
   <select> left in the markup. */
{
  const watch = fs.readFileSync('watch.js', 'utf8');
  const html = fs.readFileSync('index.html', 'utf8');
  check('the season control is not a <select>',
        /<select[^>]*id="series-season"/.test(html), false);
  check('...it is a container the renderer fills with chips',
        /id="series-season"[^>]*class="season-chips"/.test(html), true);
  const block = watch.slice(watch.indexOf("const sel = $('series-season')"),
                            watch.indexOf('episodes(series, season)'));
  check('season chips are real buttons a remote can reach',
        /createElement\('button'\)/.test(block), true);
  check('...and a chip selects when FOCUSED on a TV',
        /addEventListener\('focus'/.test(block) && /classList\.contains\('tv'\)/.test(block), true);
  check('...while a single-season series shows no chip row at all',
        /sel\.hidden = true;/.test(block), true);
}

/* BACK RETURNS TO THE PLACE. Measured on the live site before the fix: browse
   into Home, open a title, press Back, and focus landed on "Home" in the nav
   rail at scroll 0 — on a page carrying 391 focusable tiles. Roku had the same
   complaint (F8).

   The key is the href, because a hash router re-renders the whole view on every
   route change, so an index or an object reference would not survive. Verified
   separately in a real browser that Home's links ARE stable across a Back
   (391/391 identical, same order): shelves randomise per page LOAD, not per
   route change, which is what makes an href key work at all. */
{
  const goRoute = (h) => { global.location.hash = h; hashHandlers.forEach(fn => fn()); };

  goRoute('#/home');
  rowB[3].focus();                       // deep in the second shelf
  check('we are where the viewer was', doc.activeElement?.attrs.name, 'B3');

  goRoute('#/item/B3');                  // open the title
  doc.activeElement = null;              // the view was re-rendered
  goRoute('#/home');                     // press Back
  check('Back restores the tile, not the top of the page',
        doc.activeElement?.attrs.name, 'B3');

  // A route never visited must NOT inherit somebody else's position.
  // A route NEVER visited must not inherit somebody else's position. It has to
  // be a genuinely novel one: '#/browse' failed here at first and the code was
  // right — an earlier block in this file had already focused something while
  // on it, so restoring B0 was the feature working, not a bug.
  doc.activeElement = null;
  goRoute('#/never-been-here');
  check('a fresh route still claims its own first content',
        doc.activeElement?.attrs.name, 'nav-Home');
}

/* A TV APP MAY NOT ADVERTISE OTHER PLATFORMS' STORES. The shared footer says
   "Get the app — Apple TV · Android & Google TV · Fire TV", and About carries
   buttons into the App Store, Play and the Amazon Appstore. Inside the Tizen
   .wgt that is a review-guideline problem AND three dead controls the D-pad
   must walk past, since a packaged TV app has no browser to hand off to.
   Hidden on TV only — on the web they are correct and wanted. */
{
  const css = fs.readFileSync('tv.css', 'utf8');
  const rule = css.slice(css.indexOf('.tv .foot-apps'));
  check('the store-promo footer is hidden on TV',
        /\.tv \.foot-apps/.test(css) && /display:\s*none/.test(rule.slice(0, 200)), true);
  check('...and the About page store buttons too',
        /\.tv \.store-links/.test(css), true);
  // It must NOT take the things a store requires or a viewer needs with it.
  for (const keep of ['about', 'privacy', 'terms', 'donate']) {
    check(`...while leaving ${keep} reachable`,
          !new RegExp(`\\.tv[^{]*\\b${keep}\\b[^{]*\\{[^}]*display:\\s*none`, 'i').test(css), true);
  }
}

/* THE TV TRANSPORT. `<video controls>` draws the BROWSER's bar — pause, 0:00,
   volume, fullscreen, a kebab — at pointer sizes in a strip a D-pad cannot
   enter. The owner saw exactly that on their television. On TV the attribute
   comes off and we draw a readout instead, because the keys are already ours.
   Verified on the glass with tools/tv_glass.mjs at 1920x1080; these lock the
   shape. */
{
  const tv = fs.readFileSync('tv.js', 'utf8');
  const css = fs.readFileSync('tv.css', 'utf8');
  check('the browser control bar is removed on TV',
        /removeAttribute\('controls'\)/.test(tv), true);
  check('...as soon as the dialog OPENS, not on the first keypress',
        /attributeFilter: \['open'\]/.test(tv), true);
  check('a transport readout is drawn instead',
        /class = 'tv-transport'/.test(tv) || /'tv-transport'/.test(tv), true);
  check('...and it is NOT focusable — it must never take a press from the film',
        /setAttribute\('aria-hidden', 'true'\)/.test(tv)
        && /pointer-events:\s*none/.test(css.slice(css.indexOf('.tv-transport'))), true);
  check('the desktop head (rate, PiP, Cast, close) is hidden on TV',
        /\.tv \.player-head\s*\{\s*display:\s*none/.test(css), true);
  check('the film fills the screen and is never cropped',
        /\.tv #video[\s\S]{0,120}object-fit:\s*contain/.test(css), true);
  check('the permanent synopsis over the picture is gone on TV',
        /\.tv \.player-overlay\s*\{\s*display:\s*none/.test(css), true);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);