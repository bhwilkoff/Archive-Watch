// Playlists and remembered sorts in the real viewer (owner, 2026-10-27):
// My Order is the default list order and Edit arranges it; a playlist's films
// can be sorted, arranged, removed and the list renamed; Delete asks first;
// Browse remembers its sort per kind of grid, TV starting on A–Z.
// Headless Chrome with a throwaway profile against a local server of the repo.
//   node tools/test_web_playlists.mjs [siteRoot]
import { spawn } from "node:child_process";
const SITE = process.argv[2] || "http://127.0.0.1:18771/";
const PORT = 9339;
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (l, ok, d = "") => { console.log(`${ok ? "PASS" : "FAIL"} ${l}${d ? ` — ${d}` : ""}`); if (!ok) failures++; };
let server = null;
if (SITE.startsWith("http://127.0.0.1:18771")) {
  server = spawn("python3", ["-m", "http.server", "18771", "--bind", "127.0.0.1"],
    { stdio: "ignore", cwd: new URL("..", import.meta.url).pathname });
  await sleep(1500);
}
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, "--mute-audio", "--no-first-run",
  `--user-data-dir=/tmp/aw-playlists-${process.pid}`, "about:blank"], { stdio: "ignore" });
try {
  let target;
  for (let i = 0; i < 80 && !target; i++) { await sleep(250);
    try { target = (await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json())).find((x) => x.type === "page"); } catch {} }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let n = 0; const pending = new Map(); const errors = [];
  ws.onmessage = (e) => { const m = JSON.parse(e.data);
    if (m.method === "Runtime.exceptionThrown") errors.push(m.params.exceptionDetails?.exception?.description || m.params.exceptionDetails?.text);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
  const cdp = (method, params = {}) => new Promise((res) => { const k = ++n; pending.set(k, res); ws.send(JSON.stringify({ id: k, method, params })); });
  const ev = async (x) => (await cdp("Runtime.evaluate", { expression: x, returnByValue: true, awaitPromise: true }))?.result?.value;
  const until = async (x, tries = 60) => { let v; for (let i = 0; i < tries; i++) { await sleep(250); v = await ev(x); if (v) return v; } return v; };
  await cdp("Runtime.enable");

  await cdp("Page.navigate", { url: `${SITE}#/library` });
  await until("document.querySelectorAll('#browse-grid, #home-shelves').length > 0 && !!document.getElementById('library-playlists')");
  await sleep(1500);
  // Three films the local index serves, and three lists: two never arranged
  // (newest first), one arranged at place 0.
  const ids = await until(`fetch('catalog-index.json').then(r => r.json()).then(d => d.items.filter(r => r[3] === 'feature-film' && r[2]).slice(0, 3).map(r => [r[0], r[1], r[2]]))`);
  check("the local index has films to put in a list", Array.isArray(ids) && ids.length === 3, JSON.stringify(ids));
  const seed = [
    { id: "pl-arranged", name: "Arranged", archiveIDs: ids.map(x => x[0]), createdAt: 1000, modifiedAt: 1000, sortIndex: 0 },
    { id: "pl-older", name: "Older new", archiveIDs: [], createdAt: 2000, modifiedAt: 2000 },
    { id: "pl-newest", name: "Newest new", archiveIDs: [], createdAt: 3000, modifiedAt: 3000 },
  ];
  await ev(`new Promise((res, rej) => { const q = indexedDB.open('archivewatch', 4);
    q.onupgradeneeded = () => { for (const s of ['favorites','progress','playlists','channels']) q.result.createObjectStore(s, { keyPath: 'id' }); q.result.createObjectStore('tombstones', { keyPath: 'key' }); };
    q.onsuccess = () => { const t = q.result.transaction('playlists', 'readwrite'); const s = t.objectStore('playlists');
      for (const p of ${JSON.stringify(seed)}) s.put(p); t.oncomplete = () => { q.result.close(); res(true); }; t.onerror = () => rej(t.error); };
    q.onerror = () => rej(q.error); })`);
  await cdp("Page.reload");
  const names = () => ev("[...document.querySelectorAll('#library-playlists .playlist-card strong')].map(s => s.textContent).join('|')");
  await until("document.querySelectorAll('#library-playlists .playlist-card').length === 3");
  check("My Order: unarranged lists first, newest first, then arranged", (await names()) === "Newest new|Older new|Arranged", await names());
  check("the list Sort offers the five sorts", (await ev("[...document.querySelectorAll('#library-playlists-sort option')].map(o => o.textContent).join('|')")) === "My Order|A–Z|Z–A|Newest|Oldest");

  await ev("document.getElementById('library-playlists-edit').click()");
  await until("document.querySelectorAll('#library-playlists .move-btn').length === 6");
  check("Edit draws Move up / Move down beside each list", (await ev("document.querySelectorAll('#library-playlists .move-btn').length")) === 6);
  check("the first list cannot move up", await ev("document.querySelector('#library-playlists .move-btn[data-dir=up]').disabled"));
  await ev("document.querySelector('#library-playlists .move-btn[data-dir=down]').click()");
  await until("document.querySelector('#library-playlists .playlist-card strong').textContent === 'Older new'");
  check("Move down moves the list", (await names()) === "Older new|Newest new|Arranged", await names());
  check("focus follows the moved list", (await ev("document.activeElement.getAttribute('aria-label')")) === "Move down: Newest new",
    await ev("document.activeElement.getAttribute('aria-label')"));
  const stored = await ev(`new Promise(res => { const q = indexedDB.open('archivewatch', 4); q.onsuccess = () => {
    const r = q.result.transaction('playlists').objectStore('playlists').getAll(); r.onsuccess = () => { q.result.close(); res(r.result.map(p => [p.id, p.sortIndex, p.modifiedAt > 5000])); }; }; })`);
  const by = Object.fromEntries(stored.map(x => [x[0], x]));
  check("every list now has its place", by["pl-older"][1] === 0 && by["pl-newest"][1] === 1 && by["pl-arranged"][1] === 2, JSON.stringify(stored));
  check("each list whose place changed is stamped", by["pl-older"][2] && by["pl-newest"][2] && by["pl-arranged"][2]);

  await ev("document.getElementById('library-playlists-sort').value = 'alphabetical'; document.getElementById('library-playlists-sort').dispatchEvent(new Event('change'))");
  await until("document.querySelector('#library-playlists .playlist-card strong').textContent === 'Arranged'");
  check("A–Z sorts the lists and hides Edit", (await names()) === "Arranged|Newest new|Older new" && await ev("document.getElementById('library-playlists-edit').hidden"), await names());
  check("the list sort is remembered", (await ev("localStorage.getItem('playlistSort.lists')")) === "alphabetical");

  // One playlist: sort, arrange, remove, rename, delete.
  await cdp("Page.navigate", { url: `${SITE}#/playlist/pl-arranged` });
  await until("document.querySelectorAll('#playlist-grid .card').length === 3");
  const titles = () => ev("[...document.querySelectorAll('#playlist-grid .card .t')].map(s => s.textContent).join('|')");
  check("the films show in the list's own order", (await titles()) === ids.map(x => x[1]).join("|"), await titles());
  await ev("(() => { const s = document.getElementById('playlist-sort'); s.value = 'reverseAlphabetical'; s.dispatchEvent(new Event('change')); })()");
  const za = ids.map(x => x[1]).sort((a, b) => b.localeCompare(a, undefined, { sensitivity: "base" })).join("|");
  await until(`[...document.querySelectorAll('#playlist-grid .card .t')].map(s => s.textContent).join('|') === ${JSON.stringify(za)}`);
  check("Z–A sorts the films", (await titles()) === za, await titles());
  check("the film sort is remembered per playlist", (await ev("localStorage.getItem('playlistSort.pl-arranged')")) === "reverseAlphabetical");
  await ev("document.getElementById('playlist-edit').click()");
  await until("document.querySelectorAll('#playlist-grid .card-remove').length === 3");
  check("Edit returns the films to My Order", (await titles()) === ids.map(x => x[1]).join("|") && (await ev("document.getElementById('playlist-sort').value")) === "myOrder", await titles());
  await ev("document.querySelectorAll('#playlist-grid .move-btn[data-dir=down]')[0].click()");
  const moved = [ids[1][1], ids[0][1], ids[2][1]].join("|");
  await until(`[...document.querySelectorAll('#playlist-grid .card .t')].map(s => s.textContent).join('|') === ${JSON.stringify(moved)}`);
  check("Move down moves a film", (await titles()) === moved, await titles());
  await ev("document.querySelectorAll('#playlist-grid .card-remove')[2].click()");
  await until("document.querySelectorAll('#playlist-grid .card').length === 2");
  check("× removes a film from the playlist", (await titles()) === [ids[1][1], ids[0][1]].join("|"), await titles());
  await ev("window.prompt = () => '  Renamed list  '; document.getElementById('playlist-rename').click()");
  await until("document.getElementById('playlist-title').textContent === 'Renamed list'");
  check("Rename trims and saves the name", (await ev("document.getElementById('playlist-title').textContent")) === "Renamed list");
  await ev("window.__asked = null; window.confirm = (m) => { window.__asked = m; return false; }; document.getElementById('playlist-delete').click()");
  await sleep(300);
  check("Delete asks, in the apps' words", (await ev("window.__asked")) === "Delete “Renamed list”?\n\nIt is removed from your other devices too.", JSON.stringify(await ev("window.__asked")));
  check("declining keeps the playlist", (await ev("location.hash")) === "#/playlist/pl-arranged");

  // Browse remembers per kind of grid; TV starts on A–Z.
  await ev("localStorage.removeItem('browseSort.tv'); localStorage.removeItem('browseSort.browse')");
  await cdp("Page.navigate", { url: `${SITE}#/browse?type=tv-series` });
  await until("document.getElementById('browse-grid').children.length > 0");
  check("TV starts on A–Z", (await ev("document.getElementById('browse-sort').value")) === "az");
  const first2 = await ev("[...document.querySelectorAll('#browse-grid .card .t')].slice(0, 2).map(s => s.textContent)");
  check("…and the grid is in A–Z order", first2 && first2[0].localeCompare(first2[1], undefined, { sensitivity: "base" }) <= 0, JSON.stringify(first2));
  await ev("(() => { const s = document.getElementById('browse-sort'); s.value = 'rate'; s.dispatchEvent(new Event('change')); })()");
  await sleep(500);
  check("a TV sort is remembered for TV", (await ev("localStorage.getItem('browseSort.tv')")) === "rate");
  await ev("[...document.querySelectorAll('#browse-type-chips button')].find(b => b.textContent === 'Animation').click()");
  await until("location.hash.includes('animation')");
  await sleep(500);
  check("a film grid keeps its own default", (await ev("document.getElementById('browse-sort').value")) === "pop" && !(await ev("location.hash")).includes("sort="), await ev("location.hash"));
  await cdp("Page.navigate", { url: `${SITE}#/browse?type=tv-special` });
  await sleep(800);
  check("TV Specials share TV's remembered sort", (await ev("document.getElementById('browse-sort').value")) === "rate");
  await cdp("Page.navigate", { url: `${SITE}#/browse?type=tv-series&sort=za` });
  await sleep(800);
  check("a sort in the link wins over the remembered one", (await ev("document.getElementById('browse-sort').value")) === "za");
  // CloudKit JS refuses the production token off archivewatch.org; that is
  // the environment, not the page.
  const own = errors.filter(e => !/API Token for this container/.test(e || ""));
  check("no page errors", own.length === 0, own.join(" / ").slice(0, 300));
} catch (e) { console.log("FAIL", e.message); failures++; }
finally { chrome.kill(); if (server) server.kill(); }
console.log(failures === 0 ? "PASS web playlists" : `FAILED (${failures})`);
process.exit(failures ? 1 : 0);
