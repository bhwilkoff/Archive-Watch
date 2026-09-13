/* Archive Watch — smart-TV layer (Samsung Tizen · LG webOS · VIDAA · aggregators).
 *
 * Binding rules: docs/TV-DESIGN.md §7. Strategy: Decision 047.
 *
 * This is an ADDITIVE layer over the existing vanilla viewer — same watch.js,
 * same watch.css, same service worker, no build step, no framework. It is NOT a
 * fork of the web app (§7.1), and it is deliberately dependency-free: every
 * mature spatial-navigation library (Norigin and friends) is React-based, which
 * this codebase is not.
 *
 * It works by observing the DOM the viewer already produces — cards are real
 * <a> elements, so they are focusable without touching a line of view code.
 * The per-platform differences are ONLY key codes, lifecycle events and
 * packaging (§7.3); no logic below branches on platform beyond that table.
 */
(function () {
  'use strict';

  /* ------------------------------------------------------------------ *
   * Platform detection + the per-platform shim table (§7.3)
   * ------------------------------------------------------------------ */

  const UA = navigator.userAgent || '';
  const PLATFORM =
    /Tizen/i.test(UA) ? 'tizen' :
    /Web0S|webOS/i.test(UA) ? 'webos' :
    /VIDAA/i.test(UA) ? 'vidaa' :
    // ?tv=1 lets the TV surface be developed and screenshotted in a desktop
    // browser. Without it a TV build could only ever be tested on a TV.
    (new URLSearchParams(location.search).get('tv') === '1' ? 'debug' : null);

  if (!PLATFORM) return;   // ordinary phone/desktop web — do nothing at all.

  // Back is the one key every platform spells differently, and getting it wrong
  // is a certification failure on all of them (§1.7).
  const BACK_KEYS = new Set([
    461,    // webOS
    10009,  // Tizen
    27,     // Escape — desktop debug + some aggregator remotes
    8,      // Backspace — VIDAA and several white-label remotes
  ]);

  const KEY = {
    LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40,
    ENTER: 13,
    PLAY: 415, PAUSE: 19, PLAY_PAUSE: 10252, STOP: 413,
    FF: 417, REWIND: 412,
  };

  const SEEK_STEP = 10;   // seconds per FF/REW press — the TV convention.

  /* ------------------------------------------------------------------ *
   * Focus engine (§3, §7.2)
   * ------------------------------------------------------------------ */

  /* `tabindex="-1"` is excluded on EVERY row, not just the last one. An author
   * writing it is saying "not reachable by keyboard", and an `a[href]` or a
   * `<button>` carrying it was still a spatial candidate — which is what let
   * the hero's off-screen slides be landed on (see heroSync below). */
  const FOCUSABLE = [
    'a[href]:not([tabindex="-1"])',
    'button:not([disabled]):not([tabindex="-1"])',
    'input:not([disabled]):not([tabindex="-1"])',
    'select:not([disabled]):not(.tv-hidden-select):not([tabindex="-1"])',
    '[tabindex]:not([tabindex="-1"])',
  ].join(',');

  /** Visible, laid-out, and inside a view that is not `hidden`. A hidden view's
   *  cards stay in the DOM, so without this the D-pad would walk into the
   *  previous screen. */
  function isReachable(el) {
    if (el.closest('[hidden]')) return false;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return false;
    const style = getComputedStyle(el);
    return style.visibility !== 'hidden' && style.display !== 'none';
  }

  /* ── Native <select> is unusable with a remote ─────────────────────────────
   *
   * The owner, on a QN65S90CDFXZA: "navigation is still extremely broken …
   * the browse pages have filters that are much too small to work on a tv."
   * Both complaints are one control. Measured with tools/tv_glass.mjs at a
   * true 1920x1080: TWENTY presses of Down on #/browse and focus never left
   * the sort control at y=329. A <select> consumes Up and Down to change its
   * OPTION, so the D-pad can never step off it — the grid below is
   * unreachable, forever, by any sequence of presses.
   *
   * It is also a browser widget at browser size, and opening one hands the
   * viewer the platform's own dropdown, which on a television is a mouse
   * control drawn at ten inches for someone sitting at ten feet.
   *
   * So on TV a <select> becomes a BUTTON showing the current value, and
   * pressing it opens a list sized for the room. This is the shape the Roku
   * app already settled on ("chips open a picker on the current value") and
   * the reason is the same: the viewer is choosing among a handful of values
   * with four arrows and an OK.
   *
   * The <select> itself stays in the DOM, hidden, and remains the source of
   * truth — every existing change handler in watch.js keeps working, because
   * the picker sets .value and dispatches 'change' exactly as a click would.
   */

  /* ---------------------------------------------------------------- *
   * A QR encoder, because a TV has no other way to hand over a link   *
   * ---------------------------------------------------------------- *
   *
   * The owner: share playlists "from all native apps and have them publish to
   * a archivewatch.org link that can be shared (QR codes for TV-based native
   * apps)". On a phone that link goes to navigator.share; on a TV there is no
   * share sheet, and `navigator.clipboard` is worse than useless — the viewer
   * has nothing to paste into and no way to get the link off the set. So the
   * TV draws the link as a code the viewer points a phone at.
   *
   * Ported from roku/components/QR.brs (byte mode, EC level L) and extended
   * from versions 1-10 to 1-40, because 10 was nowhere near enough: measured
   * against REAL catalogue ids, only a 1-3 film playlist fits v10, and a
   * 50-film share URL is ~1,048-1,328 characters (v23-v27). The version and
   * alignment tables are MACHINE-GENERATED from an independent reference and
   * then verified cell-for-cell at every version — hand-transcribing them is
   * how the v10 alignment typo (52 where the spec says 50) got into the Roku
   * encoder and stayed there, malforming every version-10 code it ever drew.
   *
   * Proven two ways in tools/test_tv_qr.mjs: for every string exactly ONE of
   * the eight masks reproduces the reference bit-for-bit (which proves the
   * bitstream, ECC, interleave, function patterns, placement and format info
   * whatever mask the penalty happens to choose), and the mask it DOES choose
   * decodes back to the original string.
   */
  /* QR encoder, byte mode, EC level L, versions 1-10. Ported from
   * roku/components/QR.brs, which was proven cell-for-cell against a python
   * reference and decoded by OpenCV from a device screenshot. */
  function qrMatrix(text, forceMask) {
    const enc = new TextEncoder();
    const ba = enc.encode(text);
    const n = ba.length;
    /* Machine-generated from an independent reference implementation and then
     * VERIFIED cell-for-cell across all 40 versions (tools/test_tv_qr.mjs).
     * Transcribing these by hand is how the v10 alignment typo got in. */
    const TBL = [
      [19, 7, 1, 19, 0, 0],  // v1
      [34, 10, 1, 34, 0, 0],  // v2
      [55, 15, 1, 55, 0, 0],  // v3
      [80, 20, 1, 80, 0, 0],  // v4
      [108, 26, 1, 108, 0, 0],  // v5
      [136, 18, 2, 68, 0, 0],  // v6
      [156, 20, 2, 78, 0, 0],  // v7
      [194, 24, 2, 97, 0, 0],  // v8
      [232, 30, 2, 116, 0, 0],  // v9
      [274, 18, 2, 68, 2, 69],  // v10
      [324, 20, 4, 81, 0, 0],  // v11
      [370, 24, 2, 92, 2, 93],  // v12
      [428, 26, 4, 107, 0, 0],  // v13
      [461, 30, 3, 115, 1, 116],  // v14
      [523, 22, 5, 87, 1, 88],  // v15
      [589, 24, 5, 98, 1, 99],  // v16
      [647, 28, 1, 107, 5, 108],  // v17
      [721, 30, 5, 120, 1, 121],  // v18
      [795, 28, 3, 113, 4, 114],  // v19
      [861, 28, 3, 107, 5, 108],  // v20
      [932, 28, 4, 116, 4, 117],  // v21
      [1006, 28, 2, 111, 7, 112],  // v22
      [1094, 30, 4, 121, 5, 122],  // v23
      [1174, 30, 6, 117, 4, 118],  // v24
      [1276, 26, 8, 106, 4, 107],  // v25
      [1370, 28, 10, 114, 2, 115],  // v26
      [1468, 30, 8, 122, 4, 123],  // v27
      [1531, 30, 3, 117, 10, 118],  // v28
      [1631, 30, 7, 116, 7, 117],  // v29
      [1735, 30, 5, 115, 10, 116],  // v30
      [1843, 30, 13, 115, 3, 116],  // v31
      [1955, 30, 17, 115, 0, 0],  // v32
      [2071, 30, 17, 115, 1, 116],  // v33
      [2191, 30, 13, 115, 6, 116],  // v34
      [2306, 30, 12, 121, 7, 122],  // v35
      [2434, 30, 6, 121, 14, 122],  // v36
      [2566, 30, 17, 122, 4, 123],  // v37
      [2702, 30, 4, 122, 18, 123],  // v38
      [2812, 30, 20, 117, 4, 118],  // v39
      [2956, 30, 19, 118, 6, 119],  // v40
    ];
    const AP = [
      [],  // v1
      [6, 18],  // v2
      [6, 22],  // v3
      [6, 26],  // v4
      [6, 30],  // v5
      [6, 34],  // v6
      [6, 22, 38],  // v7
      [6, 24, 42],  // v8
      [6, 26, 46],  // v9
      [6, 28, 50],  // v10
      [6, 30, 54],  // v11
      [6, 32, 58],  // v12
      [6, 34, 62],  // v13
      [6, 26, 46, 66],  // v14
      [6, 26, 48, 70],  // v15
      [6, 26, 50, 74],  // v16
      [6, 30, 54, 78],  // v17
      [6, 30, 56, 82],  // v18
      [6, 30, 58, 86],  // v19
      [6, 34, 62, 90],  // v20
      [6, 28, 50, 72, 94],  // v21
      [6, 26, 50, 74, 98],  // v22
      [6, 30, 54, 78, 102],  // v23
      [6, 28, 54, 80, 106],  // v24
      [6, 32, 58, 84, 110],  // v25
      [6, 30, 58, 86, 114],  // v26
      [6, 34, 62, 90, 118],  // v27
      [6, 26, 50, 74, 98, 122],  // v28
      [6, 30, 54, 78, 102, 126],  // v29
      [6, 26, 52, 78, 104, 130],  // v30
      [6, 30, 56, 82, 108, 134],  // v31
      [6, 34, 60, 86, 112, 138],  // v32
      [6, 30, 58, 86, 114, 142],  // v33
      [6, 34, 62, 90, 118, 146],  // v34
      [6, 30, 54, 78, 102, 126, 150],  // v35
      [6, 24, 50, 76, 102, 128, 154],  // v36
      [6, 28, 54, 80, 106, 132, 158],  // v37
      [6, 32, 58, 84, 110, 136, 162],  // v38
      [6, 26, 54, 82, 110, 138, 166],  // v39
      [6, 30, 58, 86, 114, 142, 170],  // v40
    ];
    let v = 0;
    for (let i = 0; i < TBL.length; i++) {
      const cc = (i + 1) >= 10 ? 16 : 8;
      if (4 + cc + 8 * n <= TBL[i][0] * 8) { v = i + 1; break; }
    }
    if (!v) return null;
    const spec = TBL[v - 1];
    const size = 17 + 4 * v;

    // GF(256), QR primitive 0x11D
    const exp_ = new Array(512), log_ = new Array(256);
    { let x = 1;
      for (let i = 0; i < 255; i++) { exp_[i] = x; log_[x] = i; x <<= 1; if (x >= 256) x ^= 285; }
      for (let i = 255; i < 512; i++) exp_[i] = exp_[i - 255];
      log_[0] = 0; }
    const mul = (a, b) => (a === 0 || b === 0) ? 0 : exp_[log_[a] + log_[b]];
    function generator(k) {
      let gen = [1];
      for (let i = 0; i < k; i++) {
        const nxt = new Array(gen.length + 1).fill(0);
        for (let j = 0; j < gen.length; j++) {
          nxt[j] ^= gen[j];
          nxt[j + 1] ^= mul(gen[j], exp_[i]);
        }
        gen = nxt;
      }
      return gen;
    }
    function ecc(data, k) {
      const gen = generator(k), res = new Array(k).fill(0);
      for (const d of data) {
        const f = d ^ res[0];
        for (let i = 0; i < k - 1; i++) res[i] = res[i + 1];
        res[k - 1] = 0;
        if (f !== 0) for (let i = 0; i < k; i++) res[i] ^= mul(gen[i + 1], f);
      }
      return res;
    }

    // ---- bit stream ----
    const bits = [];
    const push = (val, nb) => { for (let i = nb - 1; i >= 0; i--) bits.push((val >> i) & 1); };
    const ccBits = v >= 10 ? 16 : 8;
    push(4, 4); push(n, ccBits);
    for (let i = 0; i < n; i++) push(ba[i], 8);
    const cap = spec[0] * 8;
    push(0, Math.min(4, cap - bits.length));
    while (bits.length % 8 !== 0) bits.push(0);
    let pad = 236;
    while (bits.length < cap) { push(pad, 8); pad = pad === 236 ? 17 : 236; }
    const cw = [];
    for (let i = 0; i < bits.length; i += 8) {
      let b = 0; for (let k = 0; k < 8; k++) b = b * 2 + bits[i + k];
      cw.push(b);
    }

    // ---- blocks + interleave ----
    const blocks = []; let p = 0;
    for (let b = 0; b < spec[2]; b++) blocks.push(cw.slice(p, p += spec[3]));
    for (let b = 0; b < spec[4]; b++) blocks.push(cw.slice(p, p += spec[5]));
    const eccs = blocks.map((b) => ecc(b, spec[1]));
    const out = [];
    const maxLen = Math.max(spec[3], spec[5]);
    for (let k = 0; k < maxLen; k++)
      for (const blk of blocks) if (k < blk.length) out.push(blk[k]);
    for (let k = 0; k < spec[1]; k++) for (const e of eccs) out.push(e[k]);
    const stream = [];
    for (const c of out) for (let i = 7; i >= 0; i--) stream.push((c >> i) & 1);

    // ---- matrix + function patterns ----
    const mods = [], fn = [];
    for (let y = 0; y < size; y++) { mods.push(new Array(size).fill(0)); fn.push(new Array(size).fill(0)); }
    function finder(ox, oy) {
      for (let dy = -1; dy <= 7; dy++) for (let dx = -1; dx <= 7; dx++) {
        const x = ox + dx, y = oy + dy;
        if (x < 0 || y < 0 || x >= size || y >= size) continue;
        let val = 0;
        if (dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6) {
          if (dx === 0 || dx === 6 || dy === 0 || dy === 6) val = 1;
          if (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4) val = 1;
        }
        mods[y][x] = val; fn[y][x] = 1;
      }
    }
    finder(0, 0); finder(size - 7, 0); finder(0, size - 7);
    for (let i = 8; i <= size - 9; i++) {
      const v2 = 1 - (i % 2);
      mods[6][i] = v2; fn[6][i] = 1;
      mods[i][6] = v2; fn[i][6] = 1;
    }
    const ap = AP[v - 1];
    for (const ay of ap) for (const ax of ap) {
      if ((ax <= 8 && ay <= 8) || (ax <= 8 && ay >= size - 9) || (ax >= size - 9 && ay <= 8)) continue;
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
        const d = Math.max(Math.abs(dx), Math.abs(dy));
        mods[ay + dy][ax + dx] = d === 1 ? 0 : 1;
        fn[ay + dy][ax + dx] = 1;
      }
    }
    for (let i = 0; i <= 8; i++) { fn[8][i] = 1; fn[i][8] = 1; }
    for (let i = 0; i <= 7; i++) { fn[8][size - 1 - i] = 1; fn[size - 1 - i][8] = 1; }
    mods[size - 8][8] = 1; fn[size - 8][8] = 1;
    if (v >= 7) {
      // BCH(18,6), generator 0x1F25. Computed, not transcribed — the same
      // reason the tables above are generated.
      let rem = v << 12;
      for (let i = 17; i >= 12; i--) if ((rem >> i) & 1) rem ^= 0x1F25 << (i - 12);
      const vb = (v << 12) | (rem & 0xFFF);
      for (let i = 0; i < 18; i++) {
        const bit = (vb >> i) & 1;
        const a = Math.floor(i / 3), b = i % 3;
        mods[a][size - 11 + b] = bit; fn[a][size - 11 + b] = 1;
        mods[size - 11 + b][a] = bit; fn[size - 11 + b][a] = 1;
      }
    }

    // ---- place data ----
    let idx = 0, x = size - 1, up = true;
    while (x > 0) {
      if (x === 6) x -= 1;
      for (let k = 0; k < size; k++) {
        const y = up ? size - 1 - k : k;
        for (let c = 0; c <= 1; c++) {
          const xx = x - c;
          if (fn[y][xx] === 0) { mods[y][xx] = idx < stream.length ? stream[idx] : 0; idx++; }
        }
      }
      up = !up; x -= 2;
    }

    // ---- mask selection ----
    const maskBit = (m, y, xx) => {
      switch (m) {
        case 0: return (y + xx) % 2 === 0;
        case 1: return y % 2 === 0;
        case 2: return xx % 3 === 0;
        case 3: return (y + xx) % 3 === 0;
        case 4: return (Math.floor(y / 2) + Math.floor(xx / 3)) % 2 === 0;
        case 5: return ((y * xx) % 2 + (y * xx) % 3) === 0;
        case 6: return (((y * xx) % 2 + (y * xx) % 3) % 2) === 0;
        default: return ((((y + xx) % 2) + ((y * xx) % 3)) % 2) === 0;
      }
    };
    function writeFormat(m, mask) {
      const data = 8 + mask;            // L = 01 -> 01<<3 | mask
      let remv = data << 10;
      for (let i = 14; i >= 10; i--) if ((remv >> i) & 1) remv ^= 1335 << (i - 10);
      const fmt = ((data << 10) + remv) ^ 21522;
      for (let i = 0; i < 15; i++) {
        const bit = (fmt >> i) & 1;
        if (i < 6) m[i][8] = bit;
        else if (i < 8) m[i + 1][8] = bit;
        else m[size - 15 + i][8] = bit;
        if (i < 8) m[8][size - 1 - i] = bit;
        else if (i < 9) m[8][7] = bit;
        else m[8][14 - i] = bit;
      }
    }
    function penalty(m) {
      let score = 0;
      for (let y = 0; y < size; y++) {
        let runC = 1, runV = m[y][0], cC = 1, cV = m[0][y];
        for (let xx = 1; xx < size; xx++) {
          if (m[y][xx] === runV) { runC++; if (runC === 5) score += 3; else if (runC > 5) score += 1; }
          else { runV = m[y][xx]; runC = 1; }
          if (m[xx][y] === cV) { cC++; if (cC === 5) score += 3; else if (cC > 5) score += 1; }
          else { cV = m[xx][y]; cC = 1; }
        }
      }
      for (let y = 0; y < size - 1; y++) for (let xx = 0; xx < size - 1; xx++) {
        const a = m[y][xx];
        if (a === m[y][xx + 1] && a === m[y + 1][xx] && a === m[y + 1][xx + 1]) score += 3;
      }
      let dark = 0;
      for (let y = 0; y < size; y++) for (let xx = 0; xx < size; xx++) dark += m[y][xx];
      const pct = Math.floor(dark * 100 / (size * size));
      score += Math.floor(Math.abs(pct - 50) / 5) * 10;
      return score;
    }
    let best = null, bestScore = Infinity, bestMask = -1;
    for (let mask = 0; mask < 8; mask++) {
      const cand = mods.map((row, y) => row.map((val, xx) =>
        (fn[y][xx] === 0 && maskBit(mask, y, xx)) ? 1 - val : val));
      writeFormat(cand, mask);
      const sc = penalty(cand);
      if (forceMask === mask) { return { size, modules: cand, version: v, mask }; }
      if (sc < bestScore) { bestScore = sc; best = cand; bestMask = mask; }
    }
    return { size, modules: best, version: v, mask: bestMask };
  }

  const PICKER_CLASS = 'tv-picker';

  function labelFor(sel) {
    const o = sel.options[sel.selectedIndex];
    return (o && o.textContent.trim()) || sel.getAttribute('aria-label') || 'Choose';
  }

  function closePicker() {
    const open = document.querySelector('.tv-picker-sheet');
    if (open) {
      const owner = open._ownerBtn;
      open.remove();
      if (owner) focusEl(owner);
    }
  }

  function openPicker(btn, sel) {
    closePicker();
    const sheet = document.createElement('div');
    sheet.className = 'tv-picker-sheet';
    sheet._ownerBtn = btn;
    const head = document.createElement('p');
    head.className = 'tv-picker-head';
    head.textContent = sel.getAttribute('aria-label') || 'Choose';
    sheet.appendChild(head);
    Array.prototype.forEach.call(sel.options, function (opt, i) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'tv-picker-opt';
      b.textContent = opt.textContent;
      if (i === sel.selectedIndex) b.setAttribute('aria-current', 'true');
      b.onclick = function () {
        sel.selectedIndex = i;
        // The <select> stays the source of truth: watch.js listens to it.
        sel.dispatchEvent(new Event('change', { bubbles: true }));
        btn.textContent = labelFor(sel);
        closePicker();
      };
      sheet.appendChild(b);
    });
    document.body.appendChild(sheet);
    const first = sheet.querySelector('[aria-current], .tv-picker-opt');
    if (first) focusEl(first);
  }

  /** Convert every <select> on screen. Idempotent: re-run on each route. */
  function tvPickers() {
    Array.prototype.forEach.call(document.querySelectorAll('select'), function (sel) {
      if (sel.dataset.tvPicker) return;
      sel.dataset.tvPicker = '1';
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = PICKER_CLASS;
      btn.textContent = labelFor(sel);
      btn.setAttribute('aria-label', sel.getAttribute('aria-label') || 'Choose');
      btn.onclick = function () { openPicker(btn, sel); };
      sel.parentNode.insertBefore(btn, sel);
      sel.classList.add('tv-hidden-select');
      // The options are filled asynchronously (decades, keywords, studios come
      // from the catalogue), so the button must follow the <select> rather
      // than snapshot it once and go stale.
      new MutationObserver(function () { btn.textContent = labelFor(sel); })
        .observe(sel, { childList: true, attributes: true, attributeFilter: ['value'] });
      sel.addEventListener('change', function () { btn.textContent = labelFor(sel); });
    });
  }


  /* ---------------------------------------------------------------- *
   * Asking before something irreversible                              *
   * ---------------------------------------------------------------- *
   *
   * `confirm()` works on a television — Samsung's and LG's engines both
   * draw it and a remote can reach its buttons — so this is not about it
   * being broken. It is about it being a WEB dialog: system-styled, tiny,
   * and nothing like the surface around it, on an app whose whole
   * instruction was that nothing should look like a web page.
   *
   * It also blocks. A native modal stops the page's own key handling, so
   * the focus engine below cannot help the viewer while one is open —
   * the remote is talking to the platform, not to us.
   *
   * Same shape as the picker and the share sheet: a sheet, Back closes
   * it, and the SAFE choice takes focus. */
  function tvConfirm(message, confirmLabel, onConfirm) {
    closeConfirm();
    const sheet = document.createElement('div');
    sheet.className = 'tv-confirm-sheet';
    sheet._ownerBtn = document.activeElement;

    const p = document.createElement('p');
    p.className = 'tv-confirm-msg';
    p.textContent = message;
    sheet.appendChild(p);

    const row = document.createElement('div');
    row.className = 'tv-confirm-row';

    // CANCEL FIRST, and it takes focus. A viewer who lands here by pressing
    // Right one time too many must not be able to delete their playlist with
    // a second press in the same direction.
    const no = document.createElement('button');
    no.type = 'button';
    no.className = 'tv-confirm-no';
    no.textContent = 'Keep it';
    no.onclick = closeConfirm;

    const yes = document.createElement('button');
    yes.type = 'button';
    yes.className = 'tv-confirm-yes';
    yes.textContent = confirmLabel;
    yes.onclick = function () { closeConfirm(); onConfirm(); };

    row.append(no, yes);
    sheet.appendChild(row);
    document.body.appendChild(sheet);
    focusEl(no);
  }

  function closeConfirm() {
    const open = document.querySelector('.tv-confirm-sheet');
    if (open) {
      const owner = open._ownerBtn;
      open.remove();
      if (owner && document.contains(owner)) focusEl(owner);
      else claimFocus();
    }
  }

  /* ---------------------------------------------------------------- *
   * The share sheet — a code, the link, and one way out               *
   * ---------------------------------------------------------------- */

  /* A URL a viewer could reasonably key in with a remote. Above this the
   * sheet stops printing it (see shareQR). */
  const TYPEABLE_URL = 120;

  function closeShare() {
    const open = document.querySelector('.tv-qr-sheet');
    if (open) {
      const owner = open._ownerBtn;
      open.remove();
      if (owner && document.contains(owner)) focusEl(owner);
      else claimFocus();
    }
  }

  /** Draw the matrix into a canvas at a whole number of pixels per module.
   *  A fractional module size is what makes a code unreadable on a TV: the
   *  browser resamples it and the scanner sees blurred edges. So the canvas
   *  is sized to the code rather than the code stretched to the canvas. */
  function qrCanvas(url, box) {
    const m = qrMatrix(url);
    if (!m) return null;                       // past v40 — nothing can encode it
    const QUIET = 4;                           // the spec's quiet zone, in modules
    const total = m.size + QUIET * 2;
    const scale = Math.max(2, Math.floor(box / total));
    const cv = document.createElement('canvas');
    cv.width = cv.height = total * scale;
    cv.style.width = cv.style.height = (total * scale) + 'px';
    const ctx = cv.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, cv.width, cv.height);
    ctx.fillStyle = '#000';
    for (let y = 0; y < m.size; y++) {
      for (let x = 0; x < m.size; x++) {
        if (m.modules[y][x]) {
          ctx.fillRect((x + QUIET) * scale, (y + QUIET) * scale, scale, scale);
        }
      }
    }
    cv.setAttribute('role', 'img');
    cv.setAttribute('aria-label', 'QR code for ' + url);
    return cv;
  }

  /** The one seam watch.js uses. It checks `html.tv` live (the idiom already
   *  used for the shelf floor and the season chips) and calls this instead of
   *  navigator.share, which does not exist on a television. */
  function shareQR(url, title) {
    closeShare();
    const sheet = document.createElement('div');
    sheet.className = 'tv-qr-sheet';
    sheet._ownerBtn = document.activeElement;

    const head = document.createElement('p');
    head.className = 'tv-qr-head';
    head.textContent = title || 'Share this playlist';
    sheet.appendChild(head);

    // The code is sized to the room that is actually left, not to a constant:
    // the panel is capped at 86vh and everything else on it (title, two lines
    // of copy, the button, the padding) measures ~360px, so a fixed 640 box
    // overflowed on a 1080 line and the flex column clipped the copy. Floor of
    // 360 so a very short panel still yields a scannable code.
    const budget = Math.max(360,
      Math.min(640, Math.floor((window.innerHeight || 1080) * 0.86) - 360));
    const cv = qrCanvas(url, budget);
    if (cv) {
      sheet.appendChild(cv);
    } else {
      // Never a blank box where a code belongs: say what happened (§ the
      // universal-states rule) rather than showing an empty frame.
      const err = document.createElement('p');
      err.className = 'tv-qr-note';
      err.textContent = 'This playlist is too long to put in a code. '
        + 'Open the link below on a phone instead.';
      sheet.appendChild(err);
    }

    const hint = document.createElement('p');
    hint.className = 'tv-qr-note';
    hint.textContent = cv
      ? 'Point your phone camera at the code to open this playlist.'
      : '';
    if (hint.textContent) sheet.appendChild(hint);

    // The link in words, for the viewer with no camera to hand — but ONLY when
    // typing it is a real option. Measured against real catalogue ids a share
    // link runs from ~116 characters for one film to ~1,328 for fifty, and
    // printing the long ones in full is what this sheet did first: seven lines
    // of base64 that overflowed the panel and pushed the only button off the
    // bottom of the screen. Nobody types a thousand-character URL, so past the
    // threshold the sheet says where the link goes and lets the code carry it.
    const link = document.createElement('p');
    link.className = 'tv-qr-url';
    link.textContent = url.length <= TYPEABLE_URL
      ? url
      : 'This link is too long to type — the code carries it.';
    sheet.appendChild(link);

    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'tv-qr-close';
    close.textContent = 'Done';
    close.onclick = closeShare;
    sheet.appendChild(close);

    document.body.appendChild(sheet);
    focusEl(close);
  }

  function candidates() {
    return Array.prototype.filter.call(
      document.querySelectorAll(FOCUSABLE), isReachable);
  }

  function centreOf(r) {
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }

  /**
   * Pick the best element in `dir` from `fromRect`.
   *
   * Scoring = distance along the axis of travel + a weighted penalty for
   * misalignment across it. The weight is what makes a grid feel like a grid:
   * pressing Down from a card should land on the card *below* it, not on a
   * nearer one three columns over (§3.5 — directional intent is preserved).
   */
  function bestInDirection(fromRect, dir, pool) {
    const from = centreOf(fromRect);
    const MISALIGN_WEIGHT = 3;
    let best = null;
    let bestScore = Infinity;

    for (const el of pool) {
      const r = el.getBoundingClientRect();
      const to = centreOf(r);

      // Must lie genuinely in the direction of travel. Compare EDGES, not
      // centres: a tall neighbour whose centre is behind us can still be the
      // correct target.
      let along, across;
      if (dir === 'right') {
        if (r.left < fromRect.right - 1) continue;
        along = r.left - fromRect.right; across = Math.abs(to.y - from.y);
      } else if (dir === 'left') {
        if (r.right > fromRect.left + 1) continue;
        along = fromRect.left - r.right; across = Math.abs(to.y - from.y);
      } else if (dir === 'down') {
        if (r.top < fromRect.bottom - 1) continue;
        along = r.top - fromRect.bottom; across = Math.abs(to.x - from.x);
      } else {
        if (r.bottom > fromRect.top + 1) continue;
        along = fromRect.top - r.bottom; across = Math.abs(to.x - from.x);
      }

      const score = Math.max(along, 0) + across * MISALIGN_WEIGHT;
      if (score < bestScore) { bestScore = score; best = el; }
    }
    return best;
  }

  /** §3.3 — a focused element must never sit under the overscan margin or
   *  off-screen; the D-pad has no other way to reveal it. */
  /* THE SCREEN FOLLOWS THE SELECTION. `block: 'nearest'` is a desktop
   * behaviour: it scrolls the least it can, which leaves the highlighted tile
   * flush against the top or bottom edge with no sense of what comes next, and
   * on a television reads as the page refusing to move. The owner, on a 65"
   * Samsung: "there is A LOT of work to do to ensure the screen follows the
   * selection rectangle".
   *
   * Centring is the ten-foot convention and it fixes a second fault for free.
   * Browse loads more titles when a sentinel at the foot of the grid comes into
   * view; a minimal scroll never brought it there, so Down died four rows in —
   * measured, focus frozen on the same tile for five consecutive presses.
   * Centring scrolls far enough that the grid keeps filling.
   *
   * `behavior: 'auto'` on purpose: a smooth scroll animates, and on a TV CPU
   * the highlight visibly lags the press. Instant is what a remote expects. */
  function reveal(el) {
    el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'auto' });
  }

  function focusEl(el) {
    if (!el) return false;
    el.focus({ preventScroll: true });
    reveal(el);
    return true;
  }

  function move(dir) {
    const pool = candidates();
    if (!pool.length) return false;

    const active = document.activeElement;
    if (!active || active === document.body || !isReachable(active)) {
      return focusEl(pool[0]);
    }
    // STAY INSIDE THE SCROLLING AREA FIRST. `body` is a flex column with
    // `overflow:hidden`, so <main> scrolls and the footer is a SIBLING pinned
    // below it, permanently on screen. Purely geometric, the footer is
    // therefore the nearest thing below EVERY row on the page — so Down from
    // the category tiles jumped straight to "About & attribution" and the page
    // never scrolled. That is the owner's report, "the screen doesn't follow
    // the rectangle", and it is not a Home bug: it is what a pinned element
    // does to a spatial engine on any surface.
    //
    // A move therefore prefers a target in the same scroll container, and only
    // leaves it when that direction is genuinely exhausted — which is when a
    // viewer means to leave. Measured with tools/tv_glass.mjs at 1920x1080.
    const box = active.getBoundingClientRect();
    const home = scrollParent(active);
    if (home) {
      const inside = pool.filter(function (el) { return scrollParent(el) === home; });
      const near = inside.length && bestInDirection(box, dir, inside);
      if (near) return focusEl(near);
    }
    const next = bestInDirection(box, dir, pool);
    // §3.4 — no dead ends. If nothing lies that way we simply stay put, which
    // is a deliberate stop, not a strand: Back always still works.
    return next ? focusEl(next) : false;
  }

  /** The nearest ancestor that actually scrolls, or null. */
  function scrollParent(el) {
    for (var n = el.parentElement; n && n !== document.body; n = n.parentElement) {
      var oy = getComputedStyle(n).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && n.scrollHeight > n.clientHeight) {
        return n;
      }
    }
    return null;
  }

  /**
   * Chrome that is NOT a destination. Landing initial focus here is technically
   * "something is focused" while being useless to a viewer — the brand logo and
   * the footer links are not what anyone came for.
   */
  const CHROME_SEL = '.brand, .sitefoot a, footer a, .install-prompt *';

  function isChrome(el) {
    return typeof el.closest === 'function' && el.closest(CHROME_SEL) != null;
  }

  /**
   * §3.1 — something is ALWAYS focused. Called on every view change, and
   * retried because views render asynchronously after the hash changes.
   *
   * Prefers real CONTENT over page chrome: focus landing on the logo was the
   * first thing a real browser showed (the shim has no notion of "useful"),
   * and it reads as broken because the first Right/Down goes somewhere
   * unrelated to what the viewer is looking at.
   */
  let claimTimer = null;
  /* §1.7 — BACK RETURNS TO THE PLACE, not the top of the page.
   *
   * Without this, coming back from a film focused the first non-chrome
   * candidate, which on Home is the nav rail: browse deep into a shelf, open a
   * title, press Back, and you were at scroll 0 with focus on "Home" — on a
   * page with several hundred tiles. Roku fixed the same complaint (F8).
   *
   * The remembered key is the element's href where it has one, because that
   * survives the view being re-rendered from scratch on every route change,
   * which is what a hash router does. Text is the fallback for buttons. An
   * index would not survive a shelf whose contents rotate per visit. */
  const lastFocus = Object.create(null);

  function routeKey() {
    return (location.hash || '#/').split('?')[0];
  }

  function elKey(el) {
    return el.getAttribute('href')
        || el.tagName + ':' + (el.textContent || '').trim().slice(0, 40);
  }

  document.addEventListener('focusin', function (ev) {
    const el = ev.target;
    if (el && el !== document.body && typeof el.getAttribute === 'function'
        && isReachable(el) && !isChrome(el)) {
      lastFocus[routeKey()] = elKey(el);
    }
  }, true);

  /* ARRIVING AT A SURFACE is not the same as having nothing focused, and
   * claimFocus cannot handle it: its first act is to keep whatever is already
   * focused, which on a route change is the nav item the viewer just pressed —
   * and Detail's content does not exist yet anyway, because the shard is still
   * being fetched. So opening a film left the remote on "Home" with Play four
   * presses away.
   *
   * Arrival therefore waits for the surface to render and then takes the
   * primary action. It gives up after six seconds, and ANY key press cancels
   * it — if the viewer has started navigating, focus is theirs and must not be
   * yanked out from under them. A route we are RETURNING to is left alone
   * entirely: the remembered tile wins over the primary action, because Back
   * means "where I was", not "start again". */
  var arriving = false, arriveTimer = null;

  function beginArrival() {
    if (lastFocus[routeKey()]) return;      // returning: Back owns the choice
    arriving = true;
    clearTimeout(arriveTimer);
    arriveTimer = setTimeout(function () { arriving = false; }, 6000);
    pursueArrival();
  }

  function cancelArrival() { arriving = false; clearTimeout(arriveTimer); }

  function pursueArrival() {
    if (!arriving) return;
    var primary = candidates().find(function (el) {
      return el.classList && el.classList.contains('btn-primary');
    });
    if (primary) { cancelArrival(); focusEl(primary); return; }
    setTimeout(pursueArrival, 200);
  }

  function claimFocus() {
    clearTimeout(claimTimer);
    let tries = 0;
    (function attempt() {
      const active = document.activeElement;
      if (active && active !== document.body && isReachable(active)) return;
      const pool = candidates();
      if (pool.length) {
        const want = lastFocus[routeKey()];
        if (want) {
          const back = pool.find(function (el) { return elKey(el) === want; });
          if (back) { focusEl(back); return; }
        }
        // ARRIVE ON THE PRIMARY ACTION. Opening a film landed focus on "Home"
        // in the nav rail, because the first non-chrome candidate in DOM order
        // is up there — so the remote arrived somewhere unrelated to what the
        // viewer just chose, and Play was four presses away. Every ten-foot
        // app puts you on the thing you came to do. `.btn-primary` already
        // marks exactly one per surface: Play on a title, Re-roll on Surprise,
        // Marathon on Cartoons.
        const primary = pool.find(function (el) {
          return el.classList && el.classList.contains('btn-primary');
        });
        if (primary) { focusEl(primary); return; }
        focusEl(pool.find(function (el) { return !isChrome(el); }) || pool[0]);
        return;
      }
      if (++tries < 20) claimTimer = setTimeout(attempt, 100);
    })();
  }

  /* ------------------------------------------------------------------ *
   * ON-SCREEN PLAYBACK DIAGNOSTICS (§5.4)
   *
   * "Videos do not play except for a few seconds" — reported on a retail
   * Samsung, where there is NO way to see why. `sdb shell` is closed on retail
   * hardware: no console, no dlog, no screenshot, and the Web Inspector needs a
   * developer (UD) unit. Playback is fine in Chrome, so the fault is the
   * platform's and cannot be reproduced anywhere this code can be watched.
   *
   * When the only oracle is the television, the app has to become the
   * instrument — the same move tvOS made with FunctionalAudit when the Apple TV
   * could not be read either. This prints the media pipeline's own events on
   * the screen, so a person standing in front of the TV can read what it did.
   *
   * TOGGLE: Up Up Down Down on the remote, within five seconds. Chosen because
   * a viewer cannot enter it by accident while browsing (it needs a reversal on
   * the same axis), it needs no extra keys registered, and it is enterable on
   * every remote including the minimal Samsung ones.
   *
   * What it records is chosen for THIS bug: every media event, plus readyState,
   * networkState, the buffered end and the error code at the moment it stops.
   * A film that dies at ~10s with networkState NETWORK_NO_SOURCE is a different
   * bug from one that dies with buffered stuck and readyState dropping, and the
   * screen has to be able to tell them apart.
   * ------------------------------------------------------------------ */

  var diagOn = false, diagEl = null, diagLines = [], diagSeq = [], diagSeqAt = 0;
  var DIAG_CODE = [38, 38, 40, 40];          // Up Up Down Down

  var NET = ['EMPTY', 'IDLE', 'LOADING', 'NO_SOURCE'];
  var RDY = ['NOTHING', 'METADATA', 'CURRENT', 'FUTURE', 'ENOUGH'];

  function diagNote(line) {
    if (!diagOn) return;
    var t = new Date().toISOString().slice(11, 23);
    diagLines.push(t + '  ' + line);
    if (diagLines.length > 18) diagLines.shift();
    if (diagEl) diagEl.textContent = diagLines.join('\n');
  }

  function diagSnapshot(v) {
    if (!v) return 'no video element';
    var b = '-';
    try { b = v.buffered.length ? v.buffered.end(v.buffered.length - 1).toFixed(1) : '0'; }
    catch (e) { b = '?'; }
    return 't=' + v.currentTime.toFixed(1) +
           ' buf=' + b +
           ' rdy=' + (RDY[v.readyState] || v.readyState) +
           ' net=' + (NET[v.networkState] || v.networkState) +
           (v.error ? ' ERR=' + v.error.code + ' ' + (v.error.message || '') : '');
  }

  function diagAttach(v) {
    if (!v || v.dataset.tvDiag) return;
    v.dataset.tvDiag = '1';
    ['loadstart', 'loadedmetadata', 'canplay', 'canplaythrough', 'play', 'playing',
     'waiting', 'stalled', 'suspend', 'abort', 'emptied', 'pause', 'ended', 'error']
      .forEach(function (ev) {
        v.addEventListener(ev, function () { diagNote(ev + '  ' + diagSnapshot(v)); });
      });
    // A heartbeat, because the interesting failure is SILENCE: a film that
    // stops without firing anything is the thing an event log alone would miss.
    setInterval(function () {
      if (diagOn && !v.paused) diagNote('tick  ' + diagSnapshot(v));
    }, 5000);
    diagNote('attached  src=' + String(v.currentSrc || v.src || '').slice(-64));
  }

  function diagToggle() {
    diagOn = !diagOn;
    if (diagOn) {
      if (!diagEl) {
        diagEl = document.createElement('pre');
        diagEl.className = 'tv-diag';
      }
      // AN OPEN <dialog> IS IN THE TOP LAYER, and nothing outside it can be
      // painted above — z-index does not apply across that boundary. The
      // player IS a dialog, so an overlay appended to <body> is created,
      // updated, and invisible behind the film. Put it inside whatever is on
      // top. Found on the glass; it would have shipped as a diagnostic that
      // silently showed nothing, which is worse than no diagnostic at all.
      // The STAGE, not the dialog root and not <body>. Evidence, not theory:
      // .tv-transport is appended to video.parentElement and renders correctly
      // inside the open player, so that element is provably paintable. An open
      // <dialog> is in the TOP LAYER and nothing outside it can be drawn above,
      // so <body> is invisible while a film is up — which is exactly when this
      // is needed.
      var v = document.querySelector('video');
      var host = (v && v.parentElement) || document.body;
      if (diagEl.parentElement !== host) host.appendChild(diagEl);
      diagEl.hidden = false;
      diagLines = ['diagnostics ON — Up Up Down Down again to hide',
                   'platform=' + PLATFORM + '  ua=' + navigator.userAgent.slice(0, 60)];
      diagEl.textContent = diagLines.join('\n');
      var v = document.querySelector('video');
      if (v) { diagAttach(v); diagNote('now  ' + diagSnapshot(v)); }
    } else if (diagEl) {
      diagEl.hidden = true;
    }
  }

  function diagKey(code) {
    var now = Date.now();
    if (now - diagSeqAt > 5000) diagSeq = [];
    diagSeqAt = now;
    diagSeq.push(code);
    if (diagSeq.length > DIAG_CODE.length) diagSeq.shift();
    if (diagSeq.length === DIAG_CODE.length &&
        diagSeq.every(function (c, i) { return c === DIAG_CODE[i]; })) {
      diagSeq = [];
      diagToggle();
    }
  }

  /* ------------------------------------------------------------------ *
   * TV TRANSPORT (§5.3)
   *
   * `<video controls>` renders the BROWSER's control bar — pause, 0:00,
   * volume, fullscreen, a kebab menu. On a desktop that is correct and free.
   * On a television it is the owner's "controls that only work for a desktop
   * web browser", and that is literally what they are: Chrome's widgets, laid
   * out for a pointer, at pointer sizes, in a strip a D-pad cannot enter.
   *
   * So on TV the attribute comes OFF and we draw our own, because the KEYS are
   * already ours: OK toggles, Left/Right seek, Back closes (see onKeyDown).
   * A TV transport is a READOUT, not a set of targets — there is nothing to
   * click, so nothing needs to be focusable, and it must never take a press
   * away from the film.
   *
   * It shows on any key and hides itself after a few seconds of stillness,
   * which is the convention every ten-foot player uses.
   * ------------------------------------------------------------------ */

  var transportEl = null, transportTimer = null;

  function fmtTime(sec) {
    if (!isFinite(sec) || sec < 0) sec = 0;
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60),
        s = Math.floor(sec % 60);
    var mm = (h && m < 10 ? '0' : '') + m;
    return (h ? h + ':' : '') + mm + ':' + (s < 10 ? '0' : '') + s;
  }

  function ensureTransport(video) {
    var stage = video.parentElement;
    if (!stage) return null;
    if (transportEl && stage.contains(transportEl)) return transportEl;
    transportEl = document.createElement('div');
    transportEl.className = 'tv-transport';
    transportEl.setAttribute('aria-hidden', 'true');   // a readout, not a control
    transportEl.innerHTML =
      '<div class="tv-tp-row">' +
        '<span class="tv-tp-state"></span>' +
        '<span class="tv-tp-now"></span>' +
        '<div class="tv-tp-bar"><i></i></div>' +
        '<span class="tv-tp-dur"></span>' +
      '</div>' +
      '<p class="tv-tp-hint">OK play/pause · ◀ ▶ 10s · Back to exit</p>';
    stage.appendChild(transportEl);
    return transportEl;
  }

  function paintTransport(video) {
    var el = ensureTransport(video);
    if (!el) return;
    var d = video.duration, t = video.currentTime;
    el.querySelector('.tv-tp-state').textContent = video.paused ? '❚❚' : '▶';
    el.querySelector('.tv-tp-now').textContent = fmtTime(t);
    el.querySelector('.tv-tp-dur').textContent = isFinite(d) ? fmtTime(d) : '';
    el.querySelector('.tv-tp-bar i').style.width =
      (isFinite(d) && d > 0 ? Math.min(100, (t / d) * 100) : 0) + '%';
  }

  function showTransport() {
    var v = activeVideo();
    if (!v) return;
    var el = ensureTransport(v);
    if (!el) return;
    paintTransport(v);
    el.classList.add('on');
    clearTimeout(transportTimer);
    // Paused stays visible: a still frame with no readout looks like a crash.
    if (!v.paused) {
      transportTimer = setTimeout(function () { el.classList.remove('on'); }, 4000);
    }
  }

  /** Strip the browser's controls and take over. Runs whenever a video shows
   *  up, because the player is opened by the app, not by us. */
  function adoptVideo(video) {
    diagAttach(video);          // record from the first frame, not from the toggle
    if (video.dataset.tvAdopted) return;
    video.dataset.tvAdopted = '1';
    video.removeAttribute('controls');
    video.addEventListener('timeupdate', function () {
      if (transportEl && transportEl.classList.contains('on')) paintTransport(video);
    });
    ['play', 'pause', 'seeked', 'loadedmetadata'].forEach(function (ev) {
      video.addEventListener(ev, showTransport);
    });
    showTransport();
  }

  /* ------------------------------------------------------------------ *
   * Playback keys (§5.2)
   * ------------------------------------------------------------------ */

  function activeVideo() {
    const v = document.querySelector('video');
    return v && isReachable(v) ? v : null;
  }

  function togglePlay(v) { if (v.paused) v.play(); else v.pause(); }
  function seekBy(v, delta) {
    const end = isFinite(v.duration) ? v.duration : Infinity;
    v.currentTime = Math.min(Math.max(v.currentTime + delta, 0), end);
  }

  /* ------------------------------------------------------------------ *
   * Key handling
   * ------------------------------------------------------------------ */

  function goBack() {
    // §1.7 — Back is layered, and the layers matter.
    //
    // An OPEN OVERLAY IS THE TOP LAYER. Backing out of the player used to run
    // history.back(), which changed the hash to home while leaving the <dialog>
    // open and the video PLAYING — a film over the home page with no way out,
    // and an automatic fail on LG's and Samsung's Back-behaviour tests.
    // Verified in Chrome; close the overlay and stop playback first.
    const openDialog = document.querySelector('dialog[open]');
    if (openDialog) {
      const vid = openDialog.querySelector('video');
      if (vid) { try { vid.pause(); } catch (e) { /* ignore */ } }
      if (typeof openDialog.close === 'function') openDialog.close();
      else openDialog.removeAttribute('open');
      claimFocus();
      return;
    }

    // Otherwise navigate back, and exit from the root. Never swallowed.
    if ((location.hash || '#/').replace(/^#\/?/, '') === '') {
      exitApp();
    } else {
      history.back();
    }
  }

  function exitApp() {
    if (PLATFORM === 'tizen' && window.tizen && tizen.application) {
      try { tizen.application.getCurrentApplication().exit(); return; } catch (e) { /* fall through */ }
    }
    if (PLATFORM === 'webos' && window.webOS && webOS.platformBack) {
      try { webOS.platformBack(); return; } catch (e) { /* fall through */ }
    }
    window.close();
  }

  /* ------------------------------------------------------------------ *
   * The marquee (§4) — a slideshow on a television, not a scroll rail
   * ------------------------------------------------------------------ */

  /* watch.js builds the hero as a scroll-snap rail: six slides laid out side
   * by side, one in view and five off to the right. On a phone that is exactly
   * right, because a phone swipes. On a television all six CTAs are `a[href]`,
   * so the spatial engine treats every one as a candidate and picks among them
   * by geometry — measured on Home with tools/tv_reachability.mjs at a true
   * 1920x1080: five of the six reachable, one not, and Right from the marquee
   * landing on a carousel dot rather than the shelf beside it. Worse, focusing
   * an off-screen CTA drags the rail sideways, because a browser scrolls a
   * focused element into view: the marquee moved without the viewer asking.
   *
   * On TV the rail becomes a slideshow. Only the slide ON SCREEN is focusable;
   * Left and Right step between featured films from the CTA itself. Left on
   * the first film falls through to the engine, so it reaches the nav rail —
   * the rule the Roku and tvOS heroes already follow. The dots stay as the
   * indicator they are (tv.css gives them a remote-sized hit box) and still
   * work, so there are two ways to change film and neither is a dead control. */

  function heroRail() {
    const rail = document.getElementById('hero-rail');
    if (!rail) return null;
    const slides = rail.querySelectorAll('.hero-cta');
    return slides.length ? { rail, slides } : null;
  }

  function heroIndex(h) {
    return Math.round(h.rail.scrollLeft / Math.max(1, h.rail.clientWidth));
  }

  /** Only the slide in view may be landed on — and the dots become what they
   *  always were, an indicator. tv.css grew them a remote-sized hit box back
   *  when they were the ONLY way to change film; now Left/Right on the CTA
   *  does that, and six identical unlabelled targets sitting between the
   *  marquee and the first shelf is a stop the remote should not have to make.
   *  They still work under a pointer, and they still show which film of six
   *  this is. */
  function heroSync() {
    const h = heroRail();
    if (!h) return;
    const cur = heroIndex(h);
    for (let i = 0; i < h.slides.length; i++) {
      if (i === cur) h.slides[i].removeAttribute('tabindex');
      else h.slides[i].setAttribute('tabindex', '-1');
    }
    const dots = document.getElementById('hero-dots');
    if (dots) {
      const b = dots.querySelectorAll('button');
      for (let i = 0; i < b.length; i++) b[i].setAttribute('tabindex', '-1');
    }
  }

  /** Step the marquee. Returns false when there is nowhere to go, so the
   *  caller can let the ordinary spatial move run instead — that is how Left
   *  on the first film reaches the nav rail rather than dead-ending. */
  function heroStep(delta) {
    const h = heroRail();
    if (!h) return false;
    const next = heroIndex(h) + delta;
    if (next < 0 || next >= h.slides.length) return false;
    h.rail.scrollTo({ left: next * h.rail.clientWidth, behavior: 'smooth' });
    // Mark the destination reachable BEFORE focusing it, or FOCUSABLE still
    // excludes it and the engine's next move computes from a stale cursor.
    for (let i = 0; i < h.slides.length; i++) {
      if (i === next) h.slides[i].removeAttribute('tabindex');
      else h.slides[i].setAttribute('tabindex', '-1');
    }
    h.slides[next].focus();
    return true;
  }

  function installHero() {
    // The rail scrolls on its own (watch.js auto-advances) and is rebuilt on
    // every Home render, so the reachable slide is re-derived from the scroll
    // position rather than tracked.
    document.addEventListener('scroll', function (ev) {
      if (ev.target && ev.target.id === 'hero-rail') heroSync();
    }, true);
  }

  function onKeyDown(ev) {
    const code = ev.keyCode;
    diagKey(code);
    // Back belongs to the picker while one is open, or Back would leave the
    // surface with a sheet still on screen over the next one.
    if (BACK_KEYS.has(code) && document.querySelector('.tv-picker-sheet')) {
      ev.preventDefault(); ev.stopPropagation();
      closePicker();
      return;
    }
    // Same rule for the share sheet: Back dismisses the sheet before it means
    // anything else, or the viewer leaves the playlist with a code still lit
    // over whatever came next.
    if (BACK_KEYS.has(code) && document.querySelector('.tv-qr-sheet')) {
      ev.preventDefault(); ev.stopPropagation();
      closeShare();
      return;
    }
    // And the confirmation, for the same reason: Back must not leave an
    // irreversible question sitting over the next screen.
    if (BACK_KEYS.has(code) && document.querySelector('.tv-confirm-sheet')) {
      ev.preventDefault(); ev.stopPropagation();
      closeConfirm();
      return;
    }        // the toggle must see EVERY press, including ones
                          // the player or the focus engine goes on to consume
    cancelArrival();      // the viewer is driving now; never yank their focus

    if (BACK_KEYS.has(code)) { ev.preventDefault(); goBack(); return; }

    const video = activeVideo();
    if (video) {
      adoptVideo(video);          // the player is opened by the app, not by us
      showTransport();            // any press brings the readout back
      switch (code) {
        case KEY.PLAY_PAUSE: case KEY.ENTER:
          ev.preventDefault(); togglePlay(video); return;
        case KEY.PLAY: ev.preventDefault(); video.play(); return;
        case KEY.PAUSE: ev.preventDefault(); video.pause(); return;
        case KEY.STOP: ev.preventDefault(); video.pause(); goBack(); return;
        case KEY.REWIND: case KEY.LEFT:
          ev.preventDefault(); seekBy(video, -SEEK_STEP); return;
        case KEY.FF: case KEY.RIGHT:
          ev.preventDefault(); seekBy(video, SEEK_STEP); return;
        default: break;
      }
    }

    // A FOCUSED <select> OWNS UP/DOWN. Without this the handler ran spatial
    // navigation on every arrow regardless of what had focus, so the arrows
    // moved focus off the control and its value could never change: Browse's
    // decade, keyword, studio and sort filters were reachable, looked fine,
    // and were dead on every TV. Left/Right still navigate, so the viewer is
    // never trapped inside a control they cannot leave — which is the failure
    // mode a naive "exempt form controls" fix introduces instead.
    const focused = document.activeElement;
    if (focused && focused.tagName === 'SELECT' && !focused.disabled
        && (code === KEY.UP || code === KEY.DOWN)) {
      return;                       // let the browser change the value
    }

    // The marquee owns Left/Right while it has focus: on a television a hero
    // is a slideshow, and stepping films is what those arrows mean there.
    if (focused && focused.classList && focused.classList.contains('hero-cta')
        && (code === KEY.LEFT || code === KEY.RIGHT)) {
      ev.preventDefault();
      if (heroStep(code === KEY.RIGHT ? 1 : -1)) return;
      // Nowhere left to step — fall through to the ordinary move, so Left on
      // the first film still reaches the nav rail.
    }

    switch (code) {
      case KEY.LEFT:  ev.preventDefault(); move('left');  break;
      case KEY.UP:    ev.preventDefault(); move('up');    break;
      case KEY.RIGHT: ev.preventDefault(); move('right'); break;
      case KEY.DOWN:  ev.preventDefault(); move('down');  break;
      case KEY.ENTER: {
        // Activate EXPLICITLY rather than relying on native behaviour.
        // Chrome does activate a focused <a> on a real Enter (verified), but TV
        // browsers are inconsistent about it, and "it works in Chrome" is not
        // the bar — the app has to work on the panel. preventDefault() first so
        // a browser that WOULD have activated natively cannot double-fire.
        const a = document.activeElement;
        if (a && a !== document.body && typeof a.click === 'function') {
          ev.preventDefault();
          a.click();
        }
        break;
      }
      default: break;
    }
  }

  /* ------------------------------------------------------------------ *
   * Lifecycle (§7.3) — pause on suspend, resume focus on return
   * ------------------------------------------------------------------ */

  function onHidden() {
    const v = document.querySelector('video');
    if (v && !v.paused) v.pause();
  }

  function installLifecycle() {
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) onHidden(); else claimFocus();
    });

    if (PLATFORM === 'webos') {
      // webOS relaunch delivers a fresh launch params payload rather than a
      // new document — treat it as a re-entry and re-claim focus.
      document.addEventListener('webOSRelaunch', claimFocus);
      document.addEventListener('webOSLaunch', claimFocus);
    }
    if (PLATFORM === 'tizen') {
      // The hardware Back/Exit key arrives as its own event on Tizen in
      // addition to keydown, depending on firmware.
      document.addEventListener('tizenhwkey', function (e) {
        if (e.keyName === 'back') { e.preventDefault(); goBack(); }
      });
    }
  }

  /** Tizen only delivers the media/colour keys after they are registered. */
  function registerTizenKeys() {
    if (PLATFORM !== 'tizen' || !window.tizen || !tizen.tvinputdevice) return;
    ['MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop',
     'MediaRewind', 'MediaFastForward'].forEach(function (name) {
      try { tizen.tvinputdevice.registerKey(name); } catch (e) { /* not all models expose all keys */ }
    });
  }

  /* ------------------------------------------------------------------ *
   * Magic Remote coexistence (§7.4) — pointer and D-pad share one focus state
   * ------------------------------------------------------------------ */

  function installPointerBridge() {
    // LG's pointer mode is not optional to support. Hovering moves focus so
    // that when the user puts the pointer down, the D-pad continues from where
    // they were looking — two input models, ONE focus state.
    document.addEventListener('mouseover', function (ev) {
      const el = ev.target && ev.target.closest ? ev.target.closest(FOCUSABLE) : null;
      if (el && isReachable(el) && el !== document.activeElement) {
        el.focus({ preventScroll: true });
      }
    });
  }

  /* ------------------------------------------------------------------ *
   * Boot
   * ------------------------------------------------------------------ */

  function boot() {
    // Activates the TV breakpoint in tv.css. Additive: the mobile-first
    // stylesheet is untouched (§7.5).
    document.documentElement.classList.add('tv', 'tv-' + PLATFORM);

    registerTizenKeys();
    installLifecycle();
    installHero();
    installPointerBridge();
    window.addEventListener('keydown', onKeyDown, true);

    // Re-claim focus whenever the viewer swaps views. Hash routing means we do
    // not need to hook showView() at all — no view code changes (§7.1).
    window.addEventListener('hashchange', function () {
      closePicker();
      closeShare();
      closeConfirm();
      tvPickers();
      heroSync();
      claimFocus();
      beginArrival();
    });

    // The first render is asynchronous (catalog index fetch), so watch for the
    // DOM filling in rather than guessing a delay.
    const mo = new MutationObserver(function () {
      const v = activeVideo();
      if (v) adoptVideo(v);       // strip the browser's controls the moment it exists
      heroSync();   // Home re-renders its rail asynchronously
      const active = document.activeElement;
      if (!active || active === document.body) claimFocus();
    });
    // ATTRIBUTES TOO. Opening a <dialog> sets `open` — an attribute mutation,
    // not a childList one — and the <video> is static markup that has existed
    // since first paint. Without this the browser's own control bar showed
    // until the viewer happened to press something.
    mo.observe(document.body, { childList: true, subtree: true,
                                attributes: true, attributeFilter: ['open'] });

    // The ONE global this layer publishes. watch.js feature-detects it rather
    // than assuming the TV layer booted, so a phone build is untouched.
    window.AWTV = window.AWTV || {};
    window.AWTV.shareQR = shareQR;
    window.AWTV.confirm = tvConfirm;

    tvPickers();
    heroSync();
    claimFocus();
    // A deep link (or a side-loaded app opened straight onto a route) fires no
    // hashchange, so arrival has to be started at boot as well.
    beginArrival();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
