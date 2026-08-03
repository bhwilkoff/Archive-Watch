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
  focus() { this.focusCount++; doc.activeElement = this; }
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
const doc = {
  activeElement: null,
  hidden: false,
  readyState: 'complete',
  documentElement: { classList: { add: (...c) => { doc._cls = (doc._cls||[]).concat(c); } } },
  body: { },
  querySelectorAll: (sel) => nodes.filter(n => matches(n, sel)),
  querySelector: (sel) => nodes.find(n => matches(n, sel)) || null,
  addEventListener: () => {},
  createElement: () => new El('div', {left:0,top:0,width:0,height:0}),
};

const handlers = [];
global.document = doc;
global.window = {
  addEventListener: (type, fn) => { if (type === 'keydown') handlers.push(fn); },
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
  const e = new El('a', { left, top, width: 200, height: 340 }, { href: '#', name });
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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
