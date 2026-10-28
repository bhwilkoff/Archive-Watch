#!/usr/bin/env node
// The web audit of 2026-10-28, held as behavior. Each block reads its code
// out of the SHIPPED file (watch.js, js/whats-new.js, sw.js), runs it against
// stand-ins, and carries a control: a plausible wrong version that must give
// a different answer on the same fixture, or the fixture proves nothing.
import { readFileSync } from 'node:fs';

const read = f => readFileSync(new URL(`../${f}`, import.meta.url), 'utf8');
const src = read('watch.js');

let fails = 0, n = 0;
const check = (ok, msg) => { n++; console.log((ok ? '  ok   ' : '  FAIL ') + msg); if (!ok) fails++; };

/** The text of `const Name = {` … its closing `\n  };`, or of a function. */
function objectText(text, name) {
  const at = text.indexOf(`const ${name} = {`);
  if (at < 0) throw new Error(`${name} not found`);
  const end = text.indexOf('\n  };', at);
  return text.slice(at + `const ${name} = `.length, end + 4);
}
function fnText(text, name) {
  const at = text.indexOf(`function ${name}(`);
  if (at < 0) throw new Error(`function ${name} not found`);
  const end = text.indexOf('\n  }', at);
  return text.slice(at, end + 4);
}
const TV_TYPES = new Function(`${/const TV_TYPES = [^\n]*/.exec(src)[0]}; return TV_TYPES;`)();

// --- B2: an uploader's HTML is parsed inert -------------------------------
{
  let liveInnerHTML = 0;
  const document = {
    createElement: () => {
      let text = '';
      return {
        set innerHTML(v) { liveInnerHTML++; text = String(v).replace(/<[^>]*>/g, ''); },
        get innerHTML() { return text.replace(/&/g, '&amp;').replace(/</g, '&lt;'); },
        set textContent(v) { text = v; }, get textContent() { return text; },
      };
    },
  };
  class DOMParser {
    parseFromString(s) { return { body: { textContent: String(s).replace(/<[^>]*>/g, '') } }; }
  }
  const evil = 'A <b>film</b><img src=x onerror="alert(1)"> about trains';
  const stripHTML = new Function('document', 'DOMParser', `${fnText(src, 'stripHTML')}; return stripHTML;`)(document, DOMParser);
  check(stripHTML(evil) === 'A film about trains' && liveInnerHTML === 0,
    'watch.js stripHTML reads text through an inert document, never innerHTML on a page element');
  const wn = read('js/whats-new.js');
  const escHtml = /const escHtml = [^\n]*/.exec(wn)[0];
  const stripTags = new Function('document', 'DOMParser',
    `${escHtml}\n${fnText(wn, 'stripTags')}; return stripTags;`)(document, DOMParser);
  liveInnerHTML = 0;
  check(stripTags(evil) === 'A film about trains' && liveInnerHTML === 0,
    'whats-new.js stripTags does the same');
  const old = new Function('document', `return function (s) { const d = document.createElement('div'); d.innerHTML = s || ''; return (d.textContent || '').trim(); };`)(document);
  liveInnerHTML = 0; old(evil);
  check(liveInnerHTML === 1, 'control: the old stripper hands the markup to a live element');
}

// --- B8 / B15: what a film surface admits --------------------------------
const Data = new Function('TV_TYPES', 'API', 'shuffle', `return ${objectText(src, 'Data')};`)(TV_TYPES, {}, a => a);
{
  // [id, title, year, type, poster, pro, search, backdrop, playable]
  const row = (id, type) => [id, id, 1960, type, 'p.jpg', 1, '', null, 1];
  const film = row('film', 'feature-film'), ad = row('ad', 'commercial'),
        ep = row('ep', 'tv-episode'), series = row('series:x', 'tv-series');
  series[8] = 0;            // as on the live index: a spine is never byte-verified
  check(Data.matchesCategory(film, '') && !Data.matchesCategory(ad, '') && !Data.matchesCategory(ep, ''),
    '"All" holds films: no commercial, no episode');
  check(Data.matchesCategory(ad, 'commercial'), '...a commercial is still there when asked for by its chip');
  check(!Data.isFilm(ep) && TV_TYPES.has('tv-episode'), 'an episode is not a film (TV_TYPES)');
  check(Data.homeShelfAdmits({ category: 'tv-series' }, series),
    'a Classic TV Home shelf admits its series cards');
  check(!Data.homeShelfAdmits({ category: 'film-noir' }, series) && Data.homeShelfAdmits({}, film),
    '...and a film shelf still refuses them');
  const oldRule = r => Data.isPro(r) && Data.isFilm(r) && Data.plays(r);
  check(!oldRule(series), 'control: the old film filter emptied the Classic TV shelves');
}

