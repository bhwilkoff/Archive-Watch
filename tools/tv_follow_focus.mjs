/* Does the screen actually follow the selection?
 *
 * The owner, on the Tizen build: "navigation is still extremely broken. I
 * really hope you can test and iterate on the glass yourself, because there is
 * A LOT of work to do to ensure the screen follows the selection rectangle."
 *
 * That is a testable claim, and this is the test. Walk each route with the
 * D-pad and assert, after EVERY press, that the focused element is entirely
 * inside the overscan-safe band — the 5% a television cuts off each side. A
 * selection that is on screen in a browser and under the bezel on a TV is the
 * exact failure the owner is describing, and it is invisible to a screenshot
 * taken at 1920x1080 on a desktop.
 *
 * The band is the interesting part. Checking against the VIEWPORT would have
 * passed the run that produced this harness: the footer links sat at y=1070,
 * ten pixels inside a 1080 screen and forty-four pixels inside the part of it
 * a TV does not show.
 *
 *   node tools/tv_follow_focus.mjs
 *   AW_TV_URL=http://127.0.0.1:8099/?tv=1 node tools/tv_follow_focus.mjs
 */
import { spawn } from "node:child_process";

const CHROME = process.env.AW_CHROME
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = Number(process.env.AW_TV_PORT || 9231);
const SITE = process.env.AW_TV_URL || process.env.AW_BASE || "https://archivewatch.org/?tv=1";
const ROUTES = (process.env.AW_TV_ROUTES
  || "#/home,#/browse,#/channels,#/collections,#/library").split(",");

/* 5% a side at 1080. The same numbers tv.css calls --tv-overscan-y. */
const SAFE_TOP = 54, SAFE_BOTTOM = 1026, SAFE_LEFT = 0, SAFE_RIGHT = 1920;

/* A walk that changes direction, because a one-directional run never exercises
 * the case where reveal() has to scroll BACK. */
const WALK = ["Down","Down","Right","Right","Right","Down","Right","Down","Down",
              "Right","Up","Left","Down","Down","Down","Right","Down","Down"];

const CODES = { Up:[38,"ArrowUp"], Down:[40,"ArrowDown"], Left:[37,"ArrowLeft"], Right:[39,"ArrowRight"],
                Enter:[13,"Enter"] };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

if (!SITE.includes("127.0.0.1") && !SITE.includes("localhost")) {
  console.log(`NOTE: measuring the LIVE site (${SITE}) — set AW_TV_URL to test a local edit.\n`);
}

/* A browser left on this port by an earlier run is not a convenience: Chrome
 * cannot bind an occupied port, so the new process serves nothing and
 * /json/list answers from the OLD browser — which still holds the previous
 * run's page AND its stylesheet. Found the hard way on 2026-09-13: a planted
 * CSS control was reverted on disk and the very next run still measured the
 * plant, because it never spoke to a new browser at all. The per-pid
 * --user-data-dir does not protect against this; only the port does. */
try {
  const probe = await fetch(`http://127.0.0.1:${PORT}/json/version`,
                            { signal: AbortSignal.timeout(800) });
  if (probe.ok) {
    console.log(`FAIL  a browser is already on port ${PORT}. A run that attaches`);
    console.log(`      to it measures that browser's page, not a fresh one:`);
    console.log(`      pkill -f "remote-debugging-port=${PORT}"`);
    process.exit(1);
  }
} catch { /* nothing listening — good */ }

