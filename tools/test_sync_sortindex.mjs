#!/usr/bin/env node
// Both web sync writers must carry a playlist's sortIndex ("My Order",
// 2026-10-27): read it, keep it, write it. A writer that drops it erases the
// viewer's arrangement on every other device the next time it pushes. A list
// that arrives keeps its OWN createdAt, never the time of this pull.
//
// Runs the shipped js/drivesync.js (Google Drive appData, Android's island)
// and js/cloudkitsync.js (Apple's AWSync records) against an in-memory
// IndexedDB stand-in and a fake CloudKit, then the SAME checks against the
// committed (HEAD) copies as a control: the control must fail, or the checks
// prove nothing.
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const root = new URL('..', import.meta.url);
const read = f => readFileSync(new URL(f, root), 'utf8');
const atHead = f => { try { return execSync(`git show HEAD:${f}`, { cwd: root, encoding: 'utf8' }); } catch { return null; } };

function fakeDB(seed = {}) {
  const st = { favorites: new Map(), playlists: new Map(), channels: new Map(), progress: new Map(), tombstones: new Map() };
  for (const p of seed.playlists || []) st.playlists.set(p.id, structuredClone(p));
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

const enc = arr => Buffer.from(JSON.stringify(arr), 'utf8').toString('base64');
const dec = b64 => JSON.parse(Buffer.from(b64, 'base64').toString('utf8'));

function load(driveSrc, ckSrc, cloudRecords) {
  const store = new Map([['aw_cksync', '1']]);
  const localStorage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
  let saved = null;
  let done;
  const finished = new Promise(r => { done = r; });
  const window = {
    AW_CLOUDKIT_API_TOKEN: 'test-token',
    addEventListener() {},
    dispatchEvent() { done(); },
    CloudKit: {
      configure() {},
      getDefaultContainer: () => ({
        setUpAuth: async () => ({ userRecordName: 'me' }),
        whenUserSignsIn: () => new Promise(() => {}),
        whenUserSignsOut: () => new Promise(() => {}),
        privateCloudDatabase: {
          fetchRecords: async () => ({ records: cloudRecords, hasErrors: false }),
          saveRecords: async recs => { saved = recs; return { hasErrors: false }; },
        },
      }),
    },
  };
  const el = () => ({ hidden: false, children: [], replaceChildren() {}, append() {}, set textContent(v) {}, set className(v) {} });
  const document = { createElement: el, addEventListener() {}, hidden: false, head: { appendChild() {} } };
  const args = ['window', 'document', 'localStorage', 'setInterval', 'CustomEvent'];
  const vals = [window, document, localStorage, () => 1, class { constructor(n) { this.type = n; } }];
  new Function(...args, driveSrc)(...vals);
  new Function(...args, 'TextDecoder', 'TextEncoder', 'atob', 'btoa', ckSrc)(
    ...vals, TextDecoder, TextEncoder, atob, btoa);
  return { window, finished, saved: () => saved };
}

const T0 = 1_760_000_000_000;   // ms
async function run(driveSrc, ckSrc) {
  const results = [];
  const check = (ok, msg) => results.push([!!ok, msg]);

  // 1. Apple -> web -> Apple: an arranged list and an unarranged one arrive
  //    from CloudKit; IndexedDB keeps the place and the list's own createdAt,
  //    and the records written back still carry the place.
  {
    const db = fakeDB();
    const recs = [{ recordName: 'playlists', recordChangeTag: 'x', fields: { payload: { value: enc([
      { id: 'a', name: 'Noir', archiveIDs: ['m1'], createdAt: T0 / 1000 - 86400, modifiedAt: T0 / 1000, sortIndex: 2 },
      { id: 'b', name: 'New', archiveIDs: [], createdAt: T0 / 1000 - 3600, modifiedAt: T0 / 1000 },
    ]) } } }];
    const env = load(driveSrc, ckSrc, recs);
    env.window.AWDriveSync.init(db, null);
    env.window.AWCloudKitSync.init(db, { hidden: true, replaceChildren() {}, append() {} });
    await Promise.race([env.finished, new Promise(r => setTimeout(r, 500))]);
    const a = db.st.playlists.get('a'), b = db.st.playlists.get('b');
    check(a && a.sortIndex === 2, `CloudKit pull keeps sortIndex (got ${a && a.sortIndex})`);
    check(a && a.createdAt === T0 - 86400_000, `CloudKit pull keeps the list's own createdAt (got ${a && a.createdAt})`);
    check(b && !('sortIndex' in b), 'a list with no place arrives with none');
    const out = env.saved() && dec(env.saved().find(r => r.recordName === 'playlists').fields.payload.value);
    const oa = out && out.find(p => p.id === 'a'), ob = out && out.find(p => p.id === 'b');
    check(oa && oa.sortIndex === 2, `CloudKit push writes sortIndex back (got ${oa && oa.sortIndex})`);
    check(ob && !('sortIndex' in ob), 'CloudKit push writes no place for a list that has none');
  }

  // 2. A web arrangement (newer) reaches Apple over an older cloud copy.
  {
    const db = fakeDB({ playlists: [{ id: 'a', name: 'Noir', archiveIDs: ['m1'], createdAt: T0 - 86400_000, modifiedAt: T0 + 60_000, sortIndex: 0 }] });
    const recs = [{ recordName: 'playlists', fields: { payload: { value: enc([
      { id: 'a', name: 'Noir', archiveIDs: ['m1'], createdAt: T0 / 1000 - 86400, modifiedAt: T0 / 1000, sortIndex: 5 },
    ]) } } }];
    const env = load(driveSrc, ckSrc, recs);
    env.window.AWDriveSync.init(db, null);
    env.window.AWCloudKitSync.init(db, { hidden: true, replaceChildren() {}, append() {} });
    await Promise.race([env.finished, new Promise(r => setTimeout(r, 500))]);
    const out = env.saved() && dec(env.saved().find(r => r.recordName === 'playlists').fields.payload.value);
    const oa = out && out.find(p => p.id === 'a');
    check(oa && oa.sortIndex === 0, `the newer web place wins in CloudKit (got ${oa && oa.sortIndex})`);
  }

  // 3. Google Drive (Android's island): the merge keeps a pulled place and
  //    the blob it returns (pushed verbatim) carries the local one.
  {
    const db = fakeDB({ playlists: [
      { id: 'w', name: 'Mine', archiveIDs: [], createdAt: T0 - 5000, modifiedAt: T0 + 9000, sortIndex: 1 },
      { id: 'k', name: 'Keep', archiveIDs: [], createdAt: T0 - 7000, modifiedAt: T0 },
    ] });
    const env = load(driveSrc, ckSrc, []);
    env.window.AWDriveSync.init(db, null);
    const blob = await env.window.AWDriveSync.merge({ v: 2, playlists: [
      { id: 'd', name: 'From Drive', archiveIDs: ['x'], createdAt: T0 - 1000, modifiedAt: T0 + 1000, sortIndex: 3 },
      { id: 'k', name: 'Keep renamed', archiveIDs: [], modifiedAt: T0 + 2000 },
    ] });
    const d = db.st.playlists.get('d'), k = db.st.playlists.get('k');
    check(d && d.sortIndex === 3, `Drive pull keeps sortIndex (got ${d && d.sortIndex})`);
    check(d && d.createdAt === T0 - 1000, 'Drive pull keeps the list\'s own createdAt');
    check(k && k.createdAt === T0 - 7000, `a pulled copy with no createdAt keeps this device's (got ${k && k.createdAt})`);
    const pushed = JSON.parse(JSON.stringify(blob)).playlists;
    const pw = pushed.find(p => p.id === 'w'), pd = pushed.find(p => p.id === 'd');
    check(pw && pw.sortIndex === 1, 'Drive push carries the local place');
    check(pd && pd.sortIndex === 3, 'Drive push carries the pulled place');
  }
  return results;
}

let fails = 0;
const cur = await run(read('js/drivesync.js'), read('js/cloudkitsync.js'));
for (const [ok, msg] of cur) { console.log((ok ? '  ok   ' : '  FAIL ') + msg); if (!ok) fails++; }

const hd = atHead('js/drivesync.js'), hc = atHead('js/cloudkitsync.js');
if (hd && hc && (hd !== read('js/drivesync.js') || hc !== read('js/cloudkitsync.js'))) {
  const ctl = await run(hd, hc);
  const caught = ctl.filter(r => !r[0]).length;
  console.log(caught ? `  ok   control: the committed writers fail ${caught}/${ctl.length} checks`
                     : '  FAIL control: the committed writers pass every check, so the checks prove nothing');
  if (!caught) fails++;
}
console.log(`sync sortIndex: ${cur.length - cur.filter(r => !r[0]).length}/${cur.length} pass`);
process.exit(fails ? 1 : 0);