// --- B7: an episode plays on into its season -----------------------------
{
  const m = src.match(/\/\/ --- episode queue ---\n([\s\S]*?)\n\s*\/\/ --- end episode queue ---/);
  const episodeQueue = new Function(`${m[1]}; return episodeQueue;`)();
  const series = { seasons: [
    { episodes: [{ archiveID: 'a1', title: 'One', downloadURL: 'u1' }] },
    { episodes: [
      { archiveID: 'b1', title: 'B1', downloadURL: 'v1' },
      { archiveID: 'b2', title: 'B2' },                       // nothing to play
      { archiveID: 'b3', title: 'B3', downloadURL: 'v3' },
      { archiveID: 'b4', downloadURL: 'v4' },
    ] },
  ] };
  const q = episodeQueue(series, 'b3', (id, url) => (id === 'b4' ? 'chosen' : url));
  check(q && q.queue.map(e => e.id).join() === 'b1,b3,b4' && q.queueIndex === 1,
    `the season's playable episodes, starting at the one opened (got ${q && q.queue.map(e => e.id)} @ ${q && q.queueIndex})`);
  check(q && q.queue[2].url === 'chosen' && q.queue[2].title === 'b4',
    "...each on the viewer's chosen copy, untitled ones by id");
  check(episodeQueue(series, 'a1') === null && episodeQueue(series, 'zz') === null,
    'a season of one, or an id in no season, is no queue');
  check(!('queue' in { id: 'b3', url: 'v3' }), 'control: the old Play passed no queue at all');
}

// --- I2: a card's poster asks for the rendition it is drawn at -------------
{
  const window = { devicePixelRatio: 1 };
  const block = src.slice(src.indexOf('const TMDB_STEPS'), src.indexOf('/** What the browser\'s OWN'));
  const wireArt = new Function('window', `${block}; return wireArt;`)(window);
  const img = () => ({ dataset: {}, getBoundingClientRect: () => ({ width: 0 }), removeAttribute() {}, src: '' });
  const url = 'https://image.tmdb.org/t/p/w780/abc.jpg';
  const a = img(); wireArt(a, [url], null, null, 200);
  check(a.src.includes('/w342/'), `an unattached card with a known width asks for w342 (got ${a.src.slice(-14)})`);
  const b = img(); wireArt(b, [url]);
  check(b.src.includes('/w780/'), 'control: with no width it fetched the index\'s w780');
  check(src.includes('img.replaceWith(placeholderArt(row)), CARD_ART_PX)'), 'card() passes CARD_ART_PX');
}

// --- I3: archive.org metadata is read once; a failure is not kept ---------
{
  let calls = 0, failNext = false;
  const API = { fetchMetadata: async id => { calls++; if (failNext) { failNext = false; throw new Error('503'); } return { id }; } };
  const Meta = new Function('API', `return ${objectText(src, 'Meta')};`)(API);
  await Meta.get('x'); await Meta.get('x');
  check(calls === 1, 'two reads of one item are one request');
  failNext = true;
  await Meta.get('y').catch(() => {});
  await new Promise(r => setTimeout(r, 0));
  const y = await Meta.get('y').catch(() => null);
  check(y && y.id === 'y' && calls === 3, 'a failed read is forgotten and asked again');
  for (let i = 0; i < 40; i++) await Meta.get('z' + i);
  check(Meta.cache.size <= Meta.MAX, `the memo stays small (${Meta.cache.size} <= ${Meta.MAX})`);
}

