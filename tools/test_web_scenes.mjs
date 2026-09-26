// Scenes on web Detail (WEB-DESIGN §4.4e): archive.org's own frames of the
// copy that will play; a frame starts the film at its second. Control: the
// live site before the row existed shows none.
//   node tools/test_web_scenes.mjs [siteRoot]
import { spawn } from "node:child_process";
const SITE = process.argv[2] || "http://127.0.0.1:18769/";
const PORT = 9337;
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (l, ok, d = "") => { console.log(`${ok ? "PASS" : "FAIL"} ${l}${d ? ` — ${d}` : ""}`); if (!ok) failures++; };
let server = null;
if (SITE.startsWith("http://127.0.0.1:18769")) {
  server = spawn("python3", ["-m", "http.server", "18769", "--bind", "127.0.0.1"],
    { stdio: "ignore", cwd: new URL("..", import.meta.url).pathname });
  await sleep(1500);
}
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, "--mute-audio",
  "--autoplay-policy=no-user-gesture-required", "--no-first-run",
  `--user-data-dir=/tmp/aw-scenes-${process.pid}`, "about:blank"], { stdio: "ignore" });
try {
  let target;
  for (let i = 0; i < 80 && !target; i++) { await sleep(250);
    try { target = (await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json())).find((x) => x.type === "page"); } catch {} }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let n = 0; const pending = new Map();
  ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
  const cdp = (method, params = {}) => new Promise((res) => { const k = ++n; pending.set(k, res); ws.send(JSON.stringify({ id: k, method, params })); });
  const ev = async (x) => (await cdp("Runtime.evaluate", { expression: x, returnByValue: true }))?.result?.value;
  await cdp("Page.navigate", { url: `${SITE}#/item/TheGeneral720p1926` });
  let s;
  for (let i = 0; i < 60; i++) { await sleep(500);
    s = await ev(`(() => { const r = document.getElementById('item-scenes'); const b = [...document.querySelectorAll('#item-scenes-row .scene')];
      return { shown: !!r && !r.hidden, n: b.length, labels: b.map(x => x.textContent), src: b[0]?.querySelector('img').src }; })()`);
    if (s.shown) break; }
  check("Scenes shows up to 12 frames", s.shown && s.n >= 4 && s.n <= 12, JSON.stringify(s).slice(0, 300));
  check("frames are the playing copy's own", /TheGeneral720p1926\.thumbs\/TheGeneral720p_\d{6}\.jpg$/.test(s.src || ""), s.src);
  if (s.shown) {
    const label = s.labels[3];
    const want = label.split(":").map(Number).reduce((a, b) => a * 60 + b, 0);
    await ev("document.querySelectorAll('#item-scenes-row .scene')[3].click()");
    let t = 0;
    for (let i = 0; i < 40; i++) { await sleep(500); t = await ev("document.getElementById('video').currentTime"); if (t >= want) break; }
    check(`a frame starts the film at its second (${label})`, t >= want && t < want + 20, `currentTime=${t}`);
  }
} catch (e) { console.log("FAIL", e.message); failures++; }
finally { chrome.kill(); if (server) server.kill(); }
console.log(failures === 0 ? "PASS web scenes" : `FAILED (${failures})`);
process.exit(failures ? 1 : 0);
