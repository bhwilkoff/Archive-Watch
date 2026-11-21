#!/usr/bin/env node
// Channels on the web, 2026-11-21 (Apple's 1.48.0): the viewer's channel order
// and a channel that plays a playlist.
//   1. ChannelOrder.arrange is Apple's GuideChannel.arranged: named ids first,
//      in the order's order, every other channel after where it stood.
//   2. Scheduler.loop is Apple's ChannelScheduler.loop: the playlist in its
//      order on one clock from 2026-01-01 UTC, so the program at any instant
//      is the one a continuous packing from that epoch puts there, whichever
//      day's guide is asked.
//   3. Both sync writers carry a channel's playlistID and the channelOrder
//      record (Drive: {ids, at ms}; CloudKit: [{ids, at seconds}]), and a
//      missing CloudKit record is fine.
// The rules are read out of the SHIPPED watch.js / js/*.js. Each part has a
// control (a plausible wrong rule, or the carry cut out) that must fail.
import { readFileSync } from 'node:fs';
process.env.TZ = 'America/Denver';

const root = new URL('..', import.meta.url);
const read = f => readFileSync(new URL(f, root), 'utf8');
let fails = 0, n = 0;
const check = (ok, msg) => { n++; console.log((ok ? '  ok   ' : '  FAIL ') + msg); if (!ok) fails++; };

const src = read('watch.js');
const m = src.match(/\/\/ --- channel rules ---\n([\s\S]*?)\n\s*\/\/ --- end channel rules ---/);
if (!m) { console.error('FAIL: the channel rules block was not found in watch.js'); process.exit(1); }
const { Scheduler, ChannelOrder } = new Function(`${m[1]}; return { Scheduler, ChannelOrder };`)();

// ---- 1. arrange
const chans = ['user-a', 'user-b', 'drama', 'comedy', 'noir', 'tv'].map(id => ({ id }));
const ids = a => a.map(c => c.id).join(',');
const got = ids(ChannelOrder.arrange(chans, ['noir', 'user-b', 'gone']));
check(got === 'noir,user-b,user-a,drama,comedy,tv', `named first in order, the rest in place, unknown ids ignored (got ${got})`);
check(ids(ChannelOrder.arrange(chans, [])) === ids(chans), 'no order: the default order');
const wrong = [...chans].sort((a, b) => ['noir', 'user-b'].indexOf(b.id) - ['noir', 'user-b'].indexOf(a.id));
check(ids(wrong) !== got, 'control: a sort that reverses the unnamed differs on this fixture');
const stored = ChannelOrder.toStore(['comedy', 'drama'], ['user-zz', 'drama', 'comedy']);
check(stored.join(',') === 'comedy,drama,user-zz', `a stored id this device does not show is kept (got ${stored})`);

// ---- 2. playlist loop
const EPOCH = 1767225600e3;
const progs = [['a', 'A', 600, null, 'short-film'], ['b', 'B', 3000, null, 'documentary'],
               ['c', 'C', null, null, 'feature-film'], ['d', 'D', 50, null, 'animation']];
const secs = p => (p[2] && p[2] > 120 ? Math.min(p[2], 10800) : ({ 'feature-film': 5400, 'documentary': 3000 }[p[4]] || 720));
function reference(t) {           // pack from the epoch, program after program
  let cur = EPOCH, i = 0;
  for (;;) {
    const end = cur + secs(progs[i]) * 1000;
    if (t < end + 120e3) return { id: progs[i][0], start: cur, end };
    cur = end + 120e3; i = (i + 1) % progs.length;
  }
}
const airing = (slots, t) => slots.find(s => s.start <= t && t < s.end + 120e3);
let agree = 0, inOrder = true, total = 0;
for (const iso of ['2026-11-21T14:03:00Z', '2026-11-22T12:59:00Z', '2027-03-14T09:30:00Z', '2026-01-01T03:00:00Z']) {
  const now = new Date(iso);
  const slots = Scheduler.loop(progs, now);
  for (let k = 1; k < slots.length; k++) {
    const a = progs.findIndex(p => p === slots[k - 1].prog), b = progs.findIndex(p => p === slots[k].prog);
    if (b !== (a + 1) % progs.length) inOrder = false;
  }
  for (const dt of [0, 3600e3, 7 * 3600e3, 20 * 3600e3]) {
    total++;
    const t = now.getTime() + dt, s = airing(slots, t), r = reference(t);
    if (s && s.prog[0] === r.id && s.start === r.start) agree++;
  }
}
check(agree === total, `the program at each instant is the epoch packing's (${agree}/${total})`);
check(inOrder, 'slots follow the playlist order, looping');
// The same instant from two days' guides: one clock, not a restart per day.
const t = new Date('2026-11-22T13:30:00Z').getTime();
const s1 = airing(Scheduler.loop(progs, new Date('2026-11-21T20:00:00Z')), t);
const s2 = airing(Scheduler.loop(progs, new Date('2026-11-22T13:31:00Z')), t);
check(s1 && s2 && s1.prog[0] === s2.prog[0] && s1.start === s2.start, 'yesterday\'s guide and today\'s agree on the same instant');
check(Scheduler.loop([], new Date()).length === 0, 'an empty playlist airs nothing');
{ // control: restart the list at each broadcast day
  const anchor = Scheduler.dayAnchor(new Date('2026-11-22T13:31:00Z')).getTime();
  let cur = anchor, i = 0, found = null;
  while (cur <= t) { const end = cur + secs(progs[i]) * 1000; if (t < end + 120e3) { found = { id: progs[i][0], start: cur }; break; } cur = end + 120e3; i = (i + 1) % progs.length; }
  const r = reference(t);
  check(!(found && found.id === r.id && found.start === r.start), 'control: a list restarted each day airs something else');
}