// --- B12: a failed read is not cached as an empty answer ------------------
{
  // Details
  let shardCalls = 0, shardFail = true;
  const fetchShard = async () => { shardCalls++; if (shardFail) { shardFail = false; return { ok: false, status: 503 }; } return { ok: true, json: async () => ({ film: ['https://archive.org/download/film/f.mp4', 'Plot'] }) }; };
  const Details = new Function('fetch', 'PAGES_ROOT', 'Data', 'AbortSignal',
    `return ${objectText(src, 'Details')};`)(fetchShard, new URL('https://archivewatch.org/'),
    { episodeMeta: new Map() }, { timeout: () => undefined });
  const first = await Details.get('film');
  const second = await Details.get('film');
  check(first === null && second && second.synopsis === 'Plot',
    'a detail shard that failed is asked for again, not kept as {}');
  await Details.get('film');
  check(shardCalls === 2, 'control: a shard that arrived is kept (one request after it)');

  // Versions
  let metaCalls = 0, metaFail = true;
  const Meta = { get: async item => {
    metaCalls++;
    if (metaFail) { metaFail = false; throw new Error('timeout'); }
    return { files: [{ name: `${item}.mp4`, size: '90000000', height: '480', format: 'h.264' }] };
  } };
  const Aliases = { all: async () => ({ other: 'film' }) };
  const Versions = new Function('Meta', 'Aliases', 'Data', 'localStorage',
    `return ${objectText(src, 'Versions')};`)(Meta, Aliases, { episodeMeta: new Map() }, null);
  const v1 = await Versions.list('film');
  const v2 = await Versions.list('film');
  check(v2.length === 2 && v1.length < 2,
    `the copies are read again after archive.org failed (first ${v1.length}, then ${v2.length})`);
  const before = metaCalls;
  await Versions.list('film');
  check(metaCalls === before, 'control: copies that arrived are kept');
  check(JSON.stringify(await Versions.merged('film')) === '["other"]',
    'the Version button counts merged uploads from aliases.json alone');

  // Aliases
  let aliasCalls = 0;
  const fetchAlias = async () => { aliasCalls++; return aliasCalls === 1 ? { ok: false, status: 500 } : { ok: true, status: 200, json: async () => ({ old: 'new' }) }; };
  const Al = new Function('fetch', 'PAGES_ROOT', 'Data', 'AbortSignal',
    `return ${objectText(src, 'Aliases')};`)(fetchAlias, new URL('https://archivewatch.org/'),
    { byID: new Map([['new', ['new']]]) }, { timeout: () => undefined });
  const a1 = await Al.survivor('old');
  const a2 = await Al.survivor('old');
  check(a1 === null && a2 === 'new', 'aliases.json that failed is fetched again');
  let notFound = 0;
  const Al404 = new Function('fetch', 'PAGES_ROOT', 'Data', 'AbortSignal',
    `return ${objectText(src, 'Aliases')};`)(async () => { notFound++; return { ok: false, status: 404 }; },
    new URL('https://archivewatch.org/'), { byID: new Map() }, { timeout: () => undefined });
  await Al404.all(); await Al404.all();
  check(notFound === 1, 'control: a 404 (a publish before the file existed) is an answer, kept');

  // Collections
  let collCalls = 0;
  const fetchColl = async () => { collCalls++; if (collCalls === 1) throw new Error('offline'); return { ok: true, json: async () => ({ collections: [{ id: 'noir' }] }) }; };
  const Coll = new Function('fetch', 'PAGES_ROOT', 'AbortSignal', '$', 'Data', 'fillGrid',
    `return ${objectText(src, 'Collections')};`)(fetchColl, new URL('https://archivewatch.org/'),
    { timeout: () => undefined }, () => ({}), {}, () => {});
  const c1 = await Coll.loadMeta();
  const c2 = await Coll.loadMeta();
  check(c1 === null && Array.isArray(c2) && c2.length === 1,
    'collection titles that failed are asked for again (and the view can say so)');
  const errEl = { hidden: true, textContent: '' };
  new Function('$', `return ${objectText(src, 'Collections')};`)(() => errEl).failed('collections-error', null);
  check(errEl.hidden === false && /couldn't load/.test(errEl.textContent), 'a failure is a visible line');
}

// --- B16: people.json is read from the site root --------------------------
{
  let asked = null;
  const People = new Function('fetch', 'PAGES_ROOT', 'foldText',
    `return ${objectText(src, 'People')};`)(async u => { asked = String(u); return { ok: true, json: async () => ({}) }; },
    new URL('https://archivewatch.org/'), s => s);
  await People.load();
  check(asked === 'https://archivewatch.org/people.json',
    `a packaged TV app asks archivewatch.org for people.json (got ${asked})`);
  check(new URL('people.json', 'file:///app/index.html').protocol === 'file:',
    'control: the old relative URL resolves inside the package, where the file is not');
}

// --- B1: a title the catalog does not serve is not drawn from archive.org --
{
  const marker = new Error('rendered');
  const replaced = [];
  const mk = (byID, survivors) => new Function('Data', 'Aliases', 'location', '$',
    `return ${objectText(src, 'Item')};`)(
    { byID, episodesReady: Promise.resolve() },
    { survivor: async id => survivors[id] || null },
    { replace: h => replaced.push(h), set hash(h) { replaced.push(h); } },
    () => { throw marker; });
  const Item = mk(new Map([['kept', ['kept', 'Kept', 1950, 'feature-film']], ['new', ['new']]]), { merged: 'new' });
  await Item.render('hidden-by-audit');
  check(replaced.at(-1) === '#/details/hidden-by-audit', `a hidden id goes to the not-in-catalog page (got ${replaced.at(-1)})`);
  await Item.render('merged');
  check(replaced.at(-1) === '#/item/new', '...a merged-away id still goes to its survivor');
  let drew = false;
  try { await Item.render('kept'); } catch (e) { drew = e === marker; }
  check(drew, 'control: a served id renders its Detail');

  const Series = new Function('Data', 'location', '$', 'fetch', 'PAGES_ROOT', 'wireArt',
    `return ${objectText(src, 'SeriesView')};`);
  const els = {};
  const $ = id => (els[id] ||= { hidden: false, textContent: '', removeAttribute() {}, replaceChildren() {} });
  let fetched = 0;
  const sv = Series({ byID: new Map(), episodes: [['ep1', 'served-show']], episodesReady: Promise.resolve() },
    {}, $, async () => { fetched++; throw new Error('offline'); }, new URL('https://archivewatch.org/'), () => {});
  await sv.render('unknown-show');
  check(els['series-title'].textContent === 'Not in Archive Watch' && fetched === 0 && els['series-share'].hidden,
    'a series with no card and no served episodes is not drawn from its spine');
  await sv.render('served-show');
  check(fetched === 1, 'control: a series whose episodes are served still loads its spine');
}

// --- B22: the service worker keeps only good answers ----------------------
{
  const sw = read('sw.js');
  const handlers = {};
  const puts = [];
  const self = { addEventListener: (t, fn) => { handlers[t] = fn; } };
  const caches = { open: async () => ({ put: (req, res) => puts.push(res.status), match: async () => null }), match: async () => null };
  const run = async (status) => {
    let responded = null;
    const fetch = async () => ({ ok: status < 400, status, type: 'basic', clone() { return this; } });
    new Function('self', 'caches', 'fetch', sw)(self, caches, fetch);
    handlers.fetch({
      request: { url: 'https://archivewatch.org/details/ab.json', method: 'GET' },
      respondWith: p => { responded = p; }, waitUntil() {},
    });
    return responded;
  };
  await run(503);
  check(puts.length === 0, 'a 503 for a detail shard is not cached as the last-good copy');
  await run(200);
  check(puts.length === 1 && puts[0] === 200, 'control: a 200 is cached');
}

console.log(`web audit fixes: ${n - fails}/${n} pass`);
process.exit(fails ? 1 : 0);
