/* test_pulse_charts.mjs — the chart kit, held to the properties a reader relies
   on: a bar's LENGTH is proportional to its value, a bullet's measure lands at
   the right position on its scale, a stack sums to the whole, and a series with
   one point draws nothing rather than a misleading flat line.

   Every case was checked to FAIL against a deliberately broken version of the
   rule it covers, which is the only way to know a regression test works.

     node tools/test_pulse_charts.mjs
*/
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "pulse", "charts.js"), "utf8");
const C = new Function(`${src}; return C;`)();

let pass = 0, fail = 0;
const check = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  ok ? pass++ : fail++;
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`}`);
};
const near = (name, got, want, tol = 0.6) => {
  const ok = Math.abs(got - want) <= tol;
  ok ? pass++ : fail++;
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `: got ${got}, want ~${want}`}`);
};
const widths = (html) => [...html.matchAll(/width:\s*([\d.]+)%/g)].map((m) => +m[1]);

/* ── bullet: the measure lands where the scale says it should ───────────── */
console.log("bullet()");
{
  // Scale 0-5, viewBox width 200 — a 4.4 measure must be 176 wide, not "most
  // of the way along", which is what a gauge would leave a reader guessing.
  const h = C.bullet({ value: 4.4, max: 5, bands: [3, 4], target: 4.5, label: "x" });
  const measure = /class="measure[^"]*"/.exec(h);
  const w = +/<rect x="0" y="7" width="([\d.]+)"/.exec(h)[1];
  near("4.4 of 5 is 88% of the scale", w, 176);
  check("the measure is drawn", !!measure, true);
  const tx = +/<line x1="([\d.]+)"/.exec(h)[1];
  near("the 4.5 target marker sits at 90%", tx, 180);
  check("three bands for two cut points", (h.match(/class="band/g) || []).length, 3);
  check("bands are one hue at three intensities, never three hues",
        /b1|b2|b3/.test(h) && !/fill="#/.test(h), true);
  check("carries its number for a screen reader", /aria-label="x"/.test(h), true);
}
{
  // A value past the top of the scale must CLAMP, not overflow the chart.
  const h = C.bullet({ value: 99, max: 5 });
  const w = +/<rect x="0" y="7" width="([\d.]+)"/.exec(h)[1];
  check("an over-scale value clamps to the axis", w, 200);
}

/* ── bars: length is proportional, on a common baseline ─────────────────── */
console.log("\nbars()");
{
  const h = C.bars([
    { label: "a", value: 10 }, { label: "b", value: 5 }, { label: "c", value: 0 },
  ]);
  check("length is proportional to value", widths(h), [100, 50, 0]);
  check("every row is drawn, zero included", (h.match(/c-bar-l/g) || []).length, 3);
}
{
  // Sharing an explicit max is what makes two charts comparable at all.
  const h = C.bars([{ label: "a", value: 25 }], { max: 100 });
  check("an explicit max sets the shared baseline", widths(h), [25]);
}
{
  const h = C.bars([{ label: "x", value: 3, display: "62%" }]);
  check("a display string overrides the raw number", /62%/.test(h), true);
}
{
  const h = C.bars([{ label: "<img src=x>", value: 1 }]);
  check("a label is escaped, never injected", /&lt;img/.test(h) && !/<img/.test(h), true);
}

/* ── stack: the segments sum to the whole ───────────────────────────────── */
console.log("\nstack()");
{
  const h = C.stack([
    { label: "live", value: 7, tone: "live" },
    { label: "flight", value: 2, tone: "flight" },
    { label: "idle", value: 2, tone: "idle" },
  ]);
  const w = widths(h);
  near("segments sum to 100%", w.reduce((a, b) => a + b, 0), 100, 0.05);
  near("7 of 11 is 63.6%", w[0], 63.64, 0.05);
  check("a zero segment is not drawn as a hairline",
        widths(C.stack([{ label: "a", value: 1 }, { label: "b", value: 0 }])).length, 1);
}

/* ── spark: shape over time, and silence when there is no shape ─────────── */
console.log("\nspark()");
{
  check("one reading draws nothing", C.spark([4]), "");
  check("no readings draw nothing", C.spark([]), "");
  const h = C.spark([1, 2, 3]);
  check("two or more readings draw a line", /<polyline/.test(h), true);
  check("the last reading is marked", /<circle/.test(h), true);
  check("a gap in the series does not break the line",
        /<polyline/.test(C.spark([1, null, 3])), true);
  // A flat series must still draw — "nothing changed" is a finding, not a blank.
  const flat = C.spark([2, 2, 2]);
  check("a flat series still draws", /<polyline/.test(flat), true);
  const ys = [...flat.matchAll(/,([\d.]+)/g)].map((m) => +m[1]);
  check("a flat series is drawn flat", new Set(ys.slice(1, 4)).size, 1);
}

/* ── cadence: a post lands at its position on a shared time axis ────────── */
console.log("\ncadence()");
{
  const now = Date.now();
  const iso = (d) => new Date(now - d * 864e5).toISOString();
  const h = C.cadence([{ label: "bluesky", marks: [
    { at: iso(0), title: "today" },
    { at: iso(15), title: "middle" },
    { at: iso(45), title: "older than the window" },
  ] }], { days: 30 });
  const lefts = [...h.matchAll(/left:([\d.]+)%/g)].map((m) => +m[1])
    .filter((v, i, a) => a.indexOf(v) === i);
  check("a mark outside the window is dropped",
        (h.match(/title="older than the window"/g) || []).length, 0);
  near("today sits at the right edge", Math.max(...lefts), 100, 0.5);
  near("15 days back sits at the middle", lefts.find((v) => v > 40 && v < 60), 50, 1.5);
  check("each mark carries what it is", /title="today"/.test(h), true);
}

/* ── ratio + dots ───────────────────────────────────────────────────────── */
console.log("\nratio() and dots()");
{
  const h = C.ratio(26461, 26711);
  check("the proportion is drawn", widths(h).length, 1);
  near("26461 of 26711 is 99.1%", widths(h)[0], 99.1, 0.1);
  check("the number is said as well as drawn", /of 26,711/.test(h), true);
}
{
  const h = C.dots([{ label: "a", tone: "stop" }, { label: "b", tone: "flight" }]);
  check("one mark per thing", (h.match(/<i /g) || []).length, 2);
  check("state is carried by class, not by a fill", /class="stop"/.test(h), true);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
