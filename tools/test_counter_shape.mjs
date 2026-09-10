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
check("...a visit is recorded under its own key",
      /awCount\("\(visit\)"\)/.test(beacon), true);
check("...exactly once, not on every hashchange",
      (beacon.match(/awCount\("\(visit\)"\)/g) || []).length, 1);
check("...and hashchange still records the route",
      /hashchange".*awCount\(awRoute\(\)\)/s.test(beacon), true);

/* THE PACKAGED APPS MUST NOT BEACON. privacy.html: "The apps collect nothing
   at all. The website keeps one aggregate counter." The Tizen .wgt and webOS
   .ipk ship this same watch.js, so without a guard the promise is false — and
   CORS is not the guard, because a simple POST is sent even when the response
   is blocked. */
{
  const beaconSrc = watch.slice(watch.indexOf("function awOnWebsite"),
                                watch.indexOf("addEventListener(\"hashchange\""));
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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