// ---- 3. sync writers
function fakeDB(seed = {}) {
  const st = { favorites: new Map(), playlists: new Map(), channels: new Map(), progress: new Map(), tombstones: new Map(), order: seed.order || null };
  for (const c of seed.channels || []) st.channels.set(c.id, structuredClone(c));
  const all = mm => [...mm.values()].map(v => structuredClone(v));
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
    saveUserChannel: async c => { st.channels.set(c.id, structuredClone(c)); },
    removeUserChannelRaw: async id => { st.channels.delete(id); },
    channelOrder: async () => (st.order ? { key: 'order', ...structuredClone(st.order) } : null),
    saveChannelOrder: async (ids, at) => { st.order = { ids: [...ids], at }; },
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
  let saved = null, done;
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
  const vals = [window, document, localStorage, () => 1, class { constructor(x) { this.type = x; } }];
  new Function(...args, driveSrc)(...vals);
  new Function(...args, 'TextDecoder', 'TextEncoder', 'atob', 'btoa', ckSrc)(...vals, TextDecoder, TextEncoder, atob, btoa);
  return { window, finished, saved: () => saved };
}

const T0 = 1_763_000_000_000;
async function syncChecks(driveSrc, ckSrc) {
  const out = [];
  const ok = (v, msg) => out.push([!!v, msg]);

  // Drive: a pulled playlist channel keeps playlistID; a newer pulled order wins.
  {
    const db = fakeDB({ channels: [{ id: 'mine', name: 'Mine', type: null, decade: 1950, playlistID: 'pl-1', createdAt: T0 }],
                        order: { ids: ['drama'], at: T0 } });
    const env = load(driveSrc, ckSrc, []);
    env.window.AWDriveSync.init(db, null);
    const blob = JSON.parse(JSON.stringify(await env.window.AWDriveSync.merge({ v: 2,
      channels: [{ id: 'k', name: 'Noir list', contentType: null, genre: null, decade: null, playlistID: 'pl-9', createdAt: T0 }],
      channelOrder: { ids: ['user-k', 'comedy'], at: T0 + 5000 } })));
    ok(db.st.channels.get('k')?.playlistID === 'pl-9', `Drive pull keeps a channel's playlistID (got ${db.st.channels.get('k')?.playlistID})`);
    const pk = blob.channels.find(c => c.id === 'k'), pm = blob.channels.find(c => c.id === 'mine');
    ok(pk?.playlistID === 'pl-9' && pm?.playlistID === 'pl-1', 'Drive push carries playlistID for pulled and local channels');
    ok(db.st.order?.ids.join(',') === 'user-k,comedy' && db.st.order.at === T0 + 5000, 'a newer pulled order is stored here');
    ok(blob.channelOrder?.ids.join(',') === 'user-k,comedy' && blob.channelOrder.at === T0 + 5000, 'and pushed as {ids, at}');
  }
  // Drive: an older pulled order loses to this device's.
  {
    const db = fakeDB({ order: { ids: ['noir'], at: T0 + 9000 } });
    const env = load(driveSrc, ckSrc, []);
    env.window.AWDriveSync.init(db, null);
    const blob = await env.window.AWDriveSync.merge({ v: 2, channelOrder: { ids: ['tv'], at: T0 } });
    ok(db.st.order.ids.join(',') === 'noir', 'an older pulled order does not replace this device\'s');
    ok(blob.channelOrder?.ids.join(',') === 'noir' && blob.channelOrder.at === T0 + 9000, 'the local order is pushed');
  }
  // CloudKit: Apple's records in seconds; playlistID and channelOrder round-trip.
  {
    const db = fakeDB();
    const recs = [
      { recordName: 'channels', recordChangeTag: 'c', fields: { payload: { value: enc([
        { id: 'p', name: 'Keaton', createdAt: T0 / 1000, playlistID: 'pl-k' },
        { id: 'f', name: '1950s', decade: 1950, createdAt: T0 / 1000 }]) } } },
      { recordName: 'channelOrder', recordChangeTag: 'o', fields: { payload: { value: enc([{ ids: ['user-p', 'silent'], at: T0 / 1000 }]) } } },
    ];
    const env = load(driveSrc, ckSrc, recs);
    env.window.AWDriveSync.init(db, null);
    env.window.AWCloudKitSync.init(db, { hidden: true, replaceChildren() {}, append() {} });
    await Promise.race([env.finished, new Promise(r => setTimeout(r, 500))]);
    ok(db.st.channels.get('p')?.playlistID === 'pl-k', 'CloudKit pull keeps playlistID');
    ok(db.st.order?.ids.join(',') === 'user-p,silent' && db.st.order.at === T0, `CloudKit order arrives in ms (got ${JSON.stringify(db.st.order)})`);
    const saved = env.saved() || [];
    const chOut = saved.find(r => r.recordName === 'channels') && dec(saved.find(r => r.recordName === 'channels').fields.payload.value);
    ok(chOut?.find(c => c.id === 'p')?.playlistID === 'pl-k', 'CloudKit push writes playlistID back');
    ok(chOut && !('playlistID' in JSON.parse(JSON.stringify(chOut.find(c => c.id === 'f')))), 'a filter channel is written with no playlistID');
    const oRec = saved.find(r => r.recordName === 'channelOrder');
    const oOut = oRec && dec(oRec.fields.payload.value);
    ok(oOut?.length === 1 && oOut[0].ids.join(',') === 'user-p,silent' && oOut[0].at === T0 / 1000,
      `CloudKit push writes [{ids, at seconds}] (got ${JSON.stringify(oOut)})`);
    ok(oRec?.recordChangeTag === 'o', 'and saves over the fetched record');
  }
  // CloudKit: no channelOrder record yet (an older Apple build) is fine.
  {
    const db = fakeDB({ order: { ids: ['news'], at: T0 } });
    const env = load(driveSrc, ckSrc, []);
    env.window.AWDriveSync.init(db, null);
    env.window.AWCloudKitSync.init(db, { hidden: true, replaceChildren() {}, append() {} });
    await Promise.race([env.finished, new Promise(r => setTimeout(r, 500))]);
    const oRec = (env.saved() || []).find(r => r.recordName === 'channelOrder');
    ok(oRec && dec(oRec.fields.payload.value)[0]?.ids[0] === 'news', 'a missing record is created from this device\'s order');
  }
  return out;
}

