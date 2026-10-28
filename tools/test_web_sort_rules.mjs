#!/usr/bin/env node
// The web's sort rules are the apps' (owner, 2026-10-27): television grids
// default to A–Z and every grid kind remembers its own choice; Top Rated sorts
// on the pipeline's rank (Decision 171), and an older index falls back to the
// raw rating, where a series counts with no votes; playlists default to
// "My Order", where a list with no place comes FIRST (newest first) and the
// arranged lists follow ascending (Playlist.inMyOrder in UserState.swift).
//
// SortRules is read out of the SHIPPED watch.js, so the test cannot drift.
// Each rule carries a control: a plausible wrong rule must give a different
// answer on the same fixture, or the fixture proves nothing.
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const m = src.match(/\/\/ --- sort rules ---\n([\s\S]*?)\n\s*\/\/ --- end sort rules ---/);
if (!m) { console.error('FAIL: the sort rules block was not found in watch.js'); process.exit(1); }
const SortRules = new Function(`${m[1]}; return SortRules;`)();

let fails = 0, n = 0;
const check = (ok, msg) => { n++; console.log((ok ? '  ok   ' : '  FAIL ') + msg); if (!ok) fails++; };
const ids = a => a.map(x => x.id || x[0]).join(',');

// --- grid kinds and defaults
check(SortRules.surface('tv-series') === 'tv' && SortRules.surface('tv-special') === 'tv', 'series and specials are one kind: tv');
check(SortRules.surface('') === 'browse' && SortRules.surface('animation') === 'browse', 'every film grid is browse');
check(SortRules.defaultSort('tv') === 'az' && SortRules.defaultSort('browse') === 'pop', 'tv defaults to A–Z, films to Popular');
check(SortRules.key('tv') === 'browseSort.tv', 'the memory key is browseSort.<surface>');
check(SortRules.BROWSE.includes('za'), 'Z–A is offered');

// --- rows: [id, title, year, type, poster, pro, search, backdrop, playable, doc, rating10, votes]
const row = (id, title, year, type, rating, votes) => [id, title, year, type, null, 0, '', null, 1, 0, rating, votes];
const rows = [
  row('f-few', 'Few Votes', 1950, 'feature-film', 95, 12),     // a 9.5 from twelve people
  row('f-good', 'Good Film', 1940, 'feature-film', 80, 5000),
  row('s-b', 'Bonanza', null, 'tv-series', 80, null),          // TVmaze 8.0, no votes
  row('s-a', 'Adam-12', null, 'tv-series', 80, null),
  row('s-none', 'Zorro', null, 'tv-series', null, null),
];
const rated = SortRules.sortRows(rows, 'rate');
check(ids(rated) === 'f-good,s-a,s-b,f-few,s-none',
  `Top Rated: votes first, then title; a series counts with no votes (got ${ids(rated)})`);
// control: the old rule (100-vote floor for every row) sinks the series
const oldScore = r => ((r[11] || 0) >= 100 ? (r[10] || 0) : -1);
const old = [...rows].sort((a, b) => oldScore(b) - oldScore(a));
check(ids(old) !== ids(rated), 'control: the 100-vote floor for series orders the fixture differently');

// --- Decision 171: the index's column 19 is the pipeline's rank; Top Rated
// sorts on it whenever the index carries it.
const ranked = (id, title, rating, votes, rank) => {
  const r = row(id, title, 1950, 'feature-film', rating, votes);
  while (r.length < 19) r.push(null);
  r.push(rank);
  return r;
};
const byRank = [
  ranked('vierte', 'Der Vierte kommt nicht', 92, 13, 31),   // a 9.2 from thirteen votes
  ranked('harakiri', 'Harakiri', 86, 90669, 257),
  ranked('soundie', 'Soundie', null, null, 121),           // archive.org reviewers only
  ranked('plain', 'Unrated', null, null, null),
  ranked('tie-b', 'B Tie', 70, 900, 100), ranked('tie-a', 'A Tie', 70, 900, 100),
];
const rk = SortRules.sortRows(byRank, 'rate');
check(ids(rk) === 'harakiri,soundie,tie-a,tie-b,vierte,plain',
  `Top Rated follows the rank: a big crowd's 8.6 leads a tiny crowd's 9.2, unrated last (got ${ids(rk)})`);
