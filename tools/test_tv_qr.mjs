/* Lock the TV share-sheet QR encoder against the reference it was built from.
 *
 * A television has no share sheet and no usable clipboard, so a QR code is the
 * ONLY way a viewer gets a playlist link off the set. That makes the encoder
 * load-bearing, and a QR code is exactly the kind of artefact that looks
 * perfect and is unreadable: every failure mode here — a mistranscribed
 * alignment centre, a format-info axis swap, a shifted data bit — produces a
 * clean-looking square of noise.
 *
 * So the encoder is proven two ways, and the SOURCE it is proven against is an
 * independent implementation, never this one:
 *
 *   1. STRUCTURE. For each golden vector, exactly ONE of the eight masks must
 *      reproduce the reference matrix. That proves the bit stream, Reed-Solomon
 *      ECC, block interleave, function patterns, data placement, format info
 *      and every mask — independently of which mask the penalty happens to
 *      pick, which is a heuristic no two implementations agree on.
 *
 *   2. CAPACITY. Each vector is sized to its version's exact EC-L capacity, so
 *      the version chosen must be the version expected. That is what catches a
 *      wrong row in the version table, which is otherwise invisible.
 *
 * The golden vectors (tools/qr_golden.json) are matrix SHA-256s rather than
 * matrices: 40 full matrices are ~500 KB and a hash is exact.
 *
 * Regenerate ONLY from an independent reference, never from this encoder —
 * a golden file generated from the code it tests asserts nothing.
 *
 *   node tools/test_tv_qr.mjs
 */
import fs from "node:fs";
import crypto from "node:crypto";

/* Load the REAL tv.js, exactly as test_tv_focus.mjs does, so this tests the
 * shipped encoder rather than a copy that can drift away from it.
 *
 * tv.js returns immediately unless it detects a TV runtime, so the shim must
 * claim to BE one — otherwise the encoder is never defined and this file would
 * happily test nothing. The export hook is placed right after the encoder, so
 * everything the boot sequence needs is beside the point: whatever it throws
 * against this deliberately thin shim, the function is already in hand. */
const src = fs.readFileSync("tv.js", "utf8");
const MARKER = "const PICKER_CLASS = 'tv-picker';";
if (!src.includes(MARKER)) {
  console.log("FAIL  tv.js no longer contains the export anchor — update this test");
  process.exit(1);
}
const hooked = src.replace(MARKER, "__export(qrMatrix);\n  " + MARKER);

let qrMatrix;
const noop = () => {};
const el = () => ({
  className: "", style: {}, classList: { add: noop, remove: noop, contains: () => false },
  appendChild: noop, setAttribute: noop, addEventListener: noop,
  getContext: () => ({ fillRect: noop, fillStyle: "" }),
});
const shim = {
  navigator: { userAgent: "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0)" },
  location: { search: "", hash: "", pathname: "/", origin: "https://archivewatch.org" },
  document: {
    readyState: "complete", documentElement: el(), body: el(), activeElement: null,
    createElement: el, querySelector: () => null, querySelectorAll: () => [],
    addEventListener: noop, contains: () => false,
  },
  MutationObserver: class { observe() {} disconnect() {} },
  URLSearchParams: globalThis.URLSearchParams,
};
shim.window = shim;
try {
  new Function("__export", "window", "document", "navigator", "location",
               "MutationObserver", "URLSearchParams", hooked)(
    (f) => { qrMatrix = f; }, shim, shim.document, shim.navigator, shim.location,
    shim.MutationObserver, shim.URLSearchParams);
} catch (e) {
  if (!qrMatrix) throw e;     // only a failure BEFORE the encoder matters
}

let pass = 0, fail = 0;
function check(label, ok, detail) {
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}${detail ? "  — " + detail : ""}`);
  ok ? pass++ : fail++;
}
const sha = (rows) => crypto.createHash("sha256").update(rows.join("\n")).digest("hex");

check("tv.js exposes the encoder", typeof qrMatrix === "function");
if (typeof qrMatrix !== "function") {
  console.log("\ncannot continue without the encoder");
  process.exit(1);
}

const golden = JSON.parse(fs.readFileSync("tools/qr_golden.json", "utf8"));

for (const g of golden) {
  const chosen = qrMatrix(g.text);
  if (!chosen) { check(`v${g.version} encodes`, false, "returned null"); continue; }

  // 2 — CAPACITY: the string is sized to this version's exact capacity.
  check(`v${g.version} picks the right version`,
        chosen.version === g.version && chosen.size === g.size,
        `got v${chosen.version} ${chosen.size}x${chosen.size}`);

  // 1 — STRUCTURE: exactly one mask reproduces the reference.
  const hits = [];
  for (let m = 0; m < 8; m++) {
    const r = qrMatrix(g.text, m);
    if (r && sha(r.modules.map((row) => row.join(""))) === g.sha256) hits.push(m);
  }
  check(`v${g.version} matches the reference under exactly one mask`,
        hits.length === 1, `matched ${hits.length} mask(s)`);
}

/* The boundary itself. v40 EC-L holds 2,953 bytes in byte mode; one past it
 * must return null rather than a wrong code, because the share sheet renders
 * a written explanation when it cannot encode and a silent bad code would be
 * far worse than a refusal. */
check("2953 bytes still encodes", qrMatrix("a".repeat(2953))?.version === 40);
check("2954 bytes refuses", qrMatrix("a".repeat(2954)) === null);

/* A real share URL must fit — this is the whole point of extending the
 * encoder past v10, and it is the assertion that would have caught the
 * original v1-10 ceiling. Measured against real catalogue ids, a 50-film
 * playlist link runs ~1,048-1,328 characters. */
const long = "https://archivewatch.org/#/list/" + "Qm5j9x-_".repeat(166); // 1,360
const m = qrMatrix(long);
check("a 50-film-sized share link encodes", m !== null,
      m ? `v${m.version} ${m.size}x${m.size}` : "returned null");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
