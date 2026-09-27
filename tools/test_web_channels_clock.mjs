// Channels on one clock (ORPHANED-FILMS #2): two viewers in far-apart time
// zones see the SAME program on air on every preset channel, and it is the one
// channel-schedule.json says is airing now; only the clock labels differ.
// Control: the live site's per-device 6 AM-local schedule, which disagrees.
//   node tools/test_web_channels_clock.mjs [siteRoot] [--control]
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
const args = process.argv.slice(2);
const CONTROL = args.includes("--control");
const SITE = args.find((a) => a.startsWith("http")) || "http://127.0.0.1:18770/";
const PORT = 9338;
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (l, ok, d = "") => { console.log(`${ok ? "PASS" : "FAIL"} ${l}${d ? ` — ${d}` : ""}`); if (!ok) failures++; };
let server = null;
if (SITE.startsWith("http://127.0.0.1:18770")) {
  server = spawn("python3", ["-m", "http.server", "18770", "--bind", "127.0.0.1"],
    { stdio: "ignore", cwd: new URL("..", import.meta.url).pathname });
  await sleep(1500);
}
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, "--mute-audio",
  "--no-first-run", `--user-data-dir=/tmp/aw-clock-${process.pid}`, "about:blank"], { stdio: "ignore" });

async function onAir(tz) {
  let target;
  for (let i = 0; i < 80 && !target; i++) { await sleep(250);
    try { target = (await fetch(`http://127.0.0.1:${PORT}/json/new?about:blank`, { method: "PUT" }).then((r) => r.json())); } catch {} }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let n = 0; const pending = new Map();
  ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
  const cdp = (method, params = {}) => new Promise((res) => { const k = ++n; pending.set(k, res); ws.send(JSON.stringify({ id: k, method, params })); });
  const ev = async (x) => (await cdp("Runtime.evaluate", { expression: x, returnByValue: true }))?.result?.value;
  await cdp("Emulation.setTimezoneOverride", { timezoneId: tz });
  await cdp("Page.navigate", { url: `${SITE}#/channels` });
  let r;
  for (let i = 0; i < 60; i++) { await sleep(500);
    r = await ev(`(() => { const rows = [...document.querySelectorAll('#epg .epg-row')];
      return { n: rows.length, tick: document.querySelector('#epg .epg-block.airing .epg-bw')?.textContent,
        air: Object.fromEntries(rows.map(x => [x.querySelector('.epg-rail span:last-child')?.textContent,
          x.querySelector('.epg-block.airing')?.title || null])) }; })()`);
    if (r?.n >= 10) break; }
  ws.close();
  return r;
}
try {
  const a = await onAir("America/Los_Angeles");
  const b = await onAir("Pacific/Kiritimati");
  const names = Object.keys(a.air).filter((k) => k in b.air);
  const same = names.filter((k) => a.air[k] === b.air[k]);
  console.log(`  LA on-air start ${a.tick} · Kiritimati on-air start ${b.tick} · ${names.length} channels`);
  if (CONTROL) {
    check("control: the per-device schedule disagrees across zones", same.length < names.length / 2,
      `${same.length}/${names.length} agree`);
  } else {
    check("the guide draws the channels", names.length >= 10, `${names.length}`);
    check("every channel airs the same program in both zones", same.length === names.length,
      names.filter((k) => a.air[k] !== b.air[k]).map((k) => `${k}: ${a.air[k]} / ${b.air[k]}`).join("; "));
    const file = JSON.parse(readFileSync(new URL("../channel-schedule.json", import.meta.url)));
    const now = Date.now();
    const want = {};
    for (const ch of file.channels) {
      for (const key of Object.keys(ch.days).sort()) { let t = ch.days[key].start * 1000;
        for (const [id, s] of ch.days[key].slots) { const e = t + s * 1000;
          if (t <= now && e > now) want[ch.title] = file.programs[id][0]; t = e + file.gap * 1000; } }
    }
    const match = Object.keys(want).filter((k) => a.air[k] === want[k] || a.air[k] === null && false);
    check("and it is the program channel-schedule.json says is on now",
      match.length === Object.keys(want).filter((k) => k in a.air && a.air[k]).length && match.length >= 10,
      Object.keys(want).filter((k) => a.air[k] !== want[k]).map((k) => `${k}: page ${a.air[k]} / file ${want[k]}`).join("; "));
    check("the same start time is labeled in each viewer's own zone", a.tick !== b.tick, `${a.tick} vs ${b.tick}`);
  }
} catch (e) { console.log("FAIL", e.message); failures++; }
finally { chrome.kill(); if (server) server.kill(); }
console.log(failures === 0 ? "PASS web channels clock" : `FAILED (${failures})`);
process.exit(failures ? 1 : 0);
