/* Packaged-TV-app integrity checks (webOS .ipk / Tizen .wgt).
 *
 * A packaged app runs its document from file://, not https://. That single
 * difference silently broke the entire data plane once: PAGES_ROOT was
 * `new URL('.', location.href)`, which under file:// resolves every catalog
 * fetch to a local path that isn't in the package — the app would have
 * launched to an empty catalog on every LG and Samsung TV.
 *
 * These assertions run the REAL expression out of watch.js (not a copy) so
 * they follow the source if it is edited.
 *
 * Usage: node tools/test_packaged_origin.mjs
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const watchSrc = fs.readFileSync(path.join(ROOT, 'watch.js'), 'utf8');

let pass = 0, fail = 0;
const ok = (name, got, want) => {
  const good = String(got) === String(want);
  console.log(`${good ? 'PASS' : 'FAIL'}  ${name}  (got ${got}, want ${want})`);
  good ? pass++ : fail++;
};
const truthy = (name, got) => {
  console.log(`${got ? 'PASS' : 'FAIL'}  ${name}`);
  got ? pass++ : fail++;
};

/* ---- 1. PAGES_ROOT resolution, from the real source ---- */

const m = watchSrc.match(
  /const CANONICAL_ROOT = [\s\S]*?const PAGES_ROOT = [\s\S]*?;\n/);
if (!m) {
  console.log('FAIL  could not locate the PAGES_ROOT block in watch.js');
  process.exit(1);
}
const block = m[0];

function resolveRootFor(href) {
  const protocol = new URL(href).protocol;
  const location = { href, protocol };
  // eslint-disable-next-line no-new-func
  return Function('location', 'URL', `${block}; return PAGES_ROOT.href;`)(location, URL);
}

ok('browser https root',
   resolveRootFor('https://archivewatch.org/'), 'https://archivewatch.org/');
ok('browser https deep path keeps its directory',
   resolveRootFor('https://archivewatch.org/index.html?tv=1'), 'https://archivewatch.org/');
ok('localhost dev server still same-origin',
   resolveRootFor('http://localhost:8123/index.html'), 'http://localhost:8123/');
ok('webOS package (file://) falls back to canonical',
   resolveRootFor('file:///media/developer/apps/usr/palm/applications/com.archivewatch.app/index.html'),
   'https://archivewatch.org/');
ok('Tizen package (file://) falls back to canonical',
   resolveRootFor('file:///opt/usr/apps/ArchiveWatch/res/wgt/index.html'),
   'https://archivewatch.org/');

/* A file:// root that did NOT fall back would produce a local path — this is
   the exact failure the fallback exists to prevent. */
const packagedRoot = resolveRootFor('file:///opt/usr/apps/ArchiveWatch/res/wgt/index.html');
truthy('packaged catalog URL is remote, not a local file',
       new URL('catalog-index.json', packagedRoot).protocol === 'https:');

/* ---- 2. The staged packages carry the CURRENT shared app ---- */

const SHARED = ['index.html', 'watch.js', 'watch.css', 'tv.js', 'tv.css'];
for (const pkg of ['webos', 'tizen']) {
  const dir = path.join(ROOT, 'tv', pkg, 'app');
  if (!fs.existsSync(dir)) {
    console.log(`SKIP  ${pkg} not staged (run tv/build-tv-packages.sh)`);
    continue;
  }
  // A STALE stage is not a defect: stage() does `rm -rf` before every build, so
  // an old local copy can never reach a package. tv/<pkg>/app is gitignored, so
  // this is somebody's August leftover, not something we ship. Failing on it is
  // a red X for a non-failure (Decision 107) — and it cried wolf for five weeks.
  // Only a stage that is CURRENT and still differs means stage() is broken.
  const staleness = SHARED
    .filter((f) => fs.existsSync(path.join(dir, f)))
    .filter((f) => fs.statSync(path.join(ROOT, f)).mtimeMs
                 > fs.statSync(path.join(dir, f)).mtimeMs);
  if (staleness.length) {
    console.log(`SKIP  ${pkg} staged before ${staleness.join(', ')} changed `
              + `(run tv/build-tv-packages.sh ${pkg})`);
    continue;
  }
  for (const f of SHARED) {
    const a = fs.readFileSync(path.join(ROOT, f));
    const b = fs.existsSync(path.join(dir, f)) ? fs.readFileSync(path.join(dir, f)) : null;
    truthy(`${pkg}/${f} matches the shared source`, b && a.equals(b));
  }
  // A service worker inside a package would shadow the packaged files with a
  // stale cache and is deliberately stripped.
  truthy(`${pkg} has no packaged service worker`,
         !fs.existsSync(path.join(dir, 'sw.js')));
  // The registration lives in watch.js, not index.html — it must be guarded by
  // protocol so a packaged (file://) launch never calls register('sw.js').
  truthy(`${pkg} watch.js guards SW registration by protocol`,
         fs.readFileSync(path.join(dir, 'watch.js'), 'utf8')
           .includes('in navigator && /^https?:$/.test(location.protocol)'));
}

/* EVERY SCRIPT index.html LOADS MUST BE IN THE PACKAGE. The staged file list
   was hand-kept as `APP_JS=(js/api.js)` and went stale the moment sync shipped:
   index.html gained js/drivesync.js and js/cloudkitsync.js, the packages did
   not, and every TV launch since made two requests that 404. Nothing threw,
   because watch.js calls them as `window.AWDriveSync?.init(...)` — which is
   precisely why nobody saw it. A store's QA does look at failed resource
   loads. */
{
  const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
  const wanted = [...html.matchAll(/src="(js\/[A-Za-z0-9._-]+\.js)"/g)].map((m) => m[1]);
  truthy('index.html loads at least one js/ script', wanted.length > 0);
  for (const pkg of ['webos', 'tizen']) {
    const dir = path.join(ROOT, 'tv', pkg, 'app');
    if (!fs.existsSync(dir)) { console.log(`SKIP  ${pkg} not staged`); continue; }
    const missing = wanted.filter((f) => !fs.existsSync(path.join(dir, f)));
    truthy(`${pkg} packages every js/ script the page loads`,
           missing.length === 0, missing.join(', '));
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
