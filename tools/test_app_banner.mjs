/**
 * test_app_banner.mjs — which store the web viewer offers a visitor.
 *
 * iOS gets Safari's native Smart App Banner from a meta tag. Android and Fire
 * have no equivalent, so watch.js renders one — and picking the wrong store is
 * worse than showing nothing: a Fire tablet's user-agent CONTAINS "Android",
 * so testing Android first sends every Fire visitor to Google Play, where this
 * app cannot be installed.
 *
 * appStorePlatform is read out of the SHIPPED watch.js so the test cannot drift.
 */
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../watch.js', import.meta.url), 'utf8');
const m = src.match(/function appStorePlatform\(ua\) \{[\s\S]*?\n  \}/);
if (!m) { console.error('FAIL: appStorePlatform not found in watch.js'); process.exit(1); }
const appStorePlatform = new Function(`${m[0]}; return appStorePlatform;`)();

// Real user-agent strings.
const UA = {
  fireTablet: 'Mozilla/5.0 (Linux; Android 9; KFMAWI) AppleWebKit/537.36 (KHTML, like Gecko) Silk/119.1.1 like Chrome/119 Safari/537.36',
  fireTV:     'Mozilla/5.0 (Linux; Android 9; AFTKA Build/PS7233) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119 Safari/537.36',
  pixel:      'Mozilla/5.0 (Linux; Android 14; Pixel 8a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Mobile Safari/537.36',
  googleTV:   'Mozilla/5.0 (Linux; Android 12; Chromecast) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
  iphone:     'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  ipad:       'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  mac:        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36',
  windows:    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36',
};

const cases = [
  ['Fire tablet (Silk) -> Amazon, NOT Play', UA.fireTablet, 'fire'],
  ['Fire TV (AFTKA) -> Amazon, NOT Play',    UA.fireTV,     'fire'],
  ['Pixel phone -> Play',                    UA.pixel,      'play'],
  ['Google TV -> Play',                      UA.googleTV,   'play'],
  ['iPhone -> nothing (Safari banners it)',  UA.iphone,     null],
  ['iPad -> nothing',                        UA.ipad,       null],
  ['Mac -> nothing',                         UA.mac,        null],
  ['Windows -> nothing',                     UA.windows,    null],
  ['empty UA -> nothing',                    '',            null],
];

let pass = 0;
for (const [name, ua, want] of cases) {
  const got = appStorePlatform(ua);
  const ok = got === want;
  if (ok) pass++;
  console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${name}  (-> ${got})`);
}
console.log(`\n${pass}/${cases.length} passed`);
process.exit(pass === cases.length ? 0 : 1);
