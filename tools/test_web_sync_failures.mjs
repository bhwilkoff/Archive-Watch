#!/usr/bin/env node
// The two web sync islands under failure (web audit, 2026-10-28).
//
// Google Drive (js/drivesync.js): a read that FAILED is not an empty cloud.
// findFile and pull used to answer a 5xx with "no file" / "no data", and the
// merge then wrote this browser's state over the phone's — a second file, or a
// PATCH of a blob that never saw the cloud's. A failed push must not read
// "Synced". And playback no longer asks for a sync every ten seconds: one a
// minute at most, one at a time.
//
// CloudKit (js/cloudkitsync.js): Apple's PlaylistEntry REQUIRES createdAt and
// modifiedAt, so a list missing either must not be written without them; a
// long history must encode; and Apple's script loads only for someone signed
// in here or on the Library page.
//
// Every block carries a control that must come out the other way.
import { readFileSync } from 'node:fs';

const read = f => readFileSync(new URL(`../${f}`, import.meta.url), 'utf8');
const driveSrc = read('js/drivesync.js');
const ckSrc = read('js/cloudkitsync.js');

let fails = 0, n = 0;
const check = (ok, msg) => { n++; console.log((ok ? '  ok   ' : '  FAIL ') + msg); if (!ok) fails++; };
const tick = () => new Promise(r => setTimeout(r, 5));

function fakeDB(seed = {}) {
  const st = { favorites: new Map(), playlists: new Map(), channels: new Map(), progress: new Map(), tombstones: new Map() };
  for (const p of seed.playlists || []) st.playlists.set(p.id, structuredClone(p));
  for (const p of seed.progress || []) st.progress.set(p.id, structuredClone(p));
  const all = m => [...m.values()].map(v => structuredClone(v));
  return {
    st,
    tombstones: async () => all(st.tombstones),
    putTombstone: async (kind, id, at) => { st.tombstones.set(kind + ':' + id, { kind, id, at }); },
    favorites: async () => all(st.favorites),
    saveFavorite: async f => { st.favorites.set(f.id, f); },
    removeFavoriteRaw: async id => { st.favorites.delete(id); },
    playlists: async () => all(st.playlists),
    savePlaylistRaw: async p => { st.playlists.set(p.id, structuredClone(p)); },
    removePlaylistRaw: async id => { st.playlists.delete(id); },
    userChannels: async () => all(st.channels),
    saveUserChannel: async c => { st.channels.set(c.id, c); },
    removeUserChannelRaw: async id => { st.channels.delete(id); },
    progress: async () => all(st.progress),
    putProgressRaw: async p => { st.progress.set(p.id, p); },
    removeProgressRaw: async id => { st.progress.delete(id); },
  };
}

const el = () => ({
  children: [], hidden: false, innerHTML: '', textContent: '', className: '', type: '', id: '',
  onclick: null, setAttribute() {}, append(...c) { this.children.push(...c); },
  replaceChildren(...c) { this.children = c; },
});
const textOf = e => (e ? (e.textContent || '') + (e.children || []).map(textOf).join('') : '');
const findClick = e => (e.onclick ? e : (e.children || []).map(findClick).find(Boolean));

// --- Google Drive ----------------------------------------------------------
/** Load drivesync with a scripted Drive. `answers` maps a request kind to a
 *  status: list, pull, patch, create. */
function loadDrive(src, answers, files = [{ id: 'f1' }]) {
  const store = new Map();
  const localStorage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
  const log = [];
  const fetch = async (url, opts = {}) => {
    const m = opts.method || 'GET';
    const kind = /\/drive\/v3\/files\?spaces/.test(url) ? 'list'
      : /alt=media/.test(url) ? 'pull' : m === 'PATCH' ? 'patch' : 'create';
    log.push(kind);
    const status = answers[kind] ?? 200;
    const body = kind === 'list' ? { files } : kind === 'pull' ? { v: 2, favorites: [] } : {};
    return { ok: status < 400, status, json: async () => body };
  };
  const tc = { requestAccessToken() { tc.callback({ access_token: 'tok' }); } };
  const window = {
    AW_GOOGLE_CLIENT_ID: 'test-client',
    google: { accounts: { oauth2: { initTokenClient: () => tc } } },
    addEventListener() {}, dispatchEvent() {},
  };
  const document = { createElement: el, addEventListener() {}, hidden: false, head: { appendChild() {} } };
  const timers = [];
  const setTimeoutFake = (fn, ms) => { timers.push({ fn, ms }); return timers.length; };
  new Function('window', 'document', 'localStorage', 'setInterval', 'setTimeout', 'CustomEvent', 'google', 'fetch', 'console', src)(
    window, document, localStorage, () => 1, setTimeoutFake, class {}, window.google, fetch, { warn() {} });
  const host = el();
  window.AWDriveSync.init(fakeDB(), host);
  return { S: window.AWDriveSync, host, log, timers };
}