for (const [v, msg] of await syncChecks(read('js/drivesync.js'), read('js/cloudkitsync.js'))) check(v, msg);

// Control: the writers that rebuild a channel from the fields they knew and
// leave the order out. The checks must catch it.
const cut = s => s
  .replace(/,\n\s*\.\.\.\(ch\.playlistID \? \{ playlistID: ch\.playlistID \} : \{\}\)/, '')
  .replace(/\n\s*\.\.\.\(order \? \{ channelOrder: \{ ids: order\.ids, at: order\.at \} \} : \{\}\),/, '')
  .replace(/\n\s*\.\.\.\(c\.playlistID \? \{ playlistID: c\.playlistID \} : \{\}\),/, '')
  .replace(/\n\s*playlistID: c\.playlistID \|\| undefined,/, '');
const cd = cut(read('js/drivesync.js')), cc = cut(read('js/cloudkitsync.js'));
if (cd === read('js/drivesync.js') || cc === read('js/cloudkitsync.js')) {
  check(false, 'control: the playlistID / channelOrder carry was not found to cut out');
} else {
  const ctl = await syncChecks(cd, cc);
  const caught = ctl.filter(r => !r[0]).length;
  check(caught > 0, `control: writers without the carry fail ${caught}/${ctl.length} checks`);
}
console.log(`web channel order + playlist channels: ${n - fails}/${n} pass`);
process.exit(fails ? 1 : 0);
