/* Can a remote actually REACH every control on the screen?
 *
 * The owner's complaint had two halves. "The screen follows the selection
 * rectangle" is measured by tools/tv_follow_focus.mjs. This is the other one:
 * "it is easy to navigate to all of the interface elements."
 *
 * They are genuinely different properties, and this project has paid for the
 * difference more than once — a dead SELECT on every leftmost element, and a
 * `.clickable` class that rendered the whole EPG and every shared grid while
 * making them unreachable by remote. A screenshot shows a control. It does not
 * show whether four arrow keys can get to it.
 *
 * HOW IT WORKS. Every focusable is given an index, then each one is focused
 * programmatically in turn and the four arrows are pressed from it, recording
 * where focus lands. That builds the real focus GRAPH. A breadth-first walk
 * from wherever the app puts focus at boot then says which nodes are reachable
 * — and anything left over is on screen and unreachable.
 *
 * Focusing programmatically is the only way to explore a graph you cannot
 * teleport around, and it is sound here because tv.js reads
 * document.activeElement rather than keeping its own separate cursor.
 *
 * ⚠️  NOT YET VALIDATED, AND ITS ZEROS SHOULD NOT BE QUOTED AS EVIDENCE.
 *
 * Every other checker in this repo was checked to FAIL against a planted
 * defect before its passes were believed. This one has no such control yet.
 * Three were tried and all three proved something other than intended:
 *   - a `.tv-hidden-select` plant — that class is display:none, so the button
 *     was never on screen and "unreachable" was not what was being tested;
 *   - swallowing ArrowDown from a capture listener — tv.js registers its own
 *     capture listener on window first, and a later one cannot preempt it;
 *   - a visible focusable parked outside the viewport — the spatial engine
 *     reaches it anyway, so it is not an unreachable element at all.
 * Until a control lands that this harness demonstrably catches, treat a clean
 * run as "nothing observed" rather than "nothing wrong". The graph walk itself
 * IS controlled (see the self-check below).
 *
 * SCOPE. This measures STATIC surfaces. A route that re-renders on focus
 * cannot be walked exhaustively without disturbing itself, and the run says
 * NOT MEASURABLE rather than guessing — see the churn check below.
 *
 *   node tools/tv_reachability.mjs
 *   AW_TV_URL=http://127.0.0.1:8099/?tv=1 AW_TV_ROUTES='#/browse' node tools/tv_reachability.mjs
 */
import { spawn } from "node:child_process";

const CHROME = process.env.AW_CHROME
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = Number(process.env.AW_TV_PORT || 9232);
const SITE = process.env.AW_TV_URL || process.env.AW_BASE || "https://archivewatch.org/?tv=1";
const ROUTES = (process.env.AW_TV_ROUTES
  || "#/search,#/library,#/collections,#/surprise,#/item/the-grapes-of-wrath-1940").split(",");
/* Each element costs four presses, so a 400-tile grid is 1,600 of them. The
 * cap keeps a run to minutes; the routes worth checking exhaustively are the
 * ones with CONTROLS rather than hundreds of identical tiles. */
const CAP = Number(process.env.AW_TV_CAP || 90);
const SETTLE = Number(process.env.AW_TV_SETTLE || 90);

