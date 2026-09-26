// An archive.org address on archivewatch.org lands on the right thing
// (WEB-DESIGN §4.3b, 2026-09-26): a film we keep opens its page, a merged-away
// upload opens the film it became, and anything else says "Not in Archive
// Watch" with a link back. Runs the SHIPPED watch.js in its own headless
// Chrome, against a site root (default: this checkout, served locally).
//
//   node tools/test_web_archive_address.mjs [siteRoot]
import { spawn } from "node:child_process";

const SITE = process.argv[2] || "http://127.0.0.1:18767/";
const PORT = 9335;
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (label, ok, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
};

let server = null;
if (SITE.startsWith("http://127.0.0.1:18767")) {
  server = spawn("python3", ["-m", "http.server", "18767", "--bind", "127.0.0.1"],
    { stdio: "ignore", cwd: new URL("..", import.meta.url).pathname });
  await sleep(1500);
}
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`,
  "--no-first-run", `--user-data-dir=/tmp/aw-addr-${process.pid}`, "about:blank"],
  { stdio: "ignore" });

try {
  let target;
  for (let i = 0; i < 80 && !target; i++) {
    await sleep(250);
    try {
      target = (await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json()))
        .find((x) => x.type === "page");
    } catch { /* not up yet */ }
  }
  if (!target) throw new Error("could not start Chrome");
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let id = 0; const pending = new Map();
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
  };
  const cdp = (method, params = {}) => new Promise((res) => {
    const n = ++id; pending.set(n, res); ws.send(JSON.stringify({ id: n, method, params }));
  });
  const evaluate = async (expr) =>
    (await cdp("Runtime.evaluate", { expression: expr, returnByValue: true }))?.result?.value;
  await cdp("Page.enable"); await cdp("Runtime.enable");

  const STATE = `({ hash: location.hash,
    title: document.getElementById('details-title')?.textContent || '',
    link: document.getElementById('details-archive')?.hidden === false
          ? document.getElementById('details-archive').href : null })`;
  async function visit(path, wantHash, why) {
    await cdp("Page.navigate", { url: `${SITE}#/details/${path}` });
    let s = null;
    for (let i = 0; i < 60; i++) {
      await sleep(500);
      s = await evaluate(STATE);
      if (s && (s.hash !== `#/details/${path}` || s.title)) break;
    }
    return s;
  }

  // 1. A merged-away upload opens the film it became (aliases.json).
  let s = await visit("the-scarecrow");
  check("a merged-away upload opens its survivor", s?.hash === "#/item/TheScarecrow1920", JSON.stringify(s));
  // 2. A film we keep opens itself.
  s = await visit("TheScarecrow1920");
  check("a kept film opens its own page", s?.hash === "#/item/TheScarecrow1920", JSON.stringify(s));
  // 3. Anything else says so and links back.
  s = await visit("aw-not-a-real-item-9f3");
  check('an unknown item says "Not in Archive Watch"', s?.title === "Not in Archive Watch", JSON.stringify(s));
  check("and links to it on archive.org",
        s?.link === "https://archive.org/details/aw-not-a-real-item-9f3", String(s?.link));
  // 4. A pasted link in search goes the same way.
  await cdp("Page.navigate", { url: `${SITE}#/search?q=${encodeURIComponent("https://archive.org/details/the-scarecrow")}` });
  let h = null;
  for (let i = 0; i < 60; i++) {
    await sleep(500);
    h = await evaluate("location.hash");
    if (h === "#/item/TheScarecrow1920") break;
  }
  check("a pasted archive.org link in search opens the film", h === "#/item/TheScarecrow1920", String(h));
} catch (e) {
  console.log("FAIL", e.message); failures++;
} finally {
  chrome.kill();
  if (server) server.kill();
}
console.log(failures === 0 ? "PASS web archive addresses" : `FAILED (${failures})`);
process.exit(failures === 0 ? 0 : 1);
