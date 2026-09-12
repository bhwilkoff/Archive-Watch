/* tv_glass — see the TV app the way a TV shows it, and drive it the way a
   remote drives it.
 *
 * WHY THIS EXISTS. Everything before it was measured in a desktop Chrome
 * window at 1456x770 with a mouse, and called TV testing. It is not:
 *
 *   * this Mac's display is 1512 CSS px wide at dpr 2, so a true 1920x1080
 *     CSS viewport CANNOT be opened on it at all — every layout reading was
 *     taken at three quarters of TV width;
 *   * a mouse can reach anything. A remote can reach only what the focus
 *     engine finds, in the order it finds it, and only by pressing a
 *     direction — which is why a hero with no focusable child and four dead
 *     filters both passed a "check" and failed on the owner's television.
 *
 * Headless Chrome has no physical display, so it renders a real 1920x1080.
 * Input goes through Input.dispatchKeyEvent, which is a genuine key event —
 * not el.focus(), not a synthetic click, both of which lie about reachability.
 *
 * Dependency-free on purpose (the repo's rule): Node 22+ has WebSocket, and
 * CDP is just JSON over one.
 *
 *   node tools/tv_glass.mjs                     # walk Home, shoot every press
 *   node tools/tv_glass.mjs '#/browse' 24       # a route and a press count
 *   AW_KEYS=Down,Down,Right,Enter node tools/tv_glass.mjs
 */
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
// AW_TV_URL is the whole address, ?tv=1 included. AW_BASE is honoured too
// because it is the obvious guess and getting it wrong is SILENT: the harness
// happily measures PRODUCTION while you believe you are testing your edit,
// which cost a round of "the fix did nothing" on 2026-09-12.
const SITE = process.env.AW_TV_URL
  || (process.env.AW_BASE
        ? process.env.AW_BASE.replace(/\/+$/, "") + "/?tv=1"
        : "https://archivewatch.org/?tv=1");
if (!process.env.AW_TV_URL && !process.env.AW_BASE) {
  console.log("note: no AW_TV_URL/AW_BASE — measuring the LIVE site, not your working tree.");
}
const ROUTE = process.argv[2] || "#/";
const PRESSES = Number(process.argv[3] || 12);
const OUT = process.env.AW_TV_OUT || path.join(os.tmpdir(), "aw-tv-glass");
const PORT = 9223 + (process.pid % 200);

// Tizen and webOS send these; Chrome needs the DOM values, which are the same
// for the four directions. Enter is the remote's OK.
const KEY = {
  Up:    { windowsVirtualKeyCode: 38, key: "ArrowUp",    code: "ArrowUp" },
  Down:  { windowsVirtualKeyCode: 40, key: "ArrowDown",  code: "ArrowDown" },
  Left:  { windowsVirtualKeyCode: 37, key: "ArrowLeft",  code: "ArrowLeft" },
  Right: { windowsVirtualKeyCode: 39, key: "ArrowRight", code: "ArrowRight" },
  Enter: { windowsVirtualKeyCode: 13, key: "Enter",      code: "Enter" },
  Back:  { windowsVirtualKeyCode: 8,  key: "Backspace",  code: "Backspace" },
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });

  const chrome = spawn(CHROME, [
    "--headless=new",
    `--remote-debugging-port=${PORT}`,
    // A REAL TV viewport. --force-device-scale-factor=1 matters: without it
    // the shot comes back at the host's dpr and every size reads doubled.
    "--window-size=1920,1080",
    "--force-device-scale-factor=1",
    "--hide-scrollbars",
    "--no-first-run", "--no-default-browser-check",
    `--user-data-dir=${path.join(OUT, "profile")}`,
    "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe"] });

  let ws, target;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(250);
    try {
      const list = await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json());
      target = list.find((t) => t.type === "page");
    } catch { /* not up yet */ }
  }
  if (!target) { chrome.kill(); throw new Error("Chrome did not expose a page target"); }

  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });

  let id = 0;
  const pending = new Map();
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
  };
  const cdp = (method, params = {}) =>
    new Promise((res) => { const n = ++id; pending.set(n, res);
      ws.send(JSON.stringify({ id: n, method, params })); });

  await cdp("Page.enable");
  await cdp("Runtime.enable");

  const evaluate = async (expr) => {
    const r = await cdp("Runtime.evaluate",
      { expression: expr, returnByValue: true, awaitPromise: true });
    return r?.result?.value;
  };

  await cdp("Page.navigate", { url: SITE + ROUTE });
  await sleep(9000);                      // catalog fetch + hydrate, not a guess:
                                          // shots taken earlier show an empty shell

  const shot = async (name) => {
    const r = await cdp("Page.captureScreenshot", { format: "png" });
    fs.writeFileSync(path.join(OUT, name + ".png"), Buffer.from(r.data, "base64"));
  };

  // What has focus, and CAN THE VIEWER SEE IT — the question a screenshot alone
  // cannot answer and the one the owner's "the screen doesn't follow the
  // rectangle" report is about.
  const probe = `(() => {
    const a = document.activeElement;
    if (!a || a === document.body) return { focused: null };
    const b = a.getBoundingClientRect();
    const sc = document.querySelector('main');
    return {
      focused: (a.textContent || '').trim().slice(0, 40) || a.tagName,
      tag: a.tagName, cls: (a.className || '').slice(0, 30),
      top: Math.round(b.top), bottom: Math.round(b.bottom),
      inView: b.top >= 0 && b.bottom <= innerHeight,
      offBy: b.top < 0 ? Math.round(b.top)
           : b.bottom > innerHeight ? Math.round(b.bottom - innerHeight) : 0,
      scrollTop: sc ? Math.round(sc.scrollTop) : null,
      viewport: innerWidth + 'x' + innerHeight,
    };
  })()`;

  const keys = (process.env.AW_KEYS || Array(PRESSES).fill("Down").join(","))
    .split(",").map((s) => s.trim()).filter(Boolean);

  const log = [];
  await shot("00-start");
  log.push({ step: 0, key: "(start)", ...(await evaluate(probe)) });

  for (let i = 0; i < keys.length; i++) {
    const k = KEY[keys[i]];
    if (!k) continue;
    await cdp("Input.dispatchKeyEvent", { type: "keyDown", ...k });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", ...k });
    await sleep(500);
    const state = await evaluate(probe);
    log.push({ step: i + 1, key: keys[i], ...state });
    await shot(String(i + 1).padStart(2, "0") + "-" + keys[i]);
  }

  fs.writeFileSync(path.join(OUT, "trace.json"), JSON.stringify(log, null, 1));
  ws.close(); chrome.kill();

  // The verdict, in the terminal, so a failure does not need the images opened.
  console.log(`viewport ${log[0].viewport}   shots -> ${OUT}`);
  console.log("step key    focused                                   top  inView");
  for (const r of log) {
    console.log(`${String(r.step).padStart(4)} ${r.key.padEnd(6)} ` +
      `${String(r.focused ?? "—").padEnd(41)} ${String(r.top ?? "").padStart(5)}  ` +
      `${r.focused == null ? "" : (r.inView ? "yes" : `NO (off by ${r.offBy})`)}`);
  }
  const blind = log.filter((r) => r.focused && !r.inView);
  console.log(blind.length
    ? `\n!! ${blind.length} of ${log.length} presses left focus OFF SCREEN`
    : `\nevery focused element was visible`);
}

main().catch((e) => { console.error(e.message); process.exit(1); });
