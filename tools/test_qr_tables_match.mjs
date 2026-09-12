/* The two QR encoders must carry IDENTICAL tables.
 *
 * There are two of them — `tv.js` for the web-TV build and
 * `roku/components/QR.brs` for the Roku channel — because BrightScript cannot
 * run the JS and the Roku has no QR API. Only ONE of them can be checked
 * against an independent reference from here: `tools/test_tv_qr.mjs` proves
 * the JS cell-for-cell at all 40 versions, while BrightScript needs a device.
 *
 * So this asserts the cheap, decisive half: the version table and the
 * alignment centres are byte-identical between the two files. That makes the
 * JS proof transitive for the part of the encoder that is pure data — which is
 * exactly where the damage has happened. `QR.brs` carried [6, 28, 52] for v10
 * where the spec says 50, and every version-10 code it ever drew was
 * unreadable. This test would have caught it the moment the port existed.
 *
 * It does NOT prove the BrightScript ALGORITHM. That is verified on the device
 * (tools/roku.py + the AWQR trace), and the two implementations are
 * deliberately line-for-line twins so a reader can diff them.
 *
 *   node tools/test_qr_tables_match.mjs
 */
import fs from "node:fs";

let pass = 0, fail = 0;
const check = (label, ok, detail) => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}${detail ? "  — " + detail : ""}`);
  ok ? pass++ : fail++;
};

const js = fs.readFileSync("tv.js", "utf8");
const brs = fs.readFileSync("roku/components/QR.brs", "utf8");

/** Every `[1, 2, 3]` on its own line inside a named region of a file. */
function rows(text, startMarker, endMarker) {
  const a = text.indexOf(startMarker);
  if (a < 0) return null;
  const b = endMarker ? text.indexOf(endMarker, a) : text.length;
  const region = text.slice(a, b < 0 ? text.length : b);
  return [...region.matchAll(/\[([0-9,\s]*)\]/g)].map((m) =>
    m[1].trim() === "" ? [] : m[1].split(",").map((n) => Number(n.trim())));
}

const jsTbl = rows(js, "const TBL = [", "];");
const jsAP  = rows(js, "const AP = [", "];");
const brsTbl = rows(brs, "function qrVersionTable", "end function");
const brsAP  = rows(brs, "function qrAlignPositions", "end function");

check("tv.js version table found", jsTbl?.length === 40, `${jsTbl?.length} rows`);
check("tv.js alignment table found", jsAP?.length === 40, `${jsAP?.length} rows`);
check("QR.brs version table found", brsTbl?.length === 40, `${brsTbl?.length} rows`);
check("QR.brs alignment table found", brsAP?.length === 40, `${brsAP?.length} rows`);

if (jsTbl?.length === 40 && brsTbl?.length === 40) {
  let bad = 0;
  for (let i = 0; i < 40; i++) {
    if (JSON.stringify(jsTbl[i]) !== JSON.stringify(brsTbl[i])) {
      bad++;
      if (bad <= 3) console.log(`      v${i + 1}: js ${JSON.stringify(jsTbl[i])} vs brs ${JSON.stringify(brsTbl[i])}`);
    }
  }
  check("version tables identical across both encoders", bad === 0, `${bad} row(s) differ`);
}
if (jsAP?.length === 40 && brsAP?.length === 40) {
  let bad = 0;
  for (let i = 0; i < 40; i++) {
    if (JSON.stringify(jsAP[i]) !== JSON.stringify(brsAP[i])) {
      bad++;
      if (bad <= 3) console.log(`      v${i + 1}: js ${JSON.stringify(jsAP[i])} vs brs ${JSON.stringify(brsAP[i])}`);
    }
  }
  check("alignment tables identical across both encoders", bad === 0, `${bad} row(s) differ`);
}

/* The v10 row specifically, by value — the regression that motivated all of
 * this, named so a failure says what it is rather than "row 10 differs". */
check("v10 alignment centres are 6, 28, 50 (not 52)",
      JSON.stringify(brsAP?.[9]) === JSON.stringify([6, 28, 50]),
      JSON.stringify(brsAP?.[9]));

/* No version-info table may come back: it is computed in both files now, and a
 * reintroduced 40-constant table is 34 fresh chances to mistype one. */
check("QR.brs computes version info rather than tabulating it",
      brs.includes("BCH(18,6)") && !brs.includes("31892"));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
