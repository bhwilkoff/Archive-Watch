/**
 * test_view_transition.mjs — showView must swap the SAME way with or without
 * the View Transitions API.
 *
 * The failure this guards is subtle: startViewTransition snapshots the page,
 * runs the callback, then snapshots again. Any DOM update left OUTSIDE the
 * callback gets no transition and can be captured half-applied. And on a
 * browser without the API — or for a viewer who has asked for reduced motion —
 * the swap must still happen at all.
 *
 * showView is read out of the SHIPPED watch.js so the test cannot drift.
 */
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const m = src.match(/function showView\(name\) \{[\s\S]*?\n  \}/);
if (!m) { console.error('FAIL: showView not found in watch.js'); process.exit(1); }

// Minimal DOM: the views, the nav, and a scrollable main.
function makeEnv({ hasAPI, reducedMotion }) {
  const state = { hidden: {}, current: {}, scrollTop: 99, transitions: 0 };
  const VIEWS = ['home', 'browse', 'search', 'item'];
  for (const v of VIEWS) state.hidden[`view-${v}`] = false;
  const $ = (id) => id === 'main'
    ? { set scrollTop(v) { state.scrollTop = v; }, get scrollTop() { return state.scrollTop; } }
    : { set hidden(v) { state.hidden[id] = v; }, get hidden() { return state.hidden[id]; } };
  const document = {
    querySelectorAll: () => [{ dataset: { nav: 'home' },
      setAttribute: (k, v) => { state.current[k] = v; } }],
  };
  if (hasAPI) document.startViewTransition = (cb) => { state.transitions++; cb(); return {}; };
  const matchMedia = (q) => ({ matches: reducedMotion && q.includes('reduce') });
  const fn = new Function('VIEWS', '$', 'document', 'matchMedia',
    `${m[0]}; return showView;`)(VIEWS, $, document, matchMedia);
  return { fn, state };
}

const cases = [
  ['modern browser: swap happens', { hasAPI: true, reducedMotion: false }, 1],
  ['no API (older browser): swap still happens', { hasAPI: false, reducedMotion: false }, 0],
  ['reduced motion: swap happens, NO transition', { hasAPI: true, reducedMotion: true }, 0],
];

let pass = 0, fail = 0;
const check = (n, ok) => { ok ? pass++ : fail++; console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${n}`); };

for (const [name, env, wantTransitions] of cases) {
  const { fn, state } = makeEnv(env);
  fn('browse');
  const swapped = state.hidden['view-home'] === true
    && state.hidden['view-browse'] === false
    && state.scrollTop === 0
    && state.current['aria-current'] === 'false';
  check(`${name}`, swapped && state.transitions === wantTransitions);
  if (!swapped) console.log('        state:', JSON.stringify(state));
}

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail === 0 ? 0 : 1);
