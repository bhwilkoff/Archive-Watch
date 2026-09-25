/* Archive Watch — Pulse chart kit.

   Hand-rolled inline SVG. No library, no build step (Decision 001), and none of
   the shapes Stephen Few spends Information Dashboard Design arguing against:
   no gauges, no dials, no pie charts, no 3-D, no gradients, no chart junk.

   The encodings are chosen in Cleveland & McGill's order of how accurately a
   person reads them — POSITION first, then LENGTH, then area, and colour last.
   So a comparison is a bar or a position on a common scale; colour is reserved
   for state (live / in flight / needs you), never for quantity.

   The shapes most of the page is built from:

     bullet()    a measure against a scale, bands and a target — Few's own
                 replacement for the gauge: same information, a fifth of the space
     bars()      length on a common baseline, the most accurate comparison there is
     spark()     Tufte's word-sized graphic: shape over time, next to the number
     stack()     one bar showing how a whole divides — never a pie
     timeChart() a dated series with a readable axis and a crosshair — the
                 drill-down's chart (docs/PULSE.md, "Drill-down")

   The one runtime style this kit writes is a computed LENGTH: a bar's width,
   a mark's position, the tooltip's --x. Each is a number that exists only
   once the data does (docs/PULSE.md).

   Everything returns an SVG STRING with an aria-label, so a caller can drop it
   into innerHTML and a screen reader still gets the number. */

