/* test_pulse_render.mjs — run the REAL pulse.js against the REAL ops/pulse.json
   in a DOM shim, and assert every section builds.

   A screenshot proves a screen drew; it cannot prove that switching to the
   Roku tab does not throw, or that a platform with no data renders a sentence
   instead of an empty chart. Those are the two failures this page is most
   likely to have, so they get a test rather than an eyeball.

   The shim is deliberately thin — enough DOM for the renderers and nothing
   more. If a renderer starts needing layout, that is a signal in itself.

     node tools/test_pulse_render.mjs
*/
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

let pass = 0, fail = 0;
const check = (name, ok, detail = "") => {
  ok ? pass++ : fail++;
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : "  " + detail}`);
};

/* ── the shim ─────────────────────────────────────────────────────────── */
class El {
  constructor(tag = "div") {
    this.tagName = tag.toUpperCase();
    this.children = []; this.attrs = {}; this.style = {}; this.dataset = {};
    this._text = ""; this._html = ""; this.hidden = false;
    this.classList = { _s: new Set(), add: (c) => this.classList._s.add(c) };
  }
  set className(v) { this.attrs.class = v; }
  get className() { return this.attrs.class || ""; }
  set textContent(v) { this._text = String(v); this.children = []; }
  get textContent() {
    return this._text + this.children.map((c) => c.textContent).join("");
  }
  set innerHTML(v) { this._html = String(v); this.children = []; this._text = ""; }
  get innerHTML() {
    return this._html + this.children.map((c) => c.outerHTML).join("");
  }
  get outerHTML() {
    return `<${this.tagName.toLowerCase()} class="${this.className}">`
      + this.innerHTML + (this._text || "") + `</${this.tagName.toLowerCase()}>`;
  }
  appendChild(c) { this.children.push(c); return c; }
  insertAdjacentHTML(_pos, html) { this._html += html; }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return this.attrs[k] ?? null; }
  querySelectorAll() { return []; }
  querySelector() { return null; }
}

const byId = new Map();
for (const id of ["when", "ticker", "needs", "needs-n", "stores", "stores-n", "tiles",
                  "said", "said-n", "said-chips", "social", "social-n", "trend",
                  "sources", "src-n", "tabs", "sec-overview", "sec-platform",
                  "platform-lede", "platform-panels", "platform-rows", "platform-h2"]) {
  byId.set(id, new El("div"));
}

const doc = {
  createElement: (t) => new El(t),
  getElementById: (id) => byId.get(id) ?? null,
  querySelectorAll: () => [],
  createTextNode: (t) => { const e = new El("span"); e.textContent = t; return e; },
};

let fetched = null;
const g = globalThis;
g.document = doc;
g.location = { hash: "", pathname: "/pulse/" };
g.window = g;
g.addEventListener = () => {};
g.scrollTo = () => {};
g.fetch = (u) => { fetched = u; return Promise.resolve({ ok: true, json: () => Promise.resolve(DATA) }); };

const DATA = JSON.parse(readFileSync(join(root, "ops", "pulse.json"), "utf8"));

/* ── load the real files ──────────────────────────────────────────────── */
const charts = readFileSync(join(root, "pulse", "charts.js"), "utf8");
const page = readFileSync(join(root, "pulse", "pulse.js"), "utf8");
// pulse.js ends with the fetch chain; run it and let the shim resolve it.
const run = new Function(`${charts}\n${page}\nreturn { platforms, show, tabs, appPlatform, socialPlatform };`);
let api;
try {
  api = run();
  check("pulse.js loads and its fetch chain starts", true);
} catch (e) {
  check("pulse.js loads", false, e.message);
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(1);
}

await new Promise((r) => setTimeout(r, 30));   // let the fetch promise settle

/* ── the assertions that matter ───────────────────────────────────────── */
const list = api.platforms(DATA);
check("the data yields platforms", list.length > 0, String(list.length));

const appKeys = list.filter((p) => p.family === "app").map((p) => p.name);
check("every app platform gets a section",
      ["tvOS", "iOS", "Android", "Web"].every((n) => appKeys.includes(n)),
      appKeys.join(", "));
check("the API-less stores are present too",
      appKeys.some((n) => n === "Fire TV") && appKeys.some((n) => n === "Roku"),
      appKeys.join(", "));

const social = list.filter((p) => p.family === "social");
check("every social platform gets a section", social.length >= 4,
      social.map((p) => p.name).join(", "));

// The real risk: a platform with NO data throwing, or rendering an empty chart.
let threw = null;
for (const p of list) {
  try {
    api.show(DATA, list, p.key);
  } catch (e) {
    threw = `${p.key}: ${e.message}`;
    break;
  }
}
check("switching to every section renders without throwing", threw === null, threw || "");

api.show(DATA, list, "roku");
// Assert on the ROWS alone. Including the lede made this pass off a sentence
// the lede always prints, so it was not testing the branch it names — a
// negative control caught it before the commit, which is the point of running
// one on every case rather than on the suite.
const rokuRows = byId.get("platform-rows").textContent;
check("a store with no API says so in words, not an empty chart",
      /publishes no numbers we can read/i.test(rokuRows), JSON.stringify(rokuRows.slice(0, 70)));
check("...and its lede names the store", 
      /exposes no API/i.test(byId.get("platform-lede").innerHTML));

api.show(DATA, list, "android");
const android = byId.get("platform-panels").innerHTML;
check("Android draws its installs", /c-run|c-spark/.test(android));
check("Android draws where they are", /c-dot/.test(android));
check("Android draws its crashes as a pareto", /c-pareto/.test(android));

api.show(DATA, list, "tvos");
check("tvOS gets its OWN device series, not Apple's total",
      byId.get("platform-panels").innerHTML.length > 100);

api.show(DATA, list, "overview");
check("overview comes back", byId.get("sec-overview").hidden === false);
check("and the platform section hides", byId.get("sec-platform").hidden === true);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