const KEYS = { Up: [38, "ArrowUp"], Down: [40, "ArrowDown"],
               Left: [37, "ArrowLeft"], Right: [39, "ArrowRight"] };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`,
  "--window-size=1920,1080", "--hide-scrollbars", "--no-first-run",
  `--user-data-dir=/tmp/aw-reach-${process.pid}`, "about:blank"],
  { stdio: ["ignore", "ignore", "pipe"] });

let target;
for (let i = 0; i < 80 && !target; i++) {
  await sleep(250);
  try {
    target = (await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json()))
      .find((x) => x.type === "page");
  } catch { /* not up */ }
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
  const [code, name] = KEYS[key];
  const k = { windowsVirtualKeyCode: code, code: name, key: name };
  await cdp("Input.dispatchKeyEvent", { type: "keyDown", ...k });
  await cdp("Input.dispatchKeyEvent", { type: "keyUp", ...k });
  await sleep(SETTLE);
}

/* A node is identified by its CONTENT, not by an index injected into the DOM.
 *
 * The first version tagged elements with data-aw-reach and trusted the numbers
 * to survive. They do not: a season chip SELECTS ON FOCUS and rebuilds the
 * episode list under it, so every tag went stale mid-walk and the harness
 * reported 15 of 16 elements unreachable on a page where a remote moves around
 * perfectly well. The assumption written in this file — "the DOM is rebuilt on
 * navigation, never mid-route" — was simply false.
 *
 * A key of TAG + text + an ordinal for duplicates survives a re-render, which
 * is what a focus graph needs. NOT class: a class carries STATE — a selected
 * season chip is "season-chip on" and an unselected one "season-chip" — so
 * keying on it split one element into two nodes and invented four more
 * unreachable chips on a page a remote walks perfectly well. Second keying
 * flaw found the same way as the first: by running the harness against a page
 * already known to behave, and disbelieving it. */
const KEYS_JS = `(() => {
  const SEL = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';
  const seen = new Map();
  const out = [];
  for (const el of document.querySelectorAll(SEL)) {
    if (el.closest('[hidden]')) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    const base = el.tagName + '|'
      + (el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 30);
    const n = (seen.get(base) || 0); seen.set(base, n + 1);
    out.push(base + '#' + n);
  }
  return out;
})()`;

/** The key of whatever is focused now, computed the same way. */
const WHERE = `(() => {
  const SEL = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';
  const a = document.activeElement;
  if (!a) return '';
  const seen = new Map();
  for (const el of document.querySelectorAll(SEL)) {
    if (el.closest('[hidden]')) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    const base = el.tagName + '|'
      + (el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 30);
    const n = (seen.get(base) || 0); seen.set(base, n + 1);
    if (el === a) return base + '#' + n;
  }
  return '';
})()`;

/** Focus the element carrying this key, if it is still on the page. */
const focusKey = (k) => `(() => {
  const SEL = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';
  const seen = new Map();
  for (const el of document.querySelectorAll(SEL)) {
    if (el.closest('[hidden]')) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    const base = el.tagName + '|'
      + (el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 30);
    const n = (seen.get(base) || 0); seen.set(base, n + 1);
    if (base + '#' + n === ${JSON.stringify(k)}) { el.focus(); return document.activeElement === el; }
  }
  return false;
})()`;

/* SELF-CHECK of the walk itself, before any of it is believed. The browser
 * measurement below is not yet validated (see the header); the graph walk at
 * least is, and it runs every time so a refactor cannot quietly break it. */
{
  const reach = (edges, seed, all) => {
    const seen = new Set([seed]); const q = [seed];
    while (q.length) { const c = q.shift();
      for (const nx of (edges.get(c) || [])) if (!seen.has(nx)) { seen.add(nx); q.push(nx); } }
    return all.filter((k) => !seen.has(k));
  };
  const e = new Map([["a", new Set(["b"])], ["b", new Set(["a"])], ["island", new Set()]]);
  const out = reach(e, "a", ["a", "b", "island"]);
  if (out.length !== 1 || out[0] !== "island") {
    console.log(`FAIL  the walk does not report an isolated node (got ${JSON.stringify(out)})`);
    process.exit(1);
  }
}

let totalUnreached = 0, totalNodes = 0;
console.log(`reachability: every focusable, four arrows each  @1920x1080  (cap ${CAP}/route)\n`);

for (const route of ROUTES) {
  await cdp("Page.navigate", { url: SITE.split("#")[0] + route });
  await sleep(3200);

  // SETTLE FIRST. tv.js keeps claiming focus for a while after a route change
  // (beginArrival), and it stops the moment a key arrives (cancelArrival). So
  // press one harmless pair to end that, then wait for activeElement to hold
  // still across two reads before tagging anything.
  //
  // Skipping this is what made the first version of this harness report 27 of
  // 28 elements unreachable on About and 0 on the very next run — it was
  // tagging mid-arrival and walking a graph from a node the app was about to
  // move away from. An unstable measurement is worse than no measurement: it
  // invents defects.
  await press("Down"); await press("Up");
  let last = null, stableFor = 0;
  for (let i = 0; i < 20 && stableFor < 2; i++) {
    const who = await evaluate(`(() => {
      const a = document.activeElement;
      return a ? (a.className || a.tagName) + '|' + (a.textContent || '').trim().slice(0, 20) : 'none';
    })()`);
    stableFor = (who === last) ? stableFor + 1 : 0;
    last = who;
    await sleep(150);
  }

  // NEGATIVE CONTROL. AW_TV_PLANT=1 adds a real, visible, focusable button
  // parked OUTSIDE the viewport. It is in this harness's pool (it has a box
  // and is not display:none) and the spatial engine will never select it,
  // because it is nowhere near anything. If a planted run still reports 0,
  // the harness is measuring nothing and its clean runs mean nothing either.
  //
  // Two earlier controls failed and are worth naming so they are not retried:
  // a `.tv-hidden-select` plant proved only that the class is display:none, so
  // it was never on screen; and swallowing ArrowDown from a capture listener
  // does nothing, because tv.js registers its own capture listener on window
  // first and a later one on the same target cannot preempt it.
  if (process.env.AW_TV_PLANT) {
    await evaluate(`(() => {
      const b = document.createElement('button');
      b.textContent = 'PLANTED UNREACHABLE';
      b.style.cssText = 'position:fixed;left:-3000px;top:400px;width:260px;height:60px;';
      document.body.appendChild(b);
      return true;
    })()`);
  }

  const nodes = (await evaluate(KEYS_JS)) || [];
  const start = await evaluate(WHERE);
  const n = Math.min(nodes.length, CAP);
  if (!n) { console.log(`${route}  —  nothing focusable`); continue; }
  if (process.env.AW_TV_DEBUG) {
    console.log(`    [debug] boot focus = ${start || "(not a focusable)"}`);
  }

  const pool = nodes.slice(0, n);
  const edges = new Map();
  for (const from of pool) {
    const to = new Set();
    for (const key of Object.keys(KEYS)) {
      if (!(await evaluate(focusKey(from)))) continue;   // gone after a re-render
      await press(key);
      const landed = await evaluate(WHERE);
      if (landed && landed !== from) to.add(landed);
    }
    edges.set(from, to);
  }

  const seed = start || pool[0];
  const seen = new Set([seed]);
  const queue = [seed];
  while (queue.length) {
    const cur = queue.shift();
    for (const nx of (edges.get(cur) || [])) {
      if (!seen.has(nx)) { seen.add(nx); queue.push(nx); }
    }
  }

  // DID THE WALK CHANGE THE PAGE UNDER ITSELF?
  //
  // On a surface that re-renders on focus — a season chip selects as soon as
  // it is focused, swapping the whole episode list — an exhaustive per-node
  // walk MUTATES the thing it is measuring. By the time the walk reaches the
  // episode node, that episode no longer exists, so its edges are never
  // recorded and everything downstream of it looks unreachable. Manually the
  // page is fine: Down from the episode reaches the footer on the first press.
  //
  // So the tool refuses to report a number it cannot stand behind. This is the
  // same rule the dashboard follows (Decision 108): a reader that cannot read
  // SAYS SO, and never a confident zero — or in this case, never a confident
  // list of defects that are not there.
  const after = (await evaluate(KEYS_JS)) || [];
  const churned = after.length !== nodes.length
    || after.some((k, i) => k !== nodes[i]);
  if (churned) {
    console.log(`${route.slice(0, 40).padEnd(42)} ${n} focusable — NOT MEASURABLE: the page`);
    console.log(`      re-renders on focus, so an exhaustive walk changes what it measures.`);
    continue;
  }

  const unreached = pool.filter((k) => !seen.has(k));
  totalNodes += n; totalUnreached += unreached.length;
  console.log(`${route.slice(0, 40).padEnd(42)} ${n} focusable, ${unreached.length} UNREACHABLE`
            + (nodes.length > n ? `  (capped from ${nodes.length})` : ""));
  for (const u of unreached.slice(0, 6)) console.log(`      ${u}`);
}

console.log(`\n${totalNodes} focusable elements walked, ${totalUnreached} that no arrow key reaches`);
ws.close(); chrome.kill();
process.exit(totalUnreached ? 1 : 0);