const C = (() => {
const SVGNS = 'xmlns="http://www.w3.org/2000/svg"';
const esc = (s) => String(s == null ? "" : s)
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");

/* ── bullet: a measure, a scale, qualitative bands, a target ──────────────
   value  the featured measure (thick bar)
   max    the top of the quantitative scale
   bands  cut points, low to high — drawn as intensities of ONE hue so the
          chart survives colour-blindness and spends no colour on quantity
   target a thin perpendicular marker; omit when there is nothing to hit    */
function bullet({ value, max, bands = [], target = null, tone = "measure",
                         invert = false, label = "" }) {
  const W = 200, H = 22, r = 2;
  const x = (v) => Math.max(0, Math.min(1, v / max)) * W;
  const cuts = [...bands, max];
  let out = `<svg ${SVGNS} viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"`
    + ` class="c-bullet" role="img" aria-label="${esc(label)}">`;
  let from = 0;
  cuts.forEach((c, i) => {
    // low index = worst; invert flips that for a metric where lower is better
    const step = invert ? cuts.length - i : i + 1;
    out += `<rect x="${x(from).toFixed(1)}" y="0" width="${(x(c) - x(from)).toFixed(1)}"`
      + ` height="${H}" class="band b${Math.min(3, step)}"/>`;
    from = c;
  });
  out += `<rect x="0" y="${H / 2 - 4}" width="${x(value).toFixed(1)}" height="8"`
    + ` rx="${r}" class="measure ${tone}"/>`;
  if (target != null) {
    out += `<line x1="${x(target).toFixed(1)}" x2="${x(target).toFixed(1)}"`
      + ` y1="2" y2="${H - 2}" class="target"/>`;
  }
  return out + "</svg>";
}

/* ── bars: length on a common baseline ───────────────────────────────────
   rows: [{ label, value, tone?, note? }] — the most accurate comparison a
   reader can make, and the reason there is no pie chart on this page.     */
function bars(rows, { max = null, unit = "", showZero = true } = {}) {
  const vals = rows.map((r) => Number(r.value) || 0);
  const top = max ?? Math.max(1, ...vals);
  return `<div class="c-bars">` + rows.map((r) => {
    const v = Number(r.value) || 0;
    const pct = (v / top) * 100;
    const zero = v === 0 && !showZero;
    return `<div class="c-bar${zero ? " nil" : ""}">`
      + `<span class="c-bar-l">${esc(r.label)}</span>`
      + `<span class="c-bar-t"><i class="${esc(r.tone || "measure")}"`
      + ` style="width:${pct.toFixed(1)}%"></i></span>`
      + `<span class="c-bar-v">${esc(r.display ?? (v + unit))}</span>`
      + (r.note ? `<span class="c-bar-n">${esc(r.note)}</span>` : "")
      + `</div>`;
  }).join("") + `</div>`;
}

/* ── spark: shape over time, word-sized, beside the number ───────────────
   An area under the line so a glance reads the level, not just the wiggle;
   a dot on the last reading so "now" is findable without a legend.        */
/* `max` (and `min`) pin the vertical scale to something OUTSIDE this series,
   which is what makes a row of sparks a set of SMALL MULTIPLES rather than a
   row of unrelated shapes. Without it every spark autoscales to its own range,
   so a platform with 3 installs a day and one with 300 draw the same picture —
   and a caption claiming a shared scale would simply be false. Default stays
   self-scaling: a lone spark beside a number is right to use its own range. */
function spark(vals, { label = "", w = 220, h = 42, max = null, min = null } = {}) {
  const pts = vals.map((v, i) => [i, typeof v === "number" ? v : null])
    .filter(([, v]) => v !== null);
  if (pts.length < 2) return "";
  const pad = 3;
  const nums = pts.map(([, v]) => v);
  const lo = min != null ? min : Math.min(...nums);
  const hi = max != null ? max : Math.max(...nums);
  const span = (hi - lo) || 1;
  const X = (i) => pad + (i / Math.max(1, vals.length - 1)) * (w - pad * 2);
  const Y = (v) => h - pad - ((v - lo) / span) * (h - pad * 2);
  const line = pts.map(([i, v]) => `${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ");
  const first = pts[0], last = pts[pts.length - 1];
  const area = `${X(first[0]).toFixed(1)},${h} ${line} ${X(last[0]).toFixed(1)},${h}`;
  return `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"`
    + ` class="c-spark" role="img" aria-label="${esc(label)}">`
    + `<polygon class="fill" points="${area}"/>`
    + `<polyline class="line" points="${line}"/>`
    + `<circle class="dot" cx="${X(last[0]).toFixed(1)}" cy="${Y(last[1]).toFixed(1)}" r="2.6"/>`
    + `</svg>`;
}

/* ── stack: how one whole divides ────────────────────────────────────────
   segments: [{ label, value, tone }] — a single bar, never a pie: a reader
   compares lengths along one axis instead of judging angles.              */
function stack(segments, { label = "" } = {}) {
  const total = segments.reduce((s, x) => s + (Number(x.value) || 0), 0) || 1;
  return `<div class="c-stack" role="img" aria-label="${esc(label)}">`
    + segments.map((s) => {
      const pct = ((Number(s.value) || 0) / total) * 100;
      if (pct <= 0) return "";
      return `<i class="${esc(s.tone || "idle")}" style="width:${pct.toFixed(2)}%"`
        + ` title="${esc(s.label)}: ${s.value}"></i>`;
    }).join("") + `</div>`;
}

/* ── legend: the key for a stack, as text rather than a floating box ───── */
function legend(segments) {
  return `<div class="c-legend">` + segments.filter((s) => s.value)
    .map((s) => `<span><i class="${esc(s.tone || "idle")}"></i>`
      + `${esc(s.label)} <b>${esc(s.value)}</b></span>`).join("") + `</div>`;
}

/* ── dots: one mark per thing, coloured by state ─────────────────────────
   A waffle. Reads as a count AND a proportion at the same time, which is
   what "how much of the estate is live" actually asks.                    */
function dots(items, { label = "" } = {}) {
  return `<div class="c-dots" role="img" aria-label="${esc(label)}">`
    + items.map((i) => `<i class="${esc(i.tone || "idle")}" title="${esc(i.label)}"></i>`)
      .join("") + `</div>`;
}

/* ── cadence: small multiples of a timeline, one lane per platform ───────
   rows: [{ label, marks: [{ at, size, title, tone }] }] over `days` back from
   today. This is the shape a posting PROGRAMME actually needs — not how many
   posts there were, but whether they kept coming, and where the gaps are.
   Position on a common time axis, which is the most accurately read encoding
   there is; size carries engagement, which is the least, and deliberately so. */
function cadence(rows, { days = 30, label = "" } = {}) {
  const now = Date.now(), span = days * 864e5;
  const x = (t) => Math.max(0, Math.min(100, ((t - (now - span)) / span) * 100));
  const ticks = [days, Math.round(days / 2), 0]
    .map((d) => `<span style="left:${(100 - (d / days) * 100).toFixed(1)}%">`
      + `${d === 0 ? "today" : d + "d"}</span>`).join("");
  return `<div class="c-cadence" role="img" aria-label="${esc(label)}">`
    + rows.map((r) => `<div class="c-lane"><span class="c-lane-l">${esc(r.label)}</span>`
      + `<span class="c-lane-t">`
      + r.marks.map((m) => {
        const t = Date.parse(m.at);
        if (Number.isNaN(t) || t < now - span) return "";
        const s2 = Math.max(7, Math.min(15, 7 + (m.size || 0)));
        return `<i class="${esc(m.tone || "measure")}" title="${esc(m.title)}"`
          + ` style="left:${x(t).toFixed(2)}%;width:${s2}px;height:${s2}px"></i>`;
      }).join("")
      + `</span></div>`).join("")
    + `<div class="c-axis"><span class="c-lane-l"></span><span>${ticks}</span></div></div>`;
}


/* ── runChart: a series with its own control limits ──────────────────────
   The single most useful shape for "is this normal?". A line alone invites
   you to read every wiggle as news; a mean and ±2σ band says which points are
   SIGNAL. Statistical process control, applied to a product metric — the
   dashboard's job is not to show you 31 numbers, it is to tell you which of
   them you should look at.
   Points outside the band are drawn as filled marks and counted. */
function runChart(vals, { label = "", w = 260, h = 78, sigma = 2 } = {}) {
  const pts = vals.map((v, i) => [i, typeof v === "number" ? v : null])
    .filter(([, v]) => v !== null);
  if (pts.length < 4) return spark(vals, { label, w, h: Math.min(h, 46) });
  const nums = pts.map(([, v]) => v);
  const mean = nums.reduce((a, b) => a + b, 0) / nums.length;
  const sd = Math.sqrt(nums.reduce((a, b) => a + (b - mean) ** 2, 0) / nums.length) || 1;
  const hi = mean + sigma * sd, lo = Math.max(0, mean - sigma * sd);
  const top = Math.max(...nums, hi), bot = Math.min(...nums, lo);
  const span = (top - bot) || 1, pad = 4;
  const X = (i) => pad + (i / Math.max(1, vals.length - 1)) * (w - pad * 2);
  const Y = (v) => h - pad - ((v - bot) / span) * (h - pad * 2);
  const line = pts.map(([i, v]) => `${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ");
  const out = pts.filter(([, v]) => v > hi || v < lo);
  return `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"`
    + ` class="c-run" role="img" aria-label="${esc(label)}">`
    + `<rect class="band" x="0" y="${Y(hi).toFixed(1)}" width="${w}"`
    + ` height="${Math.max(0.5, Y(lo) - Y(hi)).toFixed(1)}"/>`
    + `<line class="mean" x1="0" x2="${w}" y1="${Y(mean).toFixed(1)}" y2="${Y(mean).toFixed(1)}"/>`
    + `<polyline class="line" points="${line}"/>`
    + out.map(([i, v]) => `<circle class="out" cx="${X(i).toFixed(1)}"`
        + ` cy="${Y(v).toFixed(1)}" r="3"><title>${v} — outside ${sigma}σ</title></circle>`).join("")
    + `</svg>`;
}

/* ── calendarHeat: activity by day, so gaps are visible ──────────────────
   A posting programme's real question is "did they keep coming", and a total
   cannot answer it. days: [{ date: "YYYY-MM-DD", value }] */
function calendarHeat(days, { label = "", weeks = 8 } = {}) {
  if (!days.length) return "";
  const by = new Map(days.map((d) => [d.date, d.value]));
  const max = Math.max(1, ...days.map((d) => d.value || 0));
  const end = new Date(days[days.length - 1].date + "T00:00:00Z");
  const cells = [];
  for (let i = weeks * 7 - 1; i >= 0; i--) {
    const d = new Date(end); d.setUTCDate(d.getUTCDate() - i);
    const k = d.toISOString().slice(0, 10);
    const v = by.get(k) || 0;
    const lvl = v === 0 ? 0 : Math.min(4, Math.ceil((v / max) * 4));
    cells.push(`<i class="l${lvl}" title="${k}: ${v}"></i>`);
  }
  return `<div class="c-cal" role="img" aria-label="${esc(label)}">${cells.join("")}</div>`;
}

/* ── dotPlot: many categories, ranked, without a wall of bars ────────────
   Cleveland's dot plot. At a dozen categories a bar chart spends most of its
   ink on the bars' shared origin; a dot plot spends it on the position, which
   is the thing being read. */
function dotPlot(rows, { label = "", max = null } = {}) {
  const top = max ?? Math.max(1, ...rows.map((r) => Number(r.value) || 0));
  return `<div class="c-dot" role="img" aria-label="${esc(label)}">`
    + rows.map((r) => {
      const v = Number(r.value) || 0;
      return `<div class="c-dot-r"><span class="c-dot-l">${esc(r.label)}</span>`
        + `<span class="c-dot-t"><i style="left:${((v / top) * 100).toFixed(1)}%"`
        + ` class="${esc(r.tone || "measure")}"></i></span>`
        + `<span class="c-dot-v">${esc(r.display ?? v.toLocaleString())}</span></div>`;
    }).join("") + `</div>`;
}

/* ── pareto: what to fix first ───────────────────────────────────────────
   Bars descending with a cumulative line. It answers "how much of the problem
   do the top three account for", which is the only question worth asking of a
   crash list. */
function pareto(rows, { label = "" } = {}) {
  const sorted = [...rows].sort((a, b) => (b.value || 0) - (a.value || 0));
  const total = sorted.reduce((a, b) => a + (b.value || 0), 0) || 1;
  let run = 0;
  const w = 240, h = 70, pad = 3;
  const bw = (w - pad * 2) / Math.max(1, sorted.length);
  const max = Math.max(1, ...sorted.map((r) => r.value || 0));
  const bars = sorted.map((r, i) => {
    const bh = ((r.value || 0) / max) * (h - pad * 2);
    return `<rect class="${esc(r.tone || "measure")}" x="${(pad + i * bw + 1).toFixed(1)}"`
      + ` y="${(h - pad - bh).toFixed(1)}" width="${Math.max(1, bw - 2).toFixed(1)}"`
      + ` height="${bh.toFixed(1)}"><title>${esc(r.label)}: ${r.value}</title></rect>`;
  }).join("");
  const line = sorted.map((r, i) => {
    run += r.value || 0;
    return `${(pad + i * bw + bw / 2).toFixed(1)},${(h - pad - (run / total) * (h - pad * 2)).toFixed(1)}`;
  }).join(" ");
  return `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"`
    + ` class="c-pareto" role="img" aria-label="${esc(label)}">${bars}`
    + `<polyline class="cum" points="${line}"/></svg>`;
}

/* ── timeChart: a DATED series, readable point by point ──────────────────
   The drawer's chart and the one every drill-down leads with. A spark answers
   "which way"; this answers "on which day, and how many". So it carries what a
   spark deliberately leaves off: the first and last dates under the axis, the
   top of the scale, and a crosshair that reads out the date and every series'
   value on hover, on focus, and with the arrow keys (interact() below).

   series  [{ label, points: [{ date: "YYYY-MM-DD", v }] }] — one to three.
           Two lines are told apart by weight and dash, never by a hue: colour
           on this page means STATE.
   from/to a shared calendar, so a row of these compares shapes day for day;
           a series that ends before `to` has the rest of the calendar greyed,
           which is how a stalled reader looks different from a quiet week.
   band    the first series' mean and ±2σ (a run chart); the figure also
           carries the class `c-run` so the older run-chart styling applies.
   Dates are CALENDAR days, labeled as they are written; they are never
   shifted through a time zone. */
const DAY = 864e5;
const dnum = (s) => Date.parse(String(s).slice(0, 10) + "T00:00:00Z");
const dstr = (t) => new Date(t).toISOString().slice(0, 10);
const dayFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
const dayFmtY = new Intl.DateTimeFormat("en-US",
  { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });
const dayLabel = (s, year = false) => {
  const t = dnum(s);
  return Number.isNaN(t) ? String(s || "") : (year ? dayFmtY : dayFmt).format(new Date(t));
};
const numFmt = (v) => (typeof v === "number")
  ? v.toLocaleString("en-US", { maximumFractionDigits: Math.abs(v) < 10 ? 2 : 1 }) : "no reading";

function timeChart(series, { label = "", from = null, to = null, w = 600, h = 120,
                             max = null, min = null, band = false, unit = "",
                             mini = false } = {}) {
  const ss = (series || []).filter((s) => (s.points || []).some((p) => typeof p.v === "number"));
  if (!ss.length) return "";
  const dates = ss.flatMap((s) => s.points.map((p) => String(p.date).slice(0, 10)));
  const start = from || dates.reduce((a, b) => (b < a ? b : a));
  const end = to || dates.reduce((a, b) => (b > a ? b : a));
  const dl = [];
  for (let t = dnum(start); t <= dnum(end); t += DAY) dl.push(dstr(t));
  const n = dl.length;
  if (n < 2) return "";
  const at = new Map(dl.map((d, i) => [d, i]));
  const vals = ss.map((s) => {
    const a = new Array(n).fill(null);
    s.points.forEach((p) => {
      const i = at.get(String(p.date).slice(0, 10));
      if (i != null && typeof p.v === "number") a[i] = p.v;
    });
    return a;
  });
  const nums = vals.flat().filter((v) => v != null);
  if (nums.length < 2) return "";
  let lo = min != null ? min : Math.min(0, ...nums);
  let hi = max != null ? max : Math.max(...nums);
  let mean = null, bHi = null, bLo = null;
  const first = vals[0].filter((v) => v != null);
  if (band && first.length >= 4) {
    mean = first.reduce((a, b) => a + b, 0) / first.length;
    const sd = Math.sqrt(first.reduce((a, b) => a + (b - mean) ** 2, 0) / first.length);
    bHi = mean + 2 * sd; bLo = Math.max(lo, mean - 2 * sd);
    hi = Math.max(hi, bHi);
  }
  if (hi === lo) hi = lo + 1;
  const pad = 6;
  const X = (i) => (i / (n - 1)) * w;
  const Y = (v) => h - pad - ((v - lo) / (hi - lo)) * (h - pad * 2);
  const f1 = (x) => x.toFixed(1);
  let svg = "";
  // Days the primary series does not cover, greyed: before it began, after it stopped.
  const idx = vals[0].map((v, i) => (v == null ? -1 : i)).filter((i) => i >= 0);
  if (idx.length && idx[0] > 0) {
    svg += `<rect class="gap" x="0" y="0" width="${f1(X(idx[0]))}" height="${h}"/>`;
  }
  if (idx.length && idx[idx.length - 1] < n - 1) {
    const x0 = X(idx[idx.length - 1]);
    svg += `<rect class="gap" x="${f1(x0)}" y="0" width="${f1(w - x0)}" height="${h}"/>`;
  }
  if (mean != null) {
    svg += `<rect class="band" x="0" y="${f1(Y(bHi))}" width="${w}"`
      + ` height="${f1(Math.max(0.5, Y(bLo) - Y(bHi)))}"/>`
      + `<line class="mean" x1="0" x2="${w}" y1="${f1(Y(mean))}" y2="${f1(Y(mean))}"/>`;
  }
  svg += `<line class="base" x1="0" x2="${w}" y1="${f1(Y(lo))}" y2="${f1(Y(lo))}"/>`;
  vals.forEach((a, s) => {
    let d = "", pen = false;
    a.forEach((v, i) => {
      if (v == null) { pen = false; return; }
      d += `${pen ? "L" : "M"}${f1(X(i))},${f1(Y(v))}`;
      pen = true;
    });
    // A lone reading between gaps has no segment to draw, so it gets a dot.
    a.forEach((v, i) => {
      if (v != null && a[i - 1] == null && a[i + 1] == null) {
        svg += `<line class="pt s${s}" x1="${f1(X(i))}" x2="${f1(X(i))}"`
          + ` y1="${f1(Y(v))}" y2="${f1(Y(v))}"/>`;
      }
    });
    svg += `<path class="ln s${s}" d="${d}"/>`;
    const li = a.map((v, i) => (v == null ? -1 : i)).filter((i) => i >= 0).pop();
    if (li != null && s === 0) {
      svg += `<line class="pt last" x1="${f1(X(li))}" x2="${f1(X(li))}"`
        + ` y1="${f1(Y(a[li]))}" y2="${f1(Y(a[li]))}"/>`;
    }
  });
  if (mean != null) {
    vals[0].forEach((v, i) => {
      if (v != null && (v > bHi || v < bLo)) {
        svg += `<line class="pt out" x1="${f1(X(i))}" x2="${f1(X(i))}"`
          + ` y1="${f1(Y(v))}" y2="${f1(Y(v))}"/>`;
      }
    });
  }
  svg += `<line class="hair" x1="0" x2="0" y1="0" y2="${h}" visibility="hidden"/>`;
  svg += ss.map((_, s) => `<line class="pt hov s${s}" x1="0" x2="0" y1="0" y2="0"`
    + ` visibility="hidden"/>`).join("");
  const lastV = [...vals[0]].reverse().find((v) => v != null);
  const summary = `${label}: ${dayLabel(start, true)} to ${dayLabel(end, true)}, `
    + `latest ${numFmt(lastV)}${unit}`;
  const data = JSON.stringify({ d: dl, v: vals, l: ss.map((s) => s.label || ""), u: unit,
                                lo, hi, w, h, p: pad });
  const key = !mini && ss.length > 1
    ? `<div class="c-time-k">${ss.map((s, i) => `<span class="s${i}"><i></i>${esc(s.label)}</span>`).join("")}</div>`
    : "";
  return `<figure class="c-time${band ? " c-run" : ""}${mini ? " mini" : ""}" tabindex="0"`
    + ` role="group" aria-label="${esc(summary)}" data-c="${esc(data)}">`
    + key
    + `<div class="c-time-p">`
    + (mini ? "" : `<span class="c-time-y">${esc(numFmt(hi))}${esc(unit)}</span>`)
    + `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true">`
    + svg + `</svg><output class="c-tip" hidden></output></div>`
    + (mini ? "" : `<div class="c-time-x"><span>${esc(dayLabel(start))}</span>`
      + `<span>${esc(dayLabel(end))}</span></div>`)
    + `</figure>`;
}

/* ── spans: when each thing was seen, on one calendar ────────────────────
   rows: [{ label, from: "YYYY-MM-DD", to }] — a version timeline. Position on
   a shared date axis; a one-day span is still drawn, as a short mark. */
function spans(rows, { label = "" } = {}) {
  const ok = (rows || []).filter((r) => r.from && r.to);
  if (!ok.length) return "";
  const lo = ok.reduce((a, r) => (r.from < a ? r.from : a), ok[0].from);
  const hi = ok.reduce((a, r) => (r.to > a ? r.to : a), ok[0].to);
  const span = Math.max(1, (dnum(hi) - dnum(lo)) / DAY + 1);
  const X = (d) => ((dnum(d) - dnum(lo)) / DAY / span) * 100;
  return `<div class="c-spans" role="img" aria-label="${esc(label)}">`
    + ok.map((r) => `<div class="c-lane"><span class="c-lane-l">${esc(r.label)}</span>`
      + `<svg ${SVGNS} viewBox="0 0 100 10" preserveAspectRatio="none" aria-hidden="true">`
      + `<line class="rule" x1="0" x2="100" y1="5" y2="5"/>`
      + `<rect class="span" x="${X(r.from).toFixed(2)}" y="1" height="8"`
      + ` width="${Math.max(0.8, X(r.to) - X(r.from) + 100 / span).toFixed(2)}">`
      + `<title>${esc(r.label)}: ${esc(dayLabel(r.from, true))} – ${esc(dayLabel(r.to, true))}</title></rect>`
      + `</svg></div>`).join("")
    + `<div class="c-axis"><span class="c-lane-l"></span><span class="c-axis-ends">`
    + `<b>${esc(dayLabel(lo))}</b><b>${esc(dayLabel(hi))}</b></span></div></div>`;
}

/* ── interact: hover, focus and arrow keys for every timeChart on the page ──
   One set of delegated listeners, so a chart drawn into a drawer an hour from
   now is live without anyone remembering to wire it. The tooltip's horizontal
   position is the one computed length this kit writes at runtime, and it goes
   through a custom property (--x) rather than a style declaration. */
function interact(doc) {
  if (!doc || !doc.addEventListener) return;
  const parsed = new WeakMap();
  const info = (fig) => {
    if (!parsed.has(fig)) {
      try { parsed.set(fig, JSON.parse(fig.dataset.c)); } catch { parsed.set(fig, null); }
    }
    return parsed.get(fig);
  };
  let current = null;
  const hide = (fig) => {
    if (!fig) return;
    fig.querySelectorAll(".hair, .hov").forEach((l) => l.setAttribute("visibility", "hidden"));
    const tip = fig.querySelector(".c-tip");
    if (tip) tip.hidden = true;
    if (current === fig) current = null;
  };
  const point = (fig, i) => {
    const c = info(fig);
    if (!c) return;
    const n = c.d.length;
    i = Math.max(0, Math.min(n - 1, i));
    fig.dataset.i = String(i);
    const x = (i / (n - 1)) * c.w;
    const Y = (v) => c.h - c.p - ((v - c.lo) / (c.hi - c.lo)) * (c.h - c.p * 2);
    const hair = fig.querySelector(".hair");
    if (hair) { hair.setAttribute("x1", x); hair.setAttribute("x2", x); hair.setAttribute("visibility", "visible"); }
    fig.querySelectorAll(".hov").forEach((l, s) => {
      const v = c.v[s] ? c.v[s][i] : null;
      if (v == null) { l.setAttribute("visibility", "hidden"); return; }
      ["x1", "x2"].forEach((a) => l.setAttribute(a, x));
      ["y1", "y2"].forEach((a) => l.setAttribute(a, Y(v)));
      l.setAttribute("visibility", "visible");
    });
    const tip = fig.querySelector(".c-tip");
    if (tip) {
      const vals = c.v.map((a, s) => `${c.l[s] && c.v.length > 1 ? c.l[s] + " " : ""}`
        + `${numFmt(a[i])}${a[i] != null ? c.u : ""}`);
      tip.textContent = `${dayLabel(c.d[i], true)} · ${vals.join(" · ")}`;
      tip.hidden = false;
      tip.style.setProperty("--x", `${((i / (n - 1)) * 100).toFixed(2)}%`);
      tip.classList.toggle("flip", i > (n - 1) / 2);
    }
    if (current && current !== fig) hide(current);
    current = fig;
  };
  doc.addEventListener("pointermove", (e) => {
    const fig = e.target && e.target.closest ? e.target.closest(".c-time") : null;
    if (!fig) { if (current && doc.activeElement !== current) hide(current); return; }
    const c = info(fig), svg = fig.querySelector("svg");
    if (!c || !svg) return;
    const r = svg.getBoundingClientRect();
    if (!r.width) return;
    point(fig, Math.round(((e.clientX - r.left) / r.width) * (c.d.length - 1)));
  });
  doc.addEventListener("keydown", (e) => {
    const fig = e.target && e.target.closest ? e.target.closest(".c-time") : null;
    if (!fig) return;
    const c = info(fig);
    if (!c) return;
    const i = Number(fig.dataset.i ?? c.d.length - 1);
    const to = { ArrowLeft: i - 1, ArrowRight: i + 1, Home: 0, End: c.d.length - 1 }[e.key];
    if (to == null) return;
    e.preventDefault();
    point(fig, to);
  });
  doc.addEventListener("focusin", (e) => {
    const fig = e.target && e.target.classList && e.target.classList.contains("c-time") ? e.target : null;
    if (fig) { const c = info(fig); if (c) point(fig, Number(fig.dataset.i ?? c.d.length - 1)); }
  });
  doc.addEventListener("focusout", (e) => {
    if (e.target && e.target.classList && e.target.classList.contains("c-time")) hide(e.target);
  });
}

/* ── ratio: a number said as a proportion, with the bar under it ───────── */
function ratio(part, whole, { label = "", tone = "measure" } = {}) {
  const pct = whole ? (part / whole) * 100 : 0;
  return `<div class="c-ratio" role="img" aria-label="${esc(label)}">`
    + `<div class="c-ratio-t"><i class="${esc(tone)}" style="width:${pct.toFixed(1)}%"></i></div>`
    + `<div class="c-ratio-v">${part.toLocaleString()}<small> of ${whole.toLocaleString()}`
    + ` · ${pct.toFixed(pct < 10 ? 1 : 0)}%</small></div></div>`;
}

return { bullet, bars, spark, stack, legend, dots, ratio, cadence,
         runChart, calendarHeat, dotPlot, pareto, timeChart, spans, interact, dayLabel };
})();
