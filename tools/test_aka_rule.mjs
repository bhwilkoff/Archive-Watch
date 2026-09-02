/**
 * The "also known as" rule (Decision 100), tested against watch.js's OWN
 * implementation — the platform the defect was reported on.
 *
 * The rule lives in three languages (Swift, Kotlin, JS) and they must agree.
 * This locks the CONTRACT with fixtures drawn from the live catalog, including
 * the cases that must stay QUIET: a rule that fires too often is the same
 * defect as one that never fires.
 *
 *     node tools/test_aka_rule.mjs
 */
import { readFileSync } from 'node:fs';

// Lift the two functions out of watch.js rather than reimplement them — a test
// that reimplements its subject proves only that two copies agree.
const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const lig = src.match(/const AKA_LIGATURES = \{[\s\S]*?\};/)[0];
const key = src.match(/function titleKey\(s\) \{[\s\S]*?\n  \}/)[0];
const aka = src.match(/function alsoKnownAs\(title, canonical\) \{[\s\S]*?\n  \}/)[0];
const { alsoKnownAs } = new Function(`${lig}\n${key}\n${aka}\nreturn { alsoKnownAs };`)();

const CASES = [
  // SHOWS — genuinely different release titles, the case this exists for.
  ['The Last Three', 'Nazty Nuisance', 'Nazty Nuisance'],
  ['Reefer Madness', 'Tell Your Children', 'Tell Your Children'],
  ['The Phantom Ship', 'The Mystery of the Mary Celeste', 'The Mystery of the Mary Celeste'],
  ['Hell Town', 'Born to the West', 'Born to the West'],
  // QUIET — the same title wearing different clothes.
  ['Suddenly', 'Suddenly', null],
  ['Alice in Wonderland', null, null],
  ['Alice in Wonderland', '', null],
  ['The Cabinet of Dr. Caligari', 'Cabinet of Dr. Caligari', null],  // leading article
  ['Reefer Madness (In Color)', 'Reefer Madness', null],             // parenthetical
  ['Thais', 'Thaïs', null],                                          // diacritic
  ['"Tannhauser"', 'Tannhäuser', null],                              // diacritic + quotes
  ['Les Oeufs de Paques', 'Les oeufs de Pâques', null],              // case + diacritic
  ['Coeur fidele', 'Cœur fidèle', null],                             // ligature + diacritic
];

let failed = 0;
for (const [title, canon, want] of CASES) {
  const got = alsoKnownAs(title, canon) || null;
  const ok = got === want;
  if (!ok) failed++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'} ${JSON.stringify(title).padEnd(32)} canon=${JSON.stringify(canon)} -> ${JSON.stringify(got)}${ok ? '' : `  (expected ${JSON.stringify(want)})`}`);
}
console.log(`\n${CASES.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
