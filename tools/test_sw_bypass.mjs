/* test_sw_bypass.mjs — the service worker must not intercept the ops tools.

   The viewer's SW is registered at root scope, so it caches EVERYTHING under
   archivewatch.org unless a path is explicitly excluded. /pulse was not, and the
   dashboard served yesterday's reading with today's timestamp beside it — which
   is the one failure mode the whole tool is built to avoid, arriving from the
   cache instead of from a reader.

     node tools/test_sw_bypass.mjs
*/
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const sw = readFileSync(join(here, "..", "sw.js"), "utf8");

// Run the handler's guard clauses against a URL, exactly as written.
const guards = [...sw.matchAll(/if \(url\.pathname\.startsWith\('([^']+)'\)\) return;/g)]
  .map((m) => m[1]);

let pass = 0, fail = 0;
const check = (name, ok) => {
  ok ? pass++ : fail++;
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}`);
};
const bypassed = (path) => guards.some((g) => path.startsWith(g));

check("/pulse/ is not cached", bypassed("/pulse/"));
check("/pulse/pulse.js is not cached", bypassed("/pulse/pulse.js"));
check("/ops/pulse.json is not cached", bypassed("/ops/pulse.json"));
check("/curate stays live too", bypassed("/curate/"));
// ...and the viewer itself MUST still be cached, or the PWA stops working
// offline. A bypass that swallows the whole site is not a fix.
check("the viewer is still cached", !bypassed("/"));
check("a film page is still cached", !bypassed("/item/the_last_three"));
check("watch.js is still cached", !bypassed("/watch.js"));

// The file's own header: changing an asset without bumping SHELL freezes every
// existing install on the old copy, permanently.
const shell = /const SHELL = 'aw-root-shell-v(\d+)'/.exec(sw);
check("SHELL carries a version", !!shell);
check("SHELL is at or past v50 (the /pulse bypass)", shell && +shell[1] >= 50);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
