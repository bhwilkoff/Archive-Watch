/* tv_audit_sizes — is anything on the TV still built for a mouse?
 *
 * The owner, after using the Tizen build on a 65" set: "All designs should be
 * updated for the tv interface! There should be nothing optimized for a web
 * interface (as they are now)." That is a real instruction and it deserves a
 * real measurement rather than a designer's eye, because the failure mode is
 * specific and countable: type too small to read across a room, and hit
 * targets too small to land on with four arrows.
 *
 * The thresholds are the platform vendors' own, not invented here:
 *   * Google's TV guidance puts BODY text at a 24sp floor at 1080p, and
 *     nothing legible below 18sp.
 *   * Every TV platform asks for focusable targets around 48-64px tall,
 *     because a D-pad lands on a whole element and a viewer cannot aim.
 *
 * So: render at a true 1920x1080, walk the routes, and report every FOCUSABLE
 * element whose computed font-size or box fails those floors. It reports
 * rather than fails — the point is a worklist, and a legitimately small thing
 * (a decorative caption) is a judgement, not a bug.
 *
 *   node tools/tv_audit_sizes.mjs
 *   AW_TV_URL=http://127.0.0.1:8099/?tv=1 node tools/tv_audit_sizes.mjs
 */
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const CHROME = process.env.AW_CHROME
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = Number(process.env.AW_TV_PORT || 9223);
const SITE = process.env.AW_TV_URL || "https://archivewatch.org/?tv=1";
const ROUTES = (process.env.AW_TV_ROUTES
  || "#/home,#/browse,#/search,#/library,#/collections,#/surprise,#/channels").split(",");
/* AW_TV_KEYS presses a sequence on each route BEFORE measuring, which is the
 * only way to reach an OVERLAY. The player is the case that forced it: it is
 * not a route, it opens on Enter from Detail, and until this existed the
 * auditor simply could not see the surface a viewer spends the most time on. */
const KEYS = (process.env.AW_TV_KEYS || "").split(",").filter(Boolean);
const KEYMAP = {
  Up: { windowsVirtualKeyCode: 38, code: "ArrowUp", key: "ArrowUp" },
  Down: { windowsVirtualKeyCode: 40, code: "ArrowDown", key: "ArrowDown" },
  Left: { windowsVirtualKeyCode: 37, code: "ArrowLeft", key: "ArrowLeft" },
  Right: { windowsVirtualKeyCode: 39, code: "ArrowRight", key: "ArrowRight" },
  Enter: { windowsVirtualKeyCode: 13, code: "Enter", key: "Enter" },
};

const MIN_FONT = 18;      // below this is not readable at ten feet
const MIN_TARGET = 44;    // below this is hard to land on with a D-pad

/* DELIBERATE EXEMPTIONS. A floor with no exceptions gets ignored, so the one
 * exception is named and reasoned rather than quietly lowered:
 *
 *   .gsi-btn — Google's Sign in with Google button. Its proportions, type
 *   (Roboto Medium 14px) and 40px height are fixed by Google's branding
 *   guidelines; restyling it is a breach of those terms, not a design choice.
 *   It appears once, on Library, and is reached by pressing Down twice. */
const EXEMPT = [/\bgsi-btn\b/];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const OUT = path.join(os.tmpdir(), "aw-tv-audit");
fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });

const chrome = spawn(CHROME, [
  "--headless=new", `--remote-debugging-port=${PORT}`,
  "--window-size=1920,1080", "--force-device-scale-factor=1",
  "--hide-scrollbars", "--no-first-run", "--no-default-browser-check",
  // A FRESH profile every run. A reused one serves a cached stylesheet, and a
  // stale stylesheet does not fail — it reports the OLD layout as the current
  // one. That cost a wrong conclusion in this session before it was noticed.
  `--user-data-dir=${path.join(OUT, "profile-" + process.pid)}`, "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] });

let target;
for (let i = 0; i < 60 && !target; i++) {
  await sleep(250);
  try {
    const list = await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json());
    target = list.find((t) => t.type === "page");
  } catch { /* not up */ }
}
if (!target) { chrome.kill(); throw new Error("Chrome did not expose a page target"); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let id = 0; const pending = new Map();
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
};
const cdp = (method, params = {}) => new Promise((res) => {
  const n = ++id; pending.set(n, res);
  ws.send(JSON.stringify({ id: n, method, params }));
});
await cdp("Page.enable"); await cdp("Runtime.enable");
const evaluate = async (expr) => (await cdp("Runtime.evaluate",
  { expression: expr, returnByValue: true, awaitPromise: true }))?.result?.value;

const PROBE = `(() => {
  const SEL = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';
  const out = [];
  for (const el of document.querySelectorAll(SEL)) {
    if (el.closest('[hidden]')) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    // The floor applies to the node that actually DRAWS the text, which is not
    // always the focusable itself. A card at 24px can contain a 15px span, and
    // reading only the focusable's own font-size passed it — that is exactly
    // how the typographic placeholder card shipped at 15px on a television.
    let minFont = Math.round(parseFloat(cs.fontSize) || 0);
    let minText = (el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 34);
    let minCls = (el.className || '').toString().split(/\\s+/)[0] || '';
    for (const d of el.querySelectorAll('*')) {
      let own = '';
      for (const n of d.childNodes) if (n.nodeType === 3) own += n.textContent;
      own = own.trim();
      if (!own) continue;
      const dr = d.getBoundingClientRect();
      if (dr.width <= 0 || dr.height <= 0) continue;
      const dcs = getComputedStyle(d);
      if (dcs.visibility === 'hidden' || dcs.display === 'none') continue;
      const f = Math.round(parseFloat(dcs.fontSize) || 0);
      if (f > 0 && f < minFont) {
        minFont = f;
        minText = own.replace(/\\s+/g, ' ').slice(0, 34);
        minCls = (d.className || '').toString().split(/\\s+/)[0] || minCls;
      }
    }
    // OVERLAPPING TEXT. A size floor proves the type is big enough, never that
    // it FITS, and enlarging type for a television is exactly what makes it
    // stop fitting — so this is here as a second, independent question.
    //
    // BE HONEST ABOUT WHAT IT CAUGHT: not the EPG. Raising the guide's labels
    // to the floor left 168 of 558 programme titles squeezed to a line and a
    // half and cut mid-glyph, and this check reported ZERO — correctly, because
    // the flex column shrank each title rather than letting two boxes collide.
    // The SCREENSHOT is what found that one. Two text boxes overlapping is
    // still never intentional, so the check earns its place; it is just not the
    // one that would have saved that afternoon.
    const boxes = [];
    for (const d of el.querySelectorAll('*')) {
      let own = '';
      for (const n of d.childNodes) if (n.nodeType === 3) own += n.textContent;
      if (!own.trim()) continue;
      const dr = d.getBoundingClientRect();
      if (dr.width <= 0 || dr.height <= 0) continue;
      boxes.push({ el: d, r: dr, t: own.trim().slice(0, 24) });
    }
    // SQUEEZED TEXT — the check that WOULD have saved that afternoon.
    //
    // A flex column shrinks its children, so a text box can be given less room
    // than the lines it is allowed to draw, and overflow:hidden then cuts a
    // line in half. Distinguish that from DELIBERATE truncation: a
    // -webkit-line-clamp box is meant to stop at N lines and end in an
    // ellipsis. So the question is not "is anything hidden" (often yes, by
    // design) but "is this box shorter than the lines the design allots it".
    // Measured on the Channels guide: 390 titles squeezed before the fix, 0
    // after, while every other signal in this file read zero both times.
    let squeezed = '';
    for (const d of el.querySelectorAll('*')) {
      let own = '';
      for (const n of d.childNodes) if (n.nodeType === 3) own += n.textContent;
      if (!own.trim()) continue;
      const dcs = getComputedStyle(d);
      if (dcs.overflow === 'visible' || dcs.display === 'none') continue;
      const lh = parseFloat(dcs.lineHeight) || 0;
      if (!lh) continue;
      const clamp = parseInt(dcs.webkitLineClamp, 10);
      const allowed = Number.isFinite(clamp) && clamp > 0
        ? Math.round(lh * clamp) : d.scrollHeight;
      const want = Math.min(d.scrollHeight, allowed);
      if (d.clientHeight > 0 && d.clientHeight < want - 1) {
        squeezed = JSON.stringify(own.trim().slice(0, 24))
          + ' got ' + d.clientHeight + 'px, needs ' + want;
        break;
      }
    }

    let overlap = '';
    for (let i = 0; i < boxes.length && !overlap; i++) {
      for (let j = i + 1; j < boxes.length; j++) {
        // NEVER an ancestor against its own descendant: a <figcaption> that
        // holds both a name and a role <span> contains that span's box by
        // definition, so the pair always "overlaps". That false positive
        // appeared on the first real page this check ran against — Detail's
        // cast chips — and is why a check advertised as having none has to be
        // tried on real markup before the claim is made.
        if (boxes[i].el.contains(boxes[j].el) || boxes[j].el.contains(boxes[i].el)) continue;
        const a = boxes[i].r, b = boxes[j].r;
        const ox = Math.min(a.right, b.right) - Math.max(a.left, b.left);
        const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (ox > 2 && oy > 2) {
          overlap = JSON.stringify(boxes[i].t) + ' over ' + JSON.stringify(boxes[j].t);
          break;
        }
      }
    }
    out.push({
      tag: el.tagName.toLowerCase(),
      cls: minCls,
      text: minText,
      font: minFont,
      overlap,
      squeezed,
      h: Math.round(r.height), w: Math.round(r.width),
    });
  }
  return out;
})()`;

let findings = 0, checked = 0;
console.log(`thresholds: font >= ${MIN_FONT}px, focusable height >= ${MIN_TARGET}px, no overlapping or squeezed text  @1920x1080\n`);

for (const route of ROUTES) {
  await cdp("Page.navigate", { url: SITE.split("#")[0] + route });
  await sleep(2600);
  for (const name of KEYS) {
    const k = KEYMAP[name];
    if (!k) continue;
    await cdp("Input.dispatchKeyEvent", { type: "keyDown", ...k });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", ...k });
    await sleep(900);
  }
  const els = (await evaluate(PROBE)) || [];
  checked += els.length;
  // The font floor applies to elements that HAVE text. A carousel dot is an
  // empty button; reporting its font-size is noise, and a checker that cries
  // about things nobody can read is a checker people learn to ignore.
  const bad = els.filter((e) => ((e.text && e.font < MIN_FONT) || e.h < MIN_TARGET
                                 || e.overlap || e.squeezed)
                             && !EXEMPT.some((re) => re.test(e.cls)));
  console.log(`${route}  —  ${els.length} focusable, ${bad.length} below the floor`);
  const seen = new Set();
  for (const b of bad) {
    const key = `${b.tag}.${b.cls}:${b.font}:${b.h}:${b.overlap ? 'ov' : ''}:${b.squeezed ? 'sq' : ''}`;
    if (seen.has(key)) continue;            // one line per KIND, not per instance
    seen.add(key);
    findings++;
    const why = [b.font < MIN_FONT ? `font ${b.font}px` : null,
                 b.h < MIN_TARGET ? `height ${b.h}px` : null,
                 b.overlap ? `TEXT OVERLAP: ${b.overlap}` : null,
                 b.squeezed ? `TEXT SQUEEZED: ${b.squeezed}` : null].filter(Boolean).join(", ");
    console.log(`    ${b.tag}.${b.cls || "—"}  ${why}   “${b.text}”`);
  }
}
console.log(`\n${checked} focusable elements checked, ${findings} distinct kinds below the TV floor`);
ws.close(); chrome.kill();
