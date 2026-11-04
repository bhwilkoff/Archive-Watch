// A playlist plays (iOS-DESIGN §4.3b), in the real viewer and the real player:
// real <video> playback of a short generated clip, so `ended` and the saved
// progress are the browser's own, not a stub's. Only the network is answered
// here: details shards, archive.org files and the counter never leave the
// machine, and a title with no file is one the fixture simply does not list.
//   node tools/test_web_playlist_player.mjs [siteRoot]
//   CHROME=/path/to/chrome   another engine (the Chromium 85 floor, Decision 162)
//   SHOTS=/some/dir          also saves what the viewer sees at 390 and 1280 px
import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const SITE = process.argv[2] || "http://127.0.0.1:18773/";
const PORT = 9341;
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const SHOTS = process.env.SHOTS || "";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (l, ok, d = "") => { console.log(`${ok ? "PASS" : "FAIL"} ${l}${d ? ` — ${d}` : ""}`); if (!ok) failures++; };

// VP8, because a Chromium snapshot has no H.264.
const tmp = mkdtempSync(join(tmpdir(), "aw-playlist-play-"));
const clipPath = join(tmp, "clip.webm");
execFileSync("ffmpeg", ["-v", "error", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=10:duration=3",
  "-c:v", "libvpx", "-b:v", "200k", clipPath]);
const clip = readFileSync(clipPath).toString("base64");

let server = null;
if (SITE.startsWith("http://127.0.0.1:18773")) {
  server = spawn("python3", ["tools/devserve.py", "18773"],
    { stdio: "ignore", cwd: new URL("..", import.meta.url).pathname });
  await sleep(1500);
}
const engine = process.env.CHROME ? ["--headless", "--no-sandbox", "--disable-gpu"] : ["--headless=new"];
const chrome = spawn(CHROME, [...engine, `--remote-debugging-port=${PORT}`, "--mute-audio", "--no-first-run",
  "--autoplay-policy=no-user-gesture-required", "--window-size=1280,900",
  `--user-data-dir=${join(tmp, "profile")}`, "about:blank"], { stdio: "ignore" });