const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`,
  "--window-size=1920,1080", "--hide-scrollbars", "--no-first-run",
  // A fresh profile every run: a stale cached stylesheet once made a fixed
  // layout look broken and cost a wrong conclusion.
  `--user-data-dir=/tmp/aw-follow-${process.pid}`, "about:blank"],
  { stdio: ["ignore", "ignore", "pipe"] });

let target;
for (let i = 0; i < 80 && !target; i++) {
  await sleep(250);
  try {
    target = (await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json()))
      .find((x) => x.type === "page");
  } catch { /* not up yet */ }
}
if (!target) { console.log("FAIL  could not start Chrome"); process.exit(1); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
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
await cdp("Emulation.setDeviceMetricsOverride",
          { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
const evaluate = async (expr) =>
  (await cdp("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true }))
    ?.result?.value;

async function press(key) {
  const [code, name] = CODES[key];
  const k = { windowsVirtualKeyCode: code, code: name, key: name };
  await cdp("Input.dispatchKeyEvent", { type: "keyDown", ...k });
  await cdp("Input.dispatchKeyEvent", { type: "keyUp", ...k });
  await sleep(230);                     // let a smooth scroll settle
}

const PROBE = `(() => {
  const a = document.activeElement;
  if (!a || a === document.body) return JSON.stringify({ none: true });
  const r = a.getBoundingClientRect();
  return JSON.stringify({
    name: (a.className || a.tagName) + '|' + (a.textContent || '').trim().slice(0, 28),
    top: Math.round(r.top), bottom: Math.round(r.bottom),
    left: Math.round(r.left), right: Math.round(r.right),
  });
})()`;

console.log(`overscan-safe band: y ${SAFE_TOP}..${SAFE_BOTTOM}, x ${SAFE_LEFT}..${SAFE_RIGHT}  @1920x1080\n`);
let checks = 0, outside = 0, lost = 0;
for (const route of ROUTES) {
  await cdp("Page.navigate", { url: SITE + route });
  await sleep(3200);
  const bad = [];
  let landed = 0, dropped = 0;
  for (const key of WALK) {
    await press(key);
    const s = JSON.parse(await evaluate(PROBE));
    if (s.none) { dropped++; continue; }
    landed++;
    const off = [];
    if (s.top < SAFE_TOP) off.push(`top ${s.top}`);
    if (s.bottom > SAFE_BOTTOM) off.push(`bottom ${s.bottom}`);
    if (s.left < SAFE_LEFT) off.push(`left ${s.left}`);
    if (s.right > SAFE_RIGHT) off.push(`right ${s.right}`);
    if (off.length) bad.push(`${key} -> ${s.name}  ${off.join(", ")}`);
  }
  checks += landed; outside += bad.length; lost += dropped;
  console.log(`${route.padEnd(16)} ${landed} presses landed, ${dropped} lost focus, `
            + `${bad.length} outside the safe band`);
  bad.slice(0, 5).forEach((b) => console.log("      " + b));
}
/* THE PLAYER, which this harness could not see.
 *
 * Everything above is keyed on document.activeElement, and the player has no
 * focused element AT ALL — by design: tv.js adopts the <video>, strips the
 * browser's controls and handles every key globally, so the whole screen is
 * the control. That made the transport the one TV surface no overscan check
 * covered, and it is drawn hard against the bottom edge, which is exactly
 * where a television cuts.
 *
 * So the player is measured differently: by the TEXT its transport draws.
 * A node is judged only when it carries its own text (the same rule
 * tv_audit_sizes uses) — a full-bleed bar may reach the edges, its LABEL may
 * not. Judging boxes instead flags every background as a defect, which is
 * what a first attempt at this did.
 */
const PLAYER_PROBE = `(() => {
  const v = document.querySelector('video');
  if (!v) return JSON.stringify({ noPlayer: true });
  const out = [];
  // The transport is NOT inside the video's own container — tv.js draws it as
  // a sibling, so scoping the search to v.closest(...) found ZERO labels and
  // reported a clean pass. A harness that measures nothing and says "0
  // outside the band" is the worst result available, so this matches the
  // transport's own class prefix and the run FAILS when it finds none.
  // Everything else on the page is the Detail screen sitting behind the
  // overlay, which is in the DOM and not on the glass.
  for (const el of document.querySelectorAll('[class*="tv-tp"]')) {
    let own = '';
    for (const n of el.childNodes) if (n.nodeType === 3) own += n.textContent;
    own = own.trim();
    if (!own) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' || cs.opacity === '0') continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    out.push({ t: own.slice(0, 34), top: Math.round(r.top), bottom: Math.round(r.bottom) });
  }
  return JSON.stringify({ items: out });
})()`;

{
  const item = process.env.AW_TV_PLAY_ITEM || "#/item/TheGeneral720p1926";
  await cdp("Page.navigate", { url: SITE + item });
  await sleep(4000);
  await press("Enter");               // boot focus lands on the Play button
  await sleep(4500);
  const p = JSON.parse(await evaluate(PLAYER_PROBE));
  if (p.noPlayer) {
    console.log(`\nplayer          NOT MEASURED: Enter did not open a player on ${item}`);
    lost++;                            // never report this as a pass
  } else {
    const bad = p.items.filter((i) => i.top < SAFE_TOP || i.bottom > SAFE_BOTTOM);
    checks += p.items.length; outside += bad.length;
    if (!p.items.length) {
      console.log(`\nplayer          NOT MEASURED: a player opened but no transport`);
      console.log(`      label was found. A clean reading from an empty probe is worse`);
      console.log(`      than no reading, so this fails rather than passing.`);
      lost++;
    } else {
      console.log(`\nplayer          ${p.items.length} transport labels, `
                + `${bad.length} outside the safe band`);
    }
    bad.slice(0, 5).forEach((b) =>
      console.log(`      "${b.t}"  top ${b.top} bottom ${b.bottom}`));
  }
}

console.log(`\n${checks} presses across ${ROUTES.length} routes — `
          + `${outside} left the selection outside the overscan-safe band, ${lost} lost focus entirely`);
ws.close(); chrome.kill("SIGKILL");
process.exit(outside || lost ? 1 : 0);
