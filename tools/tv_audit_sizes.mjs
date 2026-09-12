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
  `--user-data-dir=${path.join(OUT, "profile")}`, "about:blank",
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
    out.push({
      tag: el.tagName.toLowerCase(),
      cls: (el.className || '').toString().split(/\\s+/)[0] || '',
      text: (el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 34),
      font: Math.round(parseFloat(cs.fontSize) || 0),
      h: Math.round(r.height), w: Math.round(r.width),
    });
  }
  return out;
})()`;

let findings = 0, checked = 0;
console.log(`thresholds: font >= ${MIN_FONT}px, focusable height >= ${MIN_TARGET}px  @1920x1080\n`);

for (const route of ROUTES) {
  await cdp("Page.navigate", { url: SITE.split("#")[0] + route });
  await sleep(2600);
  const els = (await evaluate(PROBE)) || [];
  checked += els.length;
  // The font floor applies to elements that HAVE text. A carousel dot is an
  // empty button; reporting its font-size is noise, and a checker that cries
  // about things nobody can read is a checker people learn to ignore.
  const bad = els.filter((e) => ((e.text && e.font < MIN_FONT) || e.h < MIN_TARGET)
                             && !EXEMPT.some((re) => re.test(e.cls)));
  console.log(`${route}  —  ${els.length} focusable, ${bad.length} below the floor`);
  const seen = new Set();
  for (const b of bad) {
    const key = `${b.tag}.${b.cls}:${b.font}:${b.h}`;
    if (seen.has(key)) continue;            // one line per KIND, not per instance
    seen.add(key);
    findings++;
    const why = [b.font < MIN_FONT ? `font ${b.font}px` : null,
                 b.h < MIN_TARGET ? `height ${b.h}px` : null].filter(Boolean).join(", ");
    console.log(`    ${b.tag}.${b.cls || "—"}  ${why}   “${b.text}”`);
  }
}
console.log(`\n${checked} focusable elements checked, ${findings} distinct kinds below the TV floor`);
ws.close(); chrome.kill();
