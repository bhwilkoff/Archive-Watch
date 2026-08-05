/* Verify the web-TV layer activates on REAL smart-TV user agents and stays
 * inert everywhere else.
 *
 * The whole web-TV strategy hinges on this one branch: get detection wrong and
 * either TVs get the phone UI, or phones get a TV UI. Cheap to check, expensive
 * to discover on a panel you cannot debug.
 */
import fs from 'fs';

const src = fs.readFileSync('tv.js', 'utf8');

const CASES = [
  ['webOS (LG)',    'Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.31 Safari/537.36 WebAppManager', 'tv-webos'],
  ['Tizen (Samsung)','Mozilla/5.0 (SMART-TV; LINUX; Tizen 7.0) AppleWebKit/537.36 (KHTML, like Gecko) 94.0.4606.31/7.0 TV Safari/537.36',        'tv-tizen'],
  ['VIDAA (Hisense)','Mozilla/5.0 (Linux; U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89 Safari/537.36 VIDAA/6.0',                          'tv-vidaa'],
  ['iPhone',        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1',       null],
  ['Desktop Chrome','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36',           null],
];

let pass = 0, fail = 0;
for (const [name, ua, expected] of CASES) {
  const cls = [];
  global.document = {
    documentElement: { classList: { add: (...c) => cls.push(...c) } },
    addEventListener() {}, querySelector: () => null, querySelectorAll: () => [],
    body: {}, readyState: 'complete', activeElement: null,
  };
  global.window = { addEventListener() {}, close() {} };
  Object.defineProperty(global, 'navigator', { value: { userAgent: ua }, configurable: true });
  global.location = { search: '', hash: '' };
  global.history = { back() {} };
  global.getComputedStyle = () => ({ visibility: 'visible', display: 'block' });
  global.MutationObserver = class { observe() {} };
  global.URLSearchParams = URLSearchParams;
  try { new Function(src)(); } catch { /* boot errors surface as no class */ }

  const ok = expected ? cls.includes('tv') && cls.includes(expected) : cls.length === 0;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(17)} -> ${cls.join(' ') || '(inactive)'}`);
  ok ? pass++ : fail++;
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
