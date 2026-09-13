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
 * CONTROLLED. AW_TV_PLANT=1 plants a control this tool MUST catch: a visible
 * <select> carrying `tv-hidden-select`, the class tv.js puts on a native
 * select once a TV button has replaced it. The engine's FOCUSABLE excludes
 * that class, so no arrow key can reach one; this harness's pool does not, so
 * it is counted. Measured both ways on #/library: planted 11 focusable / 1
 * UNREACHABLE naming the plant, unplanted 10 / 0. Three earlier controls
 * failed and are named at the plant site so they are not retried.
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

/* A browser left on this port by an earlier run is not a convenience — Chrome
 * cannot bind an occupied port, so the new process never serves anything and
 * /json/list answers from the OLD browser, which still holds the PREVIOUS
 * run's DOM. Found exactly that way: an unplanted run reported the planted
 * control, because it was still talking to the browser the plant was in. The
 * per-pid --user-data-dir does not protect against this; only the port does. */
try {
  const r = await fetch(`http://127.0.0.1:${PORT}/json/version`,
                        { signal: AbortSignal.timeout(800) });
  if (r.ok) {
    console.log(`FAIL  a browser is already on port ${PORT}. A run that attaches to it`);
    console.log(`      measures that browser's page, not a fresh one. Close it first:`);
    console.log(`      pkill -f "remote-debugging-port=${PORT}"`);
    process.exit(1);
  }
} catch { /* nothing listening — good */ }

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
/* The pool this tool measures: what a viewer can SEE and would expect to
 * reach. It deliberately differs from tv.js's own FOCUSABLE in one direction
 * only — it does not carry `:not(.tv-hidden-select)`, so a visible select the
 * engine skips lands in the denominator and is reported. That asymmetry IS the
 * negative control (AW_TV_PLANT=1).
 *
 * It DOES honour `tabindex="-1"`, on every row rather than only the last. That
 * attribute is an author's declaration that an element is not keyboard
 * reachable, not an accident of geometry — the TV hero marks its off-screen
 * slides with it (tv.js heroSync), and counting those as defects would be the
 * tool inventing five a run. */
const SEL = 'a[href]:not([tabindex="-1"])'
  + ',button:not([disabled]):not([tabindex="-1"])'
  + ',input:not([disabled]):not([tabindex="-1"])'
  + ',select:not([disabled]):not([tabindex="-1"])'
  + ',[tabindex]:not([tabindex="-1"])';

