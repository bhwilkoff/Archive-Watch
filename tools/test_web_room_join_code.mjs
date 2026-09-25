// Can a BROWSER guest join a room by TYPING its code? (SHAREPLAY §11.10:
// "web — the link already works; a code field on /together/".) The owner
// looked for it on 2026-09-25 and it did not exist.
//
// Written after two readings from a tools-driven Chrome tab turned out to be
// the room seeking an unloaded <video>: that tab is HIDDEN and Chrome defers
// media there, while the room keeps moving currentTime. So this runs its own
// headless Chrome (visible to itself, muted, autoplay allowed) and counts a
// position as playback ONLY with readyState >= 2 and a buffered range that
// covers it.
//
//   node tools/test_web_room_join_code.mjs [film] [siteRoot]
//
// Library -> "Join a room" -> the code field; a MISHEARD, lower-case code
// ("cal1"-style) must still join and play; a wrong-length code is refused
// with a sentence; control: a bare #/together/<code> link also joins.
// Always ends the room. Silent: --mute-audio.
import { spawn } from "node:child_process";
const FILM = process.argv[2] || "that-certain-thing-1928";
const SITE = process.argv[3] || "https://archivewatch.org/";
const WORKER = "https://archivewatch-pulse.benwilkoff.workers.dev/together";
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9334;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (label, ok, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
};

try {
  await fetch(`http://127.0.0.1:${PORT}/json/version`, { signal: AbortSignal.timeout(800) });
  console.log(`FAIL a browser is already on port ${PORT}: pkill -f "remote-debugging-port=${PORT}"`);
  process.exit(1);
} catch { /* free */ }

const room = await fetch(`${WORKER}/new`, {
  method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ filmID: FILM, position: 300, rate: 1, paused: false }),
}).then((r) => r.json());
if (!room.code) { console.log("FAIL could not create a room", room); process.exit(1); }
const host = (body) => fetch(`${WORKER}/${room.code}`, {
  method: "POST",
  headers: { "content-type": "application/json", "x-aw-host-key": room.hostKey },
  body: JSON.stringify(body),
}).then((r) => r.json());
const expected = async () => {
  const s = await fetch(`${WORKER}/${room.code}`).then((r) => r.json());
  return s.paused ? s.position : s.position + (s.serverTime - s.atServerTime) * s.rate;
};
console.log(`room ${room.code} on ${FILM}`);

const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`,
  "--mute-audio", "--autoplay-policy=no-user-gesture-required",
  "--window-size=1280,800", "--no-first-run",
  `--user-data-dir=/tmp/aw-room-${process.pid}`, "about:blank"],
  { stdio: ["ignore", "ignore", "pipe"] });

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
    const n = ++id; pending.set(n, res);
    ws.send(JSON.stringify({ id: n, method, params }));
  });
  const evaluate = async (expr) =>
    (await cdp("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true }))
      ?.result?.value;
  const text = (id) => evaluate(`document.getElementById('${id}')?.textContent || ''`);
  const waitFor = async (expr, ms = 20000) => {
    for (let t = 0; t < ms; t += 250) { if (await evaluate(expr)) return true; await sleep(250); }
    return false;
  };

  await cdp("Page.navigate", { url: `${SITE}#/library` });
  const link = await waitFor(`!!document.querySelector('#view-library a[href="#/together"]')`);
  check("Library carries a Join a room entry", link);
  await evaluate(`document.querySelector('#view-library a[href="#/together"]').click()`);
  const form = await waitFor(`!document.getElementById('together-join').hidden`);
  check("it opens the code field", form, await evaluate("location.hash"));

  // Refused: three characters.
  await evaluate(`document.getElementById('together-code').value = 'ab1';
    document.getElementById('together-join').requestSubmit()`);
  await sleep(300);
  check("a short code is refused with a sentence",
        /four letters or numbers/.test(await text("together-error")), await text("together-error"));

  // The code as a guest would type what they heard: lower case, with a
  // spoken "oh" / "ell" standing in for 0 / 1 wherever the code has one.
  const heard = room.code.toLowerCase().replace(/0/g, "o").replace(/1/g, "l");
  await evaluate(`document.getElementById('together-code').value = '${heard}';
    document.getElementById('together-join').requestSubmit()`);
  const joined = await waitFor(`/with the room/.test(document.getElementById('together-note').textContent)`);
  check(`typing "${heard}" joins room ${room.code}`, joined, await text("together-note") || await text("together-error"));
  check("the field hides once joined", await evaluate(`document.getElementById('together-join').hidden`));
  const playing = await waitFor(`(() => { const v = document.querySelector('video');
    return v && v.readyState >= 2 && !v.paused && v.currentTime > 0; })()`, 45000);
  check("and the film plays", playing,
        JSON.stringify(await evaluate(`(() => { const v = document.querySelector('video'); return v && {rs: v.readyState, t: v.currentTime, p: v.paused}; })()`)));

  // Control: a bare-code LINK reaches the same room without the form.
  await cdp("Page.navigate", { url: `${SITE}#/home` });
  await sleep(1000);
  await cdp("Page.navigate", { url: `${SITE}#/together/${room.code}` });
  check("CONTROL: a bare #/together/<code> link joins too",
        await waitFor(`/with the room/.test(document.getElementById('together-note').textContent)`));
} catch (e) {
  console.log("FAIL", e.message); failures++;
} finally {
  await host({ end: true }).catch(() => {});
  chrome.kill();
}
console.log(failures === 0 ? "PASS web room join by code" : `FAILED (${failures})`);
process.exit(failures === 0 ? 0 : 1);
