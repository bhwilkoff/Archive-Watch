/* The counter's shape() decides what the dashboard can say. Two bugs lived here
   together and each made the other invisible:

   1. watch.js sent `location.pathname`, which on a HASH router is "/" on every
      surface — so every route change was recorded as a view of the home page.
   2. shape() knew nothing about the viewer's own surfaces, so had the client
      sent them, they would all have collapsed into "/other" anyway.

   And a VISIT is not a ROUTE VIEW: one page load that walks six surfaces is one
   visit and seven beacons. Summing them reports navigation as audience.

     node tools/test_counter_shape.mjs
*/
import fs from "node:fs";

let pass = 0, fail = 0;
const check = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  ok ? pass++ : fail++;
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `  (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`}`);
};

// Load the REAL shape() out of the worker rather than a copy of it.
const src = fs.readFileSync("worker/src/index.js", "utf8");
const start = src.indexOf("const ALLOW");
const end = src.indexOf("const cors");
const shape = new Function(`${src.slice(start, end)}\nreturn shape;`)();

check("a page load is its own key, never a path", shape("(visit)"), "(visit)");
check("root", shape("/"), "/");
check("a film shapes to /item, never the film id", shape("/item/metropolis"), "/item");
check("a series likewise", shape("/series/adam-12-1968"), "/series");

// The hash routes the client now sends.
for (const [route, want] of [
  ["/browse", "/browse"], ["/browse?type=film", "/browse"],
  ["/search", "/search"], ["/library", "/library"],
  ["/channels", "/channels"], ["/surprise", "/surprise"],
  ["/collections", "/collections"], ["/collection/feature_films", "/collection"],
  ["/cartoons", "/cartoons"], ["/playlist/abc", "/playlist"], ["/about", "/about"],
]) check(`hash route ${route}`, shape(route), want);

check("an unknown path is /other, never itself", shape("/whatever/1/2"), "/other");
check("...and the key space stays bounded", shape("/item/../../etc/passwd"), "/other");

// The client half: it must send the ROUTE, and must record a visit exactly once.
const watch = fs.readFileSync("watch.js", "utf8");
const beacon = watch.slice(watch.indexOf("function awCount"));
check("the client sends the hash route, not pathname",
      /location\.hash/.test(beacon) && /function awRoute/.test(beacon), true);
check("...and hashchange still records the route",
      /hashchange".*awCount\(awRoute\(\)\)/s.test(beacon), true);

/* THE PACKAGED APPS MUST NOT BEACON. privacy.html: "The apps collect nothing
   at all. The website keeps one aggregate counter." The Tizen .wgt and webOS
   .ipk ship this same watch.js, so without a guard the promise is false — and
   CORS is not the guard, because a simple POST is sent even when the response
   is blocked. */
{
  const beaconSrc = watch.slice(watch.indexOf("function awOnWebsite"),
                                watch.indexOf("addEventListener(\"hashchange\"", watch.indexOf("function awOnWebsite")));
  check("the beacon is gated on running as a website",
        /\/\^https\?:\$\/\.test\(location\.protocol\)/.test(beaconSrc), true);
  check("...and awCount refuses when it is not",
        /if \(!AW_BEACON \|\| !awOnWebsite\(\)\) return;/.test(beaconSrc), true);

  // The staged package is the thing that actually ships — assert the guard is
  // in the copy that goes INTO the .wgt, not only in the source tree.
  const staged = "tv/tizen/app/watch.js";
  if (fs.existsSync(staged)) {
    const pkg = fs.readFileSync(staged, "utf8");
    check("...and the guard is present in the STAGED Tizen package",
          /!awOnWebsite\(\)/.test(pkg), true);
  } else {
    console.log("  --   tizen not staged, skipping the packaged-copy check");
  }
}

/* ONE BEACON PER VISIT (owner, 2026-11-23: "We should not be anywhere close to
   the limits on any plan if we are using them correctly"). Every hashchange used
   to send its own request — ~2.7 Worker requests and D1 upserts per visit, 40%
   of the shared free account's daily requests on Nov 18. The client now counts
   in memory and sends once, when the page is hidden or left. Run the REAL
   counter section of watch.js in a DOM shim. */
import vm from "node:vm";
const J = (s) => { try { return JSON.parse(s); } catch { return {}; } };
function runCounter({ hash = "#/browse", sendBeaconOk = true, withSendBeacon = true, protocol = "https:" } = {}) {
  const sent = [];
  const listeners = {}, docListeners = {};
  const location = { protocol, pathname: "/", hash };
  const document = { visibilityState: "visible",
    addEventListener: (t, f) => (docListeners[t] ||= []).push(f) };
  const navigator = {};
  if (withSendBeacon) navigator.sendBeacon = (url, body) => { sent.push({ via: "sendBeacon", url, body: String(body) }); return sendBeaconOk; };
  const ctx = {
    location, document, navigator, console,
    addEventListener: (t, f) => (listeners[t] ||= []).push(f),
    fetch: (url, opts = {}) => { sent.push({ via: "fetch", url, body: opts.body ? String(opts.body) : "" }); return Promise.resolve({}); },
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(watch.slice(watch.indexOf("/* ── page-view counter")), ctx);
  const fire = (t) => (listeners[t] || []).forEach((f) => f({}));
  const hide = () => { document.visibilityState = "hidden"; (docListeners.visibilitychange || []).forEach((f) => f({})); };
  return { ctx, location, sent, fire, hide };
}
{
  const h = runCounter();
  for (const r of ["#/item/metropolis", "#/browse?type=film", "#/item/nosferatu", "#/search?q=x", "#/item/metropolis"]) {
    h.location.hash = r; h.fire("hashchange");
  }
  check("five hashchanges send nothing yet", h.sent.length, 0);
  h.fire("pagehide");
  check("...five hashchanges plus pagehide send exactly ONE beacon", h.sent.length, 1);
  const b = h.sent[0] ? J(h.sent[0].body) : {};
  check("...through sendBeacon", h.sent[0] && h.sent[0].via, "sendBeacon");
  check("...the visit counted once", b.visit, 1);
  check("...routes by surface, no film id in a route key", b.routes, { "/browse": 2, "/item": 3, "/search": 1 });
  check("...the titles the old beacon recorded, aggregated",
        b.titles, [{ p: "/item/metropolis", n: 2 }, { p: "/item/nosferatu", n: 1 }]);
  check("...and the body carries no other field", Object.keys(b).sort(), ["routes", "titles", "visit"]);
  h.fire("pagehide");
  check("a second pagehide with nothing new sends nothing", h.sent.length, 1);
  h.location.hash = "#/library"; h.fire("hashchange"); h.hide();
  const b2 = h.sent[1] ? J(h.sent[1].body) : {};
  check("visibilitychange to hidden flushes what came after", h.sent.length, 2);
  check("...and does not count the visit twice", [b2.visit, b2.routes], [0, { "/library": 1 }]);
}
{
  const h = runCounter();
  h.ctx.awCount("/item/metropolis", "play");
  h.fire("pagehide");
  const b = h.sent[0] ? J(h.sent[0].body) : {};
  check("a played film keeps its kind", b.titles, [{ p: "/item/metropolis", k: "play", n: 1 }]);
}
{
  const h = runCounter();
  for (let i = 0; i < 25; i++) { h.location.hash = `#/item/film${i}`; h.fire("hashchange"); }
  const sizes = h.sent.map((s) => (J(s.body).titles || []).length);
  check("titles cap at 20 per beacon, flushing early rather than dropping", sizes, [20]);
  h.fire("pagehide");
  check("...the rest go with the next", h.sent.map((s) => (J(s.body).titles || []).length), [20, 5]);
}
{
  const h = runCounter({ hash: "#/list/abc123blob" });
  h.fire("pagehide");
  check("a shared playlist never reaches the beacon", /abc123blob/.test(h.sent[0] ? h.sent[0].body : "x"), false);
}
{
  const h = runCounter({ sendBeaconOk: false });
  h.fire("pagehide");
  check("a refused sendBeacon falls back to one keepalive fetch", h.sent.map((s) => s.via), ["sendBeacon", "fetch"]);
}
{
  const p = runCounter({ protocol: "file:" });
  p.fire("hashchange"); p.fire("pagehide");
  check("a packaged app (file://) never beacons", p.sent.length, 0);
}

