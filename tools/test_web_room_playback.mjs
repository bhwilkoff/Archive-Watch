// Does a BROWSER guest actually play a room's film in step? (SHAREPLAY §11.6)
//
// Written after two readings from a tools-driven Chrome tab turned out to be
// the room seeking an unloaded <video>: that tab is HIDDEN and Chrome defers
// media there, while the room keeps moving currentTime. So this runs its own
// headless Chrome (visible to itself, muted, autoplay allowed) and counts a
// position as playback ONLY with readyState >= 2 and a buffered range that
// covers it.
//
//   node tools/test_web_room_playback.mjs [film] [siteRoot]
//
// Creates a real room on the live Worker, opens the invite link, asserts:
//   1. the film PLAYS (readyState >= 2, buffered covers the playhead)
//   2. it is within 1 s of the room's position
//   3. a host pause stops it on the host's frame (within 0.5 s)
//   4. ending the room says "The host ended the room."
// and always ends the room. Silent: --mute-audio.
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
  await cdp("Page.enable"); await cdp("Runtime.enable");
  await cdp("Page.navigate", { url: `${SITE}#/together/${room.code}-${FILM}` });

  const STATE = `(() => { const v = document.getElementById('video'); const n = document.getElementById('player-note');
    if (!v) return null;
    let covered = false;
    for (let i = 0; i < v.buffered.length; i++)
      if (v.buffered.start(i) <= v.currentTime && v.currentTime <= v.buffered.end(i)) covered = true;
    return { t: v.currentTime, rs: v.readyState, paused: v.paused, covered,
             hidden: document.hidden, note: n && !n.hidden ? n.textContent : null }; })()`;

  // 1. It PLAYS — measured, not inferred from currentTime.
  let s = null;
  for (let i = 0; i < 90; i++) {
    await sleep(1000);
    s = await evaluate(STATE);
    if (s && s.rs >= 2 && s.covered && !s.paused) break;
  }
  check("the page is visible to itself (not the hidden-tab trap)", s && s.hidden === false, JSON.stringify(s));
  check("the film PLAYS: readyState >= 2 and the playhead is buffered",
        s && s.rs >= 2 && s.covered && !s.paused, JSON.stringify(s));
  const t0 = s?.t ?? 0;
  await sleep(4000);
  const s2 = await evaluate(STATE);
  check("and it advances on its own", s2 && s2.t - t0 > 3, `${t0.toFixed(1)} -> ${s2?.t.toFixed(1)}`);

  // 2. In step.
  await sleep(6000);
  const [e1, g1] = [await expected(), await evaluate(STATE)];
  check("within 1 s of the room", g1 && Math.abs(e1 - g1.t) < 1.0,
        `room ${e1.toFixed(2)} guest ${g1?.t.toFixed(2)}`);

  // 3. A host pause lands on the host's frame.
  const frame = await expected();
  await host({ position: frame, rate: 1, paused: true });
  await sleep(7000);
  const g2 = await evaluate(STATE);
  check("a host pause stops the guest", g2 && g2.paused, JSON.stringify(g2));
  check("on the host's frame", g2 && Math.abs(g2.t - frame) < 0.5,
        `host ${frame.toFixed(2)} guest ${g2?.t.toFixed(2)}`);

  // 4. The room ends and the guest is told.
  await host({ end: true });
  await sleep(4000);
  const g3 = await evaluate(STATE);
  check('the guest is told "The host ended the room."',
        g3 && /ended the room/.test((await evaluate("document.getElementById('together-error').textContent")) || g3.note || ""),
        JSON.stringify(g3));
} catch (e) {
  console.log("FAIL", e.message); failures++;
} finally {
  await host({ end: true }).catch(() => {});
  chrome.kill();
}
console.log(failures === 0 ? "PASS web room playback" : `FAILED (${failures})`);
process.exit(failures === 0 ? 0 : 1);
