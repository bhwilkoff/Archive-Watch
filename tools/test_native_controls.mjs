/**
 * test_native_controls.mjs — our player chrome must never draw a control the
 * browser's OWN <video controls> bar already shows.
 *
 * Owner report: "I don't want controls that are native on specific platforms
 * to show twice... for example, picture-in-picture and speed controls when you
 * view the website on an iPad or Mac".
 *
 * The engine matrix was measured, not assumed:
 *   Chrome macOS   — overflow menu has Captions + Playback speed; NO PiP
 *                    button in the bar (PiP is right-click only). Verified on
 *                    the glass by opening the menu.
 *   Safari mac/iPad— bar has a PiP button and a settings menu with speed.
 *                    This is the owner's own report and the reason for the fix.
 *   Firefox        — speed is right-click, PiP is a hover overlay; neither is
 *                    a control in the bar, so ours must stay.
 *
 * The function is read out of the SHIPPED watch.js so the test cannot drift
 * from what runs.
 */
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const m = src.match(/function nativeControlSet\(video, doc\) \{[\s\S]*?\n  \}/);
if (!m) { console.error('FAIL: nativeControlSet not found in watch.js'); process.exit(1); }
const nativeControlSet = new Function(`${m[0]}; return nativeControlSet;`)();

const SAFARI   = [{ webkitSetPresentationMode() {} }, { pictureInPictureEnabled: false }];
// iPadOS/macOS Safari also exposes the standard flag; the WebKit bar still owns both.
const SAFARI26 = [{ webkitSetPresentationMode() {} }, { pictureInPictureEnabled: true }];
const CHROME   = [{}, { pictureInPictureEnabled: true }];
const FIREFOX  = [{}, { pictureInPictureEnabled: undefined }];

const cases = [
  ['Safari: bar has speed -> ours hidden',        SAFARI,   'speed',  true],
  ['Safari: bar has PiP -> ours hidden',          SAFARI,   'pip',    true],
  ['Safari w/ standard API: still WebKit bar',    SAFARI26, 'pip',    true],
  ['Safari w/ standard API: speed still native',  SAFARI26, 'speed',  true],
  ['Chrome: overflow has speed -> ours hidden',   CHROME,   'speed',  true],
  ['Chrome: no PiP in bar -> ours SHOWN',         CHROME,   'pip',    false],
  ['Chrome: we can drive PiP ourselves',          CHROME,   'canPiP', true],
  ['Firefox: speed not in bar -> ours SHOWN',     FIREFOX,  'speed',  false],
  ['Firefox: no standard API -> we cannot PiP',   FIREFOX,  'canPiP', false],
];

let pass = 0;
for (const [name, [v, d], key, want] of cases) {
  const got = nativeControlSet(v, d)[key];
  const ok = got === want;
  if (ok) pass++;
  console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${name}  (${key}=${got})`);
}
console.log(`\n${pass}/${cases.length} passed`);
process.exit(pass === cases.length ? 0 : 1);
