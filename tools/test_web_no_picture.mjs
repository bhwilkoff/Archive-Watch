// A copy whose picture this browser cannot decode (sound over black) says so
// or moves to another H.264 copy (WEB-DESIGN §4.4d, 2026-09-26). Runs the
// SHIPPED watch.js in headless Chrome. Control: an H.264 film plays with a
// picture and no message.
//   node tools/test_web_no_picture.mjs [siteRoot]
import { spawn } from "node:child_process";

const SITE = process.argv[2] || "http://127.0.0.1:18768/";
const PORT = 9336;
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (label, ok, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
};
let server = null;
if (SITE.startsWith("http://127.0.0.1:18768")) {
  server = spawn("python3", ["-m", "http.server", "18768", "--bind", "127.0.0.1"],
    { stdio: "ignore", cwd: new URL("..", import.meta.url).pathname });
  await sleep(1500);
}
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, "--mute-audio",
  "--autoplay-policy=no-user-gesture-required", "--no-first-run",
  `--user-data-dir=/tmp/aw-nopic-${process.pid}`, "about:blank"], { stdio: "ignore" });
try {
  let target;
  for (let i = 0; i < 80 && !target; i++) {
    await sleep(250);
    try { target = (await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json())).find((x) => x.type === "page"); } catch {}
  }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let n = 0; const pending = new Map();
  ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
  const cdp = (method, params = {}) => new Promise((res) => { const k = ++n; pending.set(k, res); ws.send(JSON.stringify({ id: k, method, params })); });
  const evaluate = async (x) => (await cdp("Runtime.evaluate", { expression: x, returnByValue: true }))?.result?.value;
  const STATE = `(() => { const v = document.getElementById('video'); const e = document.getElementById('player-error');
    return { w: v.videoWidth, ready: v.readyState, src: v.currentSrc, err: e.hidden ? '' : e.textContent }; })()`;
  async function play(id) {
    await cdp("Page.navigate", { url: `${SITE}#/item/${id}` });
    for (let i = 0; i < 60; i++) { await sleep(500); if (await evaluate("!!document.getElementById('item-play') && document.getElementById('details-title')?.textContent !== ''")) break; }
    await sleep(1500);
    await evaluate("document.getElementById('item-play').click()");
    let s;
    for (let i = 0; i < 60; i++) { await sleep(500); s = await evaluate(STATE); if (s.err || s.w > 0) break; }
    return s;
  }
  let s = await play("TheGeneral720p1926");
  check("control: an H.264 film has a picture and no message", s.w > 0 && !s.err, JSON.stringify(s));
  s = await play("Silver_Fleet_The");
  check("an undecodable picture says so", /picture doesn't play in this browser/.test(s.err), JSON.stringify(s));
} catch (e) { console.log("FAIL", e.message); failures++; }
finally { chrome.kill(); if (server) server.kill(); }
console.log(failures === 0 ? "PASS web no picture" : `FAILED (${failures})`);
process.exit(failures ? 1 : 0);