try {
  let target;
  for (let i = 0; i < 480 && !target; i++) { await sleep(250);    // Rosetta is slow to start the old engine
    try { target = (await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json())).find((x) => x.type === "page"); } catch {} }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let n = 0; const pending = new Map(); const errors = [];
  let details = {};
  const cors = [{ name: "Access-Control-Allow-Origin", value: "*" }];
  const answer = (id, url) => {
    const json = (o) => cdp("Fetch.fulfillRequest", { requestId: id, responseCode: 200,
      responseHeaders: [...cors, { name: "Content-Type", value: "application/json" }],
      body: Buffer.from(JSON.stringify(o)).toString("base64") });
    if (/\/details\/[0-9a-f]{2}\.json/.test(url)) return json(details);
    if (/archive\.org\/download\//.test(url)) return cdp("Fetch.fulfillRequest", { requestId: id, responseCode: 200,
      responseHeaders: [...cors, { name: "Content-Type", value: "video/webm" }], body: clip });
    if (/archive\.org\/metadata\//.test(url)) return json({ files: [] });
    return cdp("Fetch.failRequest", { requestId: id, errorReason: "BlockedByClient" });
  };
  ws.onmessage = (e) => { const m = JSON.parse(e.data);
    if (m.method === "Fetch.requestPaused") answer(m.params.requestId, m.params.request.url);
    if (m.method === "Runtime.exceptionThrown") errors.push(`${m.params.exceptionDetails?.url || ""} ${m.params.exceptionDetails?.exception?.description || m.params.exceptionDetails?.text}`);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
  const cdp = (method, params = {}) => new Promise((res) => { const k = ++n; pending.set(k, res); ws.send(JSON.stringify({ id: k, method, params })); });
  const ev = async (x) => (await cdp("Runtime.evaluate", { expression: x, returnByValue: true, awaitPromise: true }))?.result?.value;
  const until = async (x, tries = 80) => { let v; for (let i = 0; i < tries; i++) { await sleep(125); v = await ev(x); if (v) return v; } return v; };
  const shot = async (name) => { if (!SHOTS) return;
    const r = await cdp("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(SHOTS, `${name}.png`), Buffer.from(r.data, "base64")); };
  const key = async (code, name) => {
    for (const type of ["rawKeyDown", "keyUp"]) await cdp("Input.dispatchKeyEvent",
      { type, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code, code: name, key: name });
    await sleep(120);
  };
  await cdp("Runtime.enable");
  await cdp("Page.enable");
  await cdp("Fetch.enable", { patterns: [{ urlPattern: "*/details/*" }, { urlPattern: "*archive.org/*" },
    { urlPattern: "*workers.dev*" }] });

  await cdp("Page.navigate", { url: `${SITE}#/library` });
  await until("!!document.getElementById('library-playlists')");
  const rows = await until(`fetch('catalog-index.json').then(r => r.json()).then(d => {
    const f = d.items.filter(r => r[3] === 'feature-film' && r[8] === 1).slice(0, 5).map(r => [r[0], r[1]]);
    const s = d.items.find(r => r[3] === 'tv-series');
    return { f, s: [s[0], s[1]] }; })`);
  check("the local index has five films and a series card", rows?.f?.length === 5 && !!rows.s, JSON.stringify(rows?.s));
  const [A, B, C, D, E] = rows.f.map((r) => r[0]);
  const title = Object.fromEntries(rows.f);
  const S = rows.s[0];
  // E is the title with no file: no shard record, and archive.org lists none.
  for (const id of [A, B, C, D]) details[id] = [`https://archive.org/download/${encodeURIComponent(id)}/film.webm`];

  const list = (id, ids) => ({ id, name: id, archiveIDs: ids, createdAt: 1000, modifiedAt: 1000 });
  const lists = [list("main", [A, S, B, C]), list("one", [A]), list("series", [S]), list("film-series", [A, S]),
    list("gap", [A, E, B]), list("empty-handed", [E]), list("two", [C, D])];
  const store = (name, mode, body) => ev(`new Promise((res, rej) => { const q = indexedDB.open('archivewatch');
    q.onsuccess = () => { const t = q.result.transaction('${name}', '${mode}'); const s = t.objectStore('${name}'); let out; ${body}
      t.oncomplete = () => { q.result.close(); res(out); }; t.onerror = () => rej(t.error); }; q.onerror = () => rej(q.error); })`);
  await store("playlists", "readwrite", `for (const p of ${JSON.stringify(lists)}) s.put(p);`);
  const markWatched = (ids) => store("progress", "readwrite",
    `s.clear(); for (const id of ${JSON.stringify(ids)}) s.put({ id, position: 100, duration: 100, title: id, at: 1, firstAt: 1, plays: 1, everDone: true });`);
  const progress = () => store("progress", "readonly", `const q2 = s.getAll(); q2.onsuccess = () => { out = q2.result; };`);
  await cdp("Page.reload");
  await until("!!document.getElementById('library-playlists')");
  await sleep(800);

  const shown = (id) => `(function () { const e = document.getElementById('${id}'); return !!e && !e.hidden && e.getBoundingClientRect().width > 0; })()`;
  const open = async (id) => {
    await ev(`location.hash = '#/playlist/${id}'`);
    await until(`document.getElementById('playlist-title').textContent === '${id}' && !document.getElementById('view-playlist').hidden`);
    await sleep(350);
  };
  const buttons = async () => [await ev(shown("playlist-play")), await ev(shown("playlist-shuffle"))].join();
  const nowTitle = () => ev("document.getElementById('player-title').textContent");
  const at = () => ev("document.getElementById('player-position').textContent");
  const playing = (t) => until(`(function () { const v = document.getElementById('video');
    return document.getElementById('player').open && document.getElementById('player-title').textContent === ${JSON.stringify(t)}
      && v.currentTime > 0.2 && !v.paused; })()`);
  const closed = () => until("!document.getElementById('player').open");
  const closePlayer = async () => { await ev("window.AWPlayer.close()"); await closed(); };

  // --- what the page offers
  await open("main");
  check("three titles and a series card: Play and Shuffle", (await buttons()) === "true,true");
  check("the words are Play and Shuffle", (await ev("document.getElementById('playlist-play').textContent + '|' + document.getElementById('playlist-shuffle').textContent")) === "Play|Shuffle");
  await shot("playlist-1280");
  await open("one");
  check("one title: Play, no Shuffle", (await buttons()) === "true,false");
  await open("film-series");
  check("a film and a series card count as one: Play, no Shuffle", (await buttons()) === "true,false");
  await open("series");
  check("a series card alone: neither", (await buttons()) === "false,false");

  // --- Play: order on screen, from the first title not watched
  await markWatched([A]);
  await open("main");
  await ev("document.getElementById('playlist-play').click()");
  check("Play starts at the first title not watched", await playing(title[B]), await nowTitle());
  check("the series card is not counted", (await at()) === "2 of 3", await at());
  check("Previous and Next are on screen", await ev(shown("player-prev")) && await ev(shown("player-next")));
  await shot("player-1280");
  await sleep(1100);
  await ev("document.getElementById('player-next').click()");
  check("Next moves on", await playing(title[C]), await nowTitle());
  check("the position follows", (await at()) === "3 of 3", await at());
  check("Next stops at the last title", await ev("document.getElementById('player-next').disabled"));
  const left = (await progress()).find((p) => p.id === B);
  check("the title left behind kept its progress", left?.position > 0.5 && left?.duration > 0, JSON.stringify(left));
  await ev("document.getElementById('player-prev').click()");
  check("Previous goes back", await playing(title[B]), await nowTitle());
  check("the position follows back", (await at()) === "2 of 3", await at());
  await ev("document.getElementById('player-prev').click()");
  check("the watched title can still be reached", await playing(title[A]), await nowTitle());
  check("Previous stops at the top", await ev("document.getElementById('player-prev').disabled"));

  // --- titles follow one another with Autoplay off, and the list stops
  check("Autoplay is off here", (await ev("localStorage.getItem('aw_autoplay')")) !== "1");
  check("the next title follows when one ends", await until(`document.getElementById('player-title').textContent === ${JSON.stringify(title[B])}`, 60), await nowTitle());
  check("and the next", await until(`document.getElementById('player-title').textContent === ${JSON.stringify(title[C])}`, 60), await nowTitle());
  check("the list stops: the player closes after the last title", await until("!document.getElementById('player').open", 60));
  check("nothing is offered over the list", await ev("document.getElementById('player-endcard').hidden"));
  const after = await progress();
  check("every title that ran is saved as watched", [A, B, C].every((id) => after.find((p) => p.id === id)?.everDone), after.map((p) => `${p.id}:${p.everDone}`).join(" "));

  // --- every title watched: from the top
  await ev("document.getElementById('playlist-play').click()");
  check("all watched: Play starts at the top", await playing(title[A]), await nowTitle());
  check("at 1 of 3", (await at()) === "1 of 3", await at());
  await closePlayer();

  // --- the viewer's sort is the order
  await markWatched([]);
  await ev("(function () { const s = document.getElementById('playlist-sort'); s.value = 'reverseAlphabetical'; s.dispatchEvent(new Event('change')); })()");
  await sleep(400);
  const za = [A, B, C].map((id) => title[id]).sort((x, y) => y.localeCompare(x, undefined, { sensitivity: "base" }));
  await ev("document.getElementById('playlist-play').click()");
  check("Z–A on screen: Play follows it", await playing(za[0]), await nowTitle());
  check("the queue is the sorted one", (await ev("window.AWPlayer.ctx().queue.map(q => q.title).join('|')")) === za.join("|"));
  await closePlayer();
  await ev("localStorage.removeItem('playlistSort.main')");
  await open("main");

  // --- Shuffle: fresh, each title once, from the start of its order
  await markWatched([A, B]);
  const orders = new Set();
  let once = true, top = true;
  for (let i = 0; i < 8; i++) {
    await ev("document.getElementById('playlist-shuffle').click()");
    await until("document.getElementById('player').open && window.AWPlayer.ctx().list");
    const ids = await ev("window.AWPlayer.ctx().queue.map(q => q.id)");
    orders.add(ids.join());
    once = once && ids.length === 3 && [A, B, C].every((id) => ids.includes(id));
    top = top && (await at()) === "1 of 3";
    await closePlayer();
  }
  check("each title once, no series card", once);
  check("each shuffle starts at 1 of 3, watched or not", top);
  check("the order is fresh", orders.size > 1, `${orders.size} orders in 8`);

  // --- Autoplay on: the list still stops; the chooser's countdown never runs
  await ev("localStorage.setItem('aw_autoplay', '1')");
  await markWatched([]);
  await open("two");
  await ev("document.getElementById('playlist-play').click()");
  check("Autoplay on: the first title plays", await playing(title[C]), await nowTitle());
  check("the next follows", await until(`document.getElementById('player-title').textContent === ${JSON.stringify(title[D])}`, 60));
  check("the list stops", await until("!document.getElementById('player').open", 60));
  await sleep(1500);
  check("and nothing starts after it", (await ev("document.getElementById('player').open")) === false && !(await ev("document.getElementById('video').getAttribute('src')")));
  await ev("localStorage.removeItem('aw_autoplay')");

  // --- a title found to have no file
  await markWatched([]);
  await open("gap");
  await ev("document.getElementById('playlist-play').click()");
  check("a list with a missing file plays", await playing(title[A]), await nowTitle());
  await ev("document.getElementById('player-next').click()");
  check("Next passes the title with no file", await playing(title[B]), await nowTitle());
  check("and the count stays true", (await at()) === "2 of 2", await at());
  await closePlayer();
  await open("empty-handed");
  await ev("document.getElementById('playlist-play').click()");
  check("nothing playable says so on the page", await until(shown("playlist-error"), 120));
  check("and no player opens", (await ev("document.getElementById('player').open")) === false);

  // --- nothing else changed: a single film keeps its end card, and no controls
  await ev(`location.hash = '#/item/${encodeURIComponent(A)}'`);
  await until("!document.getElementById('item-play').disabled && !document.getElementById('view-item').hidden");
  await ev("document.getElementById('item-play').click()");
  check("control: a single film plays", await playing(title[A]), await nowTitle());
  check("control: no Previous, Next or position", await ev("document.getElementById('player-list').hidden"));
  check("control: a single film ends on the chooser, not a closed player",
    await until("!document.getElementById('player-endcard').hidden", 60) && await ev("document.getElementById('player').open"));
  await closePlayer();

  // --- nothing new stored
  const saved = await store("playlists", "readonly", `const q2 = s.getAll(); q2.onsuccess = () => { out = q2.result; };`);
  const fields = [...new Set(saved.flatMap((p) => Object.keys(p)))].sort().join();
  check("a playlist's record has no new field", fields === "archiveIDs,createdAt,id,modifiedAt,name", fields);
  const keys = await ev("Object.keys(localStorage).filter(k => /queue|shuffle|listPlay/i.test(k)).join()");
  check("nothing about playing is kept in storage", !keys, keys);

  // --- narrow: a 390 px iframe, because headless will not lay out under ~500
  await markWatched([]);
  await cdp("Page.navigate", { url: `${SITE}tools/narrow-frame-host` });
  await sleep(500);
  await ev(`(function () { document.documentElement.style.background = '#333'; document.body.innerHTML = '';
    const f = document.createElement('iframe'); f.id = 'f'; f.src = '${SITE}#/playlist/main';
    f.style.cssText = 'width:390px;height:844px;border:0'; document.body.appendChild(f); })()`);
  const inFrame = (x) => `(function () { const w = document.getElementById('f').contentWindow, document_ = w.document; return (function (document, window) { return ${x}; })(document_, w); })()`;
  await until(inFrame("document.getElementById('playlist-title') && document.getElementById('playlist-title').textContent === 'main'"));
  await sleep(600);
  const fits = (id) => inFrame(`(function () { const r = document.getElementById('${id}').getBoundingClientRect(); return r.width > 0 && r.left >= 0 && r.right <= 390; })()`);
  check("390: Play fits", await ev(await fits("playlist-play")));
  check("390: Shuffle fits", await ev(await fits("playlist-shuffle")));
  check("390: the page does not scroll sideways", await ev(inFrame("document.documentElement.scrollWidth <= 390")));
  await shot("playlist-390");
  await ev(inFrame("document.getElementById('playlist-play').click()"));
  await until(inFrame("document.getElementById('player').open && document.getElementById('player-position').textContent === '1 of 3'"));
  await sleep(500);
  check("390: Previous, position and Next fit", await ev(await fits("player-prev")) && await ev(await fits("player-position")) && await ev(await fits("player-next")));
  await shot("player-390");
  await ev(inFrame("window.AWPlayer.close()"));

  // --- the television: same queue, the remote's verbs
  await markWatched([A]);
  // Arrive from another page, as a viewer does: the pursuit of the primary
  // action gives up after six seconds, and a cold index on an emulated engine
  // takes longer than that.
  await cdp("Page.navigate", { url: `${SITE}?tv=1#/library` });
  await until("document.querySelectorAll('#library-playlists .playlist-card').length > 0", 400);
  await ev("location.hash = '#/playlist/main'");
  await until("document.getElementById('playlist-title').textContent === 'main' && !document.getElementById('view-playlist').hidden");
  check("TV: the layer is on", await until("document.documentElement.classList.contains('tv')"));
  check("TV: the remote arrives on Play", await until("document.activeElement && document.activeElement.id === 'playlist-play'", 60), await ev("document.activeElement && (document.activeElement.id || document.activeElement.className)"));
  await shot("playlist-tv");
  await key(13, "Enter");
  check("TV: OK on Play plays from the first title not watched", await playing(title[B]), await nowTitle());
  check("TV: the player's own bar stays away", !(await ev(shown("player-list"))));
  await key(38, "ArrowUp");
  const labels = await until("[...document.querySelectorAll('.tv-options button')].map(b => b.textContent).join('|')");
  check("TV: Player Options says Previous and Next", /(^|\|)Previous(\||$)/.test(labels) && /(^|\|)Next(\||$)/.test(labels), labels);
  check("TV: no episode words and no Autoplay row in a playlist", !/episode|Autoplay/.test(labels), labels);
  check("TV: the transport says where it is", (await ev("document.querySelector('.tv-tp-pos').textContent")) === "2 of 3", await ev("document.querySelector('.tv-tp-pos').textContent"));
  await shot("player-tv");
  await ev("[...document.querySelectorAll('.tv-options button')].find(b => b.textContent === 'Next').click()");
  check("TV: Next moves on", await playing(title[C]), await nowTitle());
  await until("document.querySelector('.tv-tp-pos').textContent === '3 of 3'");
  check("TV: the position follows", (await ev("document.querySelector('.tv-tp-pos').textContent")) === "3 of 3");
  check("TV: the list stops at its end", await until("!document.getElementById('player').open", 60));

  // CloudKit refuses this origin's token on any local run; it has nothing to do with playing.
  const real = errors.filter((e) => !/cdn\.apple-cloudkit\.com/.test(e));
  check("no script error anywhere in the run", real.length === 0, real.slice(0, 3).join(" / "));
} finally {
  chrome.kill("SIGKILL");
  if (server) server.kill();
  await sleep(300);
  rmSync(tmp, { recursive: true, force: true });
}
console.log(failures ? `${failures} FAILED` : "all passed");
process.exit(failures ? 1 : 0);