async function signInAndSync(env) {
  findClick(env.host).onclick();     // "Sign in with Google": the one interactive sync
  for (let i = 0; i < 20; i++) await tick();
}

async function driveCases(src) {
  const out = [];
  const c = (ok, msg) => out.push([!!ok, msg]);
  {
    const env = loadDrive(src, { list: 500 });
    await signInAndSync(env);
    c(!env.log.includes('patch') && !env.log.includes('create'),
      `a file list that failed (500) writes nothing to Drive (requests: ${env.log})`);
    c(!/Synced/.test(textOf(env.host)) && /Sync failed/.test(textOf(env.host)), '...and says it failed');
  }
  {
    const env = loadDrive(src, { pull: 503 });
    await signInAndSync(env);
    c(!env.log.includes('patch') && !env.log.includes('create'),
      `a cloud copy that could not be read is never overwritten (requests: ${env.log})`);
  }
  {
    const env = loadDrive(src, { patch: 500 });
    await signInAndSync(env);
    c(env.log.includes('patch') && !/Synced/.test(textOf(env.host)),
      `a push that failed never reads "Synced" (bar: "${textOf(env.host).trim()}")`);
  }
  {
    const env = loadDrive(src, {}, []);
    await signInAndSync(env);
    c(env.log.join() === 'list,create', `control: an OK EMPTY list is "no file", and one is created (${env.log})`);
  }
  {
    const env = loadDrive(src, {});
    await signInAndSync(env);
    c(env.log.join() === 'list,pull,patch' && /Synced/.test(textOf(env.host)),
      `control: a sync that worked reads "Synced" (${env.log})`);
    // The player used to nudge every 10 s; a nudge inside the minute waits.
    const before = env.log.length;
    env.S.nudge(); env.S.nudge(); env.S.nudge();
    await tick();
    c(env.log.length === before && env.timers.length === 1 && env.timers[0].ms >= 59_000,
      `three nudges inside a minute are one sync, a minute on (requests ${env.log.length - before}, timers ${env.timers.length})`);
    env.timers[0].fn();
    for (let i = 0; i < 10; i++) await tick();
    c(env.log.length === before + 3, '...which then runs');
  }
  return out;
}

const cur = await driveCases(driveSrc);
for (const [ok, msg] of cur) check(ok, msg);
// Control: a Drive client that reads failures as "nothing there" and pushes
// regardless — the shape these checks exist to catch.
const lenient = driveSrc
  .replace("if (!r.ok) throw new Error(`Drive ${r.status}`);\n    const d = await r.json();", 'const d = r.ok ? await r.json() : { files: [] };')
  .replace("if (!r.ok) throw new Error(`Drive ${r.status}`);\n    return r.json();", 'return r.ok ? r.json() : null;');
if (lenient === driveSrc) check(false, 'control: the failure handling was not found to remove');
else {
  const ctl = await driveCases(lenient);
  const caught = ctl.filter(r => !r[0]).length;
  check(caught > 0, `control: a client that reads a failure as empty fails ${caught}/${ctl.length} checks`);
}