/* THE WORKER: accepts the batched body, keeps the legacy single-route shape,
   writes with ONE env.DB.batch, one upsert per distinct row. */
const worker = (await import("../worker/src/index.js")).default;
function stubDB() {
  const db = { batches: [], runs: [] };
  db.prepare = (sql) => ({ sql, bind: (...args) => ({ sql, args, run: async () => { db.runs.push({ sql, args }); return {}; } }) });
  db.batch = async (stmts) => { db.batches.push(stmts.map((s) => ({ sql: s.sql, args: s.args }))); return []; };
  return db;
}
const rows = (db) => [...db.batches.flat(), ...db.runs].map(({ sql, args }) =>
  [/INTO views/.test(sql) ? "views" : "titles", ...args.slice(1)]).sort((a, b) => JSON.stringify(a) < JSON.stringify(b) ? -1 : 1);
{
  const db = stubDB();
  const body = JSON.stringify({ visit: 1, routes: { "/item": 3, "/browse?type=film": 1, "/browse": 1, "(visit)": 9 },
    titles: [{ p: "/item/Metropolis", n: 2 }, { p: "/item/Metropolis", n: 1 }, { p: "/item/nosferatu", k: "play" }, { p: "/list/x" }] });
  const r = await worker.fetch(new Request("https://w.example/beacon/v2", { method: "POST", body, headers: { "Content-Type": "text/plain" } }), { DB: db });
  check("batched body answers 204", r.status, 204);
  check("...in ONE env.DB.batch", [db.batches.length, db.runs.length], [1, 0]);
  check("...duplicate routes aggregated, a route cannot forge a visit, ids keep their case", rows(db), [
    ["titles", "Metropolis", "open", 3], ["titles", "nosferatu", "play", 1],
    ["views", "(visit)", 1], ["views", "/browse", 2], ["views", "/item", 3],
  ]);
}
{
  const db = stubDB();
  const body = JSON.stringify({ visit: 0, routes: { "/item": 99999 } });
  await worker.fetch(new Request("https://w.example/beacon", { method: "POST", body }), { DB: db });
  check("a batch to /beacon works too, and counts are capped", rows(db), [["views", "/item", 500]]);
}
{
  const db = stubDB();
  await worker.fetch(new Request("https://w.example/beacon?p=%2Fitem%2Fmetropolis&k=play", { method: "POST" }), { DB: db });
  check("legacy single-route beacon still counts route and title", rows(db), [["titles", "metropolis", "play", 1], ["views", "/item", 1]]);
  const db2 = stubDB();
  await worker.fetch(new Request("https://w.example/beacon?p=(visit)", { method: "POST" }), { DB: db2 });
  check("...and a legacy visit", rows(db2), [["views", "(visit)", 1]]);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