const KEYS_JS = `(() => {
  const SEL = ${JSON.stringify(SEL)};
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
  const SEL = ${JSON.stringify(SEL)};
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
  const SEL = ${JSON.stringify(SEL)};
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

  // NEGATIVE CONTROL. AW_TV_PLANT=1 plants a control this harness MUST report.
  //
  // It is a <select> carrying `tv-hidden-select` — the class tv.js puts on a
  // native select once it has replaced it with a TV button. The engine's own
  // FOCUSABLE ends `select:not([disabled]):not(.tv-hidden-select)`, so no
  // arrow key can ever land on one; this harness's pool does not carry that
  // exclusion, so it is in the denominator. Visible, on screen, in the pool,
  // and unreachable by the remote — exactly the defect class the tool exists
  // for, and a real one: the day a CSS change lets one of those selects draw
  // again, it is an on-screen control the D-pad cannot touch.
  //
  // `display` is set with priority, because the class is `display:none
  // !important` and a plain inline value loses to it — which is precisely how
  // the FIRST attempt at this control failed: the plant was excluded from the
  // engine as intended and also never on screen, so a planted run proved only
  // that a display:none element is not counted.
  //
  // Two other controls were tried and failed, named so they are not retried:
  // a focusable parked outside the viewport (the spatial engine reaches it
  // anyway — an off-screen box is still a candidate, so that is not an
  // unreachable element at all), and swallowing ArrowDown from a capture
  // listener (tv.js registers its own capture listener on window first, and a
  // later one on the same target cannot preempt it).
  if (process.env.AW_TV_PLANT) {
    await evaluate(`(() => {
      const s = document.createElement('select');
      s.className = 'tv-hidden-select';
      s.innerHTML = '<option>PLANTED</option>';
      s.style.cssText = 'position:fixed;left:140px;top:520px;width:260px;height:60px;';
      s.style.setProperty('display', 'block', 'important');
      document.body.appendChild(s);
      return true;
    })()`);
  }

  const start = await evaluate(WHERE);
  if (process.env.AW_TV_DEBUG) {
    console.log(`    [debug] boot focus = ${start || "(not a focusable)"}`);
  }

  // A TV route ALWAYS has the nav rail, so an empty pool is a broken probe,
  // not a clean route — and it was passing silently: a selector bug that made
  // every evaluate() throw printed "nothing focusable" for every route and
  // then exited 0. Decision 108 in the smallest possible form.
  if (!((await evaluate(KEYS_JS)) || []).length) {
    console.log(`FAIL  ${route}  —  nothing focusable. A TV route always has a`);
    console.log(`      nav rail, so this is the probe failing, not a clean page.`);
    process.exit(1);
  }

  /* WALK UNTIL THE PAGE STOPS GROWING.
   *
   * Browse lazy-loads: measured, an exhaustive pass took its pool 85 -> 145,
   * "removed 0, added 60" — the grid appended tiles as focus moved down it.
   * The first version of this tool called that churn and refused to report,
   * which threw away a measurable route. It is not the same thing as a page
   * re-rendering under the walk: nothing that had been walked went away, and
   * the keys are tag+text+ordinal, so appending at the END cannot renumber an
   * earlier one.
   *
   * But a grown pool is not free either — the 60 new tiles were never focused,
   * so edges OUT of them were never recorded, and a node reachable only from
   * one of them would read unreachable. So the walk simply repeats: each round
   * picks up whatever appeared in the last one, until nothing new shows up. */
  const edges = new Map();
  let rounds = 0, grew = 0;
  for (; rounds < 6; rounds++) {
    if (edges.size >= CAP) break;
    const present = (await evaluate(KEYS_JS)) || [];
    const todo = present.filter((k) => !edges.has(k)).slice(0, CAP - edges.size);
    if (!todo.length) break;
    if (rounds) grew += todo.length;
    for (const from of todo) {
      const to = new Set();
      for (const key of Object.keys(KEYS)) {
        if (!(await evaluate(focusKey(from)))) continue;   // gone after a re-render
        await press(key);
        const landed = await evaluate(WHERE);
        if (landed && landed !== from) to.add(landed);
      }
      edges.set(from, to);
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
  // list of defects that are not there. REMOVAL is the disqualifying event,
  // not growth: a node that vanished takes its edges with it.
  const present = (await evaluate(KEYS_JS)) || [];
  const now = new Set(present);
  const removed = [...edges.keys()].filter((k) => !now.has(k));
  if (removed.length) {
    console.log(`${route.slice(0, 40).padEnd(42)} ${edges.size} walked — NOT MEASURABLE:`);
    console.log(`      ${removed.length} element(s) the walk had already measured are gone,`);
    console.log(`      so the page re-renders on focus and the graph is stale.`);
    for (const r of removed.slice(0, 4)) console.log(`      gone: ${r}`);
    continue;
  }

  /* REACHABILITY IS ASYMMETRIC, and the first version of this tool threw that
   * away. A node the walk FINDS is proven reachable — a path was demonstrated,
   * and no amount of unwalked graph can take that back. Only UNreachability
   * needs the complete graph, because one unrecorded edge is enough to
   * overturn it.
   *
   * That matters because some surfaces never settle. Browse appends tiles as
   * focus moves down it, forever: six rounds took it 85 -> 385 walked and it
   * had grown by another 60. Calling that NOT MEASURABLE threw away a real
   * answer — the question worth asking there is whether the CONTROLS are
   * reachable, not whether all 30,000 tiles are. So an unfinished walk reports
   * what it PROVED and names what it could not settle, rather than refusing. */
  const unwalked = present.filter((k) => !edges.has(k));
  const pool = [...edges.keys()];
  // The seed must be INSIDE the pool, or the walk starts on an island and
  // every node reads unreachable. Measured on #/channels: 892 focusables, the
  // app boots focus onto one beyond the cap, and the run reported 90 of 90
  // unreachable INCLUDING the nav rail — a page a remote walks fine.
  const seed = (start && edges.has(start)) ? start : pool[0];
  const seen = new Set([seed]);
  const queue = [seed];
  while (queue.length) {
    const cur = queue.shift();
    for (const nx of (edges.get(cur) || [])) {
      if (!seen.has(nx)) { seen.add(nx); queue.push(nx); }
    }
  }

  const unreached = pool.filter((k) => !seen.has(k));

  if (unwalked.length) {
    console.log(`${route.slice(0, 40).padEnd(42)} ${seen.size} PROVEN reachable`
              + ` — the page kept growing (${unwalked.length} unwalked), so the`);
    console.log(`      ${unreached.length} it did not reach are UNSETTLED, not defects.`);
    for (const u of unreached.slice(0, 6)) console.log(`      unsettled: ${u}`);
    continue;
  }

  totalNodes += pool.length; totalUnreached += unreached.length;
  console.log(`${route.slice(0, 40).padEnd(42)} ${pool.length} focusable, ${unreached.length} UNREACHABLE`
            + (grew ? `  (${grew} appeared while walking, all walked too)` : ""));
  for (const u of unreached.slice(0, 6)) console.log(`      ${u}`);
}

console.log(`\n${totalNodes} focusable elements walked, ${totalUnreached} that no arrow key reaches`);
ws.close(); chrome.kill("SIGKILL");
process.exit(totalUnreached ? 1 : 0);
