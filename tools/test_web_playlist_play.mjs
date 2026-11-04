#!/usr/bin/env node
// What a playlist's Play and Shuffle may play (iOS-DESIGN §4.3b): series cards
// and a title whose copy failed the liveness check are skipped, a merged film
// plays once, and Play starts at the first title not watched. ListPlay is read
// out of the SHIPPED watch.js, so the test cannot drift. The wiring that a rule
// cannot show (the player's verbs reaching tv.js, the end of a list not falling
// through to the chooser) is held by reading the same files, and the behavior
// itself by tools/test_web_playlist_player.mjs in a real browser.
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const tv = readFileSync(new URL('../tv.js', import.meta.url), 'utf8');
const m = src.match(/\/\/ --- playlist play ---\n([\s\S]*?)\n\s*\/\/ --- end playlist play ---/);
if (!m) { console.error('FAIL: the playlist play block was not found in watch.js'); process.exit(1); }
const ListPlay = new Function(`${m[1]}; return ListPlay;`)();

let fails = 0, n = 0;
const check = (ok, msg) => { n++; console.log((ok ? '  ok   ' : '  FAIL ') + msg); if (!ok) fails++; };
const ids = q => q.map(x => x.id).join(',');

// rows: [id, title, year, type, poster, pro, search, backdrop, plays]
const row = (id, type, plays) => [id, id.toUpperCase(), 1930, type, null, 0, '', null, plays];
const film = row('a', 'feature-film', 1);
const episode = row('e', 'tv-episode', 1);
const special = row('sp', 'tv-special', 1);
const series = row('series:x', 'tv-series', 0);
const oldSeries = [ 'series:y', 'Y', null, 'tv-series' ];      // an index from before column 8
const dead = row('d', 'short-film', 0);
const oldFilm = ['o', 'O', 1930, 'short-film'];

check(ListPlay.playable(film), 'a film plays');
check(ListPlay.playable(episode) && ListPlay.playable(special), 'an episode and a special have files of their own');
check(ListPlay.playable(oldFilm), 'an index from before column 8 still plays');
check(!ListPlay.playable(series), 'a series card has no file');
check(!ListPlay.playable(oldSeries), 'a series card is told by its type, not only column 8');
check(!ListPlay.playable(dead), 'a title the liveness check could not reach is skipped');

const q = ListPlay.queue([['a', film], ['series:x', series], ['e', episode], ['d', dead], ['sp', special]]);
check(ids(q) === 'a,e,sp', `the queue keeps the order on screen and skips what has no file (got ${ids(q)})`);
check(q[0].title === 'A', 'an entry carries the title on screen');
const merged = ListPlay.queue([['old-upload', film], ['a', film], ['e', episode]]);
check(ids(merged) === 'a,e', `two listed ids for one film play once, under the survivor (got ${ids(merged)})`);
check(merged[0].listed === 'old-upload', 'the entry remembers the id the list holds');

check(ListPlay.startAt(q, new Set()) === 0, 'nothing watched: the top');
check(ListPlay.startAt(q, new Set(['a'])) === 1, 'the first watched is passed');
check(ListPlay.startAt(q, new Set(['e'])) === 0, 'a watched title further down does not move the start');
check(ListPlay.startAt(q, new Set(['a', 'e', 'sp'])) === 0, 'every title watched: the top');
check(ListPlay.startAt(merged, new Set(['old-upload'])) === 1, 'watched under the id the list holds counts');
check(ListPlay.startAt([], new Set()) === 0, 'an empty queue does not fall over');

// --- wiring
const onended = src.slice(src.indexOf('video.onended = async'), src.indexOf('showEndCard() {'));
check(onended.indexOf('c?.list') > -1 && onended.indexOf('c?.list') < onended.indexOf('this.showEndCard()'),
  'a list ends before the chooser, whose autoplay would carry on past it');
check(!/Prefs\.autoplay/.test(onended.slice(0, onended.indexOf('this.showEndCard()'))),
  'the queue never asks the Autoplay setting');
const noPicture = src.slice(src.indexOf('async noPicture('), src.indexOf('recover(kind) {'));
check(/persist, muted, list,/.test(noPicture), 'moving to a copy with a picture stays in the list');
const choose = src.slice(src.indexOf('async chooseCopy(v)'), src.indexOf('get autoplay() { return Prefs'));
check(/queue: c\.queue/.test(choose) && /list: c\.list/.test(choose), 'choosing a copy mid-film stays in the list');
check((src.match(/queueIndex: c\.queueIndex \+|queueIndex: queueIndex \+ 1/g) || []).length === 0,
  'one way through a queue: goTo');
check(/ctx\.list \? 'Previous'/.test(tv) && /ctx\.lineup \|\| ctx\.list \? 'Next'/.test(tv),
  "the television's options say Previous and Next in a list");
check(/AWPlayer\.position\(\)/.test(tv), 'the television shows the position');

console.log(fails ? `${fails} of ${n} FAILED` : `${n} checks passed`);
process.exit(fails ? 1 : 0);
