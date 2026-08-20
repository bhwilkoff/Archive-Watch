// Exercise the SHIPPED Aliases loader from watch.js — extracted verbatim, not
// re-authored, so a change to the real file is what these assertions see.
//
// The point of the lazy design is that the common case (nothing missing) costs
// NOTHING: no fetch, no 300 KB map. That is asserted first, because a lazy
// loader that quietly fetches anyway is just an eager one with extra steps.
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const start = src.indexOf('  const Aliases = {');
const end = src.indexOf('\n  };\n', start) + '\n  };\n'.length;
if (start < 0 || end <= start) { console.error('FAIL: could not extract Aliases'); process.exit(1); }
const body = src.slice(start, end);

let fetches = 0, respond = async () => ({ ok: true, json: async () => ({}) });
const rows = new Map([['survivor-id', ['survivor-id', 'The Cameraman', 1928, '', null]]]);
const Data = { byID: rows };
const PAGES_ROOT = 'https://archivewatch.org/';
const fetchStub = (...a) => { fetches++; return respond(...a); };
const AbortSignalStub = { timeout: () => null };

const make = () => {
  const f = new Function('Data', 'PAGES_ROOT', 'fetch', 'AbortSignal',
    `${body}\n return Aliases;`);
  return f(Data, PAGES_ROOT, fetchStub, AbortSignalStub);
};

let pass = 0, fail = 0;
const ok = (name, cond) => { cond ? (pass++, console.log(`  PASS ${name}`))
                                  : (fail++, console.log(`  FAIL ${name}`)); };

// 1. nothing missing -> never fetches
let A = make(); fetches = 0;
let out = await A.rows(['survivor-id']);
ok('no miss => no fetch (lazy)', fetches === 0 && out.size === 0);

// 2. a miss that HAS an alias resolves to the survivor row
A = make(); fetches = 0;
respond = async () => ({ ok: true, json: async () => ({ 'old-id': 'survivor-id' }) });
out = await A.rows(['old-id']);
ok('miss with alias => survivor row', out.get('old-id')?.[1] === 'The Cameraman');

// 3. the promise is cached — one fetch across many calls
A = make(); fetches = 0;
await A.rows(['old-id']); await A.rows(['another-miss']); await A.rows(['old-id']);
ok('map fetched once, then cached', fetches === 1);

// 4. a miss with NO alias stays missing rather than throwing
A = make();
out = await A.rows(['ghost-id']);
ok('miss with no alias => absent, no throw', out.size === 0);

// 5. an alias pointing at an id the index does not hold is NOT returned
A = make();
respond = async () => ({ ok: true, json: async () => ({ 'old-id': 'not-in-index' }) });
out = await A.rows(['old-id']);
ok('alias to a dead id => absent', out.size === 0);

// 6. 404 (a publish predating aliases.json) is an older catalog, not an error
A = make();
respond = async () => ({ ok: false, json: async () => ({}) });
out = await A.rows(['old-id']);
ok('404 => empty map, no throw', out.size === 0);

// 7. a network failure likewise degrades quietly
A = make();
respond = async () => { throw new Error('offline'); };
out = await A.rows(['old-id']);
ok('network error => empty map, no throw', out.size === 0);

// 8. survivor() returns the canonical id for the detail-route redirect
A = make();
respond = async () => ({ ok: true, json: async () => ({ 'old-id': 'survivor-id' }) });
ok('survivor() => canonical id', (await A.survivor('old-id')) === 'survivor-id');
A = make();
ok('survivor() of an unknown id => null', (await A.survivor('ghost')) === null);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
