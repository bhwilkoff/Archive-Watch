/* test_share_list — a shared playlist travels in its own link, and the link
 * round-trips through the SHIPPED encoder.
 *
 * The design this guards: there is no backend and no account (Decisions 009
 * and 028), and privacy.html promises playlists never leave the device except
 * through the viewer's own cloud. So the playlist is IN the URL. That only
 * holds if the encoding is compact enough to survive a chat app, and if what
 * comes out is exactly what went in.
 *
 * Raw deflate is chosen because every platform here already inflates it —
 * Apple's Compression framework (Decision 019), Android's .zz catalog — so the
 * native apps can read this link with code they already ship.
 *
 * Run: node tools/test_share_list.mjs
 */
import fs from "node:fs";

let pass = 0, fail = 0;
const check = (ok, what, detail = "") => {
  console.log(`  ${ok ? "PASS" : "FAIL"}  ${what}${ok || !detail ? "" : `  — ${detail}`}`);
  ok ? pass++ : fail++;
};

// Load the SHIPPED implementation rather than a copy of it.
const src = fs.readFileSync("watch.js", "utf8");
const body = src.slice(src.indexOf("const ShareList = {"));
const objText = body.slice(0, body.indexOf("\n  };") + 4);   // include "\n  }", not the ";"
const ShareList = eval(`(${objText.replace(/^const ShareList = /, "")})`);

const ids = ["the-grapes-of-wrath-1940", "hog-wild_1930", "TheGeneral720p1926",
             "los-tallos-amargos-1956", "1912GeorgesMeliesALaConqueteDuPole"];

const blob = await ShareList.encode("Fordy Things", ids);
check(/^[A-Za-z0-9_-]+$/.test(blob), "the blob is URL-safe (no +, / or =)", blob.slice(0, 40));

const back = await ShareList.decode(blob);
check(back.name === "Fordy Things", "the name round-trips", back.name);
check(JSON.stringify(back.ids) === JSON.stringify(ids),
      "the ids round-trip IN ORDER", JSON.stringify(back.ids).slice(0, 60));

// NEGATIVE CONTROLS — a decoder that accepts anything proves nothing.
let threw = false;
try { await ShareList.decode("not-a-real-blob"); } catch { threw = true; }
check(threw, "garbage is REFUSED, not silently rendered as an empty list");
threw = false;
try { await ShareList.decode(await ShareList.encode("x", "nope")); } catch { threw = true; }
check(threw, "a payload whose ids are not a list is REFUSED");

// The size claim the whole design rests on — measured against REAL ids. A
// synthetic list ("some-archive-identifier-1", "-2", ...) is so repetitive that
// deflate crushes it to a fifth of the truth, which would flatter the claim
// rather than test it.
let long = null;
try {
  const cat = JSON.parse(fs.readFileSync("catalog.json", "utf8")).items;
  const real = cat.filter(i => !i.excluded).map(i => i.archiveID);
  long = Array.from({ length: 50 }, (_, k) => real[(k * 617) % real.length]);
} catch { /* catalog.json is a generated artifact; it may not be here */ }
if (long) {
  const big = await ShareList.encode("Fifty", long);
  check(big.length < 2000, `50 REAL titles stay inside a usable URL (${big.length} chars)`);
} else {
  console.log("  SKIP  50-title size check (catalog.json not present)");
}
check(ShareList.LIMIT === 50, "the app refuses to share past the measured limit");

globalThis.location = { origin: "https://archivewatch.org", pathname: "/" };
check(ShareList.url("ABC") === "https://archivewatch.org/#/list/ABC",
      "the URL is a /list route on our own origin", ShareList.url("ABC"));

// THE PRIVACY RULE. The playlist lives in the URL, so the analytics beacon
// must never be handed the route verbatim: that would send the whole list to
// our counter, which privacy.html promises never receives anything.
const awRouteSrc = src.slice(src.indexOf("function awRoute()"));
const awRoute = eval(`(${awRouteSrc.slice(0, awRouteSrc.indexOf("\n}") + 2).replace(/^function awRoute\(\)/, "function ()")})`);
globalThis.location = { hash: "#/list/" + blob, pathname: "/" };
check(awRoute() === "/list",
      "the beacon reports /list and NEVER the playlist blob", awRoute().slice(0, 48));
globalThis.location = { hash: "#/browse?type=silent-film", pathname: "/" };
check(awRoute() === "/browse?type=silent-film",
      "...while every other route is unchanged", awRoute());

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
