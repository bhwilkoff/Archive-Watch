// §8.29 — the Worker's code normalisation must MATCH the app's, exactly.
//
// A code is read aloud on a call and typed on another device. If the Swift
// side maps a heard "oh" to 0 and the Worker does not — or the other way —
// then a guest who types what they heard reaches a DIFFERENT room, or no
// room, and the failure looks like "the code doesn't work" with nothing to
// point at. Two implementations of one rule is the classic way that happens,
// and this is the only thing keeping them honest.
//
// The Swift side is tools/test_studio_room.swift (§8.28); this asserts the
// SAME table of inputs against the JavaScript.
import { normalizeCode } from "../worker/src/together.js";

let failures = 0;
function check(label, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
}

console.log("=== §8.29 worker/app code parity ===");

// The identical cases §8.28 asserts in Swift.
const cases = [
  ["ca11", "CA11", "lower case"],
  ["CA 11", "CA11", "spaces ignored"],
  ["CA-11", "CA11", "dashes ignored"],
  ["CAL1", "CA11", "a typed L becomes 1"],
  ["CAI1", "CA11", "a typed I becomes 1"],
  ["CALI", "CA11", "both at once"],
  ["CODE", "C0DE", "a typed O becomes 0"],
  ["C0DE", "C0DE", "a real zero is untouched"],
  ["ABCD", "ABCD", "a clean code passes through"],
];
for (const [input, want, why] of cases) {
  const got = normalizeCode(input);
  check(`${why}: "${input}" -> ${want}`, got === want, got === null ? "null" : got);
}

// THE ONE THAT MATTERS MOST: every spelling a listener could produce lands in
// the same room.
check("ALL SPELLINGS OF THE SAME CODE AGREE",
  new Set(["CALI", "CAL1", "CAI1", "CA11", "ca11"].map(normalizeCode)).size === 1,
  JSON.stringify(["CALI", "CAL1", "CAI1", "CA11", "ca11"].map(normalizeCode)));

const rejects = [
  ["AB", "too short"],
  ["ABCDE", "too long"],
  ["AB!E", "punctuation"],
  ["ABUE", "U is not in the alphabet"],
  ["", "empty"],
  [null, "not a string"],
  [12345, "a number"],
];
for (const [input, why] of rejects) {
  check(`refused (${why})`, normalizeCode(input) === null, String(normalizeCode(input)));
}

// CONTROL: if everything were refused, the rejections above would prove
// nothing at all.
check("CONTROL: a well-formed code is still accepted", normalizeCode("XYZ9") === "XYZ9");

console.log(failures === 0 ? "=== §8.29 OK ===" : `=== §8.29 ${failures} FAILURES ===`);
process.exit(failures === 0 ? 0 : 1);