const byRating = [...byRank].sort((a, b) => (b[10] || -1) - (a[10] || -1));
check(ids(byRating) !== ids(rk), 'control: sorting on rating10 orders the fixture differently');

const twins = [row('b2', 'Beau Geste', 1939, 'feature-film'), row('b1', 'Beau Geste', 1926, 'silent-film'),
               row('a', 'all quiet', 1930, 'feature-film'), row('z', 'Zoo', 1950, 'feature-film')];
check(ids(SortRules.sortRows(twins, 'az')) === 'a,b1,b2,z', 'A–Z ignores case and ties by year');
check(ids(SortRules.sortRows(twins, 'za')) === 'z,b1,b2,a', 'Z–A reverses the title and still ties by year');
check(SortRules.sortRows(twins, 'pop') === twins, 'Popular keeps the index order');

// --- playlists: My Order
const lists = [
  { id: 'arr2', name: 'b', sortIndex: 1, createdAt: 100 },
  { id: 'old-new', name: 'C', createdAt: 50 },
  { id: 'arr1', name: 'a', sortIndex: 0, createdAt: 10 },
  { id: 'new-new', name: 'd', createdAt: 900 },
  { id: 'arr1b', name: 'e', sortIndex: 0, createdAt: 20 },
];
const mine = SortRules.inMyOrder(lists);
check(ids(mine) === 'new-new,old-new,arr1b,arr1,arr2',
  `My Order: unplaced first, newest first; then placed ascending, ties newest first (got ${ids(mine)})`);
check(ids(lists) === 'arr2,old-new,arr1,new-new,arr1b', 'inMyOrder does not reorder its input');
// control: placed-first would be the obvious wrong rule
const wrong = [...lists].sort((a, b) => (a.sortIndex ?? 1e9) - (b.sortIndex ?? 1e9));
check(ids(wrong) !== ids(mine), 'control: placed-first orders the fixture differently');
check(ids(SortRules.sortLists(lists, 'myOrder')) === ids(mine), 'myOrder is the list default rule');
check(ids(SortRules.sortLists(lists, 'alphabetical')) === 'arr1,arr2,old-new,new-new,arr1b', 'A–Z by name, case-blind');
check(ids(SortRules.sortLists(lists, 'reverseAlphabetical')) === 'arr1b,new-new,old-new,arr2,arr1', 'Z–A by name');
check(ids(SortRules.sortLists(lists, 'newest')) === 'new-new,arr2,old-new,arr1b,arr1', 'Newest by created');
check(SortRules.PLAYLIST.map(o => o[1]).join('|') === 'My Order|A–Z|Z–A|Newest|Oldest', 'the five playlist sorts, the apps\' words');
check(SortRules.listKey === 'playlistSort.lists' && SortRules.contentsKey('p1') === 'playlistSort.p1', 'the apps\' memory keys');

// --- arrange stamps only what moved
const arr = [{ id: 'x', sortIndex: 0, modifiedAt: 1 }, { id: 'y', modifiedAt: 1 }, { id: 'z', sortIndex: 2, modifiedAt: 1 }];
const changed = SortRules.arrange(arr, 777);
check(ids(changed) === 'y' && arr[1].sortIndex === 1 && arr[1].modifiedAt === 777, 'arrange places and stamps only the list that moved');
check(arr[0].modifiedAt === 1 && arr[2].modifiedAt === 1, 'an unmoved list keeps its modifiedAt (sync carries only the move)');

// --- a playlist's films
const films = [row('m1', 'Metropolis', 1927), row('m2', 'all about eve', 1950), row('m3', 'Nameless', null)];
check(ids(SortRules.sortFilms(films, 'myOrder')) === 'm1,m2,m3', 'My Order is the list\'s own order');
check(ids(SortRules.sortFilms(films, 'alphabetical')) === 'm2,m1,m3', 'films A–Z');
check(ids(SortRules.sortFilms(films, 'newest')) === 'm2,m1,m3', 'Newest by year, undated last');
check(ids(SortRules.sortFilms(films, 'oldest')) === 'm1,m2,m3', 'Oldest by year, undated last');
const pairs = films.map(r => ['alias-' + r[0], r]);
check(SortRules.sortFilms(pairs, 'alphabetical', p => p[1]).map(p => p[0]).join(',') === 'alias-m2,alias-m1,alias-m3',
  'films sort with the id the list holds attached');

console.log(`web sort rules: ${n - fails}/${n} pass`);
process.exit(fails ? 1 : 0);