// --- CloudKit ---------------------------------------------------------------
function loadCK(src, { signedIn = true, hash = '#/', records = [], db = fakeDB(), withCK = true } = {}) {
  const store = new Map(signedIn ? [['aw_cksync', '1']] : []);
  const localStorage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
  let saved = null, scripts = 0;
  const hashHandlers = [];
  let done;
  const finished = new Promise(r => { done = r; });
  const window = {
    AW_CLOUDKIT_API_TOKEN: 'test-token',
    location: { hash },
    AWDriveSync: null,
    addEventListener: (t, fn) => { if (t === 'hashchange') hashHandlers.push(fn); },
    dispatchEvent() { done(); },
  };
  if (withCK) window.CloudKit = {
    configure() {},
    getDefaultContainer: () => ({
      setUpAuth: async () => ({ userRecordName: 'me' }),
      whenUserSignsIn: () => new Promise(() => {}),
      whenUserSignsOut: () => new Promise(() => {}),
      privateCloudDatabase: {
        fetchRecords: async () => ({ records, hasErrors: false }),
        saveRecords: async recs => { saved = recs; return { hasErrors: false }; },
      },
    }),
  };
  const document = { createElement: el, addEventListener() {}, hidden: false,
                     head: { appendChild: () => { scripts++; } } };
  const args = ['window', 'document', 'localStorage', 'setInterval', 'CustomEvent', 'console'];
  const vals = [window, document, localStorage, () => 1, class { constructor(t) { this.type = t; } }, { warn() {} }];
  new Function(...args, 'setTimeout', driveSrc)(...vals, setTimeout);
  new Function(...args, 'TextDecoder', 'TextEncoder', 'atob', 'btoa', src)(...vals, TextDecoder, TextEncoder, atob, btoa);
  window.AWDriveSync.init(db, null);     // the shared merge reads its DB
  window.AWCloudKitSync.init(db, el());
  return { window, finished, saved: () => saved, scripts: () => scripts, hashHandlers, db };
}
const dec = b64 => JSON.parse(Buffer.from(b64, 'base64').toString('utf8'));
const payload = (env, name) => dec(env.saved().find(r => r.recordName === name).fields.payload.value);

async function ckCases(src) {
  const out = [];
  const c = (ok, msg) => out.push([!!ok, msg]);
  const T = 1_760_000_000_000;
  {
    // A list made on the web before createdAt was written, and a long history.
    const progress = Array.from({ length: 30000 }, (_, i) => ({ id: 'film-number-' + i, position: 1, duration: 2, at: T, firstAt: T, plays: 1 }));
    const db = fakeDB({ playlists: [{ id: 'imp', name: 'Shared', archiveIDs: ['a'], modifiedAt: T }], progress });
    const env = loadCK(src, { db });
    await Promise.race([env.finished, new Promise(r => setTimeout(r, 1500))]);
    const pl = env.saved() && payload(env, 'playlists').find(p => p.id === 'imp');
    c(pl && pl.createdAt === T / 1000 && pl.modifiedAt === T / 1000,
      `a list with no createdAt is written with one (got ${pl && pl.createdAt})`);
    const pr = env.saved() && payload(env, 'progress');
    c(pr && pr.length === 30000, `a 30,000-title history encodes and is written (got ${pr && pr.length})`);
  }
  {
    const records = [{ recordName: 'playlists', fields: { payload: { value: Buffer.from(JSON.stringify([
      { id: 'x', name: 'Old', archiveIDs: [], modifiedAt: T / 1000 }])).toString('base64') } } }];
    const env = loadCK(src, { records });
    await Promise.race([env.finished, new Promise(r => setTimeout(r, 500))]);
    const got = env.db.st.playlists.get('x');
    c(got && got.createdAt === T, `a cloud list with no createdAt arrives dated by its modifiedAt (got ${got && got.createdAt})`);
  }
  {
    const env = loadCK(src, { signedIn: false, hash: '#/', withCK: false });
    await tick();
    const onHome = env.scripts();
    env.window.location.hash = '#/library';
    env.hashHandlers.forEach(h => h());
    await tick();
    c(onHome === 0 && env.scripts() === 1,
      `Apple's script loads on the Library, not on every visit (home ${onHome}, library ${env.scripts()})`);
    const signed = loadCK(src, { signedIn: true, hash: '#/', withCK: false });
    await tick();
    c(signed.scripts() === 1, 'control: someone signed in here gets it at once');
  }
  return out;
}

const ck = await ckCases(ckSrc);
for (const [ok, msg] of ck) check(ok, msg);
// Control: the writer before this change — createdAt passed through as is,
// and the whole payload spread into one fromCharCode call.
const oldCK = ckSrc
  .replace(/createdAt: sec\(p\.createdAt \|\| p\.modifiedAt \|\| Date\.now\(\)\),/, 'createdAt: sec(p.createdAt),')
  .replace(/const enc = \(arr\) => \{[\s\S]*?\n  \};/, 'const enc = (arr) => btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(arr))));');
if (oldCK === ckSrc) check(false, 'control: the CloudKit fixes were not found to undo');
else {
  const ctl = await ckCases(oldCK);
  const caught = ctl.filter(r => !r[0]).length;
  check(caught > 0, `control: the old CloudKit writer fails ${caught}/${ctl.length} checks`);
}

console.log(`web sync failures: ${n - fails}/${n} pass`);
process.exit(fails ? 1 : 0);
